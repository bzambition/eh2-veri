.. _directory_layout:
.. _08_appendix/directory_layout:

目录结构速查
============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本章解释 `/home/host/eh2-veri` 工作区中主要目录的职责、构建入口和产物边界。EH2
验证平台不是单一 UVM 目录，而是由上游 RTL、项目内 wrapper、UVM 主环境、CSR
子环境、RISC-V compliance 子环境、formal、lint、synthesis/LEC、Sphinx 手册和
脚本共同组成。目录速查的目标是帮助读者迅速判断「该看哪里」「该改哪里」
以及「哪些文件只是可再生产物」。

当前 sign-off 主线以 VCS 为默认 simulator。VCS compile、URG coverage、IFV
formal、DC/Formality LEC 和 HTML report 均会产生大量工具产物；本章同时说明这些
产物应落在 `build/`、`syn/build/`、`dv/formal/build/` 或 Sphinx build 目录中，
而不是混入源码目录。

设计目标与约束
--------------

目录说明必须服务工程操作。源码目录不应被清理脚本误删；可再生产物不应被提交；
release 证据应可追溯；Sphinx 手册应从源码、脚本和配置引用真实片段。新增目录时，
应先判断它属于源码、配置、测试、工具输出、文档还是本地 scratch，再决定是否进入
`.gitignore`、`docs/dir-conventions.md` 或本章。

.. warning::

   不要把 `build/` 下某个历史目录名写成当前权威证据。当前手册统一引用
   2026-05-19 demo 数字和 VCS/URG 主线；历史产物只作为复现线索。

架构与组成
----------

顶层结构可以按职责分为 8 类：

::

   eh2-veri/
      |
      +-- Makefile, env.sh, env.mk, eh2_configs.yaml
      +-- dv/
      |    +-- cosim/
      |    +-- uvm/core_eh2/
      |    +-- uvm/cs_registers_eh2/
      |    +-- uvm/riscv_compliance/
      |    `-- formal/
      +-- rtl/
      |    +-- eh2_veer_wrapper_rvfi.sv
      |    `-- lec_shim/
      +-- syn/
      +-- lint/
      +-- scripts/
      +-- docs/
      |    +-- adr/
      |    `-- sphinx_cn/
      +-- tests/asm/
      +-- vendor/
      `-- build/         可再生产物和 sign-off 输出

.. list-table:: 顶层目录职责
   :header-rows: 1
   :widths: 22 36 42

   * - 路径
     - 主要内容
     - 使用边界
   * - :file:`dv/uvm/core_eh2`
     - EH2 UVM 主 testbench、agent、env、tests、scripts、coverage
     - 普通仿真、regression、riscv-dv 和 sign-off 主入口
   * - :file:`dv/cosim`
     - Spike DPI C++ 桥接和 cosim header
     - 由 ``make cosim`` 和 VCS ``-sv_lib`` 使用
   * - :file:`dv/uvm/cs_registers_eh2`
     - CSR unit 子环境
     - sign-off 的 ``csr_unit`` stage
   * - :file:`dv/uvm/riscv_compliance`
     - RISC-V compliance 子环境
     - sign-off 的 ``compliance`` stage
   * - :file:`dv/formal`
     - IFV/Symbiyosys property、bind、top 和 scripts
     - sign-off 的 ``formal`` stage
   * - :file:`syn`
     - DC 综合、Formality LEC 和 block-level report
     - sign-off 的 ``syn`` stage
   * - :file:`lint`
     - Verible/Verilator 配置和输出
     - sign-off 的 ``lint`` stage
   * - :file:`docs/sphinx_cn`
     - 中文 Sphinx 手册 source 与 build
     - ``make manual`` 或 ``sphinx-build`` 构建

实现细节
--------

顶层 Makefile 把目录名集中定义为变量，后续 target 统一引用：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 78-90
   :caption: Makefile:78-90 - 顶层目录变量

UVM 主 testbench 的 filelist 展示了 `core_eh2` 子目录如何进入编译：

.. literalinclude:: ../../../../dv/uvm/core_eh2/eh2_tb.f
   :language: text
   :lines: 1-38
   :caption: dv/uvm/core_eh2/eh2_tb.f:1-38 - agent package 编译入口

filelist 后半段连接 coverage、env、test package、RVFI interface 和 TB top：

.. literalinclude:: ../../../../dv/uvm/core_eh2/eh2_tb.f
   :language: text
   :lines: 40-72
   :caption: dv/uvm/core_eh2/eh2_tb.f:40-72 - env/fcov/tests/tb top

目录和产物规范由 `docs/dir-conventions.md` 记录。它要求源码和可再生产物分离：

