.. _adr-0017:

ADR-0017: Integrity Test Cosim Waiver
========================================

:status: Accepted
:source: docs/adr/0017-integrity-cosim-waiver.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 实现多项硬件完整性保护（RF parity、DCCM/ICCM ECC、ICache parity）。
Spike ISS 无 ECC/parity 模型，无法复制这些验证步骤。

§2  决策
---------

完整性测试永久 ``cosim: disabled`` ，通过正式 waiver 文件豁免。
signoff.py 三级关卡：``--fail-on-cosim-disabled`` + ``--validate-waivers``

§3  后果
---------

5 个完整性测试（pc_intg/rf_intg/rf_addr_intg/ram_intg/icache_intg/mem_intg_error）
有 cosim: disabled 和正式 waivers。

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - integrity cosim waiver
     - :file:`docs/adr/0017-*`
   * - 代码路径 1
     - :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/scripts/signoff.py`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`docs/signoff-gates.md`
     - 当前仓库实际文件


签核与边界
----------

当前 signoff.py 使用 25% fail-rate ceiling 和 waiver schema 校验管理 cosim-disabled 项。integrity fault injection 由于 Spike 无 ECC/parity 模型，必须在 waiver 中有原因、跟踪项和过期策略。

统一签核口径为 2026-05-19 01:02 VCS 主线 demo：``9/9`` stages PASS，实跑覆盖率
``102/104`` （98.1%），LEC ``31635/31635`` PASS。覆盖率由 VCS ``simv.vdb``
经 URG 原生 dashboard 生成，编译时 :file:`dv/uvm/core_eh2/cover.cfg` 限定
``+tree core_eh2_tb_top.dut``，指标为 ``line+tgl+assert+fsm+branch`` 五维，
不包含 cond 维度。NC/Incisive 是完整备选 simulator，可运行 smoke、regress、sign-off、demo 与覆盖率 cross-check；默认 release 参考仍为 VCS/URG。

参考章节
--------

* :ref:`adr_summary`
* :ref:`signoff_flow`
* :ref:`appendix_b_uvm/index`
* :ref:`appendix_c_tools/index`
