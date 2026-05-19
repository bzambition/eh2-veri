.. _appendix_b_uvm_tests:
.. _appendix_b_uvm/tests:

测试库 — 详细参考
================================================================================

:status: draft
:source: dv/uvm/core_eh2/tests/core_eh2_base_test.sv
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  文件边界与类关系
--------------------------------------------------------------------------------

``dv/uvm/core_eh2/tests/`` 下的 SystemVerilog 测试库由 package、report server、base test、
directed test library、integrity test library、virtual sequence library 和独立 RVFI smoke
test 组成。本文只解释 SV/Python 测试基础设施；汇编测试程序本身见
:ref:`appendix_c_tools/asm_tests`。

**测试类数据流**：

.. code-block:: text

   core_eh2_tb_top.run_test()
     |
     +-- core_eh2_test_pkg
     |     +-- core_eh2_report_server
     |     +-- core_eh2_seq_lib / core_eh2_new_seq_lib
     |     +-- core_eh2_vseq
     |     +-- core_eh2_base_test
     |     +-- core_eh2_test_lib
     |     +-- core_eh2_intg_test_lib
     |
     +-- core_eh2_base_test
           |
           +-- build_phase: create env, get tb_vif/halt_run_vif
           +-- end_of_elaboration_phase: populate cosim_config and pending binary
           +-- run_phase: load binary, start vseq, wait for completion
           +-- helper tasks: mailbox, CSR, core status, binary load

``core_eh2_rvfi_smoke_test.sv`` 位于同一目录，但 ``core_eh2_test_pkg.sv`` 的 include 列表
没有包含该文件；它依赖编译 filelist 是否单独加入该源文件。本文把它作为独立测试文件解释。

§2  ``core_eh2_test_pkg.sv`` — package 汇聚点
--------------------------------------------------------------------------------

§2.1  import、类型定义与 include 顺序
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：定义测试 package 的编译边界，导入 env/agent package，声明 directed tests 用到的
instruction tracking 类型和 new sequence 调度枚举，然后按顺序 include 测试库文件。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L9-L18``）：

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

逐段解释：

* 第 L9 行：package 名为 ``core_eh2_test_pkg``，仿真 filelist 中引用的是这个 package 文件。
* 第 L11-L18 行：导入 UVM、env、AXI4、trace、IRQ、JTAG、cosim、halt/run package，确保
  后续 include 的 test、sequence 和 helper 能直接使用这些 class/type。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L20-L40``）：

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

     // Error injection side selection
     typedef enum bit [1:0] {
       IsideErr, // Inject error in instruction side memory
       DsideErr, // Inject error in data side memory
       PickErr   // Pick which memory to inject error in
     } error_type_e;

逐段解释：

* 第 L21-L26 行：``instr_t`` 保存 opcode、funct3、funct7 和 ``system_imm``，用于
  ``core_eh2_directed_test`` 的 instruction 去重。
* 第 L29-L33 行：``run_type_e`` 定义 new sequence 的单次、无限次和多次运行模式。
* 第 L36-L40 行：``error_type_e`` 定义 memory error sequence 选择 instruction side、
  data side 或随机选择。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:L42-L49``）：

