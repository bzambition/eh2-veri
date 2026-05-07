快速开始
========

本章给出从空 shell 到跑通 EH2 UVM 平台的最短路径。默认读者已经在
``/home/host/eh2-veri`` 仓库内工作，并且机器上安装了 VCS、RISC-V
裸机 GCC、Spike cosim 依赖与 Python ``pyyaml``。

环境初始化
----------

所有命令建议从仓库根目录执行：

.. code-block:: bash

   cd /home/host/eh2-veri
   source env.sh

``env.sh`` 会设置平台常用变量，包括 ``EH2_VERIF_ROOT``、``RV_ROOT``、
``GCC_PREFIX``、``ABI``、``RISCV_DV_ROOT`` 等。若命令找不到
``riscv32-unknown-elf-gcc``，先检查 ``GCC_PREFIX`` 是否指向当前机器上的
工具链安装目录。

最小烟囱路径
------------

无 cosim 的最小 smoke 用于证明 RTL testbench、预生成 hex、mailbox
结束机制和 UVM 框架可以启动：

.. code-block:: bash

   make compile NO_COSIM=1
   make run TEST=smoke BINARY=tests/asm/smoke.hex SIM_OPTS="+disable_cosim=1"

该路径不需要 ``build/libcosim.so``。适合第一次确认仿真器、license、
filelist、DUT wrapper 是否能工作。

cosim 证明路径
--------------

cosim 是本平台的核心闭环。推荐先构建 ``libcosim.so``，再跑 4 个 directed
cosim 证明测试：

.. code-block:: bash

   make cosim
   make compile
   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --testlist dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml \
     --simulator vcs \
     --iterations 1 \
     --parallel 4 \
     --output build/cosim_smoke

成功时 ``build/cosim_smoke/report.json`` 中四个测试全部 PASS，仿真 log
的 cosim scoreboard 报告 ``RESULT: PASS`` 且 ``Mismatches: 0``。

单测调试
--------

运行一个 riscv-dv 测试：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --test riscv_arithmetic_basic_test \
     --seed 1 \
     --simulator vcs \
     --output build/one_arith

运行一个已有 directed 汇编：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --testlist dv/uvm/core_eh2/directed_tests/directed_testlist.yaml \
     --test directed_alu \
     --seed 1 \
     --output build/one_directed

常用调试开关如下：

.. list-table::
   :header-rows: 1
   :widths: 28 72

   * - 开关
     - 用途
   * - ``--waves`` 或 ``WAVES=1``
     - 打开波形相关编译 / 运行选项。
   * - ``--coverage`` 或 ``COV=1``
     - 打开代码覆盖率与 ``+enable_eh2_fcov=1``。
   * - ``--fail-on-warnings``
     - sign-off 使用；把 UVM / 仿真警告提升为失败。
   * - ``--sim-opts "+disable_cosim=1"``
     - 显式关闭 cosim，适用于 Spike 尚不支持的测试。
   * - ``--sim-opts "+max_cycles=500000"``
     - 增大 UVM base_test 的 cycle timeout。

sign-off 快速入口
-----------------

开发中推荐先跑 quick profile：

.. code-block:: bash

   make signoff_quick PARALLEL=4

完整签发入口：

.. code-block:: bash

   make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_full

``signoff.py`` 会执行 precheck，并按 profile 运行 smoke、directed、cosim、
riscvdv stage。最终报告位于：

.. code-block:: text

   build/sf_full/signoff_status.json
   build/sf_full/signoff_report.md
   build/sf_full/reports/<stage>/report.json

文档构建
--------

本手册源码位于 ``docs/sphinx_cn/source``。当前工作环境已知没有可用的
Sphinx + rinohtype PDF 组合，因此本次交付以 Sphinx 中文源文件为准。
如果在 Python 3.10+ 环境安装依赖，可以尝试：

.. code-block:: bash

   pip install --user -r docs/requirements-docs.txt
   make manual

该命令会调用 ``docs/build_manual_pdf.sh``，按 eh2-verification 的
``build_reference_pdf.sh`` 风格生成 rinoh PDF。依赖不可用时，不影响
手册源码阅读和维护。

输出目录速查
------------

.. list-table::
   :header-rows: 1
   :widths: 28 72

   * - 目录 / 文件
     - 内容
   * - ``build/libcosim.so``
     - Spike DPI cosim 共享库。
   * - ``build/simv``
     - VCS 编译后的仿真可执行文件。
   * - ``build/<run>/<test>_s<seed>/``
     - 单个测试的生成、编译、仿真 log 与 result pickle/yaml。
   * - ``out/``
     - Ibex-style ``make run GOAL=...`` 流程的输出。
   * - ``docs/sphinx_cn/build/``
     - Sphinx 构建输出。可删除重建，不入核心源码。

