:orphan:

Sign-off 流程
==========================================================================================

``dv/uvm/core_eh2/scripts/signoff.py`` 是 EH2 UVM 平台的签发 gate。它既可以
启动各 stage 回归，也可以在 ``--gate-only`` 模式下评估已有结果目录。
顶层入口是：

.. code-block:: bash

   make signoff PROFILE=full PARALLEL=4

Profile
------------------------------------------------------------------------------------------

当前 profile 与 stage 映射：

.. list-table::
   :header-rows: 1
   :widths: 18 82

   * - Profile
     - Stage
   * - ``quick``
     - ``smoke``、``directed``
   * - ``cosim``
     - ``smoke``、``cosim``
   * - ``nightly``
     - ``smoke``、``directed``、``cosim``、``riscvdv``
   * - ``full``
     - ``smoke``、``directed``、``cosim``、``riscvdv``

也可以通过 ``--stages smoke,cosim`` 覆盖 stage 清单。

Stage 内容
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 18 28 54

   * - Stage
     - 输入
     - 说明
   * - ``smoke``
     - ``tests/asm/smoke.hex``
     - 单个 mailbox smoke，带 ``+disable_cosim=1`` 。
   * - ``directed``
     - ``directed_tests/directed_testlist.yaml``
     - 3 个 deterministic directed test。
   * - ``cosim``
     - ``directed_tests/cosim_testlist.yaml``
     - 4 个 Spike lockstep proof test。
   * - ``riscvdv``
     - ``riscv_dv_extension/testlist.yaml``
     - 随机 testlist；sign-off 模式跳过 ``skip_in_signoff`` 项。

Precheck
------------------------------------------------------------------------------------------

默认 sign-off 先执行 precheck：

* EH2 根目录存在。
* RTL / TB filelist 存在。
* simulator 或 ``build/simv`` 可用。
* ``riscv32-unknown-elf-gcc`` / ``objcopy`` 可用。
* riscv-dv ``run.py`` 存在。
* cosim stage 需要 ``build/libcosim.so`` 。
* default profile 是 ``NUM_THREADS=1`` 。

precheck 失败会阻塞最终状态，除非使用 ``--skip-precheck`` 。

Gate 条件
------------------------------------------------------------------------------------------

默认 gate 条件：

* 所有 stage 状态必须 PASS。
* 每个 stage pass rate 不低于 ``--min-pass-rate`` ，默认 100%。
* 若启用 ``--require-coverage`` ，必须找到并解析 coverage report。
* 若启用 ``--require-cosim-all-tests`` ，任何 ``cosim: disabled`` 都会阻塞。
* 未加 ``--allow-warnings`` 时，stage command 使用 ``--fail-on-warnings`` 。

Coverage gate 支持：

* ``--min-overall-coverage``
* ``--min-line-coverage``
* ``--min-cond-coverage``
* ``--min-fsm-coverage``
* ``--min-toggle-coverage``
* ``--min-functional-coverage``

当前 full PASS 报告 coverage 状态是 ``SKIP`` ，说明 coverage 尚不是默认门限。

输出
----

sign-off 输出目录默认 ``build/signoff`` ，可用 ``SIGNOFF_OUT`` 覆盖。关键文件：

.. code-block:: text

   signoff_status.json
   signoff_report.md
   logs/<stage>.log
   runs/<stage>/report.json
   reports/<stage>/report.json

``signoff_report.md`` 是人工审阅入口；``signoff_status.json`` 适合 CI 或
后续脚本消费。

当前基线
------------------------------------------------------------------------------------------

``build/sf_full2/signoff_report.md`` 显示 2026-05-07 的 full profile PASS，
``build/sf_baseline2/`` 二次验证结果完全一致：

.. list-table::
   :header-rows: 1
   :widths: 18 16 16 16 18

   * - Stage
     - Total
     - Passed
     - Failed
     - Pass Rate
   * - smoke
     - 1
     - 1
     - 0
     - 100.00%
   * - directed
     - 3
     - 3
     - 0
     - 100.00%
   * - cosim
     - 4
     - 4
     - 0
     - 100.00%
   * - riscvdv
     - 32
     - 32
     - 0
     - 100.00%

