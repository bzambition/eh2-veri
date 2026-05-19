.. _vseq_library:
.. _05_verification_arch/vseq_library:

虚拟序列库 — 架构桥接说明
================================================================================

:status: draft
:source: dv/uvm/core_eh2/tests/core_eh2_vseq.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  当前源码边界
--------------------------------------------------------------------------------

当前 ``dv/uvm/core_eh2`` 下只有一个虚拟序列类：``core_eh2_vseq``；只有一个虚拟
sequencer 类：``core_eh2_vseqr``。旧文档中列出的 ``core_eh2_smoke_vseq``、
``core_eh2_directed_vseq`` 和 ``core_eh2_cosim_vseq`` 在当前源码中没有对应 class，
因此本章不再使用这些名称。

``core_eh2_vseq`` 的职责不是加载 binary、释放 reset 或初始化 Spike。binary load、
completion 和 cosim config 由 ``core_eh2_base_test`` 完成；virtual sequence 只根据
``env_cfg`` 选择是否并发启动 IRQ、debug 和 fetch-enable 子序列。

.. code-block:: text

   core_eh2_base_test.run_phase()
      |
      |-- load_binary_to_mem()
      |-- start_vseq()
      |     |
      |     v
      |  core_eh2_vseq.cfg = env_cfg
      |  core_eh2_vseq.start(env.vseqr)
      |     |
      |     v
      |  fork/join_none
      |     |-- irq_raise_single_seq      if cfg.enable_irq_single_seq
      |     |-- irq_raise_seq             if cfg.enable_irq_multiple_seq
      |     |-- irq_raise_nmi_seq         if cfg.enable_irq_nmi_seq
      |     |-- debug_seq                 if cfg.enable_debug_seq/stress/single
      |     `-- fetch_enable_seq          if cfg.enable_fetch_toggle
      |
      `-- wait_for_completion()

**逐段解释**：

* 上层 test 调用 ``start_vseq()`` 前已经创建 env 和 env_cfg，并已经把 virtual
  interface 放入 config_db。
* ``core_eh2_vseq`` 通过 ``env.vseqr`` 拿到 JTAG sequencer，通过 config_db 拿到
  ``irq_vif``，fetch-enable sequence 则依赖 ``fetch_vif``。
* ``fork/join_none`` 使 virtual sequence body 启动分支后立即返回；生命周期由 base
  test 的 completion 和 ``vseq.stop()`` 管理。
* 子序列都是 stimulus producer，不做 scoreboard compare；cosim compare 仍由
  trace/probe/AXI monitor 接入 cosim scoreboard 完成。

**接口关系**：

* **被调用**：``core_eh2_base_test.start_vseq()`` 创建并启动 ``core_eh2_vseq``。
* **调用**：``core_eh2_vseq`` 创建 IRQ、debug 和 fetch-enable sequence。
* **共享状态**：``core_eh2_env_cfg`` 的 enable 位、``core_eh2_vseqr`` 的 sequencer
  句柄，以及 tb_top 放入 config_db 的 ``irq_vif``/``fetch_vif``。

§2  上层入口
--------------------------------------------------------------------------------

§2.1  ``core_eh2_base_test.start_vseq()`` — 创建并启动唯一 vseq
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：base test 是 virtual sequence 的唯一常规入口。它创建
``core_eh2_vseq``，把 env_cfg 交给 sequence，再用 ``env.vseqr`` 启动。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L335-L342``）：

.. code-block:: systemverilog

   // =========================================================================
   // Virtual Sequence
   // =========================================================================
   virtual task start_vseq();
     vseq = core_eh2_vseq::type_id::create("vseq");
     vseq.cfg = env_cfg;
     vseq.start(env.vseqr);
   endtask

**逐段解释**：

* 第 L338-L339 行：test 通过 UVM factory 创建 ``core_eh2_vseq``，对象名固定为
  ``vseq``。
* 第 L340 行：``env_cfg`` 被写入 ``vseq.cfg``，后续 ``pre_body()`` 会检查它非空，
  ``body()`` 会读取其中的 enable 位和 ``max_interval``。
* 第 L341 行：``vseq.start(env.vseqr)`` 把 env 创建的 virtual sequencer 作为
  ``m_sequencer`` 传给 sequence。

**接口关系**：

* **被调用**：base ``run_phase``、多个派生 test ``run_phase`` 和 integrity
  ``main_phase`` 调用。
* **调用**：调用 ``core_eh2_vseq::type_id::create`` 和 ``vseq.start``。
* **共享状态**：读取 ``env_cfg`` 和 ``env.vseqr``，写入 test 对象成员 ``vseq``。

§2.2  ``core_eh2_env`` — 创建并接线 virtual sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：env 创建 ``core_eh2_vseqr``，并在 connect phase 把 active agent 的
sequencer 句柄接到 virtual sequencer。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env.sv:L60-L72``）：

