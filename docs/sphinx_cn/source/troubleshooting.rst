:orphan:

故障排查
==========================================================================================

本附录把 Phase 1–5 工业化整改期间真实碰到过的 **平台坑** 整理成可检索
的故障排查手册。所有条目都有 **症状 → 根因 → 解决方法** 三段，并尽量
给出对应 commit 哈希便于回溯。

阅读建议：先按 **症状分组** 定位你看到的错误信息，再读对应根因。
若新坑出现，请按相同三段格式追加（必要时同步 :term:`CONTEXT.md` ）。

.. contents:: 故障分组
   :local:
   :depth: 2


故障分组速查
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 22 78

   * - 类别
     - 第一线索
   * - 编译报错
     - VCS / GCC / DPI 链接错误信息
   * - 仿真启动失败
     - VCS 启动 banner 后立刻退出，未到 ``run_test``
   * - 仿真跑了但 fail
     - UVM 报告含 ERROR / FATAL，或 mailbox FAIL
   * - Collector 误判
     - ``check_logs.py`` 报失败，但实际 UVM Summary 显示通过
   * - cosim mismatch
     - Spike 与 RTL 比对不一致：PC / 写回 / 内存
   * - 长时间挂起
     - 跑到 timeout，没有 PASS / FAIL 信号


编译报错
------------------------------------------------------------------------------------------

GCC 11.1 不支持 Zbc/Zbs
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   error: Error: invalid CPU/architecture rv32imac_zba_zbb_zbc_zbs

**根因** ：

* ``$GCC_PREFIX`` 指向 ``/home/host/gcc-riscv64-unknown-elf`` ，
  这是 GCC 11.1 工具链。
* GCC 11.1 仅支持 Zba/Zbb；Zbc/Zbs 在 12.x 之后才合入。
* DUT 默认 profile 把 4 个 bitmanip 都打开了，但工具链跟不上。

**解决方法** ：

* ``env.sh`` 中 ``$ABI`` 的 ``-march`` 上限设为 ``rv32imac_zba_zbb`` 。
  这是 **GCC 工具链限制** ，不是 DUT 限制。
* DUT 自身 RTL ``BITMANIP_ZBC=1`` / ``BITMANIP_ZBS=1`` 仍可保留——
  只是无法生成对应汇编。

链接缺 ``libcosim.so`` → ``DPI-DIFNF``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   Error-[DPI-DIFNF] DPI Function Implementation Not Found
       chandle riscv_cosim_init(...)

**根因** ：

* ``dv/cosim/`` 下的 C++ 桥未编译，``build/libcosim.so`` 不存在。
* VCS / Xcelium 在 elaboration 时通过 ``-sv_lib`` 链入此 ``.so`` ，
  缺失则 DPI 符号未定义。
* 历史上 ``compile_vcs`` 对 ``libcosim.so`` 缺失 **静默通过** ，
  到 run 阶段才爆炸。

**解决方法** ：

* 显式构建：``make cosim`` 。
* escape hatch：``make NO_COSIM=1 ...`` —— 明示不需要 cosim 的场景。
* Phase 1 已把 ``compile_vcs`` 改为硬依赖， :term:`libcosim.so` 缺失
  立刻报错。修复在 commit ``b245f7c`` （详见 ADR 0001）。


仿真启动失败
------------------------------------------------------------------------------------------

VCS banner 与 UVM Summary 重叠，被误判为 UVM_FATAL
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   [check_logs] FAIL: detected UVM_FATAL in <test>.log

但人工查看 log 末尾的 ``UVM Report Summary`` **明明 0 fatal 0 error** 。

**根因** ：

* VCS 退出时打印 ``Verdi`` / VCS banner 与 UVM Report Summary **同周期**
  写到同一个 fd，造成行被截断、损坏，看起来像两段交叉。
* ``check_logs.py`` 旧版 regex 把损坏后的 summary 行误识别为 UVM_FATAL
  报告头。

