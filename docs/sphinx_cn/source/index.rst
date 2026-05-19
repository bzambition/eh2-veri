.. _index:

EH2 UVM 验证平台 — 参考手册
============================

:status: draft
:last-reviewed: 2026-05-19

本手册是 **VeeR EH2 RISC-V 处理器** UVM 验证平台的完整技术参考，面向验证工程师、处理器架构师、SoC 集成人员与工具链开发者。

平台对 EH2 双线程 RV32IMAC + Zb* 处理器进行工业级 UVM 验证，对标 `lowRISC Ibex 验证平台 <https://ibex-core.readthedocs.io/en/latest/>`_。

.. toctree::
   :maxdepth: 2
   :caption: 第〇部分 — 关于本手册
   :numbered:

   00_about/index
   00_about/reader
   00_about/conventions
   00_about/contributing

.. toctree::
   :maxdepth: 2
   :caption: 第一部分 — EH2 核总览
   :numbered:

   01_overview/index
   01_overview/introduction
   01_overview/features
   01_overview/standards
   01_overview/targets
   01_overview/licensing

.. toctree::
   :maxdepth: 2
   :caption: 第二部分 — EH2 核架构参考
   :numbered:

   02_core_reference/index
   02_core_reference/pipeline
   02_core_reference/dual_thread
   02_core_reference/icache
   02_core_reference/dccm_iccm
   02_core_reference/csr
   02_core_reference/pic
   02_core_reference/debug
   02_core_reference/bus_axi_ahb
   02_core_reference/rvfi_trace
   02_core_reference/mailbox

.. toctree::
   :maxdepth: 2
   :caption: 第三部分 — 集成与配置
   :numbered:

   03_integration/index
   03_integration/system_requirements
   03_integration/getting_started
   03_integration/configuration
   03_integration/soc_integration
   03_integration/examples

.. toctree::
   :maxdepth: 2
   :caption: 第四部分 — 验证平台总览
   :numbered:

   04_verification_overview/index
   04_verification_overview/goals_scope
   04_verification_overview/quickstart
   04_verification_overview/ibex_capability_matrix

.. toctree::
   :maxdepth: 2
   :caption: 第五部分 — 验证平台架构与组件
   :numbered:

   05_verification_arch/index
   05_verification_arch/tb_top
   05_verification_arch/env
   05_verification_arch/agent_axi4
   05_verification_arch/agent_irq
   05_verification_arch/agent_jtag
   05_verification_arch/agent_halt_run
   05_verification_arch/agent_trace
   05_verification_arch/agent_cosim
   05_verification_arch/cosim_scoreboard
   05_verification_arch/functional_coverage
   05_verification_arch/pmp_coverage
   05_verification_arch/tests_library
   05_verification_arch/vseq_library
   05_verification_arch/riscv_dv_extension

.. toctree::
   :maxdepth: 2
   :caption: 第六部分 — 流程与脚本
   :numbered:

   06_flows/index
   06_flows/build_flow
   06_flows/regression_flow
   06_flows/signoff_flow
   06_flows/ci_pipeline
   06_flows/lint_flow
   06_flows/formal_flow
   06_flows/synthesis_flow
   06_flows/lec_flow
   06_flows/compliance_flow
   06_flows/scripts_reference

.. toctree::
   :maxdepth: 2
   :caption: 第七部分 — 设计决策与质量
   :numbered:

   07_decisions/index
   07_decisions/adr_summary
   07_decisions/risk_register
   07_decisions/coverage_plan
   07_decisions/known_limitations

.. toctree::
   :maxdepth: 2
   :caption: 第八部分 — 附录
   :numbered:

   08_appendix/index
   08_appendix/directory_layout
   08_appendix/glossary
   08_appendix/troubleshooting
   08_appendix/issue_tracker
   08_appendix/references
   08_appendix/changelog

