.. _tests_library:
.. _05_verification_arch/tests_library:

测试库 — 架构桥接说明
================================================================================

:status: draft
:source: dv/uvm/core_eh2/tests/
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  测试库边界
--------------------------------------------------------------------------------

``dv/uvm/core_eh2/tests/`` 是 UVM test class、virtual sequence、directed
stimulus helper、integrity fault-injection test 和 test-level sign-off 单元测试的
汇聚目录。它不直接描述 RTL，也不生成 riscv-dv assembly；它接收回归脚本传入的
``rtl_test``、binary、``sim_opts`` 和 env_cfg plusarg，把这些信息转换成 UVM
testbench 中的 env、vseq、mailbox completion 和 cosim 配置。

.. code-block:: text

   YAML test entry
     |  test / test_srcs / gen_test / rtl_test / sim_opts / cosim
     v
   regression metadata + run_rtl.py
     |
     v
   core_eh2_tb_top.run_test(<rtl_test>)
     |
     v
   core_eh2_test_pkg
     |-- core_eh2_report_server
     |-- core_eh2_seq_lib / core_eh2_new_seq_lib
     |-- core_eh2_vseq
     |-- core_eh2_base_test
     |-- core_eh2_test_lib
     `-- core_eh2_intg_test_lib
          |
          v
   env + agents + mailbox + cosim scoreboard

**逐段解释**：

* 第一层是 YAML：``riscv_dv_extension/testlist.yaml`` 和
  ``directed_tests/*.yaml`` 把 ``rtl_test`` 写成 ``core_eh2_*_test`` 类名。
* 第二层是 UVM package：``core_eh2_test_pkg.sv`` 用 include 顺序把 report
  server、sequence、vseq、base test、常规 test library 和 integrity test library
  拉进同一个 package。
* 第三层是 base test：``core_eh2_base_test`` 统一完成 env 创建、binary load、
  cosim config、vseq 启动和 mailbox/timeout completion。
* 派生类只在需要时覆盖 ``build_phase()``、``run_phase()`` 或 ``start_vseq()``。
  它们通常不重写 env 连接，而是改 ``env_cfg`` 开关或 fork 背景 IRQ/debug 刺激。
* integrity 类不使用普通 ``run_phase`` 结束路径；它们在 ``main_phase`` 中通过
  ``uvm_hdl_*`` 对 RTL 内部路径做短脉冲 force/read/release，并显式关闭 cosim。

**接口关系**：

* **被调用**：仿真 filelist 编译 ``core_eh2_test_pkg.sv``，``run_test()`` 按
  ``rtl_test`` 字符串实例化对应 UVM test。
* **调用**：test class 创建 ``core_eh2_env``、启动 ``core_eh2_vseq``、调用
  IRQ/JTAG sequence helper 和 ``tb_vif`` mailbox/memory helper。
* **共享状态**：``env_cfg``、``tb_vif``、``halt_run_vif``、``mailbox_test_done``、
  ``env.vseqr`` 和 ``env.cosim_agt.scoreboard`` 是 test 与 env 之间的核心共享面。

§2  package 与 report server
--------------------------------------------------------------------------------

§2.1  ``core_eh2_test_pkg.sv`` — 编译边界和 include 顺序
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该 package 定义测试库的编译边界，导入 env/agent package，声明测试库
共享类型，并按顺序 include 测试相关 SV 文件。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L9-L18``）：

.. code-block:: systemverilog

   package core_eh2_test_pkg;
   
     import uvm_pkg::*;
     import core_eh2_env_pkg::*;
     import axi4_agent_pkg::*;
     import eh2_trace_agent_pkg::*;
     import eh2_irq_agent_pkg::*;
     import eh2_jtag_agent_pkg::*;
     import eh2_cosim_agent_pkg::*;
     import eh2_halt_run_agent_pkg::*;

**逐段解释**：

* 第 L9 行：package 名称是 ``core_eh2_test_pkg``，这是 testbench filelist 编译测试库的
  顶层 SV package。
* 第 L11-L18 行：package 导入 UVM、env、AXI4、trace、IRQ、JTAG、cosim 和 halt/run
  package。后续 include 的 test 和 sequence 因此可以直接引用这些 class/type。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L20-L49``）：

.. code-block:: systemverilog

     // Instruction tracking type (used by directed tests)
     typedef struct {
       bit [6:0]  opcode;
       bit [2:0]  funct3;
       bit [6:0]  funct7;
       bit [11:0] system_imm;
     } instr_t;
   
     // Run scheduling modes for new_seq_lib
     typedef enum bit [1:0] {
       SingleRun,    // Single iteration
       InfiniteRuns, // Run forever until stop is specified
       MultipleRuns  // Multiple runs with configurable iteration count
     } run_type_e;

**逐段解释**：

* 第 L21-L26 行：``instr_t`` 保存 opcode、funct3、funct7 和 system immediate，
  用于 directed test 中的 instruction 类型去重。
* 第 L29-L33 行：``run_type_e`` 给 new-style sequence 定义单次、无限次和多次运行
  三种调度模式。
* 第 L36-L40 行：``error_type_e`` 定义 memory error sequence 可选择的 instruction
  side、data side 或随机选择。
* 第 L42-L48 行：include 顺序先是 report server 和 sequence，再是 vseq、base
  test、常规 test library，最后是 integrity test library。这个顺序保证派生测试类
  可以继承已经 include 的 ``core_eh2_base_test``。

**接口关系**：

* **被调用**：``dv/uvm/core_eh2/eh2_tb.f`` 编译该 package。
* **调用**：SV preprocessor include 多个本目录文件。
* **共享状态**：``instr_t``、``run_type_e`` 和 ``error_type_e`` 被 test library 与
  sequence library 共享。

§2.2  ``core_eh2_report_server`` — UVM 总结转 PASS/FAIL 字符串
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：自定义 report server 在 UVM summarize 阶段读取 error/fatal 计数，打印
``EH2 UVM TEST PASSED`` 或 ``EH2 UVM TEST FAILED``，供日志检查脚本识别。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_report_server.sv:L7-L24``）：

.. code-block:: systemverilog

   class core_eh2_report_server extends uvm_default_report_server;
   
     function new(string name = "");
       super.new(name);
     endfunction
   
     function void report_summarize(UVM_FILE file = 0);
       int error_count;
       error_count = get_severity_count(UVM_ERROR);
       error_count = get_severity_count(UVM_FATAL) + error_count;
   
       if (error_count == 0) begin
         $display("\n--- EH2 UVM TEST PASSED ---\n");
       end else begin

**逐段解释**：

* 第 L7-L11 行：class 继承 ``uvm_default_report_server``，构造函数只调用父类。
* 第 L13-L17 行：``report_summarize()`` 读取 ``UVM_ERROR`` 计数，再加
  ``UVM_FATAL`` 计数，形成最终 ``error_count``。
* 第 L18-L22 行：``error_count`` 为 0 时打印 PASS，否则打印 FAIL。
* 第 L23 行：函数最后调用父类 ``report_summarize(file)``，保留 UVM 默认统计输出。

**接口关系**：

* **被调用**：``core_eh2_base_test.new()`` 创建并安装该 report server。
* **调用**：调用 UVM ``get_severity_count()`` 和父类 summarize。
* **共享状态**：日志后处理脚本 ``eh2_log_to_trace_csv.py`` 中的
  ``check_eh2_uvm_log()`` 查找 ``RISC-V UVM TEST PASSED/FAILED``，而这里打印的是
  ``EH2 UVM TEST PASSED/FAILED``；当前文档仅记录源码事实。

§3  base test 生命周期
--------------------------------------------------------------------------------

§3.1  字段、地址和 status code — test 的共享状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``core_eh2_base_test`` 声明 env、env_cfg、virtual sequence、TB service
interface、ISA 字符串、signature/boot 地址和 riscv-dv status code。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L24-L62``）：

.. code-block:: systemverilog

   class core_eh2_base_test extends uvm_test;
   
     `uvm_component_utils(core_eh2_base_test)
   
     // Environment and configuration
     core_eh2_env     env;
     core_eh2_env_cfg env_cfg;
   
     // Virtual sequence
     core_eh2_vseq vseq;
   
     // Testbench service interfaces
     virtual core_eh2_tb_intf tb_vif;
     virtual eh2_halt_run_intf    halt_run_vif;
   
     // Test identity
     string test_name = "core_eh2_base_test";

