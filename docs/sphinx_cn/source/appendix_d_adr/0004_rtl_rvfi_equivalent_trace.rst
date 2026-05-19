.. _adr-0004:

ADR-0004: RTL trace 包增加 verification-only rd_addr/rd_wdata 字段
=====================================================================

:status: Proposed（Phase 1 待执行）
:source: docs/adr/0004-rtl-rvfi-equivalent-trace.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

**上下文** ：ADR-0001 的双通道架构在实践中产生了 cosim 闭环不收敛的问题。
scoreboard 膨胀到 1026 行（Ibex 等价仅 361 行），引入了 ``WB_SEARCH_DEPTH``
band-aid 限制启发式搜索，NB-load、DIV cancel、interrupt-killed wb 等异步事件需要
专门的 corner 处理，50 多个调试 build 目录在 build/ 下累积，反映了多次试错。根本
原因是 trace 通道与 wb 通道之间没有可靠的对应关系，只能靠 #0 延迟加 rd 匹配加
搜索窗口启发式来关联。

**决策** ：参考 Ibex ``ibex_top_tracing.sv`` 的实践，在 EH2 RTL 层将
verification-only 信号引出到 trace 包。具体而言，在 ``eh2_trace_pkt_t`` 结构体中
增加 ``trace_rv_i_rd_addr_ip``、``trace_rv_i_rd_wdata_ip``、``trace_rv_i_rd_valid_ip``
三个字段，每个 slot 对应一组。在解码阶段增加 wb1 阶段的 wdata/waddr 寄存器，对齐
现有的 inst_wb1/pc_wb1 流水线。在 ``eh2_veer.sv`` trace 端口列表中解包新字段。
UVM 侧，trace_monitor 直接采样 rd_addr/rd_wdata 填入 trace_seq_item，scoreboard
删除 ``pending_wb_q``、``wb_search_depth`` 和 ``run_cosim_probe`` 主路径，
probe_monitor 仅保留 nb_load / div_cancel 异步通道，预期 scoreboard 从 1026 行
降到约 500 行。

**影响评估** ：功能行为零影响（纯组合复用已有信号加 verification 输出）。时序影响低，
仅新增 4 个 rvdffe 与现有寄存器同负载。综合面积增加约 150 FF，可忽略。对上游兼容性，
trace_pkt 是内部 struct，外部端口可选用 ``RV_DV_VERIFICATION`` 宏包裹。
**正面** ：cosim scoreboard 与 Ibex 同等复杂度，删除 band-aid，平台真正进入工业级，
为 NUM_THREADS=2 cosim 扩展打地基。**负面** ：涉及 RTL 改动，需验证综合时序中性，
需在所有 RTL filelist 同步声明新信号，上游回流时需评估 ``ifdef`` 包裹策略，且存在
"伪 RVFI"风险（信号从 trace + probe 推导，非 design 原生）。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - RVFI 等价 trace 与 wrapper adapter
     - :file:`docs/adr/0004-*`
   * - 代码路径 1
     - :file:`rtl/eh2_veer_wrapper_rvfi.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/env/eh2_rvfi_if.sv`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`
     - 当前仓库实际文件


签核与边界
----------

当前项目选择在仓库内 wrapper 层做 RVFI 适配，不直接改上游 /home/host/Cores-VeeR-EH2 设计 RTL。TB top 实例化 RVFI converter 并把接口交给 RVFI smoke 与后续 formal/trace 检查。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC 仅保留 ``SIMULATOR=nc WAVES=1`` 的单测波形调试用途。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