.. code-block:: systemverilog

   function new(string name, uvm_component parent);
     super.new(name, parent);
     // Create cfg in constructor so it's available during child build_phase
     cfg = core_eh2_env_cfg::type_id::create("cfg");
   endfunction
   
   function void build_phase(uvm_phase phase);
     super.build_phase(phase);
     `uvm_info("env", cfg.convert2string(), UVM_LOW)
   
     // Virtual sequencer
     vseqr = core_eh2_vseqr::type_id::create("vseqr", this);

**逐段解释**：

* 第 L60-L64 行：env constructor 创建 ``core_eh2_env_cfg``，使 base test build phase
  可以立刻通过 ``env.cfg`` 获取配置对象。
* 第 L66-L72 行：env build phase 打印配置，并创建 ``core_eh2_vseqr``。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L173``）：

.. code-block:: systemverilog

   // Wire sub-sequencers to virtual sequencer
   vseqr.irq_seqr      = irq_agent.sequencer;
   vseqr.jtag_seqr     = jtag_agent.sequencer;
   vseqr.halt_run_seqr = halt_run_agt.sequencer;
   endfunction

**逐段解释**：

* 第 L169-L172 行：connect phase 把 IRQ agent、JTAG agent 和 halt/run agent 的
  sequencer 句柄写入 ``vseqr``。
* 当前 ``core_eh2_vseq`` 只直接读取 ``vseqr.jtag_seqr``；IRQ 子序列通过
  ``get_irq_vif()`` 拿 interface，而不是通过 ``vseqr.irq_seqr`` 启动。

**接口关系**：

* **被调用**：UVM env phase 调度器调用 build/connect。
* **调用**：调用 ``core_eh2_vseqr::type_id::create``。
* **共享状态**：``vseqr`` 是 test 启动 virtual sequence 的 sequencer 参数。

§2.3  ``core_eh2_vseqr`` — sequencer 句柄容器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：virtual sequencer 不产生 transaction；它只保存各 active agent 的 sequencer
句柄，供 virtual sequence 统一访问。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L20``）：

.. code-block:: systemverilog

   class core_eh2_vseqr extends uvm_sequencer;
   
     `uvm_component_utils(core_eh2_vseqr)
   
     // Sub-sequencers (use specific types for type-safe access)
     eh2_irq_sequencer              irq_seqr;
     eh2_jtag_sequencer             jtag_seqr;
     uvm_sequencer #(eh2_halt_run_seq_item) halt_run_seqr;
   
     function new(string name, uvm_component parent);
       super.new(name, parent);
     endfunction

**逐段解释**：

* 第 L7-L9 行：class 继承 ``uvm_sequencer`` 并注册 UVM component。
* 第 L12-L14 行：成员包括 IRQ sequencer、JTAG sequencer 和 halt/run sequencer。
* 第 L16-L18 行：构造函数只调用父类构造函数，没有本地创建子 sequencer。

**接口关系**：

* **被调用**：``core_eh2_env`` 创建并接线该对象；``core_eh2_vseq`` 在 pre_body 中
  cast ``m_sequencer`` 为该类型。
* **调用**：无任务调用。
* **共享状态**：``jtag_seqr`` 被 ``debug_seq`` 使用；``halt_run_seqr`` 当前在
  ``core_eh2_vseq.sv`` 中没有被直接使用。

§3  env_cfg 控制面
--------------------------------------------------------------------------------

§3.1  enable 位与 timing knob — vseq 的输入配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``core_eh2_env_cfg`` 从 plusarg 读取 sequence enable 位和 timing knob。
``core_eh2_vseq`` 只消费其中的一部分字段。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L27-L45``）：

.. code-block:: systemverilog

   // Interrupt sequences
   bit enable_irq_single_seq     = 0;  // Single interrupt per event
   bit enable_irq_multiple_seq   = 0;  // Multiple simultaneous interrupts
   bit enable_irq_nmi_seq        = 0;  // NMI stimulus
   bit enable_irq_drop_seq       = 0;  // Interrupt deassert sequence
   
   // Debug sequences
   bit enable_debug_seq          = 0;  // Debug halt/resume
   bit enable_debug_stress       = 0;  // Continuous debug requests
   bit enable_debug_single       = 0;  // Single debug pulse
   
   // Fetch enable
   bit enable_fetch_toggle       = 0;  // Random fetch-enable toggling

**逐段解释**：

* 第 L28-L31 行：IRQ 相关 enable 位包括 single、multiple、NMI 和 drop。
* 第 L34-L36 行：debug 相关 enable 位包括 general debug sequence、continuous
  stress 和 single debug pulse。
* 第 L39 行：``enable_fetch_toggle`` 控制 fetch-enable sequence。
* 第 L44-L45 行：cosim enable/disable 也在同一配置对象中，但 virtual sequence
  不直接读取 cosim 字段。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L67-L83``）：

.. code-block:: systemverilog

   // =========================================================================
   // Stimulus timing
   // =========================================================================
   int max_interval              = 500;   // Max cycles between stimulus events
   int irq_delay_min             = 100;   // Min delay before first IRQ (ns)
   int irq_delay_max             = 5000;  // Max delay before first IRQ (ns)
   int debug_delay_min           = 1000;  // Min delay before debug request (ns)
   int debug_delay_max           = 10000; // Max delay before debug request (ns)
   
   // =========================================================================
   // Test completion
   // =========================================================================
   longint timeout_ns            = 64'd1_800_000_000_000;  // Wall-clock timeout (ns) - 30 minutes
   int max_cycles                = 100_000;     // Cycle count timeout

**逐段解释**：

* 第 L69-L73 行：``max_interval`` 是 vseq 传给旧式 IRQ/debug/fetch 子序列的主要
  interval knob；``irq_delay_*`` 和 ``debug_delay_*`` 在该配置对象中存在，但
  当前 ``core_eh2_vseq.sv`` 没有直接使用这些字段。
