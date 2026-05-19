.. _mailbox:
.. _02_core_reference/mailbox:

Mailbox 地址与测试结果判定
================================================================================

:status: draft
:source: dv/uvm/core_eh2/tb/core_eh2_tb_top.sv; dv/uvm/core_eh2/common/core_eh2_tb_intf.sv; dv/uvm/core_eh2/env/core_eh2_env_cfg.sv; dv/uvm/core_eh2/tests/core_eh2_base_test.sv; dv/uvm/core_eh2/tests/core_eh2_test_lib.sv; dv/uvm/core_eh2/tests/core_eh2_report_server.sv; dv/uvm/core_eh2/scripts/check_logs.py; dv/uvm/core_eh2/scripts/run_rtl.py; Makefile; dv/uvm/core_eh2/scripts/metadata.py; dv/uvm/core_eh2/scripts/riscvdv.mk; dv/uvm/core_eh2/scripts/run_instr_gen.py; dv/uvm/core_eh2/scripts/build_instr_gen.py; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv; dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv; dv/uvm/core_eh2/tests/asm/cosim_smoke.S; dv/uvm/core_eh2/tests/asm/cosim_alu.S; dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S; tests/asm/smoke.S; CONTEXT.md; docs/PROJECT_STATUS.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与结论
--------------------------------------------------------------------------------

本章只描述当前仓库中可回溯到源码的 mailbox 行为。EH2 验证平台把
``0xD058_0000`` 用作测试程序与 testbench 之间的结果通道：测试程序向该地址写入
``0xFF`` 表示 PASS，写入 ``0x01`` 表示 FAIL，写入可打印 ASCII 低字节时由
testbench 输出到仿真控制台。所有判定都基于写入数据的低 8 bit，即
``mailbox_data[7:0]``。

该通道同时出现在 4 个层面：