.. code-block:: systemverilog

     `include "core_eh2_report_server.sv"
     `include "core_eh2_seq_lib.sv"
     `include "core_eh2_new_seq_lib.sv"
     `include "core_eh2_vseq.sv"
     `include "core_eh2_base_test.sv"
     `include "core_eh2_test_lib.sv"
     `include "core_eh2_intg_test_lib.sv"

   endpackage

逐段解释：

* 第 L42-L45 行：先 include report server、sequence library 和 virtual sequence。
* 第 L46 行：再 include base test，使后续 test library 可以继承 ``core_eh2_base_test``。
* 第 L47-L48 行：include directed test library 和 integrity test library。
* 第 L49 行：结束 package；``core_eh2_rvfi_smoke_test.sv`` 不在该 include 列表中。

接口关系：

* 被调用：``dv/uvm/core_eh2/eh2_tb.f`` 引用 ``core_eh2_test_pkg.sv``。
* 调用：通过 preprocessor include 拉入多个测试源文件。
* 共享状态：定义 ``instr_t``、``run_type_e``、``error_type_e`` 给 include 文件使用。

§3  ``core_eh2_report_server.sv`` — PASS/FAIL 摘要
--------------------------------------------------------------------------------

§3.1  ``report_summarize()`` — 按 UVM error/fatal 计数打印结果
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：覆盖 UVM 默认 report server 的总结阶段，根据 ``UVM_ERROR`` 和 ``UVM_FATAL`` 计数打印
EH2 UVM TEST PASSED 或 FAILED，然后调用父类总结。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_report_server.sv:L7-L24``）：

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
         $display("\n--- EH2 UVM TEST FAILED ---\n");
       end
       super.report_summarize(file);
     endfunction

   endclass

逐段解释：

* 第 L7 行：``core_eh2_report_server`` 继承 ``uvm_default_report_server``。
* 第 L9-L11 行：构造函数只调用父类构造函数。
* 第 L13-L17 行：``report_summarize`` 读取 ``UVM_ERROR`` 数，再加上 ``UVM_FATAL`` 数。
* 第 L18-L22 行：当合计 error count 为 0 时打印 PASSED，否则打印 FAILED。
* 第 L23 行：最后调用 ``super.report_summarize(file)``，保留 UVM 默认总结输出。

接口关系：

* 被调用：``core_eh2_base_test.new`` 创建并安装该 report server。
* 调用：UVM report server API ``get_severity_count`` 和 ``super.report_summarize``。
* 共享状态：读取 UVM report server 内部 severity count。

§4  ``core_eh2_base_test.sv`` — 所有常规测试的基类
--------------------------------------------------------------------------------

§4.1  class 字段与 status code
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：声明 env、env_cfg、virtual sequence、TB service interface、测试名称、ISA 字符串、
signature address、boot address 和 riscv-dv status code。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L24-L47``）：

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

     // ISA string for cosim
     string isa_string = "";

     // Signature address for riscv-dv handshake
     parameter bit [31:0] SIGNATURE_ADDR = 32'hD058_0000;
     parameter bit [31:0] BOOT_ADDR      = 32'h8000_0000;

逐段解释：

* 第 L24-L26 行：``core_eh2_base_test`` 继承 ``uvm_test`` 并注册 UVM factory。
* 第 L29-L33 行：保存 env、env_cfg 和 ``core_eh2_vseq`` 句柄。
* 第 L36-L37 行：从 TB 顶层通过 ``uvm_config_db`` 获取 ``tb_vif`` 和 ``halt_run_vif``。
* 第 L40-L47 行：保存 test name、ISA 字符串、signature mailbox 地址和 boot 地址。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L49-L68``）：

.. code-block:: systemverilog

     // Core status codes (from riscv-dv)
     localparam INITIALIZED     = 0;
     localparam CORE_RUNNING    = 1;
     localparam TEST_PASS       = 2;
     localparam TEST_FAIL       = 3;
     localparam WB_EXCEPTION    = 4;
     localparam IRQ_EXCEPTION   = 5;
     localparam DEBUG_REQ       = 6;
     localparam CSR_ACCESS      = 7;
     localparam WFI_INSTR       = 8;
     localparam TIMER_INTRPT     = 9;
     localparam EXT_INTRPT       = 10;
     localparam ECALL            = 11;

     function new(string name, uvm_component parent);
       core_eh2_report_server eh2_report_server;
       super.new(name, parent);
       eh2_report_server = new();
       uvm_report_server::set_server(eh2_report_server);
     endfunction

逐段解释：

* 第 L50-L61 行：定义 riscv-dv signature status code，包括 initialized、running、pass/fail、
  exception、debug、CSR、WFI、timer/external interrupt 和 ecall。
* 第 L63-L68 行：构造函数创建 ``core_eh2_report_server`` 并通过
  ``uvm_report_server::set_server`` 安装。

接口关系：

* 被调用：所有继承 ``core_eh2_base_test`` 的 test class 构造时调用。
* 调用：UVM factory 注册、report server 安装。
* 共享状态：保存 env/test 配置和 TB virtual interface 句柄。

§4.2  ``build_phase()`` — 创建 env 并获取 virtual interface
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：创建 ``core_eh2_env``，取出 env 构造时创建的 ``cfg``，从 ``uvm_config_db`` 获取
``tb_vif`` 和 ``halt_run_vif``，并构造 ISA 字符串。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L73-L94``）：

.. code-block:: systemverilog

     function void build_phase(uvm_phase phase);
       super.build_phase(phase);

       // Create environment (which creates env_cfg internally)
       env = core_eh2_env::type_id::create("env", this);

       // env.cfg is created in env's constructor, so it's available immediately
       env_cfg = env.cfg;

       if (!uvm_config_db#(virtual core_eh2_tb_intf)::get(null, "", "tb_vif", tb_vif)) begin
         `uvm_fatal(test_name, "Cannot get tb_vif")
       end

       if (!uvm_config_db#(virtual eh2_halt_run_intf)::get(null, "", "halt_run_vif", halt_run_vif)) begin
         `uvm_info(test_name, "halt_run_vif not set; halt/load helper tasks disabled", UVM_LOW)
       end

       // Build ISA string
       build_isa_string();

       `uvm_info(test_name, $sformatf("ISA: %s", isa_string), UVM_LOW)
     endfunction

逐段解释：

* 第 L76-L80 行：通过 UVM factory 创建 ``env``，并把 ``env.cfg`` 保存为 ``env_cfg``。
* 第 L82-L84 行：获取 ``tb_vif``；失败时直接 ``uvm_fatal``，说明 base test 必须依赖
  TB service interface。
* 第 L86-L88 行：获取 ``halt_run_vif``；失败时只打印 info，因此 halt/load helper 可选禁用。
* 第 L90-L93 行：调用 ``build_isa_string`` 并打印 ISA 字符串。

接口关系：

* 被调用：UVM build phase。
* 调用：``core_eh2_env::type_id::create``、``uvm_config_db::get``、``build_isa_string``。
* 共享状态：写 ``env``、``env_cfg``、``tb_vif``、``halt_run_vif``、``isa_string``。

§4.3  ``end_of_elaboration_phase()`` — cosim 配置和 pending binary
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在 elaboration 结束后，把 ISA、boot PC、mtvec、PMP/MHPM 计数字段写入 cosim
scoreboard 的配置字符串，并把 binary 路径延迟交给 scoreboard。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L99-L128``）：

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
           0,             // pmp_granularity
           0              // mhpm_counter_num
         );
         env.cosim_agt.scoreboard.cosim_config = cosim_cfg_str;
         `uvm_info(test_name, $sformatf("Cosim config: %s", cosim_cfg_str), UVM_LOW)

逐段解释：

* 第 L99-L104 行：仅当 ``env_cfg.enable_cosim`` 且 scoreboard 存在时生成配置。
* 第 L106-L113 行：配置字符串包含 ``isa``、``pc``、``mtvec``、``pmp_regions``、
  ``pmp_granularity`` 和 ``mhpm_counters``；``mtvec`` 使用 ``env_cfg.boot_addr`` 清低 8 位。
* 第 L114-L115 行：把字符串写入 ``env.cosim_agt.scoreboard.cosim_config`` 并打印。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L118-L127``）：

.. code-block:: systemverilog

       // Set pending binary path for cosim (loaded during init_cosim, avoids race)
       if (env_cfg.enable_cosim && env.cosim_agt.scoreboard != null && env_cfg.binary != "") begin
         env.cosim_agt.scoreboard.pending_bin_path  = env_cfg.binary;
         env.cosim_agt.scoreboard.pending_base_addr = env_cfg.boot_addr;
         `uvm_info(test_name, $sformatf("Deferred cosim binary load: %s at 0x%08x",
           env_cfg.binary, env_cfg.boot_addr), UVM_LOW)
       end

       `uvm_info(test_name, "Test environment:", UVM_LOW)
       env.print();

逐段解释：

* 第 L119-L123 行：当 cosim 打开、scoreboard 存在且 binary 非空时，记录
  ``pending_bin_path`` 和 ``pending_base_addr``。
* 第 L126-L127 行：打印环境标题并调用 ``env.print()``。

接口关系：

* 被调用：UVM end-of-elaboration phase。
* 调用：scoreboard 字段赋值和 ``env.print``。
* 共享状态：读 ``env_cfg``，写 ``cosim_agt.scoreboard`` 的配置字段。

§4.4  ``run_phase()`` — base test 主流程
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：管理 objection，加载 binary，启动 virtual sequence，等待 completion，停止 sequence，
再释放 objection。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L133-L156``）：

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
       `uvm_info(test_name, "Completion detected", UVM_LOW)

       `uvm_info(test_name, "Test finished", UVM_LOW)

       // Stop virtual sequence
       if (vseq != null) vseq.stop();

       phase.drop_objection(this);
     endtask

逐段解释：

* 第 L134 行：进入 run phase 后先 raise objection。
* 第 L138-L143 行：调用 ``load_binary_to_mem``，再创建/启动 virtual sequence。
* 第 L146-L148 行：调用 ``wait_for_completion``，该 task 内部由 mailbox、wall-clock、
  cycle count 和 double-fault 四路竞争结束。
* 第 L152-L155 行：如果 ``vseq`` 非空则调用 ``stop``，最后 drop objection。

接口关系：

* 被调用：UVM run phase。
* 调用：``load_binary_to_mem``、``start_vseq``、``wait_for_completion``、``vseq.stop``。
* 共享状态：读写 ``vseq``，通过 helper 访问 ``tb_vif`` 和 ``env_cfg``。

§4.5  ``load_binary_to_mem()`` — hex/raw binary 分派
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：根据 ``env_cfg.binary`` 判断是否加载 binary；如果 TB 顶层已 early load，则跳过；
否则按后缀选择 hex 或 raw binary 加载路径。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L204-L226``）：

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

       `uvm_info(test_name, $sformatf("Loading binary: %s at 0x%08x", bin_path, env_cfg.boot_addr), UVM_LOW)

       if (bin_path.len() > 4 && bin_path.substr(bin_path.len()-4, bin_path.len()-1) == ".hex") begin
         load_hex_to_mem(bin_path);
       end else begin
         load_raw_binary_to_mem(bin_path, env_cfg.boot_addr);
       end
     endtask

