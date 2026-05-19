.. _appendix_b_uvm_vseq:
.. _appendix_b_uvm/vseq:

虚拟序列库逐段参考
==================

:status: draft
:source: dv/uvm/core_eh2/tests/core_eh2_vseq.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1 文件定位与执行边界
--------------------------------------------------------------------------------

本章只解释 UVM 测试层的序列编排代码，不解释 DUT 内部的中断、debug 或取指 RTL。
源文件证据来自 ``core_eh2_vseq.sv``、``core_eh2_seq_lib.sv``、
``core_eh2_new_seq_lib.sv``、``core_eh2_vseqr.sv``、``core_eh2_env.sv``、
``core_eh2_env_cfg.sv``、``core_eh2_base_test.sv`` 和 ``core_eh2_test_pkg.sv``。

虚拟序列的运行路径如下：

.. code-block:: text

   core_eh2_base_test.start_vseq()
       |
       v
   core_eh2_vseq.cfg = env_cfg
       |
       v
   core_eh2_vseq.start(env.vseqr)
       |
       v
   core_eh2_vseq.body()
       |
       +--> irq_raise_single_seq / irq_raise_seq / irq_raise_nmi_seq
       +--> debug_seq
       +--> fetch_enable_seq

这张图只表示当前代码中的调用关系：``start_vseq()`` 创建 ``core_eh2_vseq``，
把 ``env_cfg`` 写入 ``vseq.cfg``，再通过 ``env.vseqr`` 启动虚拟序列。
``core_eh2_vseq.body()`` 内部根据配置位决定是否创建 IRQ、debug 和
fetch-enable 子序列。

§1.1 测试包包含顺序
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``core_eh2_test_pkg.sv`` 定义序列库可见性。旧序列库、新序列库和虚拟序列都在同一个 package 内被 include。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L30-L48``）：