* 第 L78-L80 行：``timeout_ns`` 和 ``max_cycles`` 由 base test completion 逻辑使用，
  不由 vseq 决定。

**接口关系**：

* **被调用**：env constructor 创建 cfg；base test 和派生 test 修改 cfg；vseq 读取 cfg。
* **调用**：该段不调用任务。
* **共享状态**：YAML ``sim_opts`` 中的 plusarg 最终写入这些字段。

§3.2  plusarg 读取与 IRQ drop 派生规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：cfg constructor 读取 plusarg，并在 ``enable_irq_single_seq`` 为 1 时自动
打开 IRQ drop sequence 标志。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L96-L136``）：

.. code-block:: systemverilog

   function new(string name = "core_eh2_env_cfg");
     super.new(name);
     // Read all plusargs
     void'($value$plusargs("enable_irq_seq=%0d", enable_irq_single_seq));
     void'($value$plusargs("enable_irq_single_seq=%0d", enable_irq_single_seq));
     void'($value$plusargs("enable_irq_multiple_seq=%0d", enable_irq_multiple_seq));
     void'($value$plusargs("enable_irq_nmi_seq=%0d", enable_irq_nmi_seq));
     void'($value$plusargs("enable_irq_drop_seq=%0d", enable_irq_drop_seq));
     void'($value$plusargs("enable_debug_seq=%0d", enable_debug_seq));
     void'($value$plusargs("enable_debug_stress=%0d", enable_debug_stress));
     void'($value$plusargs("enable_debug_single=%0d", enable_debug_single));
     void'($value$plusargs("enable_fetch_toggle=%0d", enable_fetch_toggle));

**逐段解释**：

* 第 L96-L107 行：constructor 读取 IRQ、debug 和 fetch 相关 plusarg。``+enable_irq_seq``
  和 ``+enable_irq_single_seq`` 都写入 ``enable_irq_single_seq``。
* 第 L108-L126 行：constructor 继续读取 AXI4 error、cosim、memory error、
  spurious response、double-fault、interval、timeout、binary 和 delay 相关 plusarg。
* 第 L128-L129 行：``disable_cosim`` 为 1 时强制 ``enable_cosim = 0``。
* 第 L131-L135 行：``enable_irq_single_seq`` 为 1 时，``enable_irq_drop_seq`` 被置 1；
  但当前 ``core_eh2_vseq.body()`` 没有根据 ``enable_irq_drop_seq`` 创建 ``irq_drop_h``。

**接口关系**：

* **被调用**：``core_eh2_env`` constructor 创建 cfg 时执行。
* **调用**：调用 ``$value$plusargs``。
* **共享状态**：``run_regress.py`` 合并 YAML/CLI ``sim_opts`` 后把这些 plusarg 传入仿真。

§3.3  YAML 中的 vseq plusarg 来源
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：riscv-dv 和 directed testlist 通过 ``sim_opts`` 打开 vseq 分支并调整
``max_interval``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L106-L127``）：

.. code-block:: yaml

   - test: riscv_interrupt_test
     description: Random interrupt test — cosim enabled (issue 53 interrupt cosim)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=20000 +boot_mode=m +enable_interrupt=1 +enable_nested_interrupt=1 +directed_instr_0=eh2_pic_int_stream,5
   
       '
     rtl_test: core_eh2_base_test
     sim_opts: '+enable_irq_seq=1 +max_interval=500
   
       '
     iterations: 15

**逐段解释**：

* 第 L106-L116 行：``riscv_interrupt_test`` 的 ``sim_opts`` 打开
  ``+enable_irq_seq=1``，因此 cfg 会置位 ``enable_irq_single_seq``，vseq 会启动
  ``irq_raise_single_seq``。
* 第 L117-L127 行：``riscv_irq_single_test`` 显式写
  ``+enable_irq_single_seq=1 +max_interval=200``，使 single IRQ 子序列 interval 更短。

**关键代码** （``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L227-L236``）：

.. code-block:: yaml

   - test: directed_pic_state_walk
     description: PIC CSR state walk with IRQ sequence drive
     test_srcs: tests/asm/directed_pic_state_walk.S
     rtl_test: core_eh2_base_test
     sim_opts: '+enable_irq_seq=1 +enable_irq_single_seq=1 +max_interval=20'
     iterations: 5
   
   - test: directed_dbg_dret_walk
     description: Debug DRET walk with debug sequence drive
     test_srcs: tests/asm/directed_dbg_dret_walk.S

**逐段解释**：

* 第 L227-L232 行：``directed_pic_state_walk`` 同时写 ``+enable_irq_seq=1`` 和
  ``+enable_irq_single_seq=1``，并把 ``+max_interval`` 调到 20。
* 第 L234-L236 行：``directed_dbg_dret_walk`` 的下一条目使用 debug 相关 plusarg；
  该片段显示 directed YAML 同样通过 ``sim_opts`` 控制 vseq 分支。

**接口关系**：

* **被调用**：回归脚本读取 YAML 并把 ``sim_opts`` 拼入 RTL 仿真命令。
* **调用**：YAML 不调用函数。
* **共享状态**：``sim_opts`` 到 ``core_eh2_env_cfg`` 的映射由 plusarg 读取完成。

§4  ``core_eh2_vseq`` 内部拓扑
--------------------------------------------------------------------------------