逐段解释：

* 第 L207-L211 行：读取 ``env_cfg.binary``；空字符串时不加载。
* 第 L213-L217 行：如果 ``tb_vif.early_bin_loaded`` 为真，说明 TB 顶层已经通过 ``$readmemh``
  预加载 hex，UVM 不重复加载。
* 第 L219-L225 行：根据文件名最后 4 个字符是否等于 ``.hex`` 选择 ``load_hex_to_mem`` 或
  ``load_raw_binary_to_mem``。

接口关系：

* 被调用：base test 和 integrity tests 的 run/main phase。
* 调用：``load_hex_to_mem`` 或 ``load_raw_binary_to_mem``。
* 共享状态：读 ``env_cfg.binary``、``env_cfg.boot_addr``、``tb_vif.early_bin_loaded``。

§4.6  raw/hex loader 与 ``write_mem_byte()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：raw loader 逐 byte 读二进制文件，hex loader 解析 ``@ADDR`` 和 hex 字符；两者最终都
调用 ``write_mem_byte``，再由 TB service interface 写三组 AXI4 memory。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L229-L251``）：

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
         if (byte_val == 1) begin
           write_mem_byte(addr, mem_byte);
           addr++;
         end
       end
       $fclose(fd);

       `uvm_info(test_name, $sformatf("Loaded %0d bytes from raw binary", addr - base_addr), UVM_LOW)
     endtask

逐段解释：

* 第 L235-L238 行：以 ``rb`` 打开 raw binary；打开失败时 fatal。
* 第 L240-L247 行：从 ``base_addr`` 开始逐 byte 读取；``$fread`` 返回 1 时写入 memory 并
  递增地址。
* 第 L248-L250 行：关闭文件并打印加载字节数。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L273-L321``）：

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
             else if (c >= "A" && c <= "F") new_addr = (new_addr << 4) | (c - "A" + 10);
             else break;  // Non-hex char ends address
           end
           addr = new_addr;
           nybble_count = 0;
           val = 0;

逐段解释：

* 第 L273-L275 行：逐字符读取 hex 文件，到 EOF 时退出。
* 第 L277-L289 行：遇到 ``@`` 后解析后续十六进制地址，支持数字、小写 a-f 和大写 A-F。
* 第 L289-L291 行：将解析出的地址写入 ``addr``，并清空当前 byte 累积状态。
* 第 L292-L321 行：源文件后续累积 hex nybble，在空白字符或文件结束时调用
  ``write_mem_byte``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L323-L333``）：

.. code-block:: systemverilog

     // Write a byte to all AXI4 memory models via backdoor
     virtual task write_mem_byte(bit [31:0] addr, bit [7:0] data);
       tb_vif.write_mem_byte(addr, data);
     endtask

     // Load binary into co-simulation reference model
     virtual task load_binary_to_cosim(string bin_path, bit [31:0] addr);
       if (env.cosim_agt.scoreboard != null) begin
         env.cosim_agt.scoreboard.load_binary(bin_path, addr);
       end
     endtask

逐段解释：

* 第 L324-L326 行：``write_mem_byte`` 不直接访问 hierarchy，而是调用
  ``tb_vif.write_mem_byte``。
* 第 L329-L332 行：``load_binary_to_cosim`` 在 scoreboard 存在时调用
  ``scoreboard.load_binary``。

接口关系：

* 被调用：``load_binary_to_mem``、raw loader、hex loader 和需要 cosim backdoor 的路径。
* 调用：``$fopen``、``$fread``、``$fgetc``、``tb_vif.write_mem_byte``、scoreboard
  ``load_binary``。
* 共享状态：读文件系统 binary/hex，写 TB memory service 和 cosim scoreboard。

§4.7  ``wait_for_completion()`` — 四路 completion 竞争
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：同时等待 signature mailbox、wall-clock timeout、cycle timeout 和 double-fault detector；
任一分支返回后关闭其它分支。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L347-L378``）：

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
         end

         // Way 3: Cycle count timeout
         begin
           tb_vif.wait_clks(env_cfg.max_cycles);
           `uvm_error(test_name, $sformatf("Cycle timeout: %0d cycles", env_cfg.max_cycles))

逐段解释：

* 第 L349-L355 行：signature 分支只有在 ``env_cfg.use_signature`` 打开时调用
  ``wait_for_signature``。
* 第 L357-L361 行：wall-clock 分支使用 ``env_cfg.timeout_ns`` 延时并上报 UVM error。
* 第 L363-L367 行：cycle 分支通过 ``tb_vif.wait_clks(env_cfg.max_cycles)`` 等待 cycle 数。
* 第 L369-L378 行：源文件后续加入 double-fault 分支；``join_any`` 返回后 ``disable fork``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L382-L414``）：

