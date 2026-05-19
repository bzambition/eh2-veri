:orphan:

参考资料
==========================================================================================

本附录列出 EH2 UVM 平台相关的内部文档、外部参考平台与关键源码入口。

内部文档
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 36 64

   * - 路径
     - 内容
   * - ``CONTEXT.md``
     - 项目领域语境：术语、架构、风险、sign-off 状态。
   * - ``eh2-uvm-implementation-plan.md``
     - UVM 平台搭建蓝图，对标 Ibex。
   * - ``docs/cosim-correctness-analysis.md``
     - cosim 数据通路与风险分析。
   * - ``docs/adr/``
     - ADR 0001–0005。
   * - ``docs/agents/issue-tracker.md``
     - 本地 issue tracker 约定。
   * - ``docs/agents/triage-labels.md``
     - triage 标签定义。
   * - ``.scratch/platform-industrialization/PHASE*_PROGRESS.md``
     - Phase 1–5 进度记录。
   * - ``build/sf_full2/signoff_report.md``
     - 2026-05-07 full PASS 证据。

外部 / 相邻项目
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 36 64

   * - 路径
     - 说明
   * - ``/home/host/ibex/dv/uvm/core_ibex/``
     - lowRISC Ibex UVM 参考平台。
   * - ``/home/host/eh2-verification/``
     - EH2 指令级验证平台，使用 QEMU / trace diff，与本 UVM 平台互补。
   * - ``/home/host/spike-cosim/``
     - Spike cosim 安装与库文件来源。
   * - ``vendor/google_riscv-dv/``
     - riscv-dv 子模块。
   * - ``/home/host/Cores-VeeR-EH2``
     - EH2 RTL 源仓库，``RV_ROOT`` 默认指向此处。

关键源码入口
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 36 64

   * - 路径
     - 说明
   * - ``dv/uvm/core_eh2/tb/core_eh2_tb_top.sv``
     - testbench 顶层。
   * - ``dv/uvm/core_eh2/env/core_eh2_env.sv``
     - UVM env 组件组合。
   * - ``dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv``
     - Spike lockstep scoreboard。
   * - ``dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv``
     - retired trace monitor。
   * - ``dv/uvm/core_eh2/common/trace_agent/eh2_dut_probe_monitor.sv``
     - async probe monitor。
   * - ``dv/cosim/spike_cosim.cc``
     - Spike C++ 适配与 EH2 fixup。
   * - ``dv/uvm/core_eh2/scripts/signoff.py``
     - sign-off gate。
   * - ``dv/uvm/core_eh2/scripts/run_regress.py``
     - regression runner。

文档构建参考
------------------------------------------------------------------------------------------

本手册的 Sphinx 结构参考 ``/home/host/eh2-verification/docs/sphinx_en`` ：

* ``docs/sphinx_en/source/conf.py`` ：Sphinx + rinoh 配置。
* ``docs/build_reference_pdf.sh`` ：生成 catalog/status 后调用
  ``sphinx-build -b rinoh`` 。

eh2-veri 当前提供 ``docs/build_manual_pdf.sh`` 与 ``make manual`` 。受限于
当前 Python 3.6 + rinohtype 兼容性，本次交付不要求现场生成 PDF。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