.. code-block:: systemverilog

     SingleRun,    // Single iteration
     InfiniteRuns, // Run forever until stop is specified
     MultipleRuns  // Multiple runs with configurable iteration count
   } run_type_e;

   // Error injection side selection
   typedef enum bit [1:0] {
     IsideErr, // Inject error in instruction side memory
     DsideErr, // Inject error in data side memory
     PickErr   // Pick which memory to inject error in
   } error_type_e;

   `include "core_eh2_report_server.sv"
   `include "core_eh2_seq_lib.sv"
   `include "core_eh2_new_seq_lib.sv"
   `include "core_eh2_vseq.sv"
   `include "core_eh2_base_test.sv"
   `include "core_eh2_test_lib.sv"
   `include "core_eh2_intg_test_lib.sv"

逐段解释：

* 第 L30-L33 行：``run_type_e`` 给新式序列库提供 ``SingleRun``、``InfiniteRuns`` 和 ``MultipleRuns`` 三种调度模式；这些枚举值在 ``core_eh2_base_new_seq.body()`` 的 ``case`` 中被消费。
* 第 L35-L40 行：``error_type_e`` 给 ``memory_error_seq`` 提供 ``IsideErr``、``DsideErr`` 和 ``PickErr`` 三个取值；序列本身只记录选择并打印日志。
* 第 L42-L48 行：package include 顺序先引入旧序列库，再引入新序列库，随后引入 ``core_eh2_vseq.sv``；因此虚拟序列可以直接声明 ``irq_raise_seq``、``debug_seq`` 和 ``fetch_enable_seq`` 句柄。

接口关系：

* 被调用：编译单元通过 ``core_eh2_test_pkg`` 引入这些类型。
* 调用：本片段不执行任务，只通过 ``include`` 建立类型可见性。
* 共享状态：``run_type_e`` 被 ``core_eh2_new_seq_lib.sv`` 读取；``error_type_e`` 被 ``memory_error_seq`` 读取。

§1.2 基类启动虚拟序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``core_eh2_base_test.start_vseq()`` 是虚拟序列的上层入口，它把环境配置对象传给序列，并把启动 sequencer 指向 ``env.vseqr``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L335-L342``）：

.. code-block:: systemverilog

   // =========================================================================
   // Virtual Sequence
   // =========================================================================
   virtual task start_vseq();
     vseq = core_eh2_vseq::type_id::create("vseq");
     vseq.cfg = env_cfg;
     vseq.start(env.vseqr);
   endtask

逐段解释：

* 第 L338-L339 行：测试基类用 UVM factory 创建 ``core_eh2_vseq`` 对象，名字固定为 ``vseq``。
* 第 L340 行：``env_cfg`` 被写入 ``vseq.cfg``。后续 ``pre_body()`` 会检查 ``cfg`` 非空，``body()`` 会读取其中的使能位和 ``max_interval``。
* 第 L341 行：``vseq.start(env.vseqr)`` 把 ``env.vseqr`` 作为 ``m_sequencer`` 传给虚拟序列；当前 ``core_eh2_vseq.pre_body()`` 还会把 ``m_sequencer`` cast 成 ``core_eh2_vseqr``。

接口关系：

* 被调用：具体 test 的 run flow 会调用 ``start_vseq()``。
* 调用：``core_eh2_vseq::type_id::create()`` 和 ``vseq.start()``。
* 共享状态：读取 ``env_cfg``、``env.vseqr``，写入测试对象成员 ``vseq``。

§2 ``core_eh2_vseq`` 顶层编排
--------------------------------------------------------------------------------

``core_eh2_vseq`` 是当前 UVM 环境中唯一的虚拟序列类。它不直接驱动 DUT 端口，而是创建普通 sequence，并把 IRQ virtual interface 或 JTAG sequencer 句柄传给子序列。

§2.1 类声明、导入与成员句柄
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：类声明区域定义 ``core_eh2_vseq`` 需要的 package、配置对象、virtual sequencer 和各类子序列句柄。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L17-L40``）：

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
     core_eh2_vseqr vseqr;

     // Sub-sequences
     irq_raise_single_seq irq_single_h;
     irq_raise_seq        irq_multi_h;
     irq_raise_nmi_seq    irq_nmi_h;
     irq_drop_seq         irq_drop_h;
     debug_seq            debug_stress_h;
     debug_seq            debug_single_h;
     fetch_enable_seq     fetch_en_h;

逐段解释：

* 第 L17-L21 行：导入 UVM、环境 package、IRQ agent package 和 JTAG agent package；这些导入分别提供 ``uvm_sequence``、``core_eh2_env_cfg``、``eh2_irq_intf``、``eh2_jtag_seq_item`` 等类型。
* 第 L23-L25 行：``core_eh2_vseq`` 继承 ``uvm_sequence``，并用 ``uvm_object_utils`` 注册到 UVM factory。
* 第 L28-L31 行：``cfg`` 保存环境配置，``vseqr`` 保存虚拟 sequencer；二者都不是在构造函数中创建，而是由上层 test 或 ``pre_body()`` 赋值。
* 第 L34-L40 行：每个子序列都有单独句柄。``irq_drop_h`` 有句柄和 helper task，但当前 ``body()`` 中没有创建它。

接口关系：

* 被调用：``core_eh2_base_test.start_vseq()`` 创建并启动该类。
* 调用：声明阶段不调用任务；后续 ``body()`` 会创建这些子序列。
* 共享状态：``cfg`` 来自 test，``vseqr`` 来自 ``m_sequencer`` 或外部赋值。

§2.2 ``new()`` 与 ``pre_body()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造函数只调用父类构造；``pre_body()`` 在真正进入 ``body()`` 前检查配置和 sequencer 类型。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L42-L53``）：

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

逐段解释：

* 第 L42-L44 行：构造函数没有创建任何子对象，只把名字传给 ``uvm_sequence``。
* 第 L46-L49 行：``cfg`` 为空时直接 ``uvm_fatal``，因为后续所有子序列使能判断都依赖 ``cfg``。
* 第 L50-L52 行：当 ``vseqr`` 尚未被外部设置时，代码尝试把 ``m_sequencer`` cast 成 ``core_eh2_vseqr``；失败时 ``uvm_fatal``，避免后续访问 ``vseqr.jtag_seqr`` 时空指针。

接口关系：

* 被调用：``vseq.start(env.vseqr)`` 触发 UVM sequence pre-body 流程。
* 调用：``$cast`` 和 ``uvm_fatal``。
* 共享状态：读取 ``cfg``、``vseqr``、``m_sequencer``，可能写入 ``vseqr``。

§2.3 ``body()`` 的并行拓扑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``body()`` 按配置位启动多个独立 stimulus 分支；当前代码使用 ``fork ... join_none``，因此启动后不等待这些分支自然结束。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L55-L66``）：

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

逐段解释：

* 第 L55-L58 行：进入 ``body()`` 后先打印 UVM log，然后打开 ``fork``。该 ``fork`` 下的每个 ``begin`` 块是一个并行分支。
* 第 L61-L65 行：当 ``cfg.enable_irq_single_seq`` 为 1 时，创建 ``irq_raise_single_seq``，通过 ``get_irq_vif()`` 获取 IRQ virtual interface，把 ``cfg.max_interval`` 写入子序列，再以 ``start(null)`` 启动。
* ``start(null)`` 说明该子序列不通过 typed sequencer 取 item，而是直接使用 virtual interface 或内部任务驱动。

接口关系：

* 被调用：UVM sequence body 流程调用。
* 调用：``irq_raise_single_seq::type_id::create()``、``get_irq_vif()``、``irq_single_h.start(null)``。
* 共享状态：读取 ``cfg.enable_irq_single_seq`` 和 ``cfg.max_interval``，写入 ``irq_single_h``。

§2.4 多 IRQ 与 NMI 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：多 IRQ 和 NMI 分支与单 IRQ 分支同级并行，它们只在对应配置位为 1 时创建。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L69-L85``）：

.. code-block:: systemverilog

         begin
           if (cfg.enable_irq_multiple_seq) begin
             irq_multi_h = irq_raise_seq::type_id::create("irq_multi_h");
             irq_multi_h.irq_vif = get_irq_vif();
             irq_multi_h.interval = cfg.max_interval;
             irq_multi_h.start(null);
           end
         end

         begin
           if (cfg.enable_irq_nmi_seq) begin
             irq_nmi_h = irq_raise_nmi_seq::type_id::create("irq_nmi_h");
             irq_nmi_h.irq_vif = get_irq_vif();
             irq_nmi_h.interval = cfg.max_interval;
             irq_nmi_h.start(null);
           end
         end

逐段解释：

* 第 L69-L75 行：``cfg.enable_irq_multiple_seq`` 控制 ``irq_raise_seq``，该序列一次可以拉起多个 ``extintsrc_req`` bit。
* 第 L78-L84 行：``cfg.enable_irq_nmi_seq`` 控制 ``irq_raise_nmi_seq``，该序列只驱动 ``nmi_int``。
* 两个分支都调用 ``get_irq_vif()``，因此都依赖 ``uvm_config_db`` 中存在 ``irq_vif``。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的并行分支。
* 调用：``irq_raise_seq``、``irq_raise_nmi_seq`` 的 factory create 和 ``start(null)``。
* 共享状态：读取 ``cfg.enable_irq_multiple_seq``、``cfg.enable_irq_nmi_seq``、``cfg.max_interval``，写入 ``irq_multi_h``、``irq_nmi_h``。

§2.5 Debug 与 fetch-enable 分支
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：debug 分支把 JTAG sequencer 传给 ``debug_seq``；fetch-enable 分支创建 ``fetch_enable_seq``，但本片段没有给 ``fetch_en_h.fetch_vif`` 赋值。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L87-L116``）：

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
             debug_single_h = debug_seq::type_id::create("debug_single_h");
             debug_single_h.jtag_seqr = vseqr.jtag_seqr;
             debug_single_h.stress_mode = 0;
             debug_single_h.interval = cfg.max_interval;
             debug_single_h.start(null);
           end
         end

         // Fetch-enable sequence
         begin
           if (cfg.enable_fetch_toggle) begin
             fetch_en_h = fetch_enable_seq::type_id::create("fetch_en_h");
             fetch_en_h.interval = cfg.max_interval;
             fetch_en_h.start(null);
           end
         end
       join_none

逐段解释：

* 第 L89-L95 行：``cfg.enable_debug_seq`` 或 ``cfg.enable_debug_stress`` 为 1 时创建 ``debug_stress_h``。``stress_mode`` 被赋值为 ``cfg.enable_debug_stress``，所以普通 ``+enable_debug_seq=1`` 可以触发有限 debug walk，``+enable_debug_stress=1`` 触发循环模式。
* 第 L99-L105 行：``cfg.enable_debug_single`` 创建另一个 ``debug_seq`` 实例，``stress_mode`` 固定为 0。
* 第 L110-L113 行：``cfg.enable_fetch_toggle`` 创建 ``fetch_enable_seq`` 并设置 ``interval``。当前虚拟序列没有设置 ``fetch_en_h.fetch_vif``。
* 第 L116 行：``join_none`` 让 ``body()`` 不等待子分支结束。上层需要通过 ``stop()`` 或仿真结束流程终止长期运行的子序列。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的并行分支。
* 调用：``debug_seq``、``fetch_enable_seq`` 的 factory create 和 ``start(null)``。
* 共享状态：读取 ``cfg.enable_debug_seq``、``cfg.enable_debug_stress``、``cfg.enable_debug_single``、``cfg.enable_fetch_toggle``、``cfg.max_interval``，读取 ``vseqr.jtag_seqr``，写入 ``debug_stress_h``、``debug_single_h``、``fetch_en_h``。

§2.6 ``stop()`` 停止已创建的子序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``stop()`` 对每个非空子序列句柄调用对应 ``stop()``，把停止请求传递到旧序列库的 ``stopped`` 标志。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L119-L128``）：

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

逐段解释：

* 第 L120-L124 行：IRQ 类句柄逐个判空后停止。即使 ``irq_drop_h`` 不是由 ``body()`` 创建，也可能由 helper task 创建，因此这里同样处理。
* 第 L125-L127 行：debug 和 fetch-enable 句柄也按同样方式停止。旧序列库的 ``stop()`` 只置 ``stopped`` 标志，真正返回发生在各子序列下一次检查该标志时。

接口关系：

* 被调用：上层 test 可在完成或超时路径中调用。
* 调用：各子序列的 ``stop()``。
* 共享状态：读取各子序列句柄，间接写入子序列内部 ``stopped`` 标志。

§2.7 ``get_irq_vif()`` 从 config_db 取 IRQ 接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数从 UVM config_db 查询 ``irq_vif``，查询失败时只报警告，仍返回局部变量 ``vif``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L130-L137``）：

.. code-block:: systemverilog

     // Helper: get IRQ virtual interface from config_db
     function virtual eh2_irq_intf get_irq_vif();
       virtual eh2_irq_intf vif;
       if (!uvm_config_db#(virtual eh2_irq_intf)::get(null, "*", "irq_vif", vif)) begin
         `uvm_warning("vseq", "Could not get IRQ virtual interface")
       end
       return vif;
     endfunction

逐段解释：

* 第 L131-L132 行：函数返回类型是 ``virtual eh2_irq_intf``，局部变量 ``vif`` 用来承接 config_db 查询结果。
* 第 L133-L135 行：查询路径为 ``null, "*", "irq_vif"``，作用域是全局通配；失败时发 ``uvm_warning``，不是 ``uvm_fatal``。
* 第 L136 行：无论查询是否成功都返回 ``vif``。调用方没有额外判空，因此 config_db 未设置时，后续子序列访问 ``irq_vif`` 会面临空句柄风险。

接口关系：

* 被调用：``body()`` 的 IRQ 分支和 IRQ helper tasks。
* 调用：``uvm_config_db::get()``。
* 共享状态：读取 config_db 中的 ``irq_vif``。

§2.8 Directed helper tasks
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 helper task 给 directed test 提供显式启动单个子序列的入口，不经过 ``body()`` 的配置位判断。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L139-L162``）：

.. code-block:: systemverilog

     // Helper tasks for directed stimulus (called from tests)
     virtual task start_irq_raise_single_seq();
       irq_single_h = irq_raise_single_seq::type_id::create("irq_single_h");
       irq_single_h.irq_vif = get_irq_vif();
       irq_single_h.start(null);
     endtask

     virtual task start_irq_raise_seq();
       irq_multi_h = irq_raise_seq::type_id::create("irq_multi_h");
       irq_multi_h.irq_vif = get_irq_vif();
       irq_multi_h.start(null);
     endtask

     virtual task start_nmi_raise_seq();
       irq_nmi_h = irq_raise_nmi_seq::type_id::create("irq_nmi_h");
       irq_nmi_h.irq_vif = get_irq_vif();
       irq_nmi_h.start(null);
     endtask

     virtual task start_irq_drop_seq();
       irq_drop_h = irq_drop_seq::type_id::create("irq_drop_h");
       irq_drop_h.irq_vif = get_irq_vif();
       irq_drop_h.start(null);
     endtask

