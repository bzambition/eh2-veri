Testbench 顶层
==============

``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`` 是 UVM 平台与 EH2 RTL 的连接点。
该文件当前 1071 行，职责集中在 **例化 DUT、搭建行为级外设、导出验证接口、
监听 mailbox、启动 UVM**，不承载测试场景逻辑。

顶层职责
--------

TB top 的主要工作如下：

* 生成 ``clk`` / ``rst_l``，并提供 30 分钟级安全超时。
* 例化 ``eh2_veer_wrapper``，把 ``rtl/design`` 下的 EH2 接入仿真。
* 例化 IFU / LSU / SB / DMA 四组 AXI4 通道的行为级存储模型或 tie-off。
* 暴露 ``core_eh2_tb_intf`` 给 UVM base_test，用于 mailbox 与时钟等待。
* 暴露 ``eh2_trace_intf``、``eh2_dut_probe_if``、``eh2_csr_if``、
  ``eh2_instr_monitor_if`` 给 monitor / scoreboard。
* 通过 ``uvm_config_db`` 将 virtual interface 注入 UVM 层。

mailbox 协议
------------

TB top 监听 LSU AXI 写地址 ``0xD058_0000``：

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - 写入数据低 8 位
     - 含义
   * - ``0xFF``
     - 测试 PASS，触发 ``mailbox_test_pass``。
   * - ``0x01``
     - 测试 FAIL，触发 ``mailbox_test_fail``。
   * - ``0x20`` 到 ``0x7E``
     - 作为 ASCII 字符输出，便于裸机程序打印诊断信息。

UVM base_test 不直接看软件内部状态，而是等待 ``core_eh2_tb_intf`` 上的
``mailbox_test_done``。这使 directed 汇编、riscv-dv 随机测试、cosim
证明测试共享同一结束协议。

DUT 与地址空间
--------------

默认 reset vector 为 ``0x8000_0000``，cosim scoreboard 同步注册以下
内存区域到 Spike：

.. list-table::
   :header-rows: 1
   :widths: 24 18 58

   * - 地址
     - 大小
     - 用途
   * - ``0x8000_0000``
     - 64 MiB
     - boot / main memory。
   * - ``0xA058_0000``
     - 64 MiB
     - Debug system bus memory。
   * - ``0xB000_0000``
     - 64 MiB
     - External data region 1。
   * - ``0xC058_0000``
     - 64 MiB
     - External data region。
   * - ``0xEE00_0000``
     - 64 KiB
     - ICCM。
   * - ``0xF004_0000``
     - 64 KiB
     - DCCM。
   * - ``0xF00C_0000``
     - 32 KiB
     - PIC。
   * - ``0xD058_0000``
     - 4 KiB
     - mailbox / signature。
   * - ``0x1111_0000``
     - 4 KiB
     - NMI vector。

AXI4 端口
---------

EH2 在当前 AXI4 配置下有四类 master 端口：

.. list-table::
   :header-rows: 1
   :widths: 16 18 66

   * - 端口
     - TB 策略
     - 说明
   * - IFU
     - 行为级 slave + passive monitor
     - 取指流量，主要用于代码访问观察。
   * - LSU
     - 行为级 slave + passive monitor + cosim dmem port
     - load/store 访问，scoreboard 从这里获得内存通知。
   * - SB
     - 行为级 slave + passive monitor
     - 调试 System Bus 通道。
   * - DMA
     - 当前无外部 DMA master，输入 tie-off
     - 保留端口完整性；后续 active driver 可扩展。

AXI4 agent 当前只做 passive monitoring，错误响应和时序扰动不由 agent
主动注入。该决策见 ADR-0002。

验证接口
--------

TB top 通过 interface 将 DUT 内部状态整理给 UVM：

* ``eh2_trace_intf``：retired instruction trace，包含 PC、insn、
  exception、interrupt、slot、wb_valid、rd、rd_data 等 RVFI 等价字段。
* ``eh2_dut_probe_if``：reset、mcycle、mip、debug/nmi、NB-load、
  DIV async hint 等 probe 状态。
* ``eh2_csr_if``：CSR 访问监控入口。
* ``eh2_instr_monitor_if``：指令监控补充入口。
* ``core_eh2_tb_intf``：mailbox、时钟等待、test_done 等 test 服务。

``core_eh2_dut_signals.svh`` 把复杂 hierarchical reference 集中在一个
include 文件内，降低 TB top 主体的噪声，也让 RTL hierarchy 变动时有一个
明确修补点。

配置数据库注入
--------------

TB top 在 initial block 中把 virtual interface 写入 ``uvm_config_db``。
UVM env / agent 在 build 或 connect 阶段取回：

.. code-block:: text

   tb_top
     ├─ set("*", "tb_vif", core_eh2_tb_intf)
     ├─ set("*trace_monitor*", "vif", eh2_trace_intf)
     ├─ set("*dut_probe_monitor*", "vif", eh2_dut_probe_if)
     ├─ set("*cosim_agt*", "probe_vif", eh2_dut_probe_if)
     └─ set("*irq_agent*", "vif", eh2_irq_intf)

这种方式保持 RTL 连接在 TB top，测试场景通过 UVM 对象层配置，不需要在
每个 test 中硬编码 hierarchy。

维护边界
--------

TB top 应避免承载测试策略。以下内容应放在更合适的位置：

* 新的随机激励：放到 ``tests/core_eh2_seq_lib.sv`` 或 agent sequence。
* 新的检查器：优先放到 env scoreboard / cosim scoreboard。
* 新的覆盖点：放到 ``fcov/``，通过 bind 或 interface 接入。
* 新的 directed 汇编：放到 ``tests/asm`` 或 ``directed_tests`` testlist。

