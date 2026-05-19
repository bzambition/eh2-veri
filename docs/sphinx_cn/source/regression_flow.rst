:orphan:

回归流程
==========================================================================================

``dv/uvm/core_eh2/scripts/run_regress.py`` 是 EH2 平台的统一回归入口。它把
riscv-dv 生成、汇编编译、RTL 仿真、log 检查和报告生成串成一个流程，
同时兼容 directed testlist 与 riscv-dv testlist。

流程总览
------------------------------------------------------------------------------------------

.. code-block:: text

   testlist / --test
      │
      ▼
   build test matrix (test, seed)
      │
      ├─ riscv-dv: run_instr_gen.py → asm
      ├─ directed: use existing .S
      ▼
   compile_test.py → .bin / .hex
      │
      ▼
   run_rtl.py → simulator log
      │
      ▼
   check_logs.py → TestRunResult
      │
      ▼
   regr.log / regr_junit.xml / report.json

``run_regress.py`` 支持 ``--parallel`` ，通过 ``ProcessPoolExecutor`` 并发
执行多个 test/seed。每个测试有独立工作目录。

输入模式
------------------------------------------------------------------------------------------

单测模式：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --test riscv_arithmetic_basic_test \
     --seed 7 \
     --output build/arith_s7

testlist 模式：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --testlist dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml \
     --iterations 1 \
     --parallel 4 \
     --output build/nightly

directed testlist 模式会识别 ``config`` entry，并用
``directed_test_schema.py`` 展开为普通 test entry。

工作目录
------------------------------------------------------------------------------------------

每个 test/seed 的输出目录形如：

.. code-block:: text

   build/<run>/<test>_s<seed>/
   ├── gen.log
   ├── compile.log
   ├── <test>.bin
   ├── <test>.hex
   ├── sim_<test>_<seed>.log
   ├── result.yaml
   └── result.pkl

回归根目录还会生成：

* ``regr.log`` ：人类可读摘要。
* ``regr_junit.xml`` ：CI 可消费。
* ``report.json`` ：signoff.py 读取的结构化结果。

Cosim 策略
------------------------------------------------------------------------------------------

``build_sim_opts`` 会合并 testlist 的 ``sim_opts`` 与 CLI ``--sim-opts`` ，
并按 ``cosim`` 字段自动添加 plusarg：

* ``cosim: disabled`` → ``+disable_cosim=1``
* 其它或缺省 → ``+enable_cosim=1``

如果用户已经显式提供 ``+enable_cosim`` 或 ``+disable_cosim`` ，脚本不会再
追加。这样单测调试可以临时覆盖 testlist 的策略。

Sign-off Skip
------------------------------------------------------------------------------------------

``signoff.py`` 在运行 stage command 前设置环境变量
``EH2_SIGNOFF_MODE=1`` 。``run_regress.py`` 检测到该变量后会跳过 testlist
中 ``skip_in_signoff: true`` 的 entry，并打印跳过清单。

注意：``skip_in_signoff`` 只影响 sign-off 模式；普通 regression 或单测
仍可手动运行这些测试。

失败分类
------------------------------------------------------------------------------------------

``TestRunResult.failure_mode`` 用于区分失败阶段：

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - failure_mode
     - 含义
   * - ``GEN_ERROR`` / ``GEN_TIMEOUT`` / ``GEN_NO_ASM``
     - riscv-dv 生成失败。
   * - ``DIRECTED_ASM_MISSING``
     - directed testlist 指向的汇编不存在。
   * - ``COMPILE_ERROR`` / ``COMPILE_TIMEOUT``
     - RISC-V GCC 或 objcopy 失败。
   * - ``SIM_TIMEOUT``
     - RTL 仿真进程超时。
   * - ``UVM_ERROR`` / ``UVM_FATAL`` / ``MISMATCH``
     - ``check_logs.py`` 从仿真 log 判定失败。

排查时先看 ``failure_mode`` ，再打开对应阶段 log。

报告消费
------------------------------------------------------------------------------------------

``collect_results.py`` 可以从已有 result pickle/yaml 重新汇总结果；
``signoff.py`` 优先读取 stage 的 ``report.json`` 。这使得 gate-only 模式可以
在不重跑仿真的情况下评估已有结果：

.. code-block:: bash

   make signoff_gate PROFILE=full SIGNOFF_OUT=build/sf_full

回归维护准则
------------------------------------------------------------------------------------------

* testlist entry 必须包含 ``test``、``description``、``rtl_test`` 。
* 新增 ``cosim: disabled`` 必须有风险登记或 issue 说明。
* 大幅增加 ``iterations`` 前先确认单 seed 稳定。
* ``--fail-on-warnings`` 是 sign-off 行为；日常调试可先不用。
* 不要把工具链或仿真器路径硬编码进 testlist，统一放到 env 或 Makefile。

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页介绍的 Makefile target 或 Python 脚本入口是什么，默认 simulator 是否仍是 VCS？
2. 该流程产生哪些 build 目录、log、JSON、coverage database 或 HTML artifact？
3. VCS/URG 路径和 NC/IMC 备选路径在本页中是否被分开解释？
4. 失败时第一份应打开的日志是哪一个，第二步应检查哪个变量或 YAML 配置？
5. 本页中的 sign-off 数字是否仍为 9/9 PASS、102/104、LEC 31635/31635 和 LINE 95.05%？