**逐段解释**：

* 第 L24-L33 行：base test 继承 ``uvm_test``，注册 UVM component，并持有
  ``core_eh2_env``、``core_eh2_env_cfg`` 和 ``core_eh2_vseq``。
* 第 L36-L37 行：``tb_vif`` 是 testbench service interface；``halt_run_vif`` 用于
  halt/run 辅助任务。
* 第 L40-L47 行：``test_name`` 默认是 ``core_eh2_base_test``，``isa_string`` 初始为空；
  signature address 是 ``32'hD058_0000``，boot address 是 ``32'h8000_0000``。
* 第 L50-L62 行：localparam 定义 riscv-dv core status code，包括
  ``TEST_PASS``、``TEST_FAIL``、``DEBUG_REQ``、``CSR_ACCESS``、``WFI_INSTR`` 和
  interrupt/exception 相关状态。

**接口关系**：

* **被调用**：所有常规 ``core_eh2_*_test`` 继承该 base test。
* **调用**：字段本身不调用函数；后续 phase/task 使用这些共享状态。
* **共享状态**：``SIGNATURE_ADDR`` 与 riscv-dv program generator 的 mailbox 地址一致。

§3.2  ``build_phase`` 和 ``end_of_elaboration_phase`` — env 与 cosim 配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：build 阶段创建 env、抓取 virtual interface、构造 ISA 字符串；elaboration
结束时把 cosim 配置和 pending binary path 写进 cosim scoreboard。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L63-L94``）：

.. code-block:: systemverilog

     function new(string name, uvm_component parent);
       core_eh2_report_server eh2_report_server;
       super.new(name, parent);
       eh2_report_server = new();
       uvm_report_server::set_server(eh2_report_server);
     endfunction
   
     function void build_phase(uvm_phase phase);
       super.build_phase(phase);
   
       // Create environment (which creates env_cfg internally)
       env = core_eh2_env::type_id::create("env", this);
   
       // env.cfg is created in env's constructor, so it's available immediately
       env_cfg = env.cfg;

**逐段解释**：

* 第 L63-L68 行：构造函数创建 ``core_eh2_report_server``，并通过
  ``uvm_report_server::set_server()`` 安装。
* 第 L73-L80 行：``build_phase()`` 创建 ``core_eh2_env``，随后从 ``env.cfg`` 取得
  ``env_cfg``。源码注释说明 env constructor 已经创建 cfg。
* 第 L82-L88 行：test 从 config_db 获取 ``tb_vif``，失败则 fatal；获取
  ``halt_run_vif`` 失败只打印 info，halt/load helper 会被禁用。
* 第 L90-L93 行：调用 ``build_isa_string()`` 后打印 ISA。base 实现把 ISA 写为
  ``rv32imac_zba_zbb_zbc_zbs``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L99-L128``）：