.. code-block:: systemverilog

     virtual task wait_for_signature();
       forever begin
         @(posedge tb_vif.clk);
         if (tb_vif.mailbox_test_done) begin
           // Check which event fired
           if (tb_vif.mailbox_data[7:0] == 8'hFF) begin
             `uvm_info(test_name, "TEST PASSED (signature)", UVM_LOW)
           end else begin
             `uvm_error(test_name, "TEST FAILED (signature)")
           end
           // EH2 can retire the mailbox store before the external AXI write
           // response is observed. Leave a short drain window so monitors and
           // scoreboards can close outstanding transactions before report_phase.
           tb_vif.wait_clks(10);
           return;
         end
       end
     endtask

逐段解释：

* 第 L383-L385 行：每个 ``tb_vif.clk`` 上升沿轮询 ``mailbox_test_done``。
* 第 L387-L391 行：低 8 位等于 ``8'hFF`` 时打印 PASS，否则报 UVM error。
* 第 L392-L396 行：完成后等待 10 个 clock 作为 AXI/scoreboard drain 窗口。
* 第 L402-L414 行：``detect_double_fault`` 每 1000 ns 检查
  ``env.trace_monitor.exception_count`` 是否超过 ``env_cfg.double_fault_threshold``。

接口关系：

* 被调用：``run_phase`` 和若干重写 run_phase 的子类。
* 调用：``wait_for_signature``、``detect_double_fault``、``tb_vif.wait_clks``。
* 共享状态：读 ``env_cfg``、``tb_vif`` 和 ``env.trace_monitor``。

§4.8  signature/CSR helper — mailbox 语义复用
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：提供等待 mailbox transaction、检查 core status、等待特定 CSR 写入的公共 helper。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L422-L465``）：

.. code-block:: systemverilog

     virtual task wait_for_mem_txn(output bit [31:0] addr, output bit [31:0] data,
                                    output bit is_write);
       // Wait for a mailbox write event
       @(posedge tb_vif.mailbox_write);
       addr    = tb_vif.mailbox_addr;
       data    = tb_vif.mailbox_data[31:0];
       is_write = 1;
     endtask

     // Check next core status from signature
     virtual task check_next_core_status(input int expected_status);
       bit [31:0] addr, data;
       bit is_write;
       wait_for_mem_txn(addr, data, is_write);
       if (is_write && addr == SIGNATURE_ADDR) begin
         if (data[7:0] != expected_status[7:0]) begin
           `uvm_error(test_name, $sformatf(
             "Core status mismatch: expected=%0d got=%0d",
             expected_status, data[7:0]))

逐段解释：

* 第 L422-L429 行：``wait_for_mem_txn`` 等 ``tb_vif.mailbox_write`` 上升沿，然后返回地址、
  低 32 位数据，并把 ``is_write`` 固定为 1。
* 第 L432-L440 行：``check_next_core_status`` 调用 ``wait_for_mem_txn``，只在地址等于
  ``SIGNATURE_ADDR`` 时比较低 8 位 status。
* 第 L446-L465 行：源文件后续 ``wait_for_core_status`` 和 ``wait_for_csr_write`` 在 loop 中
  反复等待 mailbox，直到 status 或 CSR address 匹配。

接口关系：

* 被调用：directed debug helper、CSR helper、integration tests。
* 调用：``wait_for_mem_txn`` 和 UVM report 宏。
* 共享状态：读 ``tb_vif.mailbox_*`` 和 ``SIGNATURE_ADDR``。

§5  ``core_eh2_directed_test`` — directed 模式公共基类
--------------------------------------------------------------------------------

§5.1  ``send_stimulus()`` 和 ``check_stimulus()`` hook
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：为 directed 场景提供 Ibex-style 的 stimulus/check 框架：后台启动 vseq，等待 core 初始化，
fork 子类 ``check_stimulus``，再等 mailbox done。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L22-L39``）：

.. code-block:: systemverilog

   class core_eh2_directed_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_directed_test)

     function new(string name = "core_eh2_directed_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction

     // =========================================================================
     // Instruction tracking types
     // =========================================================================

     typedef struct {
       bit [6:0]  opcode;
       bit [2:0]  funct3;
       bit [6:0]  funct7;
       bit [11:0] system_imm;  // 12-bit immediate for SYSTEM instructions
     } instr_t;

逐段解释：

* 第 L22-L28 行：``core_eh2_directed_test`` 继承 base test 并注册 UVM factory。
* 第 L34-L39 行：局部 ``instr_t`` 与 package 中的结构字段一致，用于记录已见 instruction。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L87-L124``）：

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
             check_stimulus();
           join_none

逐段解释：

* 第 L87-L92 行：``send_stimulus`` fork 出后台分支启动 ``vseq.start(env.vseqr)``。
* 第 L94-L99 行：第二个分支先等待 core setup mailbox，再等待 50 个 clock。
* 第 L101-L103 行：以 ``join_none`` 启动子类覆盖的 ``check_stimulus``。
* 第 L105-L116 行：源文件后续等待 ``wait_test_done``，停止 vseq，等待 100 个 clock，然后
  ``disable fork``。
* 第 L122-L124 行：基类 ``check_stimulus`` 直接 fatal，说明该类不应直接作为测试运行。

接口关系：

* 被调用：directed 子类可复用 ``send_stimulus`` 或覆盖 ``check_stimulus``。
* 调用：``vseq.start``、``wait_for_core_setup``、``tb_vif.wait_clks``、``wait_test_done``。
* 共享状态：读写 ``vseq``，读取 mailbox 状态。

§5.2  DCSR/debug helper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：通过 JTAG 写 ``DMI_DMCONTROL`` 发出 debug halt/resume，等待 signature status
``DEBUG_REQ``，读取/缓存 DCSR，并检查 ``dcsr.prv`` 和 ``dcsr.cause``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L166-L218``）：

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
         eh2_jtag_seq_item::DMI_DMCONTROL, 32'h80000001);

       // Wait for core to acknowledge debug mode entry
       fork
         begin
           wait_for_core_status(DEBUG_REQ);

逐段解释：

* 第 L166-L171 行：参数包括期望 privilege mode、状态消息、可选 JTAG sequencer 和 halt
  timeout。
* 第 L175-L180 行：如果调用者未传 sequencer，则使用 ``env.jtag_agent.sequencer``；随后向
  ``DMI_DMCONTROL`` 写 ``32'h80000001``。
* 第 L183-L193 行：fork 出 status 等待和 timeout 两个分支；status 分支等待
  ``DEBUG_REQ``。
* 第 L204-L215 行：源文件后续等待 ``CSR_DCSR`` 写、缓存 ``dcsr_data``，调用
  ``check_dcsr_prv``、``check_dcsr_cause``，再写 ``32'h40000000`` resume。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L245-L296``）：

.. code-block:: systemverilog

     // Debug entry cause codes (RISC-V Debug Spec)
     localparam bit [2:0] DBG_CAUSE_EBREAK   = 3'd1;
     localparam bit [2:0] DBG_CAUSE_TRIGGER  = 3'd2;
     localparam bit [2:0] DBG_CAUSE_HALTREQ  = 3'd3;
     localparam bit [2:0] DBG_CAUSE_STEP     = 3'd4;
     localparam bit [2:0] DBG_CAUSE_RESETHALT = 3'd5;

     // CSR addresses for debug-mode CSRs
     localparam bit [11:0] CSR_DCSR = 12'h7B0;
     localparam bit [11:0] CSR_DPC  = 12'h7B1;

     // Check dcsr.ebreak against the privilege mode encoded in dcsr.prv.
     // Verifies that the ebreak bit for the current privilege mode is set.
     virtual function void check_dcsr_ebreak();
       case (dcsr_data[1:0])
         2'b11: begin  // M-mode
           if (dcsr_data[15] !== 1'b1)

逐段解释：

* 第 L246-L250 行：定义 debug entry cause code，包括 ebreak、trigger、haltreq、step、
  resethalt。
* 第 L253-L254 行：DCSR 和 DPC CSR 地址分别为 ``12'h7B0`` 和 ``12'h7B1``。
* 第 L258-L280 行：``check_dcsr_ebreak`` 根据 ``dcsr_data[1:0]`` 判断 M/S/U mode，并检查
  对应 ebreak bit。
* 第 L283-L296 行：``check_dcsr_cause`` 检查 ``dcsr_data[8:6]``；
  ``check_dcsr_prv`` 检查 ``dcsr_data[1:0]``。

接口关系：

* 被调用：debug directed tests 或子类 hook。
* 调用：``eh2_jtag_seq::send_write``、``wait_for_core_status``、``wait_for_csr_write`` 和
  DCSR 检查函数。
* 共享状态：读 ``env.jtag_agent.sequencer``，写/读 ``dcsr_data``。

§5.3  instruction tracking — ``decode_instr()`` 与 compressed 去重
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把已见普通/压缩 instruction 类型记入队列，帮助 directed test 在第一次遇到某类
instruction 时触发 stimulus。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L313-L398``）：

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
           // Identified by opcode alone
           foreach (seen_instr[i]) begin
             if (opcode == seen_instr[i].opcode)
               return 0;
           end

逐段解释：

* 第 L313-L323 行：从 32 位 instruction 拆出 opcode、funct3、funct7 和 ``system_imm``。
* 第 L325-L332 行：LUI、AUIPC、JAL 只按 opcode 去重。
* 第 L334-L386 行：load/store/branch/JALR/misc-mem 按 opcode+funct3；OP-IMM shift 额外比较
  funct7；OP 比较 opcode+funct3+funct7；SYSTEM 对 WFI/ECALL/MRET/DRET/CSR 做特殊处理。
* 第 L394-L397 行：若未命中已见队列，则 push ``instr_fields`` 并返回 1。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L402-L466``）：

.. code-block:: systemverilog

     virtual function bit decode_compressed_instr(bit [15:0] instr);
       foreach (seen_compressed_instr[i]) begin
         if (instr[1:0] == seen_compressed_instr[i][1:0]) begin
           case (instr[1:0])
             2'b00: begin  // C0 quadrant
               if (instr[15:13] == seen_compressed_instr[i][15:13])
                 return 0;
             end

             2'b01: begin  // C1 quadrant
               if (instr[15:13] == seen_compressed_instr[i][15:13]) begin
                 case (instr[15:13])
                   3'b000, 3'b001, 3'b010,
                   3'b011, 3'b101, 3'b110, 3'b111: begin

逐段解释：

* 第 L402-L408 行：compressed instruction 先按 quadrant ``instr[1:0]`` 和
  ``instr[15:13]`` 比较。
* 第 L411-L435 行：C1 quadrant 对 ``3'b100`` 再细分 ``instr[11:10]``、``instr[12]`` 和
  ``instr[6:5]``。
* 第 L439-L451 行：C2 quadrant 对 ``3'b100`` 额外比较 ``instr[12]``，其它非法编码会 fatal。
* 第 L463-L465 行：未见过则把 16 位 instruction push 到 ``seen_compressed_instr``。

接口关系：

* 被调用：directed tests 可用这些函数决定是否触发 interrupt/debug stimulus。
* 调用：只访问队列和 UVM fatal。
* 共享状态：读写 ``seen_instr`` 和 ``seen_compressed_instr``。

§6  ``core_eh2_test_lib.sv`` — 常规 test class 分组
--------------------------------------------------------------------------------

§6.1  后台 IRQ/Debug/Stress test
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 class 通过覆盖 ``start_vseq`` 或 ``run_phase`` fork 出 IRQ/JTAG 背景刺激，再调用
base completion 流程。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L495-L522``）：

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
           forever begin
             #($urandom_range(500, 5000) * 10ns);
             txn = eh2_irq_seq_item::type_id::create("txn");

逐段解释：

* 第 L495-L501 行：``core_eh2_irq_test`` 继承 base test 并注册 factory。
* 第 L505-L520 行：覆盖 ``start_vseq``，在 fork 背景分支中每隔随机时间创建
  ``eh2_irq_seq_item``，设置 external IRQ，再发送到 ``env.irq_agent.sequencer``。
* 第 L521 行：背景刺激 fork 后仍调用 ``super.start_vseq()``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L529-L599``）：

.. code-block:: systemverilog

   class core_eh2_debug_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_debug_test)

     function new(string name = "core_eh2_debug_test", uvm_component parent = null);
       super.new(name, parent);
     endfunction

     // Override start_vseq: fork a background debug_seq on the JTAG sequencer
     // so that the vseq body() doesn't return immediately (causing join_any
     // to complete at time 0).
     virtual task start_vseq();
       debug_seq dbg_h;
       fork
         begin
           dbg_h = debug_seq::type_id::create("dbg_h");

逐段解释：

* 第 L529-L552 行：``core_eh2_debug_test`` 创建 ``debug_seq``，把 ``env.vseqr.jtag_seqr``
  赋给它，设置 ``stress_mode = 1``，再启动。
* 第 L559-L599 行：``core_eh2_stress_test`` 在一个 fork 中并行生成 IRQ stimulus 和 JTAG
  halt/resume stimulus，然后调用 ``super.start_vseq``。

接口关系：

* 被调用：UVM factory 根据 ``+UVM_TESTNAME`` 创建这些 test。
* 调用：``eh2_irq_seq::send_irq``、``debug_seq.start``、``eh2_jtag_seq::send_write``。
* 共享状态：读 ``env.irq_agent.sequencer``、``env.jtag_agent.sequencer``、``env.vseqr``。

§6.2  配置型 test — 只改 ``env_cfg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：部分 test 不重写 run phase，而是在 ``build_phase`` 中关闭/打开特定 stimulus 或调整
timeout/cycle。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L606-L637``）：

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

     `uvm_component_utils(core_eh2_cosim_test)

逐段解释：

* 第 L606-L616 行：``core_eh2_bitmanip_test`` 只覆盖 ISA 字符串，值为
  ``rv32imac_zba_zbb_zbc_zbs``。
* 第 L623-L635 行：``core_eh2_cosim_test`` 在 ``build_phase`` 中设置
  ``env_cfg.enable_cosim = 1``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L886-L1013``）：

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
     endfunction

   endclass

逐段解释：

* 第 L886-L900 行：``core_eh2_csr_test`` 关闭单 IRQ、多 IRQ 和 debug stress。
* 第 L907-L919 行：``core_eh2_load_store_test`` 关闭单 IRQ 和 debug stress。
* 第 L926-L957 行：``core_eh2_muldiv_test`` 和 ``core_eh2_atomic_test`` 同样关闭单 IRQ 和
  debug stress。
* 第 L964-L1013 行：``core_eh2_dual_issue_test`` 关闭单 IRQ/debug stress；
  ``core_eh2_fetch_toggle_test`` 打开 ``enable_fetch_toggle``。

接口关系：

* 被调用：UVM build phase。
* 调用：``super.build_phase``。
* 共享状态：只改 ``env_cfg`` 字段，沿用 base ``run_phase``。

§6.3  IRQ/PIC/JTAG run_phase 重写
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 test 重写 ``run_phase``，先加载 binary，再并行启动定向 stimulus、vseq 和
completion。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L650-L674``）：

.. code-block:: systemverilog

     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "Timer IRQ test started", UVM_LOW)
       load_binary_to_mem();
       fork
         run_timer_stimulus();
         start_vseq();
         wait_for_completion(phase);
       join_any
       disable fork;
       phase.drop_objection(this);
     endtask

     virtual task run_timer_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       forever begin
         #($urandom_range(1000, 5000) * 10ns);
         txn = eh2_irq_seq_item::type_id::create("txn");
         txn.irq_type = eh2_irq_seq_item::IRQ_TIMER;
         txn.irq_val = 1'b1;
         txn.duration = $urandom_range(5, 20);
         eh2_irq_seq::send_irq(env.irq_agent.sequencer, txn);

