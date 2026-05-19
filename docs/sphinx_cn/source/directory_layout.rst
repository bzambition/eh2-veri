:orphan:

目录结构
==========================================================================================

本附录描述 ``/home/host/eh2-veri/`` 仓库的目录布局。条目按 **访问频次**
排序：日常修改频繁的 UVM 验证代码在前；自动生成或外部依赖的目录在后。

.. note::

   "访问频次" 反映的是 Phase 1–5 工业化整改期间的实际编辑分布，
   并不构成对未来工作的约束。具体每个目录的职责仍以 :term:`CONTEXT.md`
   与 ``docs/adr/`` 为准。

.. contents:: 本章导航
   :local:
   :depth: 2


顶层目录树
------------------------------------------------------------------------------------------

下列树由 ``find /home/host/eh2-veri -maxdepth 3 -type d`` 生成，
排除生成产物（``build/``、``out/``、``csrc/`` ）和 ``.git/`` ：

.. code-block:: text

   eh2-veri/
   ├── CLAUDE.md                       项目级 Claude Code 指令
   ├── CONTEXT.md                      领域语境（术语 + 架构 + 风险）
   ├── README.md                       顶层快速开始
   ├── Makefile                        统一构建入口（461 行）
   ├── env.mk                          构建变量（simulator / WAVES / COV）
   ├── env.sh                          shell 环境（PATH / RV_ROOT / GCC_PREFIX）
   ├── eh2_configs.yaml                RTL 配置 profile（default/minimal/dual_thread/ahb_lite）
   ├── eh2-uvm-implementation-plan.md  平台搭建蓝图（Ibex 对标）
   ├── PHASE1_PLAN.md                  Phase 1 路线图
   │
   ├── dv/                             验证源码主干（最常修改）
   │   ├── uvm/
   │   │   ├── bus_params_pkg/        AXI4 / AHB 参数包
   │   │   └── core_eh2/              EH2 UVM testbench 主体
   │   ├── cosim/                      Spike DPI 桥（C++）
   │   └── verilator/                  Verilator 备选流程
   │
   ├── docs/                           文档主干
   │   ├── adr/                        架构决策记录（5 篇）
   │   ├── agents/                     agent 流程文档
   │   ├── sphinx_cn/                  中文 Sphinx 手册（本文档源）
   │   ├── superpowers/                superpowers 技能记录
   │   └── cosim-correctness-analysis.md
   │
   ├── doc/                            旧版文档（保留，逐步迁移到 docs/）
   │   ├── architecture/
   │   ├── images/
   │   └── phase_reports/
   │
   ├── rtl/                            DUT 工程拷贝（snapshots）
   │   ├── design/                    EH2 RTL 源（从 RV_ROOT 同步）
   │   └── snapshots/                 配置后的 RTL 快照
   │
   ├── shared/                         共享 SystemVerilog 源
   │   └── rtl/                       AXI4 接口、参数、slave mem 模型
   │
   ├── tests/                          顶层 asm 资源
   │   └── asm/
   │       └── hex/                   预生成 hex（smoke 等）
   │
   ├── vendor/                         第三方子模块
   │   └── google_riscv-dv/           riscv-dv（受约随机指令生成器）
   │
   ├── .scratch/                       工作目录（feature / issue / snapshot）
   │   ├── platform-industrialization/  Phase 1–5 工业化整改
   │   ├── cosim-correctness/         cosim 正确性整改
   │   └── snapshots/                 Phase 完成快照 tar.gz
   │
   ├── .github/                        GitHub Actions（CI gate）
   │
   ├── build/                          仿真生成产物（.gitignore，可清空）
   ├── out/                            riscv-dv 生成的 asm/hex（可清空）
   └── csrc/                           VCS C 编译中间件（可清空）


``dv/uvm/core_eh2/`` — UVM 验证主干
------------------------------------------------------------------------------------------

这是平台 **最常修改** 的目录。所有 UVM testbench、env、agent、test、scripts
都在这里。布局对标 ``/home/host/ibex/dv/uvm/core_ibex/`` ：

