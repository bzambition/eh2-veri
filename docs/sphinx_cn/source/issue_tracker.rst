:orphan:

Issue Tracker
==========================================================================================

本仓库使用本地 Markdown issue tracker，而不是外部服务作为唯一事实源。
issue、PRD、进度记录均位于 ``.scratch`` ，便于和代码一起审查、搜索和归档。

目录约定
------------------------------------------------------------------------------------------

.. code-block:: text

   .scratch/<feature-slug>/
   ├── PRD.md
   ├── PHASE*_PROGRESS.md
   └── issues/
       ├── 01-<title>.md
       ├── 02-<title>.md
       └── ...

当前主要 feature：

* ``platform-industrialization`` ：Phase 1–5 工业化整改。
* ``cosim-correctness`` ：cosim 正确性闭环专项。

issue 文件顶部应包含 ``Status:`` 行。评论和历史记录追加到文件底部
``## Comments`` 。

Triage 标签
------------------------------------------------------------------------------------------

标准状态：

.. list-table::
   :header-rows: 1
   :widths: 26 74

   * - 标签
     - 含义
   * - ``needs-triage``
     - 维护者尚未评估。
   * - ``needs-info``
     - 等待提报人补充信息。
   * - ``ready-for-agent``
     - 规格完整，可交给 agent 实现。
   * - ``ready-for-human``
     - 需要人工判断或实现。
   * - ``wontfix``
     - 明确不处理，需说明原因。

重要 issue
------------------------------------------------------------------------------------------

``platform-industrialization/issues`` 中的关键项：

.. list-table::
   :header-rows: 1
   :widths: 16 54 30

   * - 编号
     - 标题
     - 状态定位
   * - 01
     - RTL add RVFI-equivalent trace
     - Phase 1 核心修复。
   * - 02
     - trace monitor sample wb
     - Phase 1 trace 自包含。
   * - 03
     - scoreboard simplify
     - 删除启发式 wb 对齐。
   * - 04
     - probe monitor keep async
     - probe 通道降级为 async hint。
   * - 05
     - testlist enable cosim
     - cosim-enabled testlist 收敛。
   * - 06
     - signoff full pass
     - full profile PASS 证据。
   * - 40
     - axi4 active driver
     - 后续扩展。
   * - 41
     - multi-hart cosim
     - NUM_THREADS=2 解锁项。
   * - 42
     - formal bridge
     - formal / RVFI bridge 规划。

``cosim-correctness/issues`` 保留 smoke、ALU、load/store、dual-issue、
interrupt、per-test toggle、CSR suppression、EH2 CSR fixup、64-bit AXI、
NUM_THREADS constraint 等闭环记录。

与手册的关系
------------------------------------------------------------------------------------------

本手册不替代 issue tracker。手册描述平台当前结构和稳定流程；issue tracker
描述某个问题的调查历史、决策过程和未完成项。更新规则：

* 修复风险时，同时更新 issue、``CONTEXT.md`` 风险表、必要时更新手册。
* 新增 ``skip_in_signoff`` 时，必须创建或引用 issue。
* 关闭 issue 时，保留原文件并记录验证命令与结果。