.. code-block:: bash

   assembly test
      |
      v
   store to 0xD0580000
      |
      v
   core_eh2_tb_top: lsu_axi_awvalid && lsu_axi_awready
      |
      |-- 0xff --> mailbox_test_done + mailbox_test_pass + "TEST PASSED"
      |-- 0x01 --> mailbox_test_done + mailbox_test_fail + "TEST FAILED"
      `-- printable byte --> console character
      |
      v
   core_eh2_base_test / check_logs.py / run_rtl.py result classification

**逐段解释** ：

* 汇编测试只需要发起一次 store；testbench 通过 LSU AXI 写地址握手观察写入地址，
  并从 ``lsu_axi_wdata`` 读取数据。
* ``core_eh2_tb_top`` 不在 mailbox 处直接调用 ``$finish``。它设置
  ``mailbox_test_done`` 并触发事件，使 UVM 的 ``report_phase`` 和
  ``final_phase`` 仍然有机会运行。
* ``core_eh2_base_test`` 轮询 ``mailbox_test_done``，并在 mailbox store 之后等待
  10 个 clock，让 monitors 和 scoreboards 收敛 outstanding transaction。
* ``check_logs.py`` 不把 simulator 返回码 0 当作通过；日志中必须出现显式
  ``TEST PASSED`` 或 ``test_passed`` 标记。

**接口关系** ：

* **上游** ：汇编测试、riscv-dv 生成程序和 directed UVM 测试通过同一个
  ``SIGNATURE_ADDR`` / mailbox 地址报告状态。
* **下游** ：``core_eh2_tb_top``、``core_eh2_base_test``、``check_logs.py`` 和
  ``run_rtl.py`` 共同决定仿真结果。
* **共享状态** ：``mailbox_write``、``mailbox_addr``、``mailbox_data``、
  ``mailbox_test_done``、``SIGNATURE_ADDR``、``signature_addr``。

§2  TB top 中的 mailbox 约定
--------------------------------------------------------------------------------

**职责** ：``core_eh2_tb_top`` 在文件头说明 mailbox 约定，并在模块内部声明用于
pass/fail 检测的 wires、events 和完成标志。该约定是本章所有后续行为的根。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L18-L20``）：

.. code-block:: systemverilog

   // Mailbox convention (from VeeR testbench):
   //   Address 0xD0580000: write 0xFF = PASS, 0x01 = FAIL
   //   Other printable chars are console output

**逐段解释** ：

* 第 L18 行：说明该约定来自 VeeR testbench，而不是 UVM 类内部临时定义。
* 第 L19 行：固定地址为 ``0xD0580000``，低字节 ``0xFF`` 表示 PASS，
  ``0x01`` 表示 FAIL。
* 第 L20 行：除 PASS/FAIL 外，其他可打印字符作为控制台输出处理。源码没有为其他
  非可打印值定义动作，因此文档不扩展额外语义。

**接口关系** ：

* **被调用** ：该注释本身不被调用；其约定由同文件后续 mailbox monitor 实现。
* **调用** ：无。
* **共享状态** ：约定约束 ``mailbox_addr`` 和 ``mailbox_data[7:0]`` 的解释方式。

§3  mailbox 信号声明与 LSU AXI 采样
--------------------------------------------------------------------------------

**职责** ：``core_eh2_tb_top`` 从 DUT 的 LSU AXI 写路径抽取 mailbox 观察信号。写事件
由 AW 通道握手给出，地址取自 ``lsu_axi_awaddr``，数据取自 ``lsu_axi_wdata``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L63-L74``）：

.. code-block:: systemverilog

     logic        mailbox_write;
     logic [63:0] mailbox_data;
     logic [31:0] mailbox_addr;
     event mailbox_test_pass;
     event mailbox_test_fail;
     bit   mailbox_test_done = 0;
     string early_bin_path;
     logic  early_bin_loaded = 0;

     assign mailbox_write = lsu_axi_awvalid && lsu_axi_awready;
     assign mailbox_addr  = lsu_axi_awaddr;
     assign mailbox_data  = lsu_axi_wdata;

**逐段解释** ：

* 第 L63-L68 行：声明 mailbox 的写入脉冲、64-bit 数据、32-bit 地址、PASS/FAIL
  事件以及完成标志。``mailbox_test_done`` 初值为 0，只有 PASS 或 FAIL 分支会设置为 1。
* 第 L69-L70 行：``early_bin_path`` 和 ``early_bin_loaded`` 与早期 binary load 相关，
  不参与 mailbox PASS/FAIL 编码。
* 第 L72 行：``mailbox_write`` 只由 ``lsu_axi_awvalid && lsu_axi_awready`` 形成。
  这里的证据只能证明 testbench 用 AW 握手作为 mailbox 写事件，不能推出 W 通道握手同步关系。
* 第 L73-L74 行：地址和数据分别直接连接到 ``lsu_axi_awaddr`` 和 ``lsu_axi_wdata``。
  后续 monitor 对地址使用 32-bit 比较，对结果编码只看 ``mailbox_data[7:0]``。

**接口关系** ：

* **被调用** ：同文件 mailbox monitor、``core_eh2_tb_intf`` 赋值以及 UVM 测试类读取这些信号。
* **调用** ：无函数调用；这是连续赋值。
* **共享状态** ：``mailbox_write``、``mailbox_addr``、``mailbox_data``、
  ``mailbox_test_done``、``mailbox_test_pass``、``mailbox_test_fail``。

§4  ``core_eh2_tb_intf`` 服务接口
--------------------------------------------------------------------------------

**职责** ：``core_eh2_tb_intf`` 把 TB top 中的 mailbox 状态暴露给 UVM 类。UVM package
中的类不需要通过层次化路径访问 ``core_eh2_tb_top``，而是经由 virtual interface
读取 mailbox 和 clocked wait 服务。

**关键代码** （``dv/uvm/core_eh2/common/core_eh2_tb_intf.sv:L4-L18``）：

.. code-block:: systemverilog

   // UVM classes live in packages, so they must not reach into core_eh2_tb_top
   // with hierarchical references.  This interface carries the small set of
   // testbench services that tests need: clocked waits, mailbox status, early
   // binary-load state, and byte backdoor writes to the AXI memory models.

   interface core_eh2_tb_intf (
     input logic clk,
     input logic rst_n
   );

     logic        mailbox_write;
     logic [31:0] mailbox_addr;
     logic [63:0] mailbox_data;
     logic        mailbox_test_done;
     logic        early_bin_loaded;

**逐段解释** ：

* 第 L4-L7 行：源码明确说明接口的目的是避免 UVM 类直接访问 TB top 层次路径，并集中承载
  clocked waits、mailbox status、early binary-load state 和 byte backdoor writes。
* 第 L9-L12 行：接口输入为 ``clk`` 和 ``rst_n``。mailbox 轮询和 ``wait_clks()``
  都依赖这个 clock。
* 第 L14-L18 行：接口保存 mailbox 写入脉冲、地址、数据、完成标志和早期 binary load
  状态；UVM completion 逻辑读取的就是这些字段。

**接口关系** ：

* **被调用** ：``core_eh2_tb_top`` 实例化并赋值；``core_eh2_base_test`` 与
  directed test library 通过 ``tb_vif`` 访问。
* **调用** ：接口本身在该片段中不调用函数。
* **共享状态** ：``mailbox_write``、``mailbox_addr``、``mailbox_data``、
  ``mailbox_test_done``。

§5  TB top 到接口的状态映射
--------------------------------------------------------------------------------

**职责** ：``core_eh2_tb_top`` 把本地 mailbox wires 连到 ``tb_intf``，使 UVM 层可见。
这一步是 RTL-level 检测和 UVM-level completion 之间的桥。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L76-L82``）：

.. code-block:: systemverilog

     core_eh2_tb_intf tb_intf (.clk(core_clk), .rst_n(rst_l));

     assign tb_intf.mailbox_write     = mailbox_write;
     assign tb_intf.mailbox_addr      = mailbox_addr;
     assign tb_intf.mailbox_data      = mailbox_data;
     assign tb_intf.mailbox_test_done = mailbox_test_done;
     assign tb_intf.early_bin_loaded  = early_bin_loaded;

**逐段解释** ：

* 第 L76 行：接口实例使用 ``core_clk`` 和 ``rst_l``，因此 UVM 层看到的 mailbox 状态与
  DUT 主 clock/reset 域对齐。
* 第 L78-L80 行：写脉冲、地址和数据逐项透传。``core_eh2_base_test`` 后续通过
  ``tb_vif`` 读取这些字段。
* 第 L81 行：``mailbox_test_done`` 被透传给 UVM completion polling。该标志由
  TB top monitor 在 PASS/FAIL 分支中设置。
* 第 L82 行：``early_bin_loaded`` 同样透传，但不参与 mailbox 结果编码。

**接口关系** ：

* **被调用** ：UVM config_db 相关逻辑会把 ``tb_intf`` 传给测试环境；本节只记录字段映射。
* **调用** ：无。
* **共享状态** ：``tb_intf.mailbox_*`` 与 TB top 本地 ``mailbox_*`` wires 一一对应。

§6  PASS/FAIL/ASCII monitor
--------------------------------------------------------------------------------

**职责** ：TB top monitor 在 reset 释放后观察 mailbox 地址写入，并根据低 8 bit 设置测试
完成状态、触发 PASS/FAIL event 或输出 ASCII 字符。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L98-L119``）：

.. code-block:: systemverilog

     // Mailbox monitor - pass/fail detection
     // Uses events instead of $finish so UVM report_phase/final_phase run properly
     always @(posedge core_clk) begin
       if (rst_l && mailbox_write && mailbox_addr == 32'hD0580000) begin
         $display("MAILBOX WRITE detected at %0t: data=%08x", $time, mailbox_data);
         if (mailbox_data[7:0] == 8'hFF) begin
           $display("========================================");
           $display("TEST PASSED (mailbox)");
           $display("========================================");
           mailbox_test_done = 1;
           ->mailbox_test_pass;
         end else if (mailbox_data[7:0] == 8'h01) begin
           $display("========================================");
           $display("TEST FAILED (mailbox)");
           $display("========================================");
           mailbox_test_done = 1;
           ->mailbox_test_fail;
         end else if (mailbox_data[7:0] >= 8'h20 && mailbox_data[7:0] < 8'h7F) begin
           // Console output (printable ASCII)
           $write("%c", mailbox_data[7:0]);
         end
       end
     end

**逐段解释** ：

* 第 L98-L99 行：monitor 注释说明这里使用 event 而不是 ``$finish``，目的是让 UVM
  ``report_phase`` / ``final_phase`` 正常执行。
* 第 L100-L102 行：逻辑在 ``core_clk`` 上采样，要求 ``rst_l`` 为 1、``mailbox_write``
  为 1 且地址等于 ``32'hD0580000``。命中后先打印写入时间和数据。
* 第 L103-L108 行：低字节为 ``8'hFF`` 时打印 ``TEST PASSED (mailbox)``，将
  ``mailbox_test_done`` 置 1，并触发 ``mailbox_test_pass``。
* 第 L109-L114 行：低字节为 ``8'h01`` 时打印 ``TEST FAILED (mailbox)``，同样将
  ``mailbox_test_done`` 置 1，并触发 ``mailbox_test_fail``。
* 第 L115-L117 行：低字节在 ``8'h20`` 到 ``8'h7E`` 范围内时按字符输出。
  注意比较条件是 ``< 8'h7F``，因此 ``0x7F`` 不属于可打印分支。
* 第 L118-L119 行：其他值没有分支动作，源码没有赋予这些值 PASS/FAIL 或 console 语义。

**接口关系** ：

* **被调用** ：由 ``core_clk`` 事件驱动。
* **调用** ：调用系统任务 ``$display``、``$write``，并触发 SystemVerilog event。
* **共享状态** ：读 ``rst_l``、``mailbox_write``、``mailbox_addr``、
  ``mailbox_data``；写 ``mailbox_test_done``；触发 ``mailbox_test_pass`` /
  ``mailbox_test_fail``。

§7  结果编码与 riscv-dv status 编码的区别
--------------------------------------------------------------------------------

**职责** ：``core_eh2_base_test`` 同时保存 mailbox/signature 地址和 riscv-dv 风格的
core status code。文档必须区分直接 mailbox PASS/FAIL 字节和 status helper 使用的状态值。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L45-L62``）：

.. code-block:: systemverilog

     // Signature address for riscv-dv handshake
     parameter bit [31:0] SIGNATURE_ADDR = 32'hD058_0000;
     parameter bit [31:0] BOOT_ADDR      = 32'h8000_0000;

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

**逐段解释** ：

* 第 L45-L47 行：``SIGNATURE_ADDR`` 与 mailbox 地址相同，均为 ``32'hD058_0000``；
  ``BOOT_ADDR`` 为 ``32'h8000_0000``。
* 第 L49-L62 行：riscv-dv 风格 status code 把 ``TEST_PASS`` 定义为 2，
  ``TEST_FAIL`` 定义为 3。这些 code 被 helper 用于比较 signature 写入数据。
* 直接 mailbox 结束判定不是用 ``TEST_PASS=2`` 或 ``TEST_FAIL=3``；TB top monitor 的
  直接 PASS/FAIL 字节是 ``8'hFF`` 和 ``8'h01``。
* 因此，文档中需要把“mailbox 低字节 PASS/FAIL”与“riscv-dv core status code”分开说明，
  不能把 ``0xFF`` 写成 ``TEST_PASS`` localparam 的数值。

**接口关系** ：

* **被调用** ：``check_next_core_status()``、``wait_for_core_status()`` 和
  ``wait_for_csr_write()`` 使用 ``SIGNATURE_ADDR``。
* **调用** ：无。
* **共享状态** ：``SIGNATURE_ADDR``、``BOOT_ADDR``、各 status localparam。

§8  ``wait_for_completion()`` 四路完成竞争
--------------------------------------------------------------------------------

**职责** ：``core_eh2_base_test`` 通过 ``fork`` / ``join_any`` 同时等待 mailbox
signature、wall-clock timeout、cycle timeout 和 double-fault detector。任意一路返回后关闭其他分支。

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
         end

         // Way 3: Cycle count timeout
         begin
           tb_vif.wait_clks(env_cfg.max_cycles);
           `uvm_error(test_name, $sformatf("Cycle timeout: %0d cycles", env_cfg.max_cycles))
         end

         // Way 4: Double-fault detector
         begin
           if (env_cfg.enable_double_fault_detector)
             detect_double_fault();
           else
             wait (0);  // Block forever if disabled
         end
       join_any
       disable fork;
     endtask

**逐段解释** ：

* 第 L347-L355 行：第一路由 ``env_cfg.use_signature`` 控制，默认配置中该字段为 1。
  若关闭，则用 ``wait (0)`` 永久阻塞，避免该分支误结束。
* 第 L357-L361 行：第二路等待 ``env_cfg.timeout_ns``，到期后报
  ``Wall-clock timeout`` UVM error。
* 第 L363-L367 行：第三路调用 ``tb_vif.wait_clks(env_cfg.max_cycles)``，到达 cycle
  上限后报 ``Cycle timeout`` UVM error。
* 第 L369-L375 行：第四路只在 ``enable_double_fault_detector`` 打开时调用
  ``detect_double_fault()``，否则同样永久阻塞。
* 第 L376-L377 行：``join_any`` 表示任一路结束即继续；``disable fork`` 关闭剩余等待分支。

**接口关系** ：

* **被调用** ：base test run flow 在等待测试完成时调用该 task。
* **调用** ：调用 ``wait_for_signature()``、``tb_vif.wait_clks()``、
  ``detect_double_fault()`` 和 UVM error 宏。