.. code-block:: systemverilog

     function void end_of_elaboration_phase(uvm_phase phase);
       super.end_of_elaboration_phase(phase);
   
       // Populate cosim_config string from env_cfg
       // Format: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;"
       if (env_cfg.enable_cosim && env.cosim_agt.scoreboard != null) begin
         string cosim_cfg_str;
         cosim_cfg_str = $sformatf("isa=%s;pc=0x%08x;mtvec=0x%08x;pmp_regions=%0d;pmp_granularity=%0d;mhpm_counters=%0d",
           isa_string,
           env_cfg.boot_addr,
           env_cfg.boot_addr & 32'hFFFFFF00,  // mtvec: 256-byte aligned, MODE=0 (direct)
           0,             // pmp_num_regions

**逐段解释**：

* 第 L99-L104 行：只有当 ``env_cfg.enable_cosim`` 为 1 且 cosim scoreboard 存在时，
  test 才构造 cosim 配置字符串。
* 第 L106-L114 行：配置字符串包含 ISA、PC、mtvec、PMP region 数、PMP granularity
  和 mhpm counter 数。当前 base test 给后三者传 0。
* 第 L118-L124 行：如果启用 cosim 且 binary 路径非空，test 将
  ``pending_bin_path`` 和 ``pending_base_addr`` 写给 scoreboard，等待 scoreboard
  初始化时加载。
* 第 L126-L127 行：最后打印 env topology。

**接口关系**：

* **被调用**：UVM phase 调度器调用。
* **调用**：调用 ``core_eh2_env::type_id::create``、config_db get、scoreboard 字段写入。
* **共享状态**：``env_cfg.enable_cosim`` 控制 scoreboard 配置是否下发。

§3.3  ``run_phase`` — load、vseq、completion 三段式
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：base ``run_phase`` 负责加载 binary，启动 virtual sequence，等待任一
completion 条件，然后停止 vseq 并 drop objection。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L133-L156``）：

.. code-block:: systemverilog

     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
   
       `uvm_info(test_name, "Test started", UVM_LOW)
   
       // Load binary into memory (core is in reset, safe without halting)
       load_binary_to_mem();
   
       // Start virtual sequence
       `uvm_info(test_name, "Starting vseq", UVM_LOW)
       start_vseq();
       `uvm_info(test_name, "Vseq done, waiting for completion", UVM_LOW)
   
       // Wait for test completion
       wait_for_completion(phase);

**逐段解释**：

* 第 L133-L136 行：test 进入 run phase 后 raise objection 并打印开始信息。
* 第 L138-L139 行：调用 ``load_binary_to_mem()``；源码注释说明 core 此时在 reset，
  因此无需 halt 即可加载。
* 第 L141-L147 行：调用 ``start_vseq()`` 启动 virtual sequence，然后等待
  ``wait_for_completion()``。
* 第 L152-L155 行：如果 ``vseq`` 非空则调用 ``vseq.stop()``，最后 drop objection。

**接口关系**：

* **被调用**：UVM run phase 调度器调用；多数派生测试直接复用。
* **调用**：调用 ``load_binary_to_mem()``、``start_vseq()``、
  ``wait_for_completion()`` 和 ``vseq.stop()``。
* **共享状态**：``env_cfg.binary``、``tb_vif``、``env.vseqr`` 和 mailbox 信号决定
  run phase 的实际行为。

§3.4  binary load — raw bin、VMA hex 与 backdoor memory 写入
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：base test 根据 ``env_cfg.binary`` 后缀选择 raw binary 或 hex load。raw
binary 逐 byte 写入 boot address；hex 解析 ``@ADDR`` 标记后按字节写入 VMA 地址。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L204-L226``）：

.. code-block:: systemverilog

     virtual task load_binary_to_mem();
       string bin_path;
   
       bin_path = env_cfg.binary;
       if (bin_path == "") begin
         `uvm_info(test_name, "No binary specified, skipping load", UVM_LOW)
         return;
       end
   
       // Skip if already loaded early by tb_top via $readmemh
       if (tb_vif.early_bin_loaded) begin
         `uvm_info(test_name, "Binary already loaded early by tb_top, skipping UVM load", UVM_LOW)
         return;
       end

**逐段解释**：

* 第 L204-L211 行：binary 路径来自 ``env_cfg.binary``；为空时跳过加载。
* 第 L213-L217 行：如果 ``tb_vif.early_bin_loaded`` 已经置位，说明 tb_top 通过
  ``$readmemh`` 提前加载过，UVM load 会直接返回。
* 第 L219-L225 行：路径后缀为 ``.hex`` 时调用 ``load_hex_to_mem()``，否则调用
  ``load_raw_binary_to_mem()`` 并使用 ``env_cfg.boot_addr``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L229-L251``）：

.. code-block:: systemverilog

     virtual task load_raw_binary_to_mem(string bin_path, bit [31:0] base_addr);
       int fd;
       int byte_val;
       bit [7:0] mem_byte;
       int addr;
   
       fd = $fopen(bin_path, "rb");
       if (fd == 0) begin
         `uvm_fatal(test_name, $sformatf("Cannot open binary: %s", bin_path))
       end
   
       addr = base_addr;
       while (!$feof(fd)) begin
         byte_val = $fread(mem_byte, fd);

**逐段解释**：

* 第 L229-L238 行：raw loader 以二进制方式打开文件；打开失败直接 fatal。
* 第 L240-L247 行：循环 ``$fread`` 单 byte 到 ``mem_byte``，读到一个 byte 时调用
  ``write_mem_byte(addr, mem_byte)`` 并递增地址。
* 第 L248-L250 行：关闭文件后打印加载 byte 数。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L273-L321``）：

.. code-block:: systemverilog

       while (!$feof(fd)) begin
         c = $fgetc(fd);
         if (c < 0) break;  // EOF
   
         if (c == "@" ) begin
           // Address marker: read hex address
           int new_addr;
           new_addr = 0;
           while (!$feof(fd)) begin
             c = $fgetc(fd);
             if (c < 0) break;
             if (c >= "0" && c <= "9")      new_addr = (new_addr << 4) | (c - "0");
             else if (c >= "a" && c <= "f") new_addr = (new_addr << 4) | (c - "a" + 10);

**逐段解释**：

* 第 L273-L291 行：hex loader 逐字符读取。遇到 ``@`` 后解析后续十六进制地址，
  并将当前写地址切换到 ``new_addr``。
* 第 L292-L309 行：十六进制字符被拼成 byte；遇到空白字符时，如果当前累计了
  nibble，就写入当前地址并递增。
* 第 L313-L317 行：如果文件末尾没有空白，函数会提交最后一个 byte。
* 第 L323-L326 行：``write_mem_byte()`` 只转调 ``tb_vif.write_mem_byte(addr, data)``，
  实际 memory model backdoor 由 testbench interface 实现。

**接口关系**：

* **被调用**：base ``run_phase`` 和 integrity ``main_phase`` 调用
  ``load_binary_to_mem()``。
* **调用**：调用 ``$fopen``、``$fread``、``$fgetc`` 和 ``tb_vif.write_mem_byte``。
* **共享状态**：``tb_vif.early_bin_loaded`` 决定是否跳过 UVM load；``env_cfg.boot_addr``
  决定 raw binary base address。

§3.5  completion 检测 — mailbox、timeout、cycle 和 double-fault
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：base test 使用 fork/join_any 等待四类 completion 条件：mailbox
signature、wall-clock timeout、cycle timeout 和 double-fault detector。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L347-L378``）：

.. code-block:: systemverilog

     virtual task wait_for_completion(uvm_phase phase);
       fork
         // Way 1: Signature-based completion (mailbox write)
         begin
           if (env_cfg.use_signature)
             wait_for_signature();
           else
             wait (0);  // Block forever if disabled
         end
   
         // Way 2: Wall-clock timeout
         begin
           #(env_cfg.timeout_ns);
           `uvm_error(test_name, $sformatf("Wall-clock timeout: %0d ns", env_cfg.timeout_ns))

**逐段解释**：

* 第 L347-L355 行：第一条分支在 ``env_cfg.use_signature`` 为 1 时等待
  ``wait_for_signature()``，否则永久阻塞。
* 第 L357-L361 行：第二条分支等待 ``env_cfg.timeout_ns``，超时后报 UVM error。
* 第 L363-L367 行：第三条分支调用 ``tb_vif.wait_clks(env_cfg.max_cycles)``，达到最大
  cycle 后报 UVM error。
* 第 L369-L377 行：第四条分支在 ``env_cfg.enable_double_fault_detector`` 为 1 时运行
  ``detect_double_fault()``。任一分支结束后 ``join_any`` 返回并 ``disable fork``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L380-L399``）：

.. code-block:: systemverilog

     // Signature-based completion: watch for writes to SIGNATURE_ADDR
     // Polls mailbox_test_done flag instead of using events (avoids triggered-state issues)
     virtual task wait_for_signature();
       forever begin
         @(posedge tb_vif.clk);
         if (tb_vif.mailbox_test_done) begin
           // Check which event fired
           if (tb_vif.mailbox_data[7:0] == 8'hFF) begin
             `uvm_info(test_name, "TEST PASSED (signature)", UVM_LOW)
           end else begin
             `uvm_error(test_name, "TEST FAILED (signature)")

**逐段解释**：

* 第 L382-L386 行：``wait_for_signature()`` 在时钟上升沿轮询
  ``tb_vif.mailbox_test_done``，不依赖 event triggered 状态。
* 第 L387-L391 行：mailbox data 低 8 bit 为 ``8'hFF`` 时打印 pass，否则报 UVM error。
* 第 L392-L396 行：函数等待 10 个 clock 作为 drain window，给 monitor 和 scoreboard
  收敛 outstanding transaction。

**接口关系**：

* **被调用**：base ``run_phase`` 和多个派生 ``run_phase`` 调用
  ``wait_for_completion()``。
* **调用**：调用 ``wait_for_signature()``、``tb_vif.wait_clks()`` 和
  ``detect_double_fault()``。
* **共享状态**：mailbox 信号来自 tb_top；exception count 来自 ``env.trace_monitor``。

§4  常规派生测试类
--------------------------------------------------------------------------------

§4.1  directed base — mailbox 同步、debug helper 和 instruction 去重
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：``core_eh2_directed_test`` 提供 Ibex 风格的 ``send_stimulus`` /
``check_stimulus`` 模板、debug request helper、DCSR 检查和 instruction decode
tracking。该 class 本身不应直接运行。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L22-L39``）：

.. code-block:: systemverilog

   class core_eh2_directed_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_directed_test)
   
     function new(string name = "core_eh2_directed_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     typedef struct {
       bit [6:0]  opcode;
       bit [2:0]  funct3;
       bit [6:0]  funct7;
       bit [11:0] system_imm;  // 12-bit immediate for SYSTEM instructions
     } instr_t;

**逐段解释**：

* 第 L22-L28 行：directed base 继承 ``core_eh2_base_test``，注册 UVM component。
* 第 L34-L39 行：该 class 内部也定义 ``instr_t``，字段与 package 中的
  ``instr_t`` 一致，用于本类的 ``seen_instr`` 队列。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L87-L124``）：

.. code-block:: systemverilog

     virtual task send_stimulus();
       fork
         begin
           // Background: start the virtual sequence for ambient stimulus
           vseq.start(env.vseqr);
         end
         begin
           // Wait for core initialization before starting the stimulus check loop
           // First write to signature address is guaranteed to be core init info
           wait_for_core_setup();
           // Allow core to begin executing <main>
           tb_vif.wait_clks(50);
   
           // Per-test directed stimulus (override in subclass)
           fork

**逐段解释**：

* 第 L87-L92 行：``send_stimulus()`` fork 一个背景分支启动 ``vseq``。
* 第 L93-L99 行：另一分支等待 core 初始化 mailbox 写入，再等 50 个 clock。
* 第 L101-L107 行：函数以 ``join_none`` 方式启动 ``check_stimulus()``，并等待
  ``wait_test_done()``。
* 第 L108-L116 行：完成后停止 vseq、等待 100 个 clock、``disable fork``。base
  ``check_stimulus()`` 默认 fatal，要求子类 override。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L166-L218``）：

.. code-block:: systemverilog

     virtual task send_debug_stimulus(
       bit [1:0]  mode,
       string     debug_status_msg,
       uvm_sequencer #(eh2_jtag_seq_item) jtag_seqr = null,
       int        halt_timeout_ns = 10000
     );
       bit [31:0] addr, data;
       bit is_write;
   
       if (jtag_seqr == null)
         jtag_seqr = env.jtag_agent.sequencer;
   
       // Send debug halt request via JTAG
       eh2_jtag_seq::send_write(jtag_seqr,

**逐段解释**：

* 第 L166-L176 行：debug helper 接收期望 privilege mode、错误消息、可选 JTAG
  sequencer 和 timeout。未传 sequencer 时使用 ``env.jtag_agent.sequencer``。
* 第 L178-L180 行：函数向 ``DMI_DMCONTROL`` 写 ``32'h80000001`` 发起 debug halt。
* 第 L183-L193 行：fork 等待 ``DEBUG_REQ`` core status 或 timeout；timeout 时 fatal。
* 第 L204-L215 行：函数等待 ``DCSR`` CSR 写入、缓存 signature data，检查
  ``dcsr.prv`` 和 ``dcsr.cause``，最后向 ``DMI_DMCONTROL`` 写 ``32'h40000000``
  发送 resume。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L313-L398``）：

.. code-block:: systemverilog

     virtual function bit decode_instr(bit [31:0] instr);
       bit [6:0]  opcode;
       bit [2:0]  funct3;
       bit [6:0]  funct7;
       bit [11:0] system_imm;
       instr_t    instr_fields;
   
       opcode     = instr[6:0];
       funct3     = instr[14:12];
       funct7     = instr[31:25];
       system_imm = instr[31:20];
   
       case (opcode)
         OPCODE_LUI, OPCODE_AUIPC, OPCODE_JAL: begin

**逐段解释**：

* 第 L313-L323 行：函数从 32-bit instruction 中拆出 opcode、funct3、funct7 和
  ``system_imm``。
* 第 L325-L386 行：不同 opcode 用不同粒度去重：LUI/AUIPC/JAL 只看 opcode；
  branch/load/store/misc-mem 看 opcode+funct3；OP-IMM shift 还看 funct7；
  OP 看 opcode+funct3+funct7；SYSTEM 对 WFI 总是返回 1，对 ECALL/MRET/DRET 避免
  nested trap，CSR 指令按 CSR 地址去重。
* 第 L388-L397 行：无法识别的 opcode fatal；新 instruction 类型记录到
  ``seen_instr`` 并返回 1。

**接口关系**：

* **被调用**：特定 directed test 可以继承该 class 并 override ``check_stimulus()``。
* **调用**：调用 ``vseq.start``、``wait_for_mem_txn``、``eh2_jtag_seq::send_write``、
  DCSR check helper 和 mailbox helper。
* **共享状态**：``tb_vif.mailbox_data`` 缓存 CSR/status 数据；``seen_instr`` 和
  ``seen_compressed_instr`` 保存已覆盖 instruction 类型。

§4.2  IRQ/debug/stress 类 — 通过背景线程注入异步刺激
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：IRQ、debug 和 stress 类通过覆盖 ``start_vseq()`` 或 ``run_phase()`` fork
背景刺激线程，使随机程序执行期间并发出现 interrupt 或 debug request。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L495-L522``）：

.. code-block:: systemverilog

   class core_eh2_irq_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_irq_test)
   
     function new(string name = "core_eh2_irq_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     // Override start_vseq: fork a background IRQ stimulus so the test
     // doesn't complete before interrupts are generated.
     virtual task start_vseq();
       fork
         begin
           eh2_irq_seq_item txn;
           #10000ns;  // Wait for reset

**逐段解释**：

* 第 L495-L501 行：``core_eh2_irq_test`` 继承 base test，不改 build phase。
* 第 L505-L520 行：``start_vseq()`` fork 背景线程，等待 10000 ns 后循环随机间隔，
  创建 external IRQ transaction，随机 IRQ ID 1-127、持续 10-100，然后调用
  ``eh2_irq_seq::send_irq``。
* 第 L521 行：背景线程启动后调用 ``super.start_vseq()``，保留 base vseq 行为。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L529-L552``）：

.. code-block:: systemverilog

   class core_eh2_debug_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_debug_test)
   
     function new(string name = "core_eh2_debug_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual task start_vseq();
       debug_seq dbg_h;
       fork
         begin
           dbg_h = debug_seq::type_id::create("dbg_h");
           dbg_h.jtag_seqr = env.vseqr.jtag_seqr;
           dbg_h.stress_mode = 1;

**逐段解释**：

* 第 L529-L535 行：debug test 继承 base test。
* 第 L540-L548 行：``start_vseq()`` 创建 ``debug_seq``，绑定 ``env.vseqr.jtag_seqr``，
  设置 ``stress_mode=1``，并启动该 sequence。
* 第 L550-L551 行：函数随后调用 ``super.start_vseq()``，让其他配置启用的 sequence
  继续运行。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L567-L599``）：

.. code-block:: systemverilog

     // Override start_vseq: fork background IRQ + debug stimulus so the test
     // doesn't complete before stimulus is generated.
     virtual task start_vseq();
       fork
         // IRQ stimulus
         begin
           eh2_irq_seq_item txn;
           #5000ns;
           forever begin
             #($urandom_range(100, 2000) * 10ns);
             txn = eh2_irq_seq_item::type_id::create("txn");

**逐段解释**：

* 第 L567-L584 行：stress test 的第一条背景分支产生 external IRQ，初始等待
  5000 ns，之后以 100-2000 个 10 ns 单位的随机间隔发送 IRQ。
* 第 L585-L596 行：第二条背景分支等待 50000 ns 后循环发送 JTAG halt 和 resume，
  写入 ``DMI_DMCONTROL`` 的值分别是 ``32'h80000001`` 和 ``32'h40000000``。
* 第 L597-L599 行：背景分支 ``join_none`` 后调用 ``super.start_vseq()``。

**接口关系**：

* **被调用**：YAML ``rtl_test`` 可选择这些 class，例如 interrupt/debug/stress 类条目。
* **调用**：调用 IRQ sequence、JTAG sequence 和 base ``start_vseq()``。
* **共享状态**：``env.irq_agent.sequencer``、``env.jtag_agent.sequencer`` 和
  ``env.vseqr.jtag_seqr`` 是异步刺激入口。

§4.3  配置型类 — 只改 ``env_cfg`` 或 timeout
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：大量派生类不重写 run 行为，只在 ``build_phase()`` 中关闭背景刺激、开启
特定 env_cfg 开关或放宽 timeout/cycle 上限。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L606-L637``）：

.. code-block:: systemverilog

   class core_eh2_bitmanip_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_bitmanip_test)
   
     function new(string name = "core_eh2_bitmanip_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual function void build_isa_string();
       isa_string = "rv32imac_zba_zbb_zbc_zbs";
     endfunction
   
   endclass
   
   class core_eh2_cosim_test extends core_eh2_base_test;

**逐段解释**：

* 第 L606-L616 行：bitmanip test 只覆盖 ``build_isa_string()``，把 ISA 字符串设为
  ``rv32imac_zba_zbb_zbc_zbs``。
* 第 L623-L635 行：cosim test 在 ``build_phase()`` 调用父类后设置
  ``env_cfg.enable_cosim = 1``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L886-L959``）：

.. code-block:: systemverilog

   class core_eh2_csr_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_csr_test)
   
     function new(string name = "core_eh2_csr_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       // CSR tests don't need random stimulus
       env_cfg.enable_irq_single_seq = 0;
       env_cfg.enable_irq_multiple_seq = 0;
       env_cfg.enable_debug_stress = 0;

**逐段解释**：

* 第 L886-L900 行：CSR test 关闭 single IRQ、multiple IRQ 和 debug stress 背景刺激。
* 第 L907-L919 行：load/store test 关闭 single IRQ 和 debug stress。
* 第 L926-L938 行：mul/div test 关闭 single IRQ 和 debug stress。
* 第 L945-L957 行：atomic test 也关闭 single IRQ 和 debug stress。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1176-L1228``）：

.. code-block:: systemverilog

   class core_eh2_pmp_basic_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_pmp_basic_test)
   
     function new(string name = "core_eh2_pmp_basic_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.timeout_ns = 64'd5_000_000_000;  // 5s
       env_cfg.max_cycles = 500_000;

**逐段解释**：

* 第 L1176-L1188 行：PMP basic test 将 wall-clock timeout 设为 5 s，cycle 上限设为
  500000。
* 第 L1195-L1207 行：PMP disable test 使用同样的 timeout 和 cycle 上限。
* 第 L1214-L1226 行：PMP random test 把 timeout 放宽到 10 s，cycle 上限为 1000000。

**接口关系**：

* **被调用**：YAML 的 ``rtl_test`` 字段映射到这些 class。
* **调用**：主要调用父类 ``build_phase``，然后写 ``env_cfg``。
* **共享状态**：``env_cfg`` 被 env、vseq 和 completion 逻辑读取。

§4.4  PIC、WFI、IRQ/debug 组合类 — 自定义 ``run_phase`` 并行刺激
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：这些类在 ``run_phase`` 中并行启动专用刺激、base vseq 和 completion
等待，用 ``join_any`` 让 mailbox/timeout 或刺激结束路径结束当前 test。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1020-L1057``）：

.. code-block:: systemverilog

   class core_eh2_pic_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_pic_test)
   
     function new(string name = "core_eh2_pic_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "PIC test started", UVM_LOW)
       load_binary_to_mem();
       start_vseq();
       fork

**逐段解释**：

* 第 L1020-L1032 行：PIC test 继承 base test，run phase 中 raise objection、加载
  binary、启动 vseq。
* 第 L1033-L1039 行：函数 fork ``run_pic_stimulus()`` 和 ``wait_for_completion()``，
  ``join_any`` 后 disable fork，停止 vseq 并 drop objection。
* 第 L1042-L1055 行：PIC stimulus 重复 20 次，随机间隔后发送 external IRQ，
  IRQ ID 限制为 1-31，duration 为 5-30。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1368-L1444``）：

.. code-block:: systemverilog

   class core_eh2_debug_wfi_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_debug_wfi_test)
   
     function new(string name = "core_eh2_debug_wfi_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "Debug WFI test started", UVM_LOW)
       load_binary_to_mem();

**逐段解释**：

* 第 L1368-L1387 行：debug WFI test 并行运行 ``run_debug_wfi_stimulus()``、vseq 和
  completion。
* 第 L1389-L1402 行：debug WFI stimulus 循环等待 5000-20000 个 10 ns 单位后发
  ``DMI_DMCONTROL=32'h80000001``，再等待 100-500 个 10 ns 单位后发 resume
  ``32'h40000000``。
* 第 L1410-L1442 行：debug CSR test 结构相同，但间隔更短，目标是在 CSR 操作附近
  插入 debug request。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1478-L1613``）：

.. code-block:: systemverilog

   class core_eh2_irq_wfi_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_irq_wfi_test)
   
     function new(string name = "core_eh2_irq_wfi_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction
   
     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "IRQ WFI test started", UVM_LOW)
       load_binary_to_mem();

**逐段解释**：

* 第 L1478-L1518 行：IRQ WFI test 并行发送 external IRQ、运行 vseq 并等待 completion。
* 第 L1524-L1558 行：IRQ CSR test 使用较短随机间隔发送 external IRQ，以覆盖 CSR
  操作期间的 interrupt。
* 第 L1566-L1611 行：IRQ nest test 设置 10 s timeout/500000 cycle，并在每轮中 fork
  2-5 个 external IRQ transaction，以制造快速多源 interrupt。

**接口关系**：

* **被调用**：testlist 中 debug/IRQ/PIC 相关 ``rtl_test`` 字段选择这些 class。
* **调用**：调用 ``load_binary_to_mem``、``start_vseq``、IRQ/JTAG helper 和
  ``wait_for_completion``。
* **共享状态**：所有这些类依赖 ``env.irq_agent.sequencer``、``env.jtag_agent.sequencer``
  和 mailbox completion。

§5  integrity RTL-only 测试
--------------------------------------------------------------------------------

§5.1  VPI helper 与 cosim 禁用边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：integrity 测试通过 UVM HDL backdoor 读取、force、release RTL 内部路径。
这些测试在 build phase 中关闭 cosim，因为被注入的 RTL 硬件故障不由 Spike 建模。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L1-L34``）：

.. code-block:: systemverilog

   // SPDX-License-Identifier: Apache-2.0
   // EH2 integrity fault-injection tests.
   //
   // These tests intentionally drive short-lived RTL faults through VPI
   // backdoor access.  They are RTL-only by construction: the injected hardware
   // faults are not modeled by Spike/cosim.
   
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import core_eh2_env_pkg::*;
   
   function automatic bit core_eh2_intg_path_exists(string path);

**逐段解释**：

* 第 L1-L6 行：文件头明确这些测试通过 VPI backdoor 注入短周期 RTL fault，且
  “by construction” 是 RTL-only，因为 Spike/cosim 不建模这些硬件 fault。
* 第 L8-L10 行：文件包含 UVM macro，并导入 UVM 和 env package。
* 第 L12-L34 行：helper 分别包装 ``uvm_hdl_check_path``、``uvm_hdl_read``、
  ``uvm_hdl_force`` 和 ``uvm_hdl_release``；read/force/release 失败时 fatal。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L41-L61``）：

.. code-block:: systemverilog

   class core_eh2_rf_addr_intg_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_rf_addr_intg_test)
   
     string rf_addr_path;
     string rf_rden_path;
     string tlu_trap_path = "core_eh2_tb_top.dut.veer.dec.tlu.tlumt[0].tlu.i0_exception_valid_e4";
   
     function new(string name = "core_eh2_rf_addr_intg_test",
                  uvm_component parent = null);
       super.new(name, parent);
       test_name = name;
     endfunction

**逐段解释**：

* 第 L41-L48 行：RF address integrity test 继承 base test，并声明 register-file
  read-address path、read-enable path 和 TLU trap path。
* 第 L55-L61 行：build phase 调用父类后设置 ``env_cfg.enable_cosim = 0``、
  ``env_cfg.disable_cosim = 1``，并设置 5 s timeout 和 500000 cycle。
* 第 L63-L64 行：该类的 ``run_phase`` 是空 task，实际测试逻辑在 ``main_phase``。

**接口关系**：

* **被调用**：YAML 中 ``cosim: rtl_only`` 的 integrity 条目选择这些 class。
* **调用**：调用 UVM HDL backdoor API 和 base test binary/vseq helper。
* **共享状态**：:ref:`adr-0017` 记录 integrity cosim waiver 边界；testlist 中
  ``cosim: rtl_only`` 会被回归脚本转换为 ``+disable_cosim=1``。

§5.2  RF address、RAM、ICache 和 memory integrity 检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：四个 integrity class 分别检查 RF read-address force 是否生效、DCCM
ECC counter、ICache ECC counter、ICCM/DCCM error counter 是否发生变化。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L75-L132``）：

.. code-block:: systemverilog

       phase.raise_objection(this);
       load_binary_to_mem();
       start_vseq();
       @(posedge tb_vif.rst_n);
       tb_vif.wait_clks(100);
   
       rf_addr_path = "core_eh2_tb_top.dut.veer.dec.arf[0].arf.raddr0";
       rf_rden_path = "core_eh2_tb_top.dut.veer.dec.arf[0].arf.rden0";
       if (!core_eh2_intg_path_exists(rf_addr_path)) begin
         rf_addr_path = "core_eh2_tb_top.dut.veer.dec.arf[0].arf.raddr1";
         rf_rden_path = "core_eh2_tb_top.dut.veer.dec.arf[0].arf.rden1";
       end

**逐段解释**：

* 第 L75-L79 行：RF address integrity main phase raise objection，加载 binary，
  启动 vseq，等待 reset 释放后再等 100 个 clock。
* 第 L81-L89 行：先尝试 ``raddr0/rden0`` 路径，不存在则尝试 ``raddr1/rden1``；
  两者都不存在时 fatal。
* 第 L91-L118 行：函数等待最多 2000 cycle 找到非 x0 的 live read address，翻转
  address bit 0 后 force 一个 cycle，并检查 force 后采样值确实等于 forced 值。
* 第 L120-L131 行：释放 force 后最多观察 20 cycle 的 TLU exception path；无论是否
  看到 trap，函数最后打印 RTL self-check PASS 并 drop objection。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L140-L221``）：

.. code-block:: systemverilog

   class core_eh2_ram_intg_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_ram_intg_test)
   
     string ecc_pulse_path = "core_eh2_tb_top.dut.veer.lsu.lsu_single_ecc_error_incr";
     string counter_path   = "core_eh2_tb_top.dut.veer.dec.tlu.mdccmect";
     string valid_path     = "core_eh2_tb_top.dut.veer.lsu.lsu_p.valid";
   
     function new(string name = "core_eh2_ram_intg_test",
                  uvm_component parent = null);

**逐段解释**：

* 第 L140-L147 行：RAM integrity test 关注 ``lsu_single_ecc_error_incr``、
  ``mdccmect`` 和 LSU valid path。
* 第 L154-L161 行：build phase 关闭 cosim、开启 ``env_cfg.enable_mem_error``，
  并设置 timeout/cycle。
* 第 L179-L184 行：main phase 先检查 ECC pulse path 和 counter path 是否存在。
* 第 L186-L199 行：测试最多等待 3000 cycle 观察 LSU valid window；如果没有观察到，
  打印 info 后仍在 counter boundary 注入。
* 第 L201-L220 行：读取 counter，force ECC pulse 一个 clock 后 release，最多等待
  20 cycle 观察 ``MDCCMECT`` 变化；未变化则 fatal，变化则 PASS。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L229-L309``）：

.. code-block:: systemverilog

   class core_eh2_icache_intg_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_icache_intg_test)
   
     string ic_error_path = "core_eh2_tb_top.dut.veer.ifu_ic_error_start[0]";
     string counter_path  = "core_eh2_tb_top.dut.veer.dec.tlu.micect";
     string fetch_path    = "core_eh2_tb_top.dut.veer.ifu.mem_ctl.ifc_fetch_req_f1";
   
     function new(string name = "core_eh2_icache_intg_test",
                  uvm_component parent = null);

**逐段解释**：

* 第 L229-L235 行：ICache integrity test 关注 IFU error start、``micect`` counter 和
  fetch request path。
* 第 L267-L272 行：main phase 检查 error path 和 counter path 是否存在。
* 第 L274-L287 行：测试最多等待 3000 cycle 观察 fetch request；未观察到时只打印 info。
* 第 L289-L307 行：读取 ``MICECT``，force ICache error 一个 clock 后 release，最多
  30 cycle 观察 counter 变化；未变化 fatal，变化则 PASS。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L317-L410``）：

.. code-block:: systemverilog

   class core_eh2_mem_intg_error_test extends core_eh2_base_test;
   
     `uvm_component_utils(core_eh2_mem_intg_error_test)
   
     string iccm_error_path = "core_eh2_tb_top.dut.veer.iccm_dma_sb_error";
     string dccm_error_path = "core_eh2_tb_top.dut.veer.lsu.lsu_single_ecc_error_incr";
     string iccm_count_path = "core_eh2_tb_top.dut.veer.dec.tlu.miccmect";
     string dccm_count_path = "core_eh2_tb_top.dut.veer.dec.tlu.mdccmect";
   
     function new(string name = "core_eh2_mem_intg_error_test",

**逐段解释**：

* 第 L317-L324 行：generic memory integrity test 同时持有 ICCM error path、DCCM
  error path、``MICCMECT`` 和 ``MDCCMECT`` counter path。
* 第 L332-L340 行：build phase 关闭 cosim，开启 ``enable_mem_error``、
  ``enable_axi4_error_inject``，并把 ``axi4_error_pct`` 设为 100。
* 第 L361-L372 行：main phase 检查四条 HDL path 是否存在。
* 第 L374-L386 行：函数读取两个 counter，先 force/release ICCM error，再
  force/release DCCM error。
* 第 L388-L407 行：最多等待 40 cycle 观察两个 counter 是否均发生变化；任一未变化
  则 fatal，两个都变化则 PASS。

**接口关系**：

* **被调用**：``riscv_dv_extension/testlist.yaml`` 中 ``riscv_rf_addr_intg_test``、
  ``riscv_ram_intg_test``、``riscv_icache_intg_test`` 和
  ``riscv_mem_intg_error_test`` 映射到这些 RTL test。
* **调用**：调用 ``core_eh2_intg_*`` helper、``tb_vif.wait_clks``、base binary/vseq
  helper。
* **共享状态**：这些测试读写 RTL hierarchical path；路径变更会直接导致 fatal。

§6  sequence 与 virtual sequence
--------------------------------------------------------------------------------

§6.1  ``core_eh2_seq_lib.sv`` — IRQ、debug 和 fetch-enable 基础序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：旧式 sequence library 提供可停止的随机 interval/delay 基类，并实现
IRQ raise/drop、debug command walk 和 fetch enable toggle。

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
     endfunction

**逐段解释**：

* 第 L24-L31 行：base sequence 定义最大 event 间隔、初始 delay 范围和 stop flag。
* 第 L38-L49 行：``rand_delay()`` 在 ``delay_min`` 到 ``delay_max`` ns 中随机等待；
  ``rand_interval()`` 在 1 到 ``interval`` 个 10 ns 单位中随机等待。
* 第 L52-L59 行：``stop()`` 置位 ``stopped``，``wait_for_stop()`` 等待该 flag。

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

* 第 L66-L75 行：``irq_raise_seq`` 持有 ``eh2_irq_intf``，最大 external IRQ ID 为
  127，每次 event 默认拉起 3 个 interrupt。
* 第 L80-L95 行：body 先随机初始 delay，然后循环检查 ``stopped``，随机选择 IRQ ID
  拉高 ``extintsrc_req``，等待 interval 后清零，再等待下一轮 interval。
* 第 L102-L127 行：``irq_raise_single_seq`` 与 multi IRQ 类似，但每次只选择一个
  IRQ ID，并只清掉该 bit。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:L199-L239``）：

.. code-block:: systemverilog

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

**逐段解释**：

* 第 L199-L213 行：``debug_seq`` 在 stress mode 下循环执行
  ``send_debug_command_walk()``，非 stress mode 只执行一次。
* 第 L220-L239 行：command walk 先发送 ``dmactive``、halt，随后读 core register、
  读多个 DCCM 地址、读 external system bus、做 direct system-bus read/write，
  最后 resume 并 clear resume。
* 第 L241-L298 行：每个 helper 都通过 ``eh2_jtag_seq::send_write`` 向对应 DMI
  register 写固定值或地址。

**接口关系**：

* **被调用**：``core_eh2_vseq`` 和部分派生 test 创建这些 sequence。
* **调用**：调用 ``eh2_irq_intf`` 信号赋值和 ``eh2_jtag_seq::send_write``。
* **共享状态**：``interval``、``stopped`` 和 sequencer/vif 由 test 或 vseq 设置。

§6.2  ``core_eh2_new_seq_lib.sv`` — 调度模式和新式请求
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：new-style sequence library 提供 ``SingleRun``、``MultipleRuns`` 和
``InfiniteRuns`` 调度模式，并定义 IRQ、debug、memory error 和 fetch-enable 请求类。

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
     constraint zero_delays_c {

**逐段解释**：

* 第 L17-L23 行：base new sequence 是参数化 ``uvm_sequence``，可持有
  ``eh2_dut_probe_if``。
* 第 L24-L32 行：``zero_delays`` 受 ``zero_delay_pct`` 分布约束，默认 50% 概率零延迟。
* 第 L34-L48 行：``stimulus_delay_cycles`` 和 ``iteration_cnt`` 都有范围约束；
  ``iteration_modes`` 默认是 ``MultipleRuns``。
* 第 L50-L55 行：构造函数尝试从 config_db 获取 ``probe_vif``，失败只 warning。

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

* 第 L61-L85 行：body 根据 ``iteration_modes`` 选择单次、多次或无限循环调用
  ``drive_stimulus()``；未知模式 fatal。
* 第 L88-L94 行：``drive_stimulus()`` 在非零延迟模式下随机等待，然后调用
  ``send_req()``。
* 第 L96-L104 行：base ``send_req()`` 默认 fatal，子类必须实现；``stop()`` 置位
  ``stop_seq`` 并等待 ``seq_finished``。

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

* 第 L111-L127 行：new IRQ sequence 约束每次请求产生 1-5 个 interrupt，duration
  为 10-100，并尝试从 config_db 获取 ``irq_vif``。
* 第 L129-L146 行：``send_req()`` 在 ``irq_vif`` 为空时返回；否则随机选择 IRQ ID
  1-127 拉高，等待 ``irq_duration`` 个 10 ns 单位后清掉 1-127 全部 external IRQ。

**接口关系**：

* **被调用**：当前源码中该库被 package include；是否由 test 使用取决于后续 sequence
  实例化。
* **调用**：调用 config_db get、``send_req()`` 子类实现和 interface 信号赋值。
* **共享状态**：``run_type_e`` 和 ``error_type_e`` 来自 package typedef。

§6.3  ``core_eh2_vseq`` — 从 env_cfg 分派子序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：virtual sequence 根据 ``env_cfg`` 中的 enable 位并行启动 IRQ、debug 和
fetch-enable sequence，并在 ``stop()`` 中逐个停止已创建的子序列。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L23-L53``）：

.. code-block:: systemverilog

   class core_eh2_vseq extends uvm_sequence;
   
     `uvm_object_utils(core_eh2_vseq)
   
     // Configuration
     core_eh2_env_cfg cfg;
   
     // Virtual sequencer
     core_eh2_vseqr vseqr;
   
     // Sub-sequences
     irq_raise_single_seq irq_single_h;

**逐段解释**：

* 第 L23-L31 行：vseq 继承 ``uvm_sequence``，持有 ``core_eh2_env_cfg`` 和
  ``core_eh2_vseqr``。
* 第 L34-L40 行：vseq 持有 single IRQ、multi IRQ、NMI、drop、debug stress、
  debug single 和 fetch-enable 子 sequence handle。
* 第 L46-L53 行：``pre_body()`` 要求 ``cfg`` 非空，并把 ``m_sequencer`` cast 成
  ``core_eh2_vseqr``；失败 fatal。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_vseq.sv:L55-L117``）：

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

**逐段解释**：

* 第 L58-L85 行：body fork IRQ 子序列。single、multiple 和 NMI 分支分别受
  ``cfg.enable_irq_single_seq``、``cfg.enable_irq_multiple_seq`` 和
  ``cfg.enable_irq_nmi_seq`` 控制。
* 第 L87-L106 行：debug 子序列分两类：``enable_debug_seq`` 或
  ``enable_debug_stress`` 创建 ``debug_stress_h``，``enable_debug_single`` 创建
  ``debug_single_h``。
* 第 L108-L115 行：``enable_fetch_toggle`` 控制 fetch-enable sequence。
* 第 L116 行：所有分支 ``join_none``，因此 vseq body 不阻塞到子序列结束。

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

**逐段解释**：

* 第 L120-L128 行：``stop()`` 对每个非空子 sequence 调用 ``stop()``。
* 第 L131-L137 行：``get_irq_vif()`` 从 config_db 获取 ``irq_vif``，失败 warning 并
  返回当前 ``vif`` 值。
* 第 L140-L176 行：helper task 可以显式启动 single IRQ、multi IRQ、NMI、IRQ drop、
  debug stress 和 debug single sequence。

**接口关系**：

* **被调用**：base test ``start_vseq()`` 创建并启动该 vseq。
* **调用**：调用各子 sequence ``type_id::create``、``start`` 和 ``stop``。
* **共享状态**：``env_cfg`` enable 位由 plusarg、test build phase 或 YAML sim_opts
  间接设置。

§7  testlist、assembly 和 sign-off gate 的连接
--------------------------------------------------------------------------------

§7.1  ``rtl_test`` 与手写 assembly — YAML 到 UVM test 的映射
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：testlist 把随机生成测试或手写 assembly 测试映射到 UVM test class。手写
assembly 通过 ``test_srcs`` 指定，UVM test 通过 ``rtl_test`` 指定。

**关键代码** （``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L1-L19``）：

.. code-block:: yaml

   - test: smoke
     description: Basic smoke test
     test_srcs: tests/asm/cosim_smoke.S
     rtl_test: core_eh2_base_test
     iterations: 1
   
   - test: pic
     description: PIC interrupt controller test
     test_srcs: tests/asm/directed_irq_basic.S
     rtl_test: core_eh2_pic_test
     iterations: 1
   
   - test: fetch_toggle
     description: Fetch enable/disable toggling test
     test_srcs: tests/asm/cosim_smoke.S
     rtl_test: core_eh2_fetch_toggle_test

**逐段解释**：

* 第 L1-L5 行：``smoke`` 使用 ``tests/asm/cosim_smoke.S``，RTL test 是
  ``core_eh2_base_test``。
* 第 L8-L12 行：``pic`` 使用 ``directed_irq_basic.S``，RTL test 是
  ``core_eh2_pic_test``。
* 第 L15-L19 行：``fetch_toggle`` 复用 ``cosim_smoke.S``，RTL test 是
  ``core_eh2_fetch_toggle_test``。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:L203-L226``）：

.. code-block:: yaml

   - test: riscv_pmp_basic_test
     description: Basic PMP region test — cosim enabled (issue 55 PMP fixup)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=10000 +boot_mode=m +enable_pmp=1 +pmp_num_regions=4 +pmp_granularity=0
   
       '
     rtl_test: core_eh2_pmp_basic_test
     iterations: 5
   - test: riscv_pmp_disable_all_test
     description: Disable all PMP regions test — cosim enabled (issue 55)
     gen_test: riscv_rand_instr_test
     gen_opts: '+instr_cnt=5000 +boot_mode=m +enable_pmp=1 +pmp_num_regions=0

**逐段解释**：

* 第 L203-L210 行：PMP basic 随机测试由 riscv-dv 生成，``gen_opts`` 开启 PMP 并设置
  4 个 region，RTL test 使用 ``core_eh2_pmp_basic_test``。
* 第 L211-L218 行：PMP disable-all 条目设置 ``+pmp_num_regions=0``，RTL test 使用
  ``core_eh2_pmp_disable_test``。
* 第 L219-L226 行：PMP random 条目设置 8 个 region 和 granularity，RTL test 使用
  ``core_eh2_pmp_random_test``。

**接口关系**：

* **被调用**：回归脚本读取 YAML 并传 ``rtl_test`` 给仿真命令。
* **调用**：YAML 本身不调用函数。
* **共享状态**：``test_srcs`` 路径由 compile script 复制/编译；``rtl_test`` 字符串必须
  与 UVM factory 注册名一致。

§7.2  ``test_signoff_gates.py`` — 测试门禁逻辑的 Python 单元测试
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：该 Python 文件不是 UVM test；它为 ``scripts/signoff.py`` 的门禁函数提供
pytest 单元测试，覆盖 coverage requirement、coverage threshold、cosim-disabled、
skip-in-signoff 和 directed test pool completeness 等规则。该文件中的 60/50 阈值
是单元测试 fixture，不是当前 release 默认门限；当前 Makefile 默认是 line 65、
group/covergroup 40，参数名仍保留 ``SIGNOFF_MIN_FUNCTIONAL_COV``。

**关键代码** （``dv/uvm/core_eh2/tests/test_signoff_gates.py:L1-L36``）：

.. code-block:: python

   #!/usr/bin/env python3
   """Unit tests for sign-off gates in signoff.py.
   
   Covers the 7 gate rules defined in issue 50:
     1. --require-coverage default ON
     2. --min-line-coverage 60.0% threshold
     3. --min-functional-coverage 50.0% threshold
     4. --fail-on-cosim-disabled gate
     5. --fail-on-skip-in-signoff gate
     6. Directed test pool completeness check
     7. Real coverage rate < 95% → PARTIAL status
   """
   
   import json

**逐段解释**：

* 第 L1-L12 行：文件 docstring 明确列出 7 条 sign-off gate 规则；其中 60/50 是
  测试用阈值，不能外推为 release 默认值。
* 第 L14-L21 行：测试依赖 ``json``、``os``、``sys``、``tempfile``、``Path``、
  ``pytest`` 和 ``yaml``。
* 第 L23-L36 行：脚本把 ``dv/uvm/core_eh2/scripts`` 加入 ``sys.path``，并从
  ``signoff`` 导入 coverage、waiver、cosim exception、directed pool 和 report
  相关函数。

**关键代码** （``dv/uvm/core_eh2/tests/test_signoff_gates.py:L39-L56``）：

.. code-block:: python

   class Args:
       """Minimal argparse-like namespace for testing."""
       skip_precheck = True
       min_pass_rate = 100.0
       require_cosim_all_tests = False
       no_require_coverage = False
       no_fail_on_cosim_disabled = False
       no_fail_on_skip_in_signoff = False
       waivers_cosim_disabled = ""
       min_overall_coverage = 0.0
       min_line_coverage = 60.0
       min_cond_coverage = 0.0
       min_fsm_coverage = 0.0
       min_toggle_coverage = 0.0
       min_functional_coverage = 50.0
       min_pass_rate = 100.0

**逐段解释**：

* 第 L39-L56 行：``Args`` 是最小 argparse namespace，用类属性模拟 signoff CLI
  参数。这里的 line 60.0 和 functional 50.0 仅用于测试阈值比较逻辑；release
  默认门限仍由顶层 ``Makefile`` 的 ``SIGNOFF_MIN_LINE_COV=65`` 与
  ``SIGNOFF_MIN_FUNCTIONAL_COV=40`` 定义。

**关键代码** （``dv/uvm/core_eh2/tests/test_signoff_gates.py:L198-L220``）：

.. code-block:: python

   def test_directed_pool_check_detects_missing():
       """check_directed_pool_coverage must detect .S files not in testlist."""
       # Create temp directory with mock files
       import tempfile
       with tempfile.TemporaryDirectory() as tmpdir:
           asm_dir = Path(tmpdir) / "tests" / "asm"
           asm_dir.mkdir(parents=True)
           # Create 3 directed asm files
           (asm_dir / "directed_alpha.S").write_text("nop")
           (asm_dir / "directed_beta.S").write_text("nop")
           (asm_dir / "directed_gamma.S").write_text("nop")

**逐段解释**：

* 第 L198-L208 行：测试在临时目录创建 3 个 mock ``directed_*.S`` 文件。
* 第 L210-L218 行：测试创建只包含两个条目的 YAML testlist，然后调用
  ``check_directed_pool_coverage()``。
* 第 L219-L220 行：断言 on-disk 数为 3，missing 数为 1，用来证明 pool completeness
  检查能发现未列入 testlist 的 assembly。

**接口关系**：

* **被调用**：pytest 运行该文件。
* **调用**：调用 ``signoff.py`` 中的 gate 函数和 YAML/tempfile helper。
* **共享状态**：这些测试使用真实 ``signoff.py`` 函数，但部分断言对真实 testlist
  是否存在做了宽松处理。

§8  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`appendix_b_uvm_tests`、:ref:`appendix_b_uvm_env`、
  :ref:`appendix_b_uvm_vseq`、:ref:`riscv_dv_extension`、
  :ref:`cosim_scoreboard`、:doc:`../06_flows/regression_flow`、
  :doc:`../06_flows/signoff_flow`。
* 关联 ADR：:ref:`adr-0006`、:ref:`adr-0007`、:ref:`adr-0008`、
  :ref:`adr-0009`、:ref:`adr-0017`。
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_report_server.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_vseq.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/tests/test_signoff_gates.py``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml``
* 源文件：
  ``/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml``

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页描述的 env、agent、sequence、scoreboard 或 coverage 组件在 UVM phase 中何时工作？
2. 该组件连接的 SystemVerilog interface、DPI 或 probe 信号是哪一组真实文件？
3. 如果该组件失效，log 中应先查 UVM_FATAL、scoreboard mismatch、coverage hole 还是 testlist 配置？
4. 本页与 Ibex core_ibex 的一致点和 EH2 差异点分别是什么？
5. 该组件在 9-stage sign-off 中支撑 smoke、directed、cosim、riscv-dv、formal 还是 coverage gate？
