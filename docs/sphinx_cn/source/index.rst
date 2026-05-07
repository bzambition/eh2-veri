EH2 UVM 验证平台
================

.. raw:: latex

   \newpage

本手册描述 **EH2 UVM 验证平台** 的体系结构、组件、工作流和 sign-off 流程。
平台对 VeeR EH2 双线程 RV32IMAC 处理器进行工业级 UVM 验证，对标 lowRISC
Ibex 验证平台 (``/home/host/ibex/dv/uvm/core_ibex/``)。

.. toctree::
   :maxdepth: 3
   :caption: 第一部分 — 总览
   :numbered:

   overview
   architecture
   quickstart

.. toctree::
   :maxdepth: 3
   :caption: 第二部分 — 平台组件
   :numbered:

   testbench
   environment
   agents
   cosim_scoreboard
   functional_coverage
   tests_library

.. toctree::
   :maxdepth: 3
   :caption: 第三部分 — 流程与脚本
   :numbered:

   build_flow
   regression_flow
   signoff_flow
   scripts_reference

.. toctree::
   :maxdepth: 3
   :caption: 第四部分 — 设计决策与质量
   :numbered:

   architecture_decisions
   risk_register
   coverage_plan
   ci_pipeline

.. toctree::
   :maxdepth: 2
   :caption: 第五部分 — 附录
   :numbered:

   directory_layout
   glossary
   troubleshooting
   issue_tracker
   references

文档版本与构建
--------------

本手册由 ``docs/sphinx_cn/`` 下的 reStructuredText 源文件构建。

* **构建工具**：Sphinx + rinohtype（无需 LaTeX）
* **输出格式**：PDF (A4)
* **构建命令**::

    cd /home/host/eh2-veri
    bash docs/build_manual_pdf.sh

* **输出位置**::

    docs/sphinx_cn/build/rinoh/EH2_UVM_Verification_Platform.pdf

* **依赖安装** （Python 3.10+ 推荐）::

    pip install -r docs/requirements-docs.txt

.. note::

   本手册描述的状态截至 **2026-05-07 Sign-off full PASS**。
   实时项目状态以 ``CONTEXT.md`` 与 ``.scratch/platform-industrialization/``
   下的 PHASE_PROGRESS 文档为准。