逐段解释：

* 第 L140-L144 行：``start_irq_raise_single_seq()`` 创建单 IRQ 序列、填入 ``irq_vif`` 并启动。
* 第 L146-L150 行：``start_irq_raise_seq()`` 创建多 IRQ 序列。与 ``body()`` 不同，这里没有设置 ``interval``，因此使用子序列默认值。
* 第 L152-L156 行：``start_nmi_raise_seq()`` 创建 NMI 序列，只通过 ``irq_vif`` 驱动 ``nmi_int``。
* 第 L158-L162 行：``start_irq_drop_seq()`` 创建 drop 序列；这是 ``irq_drop_h`` 在当前文件中被创建的路径。

接口关系：

* 被调用：源注释标明这些任务供 tests 调用；本文件内部没有调用它们。
* 调用：``get_irq_vif()`` 和各 IRQ 序列 ``start(null)``。
* 共享状态：写入 ``irq_single_h``、``irq_multi_h``、``irq_nmi_h``、``irq_drop_h``。

§2.9 Debug helper tasks
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：debug helper task 显式启动 stress 或 single debug 序列，并把 ``vseqr.jtag_seqr`` 注入 ``debug_seq``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L164-L176``）：

.. code-block:: systemverilog

     virtual task start_debug_stress_seq();
       debug_stress_h = debug_seq::type_id::create("debug_stress_h");
       debug_stress_h.jtag_seqr = vseqr.jtag_seqr;
       debug_stress_h.stress_mode = 1;
       debug_stress_h.start(null);
     endtask

     virtual task start_debug_single_seq();
       debug_single_h = debug_seq::type_id::create("debug_single_h");
       debug_single_h.jtag_seqr = vseqr.jtag_seqr;
       debug_single_h.stress_mode = 0;
       debug_single_h.start(null);
     endtask

逐段解释：

* 第 L164-L168 行：stress helper 创建 ``debug_stress_h``，从 ``vseqr`` 取 JTAG sequencer，``stress_mode`` 固定为 1。
* 第 L171-L175 行：single helper 创建 ``debug_single_h``，同样使用 ``vseqr.jtag_seqr``，但 ``stress_mode`` 固定为 0。
* 两个 helper 都没有设置 ``interval``，因此 ``debug_seq`` 继承 ``core_eh2_base_seq`` 的默认 ``interval = 500``，除非调用方再修改句柄。

接口关系：

* 被调用：源注释把 helper task 归类为 directed stimulus 入口。
* 调用：``debug_seq::type_id::create()`` 和 ``debug_seq.start(null)``。
* 共享状态：读取 ``vseqr.jtag_seqr``，写入 ``debug_stress_h``、``debug_single_h``。

§3 旧式基础序列 ``core_eh2_base_seq``
--------------------------------------------------------------------------------

旧序列库以 ``core_eh2_base_seq`` 为公共父类。它提供随机初始延迟、随机事件间隔和停止标志，IRQ、debug、fetch-enable 旧序列都继承它。

§3.1 字段与默认时序参数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：字段定义了事件间隔、初始延迟范围和停止标志。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L24-L35``）：