§4.1  类成员与 ``pre_body()`` — 配置和 sequencer 必须存在
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：vseq 保存 cfg、vseqr 和子序列句柄；``pre_body()`` 在启动前验证 cfg 非空，
并确保 ``m_sequencer`` 可以转换为 ``core_eh2_vseqr``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L17-L40``）：

.. code-block:: systemverilog

   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import core_eh2_env_pkg::*;
   import eh2_irq_agent_pkg::*;
   import eh2_jtag_agent_pkg::*;
   
   class core_eh2_vseq extends uvm_sequence;
   
     `uvm_object_utils(core_eh2_vseq)
   
     // Configuration
     core_eh2_env_cfg cfg;
   
     // Virtual sequencer

**逐段解释**：

* 第 L17-L21 行：vseq 文件导入 UVM、env、IRQ agent 和 JTAG agent package。
* 第 L23-L31 行：class 继承 ``uvm_sequence``，持有 cfg 和 virtual sequencer 句柄。
* 第 L34-L40 行：成员句柄覆盖 single IRQ、multiple IRQ、NMI、IRQ drop、debug
  stress、debug single 和 fetch-enable sequence。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L42-L53``）：

.. code-block:: systemverilog

     function new(string name = "core_eh2_vseq");
       super.new(name);
     endfunction
   
     virtual task pre_body();
       if (cfg == null) begin
         `uvm_fatal("vseq", "cfg is null - must set before starting vseq")
       end
       if (vseqr == null && !$cast(vseqr, m_sequencer)) begin
         `uvm_fatal("vseq", "m_sequencer is not a core_eh2_vseqr")
       end
     endtask

**逐段解释**：

* 第 L42-L44 行：constructor 只调用 ``super.new(name)``，不创建任何子 sequence。
* 第 L46-L49 行：cfg 为空时 fatal，避免 ``body()`` 读取 enable 位时空指针。
* 第 L50-L52 行：当 ``vseqr`` 尚未设置时，尝试把 ``m_sequencer`` cast 成
  ``core_eh2_vseqr``；失败时 fatal。

**接口关系**：

* **被调用**：``vseq.start(env.vseqr)`` 触发 sequence pre-body。
* **调用**：调用 ``$cast`` 和 ``uvm_fatal``。
* **共享状态**：读取 ``cfg``、``vseqr`` 和 ``m_sequencer``，可能写入 ``vseqr``。

§4.2  IRQ 分支 — single、multiple 和 NMI
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``body()`` 根据 cfg 的 IRQ enable 位创建 IRQ 子序列，将 ``irq_vif`` 和
``max_interval`` 传给它们，然后直接启动。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L55-L85``）：

.. code-block:: systemverilog

   virtual task body();
     `uvm_info("vseq", "Starting virtual sequence", UVM_LOW)
   
     fork
       // IRQ sequences
       begin
         if (cfg.enable_irq_single_seq) begin
           irq_single_h = irq_raise_single_seq::type_id::create("irq_single_h");
           irq_single_h.irq_vif = get_irq_vif();
           irq_single_h.interval = cfg.max_interval;
           irq_single_h.start(null);
         end
       end

**逐段解释**：

* 第 L55-L58 行：body 打印日志后进入 ``fork``。
* 第 L60-L66 行：``enable_irq_single_seq`` 为 1 时创建 ``irq_raise_single_seq``，
  绑定 ``irq_vif``，把 ``interval`` 设为 ``cfg.max_interval``，再 ``start(null)``。
* 第 L69-L75 行：``enable_irq_multiple_seq`` 为 1 时创建 ``irq_raise_seq``，同样绑定
  interface 和 interval。
* 第 L78-L84 行：``enable_irq_nmi_seq`` 为 1 时创建 ``irq_raise_nmi_seq``。

**接口关系**：

* **被调用**：``core_eh2_base_test.start_vseq()`` 启动 vseq 后进入 body。
* **调用**：调用 ``get_irq_vif()`` 和各 IRQ sequence ``start``。
* **共享状态**：``cfg.max_interval`` 控制 IRQ 子序列随机间隔上限。

§4.3  debug 和 fetch-enable 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：debug 分支使用 virtual sequencer 的 JTAG sequencer；fetch-enable 分支创建
``fetch_enable_seq`` 并传入 interval。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L87-L117``）：

.. code-block:: systemverilog

       // Debug sequences
       begin
         if (cfg.enable_debug_seq || cfg.enable_debug_stress) begin
           debug_stress_h = debug_seq::type_id::create("debug_stress_h");
           debug_stress_h.jtag_seqr = vseqr.jtag_seqr;
           debug_stress_h.stress_mode = cfg.enable_debug_stress;
           debug_stress_h.interval = cfg.max_interval;
           debug_stress_h.start(null);
         end
       end
   
       begin
         if (cfg.enable_debug_single) begin

**逐段解释**：

* 第 L89-L95 行：当 ``enable_debug_seq`` 或 ``enable_debug_stress`` 为 1 时，vseq
  创建 ``debug_seq``，绑定 ``vseqr.jtag_seqr``，将 ``stress_mode`` 设为
  ``cfg.enable_debug_stress``，并设置 interval。
* 第 L99-L105 行：``enable_debug_single`` 为 1 时，vseq 创建第二个 ``debug_seq``，
  将 ``stress_mode`` 固定为 0。