**解决方法** ：

* Phase 1 在 ``scripts/check_logs.py`` 引入 ``UVM_SUMMARY_LINE_RE`` ，
  识别 summary 行的两种损坏形态（前后段混入）并跳过。
* 修复在 commit ``b245f7c`` 。
* 如果你看到新的 banner overlap 形态，应在 ``UVM_SUMMARY_LINE_RE``
  里增加分支，而不是放宽 ``UVM_FATAL`` 检测。

testlist 错名 stream class
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   UVM_FATAL @ 0: ... Cannot create instr stream <name>

**根因** ：

* ``directed_testlist.yaml`` 或 ``cosim_testlist.yaml`` 中
  ``gen_opts`` 引用了一个 :term:`stream class` 名字，但 riscv-dv
  里实际不存在该类。
* 历史上 ``mul_div_test`` 写了已重命名的 stream，``branch`` 测试也踩过。

**解决方法** ：

* 用 ``grep -rn "class riscv_..._stream" vendor/google_riscv-dv/`` 核对
  类名是否存在。
* 优先使用 ``dist_control_mode`` + 内置类，避免引用不存在的 stream。
* ``mul_div_test`` 的修复在 commit ``6302009`` 。

directed stream ``gen_instr`` 不被调用 → null 引用
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   UVM_FATAL: Null object access at riscv_directed_instr_lib.sv:33

**根因** ：

* riscv-dv ``riscv_directed_instr_stream`` 默认在 ``post_randomize``
  里调 ``gen_instr`` 。
* EH2 自有 8 个 directed stream **错把逻辑放在 ``randomize`` 钩子** ，
  导致 ``instr_list`` 为空，后续解引用空指针。

**解决方法** ：

* Phase 3 新增 ``eh2_base_directed_stream`` 作为统一基类，把
  ``post_randomize`` → ``gen_instr`` 桥接好。
* 8 个子类全部改为继承新基类。
* 修复在 commit ``ab4b3ca`` 。