逐段解释：

* 第 L650-L661 行：``core_eh2_timer_irq_test`` 的 run phase 用 ``fork/join_any`` 并行执行
  timer stimulus、vseq 和 completion。
* 第 L663-L674 行：timer stimulus 每隔随机时间创建 ``IRQ_TIMER`` transaction 并发送。
* 第 L681-L713 行：``core_eh2_soft_irq_test`` 结构相同，但 ``irq_type`` 为
  ``IRQ_SOFTWARE``。
* 第 L720-L753 行：``core_eh2_nmi_test`` 结构相同，但源代码设置 ``IRQ_EXTERNAL`` 和
  ``irq_id = 1``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1028-L1055``）：

.. code-block:: systemverilog

     virtual task run_phase(uvm_phase phase);
       phase.raise_objection(this);
       `uvm_info(test_name, "PIC test started", UVM_LOW)
       load_binary_to_mem();
       start_vseq();
       fork
         run_pic_stimulus();
         wait_for_completion(phase);
       join_any
       disable fork;
       if (vseq != null) vseq.stop();
       phase.drop_objection(this);
     endtask

     virtual task run_pic_stimulus();
       eh2_irq_seq_item txn;
       #10000ns;
       // Test different PIC priority levels
       repeat (20) begin
         #($urandom_range(1000, 5000) * 10ns);
         txn = eh2_irq_seq_item::type_id::create("txn");

逐段解释：

* 第 L1028-L1040 行：``core_eh2_pic_test`` 先启动 vseq，再 fork PIC stimulus 和 completion。
* 第 L1042-L1055 行：PIC stimulus 重复 20 次，IRQ ID 从 1 到 31 随机，注释说明 lower IDs
  对应 higher priority。

接口关系：

* 被调用：UVM run phase。
* 调用：``load_binary_to_mem``、``start_vseq``、``wait_for_completion``、
  ``eh2_irq_seq::send_irq``。
* 共享状态：读 ``env.irq_agent.sequencer`` 和 ``vseq``。

§6.4  extended debug/IRQ interaction tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：覆盖 WFI、CSR、nested IRQ、IRQ in debug、debug in IRQ、DRET、EBREAK、single debug
pulse 和 fetch enable check 等 run-phase 模式。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1368-L1444``）：

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
       fork
         run_debug_wfi_stimulus();
         start_vseq();
         wait_for_completion(phase);

逐段解释：

* 第 L1368-L1387 行：``core_eh2_debug_wfi_test`` 的 run phase 并行运行 debug-WFI stimulus、
  vseq 和 completion。
* 第 L1389-L1402 行：``run_debug_wfi_stimulus`` 周期性写 ``DMI_DMCONTROL`` 的 halt 值
  ``32'h80000001``，短延时后写 resume 值 ``32'h40000000``。
* 第 L1410-L1444 行：``core_eh2_debug_csr_test`` 使用相同 halt/resume 写法，但间隔更短以
  捕获 CSR 操作窗口。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L1482-L1613``）：

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
       fork
         run_irq_wfi_stimulus();
         start_vseq();
         wait_for_completion(phase);

逐段解释：

* 第 L1482-L1501 行：``core_eh2_irq_wfi_test`` 并行运行 IRQ-WFI stimulus、vseq 和 completion。
* 第 L1503-L1516 行：IRQ-WFI stimulus 等待随机时间后发送 external IRQ，持续
  ``50`` 到 ``200`` 个 cycle。
* 第 L1524-L1558 行：``core_eh2_irq_csr_test`` 用更短随机间隔发送 external IRQ，以覆盖
  CSR 指令窗口。
* 第 L1566-L1613 行：``core_eh2_irq_nest_test`` 在循环中 fork 多个 external IRQ transaction，
  触发 nested interrupt 场景。

接口关系：

* 被调用：UVM run phase。
* 调用：JTAG ``send_write``、IRQ ``send_irq``、base helper。
* 共享状态：读 ``env.jtag_agent.sequencer``、``env.irq_agent.sequencer``。

§6.5  class 清单与配置行为索引
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：把 ``core_eh2_test_lib.sv`` 中的 test class 按源码行为归类，避免只列名称不说明 hook。

.. list-table::
   :header-rows: 1
   :widths: 34 24 42

   * - class
     - 主要 hook
     - 源码行为
   * - ``core_eh2_irq_test``
     - ``start_vseq``
     - 后台随机 external IRQ，随后调用 ``super.start_vseq``。
   * - ``core_eh2_debug_test``
     - ``start_vseq``
     - 创建 ``debug_seq``，设置 ``stress_mode = 1`` 并启动。
   * - ``core_eh2_stress_test``
     - ``start_vseq``
     - 并行 IRQ stimulus 和 JTAG halt/resume。
   * - ``core_eh2_bitmanip_test``
     - ``build_isa_string``
     - ISA 字符串为 ``rv32imac_zba_zbb_zbc_zbs``。
   * - ``core_eh2_cosim_test``
     - ``build_phase``
     - 设置 ``env_cfg.enable_cosim = 1``。
   * - ``core_eh2_timer_irq_test`` / ``core_eh2_soft_irq_test``
     - ``run_phase``
     - 分别发送 ``IRQ_TIMER`` 和 ``IRQ_SOFTWARE``。
   * - ``core_eh2_nmi_test`` / ``core_eh2_nested_irq_test``
     - ``run_phase``
     - NMI test 发送 external IRQ ID 1；nested test 重复发送多个 external IRQ。
   * - ``core_eh2_debug_stress_test`` / ``core_eh2_debug_step_test``
     - ``run_phase``
     - 前者循环 halt/resume；后者写 ``DMI_ABSTRACTCS`` 后 step/resume。
   * - ``core_eh2_csr_test`` / ``core_eh2_load_store_test`` / ``core_eh2_muldiv_test``
     - ``build_phase``
     - 关闭部分随机 IRQ/debug stimulus。
   * - ``core_eh2_atomic_test`` / ``core_eh2_dual_issue_test``
     - ``build_phase``
     - 关闭单 IRQ/debug stress。
   * - ``core_eh2_fetch_toggle_test`` / ``core_eh2_stall_test``
     - ``build_phase``
     - 打开 ``enable_fetch_toggle``；stall test 还设置 ``max_interval = 100``。
   * - ``core_eh2_pic_test``
     - ``run_phase``
     - 发送 20 次 external IRQ，ID 范围 1 到 31。
   * - ``core_eh2_mem_error_test``
     - ``build_phase``
     - 设置 ``enable_mem_error = 1``。
   * - ``core_eh2_irq_debug_test``
     - ``build_phase``
     - 打开 ``enable_irq_single_seq`` 和 ``enable_debug_single``。
   * - PMP/ePMP/PC/RF/reset/single-step 类
     - ``build_phase``
     - 主要调整 ``timeout_ns``、``max_cycles`` 或 ``enable_debug_single``。
   * - WFI/CSR/IRQ/debug interaction 类
     - ``run_phase``
     - 在 run phase 并行具体 stimulus、vseq 和 completion。

§7  ``core_eh2_intg_test_lib.sv`` — RTL-only integrity 注入
--------------------------------------------------------------------------------

§7.1  VPI helper — path check/read/force/release
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：封装 ``uvm_hdl_check_path``、``uvm_hdl_read``、``uvm_hdl_force`` 和
``uvm_hdl_release``，失败时用 ``uvm_fatal`` 终止。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L12-L34``）：

.. code-block:: systemverilog

   function automatic bit core_eh2_intg_path_exists(string path);
     return (uvm_hdl_check_path(path) == 1);
   endfunction

   task automatic core_eh2_intg_read_or_fatal(string id, string path,
                                              output uvm_hdl_data_t value);
     if (!uvm_hdl_read(path, value)) begin
       `uvm_fatal(id, $sformatf("uvm_hdl_read failed for %s", path))
     end
   endtask

   task automatic core_eh2_intg_force_or_fatal(string id, string path,
                                               uvm_hdl_data_t value);
     if (!uvm_hdl_force(path, value)) begin
       `uvm_fatal(id, $sformatf("uvm_hdl_force failed for %s", path))

逐段解释：

* 第 L12-L14 行：``core_eh2_intg_path_exists`` 返回 ``uvm_hdl_check_path`` 是否等于 1。
* 第 L16-L21 行：read helper 调用 ``uvm_hdl_read``；失败时 fatal 并带路径字符串。
* 第 L23-L28 行：force helper 调用 ``uvm_hdl_force``；失败时 fatal。
* 第 L30-L34 行：release helper 调用 ``uvm_hdl_release``；失败时 fatal。

接口关系：

* 被调用：所有 integrity test 的 ``main_phase``。
* 调用：UVM HDL/VPI API。
* 共享状态：通过字符串层级路径读写 RTL 仿真对象。

§7.2  ``core_eh2_rf_addr_intg_test`` — register file 地址 force
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：禁用 cosim，寻找 register file read address path，等待 live read，force 一个不同地址，
确认 force 生效，再短暂观察 TLU exception path。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L41-L61``）：

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

     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.enable_cosim = 0;

逐段解释：

* 第 L41-L47 行：class 保存 RF 地址/rden 路径和默认 TLU trap path。
* 第 L49-L53 行：构造函数把 ``test_name`` 设置为传入 name。
* 第 L55-L61 行：build phase 禁用 cosim，设置 ``timeout_ns`` 为
  ``64'd5_000_000_000``，``max_cycles`` 为 ``500_000``。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L75-L118``）：

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
       if (!core_eh2_intg_path_exists(rf_addr_path)) begin
         `uvm_fatal(test_name, "No EH2 register-file read-address path found")
       end

