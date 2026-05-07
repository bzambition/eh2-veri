覆盖率计划
==========

本章给出 EH2 UVM 平台的覆盖率闭环计划。当前 sign-off full profile 已经
验证功能流程 PASS，但 coverage 仍处于 ``SKIP`` 状态；因此本章既记录已
实现的 coverage infrastructure，也定义后续纳入 gate 的建议路径。

覆盖目标
--------

覆盖目标按风险排序：

.. list-table::
   :header-rows: 1
   :widths: 24 34 42

   * - 目标域
     - 覆盖对象
     - 证据来源
   * - 基础 ISA
     - RV32I/M/A/C 指令类别、寄存器写回、load/store、branch/jump。
     - riscv-dv arithmetic/load_store/mul_div/amo/random。
   * - 双发射
     - i0/i1 类别组合、压缩/非压缩组合、stall / flush 交叉。
     - ``dual_issue_cg``、``cosim_dual_issue.S``。
   * - 中断 / NMI
     - timer、software、external、NMI、debug 中断交叉。
     - IRQ tests、``interrupt_cg``。
   * - Debug
     - JTAG halt/resume、single step、debug CSR、WFI/debug 组合。
     - debug test 类、JTAG agent log。
   * - CSR / WARL
     - 标准 CSR、EH2 vendor CSR、非法 CSR、WARL 字段。
     - ``csr_warl_cg``、CSR directed stream。
   * - PMP / ePMP
     - region mode、权限、lock、MML/MMWP/RLB、访问错误。
     - ``eh2_pmp_fcov_if.sv``、PMP test 类。
   * - 异步写回
     - NB-load、DIV completion / cancel、store buffer coalescing。
     - cosim scoreboard counters 与 directed tests。

测试映射
--------

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 测试
     - 主要覆盖
   * - ``riscv_arithmetic_basic_test``
     - ALU、寄存器写回、基础 retire。
   * - ``riscv_load_store_test``
     - LSU、BE、NB-load、DCCM/外部访问。
   * - ``riscv_mul_div_test``
     - M 扩展、DIV async、long latency。
   * - ``riscv_dual_issue_test``
     - i0/i1 program order、双发射组合。
   * - ``riscv_exception_test``
     - illegal、ebreak、unaligned 相关 trap。
   * - ``riscv_interrupt_*``
     - IRQ/NMI 与 pipeline/debug 组合。
   * - ``riscv_debug_*``
     - JTAG debug、single step、dret、debug CSR。
   * - ``riscv_pmp_*`` / ``riscv_epmp_*``
     - PMP/ePMP region、permission、mseccfg。

收敛指标
--------

建议 gate 分阶段打开：

1. **阶段 A：可解析性**。``--require-coverage`` 打开，要求报告存在且能解析。
2. **阶段 B：代码覆盖率基线**。line / condition / FSM / toggle 设置保守门限。
3. **阶段 C：functional coverage 基线**。对 ``eh2_fcov_if`` 主 covergroup
   建立历史基线，不要求一次达到 100%。
4. **阶段 D：waiver review**。所有未覆盖 bin 要么补测试，要么有 active waiver。
5. **阶段 E：full gate**。coverage 与 functional evidence 成为 full profile
   的硬门限。

waiver 准则
-----------

接受 waiver 需要满足至少一条：

* RTL 架构禁止该组合出现。
* 该组合只在未签发配置中可达，例如 dual_thread 当前不在 cosim 范围。
* 该组合由其它等价证据覆盖，重复测试收益很低。
* 工具链无法生成对应指令，但已有 hand-written asm 或人工分析证明。

waiver 必须写入 ``fcov/cov_waivers``，并在评审中确认 ``reason`` 不是
"暂时没时间写测试"。

与风险登记的关系
----------------

覆盖率空洞若对应已知功能风险，应在 :doc:`risk_register` 中保留风险条目。
例如：

* RISK-9：中断 / 异常 cosim 仍未完全闭环。
* RISK-10：bitmanip illegal-instruction 路径。
* RISK-11：atomic SC.W 与 Spike 语义差异。

这些风险解除后，应同步撤销 ``cosim: disabled``、补充 coverage 目标并更新
waiver 状态。

