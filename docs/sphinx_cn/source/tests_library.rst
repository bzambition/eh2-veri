:orphan:

测试库
==========================================================================================

EH2 UVM 测试库由三部分组成：SystemVerilog UVM test / sequence 类、
hand-written directed 汇编、riscv-dv 随机 testlist。三者最终都通过
``run_regress.py`` 进入统一的 generate / compile / simulate / check 流程。

UVM Test 类
------------------------------------------------------------------------------------------

核心文件：

* ``tests/core_eh2_base_test.sv`` ：所有 test 的基类，479 行。
* ``tests/core_eh2_test_lib.sv`` ：具体 test 类库，1886 行。
* ``tests/core_eh2_seq_lib.sv`` ：传统 sequence。
* ``tests/core_eh2_new_seq_lib.sv`` ：新式可调度 sequence。
* ``tests/core_eh2_vseq.sv`` ：virtual sequence。
* ``tests/core_eh2_test_pkg.sv`` ：package 汇总。

``core_eh2_base_test`` 负责创建 env、解析 env_cfg、设置 cosim_config、
延迟加载 binary 到 Spike、等待 mailbox 或 timeout，并在 report phase
汇总结果。

测试类族
------------------------------------------------------------------------------------------

``core_eh2_test_lib.sv`` 当前覆盖多类场景：

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 类别
     - 代表类
   * - directed / cosim
     - ``core_eh2_directed_test``、``core_eh2_cosim_test`` 。
   * - IRQ / NMI
     - ``core_eh2_irq_test``、``core_eh2_timer_irq_test``、
       ``core_eh2_soft_irq_test``、``core_eh2_nmi_test``、
       ``core_eh2_nested_irq_test`` 。
   * - debug
     - ``core_eh2_debug_test``、``core_eh2_debug_stress_test``、
       ``core_eh2_debug_step_test``、``core_eh2_debug_wfi_test`` 。
   * - ISA / uarch
     - ``core_eh2_bitmanip_test``、``core_eh2_load_store_test``,
       ``core_eh2_muldiv_test``、``core_eh2_atomic_test``,
       ``core_eh2_dual_issue_test``、``core_eh2_exception_test`` 。
   * - PMP / ePMP
     - ``core_eh2_pmp_basic_test``、``core_eh2_pmp_disable_test``,
       ``core_eh2_pmp_random_test``、``core_eh2_epmp_mml_test`` 等。
   * - integrity / reset
     - ``core_eh2_pc_intg_test``、``core_eh2_rf_intg_test``,
       ``core_eh2_reset_test`` 。
   * - combined stress
     - ``core_eh2_stress_test``、``core_eh2_irq_debug_test``、
       ``core_eh2_long_run_test`` 。

Directed 汇编
------------------------------------------------------------------------------------------

``tests/asm`` 下有四个 cosim proof 汇编：

* ``cosim_smoke.S`` ：初始化、binary load、首条 Spike step、mailbox PASS。
* ``cosim_alu.S`` ：确定性 ALU 写回关联。
* ``cosim_load_store.S`` ：LSU AXI memory notification 路径。
* ``cosim_dual_issue.S`` ：双发射 retire program order。

``directed_tests/directed_testlist.yaml`` 将其中三个作为 directed stage；
``directed_tests/cosim_testlist.yaml`` 将四个作为 cosim stage，并使用
``core_eh2_cosim_test`` 保证 Spike lockstep 打开。

riscv-dv Testlist
------------------------------------------------------------------------------------------

``riscv_dv_extension/testlist.yaml`` 是随机测试主清单。当前共有 43 个 test
entry，覆盖 25 个不同 ``rtl_test`` 类。其中 11 个带 ``skip_in_signoff`` ，
在 ``EH2_SIGNOFF_MODE=1`` 时被 full profile 扣除；34 个带 ``cosim: disabled`` ，
表示它们当前不进入 Spike lockstep。

entry 常用字段：

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - 字段
     - 说明
   * - ``test``
     - regression 中显示的测试名。
   * - ``description``
     - 测试意图。
   * - ``gen_test``
     - riscv-dv generator test 类。
   * - ``gen_opts``
     - 指令数量、boot mode、directed stream、分布控制等。
   * - ``rtl_test``
     - UVM test 类名。
   * - ``sim_opts``
     - UVM / TB plusarg，例如 ``+max_cycles``、``+enable_irq_seq`` 。
   * - ``iterations``
     - 默认 seed 数；sign-off 可通过 ``--iterations`` 覆盖。
   * - ``cosim``
     - ``enabled`` 或 ``disabled`` ；run_regress 自动补 ``+enable_cosim``
       或 ``+disable_cosim`` 。
   * - ``skip_in_signoff``
     - 仅 sign-off 模式跳过，普通 regression 仍可手动运行。

riscv-dv 扩展
------------------------------------------------------------------------------------------

``riscv_dv_extension`` 提供 EH2 定制：

* ``riscv_core_setting.sv`` ：ISA、XLEN、PMP、hart 数等配置。
* ``eh2_asm_program_gen.sv`` ：启动代码、mailbox 退出协议。
* ``eh2_directed_instr_lib.sv`` ：EH2 directed stream。
* ``eh2_debug_triggers_overrides.sv`` ：debug trigger 覆盖。
* ``csr_description.yaml`` ：CSR 描述补充。
* ``user_extension.svh`` ：SV extension include。

新增测试流程
------------------------------------------------------------------------------------------

新增 riscv-dv 测试建议步骤：

1. 在 ``testlist.yaml`` 添加 entry，先用较小 ``+instr_cnt`` 和
   ``iterations: 1`` 。
2. 选择已有 ``rtl_test`` ；只有确实需要新刺激组合时再新增 test 类。
3. 默认启用 cosim。若关闭，必须在描述或 issue 中说明原因。
4. 本地跑单测，确认生成、编译、仿真、log check 全部通过。
5. 若加入 sign-off，确认不需要 ``skip_in_signoff`` ；若必须 skip，创建
   本地 issue 并写清解锁条件。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认索引、术语、附录或兼容旧入口不会破坏整本手册构建。

.. code-block:: bash

   sphinx-build -W --keep-going -b html docs/sphinx_cn/source /tmp/eh2-doc-practice-check
   rg -n "自检 5 问|动手练习" docs/sphinx_cn/source | head -80

**进阶题**：抽查参考页是否使用当前统一平台口径。

.. code-block:: bash

   rg -n "95.05|31635/31635|line\+tgl\+assert\+fsm\+branch|NC/Incisive" docs/sphinx_cn/source | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
