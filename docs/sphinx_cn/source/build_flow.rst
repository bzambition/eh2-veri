构建流程
========

EH2 平台的构建流程由顶层 ``Makefile`` 统一调度，核心目标包括 cosim 共享库、
RTL testbench、单测运行、riscv-dv 指令生成、coverage 与 sign-off。VCS 是
主线仿真器，Xcelium / Questa 保留在脚本和 YAML 配置中。

顶层 Makefile
-------------

常用目标：

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - 目标
     - 作用
   * - ``make cosim``
     - 构建 ``build/libcosim.so``。
   * - ``make compile``
     - 编译 RTL testbench，默认 ``SIMULATOR=vcs``。
   * - ``make run``
     - 编译后运行一个 binary。
   * - ``make gen``
     - 调用 riscv-dv 生成指令流。
   * - ``make smoke``
     - 快速 smoke regression。
   * - ``make nightly`` / ``make weekly``
     - 按 testlist 执行较大回归。
   * - ``make regress``
     - 直接调用 ``run_regress.py``。
   * - ``make signoff``
     - 调用 ``signoff.py`` 评估签发 gate。
   * - ``make ci_unit``
     - 运行 Python 脚本单元测试和 testlist sanity。
   * - ``make manual``
     - 尝试构建中文 Sphinx rinoh PDF。

Cosim 共享库
------------

``make cosim`` 构建 ``build/libcosim.so``。输入文件：

* ``dv/cosim/spike_cosim.cc``
* ``dv/cosim/cosim_dpi.cc``
* ``dv/cosim/spike_cosim.h``
* ``dv/cosim/cosim.h``

默认依赖：

* ``SPIKE_DIR=/home/host/spike-cosim``
* ``SPIKE_INSTALL=$(SPIKE_DIR)/install``
* ``SPIKE_CXX=/home/Xilinx/Vivado/2019.1/tps/lnx64/gcc-6.2.0/bin/g++``

VCS 编译默认 **硬依赖** ``build/libcosim.so``。如果不需要 cosim，可显式：

.. code-block:: bash

   make compile NO_COSIM=1

这会跳过 ``.so`` prereq 和链接，但仿真必须带 ``+disable_cosim=1``。

VCS 编译
--------

``compile_vcs`` 使用：

* ``-full64 -assert svaext -sverilog``
* ``-ntb_opts uvm-1.2``
* ``+define+GTLSIM``
* ``eh2_rtl.f``、``eh2_shared.f``、``eh2_tb.f``
* ``-top core_eh2_tb_top``
* ``build/libcosim.so``（除非 ``NO_COSIM=1``）

``WAVES=1`` 时添加 ``-debug_access+all -kdb``；``COV=1`` 时添加
``-cm line+cond+fsm+tgl+assert``。

单测运行
--------

直接 Make 路径：

.. code-block:: bash

   make run TEST=my_test BINARY=path/to/test.hex SEED=1 SIM_OPTS="+enable_cosim=1"

``run`` 会先依赖 ``compile``，然后执行 ``build/simv``：

.. code-block:: text

   +UVM_TESTNAME=$(RTL_TEST)
   +bin=$(BINARY)
   +seed=$(SEED)
   +timeout_ns=$(TIMEOUT_NS)
   +UVM_VERBOSITY=$(VERBOSITY)
   $(SIM_OPTS)

输出 log 默认在 ``build/<TEST>_<SEED>/sim.log``。

Ibex-style GOAL 路径
---------------------

当命令带 ``GOAL`` 时，顶层 Makefile 切换到 Ibex-style staged flow：

.. code-block:: bash

   make run GOAL=rtl_sim TEST=riscv_arithmetic_basic_test OUT=out/arith

该模式先调用 ``metadata.py --op create_metadata`` 生成 metadata，再委托
``dv/uvm/core_eh2/wrapper.mk``。它适合需要复用 Ibex 脚本结构的工作流，
但日常单测更常用 ``run_regress.py``。

Filelist
--------

``dv/uvm/core_eh2`` 下的 filelist：

* ``eh2_rtl.f``：EH2 RTL 与 snapshot defines。
* ``eh2_shared.f``：共享 AXI4 interface、slave memory、参数包。
* ``eh2_tb.f``：UVM package、agent、env、test、fcov、TB top。
* ``eh2_dv_cosim_dpi.f``：cosim DPI 相关 include。

新增 SV 文件时优先放入对应 package 的 include 链；只有无法通过 package
覆盖时再改 filelist。

清理
----

``make clean`` 删除顶层 ``build``。``out``、``csrc``、Sphinx build 输出
也可按需删除重建。不要手工删除源码目录下的 filelist、testlist、waiver。
