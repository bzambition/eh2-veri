.. _adr-0010:

ADR-0010: CSR Register Model -- uvm_reg 方案
===============================================

:status: Accepted
:source: docs/adr/0010-csr-register-model.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

EH2 CSR 单元测试子环境需要一套寄存器模型来描述每个 CSR 的地址、复位值、
WARL mask、只读状态和访问权限。评估了两种方案：``csr_desc_t`` （手写 struct）
和 ``uvm_reg / uvm_reg_block`` （UVM 寄存器层）。

§2  决策
---------

使用 **uvm_reg / uvm_reg_block** 。

**选择理由：**

1. **Mirroring 和 prediction** ：``uvm_reg`` 内置 ``mirror()``、``predict()`` ，
   scoreboard 可以将 DUT 观测值推入 mirror 并检测 mismatch
2. **Access abstraction** ：``uvm_reg::read()/write()`` 同时支持 frontdoor
   （bus-sequencer）和 backdoor（DPI/hierarchical）访问
3. **Discoverability** ：标准 ``uvm_reg`` introspection 允许脚本验证
   每个 CSR 都已实例化
4. **Coverage** ：``uvm_reg`` fields 可携带 functional coverage models
5. **行业先例** ：LowRISC Ibex 使用 ``uvm_reg`` 风格的寄存器建模

§3  实现
---------

- 每个 EH2 CSR（约 95 个）是继承 ``uvm_reg`` 的 ``eh2_csr_reg`` 对象
- 所有寄存器位于继承 ``uvm_reg_block`` 的 ``eh2_csr_reg_block`` 中
- DUT 访问通过 DPI backdoor 函数（``csr_dpi_read``、``csr_dpi_write`` ）
- 寄存器模型的 ``predict_from_dut()`` 方法在每次访问后从 DUT 同步 mirror

§4  后果
---------

- 标准 UVM 工具链可 introspection 和验证模型
- 基于 mirror 的 scoreboard 比较消除手写 per-CSR 检查代码
- 模型可在单元测试和 full-chip 环境间共享（DPI backdoor vs bus frontdoor）
- 要求 VCS 或支持 DPI + UVM 1.2 的模拟器

§5  参考资料
-------------

* :file:`dv/uvm/cs_registers_eh2/`

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - CSR unit 子环境与 uvm_reg
     - :file:`docs/adr/0010-*`
   * - 代码路径 1
     - :file:`dv/uvm/cs_registers_eh2/reg_model`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/cs_registers_eh2/reg_driver`
     - 当前仓库实际文件
   * - 代码路径 3
     - :file:`dv/uvm/cs_registers_eh2/Makefile`
     - 当前仓库实际文件


签核与边界
----------

CSR 单元子环境独立于 core_eh2 主 TB，可通过 VCS 或 NC 执行寄存器模型单测。sign-off 的 csr_unit stage 保持独立关卡，避免主回归通过但 CSR mirror/predictor 退化。

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