.. code-block:: text

   dv/uvm/core_eh2/
   ├── tb/                             顶层 testbench
   │   ├── core_eh2_tb_top.sv         （1071 行）DUT 实例化 + 时钟复位 + AXI mem
   │   └── core_eh2_dut_signals.svh   probe 信号集中点
   │
   ├── env/                            UVM env 与环境接口
   │   ├── core_eh2_env.sv
   │   ├── core_eh2_env_cfg.sv
   │   ├── core_eh2_env_pkg.sv
   │   ├── core_eh2_scoreboard.sv
   │   ├── core_eh2_vseqr.sv          virtual sequencer
   │   ├── eh2_csr_if.sv              CSR probe interface
   │   ├── eh2_dut_probe_if.sv        DUT 内部信号 probe interface
   │   └── eh2_instr_monitor_if.sv    instruction monitor interface
   │
   ├── common/                         各 agent
   │   ├── axi4_agent/                AXI4 监视器（被动，4 port: IFU/LSU/SB/DMA）
   │   ├── trace_agent/               retired 指令 trace 监视器
   │   │   ├── eh2_trace_intf.sv
   │   │   ├── eh2_trace_monitor.sv
   │   │   ├── eh2_trace_seq_item.sv
   │   │   └── eh2_dut_probe_monitor.sv
   │   ├── cosim_agent/               Spike 协同仿真 agent
   │   │   ├── eh2_cosim_agent.sv
   │   │   ├── eh2_cosim_cfg.sv
   │   │   ├── eh2_cosim_scoreboard.sv  （769 行）
   │   │   ├── eh2_cosim_binary_loader.svh
   │   │   └── eh2_cosim_csr_preregister.svh
   │   ├── irq_agent/                 中断激励（active）
   │   ├── jtag_agent/                JTAG 调试（active）
   │   └── halt_run_agent/            MPC halt/run（active）
   │
   ├── tests/                          test 与 sequence 库
   │   ├── core_eh2_base_test.sv
   │   ├── core_eh2_test_lib.sv
   │   ├── core_eh2_test_pkg.sv
   │   ├── core_eh2_seq_lib.sv
   │   ├── core_eh2_new_seq_lib.sv
   │   ├── core_eh2_vseq.sv
   │   ├── core_eh2_report_server.sv
   │   └── asm/hex/                   预生成 hex 镜像
   │
   ├── directed_tests/                 定向测试
   │   ├── directed_testlist.yaml     定向 test 列表
   │   ├── cosim_testlist.yaml        cosim test 列表
   │   ├── eh2_macros.h               EH2 自定义 macro
   │   ├── custom_macros.h
   │   ├── link.ld                    链接脚本
   │   ├── gen_testlist.py
   │   └── README.md
   │
   ├── riscv_dv_extension/             riscv-dv 扩展
   │   └── （asm_program_gen / testlist 扩展）
   │
   ├── fcov/                           功能覆盖率
   │   ├── eh2_fcov_if.sv             （797 行）主 fcov interface
   │   ├── eh2_fcov_bind.sv           bind 入口
   │   ├── eh2_pmp_fcov_if.sv         PMP 子覆盖
   │   ├── eh2_csr_categories.svh
   │   └── cov_waivers/
   │
   ├── scripts/                        Python 自动化脚本
   │   ├── run_regress.py             回归入口
   │   ├── compile_tb.py / compile_test.py
   │   ├── run_rtl.py                 RTL 仿真
   │   ├── run_instr_gen.py / build_instr_gen.py  riscv-dv 调用
   │   ├── collect_results.py         结果汇总
   │   ├── check_logs.py              :term:`UVM_FATAL` 检测（含 banner overlap 容忍）
   │   ├── signoff.py                 sign-off 4-stage gate
   │   ├── directed_test_schema.py    testlist YAML schema
   │   ├── eh2_cmd.py                 命令构造器
   │   ├── eh2_sim.mk / riscvdv.mk    生成的 mk
   │   ├── render_config_template.py
   │   ├── report_lib/                结构化报告库
   │   └── tests/                     脚本自身的 pytest
   │
   ├── yaml/
   │   └── rtl_simulation.yaml        VCS / Xcelium / Questa 配置
   │
   ├── waivers/
   │   ├── coverage_waivers_xlm.tcl
   │   ├── aux_code.vRefine
   │   ├── unr.vRefine
   │   └── README.md
   │
   ├── Makefile                        子层 Makefile（106 行）
   ├── wrapper.mk                      命令包裹（处理 escape）
   ├── vcs.tcl                         VCS 启动 tcl
   ├── eh2_rtl.f / eh2_tb.f / eh2_shared.f / eh2_dv_cosim_dpi.f  filelist
   └── cover.cfg