该 32/32 是 sign-off 模式扣除 11 个 ``skip_in_signoff`` 后的统计。
报告还列出 34 个 ``cosim: disabled`` 测试，需保持 waiver-reviewed。

.. note::

   重跑 sign-off 时必须使用 ``SIGNOFF_ITERATIONS=1`` （或在 Makefile 中指定），
   否则 testlist.yaml 中各 test 的 ``iterations`` 字段会全部展开（如 10 / 20 次），
   导致多 seed 随机测试出现预期外的超时/hang（非 cosim 问题），总 test 数
   会从 32 涨到 185。

cosim:disabled 测试清单（34 项）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

以下 riscv-dv 测试因 cosim 已知限制被标 ``cosim: disabled`` ，
对应 issue 11/12/13/14：

* ``riscv_random_instr_test`` — 中断/异常路径（RISK-9, issue 11）
* ``riscv_csr_test`` — CSR WARL（RISK-1, issue 14）
* ``riscv_bitmanip_test`` — Zb* 扩展（RISK-10, issue 12）
* ``riscv_amo_test`` — atomic SC.W（RISK-11, issue 13）
* ``riscv_interrupt_test`` / ``riscv_irq_single_test`` — 中断（issue 11）
* ``riscv_debug_test`` / ``riscv_debug_csr_test`` — 调试（issue 11/14）
* ``riscv_stress_test`` / ``riscv_breakpoint_test`` — 压力/断点（issue 11）
* ``riscv_csr_hazard_test`` — CSR hazard（issue 14）
* ``riscv_exception_stream_test`` — 异常流（issue 11）
* ``riscv_pmp_basic_test`` / ``riscv_pmp_disable_all_test`` / ``riscv_pmp_random_test`` — PMP（issue 14）
* ``riscv_pc_intg_test`` / ``riscv_rf_intg_test`` — 完整性检查（issue 11）
* ``riscv_reset_test`` / ``riscv_single_step_test`` — 复位/单步（issue 11）
* ``riscv_epmp_mml_test`` / ``riscv_epmp_mmwp_test`` / ``riscv_epmp_rlb_test`` — ePMP（issue 14）
* ``riscv_mem_error_test`` — 存储错误（issue 11）
* ``riscv_debug_wfi_test`` / ``riscv_debug_during_csr_test`` / ``riscv_debug_ebreak_test`` — 调试细分（issue 11）
* ``riscv_irq_wfi_test`` / ``riscv_irq_csr_test`` / ``riscv_irq_nest_test`` — 中断细分（issue 11）
* ``riscv_irq_in_debug_test`` / ``riscv_debug_in_irq_test`` — IRQ-debug 交叉（issue 11）
* ``riscv_dret_test`` / ``riscv_debug_ebreakmu_test`` / ``riscv_single_debug_pulse_test`` — 调试返回（issue 11）

常用命令
------------------------------------------------------------------------------------------

.. code-block:: bash

   # 快速本地 gate
   make signoff_quick PARALLEL=4

   # 完整 gate
   make signoff PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_full

   # 只评估已有结果
   make signoff_gate PROFILE=full SIGNOFF_OUT=build/sf_full

   # 带 coverage 门限
   make signoff PROFILE=full COV=1 SIGNOFF_OPTS="--require-coverage --min-line-coverage 80"

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页介绍的 Makefile target 或 Python 脚本入口是什么，默认 simulator 是否仍是 VCS？
2. 该流程产生哪些 build 目录、log、JSON、coverage database 或 HTML artifact？
3. VCS/URG 路径和 NC/IMC 备选路径在本页中是否被分开解释？
4. 失败时第一份应打开的日志是哪一个，第二步应检查哪个变量或 YAML 配置？
5. 本页中的 sign-off 数字是否仍为 9/9 PASS、102/104、LEC 31635/31635 和 LINE 95.05%？