.. literalinclude:: ../../../../docs/dir-conventions.md
   :language: text
   :lines: 1-22
   :caption: docs/dir-conventions.md:1-22 - 目录与工具产物原则

配置与使用
----------

常用目录查询命令如下：

.. code-block:: bash

   # 顶层目录
   find . -maxdepth 1 -type d | sort

   # UVM 主环境目录
   find dv/uvm/core_eh2 -maxdepth 2 -type d | sort

   # 当前 Sphinx source 目录
   find docs/sphinx_cn/source -maxdepth 2 -type d | sort

   # 只看当前阶段附录行数
   wc -l docs/sphinx_cn/source/08_appendix/*.rst

   # 构建 HTML 手册
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

.. list-table:: 构建产物落点
   :header-rows: 1
   :widths: 22 36 42

   * - 产物
     - 推荐目录
     - 说明
   * - VCS compile
     - :file:`build/<target>/`
     - ``simv``、``csrc``、coverage database、compile log
   * - UVM run
     - :file:`build/<target>/runs/<stage>/`
     - ``sim_*.log``、test result、stage report
   * - URG coverage
     - :file:`build/<target>/cov_merged/`
     - ``merged.vdb``、``report/dashboard.txt``、根目录 dashboard 镜像
   * - IFV formal
     - :file:`dv/formal/build/`
     - IFV log、summary、counterexample 输出
   * - DC/Formality
     - :file:`syn/build/`
     - netlist、DDC、SVF、block-level LEC report 和 summary
   * - Sphinx HTML
     - :file:`docs/sphinx_cn/build/html/`
     - 中文手册 HTML 输出

与 Ibex 工业实现对照
--------------------

Ibex 的 `dv/uvm/core_ibex` 目录把 testbench、scripts、yaml、coverage 和 tests 组织在
同一验证根下。EH2 对齐这种布局，但增加了多个 EH2 专属子环境和工具目录。

.. list-table:: 目录布局对照
   :header-rows: 1
   :widths: 24 34 42

   * - 维度
     - Ibex
     - EH2
   * - UVM 主环境
     - :file:`/home/host/ibex/dv/uvm/core_ibex`
     - :file:`dv/uvm/core_eh2`
   * - simulator yaml
     - :file:`core_ibex/yaml/rtl_simulation.yaml`
     - :file:`core_eh2/yaml/rtl_simulation.yaml`
   * - coverage merge
     - :file:`core_ibex/scripts/merge_cov.py`
     - :file:`core_eh2/scripts/merge_cov.py`，VCS/URG 主线
   * - CSR unit
     - Ibex 有独立 CSR 流程参考
     - EH2 使用 :file:`dv/uvm/cs_registers_eh2`
   * - LEC
     - Ibex 规模较小，路径更直接
     - EH2 通过 :file:`syn` 下 block-level Formality 闭环

测试与验证
----------

目录变更应至少运行下列检查：

.. code-block:: bash

   # 确认 filelist 引用存在
   while read -r f; do
     case "$f" in
       ""|\#*|//*|+incdir+*) ;;
       *) test -e "$f" || echo "missing $f" ;;
     esac
   done < dv/uvm/core_eh2/eh2_tb.f

   # 确认 sign-off 入口默认 VCS，并允许 NC 备选 simulator
   rg -n "signoff:|demo:|SIMULATOR" Makefile

   # 确认 Sphinx 附录在总目录中
   rg -n "08_appendix" docs/sphinx_cn/source/index.rst

已知限制与未来工作
------------------

当前工作区包含大量历史、实验和本地 scratch 目录。目录速查只描述稳定入口；临时
目录不应进入手册导航。后续若新增正式子环境，例如新的 memory BFM、性能统计或
外部 ISS adapter，应同步更新 Makefile 变量、filelist、`.gitignore`、目录规范和
本章表格。

参考资料
--------

* :ref:`build_flow` - 构建入口。
* :ref:`regression_flow` - 回归产物。
* :ref:`signoff_flow` - sign-off 输出结构。
* :ref:`scripts_reference` - 脚本目录。
* :file:`docs/dir-conventions.md` - 工具产物规范。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：确认索引、术语、附录或兼容旧入口不会破坏整本手册构建。

.. code-block:: bash

   sphinx-build -W --keep-going -b html docs/sphinx_cn/source /tmp/eh2-doc-practice-check
   rg -n "自检 5 问|动手练习" docs/sphinx_cn/source | head -80

**进阶题**：抽查参考页是否使用当前统一平台口径。

.. code-block:: bash

   rg -n "95.05|31635/31635|line\+tgl\+assert\+fsm\+branch|NC/Incisive" docs/sphinx_cn/source | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