``dv/cosim/`` — Spike DPI 桥
------------------------------------------------------------------------------------------

C++ 桥接代码，编译后产出 ``build/libcosim.so`` ：

.. code-block:: text

   dv/cosim/
   ├── cosim.h                  cosim 抽象接口
   ├── cosim_dpi.cc             SystemVerilog DPI 入口
   ├── cosim_dpi.svh            DPI 头文件（被 SV 端 import）
   ├── spike_cosim.cc           Spike ISS 适配实现
   └── spike_cosim.h

构建命令：

.. code-block:: bash

   make cosim                   # 单独构建 libcosim.so
   make NO_COSIM=1 ...          # 显式跳过 cosim（escape hatch）

详见 :doc:`cosim_scoreboard` 与 ADR ``docs/adr/0001-cosim-via-trace-and-probe.md`` 。


``rtl/`` 与 ``shared/`` — RTL 来源
------------------------------------------------------------------------------------------

EH2 RTL 不直接放在 ``eh2-veri/`` 内，而是从外部仓库 ``$RV_ROOT``
（``/home/host/Cores-VeeR-EH2`` ）同步：

* ``rtl/design/`` ：当前激活的 EH2 RTL 拷贝
* ``rtl/snapshots/`` ：按 ``eh2_configs.yaml`` profile 渲染后的快照
* ``shared/rtl/`` ：验证侧自有的 SystemVerilog 资源
  （AXI4 接口、参数、slave 内存模型）

修改 RTL **不应** 在 ``rtl/`` 内进行——上游仍是 ``$RV_ROOT`` 。


``vendor/`` — 第三方子模块
------------------------------------------------------------------------------------------

.. code-block:: text

   vendor/
   └── google_riscv-dv/         受约随机指令生成器（vendor 子模块）

``vendor/google_riscv-dv/`` 是 ``/home/host/riscv-dv/`` 的子模块拷贝，
用 ``dist_control_mode`` + ``directed_instr_*`` 控制指令分布。
EH2 自有 stream 在 ``dv/uvm/core_eh2/riscv_dv_extension/`` 下扩展，
通过 ``post_randomize`` 钩子 → ``gen_instr`` 桥接（详见 ADR 与
issue ``02-trace-monitor-sample-wb`` ）。


``docs/`` — 文档主干
------------------------------------------------------------------------------------------

.. code-block:: text

   docs/
   ├── adr/                                架构决策记录
   │   ├── 0001-cosim-via-trace-and-probe.md
   │   ├── 0002-axi4-passive-monitoring.md
   │   ├── 0003-num-threads-cosim-scope.md
   │   ├── 0004-rtl-rvfi-equivalent-trace.md
   │   └── 0005-spike-cosim-store-wider-wstrb.md
   │
   ├── agents/                             agent 流程
   │   ├── domain.md                      领域语境入口
   │   ├── issue-tracker.md               本地 markdown issue 协议
   │   └── triage-labels.md               5 个 triage 角色
   │
   ├── sphinx_cn/                          中文 Sphinx 手册
   │   └── source/
   │       ├── conf.py
   │       ├── index.rst
   │       ├── overview.rst
   │       └── ...                        其余章节
   │
   ├── superpowers/
   │   └── plans/
   │
   └── cosim-correctness-analysis.md       cosim 正确性分析（19 KB）

老版 ``doc/`` 目录保留为只读，逐步迁移到 ``docs/`` 。


``.scratch/`` — feature / issue / 快照
------------------------------------------------------------------------------------------

按 :term:`feature-slug` 组织：

