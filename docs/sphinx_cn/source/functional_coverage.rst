功能覆盖率
==========

EH2 平台的 functional coverage 主要位于 ``dv/uvm/core_eh2/fcov``。覆盖率
代码通过 bind 和 interface 观察 DUT 内部信号，目标是覆盖 EH2 特有的
双发射、异常/中断、debug、CSR、PMP/ePMP、pipeline stall 等状态组合。

文件结构
--------

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - 文件
     - 职责
   * - ``eh2_fcov_if.sv``
     - 主覆盖接口，797 行，包含 uarch、CSR、dual issue、interrupt、
       instruction detail、controller FSM、pipeline state 等 covergroup。
   * - ``eh2_pmp_fcov_if.sv``
     - PMP / ePMP 子覆盖接口，覆盖 region mode、权限、lock、access error、
       mseccfg MML/MMWP/RLB 组合。
   * - ``eh2_fcov_bind.sv``
     - bind 入口，将 coverage interface 绑定到 DUT hierarchy。
   * - ``eh2_csr_categories.svh``
     - CSR 分类辅助定义。
   * - ``cov_waivers/``
     - 覆盖率 waiver YAML 与 ``eh2_cov_waiver_pkg.sv``。

启用方式
--------

编译和运行时打开 coverage：

.. code-block:: bash

   make compile COV=1
   make run TEST=<name> BINARY=<hex> COV=1

或走 regression：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --test riscv_arithmetic_basic_test \
     --coverage \
     --output build/cov_arith

SV 侧 coverage interface 通过 ``+enable_eh2_fcov=1`` 采样。顶层 Makefile
在 ``COV=1`` 时为 VCS 添加 ``-cm line+cond+fsm+tgl+assert``，并在 run
阶段添加 ``+enable_eh2_fcov=1``。

主覆盖组
--------

``eh2_fcov_if.sv`` 定义的主要 covergroup：

.. list-table::
   :header-rows: 1
   :widths: 28 72

   * - covergroup
     - 关注点
   * - ``uarch_cg``
     - i0/i1 指令类别、stall 类型、branch taken / mispredict、flush、
       exception、interrupt、debug、dual issue、ICache、LSU external 等。
   * - ``csr_cg``
     - CSR 访问类型。
   * - ``dual_issue_cg``
     - i0/i1 指令类别交叉，覆盖双发射组合。
   * - ``interrupt_cg``
     - interrupt source、NMI、debug 中断交叉。
   * - ``csr_warl_cg``
     - CSR 地址与操作类型交叉，关注 EH2 CSR WARL 空间。
   * - ``instr_detail_cg``
     - branch/load/store/ALU/muldiv/sync 子类型、压缩宽度与类别交叉。
   * - ``controller_fsm_cg``
     - debug state、exception entry、interrupt entry、mret、flush reason。
   * - ``pipeline_state_cg``
     - pipeline utilization、E4 commit、stall、branch mispredict 等。

PMP / ePMP 覆盖组
-----------------

``eh2_pmp_fcov_if.sv`` 覆盖：

* 每个 PMP region 的 mode、权限、lock。
* instruction side / data side access error。
* debug mode 与 PMP error 的交叉。
* NAPOT size WARL 行为。
* ePMP ``mseccfg`` 的 MML / MMWP / RLB 组合。

PMP coverage 需要 RTL 配置和测试共同启用 PMP，否则采样点会保持空洞。

waiver 机制
-----------

覆盖率 waiver 以 YAML 文件存放在 ``fcov/cov_waivers``。每个 waiver 必须
说明：

* ``coverage_point``：例如 ``uarch_cg.stall_cross``。
* ``reason``：为什么该 bin 架构不可达或无需覆盖。
* ``author`` / ``date``：批准人和日期。
* ``status``：active / inactive。

当前已有两个真实 waiver：

* ``dual_issue_presync_stall_cross_waiver.yaml``
* ``nmi_during_debug_cross_waiver.yaml``

waiver 不应作为补测试的替代品。只有确认 RTL 架构不可达、测试代价不成比例，
或该组合由其它证据覆盖时，才接受 waiver。

覆盖率收敛策略
--------------

推荐闭环顺序：

1. 先跑 ``riscv_arithmetic_basic_test``、``riscv_load_store_test``、
   ``riscv_dual_issue_test`` 建立 uarch / pipeline 基线。
2. 增加 ``riscv_mul_div_test``、``riscv_bitmanip_test``、``riscv_exception_test``
   覆盖特殊指令与异常路径。
3. 用 ``riscv_interrupt_*``、``riscv_debug_*``、``riscv_pmp_*`` 系列补控制面。
4. 对剩余空洞逐项分类：可测、架构不可达、工具限制、sign-off 外。
5. 可测项补 directed stream 或 asm；不可达项写 waiver。

当前 full sign-off 报告中 coverage 状态为 ``SKIP``，即覆盖率尚未作为默认
签发门限。``signoff.py`` 已支持 ``--coverage``、``--require-coverage`` 与
多个 ``--min-*-coverage`` 阈值，后续可逐步打开。