逐段解释：

* 第 L75-L79 行：raise objection，加载 binary，启动 vseq，等待 reset 释放后再等 100 个 clock。
* 第 L81-L89 行：先尝试 ``raddr0/rden0``，不存在则切换到 ``raddr1/rden1``；两者都不存在时
  fatal。
* 第 L91-L103 行：源文件后续最多等待 2000 个 clock，寻找 ``rden`` 且地址非 0 的 live read。
* 第 L105-L118 行：翻转地址 bit 0，避免 x0，force 路径，``#1step`` 后读取确认，再 release。

接口关系：

* 被调用：UVM main phase。
* 调用：base ``load_binary_to_mem``、``start_vseq``、VPI helper。
* 共享状态：force/release RTL register file read address path。

§7.3  DCCM/ICache/memory integrity counter tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：对 DCCM、ICache、ICCM/DCCM integrity pulse 做短暂 force，读取对应 TLU counter，要求
counter 在限定 clock 内发生变化。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L140-L161``）：

.. code-block:: systemverilog

   class core_eh2_ram_intg_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_ram_intg_test)

     string ecc_pulse_path = "core_eh2_tb_top.dut.veer.lsu.lsu_single_ecc_error_incr";
     string counter_path   = "core_eh2_tb_top.dut.veer.dec.tlu.mdccmect";
     string valid_path     = "core_eh2_tb_top.dut.veer.lsu.lsu_p.valid";

     function new(string name = "core_eh2_ram_intg_test",
                  uvm_component parent = null);
       super.new(name, parent);
       test_name = name;
     endfunction

     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);