* 第 L110-L114 行：``enable_fetch_toggle`` 为 1 时，vseq 创建 ``fetch_enable_seq``，
  设置 interval 并启动。当前代码没有在此处给 ``fetch_en_h.fetch_vif`` 赋值。
* 第 L116 行：``join_none`` 让 body 不等待这些分支自然结束。

**接口关系**：

* **被调用**：vseq body 的并行分支。
* **调用**：调用 ``debug_seq.start`` 和 ``fetch_enable_seq.start``。
* **共享状态**：debug 分支依赖 ``vseqr.jtag_seqr``；fetch sequence 自身成员
  ``fetch_vif`` 是否非空取决于外部赋值，当前 ``core_eh2_vseq.sv`` 没有执行赋值。

§4.4  ``stop()`` 与 helper task
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：vseq ``stop()`` 停止已创建的子序列；helper task 提供 directed test 可直接
启动某个子序列的入口。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L119-L178``）：

.. code-block:: systemverilog

   // Stop all sequences
   virtual task stop();
     if (irq_single_h != null) irq_single_h.stop();
     if (irq_multi_h  != null) irq_multi_h.stop();
     if (irq_nmi_h    != null) irq_nmi_h.stop();
     if (irq_drop_h   != null) irq_drop_h.stop();
     if (debug_stress_h != null) debug_stress_h.stop();
     if (debug_single_h != null) debug_single_h.stop();
     if (fetch_en_h   != null) fetch_en_h.stop();
   endtask
   
   // Helper: get IRQ virtual interface from config_db

**逐段解释**：

* 第 L120-L128 行：``stop()`` 对所有非空子序列调用 ``stop()``。包括
  ``irq_drop_h``，虽然 body 中当前没有创建该句柄。
* 第 L131-L137 行：``get_irq_vif()`` 从 config_db 读取 ``irq_vif``；读取失败时
  warning 并返回当前 ``vif`` 值。
* 第 L140-L176 行：helper task 可以直接创建并启动 single IRQ、multi IRQ、NMI、
  IRQ drop、debug stress 和 debug single sequence。它们主要用于 directed stimulus
  从 test 侧手动触发。

**接口关系**：

* **被调用**：base test 在 completion 后调用 ``vseq.stop()``；directed test 可调用
  helper task。
* **调用**：调用各子序列 ``stop`` 或 ``start``。
* **共享状态**：helper task 依赖 ``vseqr.jtag_seqr`` 和 config_db 中的 ``irq_vif``。

§5  子序列行为
--------------------------------------------------------------------------------

§5.1  ``core_eh2_base_seq`` — 旧式序列的 stop 与随机等待
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：旧式 IRQ/debug/fetch sequence 共同继承 ``core_eh2_base_seq``。它提供随机
初始 delay、随机 event interval 和 stop flag。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L24-L61``）：

.. code-block:: systemverilog

   class core_eh2_base_seq extends uvm_sequence;
   
     `uvm_object_utils(core_eh2_base_seq)
   
     int unsigned interval = 500;    // Max cycles between events
     int unsigned delay_min = 100;   // Min initial delay (ns)
     int unsigned delay_max = 5000;  // Max initial delay (ns)
     bit            stopped = 0;     // Stop flag
   
     function new(string name = "core_eh2_base_seq");
       super.new(name);

**逐段解释**：

* 第 L24-L31 行：base sequence 定义 ``interval``、``delay_min``、``delay_max`` 和
  ``stopped``。
* 第 L38-L42 行：``rand_delay()`` 在 ``delay_min`` 到 ``delay_max`` ns 范围内随机
  等待。
* 第 L45-L49 行：``rand_interval()`` 在 1 到 ``interval`` 的 10 ns 单位范围内随机
  等待。
* 第 L52-L59 行：``stop()`` 置 ``stopped=1``；``wait_for_stop()`` 等待该 flag。

**接口关系**：

* **被调用**：IRQ、debug 和 fetch-enable sequence 继承。
* **调用**：调用 ``$urandom_range`` 和 delay control。
* **共享状态**：``interval`` 由 ``core_eh2_vseq`` 从 ``cfg.max_interval`` 下发。

§5.2  IRQ sequence — external interrupt 和 NMI signal
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：IRQ 子序列直接驱动 ``eh2_irq_intf``：multi IRQ 每轮拉高多个
``extintsrc_req``，single IRQ 每轮拉高一个，NMI sequence 拉高 ``nmi_int``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L66-L127``）：

.. code-block:: systemverilog

   class irq_raise_seq extends core_eh2_base_seq;
   
     `uvm_object_utils(irq_raise_seq)
   
     // Virtual interface to drive interrupts
     virtual eh2_irq_intf irq_vif;
   
     int unsigned max_irq_id = 127;  // Max external interrupt ID
     int unsigned num_irqs = 3;      // Number of interrupts to raise per event
   
     function new(string name = "irq_raise_seq");
       super.new(name);

**逐段解释**：

* 第 L66-L75 行：multi IRQ sequence 持有 ``irq_vif``，最大 external IRQ ID 为 127，
  每个 event 默认拉高 3 个 interrupt。
* 第 L80-L95 行：body 先随机初始 delay，然后循环检查 ``stopped``，随机选择多个 ID
  拉高 ``irq_vif.extintsrc_req``，等待 interval 后清零，再等待下一轮 interval。
* 第 L102-L127 行：single IRQ sequence 同样使用 ``irq_vif``，但每轮只选择一个 ID，
  并在 interval 后清掉该 ID。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L132-L181``）：