* **共享状态** ：``env_cfg.use_signature``、``env_cfg.timeout_ns``、
  ``env_cfg.max_cycles``、``env_cfg.enable_double_fault_detector``、``tb_vif``。

§9  ``wait_for_signature()`` 轮询完成标志
--------------------------------------------------------------------------------

**职责** ：``wait_for_signature()`` 不直接等待 SystemVerilog event，而是在 clock 边沿轮询
``tb_vif.mailbox_test_done``。该方式避免 event triggered-state 带来的时序问题。

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
           end
           // EH2 can retire the mailbox store before the external AXI write
           // response is observed. Leave a short drain window so monitors and
           // scoreboards can close outstanding transactions before report_phase.
           tb_vif.wait_clks(10);
           return;
         end
       end
     endtask

**逐段解释** ：

* 第 L380-L382 行：注释说明该 task 观察 ``SIGNATURE_ADDR`` 写入，并通过轮询
  ``mailbox_test_done`` 避免直接等待 event 的 triggered-state 问题。
* 第 L383-L385 行：task 永久循环，每个 ``tb_vif.clk`` 上升沿检查一次完成标志。
* 第 L386-L391 行：完成标志置位后再次读取低字节。``8'hFF`` 打印 UVM info：
  ``TEST PASSED (signature)``；其他完成值走 UVM error：``TEST FAILED (signature)``。
* 第 L392-L395 行：源码说明 EH2 可能在外部 AXI write response 被观察到之前 retire
  mailbox store，因此等待 10 个 clock，给 monitors 和 scoreboards 关闭 outstanding
  transactions 的窗口。
* 第 L396-L399 行：drain window 结束后返回，completion fork 的 signature 分支结束。

**接口关系** ：

* **被调用** ：``wait_for_completion()`` 的 signature 分支调用。
* **调用** ：调用 UVM info/error 宏和 ``tb_vif.wait_clks(10)``。
* **共享状态** ：读 ``tb_vif.mailbox_test_done``、``tb_vif.mailbox_data``、
  ``tb_vif.clk``。

§10  signature transaction helper
--------------------------------------------------------------------------------

**职责** ：base test 的 signature helper 从 ``tb_vif`` 捕获下一次 mailbox 写入，并把
地址、低 32 bit 数据和写标志返回给调用者。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L420-L429``）：

.. code-block:: systemverilog

     // Wait for a write to the signature address
     // Monitors the mailbox events from TB top
     virtual task wait_for_mem_txn(output bit [31:0] addr, output bit [31:0] data,
                                    output bit is_write);
       // Wait for a mailbox write event
       @(posedge tb_vif.mailbox_write);
       addr    = tb_vif.mailbox_addr;
       data    = tb_vif.mailbox_data[31:0];
       is_write = 1;
     endtask

**逐段解释** ：

* 第 L420-L422 行：注释说明 helper 等待 signature 地址写入，来源是 TB top 暴露的
  mailbox event 状态。
* 第 L422-L423 行：task 输出 ``addr``、``data`` 和 ``is_write``。数据输出只有
  32 bit，来自 64-bit ``tb_vif.mailbox_data`` 的低 32 bit。
* 第 L425 行：等待 ``tb_vif.mailbox_write`` 的上升沿。该信号来自 TB top 的
  ``lsu_axi_awvalid && lsu_axi_awready``。
* 第 L426-L428 行：采样地址、数据并把 ``is_write`` 固定置 1。源码没有提供读事务分支。

**接口关系** ：

* **被调用** ：``check_next_core_status()``、``wait_for_core_status()``、
  ``wait_for_csr_write()`` 以及 directed test 的 setup helper。
* **调用** ：无子 task 调用；等待 virtual interface 信号。
* **共享状态** ：``tb_vif.mailbox_write``、``tb_vif.mailbox_addr``、
  ``tb_vif.mailbox_data``。

§11  status 与 CSR helper
--------------------------------------------------------------------------------

**职责** ：base test 使用同一个 signature transaction helper 实现 status 比较、等待指定
status 和 CSR 写入检测。这些 helper 不改变 TB top 的 PASS/FAIL 规则，只消费相同的
``SIGNATURE_ADDR`` 写流。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L431-L465``）：

.. code-block:: systemverilog

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
         end
       end
     endtask

     // Wait for specific core status
     virtual task wait_for_core_status(input int status);
       bit [31:0] addr, data;
       bit is_write;
       forever begin
         wait_for_mem_txn(addr, data, is_write);
         if (is_write && addr == SIGNATURE_ADDR && data[7:0] == status[7:0])
           return;
       end
     endtask

**逐段解释** ：

* 第 L431-L443 行：``check_next_core_status()`` 读取下一次 mailbox 写入；如果地址等于
  ``SIGNATURE_ADDR``，就把 ``data[7:0]`` 与 ``expected_status[7:0]`` 比较，不匹配时报
  UVM error。
* 第 L445-L454 行：``wait_for_core_status()`` 循环等待，直到看到写事务、地址等于
  ``SIGNATURE_ADDR`` 且低字节等于目标 status。
* 本片段没有包含 ``wait_for_csr_write()`` 的完整代码，是为了保持单个代码片段不超过
  30 行；下一片段单独解释 CSR 判定。

**接口关系** ：

* **被调用** ：directed UVM tests 可调用这些 helper 校验初始化、运行态和结束态。
* **调用** ：二者都调用 ``wait_for_mem_txn()``；错误路径调用 UVM error 宏。
* **共享状态** ：``SIGNATURE_ADDR``、``test_name``、``tb_vif.mailbox_*``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_base_test.sv:L456-L465``）：

.. code-block:: systemverilog

     // Wait for CSR write verification
     virtual task wait_for_csr_write(input int csr_addr);
       bit [31:0] addr, data;
       bit is_write;
       forever begin
         wait_for_mem_txn(addr, data, is_write);
         if (is_write && addr == SIGNATURE_ADDR && data[31:20] == csr_addr[11:0])
           return;
       end
     endtask

**逐段解释** ：

* 第 L456-L458 行：task 输入为目标 CSR 地址，并声明下一次 signature transaction 的地址、
  数据和写标志。
* 第 L459-L463 行：循环读取 mailbox 写事务，只有在地址为 ``SIGNATURE_ADDR`` 且
  ``data[31:20]`` 等于 ``csr_addr[11:0]`` 时返回。
* 该 helper 使用数据高位编码 CSR 地址；这与 TB top 直接用低字节判定 PASS/FAIL 是两条不同消费路径。

**接口关系** ：

* **被调用** ：directed debug/CSR 测试可以等待目标 CSR 写入。
* **调用** ：调用 ``wait_for_mem_txn()``。
* **共享状态** ：``SIGNATURE_ADDR``、``tb_vif.mailbox_*``。

§12  directed test 的 setup 与 done 轮询
--------------------------------------------------------------------------------

**职责** ：``core_eh2_test_lib.sv`` 中的 directed test 基类把 mailbox/signature 写入作为
core 初始化和测试完成的同步点。它先等第一笔 signature 写入，再运行子类 stimulus，最后轮询
``mailbox_test_done``。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L87-L117``）：

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

           // Wait for test completion signal
           wait_test_done();

           // Let sequences wind down before disabling
           if (vseq != null) vseq.stop();
           tb_vif.wait_clks(100);
           disable fork;

           // Drop any remaining objection
           // (objection management is handled by the caller / run_phase)
         end
       join_none
     endtask

**逐段解释** ：

* 第 L87-L92 行：``send_stimulus()`` 启动 background virtual sequence，给环境提供 ambient
  stimulus。
* 第 L93-L98 行：第二个分支先调用 ``wait_for_core_setup()``，等待第一笔 signature 写入；
  然后等待 50 个 clock，让 core 进入 ``<main>``。
* 第 L100-L103 行：用 ``join_none`` 启动子类覆盖的 ``check_stimulus()``，使 directed
  检查与后续完成等待并行。
* 第 L105-L110 行：``wait_test_done()`` 返回后停止 ``vseq``，再等待 100 个 clock 给序列收尾。
* 第 L111-L117 行：``disable fork`` 结束剩余并行分支；objection 管理由调用侧处理。

**接口关系** ：

* **被调用** ：directed test run flow 调用。
* **调用** ：调用 ``vseq.start()``、``wait_for_core_setup()``、``tb_vif.wait_clks()``、
  ``check_stimulus()``、``wait_test_done()``、``vseq.stop()``。
* **共享状态** ：``vseq``、``env.vseqr``、``tb_vif``、mailbox/signature 写流。

§13  ``wait_for_core_setup()`` 与 ``wait_test_done()``
--------------------------------------------------------------------------------

**职责** ：directed test 基类把“第一笔 signature 写入”作为 core setup 完成信号，并把
``mailbox_test_done`` 作为测试完成信号。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L130-L149``）：