.. code-block:: systemverilog

   class core_eh2_base_seq extends uvm_sequence;

     `uvm_object_utils(core_eh2_base_seq)

     int unsigned interval = 500;    // Max cycles between events
     int unsigned delay_min = 100;   // Min initial delay (ns)
     int unsigned delay_max = 5000;  // Max initial delay (ns)
     bit            stopped = 0;     // Stop flag

     function new(string name = "core_eh2_base_seq");
       super.new(name);
     endfunction

逐段解释：

* 第 L24-L26 行：基础序列继承 ``uvm_sequence`` 并注册 factory。
* 第 L28-L31 行：``interval`` 是事件间隔上界，``delay_min`` 和 ``delay_max`` 是初始延迟范围，``stopped`` 是循环退出条件。
* 第 L33-L35 行：构造函数只调用父类构造，不随机化字段。

接口关系：

* 被调用：各旧式子序列通过继承读取这些字段和任务。
* 调用：``super.new()``。
* 共享状态：``stopped`` 被父类 ``stop()`` 写入，被子类 ``body()`` 读取。

§3.2 ``rand_delay()`` 与 ``rand_interval()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：两个 task 负责把随机延迟转换成仿真时间等待。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L37-L49``）：

.. code-block:: systemverilog

     // Randomized initial delay
     task rand_delay();
       int d;
       d = $urandom_range(delay_min, delay_max);
       #(d * 1ns);
     endtask

     // Randomized interval between events
     task rand_interval();
       int d;
       d = $urandom_range(1, interval);
       #(d * 10ns);
     endtask

逐段解释：

* 第 L38-L41 行：``rand_delay()`` 在 ``delay_min`` 到 ``delay_max`` 范围内取随机数，并按 ``1ns`` 粒度等待。
* 第 L45-L48 行：``rand_interval()`` 在 ``1`` 到 ``interval`` 范围内取随机数，并按 ``10ns`` 粒度等待；``core_eh2_vseq`` 会把 ``cfg.max_interval`` 写入若干子序列的 ``interval``。

接口关系：

* 被调用：IRQ、debug、fetch-enable 旧序列的 ``body()`` 调用。
* 调用：``$urandom_range`` 和 SystemVerilog delay。
* 共享状态：读取 ``delay_min``、``delay_max``、``interval``。

§3.3 ``stop()`` 与 ``wait_for_stop()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``stop()`` 写停止标志，``wait_for_stop()`` 等待停止标志被写成 1。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L51-L59``）：

.. code-block:: systemverilog

     // Stop the sequence
     virtual task stop();
       stopped = 1;
     endtask

     // Wait for stop (non-blocking check)
     virtual task wait_for_stop();
       wait (stopped);
     endtask

逐段解释：

* 第 L52-L54 行：``stop()`` 不 kill process，只把 ``stopped`` 置为 1。
* 第 L57-L58 行：``wait_for_stop()`` 阻塞直到 ``stopped`` 为 1；当前旧序列库文件中没有其它代码调用它。

接口关系：

* 被调用：``core_eh2_vseq.stop()`` 调用子序列 ``stop()``。
* 调用：不调用其它函数。
* 共享状态：写入或等待 ``stopped``。

§4 IRQ 旧式序列
--------------------------------------------------------------------------------

IRQ 旧式序列都通过 ``virtual eh2_irq_intf irq_vif`` 驱动接口信号。它们不会产生 UVM sequence item，也不使用 ``vseqr.irq_seqr``。

§4.1 ``irq_raise_seq`` 多中断序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``irq_raise_seq`` 每轮随机选择多个外部中断 ID，把对应 ``extintsrc_req`` bit 拉高，等待后清零。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L66-L95``）：

.. code-block:: systemverilog

   class irq_raise_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_seq)

     // Virtual interface to drive interrupts
     virtual eh2_irq_intf irq_vif;

     int unsigned max_irq_id = 127;  // Max external interrupt ID
     int unsigned num_irqs = 3;      // Number of interrupts to raise per event

     function new(string name = "irq_raise_seq");
       super.new(name);
     endfunction

     virtual task body();
       int id;
       rand_delay();
       forever begin
         if (stopped) return;
         // Raise multiple random interrupts
         repeat (num_irqs) begin
           id = $urandom_range(1, max_irq_id);
           irq_vif.extintsrc_req[id] <= 1'b1;
         end
         rand_interval();
         // Drop all
         irq_vif.extintsrc_req <= '0;
         rand_interval();

逐段解释：

* 第 L66-L74 行：类继承 ``core_eh2_base_seq``，保存 IRQ virtual interface，默认最大外部中断 ID 为 127，每次事件默认拉起 3 个 IRQ。
* 第 L80-L84 行：进入 ``body()`` 后先调用 ``rand_delay()``，随后进入无限循环；循环首行检查 ``stopped``。
* 第 L86-L89 行：重复 ``num_irqs`` 次随机生成 ``id``，把 ``irq_vif.extintsrc_req[id]`` 非阻塞赋值为 1。
* 第 L90-L93 行：等待随机间隔后把整条 ``extintsrc_req`` 清零，再等待下一轮间隔。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的多 IRQ 分支或 ``start_irq_raise_seq()``。
* 调用：``rand_delay()``、``rand_interval()``、``$urandom_range``。
* 共享状态：读取 ``irq_vif``、``num_irqs``、``max_irq_id``、``stopped``，写 ``irq_vif.extintsrc_req``。

§4.2 ``irq_raise_single_seq`` 单中断序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``irq_raise_single_seq`` 每轮只随机选择一个外部中断 ID，并单独拉高再拉低该 bit。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L102-L125``）：

.. code-block:: systemverilog

   class irq_raise_single_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_single_seq)

     virtual eh2_irq_intf irq_vif;

     int unsigned max_irq_id = 127;

     function new(string name = "irq_raise_single_seq");
       super.new(name);
     endfunction

     virtual task body();
       int id;
       rand_delay();
       forever begin
         if (stopped) return;
         id = $urandom_range(1, max_irq_id);
         irq_vif.extintsrc_req[id] <= 1'b1;
         rand_interval();
         irq_vif.extintsrc_req[id] <= 1'b0;
         rand_interval();
       end

逐段解释：

* 第 L102-L108 行：类结构与多 IRQ 序列相同，但没有 ``num_irqs`` 字段。
* 第 L114-L118 行：``body()`` 先随机初始延迟，再循环检查 ``stopped``。
* 第 L119-L123 行：每轮随机一个 ``id``，拉高对应 ``extintsrc_req[id]``，等待后只拉低同一个 bit，再等待下一轮。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的单 IRQ 分支或 ``start_irq_raise_single_seq()``。
* 调用：``rand_delay()``、``rand_interval()``、``$urandom_range``。
* 共享状态：读取 ``irq_vif``、``max_irq_id``、``stopped``，写 ``irq_vif.extintsrc_req[id]``。

§4.3 ``irq_raise_nmi_seq`` NMI 序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``irq_raise_nmi_seq`` 周期性拉高和拉低 ``nmi_int``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L132-L151``）：

.. code-block:: systemverilog

   class irq_raise_nmi_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_raise_nmi_seq)

     virtual eh2_irq_intf irq_vif;

     function new(string name = "irq_raise_nmi_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       forever begin
         if (stopped) return;
         irq_vif.nmi_int <= 1'b1;
         rand_interval();
         irq_vif.nmi_int <= 1'b0;
         rand_interval();
       end
     endtask

逐段解释：

* 第 L132-L139 行：NMI 序列只保存 ``irq_vif``，没有 IRQ ID 随机字段。
* 第 L142-L150 行：循环中先检查 ``stopped``，再把 ``nmi_int`` 拉高，等待，拉低，再等待。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的 NMI 分支或 ``start_nmi_raise_seq()``。
* 调用：``rand_delay()``、``rand_interval()``。
* 共享状态：读取 ``irq_vif``、``stopped``，写 ``irq_vif.nmi_int``。

§4.4 ``irq_drop_seq`` 中断清零序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``irq_drop_seq`` 周期性清零所有外部 IRQ、timer、software 和 NMI 信号。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L158-L179``）：

.. code-block:: systemverilog

   class irq_drop_seq extends core_eh2_base_seq;

     `uvm_object_utils(irq_drop_seq)

     virtual eh2_irq_intf irq_vif;

     function new(string name = "irq_drop_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       forever begin
         if (stopped) return;
         // Drop all interrupts
         irq_vif.extintsrc_req <= '0;
         irq_vif.timer_int <= '0;
         irq_vif.soft_int <= '0;
         irq_vif.nmi_int <= 1'b0;
         rand_interval();
       end
     endtask

逐段解释：

* 第 L158-L165 行：drop 序列只需要 ``irq_vif``，不需要随机 ID。
* 第 L168-L177 行：每轮检查 ``stopped`` 后清零 ``extintsrc_req``、``timer_int``、``soft_int`` 和 ``nmi_int``，再等待随机间隔。
* 该序列的 helper task 存在于 ``core_eh2_vseq``，但 ``body()`` 不按 ``cfg.enable_irq_drop_seq`` 自动创建它。

接口关系：

* 被调用：``core_eh2_vseq.start_irq_drop_seq()``。
* 调用：``rand_delay()``、``rand_interval()``。
* 共享状态：读取 ``irq_vif``、``stopped``，写 IRQ interface 的四类中断信号。

§5 Debug 旧式序列
--------------------------------------------------------------------------------

``debug_seq`` 通过 JTAG sequence 的静态 helper ``eh2_jtag_seq::send_write()`` 写 DMI 寄存器。它既可以做有限一次 debug walk，也可以在 stress 模式下循环执行 debug walk。

§5.1 字段与 ``body()`` 调度
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：字段保存 JTAG sequencer 和 stress 模式；``body()`` 决定执行一次 debug walk 还是循环执行。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L186-L213``）：

.. code-block:: systemverilog

   class debug_seq extends core_eh2_base_seq;

     `uvm_object_utils(debug_seq)

     // Sequencer to send JTAG transactions
     uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr;

     bit stress_mode = 0;  // 1 = continuous, 0 = single

     function new(string name = "debug_seq");
       super.new(name);
     endfunction

     virtual task body();
       rand_delay();
       if (stress_mode) begin
         // Continuous debug stimulus for stress tests only.
         forever begin
           if (stopped) return;
           send_debug_command_walk();
           rand_interval();
         end
       end else begin
         // Finite debug stimulus for directed coverage tests. This avoids
         // holding the core in debug mode until the mailbox timeout expires.
         send_debug_command_walk();
       end
     endtask

逐段解释：

* 第 L186-L193 行：``debug_seq`` 继承旧式基础序列，保存 ``jtag_seqr`` 和 ``stress_mode``。``jtag_seqr`` 由 ``core_eh2_vseq`` 从 ``vseqr.jtag_seqr`` 注入。
* 第 L199-L205 行：``body()`` 先执行初始随机延迟；stress 模式下进入无限循环，每轮先检查 ``stopped``，再执行 ``send_debug_command_walk()``。
* 第 L206-L212 行：stress 模式每轮 debug walk 后调用 ``rand_interval()``；非 stress 模式只执行一次 ``send_debug_command_walk()``。

接口关系：

* 被调用：``core_eh2_vseq`` 的 debug 分支和 debug helper tasks。
* 调用：``rand_delay()``、``send_debug_command_walk()``、``rand_interval()``。
* 共享状态：读取 ``stress_mode``、``stopped``、``jtag_seqr``。

§5.2 ``dmi_gap()`` 与 debug walk 序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``dmi_gap()`` 提供固定周期间隔；``send_debug_command_walk()`` 按固定顺序发 DMI 写命令。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L215-L239``）：

.. code-block:: systemverilog

     virtual task dmi_gap(int unsigned cycles = 40);
       repeat (cycles) #(10ns);
     endtask

     virtual task send_debug_command_walk();
       bit [31:0] dccm_addr;
       send_dmactive();
       dmi_gap(20);
       send_halt();
       dmi_gap(120);
       send_core_register_read();
       dmi_gap(160);
       for (int unsigned i = 0; i < 5; i++) begin
         dccm_addr = 32'hf0040000 + (i * 32'h4);
         send_core_local_memory_read(dccm_addr);
         dmi_gap(180);
       end
       send_external_system_bus_read();
       dmi_gap(220);
       send_direct_system_bus_read_write();
       dmi_gap(220);
       send_resume();
       dmi_gap(120);
       clear_resume();
     endtask

逐段解释：

* 第 L215-L217 行：``dmi_gap()`` 用 ``repeat`` 执行 ``cycles`` 次 ``#(10ns)``，默认参数是 40。
* 第 L219-L226 行：debug walk 先激活 debug module，再 halt，再发 core register read 命令，中间插入不同长度的 DMI gap。
* 第 L227-L231 行：循环 5 次，地址从 ``32'hf0040000`` 开始，每次加 4，调用 ``send_core_local_memory_read()``。
* 第 L232-L238 行：随后执行 external system bus read、direct system bus read/write、resume 和 clear resume。

接口关系：

* 被调用：``debug_seq.body()``。
* 调用：``send_dmactive()``、``send_halt()``、``send_core_register_read()``、``send_core_local_memory_read()``、``send_external_system_bus_read()``、``send_direct_system_bus_read_write()``、``send_resume()``、``clear_resume()``。
* 共享状态：通过被调用任务间接读取 ``jtag_seqr``。

§5.3 DMI 基础写命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些小任务把具体 DMI 地址和值交给 ``eh2_jtag_seq::send_write()``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L241-L265``）：

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
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h00221000);
     endtask

     virtual task send_core_local_memory_read(bit [31:0] addr = 32'hf0040000);
       // Debug memory command targeting DCCM. This goes through CORE_CMD_* and
       // exercises the DMA/debug memory path rather than the external SB path.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DATA1, addr);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h02200000);
     endtask

逐段解释：

* 第 L241-L244 行：``send_dmactive()`` 写 ``DMI_DMCONTROL`` 值 ``32'h00000001``。
* 第 L246-L249 行：``send_halt()`` 写 ``DMI_DMCONTROL`` 值 ``32'h80000001``。
* 第 L251-L255 行：``send_core_register_read()`` 写 ``DMI_COMMAND`` 值 ``32'h00221000``。
* 第 L257-L265 行：``send_core_local_memory_read()`` 先把参数 ``addr`` 写入 ``DMI_DATA1``，等待 ``dmi_gap(20)``，再写 ``DMI_COMMAND`` 值 ``32'h02200000``。

接口关系：

* 被调用：``send_debug_command_walk()``。
* 调用：``eh2_jtag_seq::send_write()`` 和 ``dmi_gap()``。
* 共享状态：读取 ``jtag_seqr``。

§5.4 System-bus 与 resume 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些任务覆盖 external system-bus read、direct system-bus read/write 和 resume 清除流程。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L267-L298``）：

.. code-block:: systemverilog

     virtual task send_external_system_bus_read();
       // Debug memory command targeting external AXI memory. This drives
       // SB_CMD_START/SEND/RESP in eh2_dbg and the SB AXI slave.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DATA1, 32'h80000000);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_COMMAND, 32'h02200000);
     endtask

     virtual task send_direct_system_bus_read_write();
       // Direct system-bus register access covers the standalone sb_state FSM.
       // bit 20 readonaddr starts a read when SBADDRESS0 is written.
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBCS, 32'h00100000);
       dmi_gap(20);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBADDRESS0, 32'h80000000);
       dmi_gap(120);
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_SBDATA0, 32'ha5a55a5a);

逐段解释：

* 第 L267-L275 行：``send_external_system_bus_read()`` 写 ``DMI_DATA1`` 为 ``32'h80000000``，等待后写 ``DMI_COMMAND`` 为 ``32'h02200000``。
* 第 L277-L287 行：``send_direct_system_bus_read_write()`` 先写 ``DMI_SBCS`` 为 ``32'h00100000``，再写 ``DMI_SBADDRESS0`` 为 ``32'h80000000``，最后写 ``DMI_SBDATA0`` 为 ``32'ha5a55a5a``。
* 本片段的每次 DMI 写都通过同一个 ``jtag_seqr`` 进入 JTAG agent sequencer。

接口关系：

* 被调用：``send_debug_command_walk()``。
* 调用：``eh2_jtag_seq::send_write()`` 和 ``dmi_gap()``。
* 共享状态：读取 ``jtag_seqr``。

§5.5 ``send_resume()`` 与 ``clear_resume()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这两个任务分别写 resume 请求值和清除值。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L290-L298``）：

.. code-block:: systemverilog

     virtual task send_resume();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h40000001);
     endtask

     virtual task clear_resume();
       eh2_jtag_seq::send_write(jtag_seqr,
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h00000001);
     endtask

逐段解释：

* 第 L290-L293 行：``send_resume()`` 写 ``DMI_DMCONTROL`` 值 ``32'h40000001``。
* 第 L295-L298 行：``clear_resume()`` 写 ``DMI_DMCONTROL`` 值 ``32'h00000001``。

接口关系：

* 被调用：``send_debug_command_walk()``。
* 调用：``eh2_jtag_seq::send_write()``。
* 共享状态：读取 ``jtag_seqr``。

§6 Fetch-enable 旧式序列
--------------------------------------------------------------------------------

``fetch_enable_seq`` 通过 ``fetch_enable_intf`` 驱动 ``fetch_enable``。当前虚拟序列创建它时只设置 ``interval``，没有在同一文件内给 ``fetch_vif`` 赋值。

§6.1 ``fetch_enable_seq.body()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该序列循环拉低和拉高 ``fetch_enable``，但每次写前都检查 ``fetch_vif`` 非空。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L305-L328``）：

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
         if (stopped) return;
         // Disable fetch
         if (fetch_vif != null)
           fetch_vif.fetch_enable <= 1'b0;
         rand_interval();
         // Re-enable fetch
         if (fetch_vif != null)
           fetch_vif.fetch_enable <= 1'b1;
         rand_interval();
       end
     endtask

逐段解释：

* 第 L305-L313 行：类保存 ``fetch_vif``，构造函数没有从 config_db 获取它。
* 第 L315-L321 行：``body()`` 初始延迟后进入循环；``fetch_vif`` 非空时把 ``fetch_enable`` 拉低。
* 第 L322-L326 行：等待随机间隔后，``fetch_vif`` 非空时把 ``fetch_enable`` 拉高，再等待下一轮。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 的 fetch 分支。
* 调用：``rand_delay()``、``rand_interval()``。
* 共享状态：读取 ``fetch_vif``、``stopped``，写 ``fetch_vif.fetch_enable``。

§7 新式序列库 ``core_eh2_new_seq_lib.sv``
--------------------------------------------------------------------------------

新式序列库提供另一组继承自 ``core_eh2_base_new_seq`` 的序列。它们被 ``core_eh2_test_pkg.sv`` include，但 ``core_eh2_vseq.sv`` 当前没有创建这些新式序列。

§7.1 ``core_eh2_base_new_seq`` 字段与约束
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：新式基础序列把停止状态、完成状态、随机延迟、调度模式和迭代次数集中在一个模板基类中。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L17-L48``）：

.. code-block:: systemverilog

   class core_eh2_base_new_seq #(type REQ = uvm_sequence_item) extends uvm_sequence #(REQ);

     `uvm_object_param_utils(core_eh2_base_new_seq#(REQ))

     // Virtual interface for DUT probing
     virtual eh2_dut_probe_if dut_vif;

     bit          stop_seq;
     bit          seq_finished;

     rand bit     zero_delays;
     int unsigned zero_delay_pct = 50;
     constraint zero_delays_c {
       zero_delays dist {1 :/ zero_delay_pct,
                         0 :/ 100 - zero_delay_pct};
     }

     rand int unsigned stimulus_delay_cycles;
     int unsigned stimulus_delay_cycles_min = 200;
     int unsigned stimulus_delay_cycles_max = 400;
     constraint reasonable_delay_c {
       stimulus_delay_cycles inside {[stimulus_delay_cycles_min : stimulus_delay_cycles_max]};
     }

     // Scheduling mode
     run_type_e iteration_modes = MultipleRuns;

     rand int unsigned iteration_cnt;
     int unsigned iteration_cnt_max = 20;
     constraint iterations_cnt_c {
       iteration_cnt inside {[1:iteration_cnt_max]};
     }

逐段解释：

* 第 L17-L22 行：模板类继承 ``uvm_sequence#(REQ)``，并声明 ``dut_vif``。
* 第 L24-L31 行：``stop_seq`` 和 ``seq_finished`` 是停止握手状态；``zero_delays`` 通过 ``zero_delay_pct`` 分布约束随机化。
* 第 L34-L39 行：``stimulus_delay_cycles`` 被限制在 ``stimulus_delay_cycles_min`` 到 ``stimulus_delay_cycles_max`` 之间。
* 第 L42-L48 行：默认调度模式是 ``MultipleRuns``，随机迭代次数 ``iteration_cnt`` 被限制在 1 到 ``iteration_cnt_max``。

接口关系：

* 被调用：新式子序列继承该基类。
* 调用：声明阶段不调用任务。
* 共享状态：``iteration_modes`` 依赖 ``core_eh2_test_pkg.sv`` 中的 ``run_type_e``。

§7.2 ``new()`` 与 ``pre_body()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造函数从 config_db 读取 ``probe_vif``；``pre_body()`` 统一随机化基类字段。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L50-L59``）：

.. code-block:: systemverilog

     function new(string name = "");
       super.new(name);
       if (!uvm_config_db#(virtual eh2_dut_probe_if)::get(null, "", "probe_vif", dut_vif)) begin
         `uvm_warning(get_name(), "Cannot get probe_vif for new_seq_lib")
       end
     endfunction

     virtual task pre_body();
       this.randomize();
     endtask

逐段解释：

* 第 L50-L55 行：构造函数读取 ``probe_vif``。查询失败时发 warning，不中止仿真。
* 第 L57-L59 行：``pre_body()`` 调用 ``this.randomize()``，因此 ``zero_delays``、``stimulus_delay_cycles`` 和 ``iteration_cnt`` 在 body 前被随机化。

接口关系：

* 被调用：新式子序列对象构造和 UVM pre-body 流程。
* 调用：``uvm_config_db::get()``、``uvm_warning``、``randomize()``。
* 共享状态：读取 config_db，写 ``dut_vif`` 和随机字段。

§7.3 ``body()`` 调度模式
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：新式基础 ``body()`` 根据 ``iteration_modes`` 选择单次、多次或无限执行 ``drive_stimulus()``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L61-L86``）：

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
             drive_stimulus();
           end
         end
         InfiniteRuns: begin
           while (!stop_seq) begin
             drive_stimulus();
           end
         end
         default: begin
           `uvm_fatal(get_name(), "Invalid run type")
         end
       endcase
       seq_finished = 1'b1;
     endtask

逐段解释：

* 第 L61-L64 行：打印调度模式，然后清 ``stop_seq`` 和 ``seq_finished``。
* 第 L65-L68 行：``SingleRun`` 只调用一次 ``drive_stimulus()``。
* 第 L69-L75 行：``MultipleRuns`` 从 0 循环到 ``iteration_cnt``，每轮先检查 ``stop_seq``，再打印迭代号并驱动一次 stimulus。
* 第 L76-L80 行：``InfiniteRuns`` 在 ``stop_seq`` 为 0 时持续调用 ``drive_stimulus()``。
* 第 L81-L85 行：非法调度模式触发 ``uvm_fatal``；正常离开 ``case`` 后设置 ``seq_finished``。

接口关系：

* 被调用：新式子序列启动后的 UVM body 流程。
* 调用：``drive_stimulus()``、``uvm_info``、``uvm_fatal``。
* 共享状态：读取 ``iteration_modes``、``iteration_cnt``、``stop_seq``，写 ``seq_finished``。

§7.4 ``drive_stimulus()``、``send_req()`` 与 ``stop()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``drive_stimulus()`` 处理可选延迟并调用子类实现；基类 ``send_req()`` 是必须覆写的 fatal stub；``stop()`` 请求退出并等待完成。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L88-L104``）：

.. code-block:: systemverilog

     task drive_stimulus();
       if (!zero_delays) begin
         `uvm_info(get_name(), $sformatf("Delay: %0d cycles", stimulus_delay_cycles), UVM_HIGH)
         #($urandom_range(stimulus_delay_cycles_min, stimulus_delay_cycles_max) * 10ns);
       end
       send_req();
     endtask

     virtual task send_req();
       `uvm_fatal(get_name(), "send_req() must be implemented in subclass")
     endtask

     virtual task stop();
       stop_seq = 1'b1;
       `uvm_info(get_name(), "Stopping sequence", UVM_MEDIUM)
       wait (seq_finished == 1'b1);
     endtask

逐段解释：

* 第 L88-L93 行：``zero_delays`` 为 0 时先等待一个随机周期数，随机范围使用 ``stimulus_delay_cycles_min`` 和 ``stimulus_delay_cycles_max``；随后调用 ``send_req()``。
* 第 L96-L98 行：基类 ``send_req()`` 只报 fatal，要求子类覆写。
* 第 L100-L103 行：``stop()`` 把 ``stop_seq`` 置 1，打印 log，然后等待 ``seq_finished`` 为 1。

接口关系：

* 被调用：``body()`` 调用 ``drive_stimulus()``；外部可调用 ``stop()``。
* 调用：``$urandom_range``、``send_req()``、``uvm_info``、``uvm_fatal``。
* 共享状态：读取 ``zero_delays`` 和延迟上下界，写 ``stop_seq``，等待 ``seq_finished``。

§7.5 ``irq_new_seq``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：新式 IRQ 序列一次随机拉起 1 到 5 个外部中断，保持随机持续时间后清除外部 IRQ bit。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L111-L146``）：

.. code-block:: systemverilog

   class irq_new_seq extends core_eh2_base_new_seq #(uvm_sequence_item);

     `uvm_object_utils(irq_new_seq)

     virtual eh2_irq_intf irq_vif;

     rand int unsigned num_interrupts;
     constraint num_interrupts_c { num_interrupts inside {[1:5]}; }

     rand int unsigned irq_duration;
     constraint irq_duration_c { irq_duration inside {[10:100]}; }

     function new(string name = "irq_new_seq");
       super.new(name);
       if (!uvm_config_db#(virtual eh2_irq_intf)::get(null, "", "irq_vif", irq_vif))
         `uvm_warning(get_name(), "Cannot get irq_vif")
     endfunction

     task send_req();
       if (irq_vif == null) return;

       for (int i = 0; i < num_interrupts; i++) begin
         int irq_id;
         irq_id = $urandom_range(1, 127);
         irq_vif.extintsrc_req[irq_id] = 1'b1;

逐段解释：

* 第 L111-L121 行：``irq_new_seq`` 继承新式基础序列，保存 ``irq_vif``，随机中断数量限制为 1 到 5，持续时间限制为 10 到 100。
* 第 L123-L127 行：构造函数从 config_db 读取 ``irq_vif``，失败只发 warning。
* 第 L129-L135 行：``send_req()`` 若 ``irq_vif`` 为空直接返回；否则循环 ``num_interrupts`` 次，随机 ID 范围固定为 1 到 127，并拉高对应 ``extintsrc_req``。

接口关系：

* 被调用：若外部创建并启动 ``irq_new_seq``，由新式基类 ``drive_stimulus()`` 调用 ``send_req()``。
* 调用：``uvm_config_db::get()``、``$urandom_range``。
* 共享状态：读取 ``irq_vif``、``num_interrupts``、``irq_duration``，写 ``irq_vif.extintsrc_req``。

§7.6 ``irq_new_seq`` 清除阶段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段展示 ``irq_new_seq.send_req()`` 后半段如何等待持续时间并清除外部 IRQ。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L136-L146``）：

.. code-block:: systemverilog

         `uvm_info(get_name(), $sformatf("Asserting IRQ %0d", irq_id), UVM_MEDIUM)
       end

       #(irq_duration * 10ns);

       // Drop all
       for (int i = 1; i <= 127; i++) begin
         irq_vif.extintsrc_req[i] = 1'b0;
       end
       `uvm_info(get_name(), "Dropped all interrupts", UVM_MEDIUM)
     endtask

逐段解释：

* 第 L136-L137 行：每个被拉高的 IRQ ID 都输出一条 UVM log。
* 第 L139 行：保持时间按 ``irq_duration * 10ns`` 计算。
* 第 L142-L144 行：清除外部 IRQ 范围 1 到 127。
* 第 L145 行：清除完成后输出 log。

接口关系：

* 被调用：``irq_new_seq.send_req()`` 内部连续执行。
* 调用：``uvm_info``。
* 共享状态：读取 ``irq_duration``，写 ``irq_vif.extintsrc_req[1:127]``。

§7.7 ``debug_new_seq``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：新式 debug 序列当前只打印 debug pulse 长度并等待随机时间；代码中声明了 ``jtag_vif``，但 ``send_req()`` 未直接驱动它。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L153-L170``）：

.. code-block:: systemverilog

   class debug_new_seq extends core_eh2_base_new_seq #(uvm_sequence_item);

     `uvm_object_utils(debug_new_seq)

     virtual eh2_jtag_intf jtag_vif;

     rand int unsigned pulse_length_cycles;
     constraint pulse_length_c { pulse_length_cycles inside {[75:500]}; }

     function new(string name = "debug_new_seq");
       super.new(name);
     endfunction

     task send_req();
       `uvm_info(get_name(), $sformatf("Debug pulse: %0d cycles", pulse_length_cycles), UVM_MEDIUM)
       // Use JTAG agent sequencer for debug requests
       #($urandom_range(75, 500) * 10ns);
     endtask

逐段解释：

* 第 L153-L160 行：类声明 ``jtag_vif`` 和随机 ``pulse_length_cycles``，约束范围是 75 到 500。
* 第 L162-L164 行：构造函数只调用父类构造，没有读取 ``jtag_vif``。
* 第 L166-L169 行：``send_req()`` 打印 ``pulse_length_cycles``，随后等待 ``$urandom_range(75, 500) * 10ns``。当前片段没有 JTAG 写操作。

接口关系：

* 被调用：若外部创建并启动 ``debug_new_seq``，由新式基类 ``drive_stimulus()`` 调用。
* 调用：``uvm_info``、``$urandom_range``。
* 共享状态：读取 ``pulse_length_cycles``；``jtag_vif`` 当前未被 ``send_req()`` 读取。

§7.8 ``memory_error_seq``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该序列记录 memory error 注入参数并等待随机时间；实际注入由 AXI4 driver 配置路径处理。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L177-L193``）：

.. code-block:: systemverilog

   class memory_error_seq extends core_eh2_base_new_seq #(uvm_sequence_item);

     `uvm_object_utils(memory_error_seq)

     error_type_e error_side = PickErr;
     int unsigned error_pct = 10;  // Percentage chance of error injection

     function new(string name = "memory_error_seq");
       super.new(name);
     endfunction

     task send_req();
       `uvm_info(get_name(), $sformatf("Memory error injection (side=%s, pct=%0d)",
         error_side.name(), error_pct), UVM_MEDIUM)
       // Error injection is handled by the AXI4 driver when configured
       #($urandom_range(100, 500) * 10ns);
     endtask

逐段解释：

* 第 L177-L182 行：``error_side`` 默认 ``PickErr``，``error_pct`` 默认 10。
* 第 L184-L186 行：构造函数只调用父类构造。
* 第 L188-L192 行：``send_req()`` 打印 ``error_side`` 和 ``error_pct``，随后等待 100 到 500 个 10ns 单位的随机时间。注释说明 error injection 由 AXI4 driver 在配置后处理。

接口关系：

* 被调用：若外部创建并启动 ``memory_error_seq``，由新式基类 ``drive_stimulus()`` 调用。
* 调用：``uvm_info``、``$urandom_range``。
* 共享状态：读取 ``error_side``、``error_pct``。

§7.9 ``fetch_enable_new_seq``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：新式 fetch-enable 序列从 config_db 获取 ``fetch_vif``，在 ``send_req()`` 中拉低再拉高 ``fetch_enable``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:L200-L223``）：

.. code-block:: systemverilog

   class fetch_enable_new_seq extends core_eh2_base_new_seq #(uvm_sequence_item);

     `uvm_object_utils(fetch_enable_new_seq)

     virtual fetch_enable_intf fetch_vif;

     function new(string name = "fetch_enable_new_seq");
       super.new(name);
       if (!uvm_config_db#(virtual fetch_enable_intf)::get(null, "", "fetch_vif", fetch_vif))
         `uvm_warning(get_name(), "Cannot get fetch_vif")
     endfunction

     task send_req();
       if (fetch_vif == null) return;

       // Disable fetch
       fetch_vif.fetch_enable = 1'b0;
       `uvm_info(get_name(), "Fetch disabled", UVM_MEDIUM)
       #($urandom_range(10, 100) * 10ns);

       // Re-enable fetch
       fetch_vif.fetch_enable = 1'b1;
       `uvm_info(get_name(), "Fetch enabled", UVM_MEDIUM)
     endtask

逐段解释：

* 第 L200-L209 行：构造函数从 config_db 读取 ``fetch_vif``，失败时 warning。
* 第 L212-L213 行：``send_req()`` 先判空，接口不存在时直接返回。
* 第 L216-L218 行：把 ``fetch_enable`` 写成 0，打印 log，然后等待 10 到 100 个 10ns 单位的随机时间。
* 第 L221-L222 行：把 ``fetch_enable`` 写回 1，并打印启用 log。

接口关系：

* 被调用：若外部创建并启动 ``fetch_enable_new_seq``，由新式基类 ``drive_stimulus()`` 调用。
* 调用：``uvm_config_db::get()``、``uvm_info``、``$urandom_range``。
* 共享状态：读取 ``fetch_vif``，写 ``fetch_vif.fetch_enable``。

§8 Virtual sequencer 与环境接线
--------------------------------------------------------------------------------

``core_eh2_vseq`` 依赖 ``core_eh2_vseqr`` 提供 JTAG sequencer。IRQ 旧序列虽然通过 virtual interface 驱动，但环境仍把 IRQ agent sequencer 接到 ``vseqr``。

§8.1 ``core_eh2_vseqr`` 只保存 sequencer 句柄
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``core_eh2_vseqr`` 是一个轻量 UVM sequencer，内部只声明三个下游 sequencer 句柄。

关键代码（``dv/uvm/core_eh2/env/core_eh2_vseqr.sv:L7-L18``）：

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

逐段解释：

* 第 L7-L9 行：``core_eh2_vseqr`` 继承 ``uvm_sequencer``，并注册为 component。
* 第 L12-L14 行：保存 IRQ、JTAG 和 halt/run 三个 sequencer 句柄。当前 ``core_eh2_vseq`` 只读取 ``jtag_seqr``。
* 第 L16-L18 行：构造函数只调用父类构造，不创建子 sequencer。

接口关系：

* 被调用：``core_eh2_env.build_phase()`` 创建该 component。
* 调用：``super.new()``。
* 共享状态：句柄由 ``core_eh2_env.connect_phase()`` 写入，被虚拟序列读取。

§8.2 环境创建 ``vseqr``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：环境在 build phase 创建 ``vseqr``，同时创建 IRQ、JTAG、halt/run 等 agent。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L66-L97``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       `uvm_info("env", cfg.convert2string(), UVM_LOW)

       // Virtual sequencer
       vseqr = core_eh2_vseqr::type_id::create("vseqr", this);

       // AXI4 agents — active when error injection is enabled, passive otherwise
       lsu_agent = axi4_agent#(`RV_LSU_BUS_TAG)::type_id::create("lsu_agent", this);
       if (cfg.enable_axi4_error_inject) begin
         uvm_config_db#(uvm_active_passive_enum)::set(this, "lsu_agent", "is_active", UVM_ACTIVE);
       end else begin
         uvm_config_db#(uvm_active_passive_enum)::set(this, "lsu_agent", "is_active", UVM_PASSIVE);
       end

       ifu_agent = axi4_agent#(`RV_IFU_BUS_TAG)::type_id::create("ifu_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "ifu_agent", "is_active", UVM_PASSIVE);

       sb_agent = axi4_agent#(`RV_SB_BUS_TAG)::type_id::create("sb_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "sb_agent", "is_active", UVM_PASSIVE);

       // Interrupt agent (active)
       irq_agent = eh2_irq_agent::type_id::create("irq_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "irq_agent", "is_active", UVM_ACTIVE);

       // JTAG agent (active)
       jtag_agent = eh2_jtag_agent::type_id::create("jtag_agent", this);
       uvm_config_db#(uvm_active_passive_enum)::set(this, "jtag_agent", "is_active", UVM_ACTIVE);

逐段解释：

* 第 L66-L71 行：``build_phase`` 先打印 ``cfg.convert2string()``，然后创建 ``vseqr``。
* 第 L74-L85 行：创建 LSU、IFU 和 SB 三个 AXI4 agent。LSU 根据 ``cfg.enable_axi4_error_inject`` 选择 active/passive，IFU 和 SB 固定 passive。
* 第 L88-L93 行：创建 IRQ 和 JTAG agent，并把两者配置为 ``UVM_ACTIVE``。
* 第 L96-L97 行：创建 halt/run agent 并配置为 ``UVM_ACTIVE``；该 agent 的 sequencer 稍后也接入 ``vseqr``。

接口关系：

* 被调用：UVM build phase。
* 调用：多个 component 的 ``type_id::create()`` 和 ``uvm_config_db::set()``。
* 共享状态：写环境成员 ``vseqr``、``irq_agent``、``jtag_agent``、``halt_run_agt``。

§8.3 ``connect_phase()`` 接入下游 sequencer
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：connect phase 把 agent 内部 sequencer 写入 ``vseqr``，使虚拟序列可以通过 ``vseqr`` 访问 JTAG sequencer。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env.sv:L169-L173``）：

.. code-block:: systemverilog

     // Wire sub-sequencers to virtual sequencer
     vseqr.irq_seqr      = irq_agent.sequencer;
     vseqr.jtag_seqr     = jtag_agent.sequencer;
     vseqr.halt_run_seqr = halt_run_agt.sequencer;
   endfunction

逐段解释：

* 第 L170 行：IRQ agent sequencer 被写入 ``vseqr.irq_seqr``。当前旧式 IRQ 序列通过 ``irq_vif`` 驱动，不读取该句柄。
* 第 L171 行：JTAG agent sequencer 被写入 ``vseqr.jtag_seqr``。``core_eh2_vseq`` 的 debug 分支读取该句柄，并写入 ``debug_seq.jtag_seqr``。
* 第 L172 行：halt/run agent sequencer 被写入 ``vseqr.halt_run_seqr``。当前 ``core_eh2_vseq`` 文件没有读取它。

接口关系：

* 被调用：UVM connect phase。
* 调用：不调用其它函数。
* 共享状态：读取 agent 内部 ``sequencer``，写 ``vseqr`` 三个句柄。

§9 配置位与 plusarg
--------------------------------------------------------------------------------

虚拟序列读取 ``core_eh2_env_cfg`` 的配置位。配置对象由环境构造函数创建，由 plusarg 覆盖默认值。

§9.1 刺激控制字段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：``core_eh2_env_cfg`` 用 bit 字段表示哪些序列允许启动。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L27-L40``）：

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

逐段解释：

* 第 L28-L31 行：IRQ 相关字段分为单 IRQ、多 IRQ、NMI 和 drop。``core_eh2_vseq.body()`` 使用前三个字段，drop 字段只在配置对象中存在。
* 第 L34-L36 行：debug 字段分为通用 debug、stress debug 和 single debug。当前虚拟序列用 ``enable_debug_seq || enable_debug_stress`` 控制 ``debug_stress_h``，用 ``enable_debug_single`` 控制 ``debug_single_h``。
* 第 L39 行：``enable_fetch_toggle`` 控制 ``fetch_enable_seq`` 是否创建。

接口关系：

* 被调用：``core_eh2_vseq.body()`` 读取这些字段。
* 调用：不调用函数。
* 共享状态：默认值均为 0，由 plusarg 读取逻辑覆盖。

§9.2 plusarg 读取与派生配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造函数读取 stimulus 相关 plusarg，并在单 IRQ 使能时派生打开 drop 配置位。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L96-L135``）：

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
       void'($value$plusargs("enable_axi4_error_inject=%0d", enable_axi4_error_inject));
       void'($value$plusargs("axi4_error_pct=%d", axi4_error_pct));
       void'($value$plusargs("enable_cosim=%0d", enable_cosim));
       void'($value$plusargs("disable_cosim=%0d", disable_cosim));

逐段解释：

* 第 L96-L98 行：构造函数先调用父类构造，再进入 plusarg 读取。
* 第 L99-L107 行：读取 IRQ、debug 和 fetch-enable 相关 plusarg。``enable_irq_seq`` 是 ``enable_irq_single_seq`` 的别名式入口，因为二者写入同一个字段。
* 第 L108-L111 行：本片段继续读取 AXI4 error injection 和 cosim 开关；这些不是虚拟序列直接读取的字段，但同属环境配置对象。

接口关系：

* 被调用：``core_eh2_env`` 构造函数创建 ``cfg`` 时执行。
* 调用：``$value$plusargs``。
* 共享状态：写 ``enable_irq_single_seq``、``enable_irq_multiple_seq``、``enable_irq_nmi_seq``、``enable_irq_drop_seq``、``enable_debug_seq``、``enable_debug_stress``、``enable_debug_single``、``enable_fetch_toggle``。

§9.3 ``max_interval`` 和 ``enable_irq_drop_seq`` 派生
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该片段读取 ``max_interval``，并在单 IRQ 序列使能时自动打开 drop 配置位。

关键代码（``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L117-L135``）：

.. code-block:: systemverilog

       void'($value$plusargs("max_interval=%d", max_interval));
       void'($value$plusargs("timeout_ns=%d", timeout_ns));
       void'($value$plusargs("max_cycles=%d", max_cycles));
       void'($value$plusargs("bin=%s", binary));
       void'($value$plusargs("bin_cosim=%s", cosim_binary));
       void'($value$plusargs("boot_addr=%h", boot_addr));
       void'($value$plusargs("irq_delay_min=%d", irq_delay_min));
       void'($value$plusargs("irq_delay_max=%d", irq_delay_max));
       void'($value$plusargs("debug_delay_min=%d", debug_delay_min));
       void'($value$plusargs("debug_delay_max=%d", debug_delay_max));

       // If disable_cosim is set, override enable_cosim
       if (disable_cosim) enable_cosim = 0;

       // If enable_irq_seq is set, enable single + drop IRQ sequences
       // (multiple and NMI must be enabled independently)
       if (enable_irq_single_seq) begin
         enable_irq_drop_seq = 1;
       end

逐段解释：

* 第 L117 行：``max_interval`` 由 ``+max_interval=`` 覆盖，随后 ``core_eh2_vseq`` 把它写入旧式子序列的 ``interval``。
* 第 L118-L126 行：同一个构造函数还读取 timeout、binary、boot address、IRQ/debug 延迟范围等配置。
* 第 L128-L129 行：``disable_cosim`` 为 1 时强制 ``enable_cosim`` 为 0。
* 第 L131-L135 行：``enable_irq_single_seq`` 为 1 时，配置对象把 ``enable_irq_drop_seq`` 置 1。当前虚拟序列的 ``body()`` 没有自动读取 ``enable_irq_drop_seq`` 创建 drop 序列。

接口关系：

* 被调用：``core_eh2_env_cfg.new()`` 内部连续执行。
* 调用：``$value$plusargs``。
* 共享状态：写 ``max_interval``、``enable_cosim``、``enable_irq_drop_seq`` 等字段。

§10 时序与停止关系
--------------------------------------------------------------------------------

``core_eh2_vseq.body()`` 使用 ``join_none``，而旧式子序列大多是 ``forever`` 循环。因此长期运行序列的结束依赖外部停止请求或仿真结束。

.. code-block:: text

   start_vseq()
       |
       v
   core_eh2_vseq.body()
       |
       +-- fork branch: irq seq forever loop
       +-- fork branch: debug_seq finite or forever loop
       +-- fork branch: fetch seq forever loop
       |
       +-- join_none returns from body
       |
       v
   later: core_eh2_vseq.stop()
       |
       +-- child.stop() sets stopped = 1
       +-- child loop exits when it next checks stopped

逐段解释：

* ``join_none`` 的直接证据在 ``core_eh2_vseq.sv:L116``，它表示父 ``body()`` 不等待分支结束。
* 旧式 IRQ、NMI、drop 和 fetch-enable 序列均有 ``forever`` 循环，并在循环开头检查 ``stopped``。
* ``debug_seq`` 在 ``stress_mode`` 为 1 时也进入 ``forever`` 循环；非 stress 模式只执行一次 debug walk。
* ``core_eh2_vseq.stop()`` 只能调用已经创建且句柄非空的子序列；如果某个分支没有根据配置创建，对应句柄保持空，不会被停止。

§11 参考资料
--------------------------------------------------------------------------------

* 关联章节：:doc:`env`、:doc:`tests`、:doc:`irq_agent`、:doc:`jtag_agent`
* 关联架构章节：:ref:`vseq_library`、:ref:`agent_irq`、:ref:`agent_jtag`
* 关联 ADR：:ref:`adr-0007`、:ref:`adr-0008`
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_vseq.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_vseqr.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env.sv``
* 源文件绝对路径：``/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_cfg.sv``