.. code-block:: systemverilog

   class irq_raise_nmi_seq extends core_eh2_base_seq;
   
     `uvm_object_utils(irq_raise_nmi_seq)
   
     virtual eh2_irq_intf irq_vif;
   
     function new(string name = "irq_raise_nmi_seq");
       super.new(name);
     endfunction
   
     virtual task body();
       rand_delay();

**逐段解释**：

* 第 L132-L140 行：NMI sequence 持有 ``eh2_irq_intf``。
* 第 L142-L150 行：body 循环拉高 ``irq_vif.nmi_int``，等待 interval 后拉低，再等待
  下一轮 interval。
* 第 L158-L179 行：``irq_drop_seq`` 周期性清零 ``extintsrc_req``、``timer_int``、
  ``soft_int`` 和 ``nmi_int``。

**接口关系**：

* **被调用**：``core_eh2_vseq`` 和 helper task 启动。
* **调用**：直接赋值 ``eh2_irq_intf`` 信号。
* **共享状态**：``irq_vif`` 由 ``get_irq_vif()`` 从 config_db 获取。

§5.3  ``debug_seq`` — JTAG DMI command walk
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：debug sequence 通过 JTAG sequencer 发送一组 DMI write，覆盖 dmactive、
halt、abstract register read、core-local memory read、external system bus read、
direct system bus access、resume 和 clear resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L186-L239``）：

.. code-block:: systemverilog

   class debug_seq extends core_eh2_base_seq;
   
     `uvm_object_utils(debug_seq)
   
     // Sequencer to send JTAG transactions
     uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr;
   
     bit stress_mode = 0;  // 1 = continuous, 0 = single
   
     function new(string name = "debug_seq");
       super.new(name);

**逐段解释**：

* 第 L186-L193 行：debug sequence 持有 JTAG sequencer 和 ``stress_mode``。
* 第 L199-L213 行：body 先随机 delay；stress mode 下循环执行 command walk 和随机
  interval，非 stress mode 只执行一次 command walk。
* 第 L220-L239 行：``send_debug_command_walk()`` 的顺序是 dmactive、halt、读 core
  register、读 5 个 DCCM 地址、读 external system bus、direct system-bus read/write、
  resume、clear resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L241-L298``）：