.. code-block:: systemverilog

     // Wait for the core to write its initialization info to the signature
     // address, indicating it is ready to execute <main>.
     virtual task wait_for_core_setup();
       bit [31:0] addr, data;
       bit is_write;
       `uvm_info(test_name, "Waiting for core initialization (signature write)", UVM_LOW)
       wait_for_mem_txn(addr, data, is_write);
       `uvm_info(test_name, "Core initialization detected", UVM_LOW)
     endtask

     // Poll the mailbox_test_done flag set by the test program.
     virtual task wait_test_done();
       forever begin
         @(posedge tb_vif.clk);
         if (tb_vif.mailbox_test_done) begin
           `uvm_info(test_name, "Test done detected (mailbox)", UVM_LOW)
           return;
         end
       end
     endtask

**逐段解释** ：

* 第 L130-L138 行：``wait_for_core_setup()`` 调用 ``wait_for_mem_txn()`` 等待下一笔
  signature/mailbox 写入，然后打印 core initialization detected。该片段不检查地址和 status。
* 第 L140-L149 行：``wait_test_done()`` 每个 ``tb_vif.clk`` 上升沿检查
  ``tb_vif.mailbox_test_done``，置位后打印 ``Test done detected (mailbox)`` 并返回。
* 这两个 task 都依赖 base helper 暴露的 mailbox 状态，但关注点不同：setup 等第一笔写入，
  done 等 TB top monitor 的完成标志。

**接口关系** ：

* **被调用** ：``send_stimulus()`` 调用二者。
* **调用** ：``wait_for_core_setup()`` 调用 ``wait_for_mem_txn()``；``wait_test_done()``
  只等待 clock 和完成标志。
* **共享状态** ：``tb_vif.mailbox_write``、``tb_vif.mailbox_test_done``、``test_name``。

§14  directed debug helper 的最后 signature 数据
--------------------------------------------------------------------------------

**职责** ：directed test library 还提供读取最近 signature 数据和覆盖 CSR wait helper 的逻辑。
这条路径用于 DCSR/CSR 检查，仍然消费同一个 mailbox 数据源。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_test_lib.sv:L473-L488``）：

.. code-block:: systemverilog

     virtual function bit [31:0] get_last_signature_data();
       return tb_vif.mailbox_data[31:0];
     endfunction

     // Override wait_for_csr_write to also cache the data for check_dcsr_*()
     virtual task wait_for_csr_write(input int csr_addr);
       bit [31:0] addr, data;
       bit is_write;
       forever begin
         wait_for_mem_txn(addr, data, is_write);
         if (is_write && addr == SIGNATURE_ADDR && data[31:20] == csr_addr[11:0]) begin
           dcsr_data = data;
           return;
         end
       end
     endtask

**逐段解释** ：

* 第 L473-L475 行：``get_last_signature_data()`` 直接返回 ``tb_vif.mailbox_data[31:0]``，
  即最近一次由接口暴露的 mailbox 数据低 32 bit。
* 第 L477-L488 行：覆盖版 ``wait_for_csr_write()`` 延续 base class 的 CSR 地址判定，
  并在命中时把整笔 ``data`` 缓存到 ``dcsr_data``，供后续 ``check_dcsr_*()`` 类检查使用。
* 该片段没有改变 PASS/FAIL 判定；它扩展的是 directed debug 检查中对 signature 数据的消费。

**接口关系** ：

* **被调用** ：directed debug 检查逻辑可调用。
* **调用** ：覆盖版 task 调用 ``wait_for_mem_txn()``。
* **共享状态** ：``tb_vif.mailbox_data``、``SIGNATURE_ADDR``、``dcsr_data``。

§15  timeout 配置与 TB top 兜底超时
--------------------------------------------------------------------------------

**职责** ：环境配置给 UVM completion 提供 wall-clock timeout 和 cycle timeout；TB top 还有
一个固定 30 分钟的兜底 ``$finish``。两者不是同一段代码。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L78-L82``）：

.. code-block:: systemverilog

     longint timeout_ns            = 64'd1_800_000_000_000;  // Wall-clock timeout (ns) - 30 minutes
     int max_cycles                = 100_000;     // Cycle count timeout
     bit use_signature             = 1;  // Use signature-based completion
     bit [31:0] signature_addr     = 32'hD058_0000;  // Mailbox/signature address
     bit [31:0] boot_addr          = 32'h8000_0000;  // Boot address

**逐段解释** ：

* 第 L78 行：默认 wall-clock timeout 为 ``64'd1_800_000_000_000`` ns，注释标明 30 分钟。
* 第 L79 行：默认 cycle timeout 为 ``100_000``。
* 第 L80 行：``use_signature`` 默认为 1，因此 ``wait_for_completion()`` 默认启用
  mailbox/signature 分支。
* 第 L81-L82 行：默认 signature 地址为 ``32'hD058_0000``，boot 地址为
  ``32'h8000_0000``。

**接口关系** ：

* **被调用** ：``core_eh2_base_test`` 的 completion flow 读取这些字段。
* **调用** ：无。
* **共享状态** ：``timeout_ns``、``max_cycles``、``use_signature``、``signature_addr``。

**关键代码** （``dv/uvm/core_eh2/env/core_eh2_env_cfg.sv:L118-L123``）：

.. code-block:: systemverilog

     void'($value$plusargs("timeout_ns=%d", timeout_ns));
     void'($value$plusargs("max_cycles=%d", max_cycles));
     void'($value$plusargs("bin=%s", binary));
     void'($value$plusargs("bin_cosim=%s", cosim_binary));
     void'($value$plusargs("boot_addr=%h", boot_addr));
     void'($value$plusargs("irq_delay_min=%d", irq_delay_min));

**逐段解释** ：

* 第 L118-L119 行：``+timeout_ns`` 和 ``+max_cycles`` 可覆盖默认 timeout。
* 第 L120-L122 行：binary、cosim binary 和 boot address 也通过 plusarg 读入；本片段没有
  读取 ``signature_addr`` 的 plusarg。
* 第 L123 行：后续 IRQ delay plusarg 与 mailbox 本身无关，只是同一个构造函数里的配置读取。

**接口关系** ：

* **被调用** ：``core_eh2_env_cfg.new()`` 构造时执行。
* **调用** ：SystemVerilog ``$value$plusargs``。
* **共享状态** ：``timeout_ns``、``max_cycles``、``binary``、``cosim_binary``、
  ``boot_addr``。

**关键代码** （``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv:L566-L575``）：

.. code-block:: systemverilog

     //--------------------------------------------------------------------------
     // Safety Timeout (UVM handles timeouts via the test - this is a last resort)
     //--------------------------------------------------------------------------
     initial begin
       #(64'd1_800_000_000_000);  // 30 minutes safety timeout (matches env_cfg.timeout_ns)
       $display("========================================");
       $display("SAFETY TIMEOUT (TB top) - 30 minutes");
       $display("========================================");
       $finish;
     end

**逐段解释** ：

* 第 L566-L568 行：注释说明 UVM test 负责正常 timeout；TB top 这段是 last resort。
* 第 L569-L570 行：initial block 等待 ``64'd1_800_000_000_000`` time unit，注释与
  ``env_cfg.timeout_ns`` 的 30 分钟默认值一致。
* 第 L571-L574 行：超时后打印 safety timeout banner 并调用 ``$finish``。

**接口关系** ：

* **被调用** ：仿真启动后 initial block 自动执行。
* **调用** ：``$display`` 和 ``$finish``。
* **共享状态** ：无 mailbox 信号写入；只提供兜底结束路径。

§16  UVM report server 与日志 PASS/FAIL 文本
--------------------------------------------------------------------------------

**职责** ：``core_eh2_report_server`` 在 UVM 汇总阶段根据 error/fatal 数量打印整体
PASS/FAIL 文本。该文本会被日志检查脚本识别，但 failure 优先级仍由 ``check_logs.py`` 决定。

**关键代码** （``dv/uvm/core_eh2/tests/core_eh2_report_server.sv:L13-L23``）：

.. code-block:: systemverilog

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

**逐段解释** ：

* 第 L13-L17 行：report server 在 summarize 阶段读取 UVM error 和 fatal 计数，并相加。
* 第 L18-L22 行：error/fatal 合计为 0 时打印 ``EH2 UVM TEST PASSED``，否则打印
  ``EH2 UVM TEST FAILED``。
* 第 L23 行：最后调用父类 ``super.report_summarize(file)``，保留标准 UVM summary。

**接口关系** ：

* **被调用** ：``core_eh2_base_test.new()`` 安装该 report server 后，由 UVM report flow 调用。
* **调用** ：``get_severity_count()``、``$display``、``super.report_summarize()``。
* **共享状态** ：UVM report server 的 severity counters。

§17  ``check_logs.py`` 日志扫描入口
--------------------------------------------------------------------------------

**职责** ：``check_logs.py`` 扫描仿真日志，识别 UVM error/fatal、mailbox pass/fail 文本、
tool crash 和 timeout。它返回统一的 ``passed`` 与 ``failure_mode``。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L58-L78``）：

.. code-block:: python

   def check_uvm_log(log_path: str, fail_on_warnings: bool = False,
                     sim_returncode: int = None) -> tuple:
       """
       Check UVM simulation log for errors.

       Returns:
           (passed: bool, failure_mode: str, num_errors: int, num_warnings: int)
       """
       if not os.path.exists(log_path):
           return (False, "FILE_ERROR", 0, 0)

       num_errors = 0
       num_warnings = 0
       summary_errors = None
       summary_warnings = None
       has_fatal = False
       has_test_pass = False
       has_test_fail = False
       has_tool_crash = False
       has_tool_timeout = False

**逐段解释** ：

* 第 L58-L65 行：函数输入包括 log path、warning 策略和 simulator return code；返回元组包含
  pass/fail、failure mode、error 数和 warning 数。
* 第 L66-L67 行：日志文件不存在时立即返回 ``FILE_ERROR``。
* 第 L69-L78 行：初始化 error/warning 计数、summary 计数和若干布尔标志，其中
  ``has_test_pass`` / ``has_test_fail`` 对应 mailbox 或 report server 打印出的文本。

**接口关系** ：

* **被调用** ：``check_sim_log()`` 和 ``run_rtl.py`` 的仿真结果解析路径使用该函数。
* **调用** ：``os.path.exists``；后续片段会打开日志文件。
* **共享状态** ：本地计数器和 pass/fail 标志。

§18  PASS/FAIL 文本识别
--------------------------------------------------------------------------------

**职责** ：日志扫描逐行识别工具 crash、timeout、UVM severity、``TEST PASSED`` 和
``TEST FAILED`` 文本。TB top 的 mailbox banner 和 UVM report server 的 summary 都会落入这些匹配规则。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L79-L117``）：

.. code-block:: python

       with open(log_path, "r", errors="replace") as f:
           for line in f:
               if TOOL_CRASH_RE.search(line):
                   has_tool_crash = True
               if TOOL_TIMEOUT_RE.search(line):
                   has_tool_timeout = True

               summary_match = UVM_SUMMARY_RE.match(line)
               if summary_match:
                   count = int(summary_match.group(2))
                   if count == 0:
                       continue
                   severity = summary_match.group(1)
                   if severity == "UVM_WARNING":
                       summary_warnings = (summary_warnings or 0) + count
                       continue
                   summary_errors = (summary_errors or 0) + count
                   if severity == "UVM_FATAL":
                       has_fatal = True
                   continue

               # Skip summary lines whose count was overwritten by tool banner
               # text (still summary lines, not real fatals/errors/warnings).
               if UVM_SUMMARY_LINE_RE.match(line):
                   continue

               if line.startswith("UVM_FATAL") or " UVM_FATAL " in line:

**逐段解释** ：

* 第 L79-L84 行：打开日志后逐行扫描，先设置 crash 和 timeout 标志。
* 第 L86-L98 行：如果命中 UVM summary 行，则按 summary count 更新 warning/error/fatal 状态。
  count 为 0 的 summary 行直接跳过。
* 第 L100-L103 行：跳过被工具 banner 覆盖的 summary 行，避免把 summary 误判为真实 UVM error。
* 第 L105 行：开始识别真实 ``UVM_FATAL`` 行；后续片段继续展示 error、warning 和 PASS/FAIL 文本。

**接口关系** ：

* **被调用** ：``check_uvm_log()`` 内部主循环。
* **调用** ：正则 ``search`` / ``match``。
* **共享状态** ：``has_tool_crash``、``has_tool_timeout``、``summary_errors``、
  ``summary_warnings``、``has_fatal``。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L105-L117``）：

.. code-block:: python

               if line.startswith("UVM_FATAL") or " UVM_FATAL " in line:
                   has_fatal = True
                   num_errors += 1
               elif line.startswith("UVM_ERROR") or " UVM_ERROR " in line:
                   num_errors += 1
               elif "UVM_WARNING" in line or TOOL_WARNING_RE.search(line):
                   num_warnings += 1
               elif "TEST PASSED" in line or "test_passed" in line:
                   has_test_pass = True
               elif ("TEST FAILED" in line or "test_failed" in line or
                     "EH2 UVM TEST FAILED" in line or
                     "RISC-V UVM TEST FAILED" in line):
                   has_test_fail = True

**逐段解释** ：

* 第 L105-L110 行：真实 ``UVM_FATAL`` 和 ``UVM_ERROR`` 会增加 error 计数；
  ``UVM_FATAL`` 同时设置 ``has_fatal``。
* 第 L110-L111 行：``UVM_WARNING`` 或工具 warning 正则会增加 warning 计数。
* 第 L112-L113 行：包含 ``TEST PASSED`` 或 ``test_passed`` 的行设置
  ``has_test_pass``。TB top 的 ``TEST PASSED (mailbox)`` 和 base test 的
  ``TEST PASSED (signature)`` 都满足这个条件。
* 第 L114-L117 行：包含 ``TEST FAILED``、``test_failed``、``EH2 UVM TEST FAILED``
  或 ``RISC-V UVM TEST FAILED`` 的行设置 ``has_test_fail``。

**接口关系** ：

* **被调用** ：``check_uvm_log()`` 主循环。
* **调用** ：字符串匹配和 ``TOOL_WARNING_RE.search``。
* **共享状态** ：``has_fatal``、``num_errors``、``num_warnings``、``has_test_pass``、
  ``has_test_fail``。

§19  ``check_logs.py`` failure mode 优先级
--------------------------------------------------------------------------------

**职责** ：日志扫描完成后，``check_logs.py`` 按固定优先级给出最终结果。显式 PASS 只有在没有更高优先级失败条件时才返回通过。

**关键代码** （``dv/uvm/core_eh2/scripts/check_logs.py:L119-L144``）：

.. code-block:: python

       if summary_errors is not None:
           num_errors = summary_errors
       if summary_warnings is not None:
           num_warnings = summary_warnings

       # Simulator crashes must take priority over a missing pass signature. This
       # keeps infrastructure failures visible in sign-off summaries.
       if has_tool_crash:
           return (False, "SIM_CRASH", num_errors, num_warnings)
       if has_tool_timeout:
           return (False, "SIM_TIMEOUT", num_errors, num_warnings)
       if has_fatal:
           return (False, "UVM_FATAL", num_errors, num_warnings)
       if has_test_fail:
           return (False, "TEST_FAIL", num_errors, num_warnings)
       if num_errors > 0:
           return (False, "UVM_ERROR", num_errors, num_warnings)
       if sim_returncode not in (None, 0):
           return (False, "SIM_ERROR", num_errors, num_warnings)
       if fail_on_warnings and num_warnings > 0:
           return (False, "TOOL_WARNING", num_errors, num_warnings)
       if has_test_pass:
           return (True, "NONE", num_errors, num_warnings)

       # EH2 tests must explicitly report pass via mailbox/signature text.
       return (False, "NO_PASS_SIGNATURE", num_errors, num_warnings)

**逐段解释** ：

* 第 L119-L122 行：如果日志里有 UVM summary 计数，summary 计数覆盖逐行累计值。
* 第 L124-L133 行：tool crash、tool timeout、UVM fatal 和显式 test fail 的优先级高于
  其他结果。
* 第 L134-L139 行：UVM error、非零 simulator return code、以及可配置的 warning failure
  都会返回失败。
* 第 L140-L141 行：只有在前面所有失败条件都未命中时，``has_test_pass`` 才返回
  ``(True, "NONE", ...)``。
* 第 L143-L144 行：没有显式 PASS 文本时返回 ``NO_PASS_SIGNATURE``。这条规则保证单纯
  simulator 退出码 0 不能证明测试通过。

**接口关系** ：

* **被调用** ：``check_uvm_log()`` 末尾。
* **调用** ：无外部调用。
* **共享状态** ：``summary_errors``、``summary_warnings``、``has_tool_crash``、
  ``has_tool_timeout``、``has_fatal``、``has_test_fail``、``num_errors``、
  ``sim_returncode``、``fail_on_warnings``、``has_test_pass``。

§20  ``run_rtl.py`` 强制显式 pass marker
--------------------------------------------------------------------------------

**职责** ：``run_rtl.py`` 在 simulator 结束后调用日志检查器，并把检查结果写入
``TestRunResult``。源码注释明确说明 simulator 返回码 0 不足以判定 PASS。

**关键代码** （``dv/uvm/core_eh2/scripts/run_rtl.py:L151-L174``）：

.. code-block:: python

       # Simulate
       try:
           sim_cmd = build_sim_cmd(md, sim_cfg)
       except ValueError as err:
           trr.failure_mode = "CONFIG_ERROR"
           with open(trr.sim_log_path, "w") as log_f:
               log_f.write(f"ERROR: {err}\n")
           return trr
       trr.sim_cmd = sim_cmd
       rc = run_command(sim_cmd, trr.sim_log_path, timeout=600)
       trr.sim_returncode = rc

       # Parse results. A zero simulator return code is not sufficient for pass:
       # the test must emit an explicit mailbox/signature pass marker.
       checked = check_sim_log(trr.sim_log_path, trr.trace_path,
                               sim_returncode=rc)
       trr.passed = checked.passed
       trr.failure_mode = checked.failure_mode
       trr.num_instructions = checked.num_instructions
       trr.num_cycles = checked.num_cycles
       trr.ipc = checked.ipc
       trr.uvm_errors = checked.uvm_errors
       trr.uvm_warnings = checked.uvm_warnings

**逐段解释** ：

* 第 L151-L159 行：先构建 sim command；配置错误会写入 sim log 并返回
  ``CONFIG_ERROR``。
* 第 L160-L161 行：执行仿真命令，timeout 参数为 600，并保存 simulator return code。
* 第 L163-L166 行：注释直接给出规则：返回码 0 不足以通过，测试必须发出显式
  mailbox/signature pass marker；随后调用 ``check_sim_log()``。
* 第 L167-L174 行：把日志检查器返回的 pass/failure mode、instruction/cycle/IPC 和
  UVM error/warning 计数写入 ``TestRunResult``。

**接口关系** ：

* **被调用** ：RTL run flow 调用。
* **调用** ：``build_sim_cmd()``、``run_command()``、``check_sim_log()``。
* **共享状态** ：``trr``、``md``、``sim_cfg``、sim log、trace log。

§21  顶层 Makefile 与 metadata 的地址入口
--------------------------------------------------------------------------------

**职责** ：顶层 ``Makefile`` 给 ``SIGNATURE_ADDR`` 提供默认值，并把它传给
``metadata.py``。metadata 再保存到 test run 描述中，供后续脚本使用。

**关键代码** （``Makefile:L40-L62``）：

.. code-block:: makefile

   RTL_TEST    ?= core_eh2_base_test
   SIM_OPTS    ?=
   GEN_OPTS    ?=
   ISS         ?= spike
   VERBOSE     ?= 0
   SIGNATURE_ADDR ?= d0580000
   OUT ?= out
   OUT-DIR := $(dir $(OUT)/)
   METADATA-DIR := $(OUT-DIR)metadata

   export PYTHONPATH := $(shell cd dv/uvm/core_eh2 && python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

   .PHONY: run
   run:
   	+@env PYTHONPATH=$(PYTHONPATH) python3 dv/uvm/core_eh2/scripts/metadata.py \
   	  --op "create_metadata" \
   	  --dir-metadata $(METADATA-DIR) \
   	  --dir-out $(OUT-DIR) \
   	  --args-list "\
   	  SEED=$(SEED) WAVES=$(WAVES) COV=$(COV) SIMULATOR=$(SIMULATOR) \
   	  ISS=$(ISS) TEST=$(TEST) VERBOSE=$(VERBOSE) ITERATIONS=$(ITERATIONS) \
   	  SIGNATURE_ADDR=$(SIGNATURE_ADDR) CONFIG=$(CONFIG) RTL_TEST=$(RTL_TEST) \
   	  SIM_OPTS=$(SIM_OPTS) GEN_OPTS=$(GEN_OPTS)"

**逐段解释** ：

* 第 L40-L46 行：``SIGNATURE_ADDR`` 默认值为 ``d0580000``，与 TB top 的
  ``32'hD0580000`` 地址一致，只是没有下划线和 ``0x`` 前缀。
* 第 L47-L50 行：定义 out/metadata 目录和 ``PYTHONPATH``。
* 第 L52-L62 行：``run`` target 调用 ``metadata.py --op create_metadata``，并在
  ``--args-list`` 中传入 ``SIGNATURE_ADDR=$(SIGNATURE_ADDR)``。

**接口关系** ：

* **被调用** ：用户或 CI 通过 ``make run`` 触发。
* **调用** ：调用 ``dv/uvm/core_eh2/scripts/metadata.py``。
* **共享状态** ：``SIGNATURE_ADDR``、``METADATA-DIR``、``OUT-DIR``、``SIM_OPTS``、
  ``GEN_OPTS``。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L25-L32``）：

.. code-block:: python

       # Test configuration
       test_name: str = ""
       test_type: str = "RISCVDV"
       seed: int = 0
       iterations: Optional[int] = 1
       binary_path: str = ""
       rtl_test: str = "core_eh2_base_test"
       signature_addr: str = "d0580000"

**逐段解释** ：

* 第 L25-L32 行：``TestMetadata`` 的默认 ``signature_addr`` 同样是 ``d0580000``。
* 该默认值与 ``Makefile`` 的默认值一致；如果 Makefile 没有覆盖，metadata 仍有同一地址。

**接口关系** ：

* **被调用** ：metadata create/load flow 构造 metadata 对象。
* **调用** ：无。
* **共享状态** ：``signature_addr`` 字段。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L396-L403``）：

.. code-block:: python

       md.iterations = (int(args.get("ITERATIONS", 1))
                        if args.get("ITERATIONS", "") not in ("", None)
                        else None)
       md.waves = _str_to_bool(args.get("WAVES", "0"))
       md.coverage = _str_to_bool(args.get("COV", "0"))
       md.verbose = _str_to_bool(args.get("VERBOSE", "0"))
       md.iss = args.get("ISS", "spike") or "spike"
       md.signature_addr = args.get("SIGNATURE_ADDR", md.signature_addr)
       md.eh2_config = args.get("CONFIG", args.get("EH2_CONFIG", "default"))

**逐段解释** ：

* 第 L396-L401 行：metadata 从参数字典读入 iterations、waves、coverage、verbose 和 ISS。
* 第 L402 行：``SIGNATURE_ADDR`` 参数存在时覆盖 ``md.signature_addr``，否则保留默认值。
* 第 L403 行：EH2 config 从 ``CONFIG`` 或 ``EH2_CONFIG`` 读入，与 mailbox 地址无直接耦合。

**接口关系** ：

* **被调用** ：``create_metadata`` 参数处理流程调用。
* **调用** ：``_str_to_bool()``。
* **共享状态** ：``args``、``md.signature_addr``。

§22  riscv-dv instruction generator 的 signature 地址
--------------------------------------------------------------------------------

**职责** ：riscv-dv 生成路径把 EH2 的 signature 地址传给 generator。构建 generator 与运行
generator 的脚本都把地址固定为 ``d0580000`` / ``0D058000``。

**关键代码** （``dv/uvm/core_eh2/scripts/riscvdv.mk:L15-L18``）：

.. code-block:: makefile

   INSTR-GEN-BUILD-STAMP = $(METADATA-DIR)/instr.gen.build.stamp
   instr_gen_build: $(METADATA-DIR)/instr.gen.build.stamp
   instr-gen-build-var-deps := SIMULATOR SIGNATURE_ADDR

**逐段解释** ：

* 第 L15-L16 行：instruction generator build 通过 stamp 文件建模。
* 第 L17 行：``instr-gen-build-var-deps`` 包含 ``SIMULATOR`` 和 ``SIGNATURE_ADDR``，
  表示 generator build 的变量依赖中包含 signature 地址。

**接口关系** ：

* **被调用** ：``wrapper.mk`` include 后，``instr_gen_build`` target 使用该依赖。
* **调用** ：make 变量依赖 helper。
* **共享状态** ：``SIGNATURE_ADDR``、``METADATA-DIR``。

**关键代码** （``dv/uvm/core_eh2/scripts/run_instr_gen.py:L25-L35``）：

.. code-block:: python

   EH2_SIGNATURE_ADDR = "d0580000"


   def build_sim_opts() -> str:
       """Build riscv-dv generator simulator plusargs for EH2 customizations."""
       return " ".join([
           "+uvm_set_inst_override=riscv_asm_program_gen,"
           "eh2_asm_program_gen,uvm_test_top.asm_gen",
           "+require_signature_addr=1",
           f"+signature_addr={EH2_SIGNATURE_ADDR}",
       ])

**逐段解释** ：

* 第 L25 行：脚本常量 ``EH2_SIGNATURE_ADDR`` 为 ``d0580000``。
* 第 L28-L35 行：``build_sim_opts()`` 构造给 generator simulator 的 plusargs：
  instance override、``+require_signature_addr=1`` 和 ``+signature_addr=d0580000``。
* 该函数生成的是 riscv-dv generator 的仿真选项，不是 DUT RTL 仿真的 mailbox monitor。

**接口关系** ：

* **被调用** ：``run_instr_gen.py`` 后续构造 generator 命令时调用。
* **调用** ：字符串拼接和 ``join``。
* **共享状态** ：``EH2_SIGNATURE_ADDR``。

**关键代码** （``dv/uvm/core_eh2/scripts/build_instr_gen.py:L40-L48``）：

.. code-block:: python

       cmd = riscvdv_interface.get_run_cmd(
           test='riscv_arithmetic_basic_test',
           seed=0,
           isa='rv32imac_zba_zbb_zbc_zbs',
           output_dir=str(gen_dir),
       )
       # Append compile-only flags
       cmd.extend(['--co', '--simulator', md.simulator, '--end_signature_addr', '0D058000'])
       cmd = format_to_cmd(cmd)

**逐段解释** ：

* 第 L40-L45 行：构造 riscv-dv generator 的 run command，使用固定 test、seed、ISA 和输出目录。
* 第 L46-L48 行：追加 compile-only 选项、simulator 名称和
  ``--end_signature_addr 0D058000``，然后格式化为命令字符串。
* 这里的 ``0D058000`` 与 ``0xD0580000`` 是同一地址的无前缀十六进制表示。

**接口关系** ：

* **被调用** ：instruction generator build flow 调用。
* **调用** ：``riscvdv_interface.get_run_cmd()``、``cmd.extend()``、``format_to_cmd()``。
* **共享状态** ：``md.simulator``、``gen_dir``。

§23  cosim 配置中的 mailbox 内存区
--------------------------------------------------------------------------------

**职责** ：cosim 配置把 mailbox 地址作为 Spike 可访问内存区之一注册。源码能证明的是内存区
base/size 和 ``riscv_cosim_add_memory`` 调用；本章不声称 mailbox store 在 Spike 端具有
未在源码中出现的 side-effect 语义。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv:L59-L65``）：

.. code-block:: systemverilog

     bit [31:0] dccm_base = 32'hF004_0000;
     bit [31:0] dccm_size = 32'h0001_0000;
     bit [31:0] iccm_base = 32'hEE00_0000;
     bit [31:0] iccm_size = 32'h0001_0000;
     mem_region_t mem_pic       = '{base: 32'hF00C_0000, size: 32'h0000_8000};
     mem_region_t mem_mailbox   = '{base: 32'hD058_0000, size: 32'h0000_1000};
     mem_region_t mem_nmi_vec   = '{base: 32'h1111_0000, size: 32'h0000_1000};

**逐段解释** ：

* 第 L59-L62 行：配置保存 DCCM/ICCM 的 base 和 size。
* 第 L63 行：PIC 内存区 base 为 ``32'hF00C_0000``，size 为 ``32'h0000_8000``。
* 第 L64 行：mailbox 内存区 base 为 ``32'hD058_0000``，size 为 ``32'h0000_1000``。
* 第 L65 行：NMI vector 内存区 base 为 ``32'h1111_0000``，size 为 ``32'h0000_1000``。

**接口关系** ：

* **被调用** ：cosim scoreboard 初始化时读取 ``cfg.mem_mailbox``。
* **调用** ：无。
* **共享状态** ：``mem_mailbox.base``、``mem_mailbox.size``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L136-L144``）：

.. code-block:: systemverilog

       if (cfg != null) begin
         if (cosim_config == "") cosim_config = cfg.isa_string;
         fatal_on_mismatch = cfg.relax_cosim_check ? 0 : 1;
         // Memory region overrides (issue 65): plusargs override cfg defaults
         void'($value$plusargs("MEM_BOOT_BASE=%h",     cfg.mem_boot.base));
         void'($value$plusargs("MEM_ICCM_BASE=%h",     cfg.mem_iccm.base));
         void'($value$plusargs("MEM_DCCM_BASE=%h",     cfg.mem_dccm.base));
         void'($value$plusargs("MEM_MAILBOX_BASE=%h",  cfg.mem_mailbox.base));
       end

**逐段解释** ：

* 第 L136-L138 行：当 ``cfg`` 非空时，scoreboard 从配置中补齐 ISA string，并根据
  ``relax_cosim_check`` 设置 mismatch 是否 fatal。
* 第 L139-L143 行：内存区 base 支持 plusarg override，其中 ``MEM_MAILBOX_BASE`` 可覆盖
  ``cfg.mem_mailbox.base``。
* 第 L144 行：override 只在 ``cfg != null`` 分支执行。

**接口关系** ：

* **被调用** ：cosim scoreboard build/config 阶段执行该逻辑。
* **调用** ：``$value$plusargs``。
* **共享状态** ：``cfg.mem_mailbox.base``、``cosim_config``、``fatal_on_mismatch``。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L729-L739``）：

.. code-block:: systemverilog

         // Register all DUT-accessible memory regions with Spike (from cfg — issue 65).
         if (cfg != null) begin
           riscv_cosim_add_memory(cosim_handle, cfg.mem_boot.base,      cfg.mem_boot.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_debug_sb.base,  cfg.mem_debug_sb.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data1.base, cfg.mem_ext_data1.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_ext_data2.base, cfg.mem_ext_data2.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_iccm.base,      cfg.mem_iccm.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_dccm.base,      cfg.mem_dccm.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_pic.base,       cfg.mem_pic.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_mailbox.base,   cfg.mem_mailbox.size);
           riscv_cosim_add_memory(cosim_handle, cfg.mem_nmi_vec.base,   cfg.mem_nmi_vec.size);

**逐段解释** ：

* 第 L729-L730 行：注释说明所有 DUT-accessible memory regions 从 ``cfg`` 注册到 Spike。
* 第 L731-L737 行：boot、debug system bus、外部数据区、ICCM、DCCM 和 PIC 逐项注册。
* 第 L738 行：mailbox 区域通过 ``riscv_cosim_add_memory(cosim_handle,
  cfg.mem_mailbox.base, cfg.mem_mailbox.size)`` 注册。
* 第 L739 行：NMI vector 区域继续注册。mailbox 只是注册列表中的一项，源码片段没有给出额外
  side-effect 行为。

**接口关系** ：

* **被调用** ：cosim 初始化成功后执行。
* **调用** ：``riscv_cosim_add_memory`` DPI/C++ 接口。
* **共享状态** ：``cosim_handle``、``cfg.mem_mailbox`` 和其他 memory region 配置。

**关键代码** （``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L740-L747``）：

.. code-block:: systemverilog

         end else begin
           riscv_cosim_add_memory(cosim_handle, 32'h8000_0000, 32'h0400_0000);
           riscv_cosim_add_memory(cosim_handle, 32'hA058_0000, 32'h0400_0000);
           riscv_cosim_add_memory(cosim_handle, 32'hB000_0000, 32'h0400_0000);
           riscv_cosim_add_memory(cosim_handle, 32'hC058_0000, 32'h0400_0000);
           riscv_cosim_add_memory(cosim_handle, 32'hF00C_0000, 32'h0000_8000);
           riscv_cosim_add_memory(cosim_handle, 32'hD058_0000, 32'h0000_1000);
           riscv_cosim_add_memory(cosim_handle, 32'h1111_0000, 32'h0000_1000);

**逐段解释** ：

* 第 L740 行：当 ``cfg`` 为空时进入 fallback 分支。
* 第 L741-L746 行：fallback 以常量地址注册多个 memory region，其中第 L746 行为
  ``32'hD058_0000``、``32'h0000_1000`` 的 mailbox region。
* 第 L747 行：最后注册 NMI vector region。该 fallback 也只证明内存区注册事实。

**接口关系** ：

* **被调用** ：cosim 初始化中 ``cfg == null`` 的 fallback 路径。
* **调用** ：``riscv_cosim_add_memory``。
* **共享状态** ：``cosim_handle``。

§24  汇编 smoke 测试中的直接 PASS 写入
--------------------------------------------------------------------------------

**职责** ：最小 smoke 测试通过一条 store 向 mailbox 写入 ``0xFF``。该用例验证 fetch、
decode、execute 和 store pipeline 至少能到达 mailbox。

**关键代码** （``dv/uvm/core_eh2/tests/asm/cosim_smoke.S:L10-L17``）：

.. code-block:: bash

   _start:
       // Write 0xFF to mailbox (0xD0580000) = PASS
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)

       // Loop forever (halt via debug or timeout)
   1:  j       1b

**逐段解释** ：

* 第 L10 行：入口标签为 ``_start``。
* 第 L11-L14 行：加载 mailbox 地址 ``0xD0580000`` 到 ``t0``，加载 ``0xFF`` 到 ``t1``，
  然后执行 ``sw t1, 0(t0)``。
* 第 L16-L17 行：写入后进入永久循环。测试结束依赖 testbench 看到 mailbox PASS，而不是程序返回。

**接口关系** ：

* **被调用** ：RTL/cosim 仿真加载该汇编编译出的 binary。
* **调用** ：执行 RISC-V 指令 ``li``、``sw``、``j``。
* **共享状态** ：外部可观察状态为 ``0xD0580000`` 地址写入低字节 ``0xFF``。

§25  汇编 PASS/FAIL 双分支示例
--------------------------------------------------------------------------------

**职责** ：``cosim_alu.S`` 展示典型 directed 汇编结构：检查通过跳到 ``pass`` 写
``0xFF``，检查失败跳到 ``fail`` 写 ``0x01``。

**关键代码** （``dv/uvm/core_eh2/tests/asm/cosim_alu.S:L67-L82``）：

.. code-block:: bash

   pass:
       // Write PASS to mailbox
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)
       j       done

   fail:
       // Write FAIL to mailbox
       li      t0, 0xD0580000
       li      t1, 0x01
       sw      t1, 0(t0)

   done:
       // Loop forever
   1:  j       1b

**逐段解释** ：

* 第 L67-L72 行：``pass`` 分支向 ``0xD0580000`` 写入 ``0xFF``，然后跳到 ``done``。
* 第 L74-L78 行：``fail`` 分支向同一地址写入 ``0x01``。TB top 看到该低字节会触发
  ``mailbox_test_fail``。
* 第 L80-L82 行：``done`` 进入永久循环，等待 testbench 根据 mailbox 写入结束仿真流程。

**接口关系** ：

* **被调用** ：汇编检查分支跳转到 ``pass`` 或 ``fail``。
* **调用** ：执行 RISC-V ``li``、``sw``、``j`` 指令。
* **共享状态** ：``0xD0580000`` 的低字节写入。

§26  directed NB-load 汇编的 mailbox 结果
--------------------------------------------------------------------------------

**职责** ：``directed_nb_load_chain.S`` 也使用同一 mailbox 结果协议，证明 directed
汇编测试与 cosim smoke 使用同一判定通道。

**关键代码** （``dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S:L47-L58``）：

.. code-block:: bash

   pass:
       li      t0, 0xD0580000
       li      t1, 0xFF
       sw      t1, 0(t0)
       j       done

   fail:
       li      t0, 0xD0580000
       li      t1, 0x01
       sw      t1, 0(t0)

   done:

**逐段解释** ：

* 第 L47-L51 行：PASS 分支写 ``0xFF`` 到 mailbox 后跳到 ``done``。
* 第 L53-L56 行：FAIL 分支写 ``0x01`` 到 mailbox。
* 第 L58 行：``done`` 标签承接结果写入后的控制流。

**接口关系** ：

* **被调用** ：前面的 NB-load chain 检查根据比较结果进入 ``pass`` 或 ``fail``。
* **调用** ：执行 RISC-V ``li``、``sw``、``j`` 指令。
* **共享状态** ：mailbox 地址 ``0xD0580000`` 的结果写入。

§27  顶层 ``tests/asm`` smoke 示例
--------------------------------------------------------------------------------

**职责** ：仓库顶层 ``tests/asm/smoke.S`` 使用 byte store 写 PASS。它与 UVM asm 目录下的
测试一样依赖低 8 bit 结果编码。

**关键代码** （``tests/asm/smoke.S:L8-L15``）：

.. code-block:: bash

   _start:
       // Load mailbox address
       lui   a0, 0xD0580      // a0 = 0xD0580000
       // Write 0xFF (PASS) to mailbox
       li    a1, 0xFF
       sb    a1, 0(a0)
       // Loop forever
   1:  j     1b

**逐段解释** ：

* 第 L8-L10 行：入口 ``_start`` 后用 ``lui a0, 0xD0580`` 形成 ``0xD0580000`` 地址。
* 第 L11-L13 行：加载 ``0xFF`` 并用 ``sb`` 写入一个字节。TB top 使用
  ``mailbox_data[7:0]``，因此 byte store 的低字节仍然是 PASS 编码。
* 第 L14-L15 行：写入后进入永久循环。

**接口关系** ：

* **被调用** ：顶层 ASM smoke flow 编译/运行该文件。
* **调用** ：执行 RISC-V ``lui``、``li``、``sb``、``j`` 指令。
* **共享状态** ：mailbox 地址低字节 ``0xFF``。

§28  术语与 release 记录中的 mailbox
--------------------------------------------------------------------------------

**职责** ：项目上下文和 release note 对 mailbox 有简短记录。它们用于确认术语和当前 release
smoke 路径，不替代源码级实现解释。

**关键代码** （``CONTEXT.md:L33-L36``）：

.. code-block:: bash

   | **mailbox** | 0xD058_0000 地址。0xFF=PASS, 0x01=FAIL，其它字符=控制台输出 |
   | **mailbox FAIL / pass** | TB top 监听 0xD058_0000 写入决定测试通过 |

**逐段解释** ：

* 第 L33 行：术语表把 mailbox 定义为 ``0xD058_0000`` 地址，并记录
  ``0xFF=PASS``、``0x01=FAIL`` 和其他字符输出。
* 第 L36 行：术语表说明 TB top 监听该地址写入决定测试通过。

**接口关系** ：

* **被调用** ：文档术语约束使用。
* **调用** ：无。
* **共享状态** ：术语定义与 TB top monitor 保持一致。

**关键代码** （``docs/PROJECT_STATUS.md`` 摘要）：

.. code-block:: bash

   | smoke | PASS | 1 | 1 | RTL-only mailbox smoke path |

**逐段解释** ：

* 当前 project status 记录 ``smoke`` 为 PASS，run 数和 pass 数均为 1，
  备注为 ``RTL-only mailbox smoke path``。
* 该行只证明 status 中存在 smoke mailbox 路径记录；具体 pass/fail 判定仍以
  TB top 和日志检查脚本为准。

**接口关系** ：

* **被调用** ：release 说明引用。
* **调用** ：无。
* **共享状态** ：release note 中的 smoke 状态。

§29  常见误读边界
--------------------------------------------------------------------------------

**职责** ：把源码没有证明的内容从文档结论中排除，避免 mailbox 章节产生 ground truth 漂移。

**关键边界** ：

* ``mailbox_write`` 来自 AW 通道握手，数据来自 ``lsu_axi_wdata``。源码没有在该段中证明
  W 通道握手与 AW 同周期，因此文档只描述 testbench 的采样方式。
* TB top 直接 PASS/FAIL 编码是 ``8'hFF`` 和 ``8'h01``；riscv-dv status localparam 中
  ``TEST_PASS=2``、``TEST_FAIL=3`` 是 helper 消费的状态编码，不能替代直接 mailbox 编码。
* cosim 源码证明 mailbox 被注册为 Spike 可访问 memory region；本章不写“side-effect 不比对”
  这类未在所引源码片段中出现的结论。
* ``core_eh2_env_cfg.sv`` 读取 ``+timeout_ns`` 和 ``+max_cycles``，但本章所引片段没有读取
  ``+signature_addr``。顶层 ``Makefile`` 和 metadata 维护 ``SIGNATURE_ADDR`` 字段，riscv-dv
  generator 脚本也固定传入 ``d0580000``。
* PASS 文本只是必要条件之一。``check_logs.py`` 中 crash、timeout、UVM fatal、显式 FAIL、
  UVM error 和非零 simulator return code 都高于 ``has_test_pass``。

§30  参考资料
--------------------------------------------------------------------------------

**关联 ADR** ：

* 无。本章引用的 mailbox 行为均来自源码、项目上下文和 release note；已检查
  :ref:`adr-0016` 与 :ref:`adr-0017`，其中没有直接 mailbox 行为定义。

**关联章节** ：

* :doc:`/02_core_reference/bus_axi_ahb`：mailbox 写入由 LSU AXI 写路径暴露。
* :doc:`/05_verification_arch/cosim_scoreboard`：cosim scoreboard 的整体数据流。
* :doc:`/06_flows/scripts_reference`：脚本入口与日志检查流程。
* :doc:`/appendix_b_uvm/tests`：UVM test class 字典。
* :doc:`/appendix_b_uvm/cosim_agent`：cosim agent 与 scoreboard 字典。

**源文件绝对路径** ：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/core_eh2_tb_intf.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/env/core_eh2_env_cfg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_base_test.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_test_lib.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/core_eh2_report_server.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/check_logs.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py`
* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/riscvdv.mk`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_instr_gen.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/build_instr_gen.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_cfg.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_smoke.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/cosim_alu.S`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/tests/asm/directed_nb_load_chain.S`
* :file:`/home/host/eh2-veri/tests/asm/smoke.S`
* :file:`/home/host/eh2-veri/CONTEXT.md`
* :file:`/home/host/eh2-veri/docs/PROJECT_STATUS.md`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
