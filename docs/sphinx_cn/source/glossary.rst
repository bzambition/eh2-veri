术语表
======

本附录收录 EH2 UVM 验证平台中出现的核心术语。所有条目按 **英文字母**
排序（英文缩写在前，中文释义在后），便于交叉检索。

术语来源主要为 ``CONTEXT.md``、``docs/adr/`` 与平台源码。同一术语
若在不同章节被首次引用，应通过 ``:term:`...``` 角色链接回本附录。

.. note::

   术语含义随平台演进可能更新。出现冲突时以 ``CONTEXT.md`` 当前版本为准。

.. glossary::
   :sorted:

   ADR
     Architecture Decision Record。架构决策记录。仓库内位于 ``docs/adr/``，
     5 篇决策（cosim 路径、AXI4 被动监控、NUM_THREADS 范围、RVFI 等价 trace、
     Spike store 宽度对齐）。每个决策一个 markdown 文件。

   AXI4
     ARM AMBA AXI4 总线协议。EH2 在 AXI4 配置下暴露四个 master port：IFU、
     LSU、SB（System Bus）、DMA。本平台对 AXI4 采取 **被动监控** 策略
     （ADR 0002），不做激励。

   async_wb_q
     scoreboard 内异步写回事件队列。NB-load、DIV cancel 等异步通道的
     写回事件先入此队列，再由 trace_pkt 触发匹配消费。

   base_test
     ``core_eh2_base_test`` 的简称。所有 UVM test 继承此类。默认 cycle
     timeout 100,000 cycle，可通过 ``+max_cycles=...`` 重写。

   BE
     Byte Enable。AXI4 写通道的 ``WSTRB`` 信号。EH2 sub-byte store 用
     wider WSTRB（即字节通道选择 + read-modify-write 语义）。
     Phase 3 在 ``spike_cosim.cc`` 中放宽 BE 语义检查（ADR 0005）。

   bitmanip
     RISC-V Bit-Manipulation 扩展。EH2 实现 Zba/Zbb/Zbc/Zbs 子集。GCC 11.1
     工具链 **不支持** Zbc/Zbs，因此 ``$ABI`` 上限设为 ``rv32imac_zba_zbb``。

   build
     根目录 ``build/`` 的简称，是仿真生成产物的根目录。**不入库**，
     可任意清空重建。

   check_logs
     ``scripts/check_logs.py``。扫描仿真 log 判定 :term:`UVM_FATAL` /
     ``UVM_ERROR`` 数量。Phase 1 修复了 VCS banner 与 UVM Report Summary
     重叠时的误判。

   CONTEXT.md
     仓库根目录的领域语境文档。新会话进入项目时应先读此文档。包含术语、
     架构、风险、Sign-off 状态等。

   cosim
     Co-simulation。协同仿真。把 DUT 每条 retired 指令喂给 :term:`Spike DPI`
     ISS，逐拍比对 PC、寄存器写回与内存访问。

   cosim:disabled
     testlist 上的标记，表示该 test 暂不参与 cosim 比对。当前用于
     ``random_instr_test`` （中断 cosim 未实现）、bitmanip 高 illegal-instr
     率、atomic SC.W 分歧三类用例。

   DCCM
     Data Closely Coupled Memory。EH2 数据紧耦合存储。配置 64 KB（默认 profile）。

   DIV cancel
     EH2 推测除法被 kill 后写回作废的事件。RTL 信号
     ``dec_div_cancel_overwrite`` 通知 scoreboard 从异步队列移除该写回。
     始终 slot=0。

   DPI-DIFNF
     VCS 报错码 "DPI Function Implementation Not Found"。当
     ``libcosim.so`` 缺失或未链接时出现。修复：``make cosim`` 或
     ``NO_COSIM=1`` （详见 :doc:`troubleshooting`）。

   DM
     Debug Module。EH2 自带 RISC-V 调试模块，通过 :term:`JTAG` 访问。

   DUT
     Device Under Test。本平台中即 VeeR EH2 核
     （``rtl/design/``）。在 testbench 中以 ``dut`` 实例化，通过
     ``eh2_veer_wrapper`` 包装。

   eh2_configs.yaml
     RTL 配置 profile 文件。当前定义 4 个 profile：``default`` /
     ``minimal`` / ``dual_thread`` / ``ahb_lite``。

   EH2_SIGNOFF_MODE
     Sign-off 模式编译宏。打开后 ``base_test`` 启用更严格的检查
     （cycle timeout、UVM 报告等级）。

   env.sh
     仓库根目录的 shell 环境脚本。``source env.sh`` 后导出
     ``$EH2_VERIF_ROOT`` / ``$RV_ROOT`` / ``$GCC_PREFIX`` / ``$QEMU_BIN``
     等变量。

   fcov
     Functional Coverage。功能覆盖率。主入口 ``dv/uvm/core_eh2/fcov/eh2_fcov_if.sv``
     共 797 行，通过 ``eh2_fcov_bind.sv`` bind 到 DUT。

   feature-slug
     ``.scratch/<feature-slug>/`` 的命名约定，每个 feature 一个目录，
     内含 PRD 与 ``issues/``。当前两个 feature：``platform-industrialization``、
     ``cosim-correctness``。

   GTLSIM
     Gate-Level Timing SIMulation 编译宏。开启时切换到 GLS 流程
     （目前未在 sign-off 默认 profile 启用）。

   ICache
     Instruction Cache。EH2 32 KB I-Cache（默认 profile）。可关闭。

   ICCM
     Instruction Closely Coupled Memory。EH2 指令紧耦合存储。配置 64 KB（默认 profile）。

   IFU
     Instruction Fetch Unit。EH2 取指单元。AXI4 master port 之一。

   issue tracker
     本仓库的本地 markdown issue 体系。每个 issue 一个 ``.md`` 文件，
     位于 ``.scratch/<feature>/issues/NN-<title>.md``。详见 :doc:`issue_tracker`。

   JTAG
     Joint Test Action Group。IEEE 1149.1 调试端口。EH2 通过 JTAG 接 :term:`DM`。
     平台用 ``eh2_jtag_agent`` 主动激励。

   libcosim.so
     ``dv/cosim/`` 编译产物，VCS / Xcelium 在 elaboration 时通过 ``-sv_lib``
     链入。**缺失时报 :term:`DPI-DIFNF`**。

   LSU
     Load/Store Unit。EH2 访存单元。AXI4 master port 之一，是 :term:`NB-load`
     与 :term:`BE` 语义的源头。

   mailbox
     ``0xD058_0000`` 地址。运行时 PASS/FAIL 信号通道：``0xFF`` = PASS，
     ``0x01`` = FAIL，其它字符 = 控制台输出。tb_top 监听此地址决定
     测试结束。

   max_cycles
     UVM plusarg。``+max_cycles=N`` 覆盖 base_test 默认的 100 k cycle
     timeout。bitmanip / 复杂随机用例通常需要 500 k 以上。

   mhpm
     Machine Hardware Performance Monitor 一组 CSR（``mhpmcounter*`` /
     ``mhpmevent*``）。EH2 实现需 fixup 才能与 Spike 对齐。

   meipt / meivt / meicidpl
     EH2 自定义中断 CSR。``meivt`` = External Interrupt Vector Table，
     ``meipt`` = External Interrupt Priority Threshold，
     ``meicidpl`` = External Interrupt Current Driving Priority Level。
     Spike 不原生支持，由 ``eh2_cosim_csr_preregister.svh`` 静态注册。

   mrac
     Memory Region Access Control。EH2 自定义 CSR，控制 16 个区域的
     side-effect / cacheable 属性。

   mscause
     Machine Secondary Cause。EH2 自定义 CSR，提供 trap secondary cause。

   NB-load
     Non-Block Load。非阻塞 load。指令已 :term:`retire`，但写回 **晚于**
     指令本身到达（异步通道）。scoreboard 通过等 ``nb_load_hint`` 关联。

   needs-info
     :term:`triage` 角色之一：等待 reporter 补信息。

   needs-triage
     :term:`triage` 角色之一：默认状态，等待 maintainer 评估。

   NO_COSIM
     Make 变量。``make NO_COSIM=1 ...`` 显式跳过 cosim 链接，用于
     ``libcosim.so`` 暂时不可用时的 escape hatch。

   NUM_THREADS
     EH2 硬件线程数（1 或 2）。**当前 cosim 仅支持 NUM_THREADS=1**
     （ADR 0003 + issue 41）。

   pending_trace_q
     scoreboard 内 :term:`trace pkt` 等待队列。在写回事件先到达时，
     trace_pkt 进队等候匹配。

   PIC
     Programmable Interrupt Controller。EH2 自有的可编程中断控制器，
     127 路外部中断源（默认 profile）。Spike 不模型，相关 CSR 通过
     ``set_csr`` 静态注册。

   PHASE_PROGRESS
     ``.scratch/platform-industrialization/PHASE*_PROGRESS.md`` 系列文件。
     每个 Phase 一份完整进度记录（cosim 闭环 / 结构整理 / 流程修复 / sweep）。

   probe interface
     验证用 hierarchical reference SystemVerilog 接口
     （``eh2_dut_probe_intf``）。把 DUT 内部写回信号、CSR、中断态拉给
     monitor，避免破坏 DUT 端口。

   profile (sign-off)
     Sign-off 执行预设。``quick`` / ``cosim`` / ``nightly`` / ``full``。
     默认 sign-off 跑 full，含全部 4 stage。

   profile (RTL config)
     ``eh2_configs.yaml`` 定义的 RTL 配置组合。``default`` / ``minimal``
     / ``dual_thread`` / ``ahb_lite``。

   ready-for-agent
     :term:`triage` 角色之一：完整规格、可交给 AFK agent 实现。

   ready-for-human
     :term:`triage` 角色之一：需要人工实现，agent 暂不接。

   retire
     RISC-V 微架构概念。指令进入 retire 阶段表示 commit。EH2 双发射
     可同周期 retire 两条指令（i0 + i1）。

   RV_ROOT
     环境变量。指向 EH2 RTL 源仓库 ``/home/host/Cores-VeeR-EH2``。
     由 ``env.sh`` 设置。

   RVFI
     RISC-V Formal Interface。形式化验证用的标准 retire 接口。
     EH2 RTL 不原生提供 RVFI，但 ADR 0004 在 trace pkt 中加入了
     ``rd_addr`` / ``rd_wdata`` 字段以达到 **等价** 效果。

   riscv-dv
     Google 开源的受约随机 RISC-V 指令生成器。本平台用作 vendor
     子模块（``vendor/google_riscv-dv/``），并通过 ``riscv_dv_extension/``
     做 EH2 扩展。

   riscv_cosim_get_error
     DPI 函数。从 Spike 取最近一次 cosim 比对的错误描述字符串，便于
     UVM 端打印。

   sign-off gate
     ``dv/uvm/core_eh2/scripts/signoff.py``。4 个 stage：smoke /
     directed / cosim / riscvdv，全过才算签发。当前状态：full PASS。

   skip_in_signoff
     testlist 字段。值为 ``true`` 时该 test 不计入 sign-off 统计
     （但仍然执行）。用于 RTL/binary 层 hang 不属于 cosim 问题的情形。

   slot
     双发射的指令槽位。slot=0 是 i0，slot=1 是 i1。:term:`NB-load` /
     :term:`DIV cancel` 始终 slot=0。

   smoke
     烟雾测试。最小 hello-world 用例，用 ``smoke.hex``，含 cosim，
     6 trace / 0 mismatch。Sign-off 第 1 stage。

   SoC
     System on Chip。本文档中常指 EH2 在系统中的封装层（含 PIC、
     mailbox、AXI mem 等）。

   Spike DPI
     Spike RISC-V ISS 通过 SystemVerilog DPI 暴露的接口集合。
     ``dv/cosim/spike_cosim.cc`` 实现。Spike 上游来自
     ``/home/host/spike-cosim/``。

   stream class
     riscv-dv 中的指令流类。例：``riscv_load_store_rand_instr_stream``。
     **错名直接导致 "Cannot create instr stream" 错误**——常见坑。

   testlist
     YAML 文件，定义某 stage 要跑的所有 test。位于
     ``directed_tests/directed_testlist.yaml`` /
     ``directed_tests/cosim_testlist.yaml`` 与
     ``riscv_dv_extension/testlist.yaml``。

   trace_agent
     被动 agent，从 RTL trace pkt 提取已 :term:`retire` 指令信息。
     位于 ``common/trace_agent/``。

   trace pkt
     DUT 输出的 "已退役指令" 包，含 PC + insn + exception + interrupt
     + tval。**RTL 层 i0 与 i1 同周期同时给出** （program order：i0 在前）。

   triage
     issue 分诊。本仓库定义 5 个角色：:term:`needs-triage` /
     :term:`needs-info` / :term:`ready-for-agent` / :term:`ready-for-human`
     / :term:`wontfix`。详见 ``docs/agents/triage-labels.md``。

   urg
     Synopsys VCS Unified Report Generator。覆盖率合并工具。
     在 ``COV=1`` 时由 ``merge_cov.py`` 调用。

   UVM 1.2
     Universal Verification Methodology 标准版本。本平台沿用 Synopsys
     VCS 自带的 UVM 1.2 实现。

   UVM_FATAL
     UVM 严重错误等级。:term:`check_logs` 把任何 ``UVM_FATAL`` 视为
     测试失败。Phase 1 修复了被 banner overlap 误判的情况
     （commit b245f7c）。

   vseqr
     virtual sequencer。``core_eh2_vseqr.sv``。聚合各 agent sequencer，
     virtual sequence 通过它驱动多 agent 协同行为。

   waiver
     仿真 / 覆盖率 waiver。位于 ``dv/uvm/core_eh2/waivers/``。
     用于压制已分析过、确认可忽略的告警与覆盖空洞。

   wb / writeback
     寄存器写回事件。EH2 双发射有 i0 / i1 两个写回槽（slot 0 / slot 1）。

   wb_seq
     全局写回序号。:term:`probe interface` 上的 :term:`probe monitor`
     维护并标记每次写回。

   wb_search_depth
     旧 scoreboard 的启发式搜索窗口。Phase 1 已 **删除**——属于
     :term:`band-aid`。

   probe monitor
     ``eh2_dut_probe_monitor.sv``。读 :term:`probe interface` 上的
     写回 / CSR / 中断态信号，发到 scoreboard。

   wb_source
     scoreboard 内写回事件来源枚举。三种值：``REGULAR`` / ``DIV``
     / ``NB_LOAD``。Phase 1 引入，用于显式区分异步通道。

   wontfix
     :term:`triage` 角色之一：决定不做。当前 1 个：
     ``cosim-correctness/issues/10-num-threads-constraint.md``
     （NUM_THREADS=2 cosim 限制）。

   band-aid
     工程隐喻：临时修补、不解决根因。本平台 Phase 1 删除了两处
     band-aid：``WB_SEARCH_DEPTH`` 与 ``pending_wb_q``。