.. code-block:: systemverilog

   virtual task send_dmactive();
     eh2_jtag_seq::send_write(jtag_seqr,
       eh2_jtag_seq_item::DMI_DMCONTROL, 32'h00000001);
   endtask
   
   virtual task send_halt();
     eh2_jtag_seq::send_write(jtag_seqr,
       eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);
   endtask
   
   virtual task send_core_register_read();
     // Abstract register command: read x0 with transfer=1 and 32-bit size.

**逐段解释**：

* 第 L241-L249 行：``send_dmactive()`` 和 ``send_halt()`` 都写
  ``DMI_DMCONTROL``，值分别为 ``32'h00000001`` 和 ``32'h80000001``。
* 第 L251-L265 行：``send_core_register_read()`` 写 ``DMI_COMMAND`` 的
  ``32'h00221000``；``send_core_local_memory_read()`` 先写 ``DMI_DATA1`` 地址，再写
  ``DMI_COMMAND`` 的 ``32'h02200000``。
* 第 L267-L288 行：external system bus read 使用 ``0x80000000``；direct system-bus
  access 先写 ``DMI_SBCS``、再写 ``DMI_SBADDRESS0``、最后写 ``DMI_SBDATA0``。
* 第 L290-L298 行：resume 写 ``DMI_DMCONTROL=32'h40000001``，clear resume 写
  ``32'h00000001``。

**接口关系**：

* **被调用**：vseq debug 分支和部分派生 test 启动。
* **调用**：调用 ``eh2_jtag_seq::send_write``。
* **共享状态**：``jtag_seqr`` 来自 ``core_eh2_vseqr.jtag_seqr``。

§5.4  fetch-enable sequence — 当前 vseq 未赋 ``fetch_vif``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：fetch-enable sequence 周期性拉低/拉高 ``fetch_vif.fetch_enable``。当前
``core_eh2_vseq`` 创建该 sequence 时只设置 interval，没有给 ``fetch_vif`` 赋值。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L305-L330``）：

.. code-block:: systemverilog

   class fetch_enable_seq extends core_eh2_base_seq;
   
     `uvm_object_utils(fetch_enable_seq)
   
     virtual interface fetch_enable_intf fetch_vif;
   
     function new(string name = "fetch_enable_seq");
       super.new(name);
     endfunction
   
     virtual task body();
       rand_delay();
       forever begin

**逐段解释**：

* 第 L305-L313 行：旧式 ``fetch_enable_seq`` 持有 ``fetch_enable_intf``，constructor
  不从 config_db 获取它。
* 第 L315-L327 行：body 循环检查 ``stopped``，如果 ``fetch_vif`` 非空则拉低
  ``fetch_enable``，等待 interval，再拉高 ``fetch_enable``。
* 因为 ``core_eh2_vseq.sv`` 在创建 ``fetch_en_h`` 后只写 ``interval`` 并启动，
  当前代码路径下 ``fetch_vif`` 是否有效不能从该文件证明。

**接口关系**：

* **被调用**：``core_eh2_vseq`` 在 ``cfg.enable_fetch_toggle`` 为 1 时创建并启动。
* **调用**：直接驱动 ``fetch_vif.fetch_enable``。
* **共享状态**：tb_top 将 ``fetch_vif`` 放入 config_db；旧式 sequence 本身没有读取
  config_db 的代码。

§6  new-style sequence
--------------------------------------------------------------------------------

§6.1  ``core_eh2_base_new_seq`` — 可配置运行次数的请求序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：new-style sequence 支持零延迟概率、随机 stimulus delay、单次/多次/无限次
运行模式和停止等待。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L17-L55``）：

.. code-block:: systemverilog

   class core_eh2_base_new_seq #(type REQ = uvm_sequence_item) extends uvm_sequence #(REQ);
   
     `uvm_object_param_utils(core_eh2_base_new_seq#(REQ))
   
     // Virtual interface for DUT probing
     virtual eh2_dut_probe_if dut_vif;
   
     bit          stop_seq;
     bit          seq_finished;
   
     rand bit     zero_delays;
     int unsigned zero_delay_pct = 50;

**逐段解释**：

* 第 L17-L23 行：base new sequence 是参数化 ``uvm_sequence``，并持有可选
  ``eh2_dut_probe_if``。
* 第 L24-L32 行：``zero_delays`` 按 ``zero_delay_pct`` 分布随机，默认 50%。
* 第 L34-L48 行：``stimulus_delay_cycles`` 和 ``iteration_cnt`` 都有约束；
  ``iteration_modes`` 默认是 ``MultipleRuns``。
* 第 L50-L55 行：constructor 从 config_db 获取 ``probe_vif``，失败 warning。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L61-L106``）：

.. code-block:: systemverilog

   virtual task body();
     `uvm_info(get_name(), $sformatf("Running \"%s\" schedule", iteration_modes.name()), UVM_LOW)
     stop_seq = 1'b0;
     seq_finished = 1'b0;
     case (iteration_modes)
       SingleRun: begin
         drive_stimulus();
       end
       MultipleRuns: begin
         for (int i = 0; i <= iteration_cnt; i++) begin
           if (stop_seq) break;
           `uvm_info(get_name(), $sformatf("Iteration %0d/%0d", i, iteration_cnt), UVM_LOW)

**逐段解释**：

* 第 L61-L85 行：body 按 ``iteration_modes`` 调度：单次运行一次，多次运行
  ``0 <= i <= iteration_cnt``，无限次直到 ``stop_seq``。
* 第 L88-L94 行：``drive_stimulus()`` 在非 zero-delay 模式下等待随机 cycles，再调用
  ``send_req()``。
* 第 L96-L104 行：base ``send_req()`` fatal，子类必须实现；``stop()`` 等待
  ``seq_finished`` 后返回。

**接口关系**：

* **被调用**：``irq_new_seq``、``debug_new_seq``、``memory_error_seq`` 和
  ``fetch_enable_new_seq`` 继承。
* **调用**：调用子类 ``send_req()``。
* **共享状态**：``run_type_e`` 枚举来自 ``core_eh2_test_pkg.sv``。

§6.2  new-style 子类 — 当前源码中的请求形态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：new-style 子类提供独立的 IRQ、debug、memory error 和 fetch-enable 请求实现。
它们被 package include，但当前 ``core_eh2_vseq.sv`` 没有创建这些 new-style class。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L111-L146``）：

.. code-block:: systemverilog

   class irq_new_seq extends core_eh2_base_new_seq #(uvm_sequence_item);
   
     `uvm_object_utils(irq_new_seq)
   
     virtual eh2_irq_intf irq_vif;
   
     rand int unsigned num_interrupts;
     constraint num_interrupts_c { num_interrupts inside {[1:5]}; }
   
     rand int unsigned irq_duration;
     constraint irq_duration_c { irq_duration inside {[10:100]}; }

**逐段解释**：

* 第 L111-L127 行：``irq_new_seq`` 从 config_db 获取 ``irq_vif``，约束每次产生
  1-5 个 interrupt，duration 为 10-100。
* 第 L129-L146 行：``send_req()`` 拉高随机 external IRQ ID，等待 duration 后清掉
  1-127 全部 external IRQ。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L153-L193``）：

.. code-block:: systemverilog

   class debug_new_seq extends core_eh2_base_new_seq #(uvm_sequence_item);
   
     `uvm_object_utils(debug_new_seq)
   
     virtual eh2_jtag_intf jtag_vif;
   
     rand int unsigned pulse_length_cycles;
     constraint pulse_length_c { pulse_length_cycles inside {[75:500]}; }
   
     function new(string name = "debug_new_seq");
       super.new(name);

**逐段解释**：

* 第 L153-L164 行：``debug_new_seq`` 有 ``jtag_vif`` 成员和 75-500 cycles 的 pulse
  length 约束，但 constructor 只调用父类。
* 第 L166-L170 行：``send_req()`` 打印 pulse length，然后等待 75-500 个 10 ns 单位；
  当前代码没有通过 ``jtag_vif`` 实际驱动 debug 信号。
* 第 L177-L193 行：``memory_error_seq`` 打印 error side 和 percentage，实际注释说明
  error injection 由配置后的 AXI4 driver 处理。

**接口关系**：

* **被调用**：当前源码只证明这些类被 package include；没有在 ``core_eh2_vseq.sv``
  中创建。
* **调用**：IRQ new sequence 直接驱动 ``irq_vif``；debug/memory error new sequence
  主要打印并等待。
* **共享状态**：``probe_vif``、``irq_vif`` 和 ``fetch_vif`` 来自 config_db。

§7  config_db 接口来源
--------------------------------------------------------------------------------

§7.1  ``core_eh2_tb_top`` — 将 vif 放入 UVM config_db
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：tb_top 在启动 UVM 前把 AXI、trace、probe、IRQ、JTAG、halt/run、fetch 和
coverage virtual interface 放入 config_db。vseq 和子序列依赖其中的 IRQ/fetch/JTAG
相关条目。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L1108-L1135``）：

.. code-block:: systemverilog

   uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_LSU_BUS_TAG)))::set(null, "*lsu_agent*", "vif", lsu_axi_intf);
   uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_IFU_BUS_TAG)))::set(null, "*ifu_agent*", "vif", ifu_axi_intf);
   uvm_config_db#(virtual axi4_intf#(.ID_WIDTH(`RV_SB_BUS_TAG)))::set(null, "*sb_agent*",  "vif", sb_axi_intf);
   
   // Store trace and DUT probe interfaces
   uvm_config_db#(virtual eh2_trace_intf)::set(null, "*trace_monitor*", "vif", trace_intf);
   uvm_config_db#(virtual eh2_dut_probe_if)::set(null, "*dut_probe_monitor*", "vif", dut_probe_intf);
   
   // Also provide DUT probe interface to trace monitor (for interrupt/debug state sampling)