.. toctree::
   :maxdepth: 1
   :caption: 附录 A — RTL 模块字典

   appendix_a_rtl/index
   appendix_a_rtl/wrapper
   appendix_a_rtl/ifu
   appendix_a_rtl/dec
   appendix_a_rtl/exu
   appendix_a_rtl/lsu
   appendix_a_rtl/dbg
   appendix_a_rtl/dmi
   appendix_a_rtl/pic
   appendix_a_rtl/dma
   appendix_a_rtl/mem
   appendix_a_rtl/lib
   appendix_a_rtl/include
   appendix_a_rtl/shared_axi4

.. toctree::
   :maxdepth: 1
   :caption: 附录 B — UVM 类字典

   appendix_b_uvm/index
   appendix_b_uvm/tb
   appendix_b_uvm/env
   appendix_b_uvm/axi4_agent
   appendix_b_uvm/irq_agent
   appendix_b_uvm/jtag_agent
   appendix_b_uvm/halt_run_agent
   appendix_b_uvm/trace_agent
   appendix_b_uvm/cosim_agent
   appendix_b_uvm/tests
   appendix_b_uvm/vseq
   appendix_b_uvm/fcov
   appendix_b_uvm/riscv_dv_ext

.. toctree::
   :maxdepth: 1
   :caption: 附录 C — Cosim / Formal / Syn / Lint 源码字典

   appendix_c_tools/index
   appendix_c_tools/cosim_cpp
   appendix_c_tools/formal_properties
   appendix_c_tools/formal_infra
   appendix_c_tools/syn_yosys
   appendix_c_tools/syn_nangate
   appendix_c_tools/syn_lec
   appendix_c_tools/lint_verible
   appendix_c_tools/lint_verilator
   appendix_c_tools/asm_tests

.. toctree::
   :maxdepth: 1
   :caption: 附录 D — ADR 全文

   appendix_d_adr/index
   appendix_d_adr/0001_cosim_via_trace_and_probe
   appendix_d_adr/0002_axi4_passive_monitoring
   appendix_d_adr/0003_num_threads_cosim_scope
   appendix_d_adr/0004_rtl_rvfi_equivalent_trace
   appendix_d_adr/0005_spike_cosim_store_wider_wstrb
   appendix_d_adr/0006_atomic_cosim
   appendix_d_adr/0007_interrupt_cosim
   appendix_d_adr/0008_debug_cosim
   appendix_d_adr/0009_pmp_cosim
   appendix_d_adr/0010_csr_register_model
   appendix_d_adr/0011_compliance_framework
   appendix_d_adr/0012_formal_strategy
   appendix_d_adr/0013_synthesis_toolchain
   appendix_d_adr/0014_formal_real_runs
   appendix_d_adr/0015_rvfi_adapter_layer
   appendix_d_adr/0016_multi_hart_cosim
   appendix_d_adr/0017_integrity_cosim_waiver
   appendix_d_adr/0018_wb_tag_strict_matching
   appendix_d_adr/0019_lec_tool_version_limitation
   appendix_d_adr/0020_blocklevel_lec
   appendix_d_adr/template

.. toctree::
   :maxdepth: 1
   :caption: 附录 E — 配置矩阵

   appendix_e_config/eh2_configs

.. toctree::
   :maxdepth: 1
   :caption: 附录 F — 脚本字典

   appendix_f_scripts/index
   appendix_f_scripts/core_eh2_scripts
   appendix_f_scripts/makefiles
   appendix_f_scripts/top_scripts
   appendix_f_scripts/yaml_configs

文档版本与构建
--------------

本手册由 ``docs/sphinx_cn/source/`` 下的 reStructuredText 源文件构建。

* **HTML 构建**::

    cd /home/host/eh2-veri
    sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

* **PDF 构建** （需要 rinohtype，Python 3.10+）::

    bash docs/build_manual_pdf.sh

* **依赖安装**::

    pip install -r docs/requirements-docs.txt

.. note::

   本手册描述的状态截至 **2026-05-19** 。实时项目状态以 :file:`CONTEXT.md`
   与 :file:`docs/PROJECT_STATUS.md` 为准。

.. todolist::