.. code-block:: text

   .scratch/
   ├── platform-industrialization/
   │   ├── PHASE1_PROGRESS.md             cosim 闭环
   │   ├── PHASE2_PROGRESS.md             结构整理
   │   ├── PHASE3_PROGRESS.md             流程修复
   │   ├── PHASE3_SWEEP_PROGRESS.md       sweep 完成
   │   ├── README.md
   │   └── issues/
   │       ├── 01-rtl-add-rvfi-equivalent.md
   │       ├── 02-trace-monitor-sample-wb.md
   │       ├── 03-scoreboard-simplify.md
   │       ├── 04-probe-monitor-keep-async.md
   │       ├── 05-testlist-enable-cosim.md
   │       ├── 06-signoff-full-pass.md
   │       ├── 40-axi4-active-driver.md
   │       ├── 41-multi-hart-cosim.md
   │       └── 42-formal-bridge.md
   │
   ├── cosim-correctness/
   │   └── issues/
   │       ├── 01-cosim-smoke-test.md
   │       ├── 02-single-alu-cosim-test.md
   │       ├── 03-load-store-cosim-test.md
   │       ├── 04-dual-issue-ordering-test.md
   │       ├── 05-interrupt-cosim-test.md
   │       ├── 06-per-test-cosim-toggle.md
   │       ├── 07-csr-suppression.md
   │       ├── 08-eh2-csr-fixup-design.md
   │       ├── 09-64bit-axi-verify.md
   │       └── 10-num-threads-constraint.md
   │
   └── snapshots/                          各 Phase 完成快照 tar.gz

详见 :doc:`issue_tracker` 。


生成产物与可清空目录
------------------------------------------------------------------------------------------

下列目录 **不入库** （``.gitignore`` ），任何时候都可以删除并重新生成：

.. list-table::
   :header-rows: 1
   :widths: 18 30 52

   * - 目录
     - 内容
     - 重建命令
   * - ``build/``
     - 仿真目标（compile.log、simv、libcosim.so、results）
     - ``make tb`` / ``make cosim`` / ``make signoff ...``
   * - ``out/``
     - riscv-dv 生成的 asm 与 hex
     - ``make run TEST=<test>`` （自动触发）
   * - ``csrc/``
     - VCS C 编译中间件（未带前缀的 _csrc 残留）
     - VCS 自动重建
   * - ``ucli.key`` / ``tr_db.log``
     - VCS 运行时日志
     - 仿真自动重建（不需要保留）

.. warning::

   ``build/`` 在 Phase 1 之前曾累积 7.7 GB 残留。**当前已清理** ，
   ``.gitignore`` 也已加上规则。如再发现 ``build/`` 进入 git 历史，
   立即用 ``git rm --cached`` 清理，并补 ``.gitignore`` 。


外部依赖路径
------------------------------------------------------------------------------------------

下列路径在仓库 **之外** ，但被 ``env.sh`` 引用：

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 环境变量
     - 路径
   * - ``$RV_ROOT``
     - ``/home/host/Cores-VeeR-EH2``
   * - ``$GCC_PREFIX``
     - ``/home/host/gcc-riscv64-unknown-elf``
   * - ``$QEMU_BIN``
     - ``/home/host/eh2-verification/qemu-eh2/build/qemu-system-riscv32``
   * - ``$EH2_VENDOR_ROOT``
     - ``$EH2_VERIF_ROOT/vendor``

外部参考实现路径（**只读** 参考，不修改）：

* ``/home/host/ibex/dv/uvm/core_ibex/`` — Ibex 验证平台（对标蓝本）
* ``/home/host/spike-cosim/`` — Spike ISS 上游
* ``/home/host/riscv-dv/`` — riscv-dv 上游
* ``/home/host/eh2-verification/`` — 姐妹项目（指令级 + QEMU 协同）

详见 :doc:`references` 。


访问频次速查
------------------------------------------------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 18 62

   * - 频次
     - 目录
     - 典型动作
   * - **每天**
     - ``dv/uvm/core_eh2/``
     - 改 env、agent、scoreboard、test、scripts
   * - **每天**
     - ``dv/cosim/``
     - 改 Spike DPI、CSR fixup
   * - **每周**
     - ``docs/adr/``、``docs/agents/``、``CONTEXT.md``
     - 沉淀决策、更新术语
   * - **每周**
     - ``.scratch/<feature>/issues/``
     - 新增 / triage / 关闭 issue
   * - **按需**
     - ``rtl/``、``shared/``
     - 仅在 RTL 加 RVFI 等价信号、修 BE 语义时
   * - **按需**
     - ``vendor/``
     - 子模块升级
   * - **从不**
     - ``build/``、``out/``、``csrc/``
     - 仅生成与清空，不直接编辑

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