**逐段解释**：

* 第 L1108-L1110 行：AXI interface 绑定到 lsu/ifu/sb agent。
* 第 L1113-L1120 行：trace 和 DUT probe interface 绑定到 trace/dut probe monitor 和
  cosim agent。
* 第 L1123-L1129 行：``irq_vif``、``jtag_vif`` 和 ``halt_run_vif`` 以 wildcard
  path 放入 config_db。
* 第 L1131-L1135 行：``fetch_vif`` 和 ``fcov_vif`` 也放入 config_db。

**接口关系**：

* **被调用**：tb_top initial/setup 代码在 UVM run 前执行这些 set。
* **调用**：调用 ``uvm_config_db::set``。
* **共享状态**：``core_eh2_vseq.get_irq_vif()`` 和 new-style sequence constructor
  使用这些 config_db 条目。

§8  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`appendix_b_uvm_vseq`、:ref:`tests_library`、
  :ref:`appendix_b_uvm_env`、:ref:`appendix_b_uvm_tb`、:ref:`agent_irq`、
  :ref:`agent_jtag`、:doc:`../06_flows/regression_flow`。
* 关联 ADR：:ref:`adr-0007`、:ref:`adr-0008`。
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_vseq.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_cfg.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml``

§9  与 Ibex 工业实现对照
--------------------------------------------------------------------------------

Ibex 的 ``core_ibex_vseqr`` 保存 data/instr memory response sequencer、IRQ sequencer
等句柄，virtual sequence 负责协调 memory stimulus、IRQ、debug 和 cosim 相关控制。
EH2 当前 ``core_eh2_vseqr`` 更窄，只保存 IRQ、JTAG 和 Halt/Run 子 sequencer；AXI4
agent 默认 passive，不通过 vseqr 发起普通 memory transaction。这个差异与 EH2 TB
中行为级 AXI4 memory model 的定位一致。

.. list-table:: vseq/vseqr 对照
   :header-rows: 1
   :widths: 25 35 40

   * - 维度
     - Ibex
     - EH2
   * - vseqr 路径
     - ``/home/host/ibex/dv/uvm/core_ibex/env/core_ibex_vseqr.sv``
     - ``dv/uvm/core_eh2/env/core_eh2_vseqr.sv``
   * - 子 sequencer
     - memory response、IRQ 等
     - IRQ、JTAG、Halt/Run
   * - memory stimulus
     - 通过 Ibex memory agent/vseq 协调
     - 普通 AXI4 response 由 TB memory model 处理，error injection 走 AXI4 driver
   * - test 入口
     - Ibex test/vseq library
     - ``core_eh2_base_test``、``core_eh2_vseq``、directed/riscv-dv testlist

§10  Sign-off 关联
--------------------------------------------------------------------------------

virtual sequence 层决定 active agent stimulus 是否真的发出。当前 directed 40/40 和
riscv-dv 370/395 的稳定性依赖 ``core_eh2_vseqr`` 在 env connect phase 正确拿到
``irq_seqr``、``jtag_seqr`` 和 ``halt_run_seqr``。新增 directed vseq 时应避免发明
当前源码不存在的 ``core_eh2_smoke_vseq`` 等旧名字，优先扩展现有 ``core_eh2_vseq`` 或
test-specific helper sequence。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从真实 UVM 源码中找出本页组件所属 class、interface 或 covergroup。

.. code-block:: bash

   rg -n "class .*extends|uvm_component_utils|uvm_object_utils|phase" dv/uvm/core_eh2 | head -60
   rg -n "interface|analysis_port|scoreboard|covergroup" dv/uvm/core_eh2 | head -60

**进阶题**：检查本页是否把 EH2 和 Ibex 的一致点、差异点分开描述。

.. code-block:: bash

   rg -n "core_ibex|Ibex|与 Ibex" docs/sphinx_cn/source/05_verification_arch docs/sphinx_cn/source/appendix_b_uvm | head -80

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