逐段解释：

* 第 L140-L146 行：DCCM RAM integrity test 使用 ``lsu_single_ecc_error_incr`` 作为 pulse
  path，使用 ``mdccmect`` 作为 counter path，并可观察 ``lsu_p.valid``。
* 第 L154-L161 行：build phase 禁用 cosim，打开 ``enable_mem_error``，并设置 5 秒 timeout
  和 500000 cycles。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L201-L220``）：

.. code-block:: systemverilog

       core_eh2_intg_read_or_fatal(test_name, counter_path, before_count);
       `uvm_info(test_name,
         $sformatf("Injecting DCCM RAM ECC pulse; MDCCMECT before=%0d",
                   before_count[26:0]), UVM_LOW)
       core_eh2_intg_force_or_fatal(test_name, ecc_pulse_path, 1);
       tb_vif.wait_clks(1);
       core_eh2_intg_release_or_fatal(test_name, ecc_pulse_path);

       for (i = 0; i < 20; i++) begin
         tb_vif.wait_clks(1);
         core_eh2_intg_read_or_fatal(test_name, counter_path, after_count);
         if (after_count[26:0] != before_count[26:0]) break;
       end
       if (after_count[26:0] == before_count[26:0]) begin
         `uvm_fatal(test_name, "MDCCMECT did not increment after RAM integrity injection")
       end

逐段解释：

* 第 L201-L204 行：读取 force 前的 ``MDCCMECT`` 低 27 位并打印。
* 第 L205-L207 行：force ECC pulse 为 1，等待 1 个 clock 后 release。
* 第 L209-L213 行：最多等待 20 个 clock，重复读取 counter，发现变化即退出。
* 第 L214-L220 行：若低 27 位未变化则 fatal，否则打印 PASS 信息。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:L317-L340``）：

.. code-block:: systemverilog

   class core_eh2_mem_intg_error_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_mem_intg_error_test)

     string iccm_error_path = "core_eh2_tb_top.dut.veer.iccm_dma_sb_error";
     string dccm_error_path = "core_eh2_tb_top.dut.veer.lsu.lsu_single_ecc_error_incr";
     string iccm_count_path = "core_eh2_tb_top.dut.veer.dec.tlu.miccmect";
     string dccm_count_path = "core_eh2_tb_top.dut.veer.dec.tlu.mdccmect";

     function new(string name = "core_eh2_mem_intg_error_test",
                  uvm_component parent = null);
       super.new(name, parent);
       test_name = name;
     endfunction

     virtual function void build_phase(uvm_phase phase);
       super.build_phase(phase);
       env_cfg.enable_cosim = 0;
       env_cfg.disable_cosim = 1;
       env_cfg.enable_mem_error = 1;
       env_cfg.enable_axi4_error_inject = 1;
       env_cfg.axi4_error_pct = 100;