汇编立即数缺失：``addi rN,rN,``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   Error: invalid value `addi rN,rN,'

**根因** ：

* riscv-dv 在生成 directed stream 时，**imm_str** 字段没填，模板拼接出
  缺立即数的非法汇编。
* 通常和上一条 ``post_randomize`` 错位是同一个根因。

**解决方法** ：

* 同上：用 ``eh2_base_directed_stream`` 修正生命周期，
  ``imm_str`` 在 ``post_randomize`` 内由 :term:`riscv-dv` 填好。


仿真跑了但 fail
------------------------------------------------------------------------------------------

mailbox FAIL（``0xD058_0000`` 写入 ``0x01`` ）
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* tb_top 报告 ``MAILBOX FAIL`` ，仿真主动结束。

**根因** ：

* DUT 软件侧主动写 FAIL，通常是 self-check 内嵌断言失败。

**解决方法** ：

1. 翻看 hex 反汇编（``scripts/objdump.sh <test>`` ），定位写
   ``0xD058_0000`` 的指令。
2. 沿调用栈倒推哪段 self-check 设置了失败标志。
3. 若是 directed test，直接读对应 ``.S`` 源；若是 random test，看
   ``out/<test>/asm_test_*.S`` 。

cycle timeout 100 k 不够
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   UVM_FATAL: simulation reached max cycles 100000

**根因** ：

* ``base_test`` 默认 :term:`max_cycles` 为 100,000。
* bitmanip 测试、复杂 random、长 NB-load 序列经常超过此上限。

**解决方法** ：

* 命令行覆盖：``+max_cycles=500000`` （或更大）。
* testlist 中长用例可在 ``sim_opts`` 里固化。
* **不要** 在 ``base_test`` 里调高默认值——会掩盖真正卡死的测试。

``random_instr_test`` mailbox PASS 但仿真不退出
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* mailbox 写入 ``0xFF`` （PASS）。
* 仿真不停，CPU 在 ``c.j 0`` 自跳，等中断完成。
* 最终撞 cycle timeout。

**根因** ：

* riscv-dv 默认末尾用 ``c.j 0`` 自跳并 ``+enable_irq_seq`` 。
* cosim 还未实现中断的 :term:`Spike DPI` 路径，scoreboard 不知道何时
  允许结束。

**解决方法（短期）** ：

* commit ``ea81409`` 移除 ``+enable_irq_seq`` 。
* 把该 test 标 ``skip_in_signoff: true``——RTL/binary 层 hang，不算
  cosim 问题，但也不能阻塞 sign-off。

**解决方法（长期）** ：

* issue ``cosim-correctness/05-interrupt-cosim-test.md`` 跟踪。
* 需要扩展 scoreboard 处理 mcause/mepc/mtval。

``+enable_irq_seq`` 引发死循环
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* 与上一条相关：开 ``+enable_irq_seq`` 后 binary 必死循环等中断，
  即使 cosim 关掉也跑不完。

**解决方法** ：

* 默认关闭 ``+enable_irq_seq`` 。
* 真要测中断激励，请用 ``eh2_irq_agent`` + 专门的 IRQ test，而不是
  riscv-dv 的 plusarg。


Collector 误判
------------------------------------------------------------------------------------------

testlist description 含双引号 → wrapper.mk 失败
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* ``make run TEST=...`` 在命令拼接阶段失败，错误指向 ``wrapper.mk`` 。
* shell 报 unmatched quote 或 syntax error。

**根因** ：

* testlist YAML 的 ``description`` 字段含 ``"`` ，
  ``directed_test_schema.py`` 把字符串原样塞进 ``wrapper.mk`` ，
  shell escape 链断裂。

**解决方法** ：

* 短期：修改 description 不用裸双引号。
* 长期：``wrapper.mk`` 端做 escape；目前作为独立 bug 跟踪。


cosim mismatch
------------------------------------------------------------------------------------------

Sub-byte store BE 语义不匹配
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   Spike: store mismatch at 0x...
   wstrb=0xF data=0x... (RTL) vs Spike expected wstrb=0x1

**根因** ：

* EH2 LSU 对 sub-byte store 用 wider WSTRB（read-modify-write）。
* Spike 默认严格按汇编 byte-enable，比对不过。

**解决方法** ：

* Phase 3 在 ``dv/cosim/spike_cosim.cc`` 放宽 BE 语义检查
  （记 ADR 0005）。
* 修复合入 commit ``ab4b3ca`` 。

NUM_THREADS=2 不能 cosim
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* 在 ``dual_thread`` profile 下跑 cosim → mismatch 高频出现。

**根因** ：

* :term:`Spike DPI` 当前实现只追踪一个 hart 的状态。
* EH2 双线程并发 retire 时，scoreboard 与 Spike 状态机模型对不上。

**解决方法** ：

* 标 :term:`wontfix` for now（issue
  ``cosim-correctness/10-num-threads-constraint.md`` ）。
* 默认 sign-off 用 ``NUM_THREADS=1`` profile。
* 长期：issue ``platform-industrialization/41-multi-hart-cosim.md``
  跟踪。

EH2 自定义 CSR 未注册
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

.. code-block:: text

   Spike: unknown CSR write to 0xBC0 (mscause)

**根因** ：

* EH2 有 18+ 个自定义 CSR（mscause / mrac / meivt / meipt / meicidpl /
  mhpm 等），Spike 上游不模型。

**解决方法** ：

* 当前实现：``eh2_cosim_csr_preregister.svh`` 用 ``set_csr`` **静态注册**
  28 个 CSR，把它们当 R/W reg 处理（详见 ADR）。
* 长期：issue ``cosim-correctness/08-eh2-csr-fixup-design.md`` 设计
  WARL fixup（Phase 5）。

bitmanip illegal-instr 异常率高 → cosim 速率不匹配
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* 跑含 Zba/Zbb 的随机测试，cosim 频繁 mismatch。
* DUT 在某些 corner 触发 illegal-instr 异常，:term:`Spike DPI` 与
  trace 速率脱节。

**解决方法** ：

* 标 ``cosim:disabled`` 。
* 留 RISK-10 跟踪。


长时间挂起
------------------------------------------------------------------------------------------

仿真到达 timeout 但无 mailbox 信号
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**症状** ：

* 仿真未输出 PASS / FAIL，撞 cycle timeout。
* log 末尾无 ``UVM Report Summary`` （因为 fatal 没被触发）。

**根因（按可能性排序）** ：

1. binary 自身死循环（见 ``random_instr_test`` ）。
2. interrupt seq 等中断没来。
3. 取指越界进入未初始化区域。

**调试方法** ：

* 看 ``trace_monitor`` 的 retire log（``UVM_HIGH`` 级别）—— 最近一段时间
  仍在 retire 说明 CPU 没死，是软件循环。
* 用 ``+max_cycles=`` 临时拉高，让仿真撞 mailbox FAIL，看哪条指令踩雷。
* 必要时打开 :term:`waiver` 之外的所有 UVM_INFO，逐 phase 复盘。


调试技巧
------------------------------------------------------------------------------------------

提升 UVM verbosity
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: bash

   make run TEST=<test> UVM_VERBOSITY=UVM_HIGH
   # 或单独抬某个 component
   +uvm_set_verbosity=uvm_test_top.env.cosim_agent,_ALL_,UVM_DEBUG,run

读 trace_monitor 的 commit log
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

``eh2_trace_monitor`` 在 :term:`UVM_FATAL` 之外另有自己的 retire 日志。
打开 ``UVM_HIGH`` 后会逐拍打印 i0 / i1 的 ``pc_wb`` / ``insn`` /
``rd_addr`` / ``rd_wdata`` ，是 cosim 比对最直接的现场。

VCS Verdi 看 wave
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: bash

   make run TEST=<test> WAVES=1
   verdi -ssf build/<test>/waves.fsdb &

* 关注 ``probe_intf`` 上的 ``i0_wen`` / ``i1_wen`` / ``i0_result_wb`` 。
* 关注 ``trace_intf`` 的 ``i0_valid`` / ``i1_valid`` / ``pc_wb`` 。
* AXI4 通道在 ``axi4_intf`` 上独立呈现，4 个 master 各自一组信号。

``riscv_cosim_get_error`` DPI 函数
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

cosim 比对失败时，scoreboard 调 :term:`Spike DPI` 的
``riscv_cosim_get_error`` 取错误描述字符串：

.. code-block:: systemverilog

   string err;
   if (cosim.has_error()) begin
       err = cosim.get_error();
       `uvm_error("COSIM", err)
   end

错误字符串格式参考 ``dv/cosim/spike_cosim.cc::format_error()`` 。

按 commit 回溯
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

下表列出 Phase 1–5 涉及上述坑的关键 commit，便于 ``git show`` 回溯：

.. list-table::
   :header-rows: 1
   :widths: 14 22 64

   * - Commit
     - 类型
     - 摘要
   * - ``b245f7c``
     - fix
     - 回归 collector 误判 + libcosim 静默坑
   * - ``6302009``
     - fix
     - mul_div_test 改用 dist_control_mode 替代不存在 stream
   * - ``ab4b3ca``
     - fix
     - Phase 3 directed stream + testlist 大修，cosim 9/9 PASS
   * - ``ea81409``
     - fix
     - random_instr_test 移除 +enable_irq_seq
   * - ``20d7d05``
     - feat
     - testlist ``skip_in_signoff`` 字段，full profile 32/32 PASS
   * - ``8bfd26c``
     - docs
     - 标记 Sign-off full profile PASS

更多上下文见 :doc:`references` 与 ``CONTEXT.md`` "已知 Risk" 一节。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
