.. _adr-0018:

ADR-0018: 异步写回匹配 -- 从 rd 启发式转向严格 wb_tag
=========================================================

:status: Accepted
:source: docs/adr/0018-wb-tag-strict-matching.md
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  上下文
-----------

Issue 66 在异步写回提示（async_wb_q）匹配中引入了 ``wb_tag`` 字段。
但原始实现在三处保留了 ``rd == expected_rd`` 启发式回退。

§2  决策
---------

删除所有 ``rd == expected_rd`` 回退，强制仅通过 wb_tag 严格关联。
新增 mismatch 检测：当队列中有正确来源但 wb_tag 不匹配时，
``uvm_error`` + ``mismatch_count++`` 。

§3  wb_tag 缺失场景行为
------------------------

- hint wb_tag == item wb_tag → 正常匹配消费
- queue 有正确来源但 wb_tag 不匹配 → ``uvm_error`` + ``mismatch_count++``
- queue 空或没有正确来源 → 无错误，等待
- hint wb_tag == 0 → 从不匹配

§4  后果
---------

- 异步写回匹配具有确定性且可验证
- 与 ADR-0004 理念一致：消除启发式方法
- 验证标准：``grep -n "rd == expected_rd"`` 返回 0 行

当前实现映射
------------

.. list-table::
   :header-rows: 1
   :widths: 28 42 30

   * - 维度
     - 当前实现
     - 关键证据
   * - 决策主题
     - wb_tag 严格匹配
     - :file:`docs/adr/0018-*`
   * - 代码路径 1
     - :file:`dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv`
     - 当前仓库实际文件
   * - 代码路径 2
     - :file:`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
     - 当前仓库实际文件


签核与边界
----------

当前 async writeback 匹配以 wb_tag 为主键，不再把 rd 地址作为启发式成功条件。该决策降低 dual-issue、DIV overwrite 与 NB-load completion 场景中的误配风险。

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