逐段解释：

* 第 L321-L324 行：generic memory integrity test 同时定义 ICCM error、DCCM error、
  MICCMECT 和 MDCCMECT 路径。
* 第 L332-L340 行：build phase 禁用 cosim，打开 memory error、AXI4 error inject，并把
  ``axi4_error_pct`` 设置为 100。
* 第 L380-L386 行：源文件后续依次 force/release ICCM error 和 DCCM error。
* 第 L390-L406 行：最多等待 40 个 clock，要求两个 counter 都变化，否则 fatal。

接口关系：

* 被调用：UVM main phase。
* 调用：VPI helper、``tb_vif.wait_clks``、base loader/vseq。
* 共享状态：force RTL integrity pulse path，读取 TLU counter。

§8  ``core_eh2_rvfi_smoke_test.sv`` — RVFI 独立冒烟测试
--------------------------------------------------------------------------------

§8.1  build/run phase 与 RVFI monitor thread
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：从 config DB 获取 ``rvfi_vif``，并行启动 RVFI monitor 和 200 ms timeout；monitor 要求
至少 5 条 instruction retire。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv:L15-L45``）：

.. code-block:: systemverilog

   class core_eh2_rvfi_smoke_test extends core_eh2_base_test;

     `uvm_component_utils(core_eh2_rvfi_smoke_test)

     // RVFI interface for monitoring
     virtual eh2_rvfi_if rvfi_vif;

     // Expected instruction count
     localparam int MIN_RETIRED = 5;

     // Per-instruction tracking
     int           retired_count;
     string        retired_insn[$];
     bit [31:0]    retired_pc[$];
     bit [31:0]    retired_rd_wdata[$];

逐段解释：

* 第 L15-L20 行：该 class 继承 ``core_eh2_base_test``，并保存 ``eh2_rvfi_if`` virtual handle。
* 第 L22-L29 行：``MIN_RETIRED`` 固定为 5，并定义 retire 计数与 PC/insn/rd data 队列。
* 第 L31-L34 行：构造函数把 ``test_name`` 固定为 ``core_eh2_rvfi_smoke_test``。
* 第 L39-L45 行：build phase 调用父类后，从 config DB 获取 ``rvfi_vif``；失败时 warning。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv:L50-L61``）：

.. code-block:: systemverilog

     task run_phase(uvm_phase phase);
       phase.raise_objection(this);

       `uvm_info("RVFI_SMOKE", "Starting RVFI smoke test — expecting >= 5 retired instructions", UVM_LOW)

       fork
         rvfi_monitor_thread();
         timeout_thread();
       join_any

       phase.drop_objection(this);
     endtask

逐段解释：

* 第 L50-L53 行：run phase raise objection 并打印期望至少 5 条 retire。
* 第 L55-L58 行：``fork/join_any`` 并行启动 ``rvfi_monitor_thread`` 和 ``timeout_thread``。
* 第 L60 行：任一分支结束后 drop objection。

关键代码（``dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv:L66-L120``）：

.. code-block:: systemverilog

     task rvfi_monitor_thread();
       retired_count = 0;

       // Wait for reset deassertion
       @(posedge rvfi_vif.rst_l);

       forever begin
         @(posedge rvfi_vif.clk);
         if (rvfi_vif.rst_l) begin
           // Channel 0 (i0)
           if (rvfi_vif.rvfi_valid[0]) begin
             retired_count++;
             $display("RVFI: pc=%08x insn=%08x rd_addr=%0d rd_wdata=%08x mem_addr=%08x mem_wdata=%08x mem_rdata=%08x [i0, seq=%0d]",
               rvfi_vif.rvfi_pc_rdata[31:0],
               rvfi_vif.rvfi_insn[31:0],

逐段解释：

* 第 L66-L70 行：monitor 初始化 retire count，然后等待 ``rvfi_vif.rst_l`` 上升沿。
* 第 L72-L91 行：每个 clock 上升沿，如果 slot 0 valid，则递增计数、打印 PC/insn/rd/mem/order，
  并把 PC、insn、rd data push 到队列。
* 第 L93-L109 行：slot 1 使用 ``[63:32]`` 或 ``[9:5]`` 切片执行同样记录。
* 第 L111-L117 行：当 ``retired_count >= MIN_RETIRED`` 时打印 UVM PASS 信息和 ``$display``，
  然后 break。
* 第 L125-L129 行：timeout thread 延时 ``200_000_000``，若未达标则报 UVM error。

接口关系：

* 被调用：作为独立 UVM test 运行时由 factory 创建。
* 调用：``uvm_config_db::get``、``rvfi_monitor_thread``、``timeout_thread``。
* 共享状态：读取 ``rvfi_vif``，写 retire tracking 队列。

§9  ``test_signoff_gates.py`` — sign-off gate 单元测试
--------------------------------------------------------------------------------

§9.1  Gate 覆盖范围
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：用 pytest 覆盖 signoff.py 的 gate 逻辑，包括 coverage required、coverage 阈值、
cosim-disabled waiver、skip-in-signoff waiver、directed pool 完整性和 real-run rate。

关键代码（``dv/uvm/core_eh2/tests/test_signoff_gates.py:L1-L36``）：

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
   import os
   import sys
   import tempfile
   from pathlib import Path

   import pytest
   import yaml

   SCRIPT_DIR = Path(__file__).resolve().parent.parent / "scripts"
   sys.path.insert(0, str(SCRIPT_DIR))

   from signoff import (

逐段解释：

* 第 L1-L12 行：docstring 明确该文件是 signoff gate 的单元测试，并列出 7 条规则。
* 第 L14-L21 行：导入标准库、pytest 和 yaml。
* 第 L23-L36 行：把 ``dv/uvm/core_eh2/scripts`` 加到 ``sys.path``，再从 ``signoff`` 导入
  被测函数。

关键代码（``dv/uvm/core_eh2/tests/test_signoff_gates.py:L39-L56``）：

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
       require_coverage = True

逐段解释：

* 第 L39-L56 行：``Args`` 是最小 argparse-like namespace，用 class attribute 模拟
  ``signoff.py`` 需要的参数。默认 line coverage 阈值为 60.0，functional coverage 阈值为
  50.0，``require_coverage`` 为 True。

接口关系：

* 被调用：pytest discovery。
* 调用：``signoff.py`` 中的 evaluate/collect/check/write 函数。
* 共享状态：创建临时目录、mock testlist，读取真实 testlist 时由被测函数决定。

§10  参考资料
--------------------------------------------------------------------------------

* 关联章节：:ref:`tests_library`、:ref:`appendix_b_uvm/tb`、:ref:`appendix_b_uvm/env`、
  :ref:`appendix_b_uvm_vseq`、:ref:`appendix_c_tools/asm_tests`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_report_server.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv`
* 源文件：:file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/test_signoff_gates.py`
