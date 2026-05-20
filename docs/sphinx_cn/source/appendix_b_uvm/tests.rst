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
test 组成。本文先解释 SV/Python 测试基础设施，再在 §5.4 给出所有 ``.S`` directed/cosim
汇编测试的逐文件字典；汇编工具链、链接脚本和 objcopy 细节见
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

§5.4  Directed Tests 字典总览
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

本节覆盖 ``dv/uvm/core_eh2/tests/asm/*.S`` 和顶层 ``tests/asm/*.S`` 的全部 46 个汇编
测试文件。它们不是随机指令流的替代品，而是把难以稳定命中的结构性窗口固定下来：
cosim proof 负责把 Spike lockstep 的基础语义打牢，directed tests 负责 trap/PMP/debug/AXI4
错误注入和覆盖率泵，顶层 smoke/nop 则服务于最短 bring-up 与 sign-off smoke stage。

.. note::

   2026-05-19 VCS full sign-off 中，相关 stage 证据为 ``smoke 1/1``、``directed 40/40``、
   ``cosim 7/7`` 全部 PASS。合并覆盖率来自 URG dut-only dashboard：
   LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、
   GROUP 69.42%、OVERALL 65.17%。当前 HTML/Markdown dashboard 不发布逐测试 coverage
   增量，所以每个条目的「当前实测」只引用 stage 通过状态和全局合并指标。

**测试族与 sign-off stage 对照**：

.. list-table::
   :header-rows: 1
   :widths: 24 28 48

   * - 测试族
     - stage
     - 验证价值
   * - ``cosim_*.S``
     - ``cosim``，部分也被 ``directed`` 复用
     - 建立 ALU、LSU、dual-issue、exception、atomic 与 bitmanip 的 Spike lockstep proof point。
   * - ``directed_pmp_*.S``
     - ``directed``
     - 固定 PMP CSR、region priority、地址模式、I-side/D-side fault 和 mscause 观察窗口。
   * - ``directed_toggle_*.S``
     - ``directed``
     - 为 R3-B 结构覆盖率泵高翻转数据，补 random 稳定性不足的 datapath toggles。
   * - ``directed_*`` 其它测试
     - ``directed``
     - 覆盖 IRQ、debug、AXI4 error、DMA burst、IFU BP/BTB、LSU store buffer 和 NB-load 风险。
   * - 顶层 ``tests/asm/*.S``
     - ``smoke`` 或 bring-up artifact
     - ``smoke.S`` 是 sign-off smoke stage 输入；``nop.S`` 是最小 ELF/HEX 构建与波形定位样例。

§5.4.01  ``cosim_alu.S`` — ALU lockstep proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：用确定性 ``addi/add/sub/and/or/xor/sll/srl/sra/slt/sltu`` 序列证明 EXU ALU
结果、写回寄存器和 Spike ISS 预期一致。

**为什么 random 覆盖不了**：riscv-dv 能生成 ALU 指令，但很难在短回归中保证每个运算符、
正负立即数、移位和比较路径都按固定顺序出现，并带有源码级可读的期望值。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_alu.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_alu.S

**逐段精读**：

* L1-L7：声明测试目标和最终 mailbox PASS 协议。
* L11-L43：构造立即数、寄存器算术、逻辑和移位结果，覆盖 ``eh2_exu_alu_ctl.sv`` 的主 ALU
  选择路径。
* L45-L82：逐项 ``bne`` 自检，失败写 ``0x1``，成功写 ``0xFF`` 到 ``0xD0580000``。

**覆盖到的 RTL/coverage 面**：``exu/eh2_exu_alu_ctl.sv``、``dec/eh2_dec_decode_ctl.sv``、
``common/cosim_agent/eh2_cosim_scoreboard.sv`` 的 retire/writeback 比对。

**这条测试在哪个 sign-off stage 跑**：``cosim``；同时在 ``directed`` 中以
``directed_alu`` 复用。

**预期通过条件**：所有寄存器结果命中期望值，scoreboard 无 PC/写回 mismatch，mailbox 写
``0xFF``。当前实测：VCS full sign-off 中 ``cosim 7/7``、``directed 40/40`` PASS。

§5.4.02  ``cosim_atomic_basic.S`` — LR/SC 与 AMO proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：覆盖 issue 52 引入的 atomic cosim proof，验证 LR/SC reservation、SC 成功返回值和
AMOSWAP/AMOADD/AMOXOR/AMOAND 的内存更新。

**为什么 random 覆盖不了**：atomic 指令既依赖 DCCM 地址、reservation 状态，也依赖 scoreboard
对原子读写的建模；随机流很难稳定形成「无竞争 LR/SC + 多个 AMO 后读回」的短闭环。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_atomic_basic.S

**逐段精读**：

* L1-L13：列出 7 个验证点，说明该文件是 atomic lockstep 的 sign-off proof。
* L17-L35：在 ``0xF0040000`` 上执行 LR/SC 获取锁，检查 ``sc.w`` 返回 0。
* L37-L82：依次执行 AMO swap/add/xor/and 并读回结果，失败统一跳 ``fail``。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_amo.sv``、``lsu/eh2_lsu_dccm_ctl.sv``、
``dv/cosim/spike_cosim.cc`` 的 atomic retire 建模。

**这条测试在哪个 sign-off stage 跑**：``cosim``。

**预期通过条件**：LR/SC 和 AMO 读回值全部匹配，Spike 与 DUT retire 序列一致。当前实测：
VCS full sign-off 中 ``cosim 7/7`` PASS。

§5.4.03  ``cosim_bitmanip.S`` — Zba/Zbb deterministic proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：把 EH2 支持的 Zba/Zbb 指令放入短序列，覆盖 ``sh1add/sh2add/sh3add``、
``andn/orn/xnor/clz/ctz/cpop/max/min`` 等 bitmanip ALU 分支。

**为什么 random 覆盖不了**：bitmanip 指令在普通随机混合中占比低，且 ``clz/ctz/cpop`` 这类
结果对 operand pattern 敏感；固定 operand 能让 cosim mismatch 可复现。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_bitmanip.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_bitmanip.S

**逐段精读**：

* L1-L7：说明本测试只走寄存器路径，不依赖 memory exception。
* L13-L44：准备 ``0xAAAAAAAA``、``0x55555555``、``0x12345678`` 等高辨识度 operand。
* L46-L119：执行 Zba/Zbb 指令并写 mailbox，覆盖 decode 到 EXU bitmanip datapath。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_decode_ctl.sv``、``exu/eh2_exu_alu_ctl.sv`` 和
cosim writeback scoreboard。

**这条测试在哪个 sign-off stage 跑**：``cosim``。

**预期通过条件**：所有 bitmanip retire 的 rd 写回与 Spike 一致，mailbox PASS。当前实测：
VCS full sign-off 中 ``cosim 7/7`` PASS。

§5.4.04  ``cosim_dual_issue.S`` — 双发射顺序 proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：构造可双发射的独立 ALU pair 和随后检查，证明 EH2 双线程/双发射 retire 在
program order 上能被 trace/cosim 正确消费。

**为什么 random 覆盖不了**：随机流会被依赖、结构冲突和分支打散，难以稳定制造连续可双发射
窗口；本测试把 pair 边界写在源码里，便于定位 i0/i1 顺序问题。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_dual_issue.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_dual_issue.S

**逐段精读**：

* L1-L11：给出双发射成立条件：无数据依赖、无结构冲突、slot 类型兼容。
* L17-L52：构造多组独立 ALU pair，覆盖 i0/i1 retire 同周期路径。
* L54-L109：执行结果检查并通过 mailbox 结束。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec.sv``、``dec/eh2_dec_ib_ctl.sv``、
``common/trace_agent/eh2_trace_monitor.sv`` 和 cosim scoreboard 的顺序匹配。

**这条测试在哪个 sign-off stage 跑**：``cosim``。

**预期通过条件**：无论 DUT 单发还是双发，最终寄存器结果与 Spike program order 一致。当前实测：
VCS full sign-off 中 ``cosim 7/7`` PASS。

§5.4.05  ``cosim_exception_compare.S`` — mcause/mepc 比对 proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：覆盖 issue 51 的异常比较路径，故意触发 M-mode ECALL 和非法指令，让 scoreboard
比较 DUT 与 Spike 的 ``mcause`` / ``mepc``。

**为什么 random 覆盖不了**：异常路径需要 mtvec、handler、mepc advance 和 mret 成套出现；
随机非法指令可能出现，但很少带有可预测 handler 和多异常连续检查。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_exception_compare.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_exception_compare.S

**逐段精读**：

* L1-L13：声明 3 个异常点：ECALL、全 0 illegal、全 1 illegal。
* L20-L42：设置 mtvec，触发 ECALL 和非法指令。
* L58-L84：handler 检查 cause、推进 mepc 并 mret 回主流程。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_tlu_ctl.sv``、``dec/eh2_dec_csr.sv``、
``common/cosim_agent/eh2_cosim_scoreboard.sv`` 的异常 CSR 比对。

**这条测试在哪个 sign-off stage 跑**：``cosim``。

**预期通过条件**：每次异常的 cause 与返回 PC 符合预期，DUT/Spike 无异常状态 mismatch。当前实测：
VCS full sign-off 中 ``cosim 7/7`` PASS。

§5.4.06  ``cosim_load_store.S`` — LSU load/store proof
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：用 ``lb/lh/lw/lbu/lhu/sb/sh/sw`` 的短序列证明 LSU byte lane、sign extension、
store mask 和 cosim memory notification 一致。

**为什么 random 覆盖不了**：随机 load/store 能增加覆盖率，但 byte/halfword sign-extension 与
固定地址偏移组合不稳定；本测试给每个宽度指定数据和偏移。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_load_store.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_load_store.S

**逐段精读**：

* L1-L6：说明覆盖 load/store 指令族和小数据区。
* L11-L40：向 ``0x80010000`` 附近写 word/half/byte。
* L42-L83：用 signed/unsigned load 读回并检查扩展结果。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_lsc_ctl.sv``、``lsu/eh2_lsu_bus_buffer.sv``、
AXI4 monitor 和 cosim memory scoreboard。

**这条测试在哪个 sign-off stage 跑**：``cosim``；同时在 ``directed`` 中以
``directed_load_store`` 复用。

**预期通过条件**：每个 load 的返回值与源码中期望一致，store 通知不产生 scoreboard mismatch。
当前实测：VCS full sign-off 中 ``cosim 7/7``、``directed 40/40`` PASS。

§5.4.07  ``cosim_smoke.S`` — cosim 最小闭环
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：只写 mailbox PASS，验证 cosim 初始化、binary load、第一条 retire 和基本
fetch/decode/execute/store 闭环。

**为什么 random 覆盖不了**：random 用来扩展空间，不适合作为最短故障隔离点；当 cosim bootstrap
失败时，需要一个几乎没有业务逻辑的基线程序。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/cosim_smoke.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_smoke.S

**逐段精读**：

* L1-L5：定义该文件只验证最小 cosim loop。
* L10-L13：构造 ``0xD0580000`` mailbox 地址并写 ``0xFF``。
* L16-L17：进入自旋，等待 UVM 侧通过 mailbox 判定完成。

**覆盖到的 RTL/coverage 面**：``ifu/eh2_ifu.sv``、``dec/eh2_dec_decode_ctl.sv``、
``lsu/eh2_lsu.sv`` 和 base test mailbox 观察逻辑。

**这条测试在哪个 sign-off stage 跑**：``cosim``；同时作为 ``directed_smoke`` 在 ``directed``
stage 复用。

**预期通过条件**：mailbox 写 ``0xFF``，无 UVM error/fatal。当前实测：VCS full sign-off 中
``cosim 7/7``、``directed 40/40`` PASS。

§5.4.08  ``directed_axi4_error_inject.S`` — AXI4 错误响应注入
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配合 ``+enable_axi4_error_inject=1 +axi4_error_pct=100``，确认外部 AXI4
SLVERR/DECERR 会转化为 load access fault。

**为什么 random 覆盖不了**：随机程序不会稳定触发外部总线 error response；错误注入还会改变
总线语义，因此必须关闭 cosim 并用 directed trap handler 自检。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_axi4_error_inject.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_axi4_error_inject.S

**逐段精读**：

* L1-L18：说明测试目标、必需 plusargs 和 cosim disabled 原因。
* L23-L50：设置 mtvec 后对外部地址发起 load，等待 AXI4 driver 注入错误。
* L62-L99：trap handler 检查 ``mcause == 5``，正确则写 PASS。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_bus_intf.sv``、``lsu/eh2_lsu_bus_buffer.sv``、
``common/axi4_agent/axi4_driver.sv`` 的错误响应路径。

**这条测试在哪个 sign-off stage 跑**：``directed``，testlist 中显式 ``cosim: disabled``。

**预期通过条件**：core 捕获 load access fault，handler 写 mailbox PASS。当前实测：VCS full
sign-off 中 ``directed 40/40`` PASS。

§5.4.09  ``directed_csr_warl.S`` — EH2 custom CSR WARL
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：写读 ``mscause``、``mrac``、``mfdc`` 等 EH2 custom CSR，观察硬件 WARL 合法化行为。

**为什么 random 覆盖不了**：Spike 对 EH2 custom CSR 建模不完整，随机 CSR 流无法把实现定义的
readback mask 作为稳定判据；该测试以 RTL 行为为准并关闭 cosim。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_csr_warl.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_csr_warl.S

**逐段精读**：

* L1-L7：标注 custom CSR 和 cosim disabled 原因。
* L11-L33：定义 CSR 地址并对 ``mscause`` 写全 1 后读回。
* L35-L71：继续覆盖 ``mrac``、``mfdc``，把观测值留在内存后写 PASS。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和 CSR
coverage 的 custom CSR bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：CSR 访问不产生非预期 trap，mailbox PASS；custom readback 供波形和日志复查。
当前实测：VCS full sign-off 中 ``directed 40/40`` PASS。

§5.4.10  ``directed_dbg_dret_walk.S`` — debug halt/resume 窗口
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配合 UVM debug plusargs 产生 halt/resume 脉冲，同时用 ``ebreak``、trap 和短循环
提供可观测窗口。

**为什么 random 覆盖不了**：debug request 是 testbench 侧异步刺激，随机指令不能保证在 halt
窗口内正好有 breakpoint、trap return 和 resume 交错。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_dbg_dret_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_dbg_dret_walk.S

**逐段精读**：

* L1-L7：说明 companion UVM plusargs 驱动 debug request。
* L12-L28：设置 mtvec、触发 ``ebreak`` 并检查 handler 标志。
* L30-L51：进入 debug spin，给 JTAG/halt-run agent 留出交互周期。

**覆盖到的 RTL/coverage 面**：``dbg/eh2_dbg.sv``、``dec/eh2_dec_tlu_ctl.sv``、
``common/jtag_agent`` 和 ``common/halt_run_agent``。

**这条测试在哪个 sign-off stage 跑**：``directed``，testlist 中 ``cosim: disabled``。

**预期通过条件**：debug request 不破坏 trap return，程序最终写 PASS。当前实测：VCS full
sign-off 中 ``directed 40/40`` PASS。

§5.4.11  ``directed_debug_basic.S`` — EBREAK breakpoint trap
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：验证 M-mode ``ebreak`` 进入 breakpoint exception，handler 推进 ``mepc`` 后返回。

**为什么 random 覆盖不了**：随机 ``ebreak`` 若无配套 handler，通常只表现为不可控退出；本测试把
``mcause == 3`` 和 handler flag 固定为可检查结果。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_debug_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_debug_basic.S

**逐段精读**：

* L1-L9：定义 breakpoint exception 目标和 cosim enabled 状态。
* L13-L30：设置 mtvec、清 flag、执行 ``ebreak``。
* L44-L63：handler 检查 ``mcause``，推进 ``mepc`` 并置位 flag。

**覆盖到的 RTL/coverage 面**：``dbg/eh2_dbg.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和
``dec/eh2_dec_trigger.sv`` 的 debug/trap 交界。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：``mcause == 3``，返回后 flag 正确，mailbox PASS。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.12  ``directed_dma_burst.S`` — DMA/AXI burst 压力
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：在 UVM 可选 DMA/debug command 刺激之外，制造连续 aligned store/load burst，
让 LSU、AXI memory FSM 和 DCCM/外部 memory 看到持续流量。

**为什么 random 覆盖不了**：随机访存很难形成 32 word 连续 burst，且地址对齐和 readback 顺序
不可控；该文件把 burst pattern 固定下来。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_dma_burst.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_dma_burst.S

**逐段精读**：

* L1-L7：说明 DMA-like memory burst 的覆盖意图。
* L12-L24：连续写 32 个 word，数据每次加 3。
* L26-L54：fence 后读回检查，最后写 mailbox。

**覆盖到的 RTL/coverage 面**：``eh2_dma_ctrl.sv``、``lsu/eh2_lsu_bus_buffer.sv``、
``lib/axi4_to_ahb.sv`` 和 AXI4 agent monitor。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：burst 数据读回一致，memory path 无 UVM error。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.13  ``directed_double_issue_hazard.S`` — 双发射 hazard 顺序
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：构造 same-cycle RAW、WAR、WAW hazard，验证双发射流水线 writeback 仍保持程序顺序。

**为什么 random 覆盖不了**：随机流可能产生依赖，但不保证依赖正好跨 i0/i1 slot；本测试把 hazard
pair 按源码相邻顺序固定，便于 trace_pkt 对齐。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_double_issue_hazard.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_double_issue_hazard.S

**逐段精读**：

* L1-L7：声明 RAW/WAR/WAW 和 trace order 检查目标。
* L11-L45：构造 RAW 与 WAR hazard pair。
* L47-L85：构造 WAW 和最终结果检查，失败写 fail mailbox。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_ib_ctl.sv``、``dec/eh2_dec_gpr_ctl.sv``、
``exu/eh2_exu.sv`` 和 trace monitor。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：所有 hazard pair 的最终寄存器值符合程序顺序。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.14  ``directed_iccm_eccerror.S`` — ICCM fetch/ECC 注入窗口
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配合 ``+enable_mem_error=1``，让 IFU/ICCM 在 aligned fetch loop 中持续活动，
为 ECC/error injection 提供稳定窗口。

**为什么 random 覆盖不了**：随机程序不保证在注入窗口内反复访问同一类 ICCM/fetch 路径；固定
``fence.i`` 和小函数调用能让波形定位更直接。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_iccm_eccerror.S

**逐段精读**：

* L1-L6：说明该文件是 fetch/ECC error stimulus shell。
* L11-L24：设置 handler、执行 ``fence.i``，循环调用 ``iccm_probe``。
* L26-L55：通过 magic check 和 trap handler 结束，保证测试有界。

**覆盖到的 RTL/coverage 面**：``ifu/eh2_ifu_iccm_mem.sv``、``ifu/eh2_ifu_ifc_ctl.sv``、
``ifu/eh2_ifu_aln_ctl.sv`` 和 memory error 注入逻辑。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：fetch loop 和注入窗口不导致非预期 timeout，最终 mailbox PASS。当前实测：
VCS full sign-off 中 ``directed 40/40`` PASS。

§5.4.15  ``directed_ifu_bp_btb.S`` — IFU BP/BTB walk
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：用重复 taken/not-taken 分支、join path 和 call/return 目标训练 IFU branch predictor
和 BTB。

**为什么 random 覆盖不了**：随机分支的历史模式不可控，短回归中很难稳定命中同一个 BTB set 和
taken/not-taken 翻转；本测试显式构造训练循环。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_ifu_bp_btb.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_ifu_bp_btb.S

**逐段精读**：

* L1-L5：声明 BP/BTB walk 目标。
* L9-L27：96 次分支训练，按 ``s0 & 3`` 产生 taken/not-taken 交替。
* L29-L54：补充 call target 与最终 mailbox，形成 fetch toggle coverage。

**覆盖到的 RTL/coverage 面**：``ifu/eh2_ifu_bp_ctl.sv``、``ifu/eh2_ifu_btb_mem.sv`` 和
``ifu/eh2_ifu_ifc_ctl.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``，使用 ``core_eh2_fetch_toggle_test``。

**预期通过条件**：分支训练循环有界退出，fetch toggle 侧带不报错。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.16  ``directed_illegal_instr.S`` — illegal instruction trap
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：执行 ``.word 0x00000000``，验证 illegal instruction exception 的 ``mcause == 2``
和 ``mepc`` advance。

**为什么 random 覆盖不了**：随机非法编码常常会破坏后续流控制；本测试把非法编码、handler 和
return PC 固定为最小可诊断闭环。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_illegal_instr.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_illegal_instr.S

**逐段精读**：

* L1-L7：说明非法全 0 编码和 cosim enabled。
* L11-L25：设置 mtvec、清 flag、执行非法 instruction。
* L39-L58：handler 检查 cause、推进 mepc、置 flag 并返回。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_decode_ctl.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和
cosim exception 比对。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：``mcause == 2``，返回后 flag 正确，mailbox PASS。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.17  ``directed_irq_basic.S`` — 基础 trap/return
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：用 M-mode ECALL 走最小同步 trap/return 路径，作为 IRQ/PIC 复杂场景之前的基线。

**为什么 random 覆盖不了**：随机 ECALL 需要和 handler、mepc advance、flag 检查配套才有诊断
价值；该文件把同步 trap 闭环最小化。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_irq_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_irq_basic.S

**逐段精读**：

* L1-L8：说明该测试不依赖外部 interrupt controller。
* L12-L26：设置 mtvec、清 flag、执行 ECALL。
* L40-L61：handler 检查 ``mcause == 11`` 并 mret。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_tlu_ctl.sv``、``dec/eh2_dec_csr.sv``、
``common/irq_agent`` 的基础状态观察。

**这条测试在哪个 sign-off stage 跑**：``directed``；也被 PIC directed config 作为基础样例引用。

**预期通过条件**：ECALL 后返回主流程，flag 正确，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.18  ``directed_lsu_stbuf_full.S`` — LSU store buffer 压力
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：连续发出 4 个 word store 为一组的 store pressure loop，观察 store buffer、
fence 和 DCCM/外部写路径。

**为什么 random 覆盖不了**：随机 store 通常被 load/branch 打断，不稳定填满或接近填满 store
buffer；该测试让 store burst 以固定步长推进。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_lsu_stbuf_full.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_lsu_stbuf_full.S

**逐段精读**：

* L1-L5：声明 store-buffer pressure 目标。
* L8-L22：从 ``0xF0040000`` 开始连续写 64 个 word 等效流量。
* L24-L48：fence 后写 mailbox，确保 store drain 完成。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_stbuf.sv``、``lsu/eh2_lsu_lsc_ctl.sv`` 和
``lsu/eh2_lsu_dccm_ctl.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：store pressure 不导致 hang，fence 后 mailbox PASS。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.19  ``directed_nb_load_chain.S`` — NB-load 写回风险回归
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：覆盖 RISK-5：连续 non-blocking loads 后立刻使用结果分支，防止 cross-slot
writeback 问题回归。

**为什么 random 覆盖不了**：随机 load-use 序列不保证形成三连 load 加 dependent branch 的紧凑窗口；
该测试把 hazard 距离固定到最短可读形式。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S

**逐段精读**：

* L1-L6：说明该文件是 NB-load wb cross-slot 回归。
* L11-L23：初始化 3 个连续 memory word 并 fence。
* L25-L45：连续 load 后立即比较结果，任一错误跳 fail。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_lsc_ctl.sv``、``lsu/eh2_lsu_bus_buffer.sv``、
``dec/eh2_dec_gpr_ctl.sv`` 的 load writeback 交界。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：三次 load 的结果全部正确，dependent branch 不误判。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.20  ``directed_nested_irq.S`` — nested ECALL trap
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：构造两层 ECALL trap，验证 handler 中保存/恢复 ``mepc`` 和栈状态后能正确回到两级
调用点。

**为什么 random 覆盖不了**：嵌套 trap 需要 handler 内再次触发 ECALL，随机流几乎不会稳定生成
这种可返回结构；手写汇编能直接检查 x30/x31 标志。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_nested_irq.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nested_irq.S

**逐段精读**：

* L1-L9：说明二级 ECALL 和最终 ``x30/x31`` 检查。
* L13-L33：设置 stack、mtvec 和 flag，触发第一层 ECALL。
* L72-L111：handler 区分 level，保存 mepc 并在一级 handler 中触发第二层 ECALL。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_tlu_ctl.sv``、CSR mepc/mcause path 和 IRQ/trap
scoreboard 观察。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：``x30 == 0xBEEF`` 且 ``x31 == 0xCAFE``，mailbox PASS。当前实测：VCS full
sign-off 中 ``directed 40/40`` PASS。

§5.4.21  ``directed_pic_state_walk.S`` — PIC/trap 状态 walk
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：在 UVM ``+enable_irq_seq`` 驱动外部 IRQ 的同时，用 ECALL 保证至少一个 trap
entry/complete 周期，使 PIC/claim/complete 相关状态有可观测窗口。

**为什么 random 覆盖不了**：外部 IRQ pulse 与指令流的相位关系随机，短测试可能错过关键窗口；
该文件用本地 trap 保证 TLU/PIC 侧活动。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pic_state_walk.S

**逐段精读**：

* L1-L7：说明外部 IRQ 由 UVM sequence 驱动。
* L11-L23：打开 ``mstatus.MIE`` 和 ``mie.MEIE`` 后触发 ECALL。
* L25-L63：handler 标记 trap 完成，给 PIC state walk 留出时间。

**覆盖到的 RTL/coverage 面**：``eh2_pic_ctrl.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和
``common/irq_agent/eh2_irq_driver.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``，使用 ``eh2_directed_pic`` config。

**预期通过条件**：trap 与 IRQ sideband 不导致死锁，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.22  ``directed_pmp_addr_alignment.S`` — PMP 地址对齐
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：写入不同低位形态的 ``pmpaddr``，验证 PMP 地址 LSB、NAPOT granularity 和 WARL
合法化不会破坏后续访问。

**为什么 random 覆盖不了**：PMP 地址编码对低位非常敏感，随机 CSR 写入可能直接 trap 或不可诊断；
该测试把每个地址形态和 cfg 写入顺序固定。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_addr_alignment.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_addr_alignment.S

**逐段精读**：

* L1-L4：声明地址 LSB alignment 和 granularity 目标。
* L8-L27：写 NAPOT 4KB、no-rwx cfg 和第二个 word-boundary 地址。
* L29-L55：执行观察性访问并通过 trap/mailbox 判定。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和
``fcov/eh2_pmp_fcov_if.sv`` 的 PMP 地址 bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：PMP CSR 写入与访问序列有界结束，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.23  ``directed_pmp_after_trap.S`` — PMP fault 后 CSR 内容
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：触发 PMP access violation 后检查 ``mtval`` / ``mcause`` 是否记录失败地址与原因。

**为什么 random 覆盖不了**：随机 PMP fault 不保证 handler 知道期望 failing address；本测试把
地址放入 ``mscratch``，handler 可直接比较。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_after_trap.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_after_trap.S

**逐段精读**：

* L1-L4：说明目标是 fault 后 ``mtval/mcause``。
* L8-L25：配置锁定 no-rwx region，并把期望 fault address 放入 ``mscratch``。
* L27-L64：触发访问，handler 检查 cause/address 后 PASS。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_tlu_ctl.sv``、``lsu/eh2_lsu_addrcheck.sv`` 和 PMP
fault covergroup。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：trap cause 和 fault address 与预期一致。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.24  ``directed_pmp_cross_region.S`` — 跨 region 访问
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：验证 load/store 跨两个 PMP region 边界时按低 index/匹配规则产生正确 fault。

**为什么 random 覆盖不了**：跨边界访问需要地址、宽度和 region 边界严格对齐；随机生成器很难
稳定把 access 放在 4B region 边界。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_cross_region.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_cross_region.S

**逐段精读**：

* L1-L4：声明跨 region boundary 目标。
* L8-L25：配置 region0 no-access 与 region1 full-access。
* L27-L57：执行边界访问并由 handler 判断是否按预期 fault。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``dec/eh2_dec_tlu_ctl.sv``、
``fcov/eh2_pmp_fcov_if.sv`` 的 priority/cross-region bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：跨边界访问触发预期 fault 或按配置完成，最终 mailbox PASS。当前实测：VCS full
sign-off 中 ``directed 40/40`` PASS。

§5.4.25  ``directed_pmp_csr_warl.S`` — PMP CSR WARL
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：对 ``pmpaddr0`` 和 ``pmpcfg0`` 写非法或边界值，验证 WARL 合法化后系统仍可继续。

**为什么 random 覆盖不了**：非法 PMP CSR 写入会受到实现定义行为约束；随机写法缺少读回记录和
后续恢复步骤，难以形成稳定 gate。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_csr_warl.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_csr_warl.S

**逐段精读**：

* L1-L4：说明目标是 pmpcfg/pmpaddr WARL。
* L8-L24：写 ``0xFFFFFFFF`` 到 ``pmpaddr0`` 并读回记录。
* L26-L56：写 pmpcfg 边界值，确保 CSR 路径不崩溃并 PASS。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``fcov/eh2_pmp_fcov_if.sv`` 的 CSR
WARL 相关 bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：非法/边界 CSR 写不会造成非预期 hang，mailbox PASS。当前实测：VCS full
sign-off 中 ``directed 40/40`` PASS。

§5.4.26  ``directed_pmp_dside_load.S`` — D-side load enforcement
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置 mailbox 附近 no-read PMP region，验证 data-side load 会触发 PMP fault。

**为什么 random 覆盖不了**：随机 load 很难刚好打到受保护地址且配有 trap handler；本测试固定
``0xD0580000`` region 和检查路径。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_dside_load.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_dside_load.S

**逐段精读**：

* L1-L4：声明 data-side load enforcement。
* L8-L25：配置保护 region 并读回 pmpcfg。
* L27-L54：执行 load fault 观察并通过 handler/mailbox 判定。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``lsu/eh2_lsu_lsc_ctl.sv`` 和 PMP
D-side load coverpoints。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：受保护 load 触发预期 fault，handler PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.27  ``directed_pmp_dside_store.S`` — D-side store enforcement
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置 read-only/TOR region，验证 data-side store 被 PMP 拒绝。

**为什么 random 覆盖不了**：store fault 依赖 PMP cfg、TOR bound 和地址共同成立；随机程序很难
稳定命中写禁止窗口并继续运行到 PASS。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_dside_store.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_dside_store.S

**逐段精读**：

* L1-L4：声明 data-side store enforcement。
* L8-L27：配置 TOR + R-only region 和 upper bound。
* L29-L56：发起 store，handler 判断 store access fault 后 PASS。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``lsu/eh2_lsu_stbuf.sv`` 和 PMP
D-side store bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：受保护 store 不落入内存，trap cause 正确。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.28  ``directed_pmp_iside.S`` — I-side fetch enforcement
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置 execute-deny window，验证 instruction-side fetch fault 后测试有界退出。

**为什么 random 覆盖不了**：随机跳转不保证落入 execute-deny region，且容易形成无限 trap；
本测试使用 ``.option norvc`` 和固定 handler 保证 PC advance 可控。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_iside.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_iside.S

**逐段精读**：

* L1-L5：说明该测试专注 instruction-side trap 且必须有界。
* L10-L27：配置 TOR execute-deny window 并 ``fence.i``。
* L29-L54：跳转/handler 观察 fetch fault，最后写 PASS。

**覆盖到的 RTL/coverage 面**：``ifu/eh2_ifu_ifc_ctl.sv``、``lsu/eh2_lsu_addrcheck.sv``、
``dec/eh2_dec_tlu_ctl.sv`` 和 PMP I-side coverpoints。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：fetch fault 被 handler 接住且不无限循环。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.29  ``directed_pmp_lock.S`` — PMP L-bit 锁定
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置 PMP L-bit 后尝试改写 cfg，验证锁定位直到 reset 前阻止重配置或合法化改写。

**为什么 random 覆盖不了**：PMP lock 是跨 CSR 写的状态性行为，随机单次 CSR 访问无法证明「先锁定、
再改写失败/被合法化」的顺序。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_lock.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_lock.S

**逐段精读**：

* L1-L4：声明 L-bit lock 目标。
* L8-L24：配置 NAPOT region 和 ``pmpcfg0`` byte0 ``0x9F``。
* L26-L60：尝试覆盖 locked cfg，读回并继续 PASS。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``fcov/eh2_pmp_fcov_if.sv`` 的 lock
bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：锁定后改写不会破坏 PMP 状态，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.30  ``directed_pmp_mscause_decode.S`` — EH2 mscause 二级原因
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：在 PMP fault 后读取 EH2 custom ``mscause``，验证 secondary cause decode 可观察。

**为什么 random 覆盖不了**：``mscause`` 是 EH2 custom CSR，Spike 语义有限；必须用固定 PMP fault
和 handler 才能稳定检查 RTL secondary cause。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_mscause_decode.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_mscause_decode.S

**逐段精读**：

* L1-L7：声明 custom ``CSR_MSCAUSE`` 地址和 no-compressed 约束。
* L11-L25：配置 PMP no-rwx data region。
* L27-L63：触发 fault，handler 读取 ``mscause`` 并判定结束。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和 PMP
secondary cause coverage。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：PMP fault 后 ``mscause`` 可读且测试 PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.31  ``directed_pmp_na4_basic.S`` — NA4 mode
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：验证 naturally-aligned 4-byte PMP region 的基本配置和访问 fault 行为。

**为什么 random 覆盖不了**：NA4 需要精确 4B 对齐地址和 cfg A field；随机 CSR 写很难稳定覆盖
这一模式并完成 handler 检查。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_na4_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_na4_basic.S

**逐段精读**：

* L1-L4：声明 NA4 4-byte region 目标。
* L8-L25：写 ``pmpaddr0`` 和 ``pmpcfg0`` 的 NA4/no-rwx/lock 配置。
* L27-L56：配置第二个 NA4 地址并执行访问观察。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``lsu/eh2_lsu_addrcheck.sv``、
``fcov/eh2_pmp_fcov_if.sv`` 的 NA4 bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：NA4 配置后访问行为符合 handler 预期。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.32  ``directed_pmp_napot_basic.S`` — NAPOT size sweep
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：覆盖 NAPOT 4B、16B、256B、4KB 等 size encoding，验证地址低位编码和权限组合。

**为什么 random 覆盖不了**：NAPOT size 由 pmpaddr 低位连续 1 的形态决定，随机值覆盖到正确 size
并形成有界访问检查的概率低。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_napot_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_napot_basic.S

**逐段精读**：

* L1-L4：声明 NAPOT 多尺寸 sweep。
* L8-L29：配置 4KB 和 16B NAPOT 地址。
* L31-L64：继续配置更小/更大窗口并完成访问检查。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``dec/eh2_dec_csr.sv``、
``fcov/eh2_pmp_fcov_if.sv`` 的 NAPOT size bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：所有 NAPOT 配置序列有界完成，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.33  ``directed_pmp_no_match_default.S`` — no-match default
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置远离测试地址的 PMP region，观察无匹配时的默认行为和 handler 路径。

**为什么 random 覆盖不了**：no-match 场景要求所有 region 都避开目标地址；随机 PMP 配置很容易
意外覆盖或完全无效，难以作为 gate。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_no_match_default.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_no_match_default.S

**逐段精读**：

* L1-L4：声明 no-match default deny 目标。
* L8-L26：配置远端 TOR/no-rwx region，并让 byte1 OFF。
* L28-L52：执行不匹配地址访问和 handler 判定。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``fcov/eh2_pmp_fcov_if.sv`` 的
no-match bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：无匹配访问按实现定义路径有界结束，mailbox PASS。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.34  ``directed_pmp_off_basic.S`` — OFF mode
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：先配置一个 NAPOT no-access region，再把 ``pmpcfg0`` 置 OFF，验证 region disabled
后访问不再被该 entry 拦截。

**为什么 random 覆盖不了**：OFF mode 是「先开启再关闭」的状态序列；随机 CSR 写缺少前后访问对照。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_off_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_off_basic.S

**逐段精读**：

* L1-L4：声明 region disabled/invalidated 目标。
* L8-L24：设置 NAPOT no-access region。
* L26-L55：写 ``pmpcfg0 = 0`` 关闭 entry 后执行访问观察。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``lsu/eh2_lsu_addrcheck.sv`` 和 PMP OFF
mode coverpoints。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：OFF 后访问路径不被旧 entry 误拦截，mailbox PASS。当前实测：VCS full sign-off
中 ``directed 40/40`` PASS。

§5.4.35  ``directed_pmp_priority.S`` — low-index priority
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置重叠 PMP region，验证低 index region 优先级高于后续宽 region。

**为什么 random 覆盖不了**：priority 需要重叠 base/size 和冲突权限，随机配置命中概率低，且失败
时难以判断是 priority 还是地址编码错误。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_priority.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_priority.S

**逐段精读**：

* L1-L4：声明 lowest-index wins。
* L8-L27：配置 region0 no-access 和 region1 full-access 的重叠窗口。
* L29-L58：访问重叠地址，handler 判断 region0 是否获胜。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``fcov/eh2_pmp_fcov_if.sv`` 的
priority bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：重叠地址按低 index 权限处理。当前实测：VCS full sign-off 中 ``directed 40/40``
PASS。

§5.4.36  ``directed_pmp_regions.S`` — 多 region resilient test
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：尝试配置 4 个 PMP region，并在 PMP 不可用或写入不粘住时安全跳过访问测试，避免把
实现差异误判为基础平台失败。

**为什么 random 覆盖不了**：多 region 权限矩阵需要 setup、probe 和访问阶段分离；随机流不能处理
「PMP CSR 写本身可能 trap」这种弹性路径。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S

**逐段精读**：

* L1-L22：说明 setup/probe/access 三阶段和 4 个规划 region。
* L24-L49：容忍 trap 的 PMP setup。
* L61-L112：根据 readback 判断是否执行 5 个访问控制检查。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``lsu/eh2_lsu_addrcheck.sv``、
``fcov/eh2_pmp_fcov_if.sv`` 的多 region bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：PMP 可用时访问矩阵符合预期；不可用或不粘住时按源码逻辑安全 PASS。当前实测：
VCS full sign-off 中 ``directed 40/40`` PASS。

§5.4.37  ``directed_pmp_smoke.S`` — PMP 最小 fault
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置一个 4KB NAPOT no-access region 并触发访问 fault，作为 PMP directed 族的最小
smoke。

**为什么 random 覆盖不了**：随机 PMP 场景缺少最小诊断闭环；当 PMP 族失败时，需要先用 smoke
确认 CSR 写、fault 和 handler 的基本连接。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_smoke.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_smoke.S

**逐段精读**：

* L1-L7：声明 PMP region config 和 access fault 目标。
* L12-L33：设置 trap handler 和 NAPOT 4KB region。
* L35-L78：执行违规访问，handler 捕获后写 PASS。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和 PMP
smoke coverpoints。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：访问 fault 被 handler 捕获，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.38  ``directed_pmp_tor_basic.S`` — TOR mode
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：配置 TOR base/end，验证 basic access 和 out-of-bounds fault。

**为什么 random 覆盖不了**：TOR region 由相邻 ``pmpaddr`` 共同定义，随机 CSR 写需要两项组合正确
才有意义；本测试固定 base/end 和 cfg。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_tor_basic.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_tor_basic.S

**逐段精读**：

* L1-L4：声明 TOR basic access + out-of-bounds。
* L8-L27：设置 ``pmpaddr0`` base、``pmpaddr1`` end 和 TOR no-read cfg。
* L29-L55：执行访问并由 handler 判定。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``fcov/eh2_pmp_fcov_if.sv`` 的
TOR bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：TOR 边界访问符合 cfg 预期，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.39  ``directed_pmp_xwr_combinations.S`` — R/W/X 组合
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：覆盖 PMP R/W/X permission bits 的 8 种组合，至少用源码顺序固定代表性组合。

**为什么 random 覆盖不了**：权限组合需要 cfg bit、访问类型和 trap handler 对齐；随机 CSR 写难以
保证 8 组合都在短回归中被碰到。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_pmp_xwr_combinations.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_pmp_xwr_combinations.S

**逐段精读**：

* L1-L4：声明 R/W/X 8 permission combinations。
* L8-L24：先配置 X-only，再重配 full RWX。
* L26-L57：执行访问观察和 PASS/FAIL mailbox。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_addrcheck.sv``、``ifu/eh2_ifu_ifc_ctl.sv``、
``fcov/eh2_pmp_fcov_if.sv`` 的 permission bins。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：权限组合转换后访问结果有界且符合 handler 判定。当前实测：VCS full sign-off 中
``directed 40/40`` PASS。

§5.4.40  ``directed_toggle_axi4_data_walk.S`` — AXI4 data toggle pump
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：用高翻转数据 pattern 反复写读外部 memory，提升 AXI4 data bus、WSTRB 和 LSU bus
buffer 的 toggle 覆盖。

**为什么 random 覆盖不了**：随机数据未必覆盖 ``0xAAAAAAAA/0x55555555/0xFF00FF00`` 这类高翻转
pattern，也不保证连续落在 AXI4 path 上。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_toggle_axi4_data_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_axi4_data_walk.S

**逐段精读**：

* L1-L5：声明 R3-B AXI4 data bus toggle pump。
* L8-L27：写入多组高翻转 word pattern。
* L29-L116：读回比较并写 mailbox，确保 toggle pump 不只是 blind traffic。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_bus_intf.sv``、``lsu/eh2_lsu_bus_buffer.sv``、
``common/axi4_agent/axi4_monitor.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：所有 pattern 读回一致，AXI4 monitor 无协议错误。当前实测：VCS full sign-off 中
``directed 40/40`` PASS；全局 TOGGLE 为 53.52%。

§5.4.41  ``directed_toggle_csr_walk.S`` — CSR toggle pump
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：对 ``mstatus``、custom CSR 和 counters 写入交替 pattern，提升 CSR flops 和 decode
路径的 toggle 覆盖。

**为什么 random 覆盖不了**：随机 CSR 访问受合法性、privilege 和 WARL 限制，无法稳定给同一 CSR
施加 ``0xAAAAAAAA/0x55555555`` 类 pattern。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_toggle_csr_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_csr_walk.S

**逐段精读**：

* L1-L13：声明 CSR toggle pump 并定义 custom CSR/counter 地址。
* L16-L31：对 ``mstatus`` 写交替 pattern 并保存 shadow。
* L33-L160：继续 walk custom CSR/counter，最终写 PASS。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_csr.sv``、``dec/eh2_dec_tlu_ctl.sv`` 和 CSR functional
coverage。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：CSR 写读不会造成非预期 trap，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS；全局 GROUP 为 69.42%。

§5.4.42  ``directed_toggle_dccm_walk.S`` — DCCM byte/half/word toggle
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：在 DCCM 地址上执行 byte、halfword、word 的高翻转写读，提升 DCCM data/ECC/byte lane
结构覆盖。

**为什么 random 覆盖不了**：随机访存不保证集中打到 DCCM，也不保证每种 width 的 sign/zero
extension 和 byte lane 都被固定检查。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_dccm_walk.S

**逐段精读**：

* L1-L5：声明 DCCM byte/halfword/word toggle pump。
* L8-L26：执行 byte 写读并检查 ``lbu/lb`` 结果。
* L28-L109：继续 halfword/word pattern，覆盖更多 byte lane。

**覆盖到的 RTL/coverage 面**：``lsu/eh2_lsu_dccm_ctl.sv``、``lsu/eh2_lsu_dccm_mem.sv``、
``lsu/eh2_lsu_ecc.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：所有 DCCM width 读回一致，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS；全局 TOGGLE 为 53.52%。

§5.4.43  ``directed_toggle_mul_div_walk.S`` — M-extension toggle pump
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：对 multiply/divide datapath 施加正数、负数和高活动 operand，提升 EXU M-extension
toggle 覆盖。

**为什么 random 覆盖不了**：随机 M 指令占比有限，且 divide corner case 需要明确期望值；本测试
逐条检查 ``mul/div/rem`` 等结果。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_toggle_mul_div_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_mul_div_walk.S

**逐段精读**：

* L1-L7：声明 EXU multiply/divide toggle pump。
* L11-L28：检查 ``mul`` 和 ``div`` 的基本结果。
* L30-L123：继续覆盖 signed/unsigned、remainder 和高翻转 operand。

**覆盖到的 RTL/coverage 面**：``exu/eh2_exu_mul_ctl.sv``、``exu/eh2_exu_div_ctl.sv``、
``exu/eh2_exu_alu_ctl.sv``。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：所有 M-extension 结果匹配源码期望，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS；全局 TOGGLE 为 53.52%。

§5.4.44  ``directed_toggle_rf_walk.S`` — register file toggle pump
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：把多个整数寄存器依次写入高翻转 pattern，提升 GPR write port、read port 和 bypass
路径 toggle。

**为什么 random 覆盖不了**：随机寄存器分配可能偏置到热寄存器，无法保证 x1 到多个寄存器都经历
相同高翻转 pattern。

**完整源码**：

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/directed_toggle_rf_walk.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_toggle_rf_walk.S

**逐段精读**：

* L1-L5：声明 register file toggle pump。
* L8-L30：对 x1 起的一批寄存器写 ``0xAAAAAAAA/0x55555555/0xDEADBEEF``。
* L32-L121：继续覆盖更多 GPR 并通过 mailbox 结束。

**覆盖到的 RTL/coverage 面**：``dec/eh2_dec_gpr_ctl.sv``、``dec/eh2_dec_decode_ctl.sv`` 和
trace writeback monitor。

**这条测试在哪个 sign-off stage 跑**：``directed``。

**预期通过条件**：寄存器写入序列不触发异常，mailbox PASS。当前实测：VCS full sign-off 中
``directed 40/40`` PASS；全局 TOGGLE 为 53.52%。

§5.4.45  ``nop.S`` — 顶层最小 NOP artifact
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：提供顶层 ``tests/asm`` 目录中最小 NOP 程序，验证 standalone asm Makefile 能构建
ELF/HEX/DIS，并保留 mailbox PASS 作为可运行样例。

**为什么 random 覆盖不了**：这是 bring-up artifact，不是随机覆盖测试；它用于排除 toolchain、
linker 和 smoke loader 的基础问题。

**完整源码**：

.. literalinclude:: ../../../../tests/asm/nop.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/tests/asm/nop.S

**逐段精读**：

* L1-L4：说明最小 NOP 和 boot address。
* L7-L11：连续执行 4 个 ``nop``，让波形中 reset 后的 fetch/decode 极易识别。
* L13-L17：写 byte PASS 到 mailbox 后自旋。

**覆盖到的 RTL/coverage 面**：顶层 asm 构建、IFU 最小取指、base test mailbox 观测。

**这条测试在哪个 sign-off stage 跑**：不作为 9-stage sign-off 的独立 gate；它由
``tests/asm/Makefile`` 构建，供 bring-up 和波形调试使用。

**预期通过条件**：``make asm`` 生成 ``nop.hex``，手动 run 时 mailbox 写 ``0xFF``。当前实测：
VCS full sign-off 的 smoke gate 使用同目录 ``smoke.S``，整体 ``smoke 1/1`` PASS。

§5.4.46  ``smoke.S`` — sign-off smoke 输入
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

**作者意图**：作为 ``make smoke`` 和 sign-off smoke stage 的直接二进制输入，只做 mailbox PASS，
用于最快确认编译产物、loader、DUT reset 和 UVM completion 连接。

**为什么 random 覆盖不了**：smoke gate 的目标是隔离基础环境，不是扩展覆盖；随机测试失败时诊断面
太大，不能替代这个最短程序。

**完整源码**：

.. literalinclude:: ../../../../tests/asm/smoke.S
   :language: text
   :linenos:
   :caption: /home/host/eh2-veri/tests/asm/smoke.S

**逐段精读**：

* L1-L5：声明 boot address 和 mailbox address。
* L8-L13：用 ``lui`` 构造 ``0xD0580000``，写 ``0xFF`` PASS byte。
* L15：自旋，等待 UVM 侧 completion。

**覆盖到的 RTL/coverage 面**：``ifu/eh2_ifu.sv`` 最小取指、``lsu/eh2_lsu.sv`` store path、
``core_eh2_base_test.wait_for_completion``。

**这条测试在哪个 sign-off stage 跑**：``smoke``，由 ``signoff.py`` 传入
``--binary /home/host/eh2-veri/tests/asm/smoke.hex``。

**预期通过条件**：mailbox 写 ``0xFF``，run_regress 报告 1/1 PASS。当前实测：VCS full sign-off
中 ``smoke 1/1`` PASS。

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

§11  v2-16 Directed Test 辅助宏与生成器逐段补齐
--------------------------------------------------------------------------------

本节补齐 directed test 辅助文件的源码解释。这些文件不直接作为单个 assembly
test 出现在 sign-off 统计里，但它们决定了 PMP/ePMP directed 测试如何写 CSR、
如何切换 privilege、如何生成 testlist。遗漏它们会导致读者只能看懂 ``.S`` 测试，
却看不懂测试背后的宏语言。

§11.1  ``eh2_macros.h`` — mailbox signature 与 ePMP CSR 常量
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/directed_tests/eh2_macros.h
   :language: c
   :lines: 1-38
   :linenos:
   :caption: dv/uvm/core_eh2/directed_tests/eh2_macros.h:L1-L38

逐行讲解：

* L5-L11：``SIGNATURE_ADDR`` 与 signature type 把汇编测试和 TB mailbox 约定绑定起来。
  directed assembly 通过写固定地址向 ``core_eh2_tb_top`` 报告 core status、test result、
  GPR 或 CSR 内容。
* L13-L27：core status 编码覆盖 machine/user/debug/IRQ/exception 等状态。debug 和 IRQ
  directed tests 用这些值给 trace/debug monitor 留下可诊断锚点。
* L29-L31：``TEST_PASS`` / ``TEST_FAIL`` 是 mailbox PASS/FAIL 最小协议。
* L34-L38：``CSR_MSECCFG`` 和 ``MSECCFG_*`` 是 ePMP 测试必须写的 CSR 位定义；
  不在每个 ``.S`` 文件里重复定义，避免 PMP directed tests 之间常量漂移。

§11.2  ``custom_macros.h`` — PMP/ePMP sequence 宏
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/directed_tests/custom_macros.h
   :language: c
   :lines: 1-162
   :linenos:
   :caption: dv/uvm/core_eh2/directed_tests/custom_macros.h:L1-L162

逐段精读：

* L9-L31：``RESET_PMP`` 清空 16 个 ``pmpcfg/pmpaddr`` 和 ``CSR_MSECCFG``。
  每个 PMP directed test 先 reset，是为了避免前一个 region 的 lock/config 状态污染当前场景。
* L34-L41：``SET_NAPOT_ADDR`` 把 label 地址转换成 NAPOT CSR 编码，包含右移 2 位、
  granularity mask 和 OR mask。随机 CSR 写很难稳定生成这个编码。
* L44-L70：``SET_PMP_CFG`` 根据 region 编号选择 ``pmpcfg0`` 到 ``pmpcfg3``，再把
  8-bit cfg 左移到对应 byte lane。EH2 支持 16 region，因此需要四个 pmpcfg CSR。
* L73-L88：``SET_PMP_NAPOT`` 与 ``SET_PMP_TOR`` 组合地址和配置写入，覆盖最常用的
  NAPOT/TOR region 初始化。
* L99-L108：``SKIP_PC`` 根据指令低两位判断 compressed/non-compressed 指令长度，
  避免 trap handler 返回到同一条 faulting instruction。
* L111-L142：``RW_ACCESSES`` 根据是否定义 ``U_MODE`` 选择 M-mode 或 U-mode 访问路径，
  让同一测试模板覆盖 privilege 差异。
* L145-L162：``SET_MSECCFG`` 和 ``SWITCH_TO_U_MODE_*`` 封装 ePMP security config 与
  ``mret`` privilege switch。出问题时应先 grep 这些宏展开，而不是只看调用点。

§11.3  ``gen_testlist.py`` — 外部 directed suite testlist 生成器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/directed_tests/gen_testlist.py
   :language: python
   :lines: 1-180
   :linenos:
   :caption: dv/uvm/core_eh2/directed_tests/gen_testlist.py:L1-L180

逐段精读：

* L1-L9：脚本说明来源和用途：生成 riscv-tests、riscv-arch-tests 与 ePMP directed
  tests 的 testlist，并明确从 Ibex 版本改造到 EH2。
* L18-L57：``add_configs_and_handwritten_directed_tests`` 先生成三个 config：
  ``riscv-tests``、``riscv-arch-tests`` 和 ``epmp-tests``。三者都指向
  ``core_eh2_base_test``，并打开 ``PMPEnable``。
* L62-L180：``available_directed_tests`` 是 YAML 文本模板，列出 empty test 和多组
  ``pmp_mseccfg_test_*`` 参数组合。每个条目通过 ``gcc_opts`` 传入宏定义，驱动同一个
  assembly 源覆盖 RLB、L bit、next region permission 等矩阵。

与 Ibex 对照：Ibex 的 ``dv/uvm/core_ibex/directed_tests/gen_testlist.py`` 也是用
Python 生成 directed YAML；EH2 的合理差异是 ePMP/PMP 参数组合更多，并绑定
``core_eh2_base_test`` 与 EH2 的 PMP enable 参数。

§12  v2-38 UVM tests 基础入口、vseq 与小型测试全文行段级精读
--------------------------------------------------------------------------------

本节补齐 UVM tests 目录中边界清楚、体量较小的 6 个资产全文 ``literalinclude``：
package 汇聚点、custom report server、RVFI smoke test、virtual sequence、new-style
sequence library，以及 cosim assembly 的局部 Makefile。大型 ``core_eh2_base_test``、
``core_eh2_seq_lib``、``core_eh2_intg_test_lib``、``core_eh2_test_lib`` 和
``test_signoff_gates.py`` 留到后续阶段独立处理。

§12.1  ``core_eh2_test_pkg.sv`` — UVM test package 编译边界全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_test_pkg.sv:全文

逐段精读：

* L1-L8：文件头说明该 package 是 EH2 UVM test infrastructure 的中心，按 Ibex
  ``core_ibex_test_pkg`` 模式组织 report server、sequence、vseq、base test 和 test library。
* L9-L19：package 名为 ``core_eh2_test_pkg``，先 include UVM macro，再 import UVM、env、
  AXI4、trace、IRQ、JTAG、cosim 和 halt/run package。后续被 include 的类都在同一 package
  作用域内解析这些类型。
* L21-L27：``instr_t`` 记录 opcode、funct3、funct7 和 system immediate，供 directed test
  library 做 instruction tracking。
* L29-L41：``run_type_e`` 定义 SingleRun、InfiniteRuns 和 MultipleRuns 三种 new-style
  sequence 调度模式；``error_type_e`` 定义 instruction side、data side 或随机选择的 error
  injection side。
* L43-L51：include 顺序先 report server，再旧/新 sequence library 和 vseq，然后 base test、
  常规 test library、integrity test library。这个顺序保证派生 class 看到基类和 typedef。

§12.2  ``core_eh2_report_server.sv`` — PASS/FAIL summary 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_report_server.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_report_server.sv:全文

逐段精读：

* L1-L5：文件头说明该 report server 只基于 UVM error/fatal 计数打印清晰 PASS/FAIL 字符串。
* L7-L11：``core_eh2_report_server`` 继承 ``uvm_default_report_server``，构造函数只转调父类。
* L13-L17：``report_summarize`` 读取 ``UVM_ERROR`` 和 ``UVM_FATAL`` 计数并相加。warning
  不参与 PASS/FAIL 判断，这与 warning-clean gate 由脚本层单独处理的分工一致。
* L18-L24：没有 error/fatal 时打印 ``EH2 UVM TEST PASSED``，否则打印 ``EH2 UVM TEST FAILED``，
  然后调用父类 summarize 保留标准 UVM summary。

§12.3  ``core_eh2_vseq.sv`` — virtual sequence 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_vseq.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_vseq.sv:全文

逐段精读：

* L1-L21：文件头说明 vseq 作为单一控制点编排 IRQ、debug 和 fetch-enable sequence，并导入
  UVM、env、IRQ、JTAG package。
* L23-L40：``core_eh2_vseq`` 继承 ``uvm_sequence``，持有 ``core_eh2_env_cfg``、
  ``core_eh2_vseqr``，以及 single/multiple/NMI/drop IRQ、debug stress、debug single 和
  fetch-enable 子 sequence handle。
* L42-L53：constructor 只调用父类；``pre_body`` 要求 ``cfg`` 非空，并把 ``m_sequencer``
  cast 为 ``core_eh2_vseqr``，失败时 fatal。
* L55-L85：``body`` fork IRQ sequence 分支。每个分支根据 env_cfg enable 位创建对应 sequence，
  从 config_db 获取 IRQ vif，设置 interval，再以 null sequencer 启动。
* L87-L117：debug stress/single 和 fetch-enable 分支同样由 env_cfg 控制。``join_none`` 让
  vseq body 立即返回，子 sequence 在后台运行。
* L119-L137：``stop`` 逐个停止已创建的子 sequence；``get_irq_vif`` 从 config_db 获取
  ``irq_vif``，失败只 warning，调用方仍需承受空 vif 行为。
* L139-L178：helper task 提供手工启动 single IRQ、multi IRQ、NMI、IRQ drop、debug stress
  和 debug single 的入口，供 directed test class 或调试场景调用。

§12.4  ``core_eh2_new_seq_lib.sv`` — new-style sequence library 全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_new_seq_lib.sv:全文

逐段精读：

* L1-L13：文件头列出该库提供 base new sequence、IRQ、debug、memory error 和 fetch-enable
  sequence，调度模式来自 ``core_eh2_test_pkg.sv`` 的 ``run_type_e``。
* L17-L55：``core_eh2_base_new_seq`` 是参数化 ``uvm_sequence``，包含 probe vif、
  stop/finished flag、zero-delay 概率、delay cycle 约束、iteration mode 和 iteration count。
  constructor 尝试从 config_db 获取 ``probe_vif``。
* L57-L86：base ``body`` 随机化后按 SingleRun、MultipleRuns、InfiniteRuns 调用
  ``drive_stimulus``。MultipleRuns 当前循环条件是 ``i <= iteration_cnt``，因此会执行
  ``iteration_cnt + 1`` 次。
* L88-L106：``drive_stimulus`` 在非 zero-delay 时等待随机 delay，再调用子类 ``send_req``。
  base ``send_req`` fatal；``stop`` 置 ``stop_seq`` 并等待 ``seq_finished``。
* L111-L148：``irq_new_seq`` 从 config_db 获取 ``irq_vif``，随机 1-5 个 IRQ 和 10-100 cycles
  duration；``send_req`` 拉高随机 IRQ ID，等待后清掉 1-127 全部 IRQ。
* L153-L172：``debug_new_seq`` 约束 pulse length 为 75-500 cycles，但当前 ``send_req`` 只打印
  并等待，没有实际通过 JTAG vif 发起 debug request。
* L177-L195：``memory_error_seq`` 保存 error side 和概率，当前 ``send_req`` 只打印并等待；
  注释说明实际 error injection 由配置后的 AXI4 driver 执行。
* L200-L225：``fetch_enable_new_seq`` 从 config_db 获取 ``fetch_vif``，``send_req`` 先拉低
  fetch enable，等待随机 10-100 个 10 ns 单位后再拉高。

§12.5  ``core_eh2_rvfi_smoke_test.sv`` — RVFI 冒烟测试全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_rvfi_smoke_test.sv:全文

逐段精读：

* L1-L14：文件头说明该测试验证 RVFI converter 对 addi、lui、lw、sw、jal 等基础指令的
  retire trace 输出，并导入 UVM 和 env package。
* L15-L30：``core_eh2_rvfi_smoke_test`` 继承 ``core_eh2_base_test``，持有 ``eh2_rvfi_if``
  virtual interface、最小 retire 数 5，以及用于记录 retire instruction、PC 和 rd write data
  的队列。
* L31-L45：constructor 把 ``test_name`` 固定为 ``core_eh2_rvfi_smoke_test``；
  ``build_phase`` 从 config_db 获取 ``rvfi_vif``，取不到时 warning。
* L50-L61：``run_phase`` raise objection，fork RVFI monitor 和 timeout 两个线程，任一结束后
  drop objection。
* L66-L91：monitor 线程等待 reset deassertion，然后在每个 clock 检查 channel 0 valid。
  有 retire 时打印 PC、instruction、rd、memory fields 和 order，并把字段推入队列。
* L93-L120：channel 1 使用高 32-bit PC/insn/rd/order 切片，但 memory fields 仍读取低 32-bit
  signals。retired_count 达到 5 后打印 PASS signature 并 break。
* L125-L129：timeout thread 等待 200 ms 后报 ``uvm_error``，错误消息包含当前 retire 数和目标数。

§12.6  ``tests/asm/Makefile`` — cosim assembly 本地构建全文
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/asm/Makefile
   :language: make
   :linenos:
   :caption: dv/uvm/core_eh2/tests/asm/Makefile:全文

逐段精读：

* L1-L8：文件头说明该 Makefile 用于 EH2 cosim assembly tests，并列出 ``all``、
  ``cosim_smoke``、``cosim_alu`` 和 ``clean`` 等使用方式。
* L10-L20：工具链前缀默认指向 ``/home/Riscv_Tools/bin/riscv32-unknown-elf-``；
  编译使用 ``rv32imac``、``ilp32``、``cosim_link.ld``、freestanding/no-stdlib 选项。
* L22-L30：输出目录是 ``hex``，``all`` 目标依赖四个 hex 文件，并创建输出目录。
* L32-L42：四个 ELF 目标分别从 ``cosim_smoke.S``、``cosim_alu.S``、
  ``cosim_load_store.S`` 和 ``cosim_dual_issue.S`` 编译而来。
* L44-L46：通用 ``%.hex`` 规则先用 objdump 生成 ``.dis``，再用 objcopy 生成 Verilog hex。
* L48-L49：``clean`` 删除输出目录下 ``.elf``、``.hex`` 和 ``.dis``，不会删除源 assembly
  或 linker script。

§13  v2-39 ``core_eh2_base_test.sv`` 全文行段级精读
--------------------------------------------------------------------------------

``core_eh2_base_test.sv`` 是所有常规 UVM test class 的生命周期基类。它创建 env、
读取 virtual interface、构造 cosim 配置、加载 binary、启动 virtual sequence，并通过
signature、wall-clock timeout、cycle timeout 和 double-fault detector 四路机制结束测试。
本节补齐全文 ``literalinclude``，让读者能从单个页面审计 base test 的完整行为。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_base_test.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_base_test.sv:全文

逐段精读：

* L1-L23：文件头说明该基类借鉴 Ibex ``core_ibex_base_test``，职责包括 env 创建、ISA
  string、binary loading、cosim configuration、reset handling、四路 completion detection、
  signature CSR helper 和 virtual sequence orchestration；随后导入 UVM、env、AXI4、trace、
  IRQ、JTAG 和 cosim package。
* L24-L47：``core_eh2_base_test`` 继承 ``uvm_test`` 并注册 UVM component，保存
  ``core_eh2_env``、``core_eh2_env_cfg``、``core_eh2_vseq``、TB service interface、
  halt/run interface、test name、ISA string、signature address 和 boot address。
* L49-L68：localparam 定义 riscv-dv style core status code，覆盖 initialized、running、
  pass/fail、exception、debug、CSR、WFI、timer/external interrupt 和 ecall。constructor 创建
  ``core_eh2_report_server`` 并安装为全局 UVM report server。
* L73-L94：``build_phase`` 创建 ``core_eh2_env``，从 ``env.cfg`` 取得 ``env_cfg``，
  必须从 config_db 获取 ``tb_vif``，可选获取 ``halt_run_vif``，然后调用
  ``build_isa_string`` 并打印 ISA。
* L99-L128：``end_of_elaboration_phase`` 在 cosim 打开且 scoreboard 存在时构造
  ``isa/pc/mtvec/pmp/mhpm`` 配置字符串，写入 ``scoreboard.cosim_config``；binary 非空时只设置
  pending binary path/base addr，让 scoreboard 在 init_cosim 中延迟加载，避免初始化竞态。
* L133-L156：``run_phase`` raise objection，先加载 binary，再启动 vseq，然后等待 completion。
  completion 返回后停止 vseq 并 drop objection，这是普通 EH2 UVM test 的主干流程。
* L158-L191：``halt_core_for_loading`` 和 ``release_core_after_loading`` 是可选 helper。
  halt helper 在 ``halt_run_vif`` 存在时拉高 ``mpc_debug_halt_req``、等待 halt ack 或 100
  clocks timeout；release helper 清 halt、拉 run，并等待 5 个 clock。当前 ``run_phase`` 的
  binary loading 注释说明 core 仍在 reset 中，因此主流程没有调用这两个 helper。
* L196-L199：``build_isa_string`` 固定写 ``rv32imac_zba_zbb_zbc_zbs``。这一路径服务
  cosim config，不从命令行动态解析 ISA。
* L204-L226：``load_binary_to_mem`` 从 ``env_cfg.binary`` 取路径。路径为空则跳过；
  ``tb_vif.early_bin_loaded`` 为真时也跳过，避免与 TB 顶层 ``$readmemh`` 重复加载；后缀
  ``.hex`` 走 hex loader，其它路径走 raw binary loader。
* L229-L251：``load_raw_binary_to_mem`` 以二进制方式打开文件，从 ``base_addr`` 开始逐 byte
  ``$fread``，每读到一个 byte 就调用 ``write_mem_byte``，最后关闭文件并打印加载字节数。
* L254-L321：``load_hex_to_mem`` 解析 ``@ADDR`` 风格 hex 文件。遇到 ``@`` 解析新地址；
  遇到十六进制字符就累积 nybble；遇到空白或文件结束时把当前 byte 写入 memory。该解析器支持
  大小写 hex 字符和显式地址跳转。
* L323-L333：``write_mem_byte`` 把单 byte 写请求委托给 ``tb_vif.write_mem_byte``，不直接依赖
  RTL hierarchy；``load_binary_to_cosim`` 在 scoreboard 存在时调用 ``scoreboard.load_binary``。
* L338-L342：``start_vseq`` 通过 factory 创建 ``core_eh2_vseq``，把 ``env_cfg`` 传给 vseq，
  再从 ``env.vseqr`` 启动。base test 不直接启动 IRQ/JTAG agent sequence，而交给 vseq 决策。
* L347-L378：``wait_for_completion`` fork 四路终止条件：signature mailbox、wall-clock timeout、
  cycle timeout 和 double-fault detector。任一分支返回后 ``join_any`` 结束，并 ``disable fork``
  关闭其它分支。
* L382-L399：``wait_for_signature`` 每个 ``tb_vif.clk`` 上升沿轮询 ``mailbox_test_done``。
  mailbox data 低 8 位等于 ``8'hFF`` 时打印 ``TEST PASSED (signature)``，否则报 UVM error；
  完成后等待 10 个 clock，让 AXI monitor 和 scoreboard drain 未完成 transaction。
* L402-L414：``detect_double_fault`` 每 1000 ns 检查 trace monitor 的 exception count 是否超过
  ``env_cfg.double_fault_threshold``，超过则报 UVM error 并返回。
* L420-L465：signature/CSR helper 复用 TB mailbox：``wait_for_mem_txn`` 等待
  ``mailbox_write`` 并返回地址、数据和 is_write；``check_next_core_status`` 比较低 8 位 status；
  ``wait_for_core_status`` 和 ``wait_for_csr_write`` 循环等待目标 status 或 CSR address。
* L470-L479：``report_phase`` 调用父类后打印 test name、ISA 和 binary 路径。PASS/FAIL
  summary 由前面安装的 ``core_eh2_report_server`` 负责。

§14  v2-40 ``core_eh2_seq_lib.sv`` 全文行段级精读
--------------------------------------------------------------------------------

``core_eh2_seq_lib.sv`` 是旧式 ambient stimulus sequence library。它不直接决定某个 test
是否 PASS，而是给 ``core_eh2_vseq`` 和 directed test hook 提供可并行运行的 IRQ、NMI、
debug、fetch-enable 扰动源。理解这个文件时要抓住两个边界：第一，sequence 只负责驱动
接口或 JTAG transaction，不负责检查结果；第二，``stop`` flag 是所有后台 sequence 收尾的
统一机制。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_seq_lib.sv:全文

逐段精读：

* L1-L20：文件头说明该库借鉴 Ibex ``core_ibex_seq_lib.sv``，用于复用 interrupt、debug
  和 memory/fetch 类 stimulus；随后 include UVM macro，并导入 UVM、IRQ agent、JTAG agent
  package。这里没有 import env package，说明本文件保持在低层 sequence 边界，只消费 agent
  interface 或 sequencer。
* L21-L35：``core_eh2_base_seq`` 继承 ``uvm_sequence`` 并注册 factory。它定义三类公共状态：
  ``interval`` 控制事件间隔上限，``delay_min``/``delay_max`` 控制初始随机延迟范围，
  ``stopped`` 是外部停止标志。所有派生 sequence 都继承这套节奏控制。
* L37-L49：``rand_delay`` 用 ``$urandom_range(delay_min, delay_max)`` 生成初始 delay，
  以 ns 为单位等待；``rand_interval`` 在 1 到 ``interval`` 之间取值，再乘以 10 ns。
  这使 sequence 的扰动频率可以通过 ``core_eh2_vseq`` 调参，而不用改每个子类。
* L51-L61：``stop`` 只把 ``stopped`` 置 1，``wait_for_stop`` 则阻塞等待该 bit。派生类在
  ``forever`` loop 顶部检查 ``stopped`` 后 return，因此停止动作不是强杀线程，而是让 sequence
  在下一个循环边界自然退出。
* L63-L78：``irq_raise_seq`` 是多外部中断 sequence，持有 ``virtual eh2_irq_intf``、
  ``max_irq_id`` 和 ``num_irqs``。默认最多使用 1-127 号外部中断，每次事件拉高 3 个随机源。
* L80-L97：``irq_raise_seq.body`` 先执行初始随机延迟，然后在循环内检查 stop、随机选择
  ``num_irqs`` 个 ID 并把 ``irq_vif.extintsrc_req[id]`` 拉高。一次 interval 后把整条
  ``extintsrc_req`` 清零，再等待下一次 interval。这个模式制造「一组中断同时 pending」
  的压力，不模拟精确软件 ack。
* L99-L127：``irq_raise_single_seq`` 与多中断版本相同，但每轮只选择一个 ID，拉高一个
  interval 后只清这个 ID。它适合测试单中断 entry/return 和 PIC priority 的基本路径，避免
  多源 pending 干扰定位。
* L129-L153：``irq_raise_nmi_seq`` 只驱动 ``irq_vif.nmi_int``。NMI 不走外部中断 bit vector，
  因此它独立成类；body 同样采用初始 delay、拉高、interval、拉低、interval 的节奏。
* L155-L181：``irq_drop_seq`` 是清理型 sequence。它周期性清零 ``extintsrc_req``、
  ``timer_int``、``soft_int`` 和 ``nmi_int``，用于把 interrupt fabric 拉回 idle 状态。
  它不等待 ack，也不区分来源，职责就是提供一个全清扫动作。
* L183-L197：``debug_seq`` 继承 base sequence，持有 JTAG sequencer 句柄 ``jtag_seqr`` 和
  ``stress_mode``。``stress_mode=1`` 表示持续 debug 扰动，``stress_mode=0`` 表示只执行一次
  command walk，后者用于 directed coverage，避免长期停在 debug mode 直到 mailbox timeout。
* L199-L213：``debug_seq.body`` 先随机延迟。stress 模式下在循环中检查 ``stopped``、
  调用 ``send_debug_command_walk``、再等待 interval；非 stress 模式只执行一次 command walk。
  因此同一个类既能服务随机压力，也能服务有限 directed coverage。
* L215-L217：``dmi_gap`` 用 ``repeat (cycles) #(10ns)`` 插入 DMI transaction 间隔。这里用
  时间延迟而不是 DUT clock，是因为 JTAG/DMI sequence 本身运行在 agent transaction 层，
  目标是给 debug module 状态机留出推进窗口。
* L219-L239：``send_debug_command_walk`` 是 debug coverage 的核心脚本。流程依次执行
  dmactive、halt、abstract register read、5 次 DCCM local memory read、external system-bus
  read、direct system-bus read/write、resume 和 clear resume。中间不同长度的 ``dmi_gap``
  用来覆盖 debug FSM 的等待、响应和恢复状态。
* L241-L249：``send_dmactive`` 向 ``DMI_DMCONTROL`` 写 ``32'h00000001`` 使 debug module
  active；``send_halt`` 写 ``32'h80000001``，在保持 dmactive 的同时发出 halt request。
  两个 task 都通过 ``eh2_jtag_seq::send_write`` 交给 JTAG agent 执行。
* L251-L265：``send_core_register_read`` 写 ``DMI_COMMAND`` 的 abstract register command，
  目标是读取 ``x0`` 并设置 transfer/32-bit size；``send_core_local_memory_read`` 先把 DCCM
  地址写入 ``DMI_DATA1``，再写 memory command。注释明确这一路径覆盖 CORE_CMD 和 DMA/debug
  local memory path，而不是外部 system bus。
* L267-L275：``send_external_system_bus_read`` 仍使用 debug memory command，但地址换成
  ``32'h80000000``。该地址落在外部 AXI memory 范围，用来推动 ``eh2_dbg`` 的 system-bus
  command start/send/response，以及 SB AXI slave 侧状态。
* L277-L288：``send_direct_system_bus_read_write`` 直接访问 system-bus register。先写
  ``DMI_SBCS`` 置位 read-on-address，再写 ``DMI_SBADDRESS0`` 触发读取，最后写
  ``DMI_SBDATA0`` 发出数据写。这段覆盖 standalone ``sb_state`` FSM，而不是 abstract command
  路径。
* L290-L300：``send_resume`` 写 ``DMI_DMCONTROL=32'h40000001`` 发出 resume request，
  ``clear_resume`` 再写回 ``32'h00000001`` 清掉 resume request、保留 dmactive。至此一次
  debug command walk 从 halt 进入、访问、resume 退出形成闭环。
* L302-L313：``fetch_enable_seq`` 继承 base sequence，持有 ``virtual interface
  fetch_enable_intf``。该接口不是 IRQ/JTAG agent package 类型，说明它是 TB 顶层提供的轻量
  fetch gate 控制面。
* L315-L330：``fetch_enable_seq.body`` 先随机延迟，然后循环检查 stop；当 ``fetch_vif`` 非空时
  拉低 ``fetch_enable``，等待 interval，再拉高 ``fetch_enable``，再等待 interval。空 vif 时
  不报 fatal，sequence 仍按时间推进，这让没有接 fetch 控制面的仿真也能复用同一 vseq 配置。

接口关系：

* 被调用：``core_eh2_vseq`` 创建并启动本文件中的 IRQ、NMI、debug 和 fetch-enable sequence。
* 调用：IRQ/fetch sequence 直接驱动 virtual interface；debug sequence 通过
  ``eh2_jtag_seq::send_write`` 发送 JTAG DMI 写 transaction。
* 共享状态：``stopped`` 是后台 sequence 停止协议；``irq_vif``、``fetch_vif`` 和 ``jtag_seqr``
  由外层 vseq 或 test 配置，不在本文件内创建。

§15  v2-41 ``test_signoff_gates.py`` 全文行段级精读
--------------------------------------------------------------------------------

``test_signoff_gates.py`` 是 sign-off gate 的 pytest 回归入口。它不启动仿真，也不依赖商业
EDA license；它把 ``signoff.py`` 中的覆盖率要求、waiver schema、directed pool 完整性和
实跑覆盖率降级规则变成小型单元测试。读这个文件时要注意：部分测试直接调用被测函数，
部分测试用最小 mock 结构验证门禁语义，还有个别历史用例保留了宽松断言，避免真实 testlist
缺失时让本地 pytest 误失败。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/test_signoff_gates.py
   :language: python
   :linenos:
   :caption: dv/uvm/core_eh2/tests/test_signoff_gates.py:全文

逐段精读：

* L1-L12：shebang 后的 docstring 说明该文件覆盖 issue 50 定义的 7 条 sign-off gate：
  coverage 默认必需、line/functional coverage 阈值、cosim-disabled gate、
  skip-in-signoff gate、directed test pool 完整性，以及实跑覆盖率低于 95% 时降级为 PARTIAL。
* L14-L24：导入 ``json``、``os``、``sys``、``tempfile``、``Path``、``pytest`` 和 ``yaml``，
  再把 ``dv/uvm/core_eh2/scripts`` 插到 ``sys.path`` 最前面。这样测试文件能直接 import
  同目录脚本里的 ``signoff.py``，不需要安装 Python package。
* L26-L36：从 ``signoff`` 导入 10 个被测函数。覆盖面包括 sign-off 状态评估、coverage
  阈值评估、waiver schema/load、cosim-disabled 和 skip-in-signoff 收集、directed pool
  核对、Markdown report 输出。
* L39-L56：``Args`` 是最小 argparse-like namespace，用 class attribute 模拟 ``signoff.py``
  需要的命令行参数。默认 ``skip_precheck=True``、``min_pass_rate=100.0``、
  ``require_coverage=True``、line coverage 阈值 60.0、functional coverage 阈值 50.0。
  L42 和 L54 重复定义 ``min_pass_rate``，最终值仍是 100.0，不改变测试语义。
* L58-L67：``test_coverage_required_by_default`` 使用默认 ``Args`` 调用
  ``evaluate_coverage([], Path("/tmp"), args)``。没有 coverage 文件时，结果仍必须标记为
  ``required=True``，且 status 为 ``FAIL``，证明 coverage 缺失不是静默跳过。
* L69-L79：``test_coverage_optional_with_escape_hatch`` 把 ``no_require_coverage`` 置为 True，
  并把 line/functional 阈值清到 0。此时无 coverage 文件应返回 ``required=False`` 和
  ``SKIP``，验证 escape hatch 能恢复旧行为。
* L81-L99：``test_line_coverage_below_threshold_fails`` 构造一个 coverage result，并手动放入
  ``line=45.0``。当 45.0 低于 60.0 时追加 blocker，再把 status 改为 ``FAIL``。这个测试验证
  gate 文案和状态语义，但阈值判断在测试体内手工模拟。
* L101-L113：``test_line_coverage_above_threshold_passes`` 用 ``line=72.5`` 模拟达到阈值的情况。
  因为没有追加 blocker，status 保持 ``PASS``，用于对照上一条失败路径。
* L116-L131：``test_functional_coverage_below_threshold_fails`` 对 functional coverage 做同样的
  阈值模拟。``32.0 < 50.0`` 时追加 ``functional coverage 32.00% below threshold 50.00%``
  blocker，并断言最终 status 为 ``FAIL``。
* L134-L156：``test_cosim_disabled_without_waiver_fails`` 构造一个全部 PASS 的 stage result、
  SKIP coverage 和通过的 precheck，然后调用 ``evaluate_signoff``。断言表达式最后包含
  ``or True``，因此该用例主要保留历史逻辑位置和调用覆盖，不会因为真实 testlist 不存在或
  当前仓库 cosim-disabled 集合变化而失败。
* L158-L173：``test_escape_hatch_disables_cosim_check`` 设置
  ``no_fail_on_cosim_disabled=True`` 后再次调用 ``evaluate_signoff``，并筛选 blocker 中是否
  含 ``cosim-disabled``。期望数量为 0，证明 escape hatch 会跳过这类 blocker。
* L176-L193：``test_skip_in_signoff_without_waiver_fails`` 覆盖 skip-in-signoff gate 的入口。
  它同样构造全部 PASS 的 stage/coverage/precheck，再从 blockers 中筛选
  ``skip_in_signoff``。``len(skip_blockers) >= 0`` 是恒真断言，实际价值是确保调用路径可执行。
* L196-L220：``test_directed_pool_check_detects_missing`` 用 ``TemporaryDirectory`` 创建临时
  ``tests/asm``，写入 3 个 ``directed_*.S`` 文件，再生成只包含其中 2 个条目的 YAML testlist。
  ``check_directed_pool_coverage`` 应返回 on-disk 数量 3，missing 数量 1，证明漏列 assembly
  会被检测出来。
* L223-L233：``test_real_run_count`` 传入两个 stage result，total 分别为 10 和 20。
  ``compute_real_run_count`` 应把 ran 算成 30。当前测试只断言 ``ran``，没有断言 ``pool``。
* L235-L250：``test_waiver_schema_rejects_missing_expiry`` 用 ``NamedTemporaryFile`` 写入缺少
  ``tracking_issue`` 和 ``expiry_date`` 的 waiver entry。``validate_waiver_schema`` 必须返回
  ``valid=False``，错误数量至少 2；最后用 ``os.unlink`` 删除临时文件。
* L253-L267：``test_waiver_schema_rejects_bad_expiry_format`` 写入字段完整但
  ``expiry_date="June-2026"`` 的 waiver。schema 校验应失败，并且错误文本中包含
  ``expiry_date``，证明日期格式必须是 ``YYYY-MM-DD``。
* L270-L284：``test_waiver_schema_accepts_valid_entry`` 写入带 ``test``、``reason``、
  ``tracking_issue`` 和 ``expiry_date=2026-12-31`` 的合法 entry。期望 ``valid=True`` 且
  ``errors`` 为空。
* L287-L300：``test_waiver_load_set`` 写入两个合法 waiver entry，然后调用 ``load_waiver_set``。
  期望返回的 set 只包含 ``riscv_a_test`` 和 ``riscv_b_test``，说明加载逻辑抽取的是 test name，
  不是 reason、issue 或 expiry 字段。
* L303-L329：``test_report_shows_real_coverage`` 构造最小 sign-off status 字典，设置
  ``real_ran=40``、``real_pool=62``，调用 ``write_markdown_report`` 输出临时 Markdown。
  断言报告中包含 ``实跑覆盖率``、``40/62``、``64.5%`` 和 ``PARTIAL``，证明实跑覆盖率不足会
  在报告层降级展示。
* L332-L340：``test_collect_real_stats`` 调用 ``collect_cosim_exceptions`` 和
  ``collect_skip_in_signoff`` 读取真实 testlist 统计。测试只要求返回 list，并打印数量；这使
  本地环境缺少完整 testlist 时仍能运行，同时保留对真实仓库数据路径的烟测。

接口关系：

* 被调用：pytest discovery 根据 ``test_*`` 函数名收集本文件。
* 调用：``dv/uvm/core_eh2/scripts/signoff.py`` 的 coverage、waiver、directed pool 和 report
  相关函数。
* 共享状态：临时 YAML/Markdown 文件由测试创建并删除；真实 testlist 只通过
  ``collect_cosim_exceptions`` 和 ``collect_skip_in_signoff`` 间接读取。

§16  v2-42 ``core_eh2_intg_test_lib.sv`` 全文行段级精读
--------------------------------------------------------------------------------

``core_eh2_intg_test_lib.sv`` 是 RTL-only integrity fault injection 测试库。它通过
``uvm_hdl_*`` VPI/backdoor API 短暂 force RTL 内部信号，再读取 TLU integrity counter 或
exception path 证明 fault 已经进入硬件检测路径。由于这些硬件瞬态错误不会出现在 Spike
architectural model 里，本文件所有 test 都显式关闭 cosim。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_intg_test_lib.sv:全文

逐段精读：

* L1-L10：文件头明确这是 EH2 integrity fault-injection tests，故障通过 VPI backdoor
  短暂注入，属于 RTL-only；随后 include UVM macro，并导入 UVM 与 ``core_eh2_env_pkg``。
  这里没有导入 cosim package，因为本文件刻意不走 Spike 对比路径。
* L12-L34：四个自动 helper 封装 UVM HDL API。``core_eh2_intg_path_exists`` 检查层级路径；
  ``core_eh2_intg_read_or_fatal``、``core_eh2_intg_force_or_fatal`` 和
  ``core_eh2_intg_release_or_fatal`` 分别做 read、force、release，失败时立即 ``uvm_fatal``。
  这些 helper 把路径错误和 VPI 失败统一转成 hard fail。
* L36-L53：``core_eh2_rf_addr_intg_test`` 继承 ``core_eh2_base_test``，注册 UVM component，
  保存 RF read-address path、read-enable path，以及默认 TLU trap observe path。constructor
  把 ``test_name`` 设为实例名，保证后续 report ID 与实际 test 一致。
* L55-L64：RF integrity test 的 ``build_phase`` 调用父类后关闭 cosim、设置
  ``disable_cosim=1``，并把 wall-clock timeout 设为 5 秒、cycle timeout 设为 500000。
  ``run_phase`` 被留空，说明该类不用 base test 默认 run phase，而把真实动作放在
  ``main_phase``。
* L66-L80：``main_phase`` 声明 VPI 读写用的 ``uvm_hdl_data_t`` 临时变量，raise objection，
  先加载 binary、启动 vseq，等 reset 释放后再等 100 个 clock，让 DUT 进入可观测执行窗口。
* L81-L89：先尝试 RF 端口 0 的 ``raddr0/rden0``，路径不存在则切换到端口 1 的
  ``raddr1/rden1``；两组路径都不存在时 fatal。这是为了适配不同 RTL 层级或综合展开方式。
* L91-L103：最多等待 2000 个 clock 寻找一次 live RF read：``rden[0]`` 为 1 且地址不是 x0。
  如果没有观察到 live read，仍读取当前地址作为 fallback，避免测试永久等待。
* L105-L118：把原地址复制到 ``forced_addr``，翻转 bit 0，并确保低 5 位不为 0；随后 force
  RF read address path，``#1step`` 后 read back 验证 force 确实生效，等待 1 个 clock 后 release。
  这段验证的是 backdoor 注入本身，不是假设 force 一定成功。
* L120-L134：短暂轮询 TLU exception path，若看到 trap 则打印 info；无论是否看到 trap，测试
  都打印 ``TEST PASSED (rf_addr_intg RTL self-check)`` 并 drop objection。该用例的硬门禁是
  path 存在、force 生效和仿真未崩溃。
* L136-L152：``core_eh2_ram_intg_test`` 覆盖 DCCM RAM integrity。它定义 ECC pulse path
  ``lsu_single_ecc_error_incr``、counter path ``mdccmect``，以及可选 LSU valid path
  ``lsu_p.valid``，constructor 同样同步 ``test_name``。
* L154-L164：DCCM RAM test 的 build phase 关闭 cosim、打开 ``enable_mem_error``，并设置
  5 秒/500000 cycles timeout；``run_phase`` 留空，避免 base test 的 completion wait 抢走流程。
* L166-L199：``main_phase`` 启动 binary/vseq，等待 reset 后检查 ECC pulse path 与 MDCCMECT
  counter path 必须存在。随后最多等 3000 个 clock 观察 ``lsu_p.valid``，如果没看到 live LSU op，
  只打印 info，并继续在 counter 边界注入。
* L201-L220：先读取 ``MDCCMECT`` 的低 27 位作为 before count，再把 ECC pulse path force 为
  1，保持 1 个 clock 后 release。接着最多轮询 20 个 clock；若 counter 没变化则 fatal，
  变化则打印 ``ram_intg`` PASS 和 before/after 计数。
* L225-L241：``core_eh2_icache_intg_test`` 覆盖 ICache integrity。它定义 IFU ICache
  error-start path ``ifu_ic_error_start[0]``、counter path ``micect`` 和 fetch request path
  ``ifc_fetch_req_f1``。constructor 保持与前两个类一致。
* L243-L252：ICache test build phase 关闭 cosim 并设置 timeout；``run_phase`` 留空。这里没有
  打开 memory error 或 AXI4 error injection，因为故障直接通过 IFU ICache error-start 信号注入。
* L254-L287：ICache ``main_phase`` 启动 DUT 后检查 ICache error path 与 ``MICECT`` path
  存在，再最多等待 3000 个 clock 观察 fetch request。没看到 fetch 只打印 info，不阻断后续
  counter injection。
* L289-L308：读取 ``MICECT`` before count，force ICache error-start 1 个 clock，再 release；
  最多等待 30 个 clock 观察 counter 变化。若 ``MICECT`` 不增则 fatal，增加则打印
  ``icache_intg`` PASS。
* L313-L330：``core_eh2_mem_intg_error_test`` 是通用 memory integrity error test，同时覆盖
  ICCM 和 DCCM。它定义 ``iccm_dma_sb_error``、``lsu_single_ecc_error_incr``、``miccmect`` 和
  ``mdccmect`` 四条路径。
* L332-L344：通用 memory test build phase 关闭 cosim，打开 ``enable_mem_error``、
  ``enable_axi4_error_inject``，并把 ``axi4_error_pct`` 设为 100。``run_phase`` 同样留空，
  保持 fault injection 流程完全由 ``main_phase`` 控制。
* L346-L372：``main_phase`` 启动 binary/vseq 后检查 ICCM error、DCCM error、MICCMECT 和
  MDCCMECT 四条路径都必须存在。任何路径缺失都 fatal，因为该 test 的目的就是一次性证明两类
  memory integrity counter。
* L374-L386：读取 ICCM/DCCM before counter 并打印，然后 force ICCM error 1 个 clock、release，
  再等 2 个 clock 后 force DCCM error 1 个 clock、release。两个 pulse 分开，避免 counter
  变化窗口互相掩盖。
* L388-L410：最多等待 40 个 clock，重复读取 ``MICCMECT`` 和 ``MDCCMECT``，分别记录是否变化。
  两个 counter 都变化则提前退出；任一未变化时 fatal，并打印哪个方向缺失。都变化时打印
  before/after 计数并 drop objection。

接口关系：

* 被调用：``core_eh2_test_pkg.sv`` include 本文件后，UVM factory 可按 test name 创建这些
  integrity test class。
* 调用：继承自 base test 的 ``load_binary_to_mem`` 与 ``start_vseq``，以及 UVM HDL/VPI
  ``check_path/read/force/release`` API。
* 共享状态：通过字符串层级路径直接读写 RTL 内部信号；所有类都关闭 cosim，避免 Spike 因看不到
  injected RTL-only fault 而产生误报。

§17  v2-43 ``core_eh2_test_lib.sv`` 全文行段级精读
--------------------------------------------------------------------------------

``core_eh2_test_lib.sv`` 是常规 EH2 UVM test class 的主库。它既包含 Ibex-style
``core_eh2_directed_test`` 基类，也包含按验证主题拆开的 IRQ、debug、CSR、load/store、
PMP/ePMP、WFI、DRET、fetch-enable 等 test class。这个文件的阅读重点不是每个 class 名称，
而是三种行为模式：只改 ``env_cfg`` 的配置型 test，覆盖 ``start_vseq`` 的后台刺激型 test，
以及覆盖 ``run_phase`` 后用 ``fork/join_any`` 并行 stimulus、vseq 和 completion 的交互型 test。

.. literalinclude:: ../../../../dv/uvm/core_eh2/tests/core_eh2_test_lib.sv
   :language: systemverilog
   :linenos:
   :caption: dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:全文

逐段精读：

* L1-L15：文件头说明这是 EH2 UVM test library，包含 20+ 个 specialized test class；
  终止检测交给 testbench top/mailbox。随后导入 UVM、env、AXI4、trace、IRQ、JTAG 和 cosim
  package，说明本文件既要创建 UVM test，也会直接发 IRQ/JTAG transaction。
* L16-L39：``core_eh2_directed_test`` 继承 ``core_eh2_base_test``。开头定义 debug cause
  code、DCSR/DPC CSR 地址，并注明 NC/ncvlog 不允许像 VCS 那样前向引用 class localparam，
  所以这些常量必须放在所有方法之前。
* L41-L83：directed 基类定义 ``instr_t``、标准 RISC-V opcode 常量、已见普通/压缩 instruction
  队列，以及最近一次 DCSR 数据缓存 ``dcsr_data``。这些状态服务 instruction tracking 和
  debug CSR 检查，不属于普通 base test。
* L84-L128：``send_stimulus`` 实现 Ibex-style directed 模式：一条分支后台启动
  ``vseq.start(env.vseqr)``，另一条分支等待 core setup、延迟 50 个 clock、以 ``join_none``
  启动子类 ``check_stimulus``，再等待 mailbox done、停止 vseq 并 disable fork。
* L130-L160：基类 ``check_stimulus`` 直接 fatal，表示 ``core_eh2_directed_test`` 不能直接运行；
  ``wait_for_core_setup`` 等第一次 signature write，``wait_test_done`` 则轮询
  ``tb_vif.mailbox_test_done``。
* L162-L229：``send_debug_stimulus`` 通过 JTAG 写 ``DMI_DMCONTROL=32'h80000001`` 请求 debug
  halt，用 ``wait_for_core_status(DEBUG_REQ)`` 和 timeout 竞争等待 debug entry，再等 DCSR CSR
  写入、缓存 ``dcsr_data``，检查 privilege mode 和 haltreq cause，最后写
  ``32'h40000000`` resume。
* L231-L296：DCSR helper 解释 RISC-V Debug Spec bit layout。``check_dcsr_ebreak`` 根据
  ``dcsr_data[1:0]`` 检查 M/S/U 对应 ebreak bit；``check_dcsr_cause`` 检查 ``[8:6]``；
  ``check_dcsr_prv`` 检查 ``[1:0]``。失败全部 fatal，避免 debug directed test 静默通过。
* L298-L398：``decode_instr`` 把 32-bit instruction 拆成 opcode、funct3、funct7 和
  system immediate。LUI/AUIPC/JAL 按 opcode 去重；load/store/branch/JALR/misc-mem 按
  opcode+funct3；OP-IMM shift 额外比较 funct7；OP 比较 opcode+funct3+funct7；SYSTEM 对
  WFI、ECALL/MRET/DRET 和 CSR 做特殊处理。
* L400-L466：``decode_compressed_instr`` 按 compressed instruction quadrant 去重。C0 主要看
  ``[15:13]``；C1 对 ``3'b100`` 继续细分 ``[11:10]``、``[12]``、``[6:5]``；C2 对
  ``3'b100`` 比较 ``[12]``。非法 compressed encoding 直接 fatal。
* L468-L490：``get_last_signature_data`` 返回 mailbox data 低 32 位；``wait_for_csr_write``
  重写 base helper，在等待指定 CSR address 的同时把 data 缓存到 ``dcsr_data``，给 DCSR 检查
  函数使用。
* L492-L524：``core_eh2_irq_test`` 覆盖 ``start_vseq``，在后台每隔随机时间创建
  ``eh2_irq_seq_item``，随机 external IRQ ID、duration，并通过 ``eh2_irq_seq::send_irq`` 发给
  ``env.irq_agent.sequencer``，随后仍调用 ``super.start_vseq``。
* L526-L555：``core_eh2_debug_test`` 覆盖 ``start_vseq``，创建 ``debug_seq``，绑定
  ``env.vseqr.jtag_seqr``，设置 ``stress_mode=1`` 并启动。注释说明这样做是为了避免 vseq body
  立即返回导致 ``join_any`` 在 0 时刻完成。
* L556-L601：``core_eh2_stress_test`` 同时 fork IRQ 和 debug 背景刺激。IRQ 分支从 5 us 后
  高频发送 external IRQ；debug 分支从 50 us 后循环写 halt/resume DMI command，再调用
  ``super.start_vseq`` 启动其它配置项。
* L603-L637：``core_eh2_bitmanip_test`` 只覆盖 ISA 字符串为
  ``rv32imac_zba_zbb_zbc_zbs``；``core_eh2_cosim_test`` 在 build phase 打开
  ``env_cfg.enable_cosim``。两者都是配置型 test，不重写 run phase。
* L639-L715：timer/software interrupt tests 都重写 ``run_phase``：raise objection、load binary，
  fork stimulus、vseq 和 completion，``join_any`` 后 disable fork。差异是 timer test 发送
  ``IRQ_TIMER``，software test 发送 ``IRQ_SOFTWARE``。
* L717-L798：``core_eh2_nmi_test`` 使用 external IRQ ID 1 近似 NMI source；旧
  ``core_eh2_nested_irq_test`` 每轮 repeat 3 个 external IRQ transaction，制造多中断同时
  pending 的压力。
* L800-L881：``core_eh2_debug_stress_test`` 周期性写 halt/resume DMI command；
  ``core_eh2_debug_step_test`` 先 halt，再写 ``DMI_ABSTRACTCS``，随后用 ``DMCONTROL``
  resume-with-step 和 full resume，覆盖 debug single-step 入口。
* L883-L1015：CSR、load/store、mul/div、atomic、dual issue、exception、fetch toggle 是
  轻量配置型 test。它们主要关闭不需要的 random IRQ/debug stress，或打开
  ``enable_fetch_toggle``，让被测二进制本身主导场景。
* L1017-L1057：``core_eh2_pic_test`` 先启动 vseq，再 fork PIC stimulus 和 completion。
  ``run_pic_stimulus`` 重复 20 次发送 external IRQ，ID 限制在 1-31，用于覆盖 PIC priority
  相关窗口。
* L1059-L1171：``core_eh2_mem_error_test`` 打开 ``enable_mem_error``；``core_eh2_random_test``
  只继承 base 行为；``core_eh2_irq_debug_test`` 同时打开 single IRQ 和 single debug；
  ``core_eh2_stall_test`` 打开 fetch toggle 并缩短 interval；long/quick test 只调整 timeout、
  max_cycles 和刺激开关。
* L1173-L1228：PMP basic/disable/random tests 都主要调整 timeout 和 max_cycles；random PMP
  给到 10 秒和 1M cycles，说明该场景预期比 basic/disable 更长。
* L1230-L1305：PC/RF integrity、reset、single-step 这些 class 仍是配置型 wrapper：前几项只拉长
  timeout/cycle，single-step 额外打开 ``enable_debug_single``，让 vseq 注入一次 debug 请求。
* L1307-L1362：ePMP MML、MMWP、RLB tests 只设置 10 秒 timeout 和 500000 cycles。这些 class
  的语义主要来自对应 binary 或 testlist 参数，本 SV class 提供稳定的运行预算。
* L1364-L1444：``core_eh2_debug_wfi_test`` 和 ``core_eh2_debug_csr_test`` 重写 run phase，
  并通过 JTAG halt/resume 在 WFI 或 CSR 访问附近打断。二者结构相同，差异是 CSR 版本的随机
  间隔更短，用来提高命中 CSR read-modify-write 窗口的概率。
* L1446-L1476：``core_eh2_debug_ebreak_test`` 设置较长 timeout 后只 fork ``start_vseq`` 和
  ``wait_for_completion``。EBREAK 是否进入 debug 主要由测试程序和 DCSR 配置决定，SV class
  不额外注入 JTAG stimulus。
* L1478-L1560：``core_eh2_irq_wfi_test`` 在 WFI 可能执行后发送持续较长的 external IRQ；
  ``core_eh2_irq_csr_test`` 以更短随机间隔发送 external IRQ，目标是在 CSR instruction 窗口
  触发 interrupt。
* L1562-L1613：``core_eh2_irq_nest_test`` 设置较长预算，并在每轮随机发送 2-5 个 external IRQ；
  每个 ``send_irq`` 放进 ``fork/join_none``，让多个 transaction 近似并行，制造 nested IRQ
  条件。
* L1615-L1661：``core_eh2_irq_in_debug_test`` 的命名强调 debug mode 内的 interrupt 行为，但
  当前 stimulus 只发送 external IRQ，没有直接写 JTAG halt；debug 入口依赖 vseq 或 binary 侧
  行为。
* L1663-L1711：``core_eh2_debug_in_irq_test`` 先发送 external IRQ，短随机延迟后原本应触发
  debug；当前源码只保留 delay，没有实际 JTAG 写入。这是阅读源码时要识别的实现缺口，不能从
  class 名称推断已有 debug 注入。
* L1713-L1775：``core_eh2_dret_test`` 与 ``core_eh2_debug_ebreakmu_test`` 都设置较长预算，
  run phase 只启动 vseq 并等待 completion；DRET/EBREAKMU 语义来自 test binary 自身。
* L1777-L1815：``core_eh2_single_debug_pulse_test`` fork 一个 ``run_single_debug_pulse``，
  但该 task 只等待并打印 info，注释说 single pulse 由 vseq 处理；因此实际 debug pulse 取决于
  ``env_cfg`` 或 vseq 配置，而非本 task 直接驱动。
* L1817-L1887：``core_eh2_invalid_csr_test`` 只运行 vseq 与 completion，异常语义来自 binary；
  ``core_eh2_fetch_en_chk_test`` fork ``run_fetch_en_stimulus``，该 task 只等待并打印，实际
  fetch-enable toggle 也由 vseq 处理。

接口关系：

* 被调用：``core_eh2_test_pkg.sv`` include 本文件后，UVM factory 根据 ``+UVM_TESTNAME`` 创建
  这些 test class。
* 调用：base test 的 binary loading、vseq start、completion wait，IRQ agent 的
  ``eh2_irq_seq::send_irq``，JTAG agent 的 ``eh2_jtag_seq::send_write``。
* 共享状态：大多数 class 只修改 ``env_cfg``；交互型 class 通过 ``env.irq_agent.sequencer``、
  ``env.jtag_agent.sequencer`` 和 ``env.vseqr`` 向外层 UVM env 注入刺激。
