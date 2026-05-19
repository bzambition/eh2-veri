:orphan:

Cosim Scoreboard
==========================================================================================

``eh2_cosim_scoreboard`` 是 EH2 UVM 平台最核心的检查器。它把 RTL retire
trace、DUT probe 异步事件、LSU AXI4 内存事务合并为 Spike 可消费的
指令流，并逐条执行 ``riscv_cosim_step`` 。当前实现位于
``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`` ，共 769 行。

输入通道
------------------------------------------------------------------------------------------

scoreboard 有三组 TLM FIFO：

.. list-table::
   :header-rows: 1
   :widths: 28 28 44

   * - FIFO
     - 来源
     - 内容
   * - ``trace_fifo``
     - ``eh2_trace_monitor.ap``
     - 每条 retired instruction 的 PC、insn、slot、exception、
       interrupt、wb_valid、rd、rd_data。
   * - ``dut_probe_fifo``
     - ``eh2_dut_probe_monitor.ap``
     - NB-load、DIV completion / cancel 等异步写回 hint。
   * - ``lsu_axi_fifo``
     - ``lsu_agent.ap``
     - LSU AXI4 read/write 事务，用于内存访问通知。

ADR-0004 之后，普通寄存器写回由 trace item 自带，probe FIFO 不再用于
regular writeback 对齐。这是 scoreboard 从 1026 行降到 769 行的主要原因。

主循环
------------------------------------------------------------------------------------------

``run_phase`` 在 cosim enabled 时启动四个并行任务：

.. code-block:: text

   init_cosim()
   fork
     run_cosim_trace()
     run_cosim_probe_async()
     run_cosim_dmem()
     run_reset_monitor()
   join

处理策略是 **trace 保序，必要时等待外部证据** ：

* trace item 到达后先进 ``pending_trace_q`` 。
* store / AMO 等待匹配 LSU AXI 写事务。
* load 不等待 AXI 读事务；EH2 DCCM hit、forwarding、内部访问可能没有
  外部 AXI。load 通过 NB-load async hint 获得写回。
* DIV 等待 DIV async hint；cancel hint 可抑制写回。
* 满足条件后弹出队首 trace item，调用 ``compare_instruction`` 。

Spike 初始化
------------------------------------------------------------------------------------------

``init_cosim`` 会销毁旧 handle、创建新 handle、注册内存区和 EH2 自定义 CSR：

* ``riscv_cosim_init(cosim_config)`` 创建 Spike processor。
* ``riscv_cosim_add_memory`` 注册 boot、debug SB、ICCM、DCCM、PIC、
  mailbox、NMI vector 等区域。
* ``eh2_cosim_csr_preregister.svh`` 静态注册 28 个 EH2 vendor CSR。
* 如果 test 已设置 ``pending_bin_path`` ，scoreboard 在初始化后加载 binary。

reset monitor 在 ``rst_n`` 下降沿 flush FIFO / queue，在复位释放后重新
``init_cosim`` 并重载 binary。

指令比对
------------------------------------------------------------------------------------------

``compare_instruction`` 的步骤：

1. interrupt-only item（``interrupt=1 && exception=0`` ）只通知 Spike
   ``debug_req`` / ``nmi`` / ``mip`` / ``mcycle`` ，不执行 ``step`` 。
2. 从 trace item 取 ``wb_valid``、``wb_dest``、``wb_data`` 。
3. 如果匹配到 NB-load 或 DIV async hint，用 hint 覆盖或抑制写回。
4. 设置 Spike sideband：debug、NMI、MIP、mcycle、iside error。
5. 调用 ``riscv_cosim_step(handle, rd, rd_data, pc, sync_trap, suppress)`` 。
6. 返回 0 表示 mismatch；按 ``fatal_on_mismatch`` 报 ``UVM_FATAL`` 或
   ``UVM_ERROR`` 。

通知顺序沿用 Ibex 模式：

.. code-block:: text

   set_debug_req
   set_nmi
   set_nmi_int
   set_mip
   set_mcycle
   step

内存访问处理
------------------------------------------------------------------------------------------

LSU AXI4 是 64-bit，而 Spike dside notification 是 32-bit 粒度。因此
scoreboard 对每个 AXI beat：

* 低 32-bit ``WSTRB[3:0]`` 有效时通知一次。
* 高 32-bit ``WSTRB[7:4]`` 有效时以 ``addr+4`` 再通知一次。
* read beat 大于 4 字节时同样拆成低 / 高两次，并标记 widened load。

EH2 store buffer 可能合并 store。scoreboard 用 ``store_axi_delivered`` 与
``store_trace_stepped`` 统计已观察 AXI store 与已 step store trace。若
trace 数超过 AXI 数，认为当前 store 被合并，允许继续前进；C++ 侧
``check_mem_access`` 负责处理空 pending 的语义。

异步写回
------------------------------------------------------------------------------------------

EH2 有两类关键异步写回：

* **NB-load** ：load retire 之后写回，trace packet 普通 wb 字段可能无效。
  scoreboard 按 rd 匹配 ``EH2_WB_SRC_NB_LOAD`` hint。
* **DIV** ：除法完成或 cancel 走异步路径。scoreboard 按 DIV hint FIFO
  顺序消费，并在 rd 不一致时报警。

``async_wb_q`` 只保存 ``rd``、``rd_data``、``suppress``、``source`` 。
regular writeback hint 会被直接丢弃，因为 trace packet 已经自包含。

配置开关
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 30 20 50

   * - plusarg / cfg
     - 默认
     - 说明
   * - ``+enable_cosim``
     - 1
     - 启动 scoreboard 主循环。
   * - ``+disable_cosim``
     - 0
     - 在 env_cfg 层关闭 cosim agent。
   * - ``+cosim_config=<str>``
     - test 生成
     - Spike 初始化字符串，包含 ISA、PC、mtvec、PMP 等。
   * - ``+cosim_fatal_on_mismatch=1``
     - cfg 决定
     - mismatch 立即 fatal，sign-off 推荐打开。

报告字段
------------------------------------------------------------------------------------------

report phase 输出：

* trace / probe / AXI item 计数。
* pending trace / memory / async hint 队列长度。
* trace backlog high watermark。
* ``Steps executed`` 与 ``Mismatches`` 。
* Spike 已匹配指令数。
* ``RESULT: PASS`` 或 ``RESULT: FAIL`` 。

一个健康 cosim 用例应满足 ``Mismatches: 0`` 且 ``Steps executed > 0`` 。
部分 EH2 时序 corner 允许结束时仍有 pending trace / memory item，但必须
伴随 0 mismatch，并在 log 中有 NOTE 解释。

已知边界
------------------------------------------------------------------------------------------

当前 cosim 签发范围是单线程 ``NUM_THREADS=1`` 。以下场景仍通过
``cosim:disabled`` 或 issue 追踪隔离：

* ``NUM_THREADS=2`` 多 hart cosim。
* debug / interrupt 嵌套下的完整 trap-frame 比对。
* atomic SC.W 与 Spike 默认语义差异。
* bitmanip illegal-instruction 路径的 step 节拍差异。

这些边界不会阻止 full profile 通过，但属于后续 sign-off 扩展项。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
