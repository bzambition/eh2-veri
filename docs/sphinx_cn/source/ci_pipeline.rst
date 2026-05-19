:orphan:

CI 流水线
==========================================================================================

EH2 仓库有两类 CI：纯 Python / YAML 快速检查，以及需要内部仿真器和
spike-cosim 的 RTL sign-off 检查。前者可在 GitHub-hosted runner 上运行，
后者必须在带 VCS license 的 self-hosted runner 上运行。

GitHub Workflows
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 28 24 48

   * - Workflow
     - Runner
     - 内容
   * - ``unit-tests.yml``
     - ``ubuntu-latest``
     - Python regression-framework 单元测试；testlist YAML sanity；
       directed / cosim testlist 基本解析。
   * - ``sim.yml``
     - ``self-hosted, eh2-sim``
     - ``make cosim``、``make compile SIMULATOR=vcs``、
       ``make signoff`` ，并上传 sign-off report artifact。

``sim.yml`` 只在手动触发或 PR 带 ``run-sim`` label 时运行，避免普通 PR
在没有内部 license 的 runner 上失败。

本地 CI
------------------------------------------------------------------------------------------

提交前推荐至少运行：

.. code-block:: bash

   make ci_unit

该目标执行：

* ``python3 -m unittest tests.test_regression_framework``
* ``make ci_lint`` ，检查 ``testlist.yaml`` 非空、无重复 test 名、必需字段存在。

它不需要 VCS、Spike 或 RISC-V GCC，适合快速发现脚本层回归。

仿真 CI
------------------------------------------------------------------------------------------

需要完整工具链时运行：

.. code-block:: bash

   source env.sh
   make cosim
   make compile SIMULATOR=vcs
   make signoff PROFILE=quick SIGNOFF_OUT=build/ci_signoff PARALLEL=4

PR 级别通常跑 ``quick`` ；合入前或里程碑跑 ``full`` 。CI 上传：

* ``signoff_status.json``
* ``signoff_report.md``
* 各 stage ``regr.log``
* 各 stage ``report.json``

失败处理
------------------------------------------------------------------------------------------

CI 失败按以下顺序定位：

1. ``unit-tests`` 失败：先看 Python traceback 或 YAML sanity 输出。
2. ``make cosim`` 失败：检查 ``SPIKE_DIR`` / ``SPIKE_INSTALL`` / C++ ABI。
3. ``make compile`` 失败：检查 filelist、include path、VCS license。
4. ``make signoff`` 失败：打开 artifact 中的 ``signoff_report.md`` ，
   根据失败 stage 跳到对应 ``runs/<stage>`` 目录。
5. 单个测试失败：打开该测试 ``result.yaml`` 和 ``sim_*.log`` 。

CI 约束
------------------------------------------------------------------------------------------

* GitHub-hosted runner 不应尝试 VCS 或 spike-cosim。
* ``sim.yml`` 的 timeout 是 240 分钟，full profile 应保持在该范围内。
* 新增 long-running test 前先评估 sign-off wall time。
* ``skip_in_signoff`` 只能作为有 issue 追踪的临时隔离，不是 CI 绿灯工具。

