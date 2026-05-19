.. _references:
.. _08_appendix/references:

参考资料索引
============

:status: draft
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

概述
----

本章列出 EH2 中文手册引用的主要内部资料、外部规范类别、Ibex 对照路径和工具文档
入口。参考资料索引的优先级是：先引用本仓库的可执行证据，再引用 ADR 和手册章节，
最后引用外部规范或工具手册。sign-off 数字、coverage 数字、LEC 数字和 waiver 状态
不得从外部网页推导，必须来自当前仓库的脚本、配置和报告。

设计目标与约束
--------------

资料索引有两个目标：帮助读者找到权威来源；避免历史材料覆盖当前事实。README、
PROJECT_STATUS 和历史发布记录可以作为背景，但若其中数字与 2026-05-19 demo
不一致，本手册采用当前 sign-off 章节和决策章节的口径。外部规范只用于解释标准
概念，不替代 EH2 的实现证据。

架构与组成
----------

资料来源分 5 层：

::

   executable evidence
      Makefile, signoff.py, merge_cov.py, cover.cfg, waiver YAML
   decision evidence
      docs/adr/INDEX.md, ADR-0001..0020
   manual evidence
      02_core_reference, 05_verification_arch, 06_flows, 07_decisions
   comparison evidence
      /home/host/ibex/dv/uvm/core_ibex
   external references
      RISC-V specs, UVM, VCS/URG, IFV, DC/Formality, Verible/Verilator

实现细节
--------

ADR 索引是长期决策引用入口：

.. literalinclude:: ../../../../docs/adr/INDEX.md
   :language: text
   :lines: 1-36
   :caption: docs/adr/INDEX.md:1-36 - canonical ADR list

Topic Map 把参考资料按技术域组织：

.. literalinclude:: ../../../../docs/adr/INDEX.md
   :language: text
   :lines: 40-78
   :caption: docs/adr/INDEX.md:40-78 - ADR topic map

coverage 引用优先使用当前可执行配置：

.. literalinclude:: ../../../../Makefile
   :language: makefile
   :lines: 169-190
   :caption: Makefile:169-190 - coverage 参考入口

Ibex 对照中的 coverage merge 参考使用官方 `core_ibex` 脚本：

.. literalinclude:: ../../../../../ibex/dv/uvm/core_ibex/scripts/merge_cov.py
   :language: python
   :lines: 31-47
   :caption: Ibex merge_cov.py:31-47 - VCS URG merge 参考

配置与使用
----------

查找参考资料的常用命令：

.. code-block:: bash

   # 查找当前手册中的内部引用
   rg -n ":ref:|:file:|literalinclude" docs/sphinx_cn/source

   # 查看 ADR topic map
   sed -n '40,90p' docs/adr/INDEX.md

   # 对照 Ibex UVM 目录
   ls /home/host/ibex/dv/uvm/core_ibex

   # 对照 EH2 coverage 配置
   sed -n '169,190p' Makefile
   cat dv/uvm/core_eh2/cover.cfg

内部资料
--------

.. list-table:: 内部权威资料
   :header-rows: 1
   :widths: 26 34 40

   * - 路径
     - 用途
     - 适用范围
   * - :file:`Makefile`
     - 顶层 target、默认变量、VCS coverage 配置、sign-off 入口
     - 命令和 gate 事实
   * - :file:`dv/uvm/core_eh2/scripts/signoff.py`
     - 9 stage gate、coverage parser、waiver gate、报告生成
     - sign-off 行为事实
   * - :file:`dv/uvm/core_eh2/scripts/merge_cov.py`
     - URG coverage merge
     - coverage 数据流事实
   * - :file:`dv/uvm/core_eh2/cover.cfg`
     - DUT-only coverage scope
     - coverage scope 事实
   * - :file:`dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
     - cosim-disabled formal waiver
     - waiver 事实
   * - :file:`docs/adr/INDEX.md`
     - ADR 编号、状态和 topic map
     - 决策事实
   * - :file:`syn/build/lec_summary.txt`
     - block-level LEC 汇总
     - LEC 证据
   * - :file:`dv/formal/build/ifv_final.log`
     - formal property 结果
     - formal 证据

外部规范类别
------------

.. list-table:: 外部规范和工具类别
   :header-rows: 1
   :widths: 24 36 40

   * - 类别
     - 用途
     - 本仓库落点
   * - RISC-V Unprivileged ISA
     - 指令语义、异常基础、压缩指令
     - directed/riscv-dv/compliance/cosim
   * - RISC-V Privileged Architecture
     - CSR、trap、interrupt、PMP、debug 相关行为
     - CSR 章节、PIC/debug/PMP coverage
   * - RISC-V Debug Spec
     - JTAG/DMI/debug mode/DRET
     - debug 章节、JTAG/halt-run agent
   * - UVM 1.2
     - component、phase、config_db、analysis port、sequence
     - :ref:`env`、agent 章节、appendix B
   * - Synopsys VCS/URG
     - SystemVerilog 编译仿真和 coverage report
     - :ref:`build_flow`、:ref:`coverage_plan`
   * - Cadence IFV
     - property proof
     - :ref:`formal_flow`
   * - Synopsys DC/Formality
     - synthesis 和 LEC
     - :ref:`synthesis_flow`、:ref:`lec_flow`
   * - Verible/Verilator
     - lint
     - :ref:`lint_flow`

与 Ibex 工业实现对照
--------------------

EH2 手册对照 Ibex 时优先引用以下路径：

.. list-table:: Ibex 对照资料
   :header-rows: 1
   :widths: 34 66

   * - 路径
     - 用途
   * - :file:`/home/host/ibex/dv/uvm/core_ibex/README.md`
     - core_ibex UVM 总览
   * - :file:`/home/host/ibex/dv/uvm/core_ibex/scripts/merge_cov.py`
     - URG merge 参考
   * - :file:`/home/host/ibex/dv/uvm/core_ibex/yaml/rtl_simulation.yaml`
     - simulator command template 参考
   * - :file:`/home/host/ibex/dv/uvm/core_ibex/cover.cfg`
     - coverage hierarchy 参考
   * - :file:`/home/host/ibex/doc/`
     - 官方文档结构参考

测试与验证
----------

参考资料页的验证重点是避免死引用和过时事实：

.. code-block:: bash

   # 检查内部路径是否存在
   test -f Makefile
   test -f docs/adr/INDEX.md
   test -f dv/uvm/core_eh2/scripts/signoff.py

   # 检查 Ibex 对照路径是否存在
   test -d /home/host/ibex/dv/uvm/core_ibex

   # 构建手册
   sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

已知限制与未来工作
------------------

本章不维护外部网页 URL 的可用性。若后续需要正式外部链接清单，应在 linkcheck 阶段
统一维护，并把外部链接与本仓库证据分开。

参考资料
--------

* :ref:`adr_summary` - ADR 汇总。
* :ref:`coverage_plan` - coverage 证据。
* :ref:`signoff_flow` - sign-off 证据。
* :ref:`ibex_capability_matrix` - Ibex 对照矩阵。
* :ref:`directory_layout` - 目录落点。

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
