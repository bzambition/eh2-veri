脚本参考
========

本章列出 ``dv/uvm/core_eh2/scripts`` 下的主要脚本及其职责。脚本均通过
``setup_imports.py`` 或入口脚本自身处理 Python import path，运行时建议先
``source env.sh``。

核心脚本
--------

.. list-table::
   :header-rows: 1
   :widths: 28 72

   * - 脚本
     - 职责
   * - ``run_regress.py``
     - 回归总入口：生成、编译、仿真、检查、报告。
   * - ``signoff.py``
     - 签发 gate：stage 编排、precheck、coverage gate、最终报告。
   * - ``run_instr_gen.py``
     - 包装 riscv-dv ``run.py --steps gen``，生成汇编。
   * - ``compile_test.py``
     - 用 RISC-V GCC 编译 ``.S``，输出 binary 和 VMA-addressed hex。
   * - ``run_rtl.py``
     - 构造 simulator 命令，运行 ``simv`` 或其它仿真器。
   * - ``check_logs.py``
     - 解析仿真 log，识别 PASS/FAIL、UVM_ERROR/FATAL、cycle、instruction。
   * - ``collect_results.py``
     - 收集 result pickle/yaml，生成 ``report.json``。
   * - ``metadata.py``
     - Ibex-style metadata 生成、保存、打印字段。

辅助脚本
--------

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 脚本 / 模块
     - 说明
   * - ``build_instr_gen.py``
     - Ibex-style wrapper 中的 instruction generator 构建步骤。
   * - ``compile_tb.py``
     - metadata 模式下构造 TB 编译命令。
   * - ``directed_test_schema.py``
     - 解析 ``directed_testlist.yaml`` / ``cosim_testlist.yaml`` 的 config/test 结构。
   * - ``eh2_cmd.py``
     - EH2 config helper，输出编译 define 与 ISA 字符串。
   * - ``get_fcov.py``
     - riscv-dv functional coverage 采集入口。
   * - ``merge_cov.py``
     - VCS / Xcelium coverage database 合并。
   * - ``render_config_template.py``
     - 渲染配置模板。
   * - ``riscvdv_interface.py``
     - riscv-dv 命令构造 helper。
   * - ``scripts_lib.py``
     - 通用 subprocess、YAML、pickle helper。
   * - ``test_entry.py`` / ``test_run_result.py``
     - test entry 与结果对象辅助类型。
   * - ``report_lib/``
     - HTML、text、JUnit、DVSIM JSON 报告输出库。

run_regress.py 关键参数
-----------------------

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - 参数
     - 说明
   * - ``--testlist <yaml>``
     - 运行 testlist。
   * - ``--test <name>``
     - 运行单个测试。
   * - ``--iterations <N>``
     - 覆盖 testlist iterations。
   * - ``--seed <N>``
     - 固定 seed。
   * - ``--rtl-test <class>``
     - 指定 UVM test 类。
   * - ``--gen-opts`` / ``--sim-opts``
     - 追加 generator / simulator 选项。
   * - ``--binary <path>``
     - 使用已有 hex / binary，跳过生成和编译。
   * - ``--disable-cosim``
     - 单测模式下关闭 cosim。
   * - ``--coverage`` / ``--waves``
     - 打开 coverage / waveform。
   * - ``--fail-on-warnings``
     - 警告即失败。
   * - ``--parallel <N>``
     - 并发运行数量。

signoff.py 关键参数
-------------------

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - 参数
     - 说明
   * - ``--profile quick|cosim|nightly|full``
     - 选择 stage 预设。
   * - ``--stages smoke,cosim``
     - 覆盖 stage 列表。
   * - ``--stage-result STAGE=DIR``
     - 使用已有 stage 结果。
   * - ``--dry-run``
     - 打印计划，不执行。
   * - ``--gate-only``
     - 只评估结果目录。
   * - ``--coverage`` / ``--coverage-path``
     - 运行时打开 coverage 或指定已有报告。
   * - ``--require-coverage``
     - coverage 缺失或不可解析则失败。
   * - ``--min-pass-rate``
     - stage pass rate 门限，默认 100。
   * - ``--require-cosim-all-tests``
     - 禁止任何 riscv-dv test 标 ``cosim: disabled``。
   * - ``--allow-warnings``
     - 不把 warnings 作为 stage 失败。
   * - ``--skip-precheck``
     - 跳过工具与输入文件预检查。

Python 单元测试
---------------

脚本自测位于 ``scripts/tests/test_regression_framework.py``。本地运行：

.. code-block:: bash

   make ci_unit

或：

.. code-block:: bash

   cd dv/uvm/core_eh2/scripts
   python3 -m unittest tests.test_regression_framework

该检查不需要 VCS 或 spike-cosim，适合作为提交前的快速验证。

