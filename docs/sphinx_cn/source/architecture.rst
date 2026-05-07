平台体系结构
============

本章描述 EH2 UVM 验证平台的顶层结构：组件分层、目录组织、关键数据通路、
Spike DPI 协同仿真桥架构、riscv-dv 集成方式，以及与 Ibex 验证平台的对照。

顶层组件分层
------------

平台从顶向下分为 4 层。每一层只能依赖更底层，反向依赖通过 UVM
配置数据库或 SystemVerilog 接口跨越。

.. code-block:: text

   ┌─────────────────────────────────────────────────────────────┐
   │  Test 层  (dv/uvm/core_eh2/tests/)                          │
   │    core_eh2_base_test  /  core_eh2_cosim_test  / ...        │
   └────────────────────────────┬────────────────────────────────┘
                                │ uvm_config_db (env_cfg)
   ┌────────────────────────────▼────────────────────────────────┐
   │  Env 层  (dv/uvm/core_eh2/env/ + common/cosim_agent/)       │
   │    core_eh2_env  →  cosim_scoreboard (769)                  │
   │                  →  functional coverage (eh2_fcov_if 797)   │
   └────────────────────────────┬────────────────────────────────┘
                                │ analysis ports / TLM
   ┌────────────────────────────▼────────────────────────────────┐
   │  Agent 层  (dv/uvm/core_eh2/common/)                        │
   │    axi4 (483)  jtag (724)  irq (324)  halt_run (273)        │
   │    trace (608) cosim (379)                                  │
   └────────────────────────────┬────────────────────────────────┘
                                │ virtual interface
   ┌────────────────────────────▼────────────────────────────────┐
   │  TB 顶层  (dv/uvm/core_eh2/tb/core_eh2_tb_top.sv, 1071)     │
   │    时钟/复位 + DUT 例化 + interface bind + DPI cosim init   │
   └─────────────────────────────────────────────────────────────┘
                                │
   ┌────────────────────────────▼────────────────────────────────┐
   │  DUT  (rtl/ → /home/host/Cores-VeeR-EH2)                    │
   │    eh2_swerv_wrapper  →  eh2_swerv  →  9 级流水             │
   └─────────────────────────────────────────────────────────────┘

各层职责一览：

.. list-table::
   :header-rows: 1
   :widths: 18 30 52

   * - 层
     - 关键文件
     - 职责
   * - Test
     - ``core_eh2_base_test.sv`` / ``core_eh2_test_lib.sv``
     - 选择 sequence、注入 sim_opts、设置 timeout
   * - Env
     - ``core_eh2_env.sv`` / ``core_eh2_env_cfg.sv``
     - 构造 agent、连接 scoreboard、订阅覆盖率
   * - Scoreboard
     - ``common/cosim_agent/eh2_cosim_scoreboard.sv`` （769 行）
     - 拉 RTL trace 与 Spike trace 做逐拍校验
   * - Agent
     - ``common/<bus>_agent/`` 下统一格式 ``eh2_*``
     - 协议级激励 / 监控 / coverage hook
   * - TB top
     - ``tb/core_eh2_tb_top.sv`` （1071 行）
     - 例化 DUT 与 interface，初始化 DPI

目录组织
--------

仓库根目录在 ``/home/host/eh2-veri/``，关键子树如下。

.. code-block:: text

   eh2-veri/
   ├── env.sh                       # 环境初始化（source 后即可用）
   ├── Makefile                     # 顶层 dispatcher（compile / run / signoff）
   ├── dv/
   │   ├── uvm/
   │   │   └── core_eh2/            # 主 UVM testbench
   │   │       ├── tb/              # 顶层（core_eh2_tb_top.sv 1071 行）
   │   │       ├── env/             # env_cfg / env / scoreboard / vseqr
   │   │       │                    #   + eh2_csr_if.sv / eh2_dut_probe_if.sv
   │   │       │                    #   / eh2_instr_monitor_if.sv
   │   │       ├── common/          # 复用 agent
   │   │       │   ├── axi4_agent/      (483)
   │   │       │   ├── jtag_agent/      (724, eh2_* 前缀)
   │   │       │   ├── irq_agent/       (324)
   │   │       │   ├── halt_run_agent/  (273)
   │   │       │   ├── trace_agent/     (probe + trace + dut_probe_monitor)
   │   │       │   └── cosim_agent/     (eh2_cosim_scoreboard 769)
   │   │       ├── tests/           # 测试库（base / cosim / new / vseq）
   │   │       │   └── asm/         # 平台自带汇编（cosim_smoke / cosim_alu / ...）
   │   │       ├── fcov/            # functional coverage（eh2_fcov_if.sv 797）
   │   │       ├── riscv_dv_extension/  # riscv-dv hook（testlist + override）
   │   │       ├── directed_tests/  # directed_testlist.yaml / cosim_testlist.yaml
   │   │       ├── waivers/         # lint / cov waiver
   │   │       ├── yaml/            # 通用 testlist schema
   │   │       └── scripts/         # Python 框架（run_regress / signoff / ...）
   │   ├── cosim/                   # Spike DPI 桥
   │   │   ├── cosim.h              # 抽象接口
   │   │   ├── spike_cosim.{h,cc}   # Spike 适配
   │   │   ├── cosim_dpi.{cc,svh}   # DPI 导出 / 导入
   │   └── verilator/               # Verilator 备用流程
   ├── rtl/                         # 链接到 /home/host/Cores-VeeR-EH2
   ├── shared/rtl/                  # 共享 RTL 与 snapshot defines
   ├── tests/asm/                   # 平台级 hand-written 测试（smoke.S / nop.S）
   ├── vendor/google_riscv-dv/      # riscv-dv 子模块
   ├── docs/
   │   ├── adr/                     # 5 条架构决策记录
   │   ├── sphinx_cn/               # 本手册
   │   └── agents/                  # agent skill 索引
   ├── .scratch/                    # feature 文件夹与 issue tracker
   ├── build/                       # 编译/运行产物（git-ignored）
   └── out/                         # ``make run GOAL=...`` 产物

.. note::

   ``dv/uvm/core_eh2/common/eh2_cosim_agent/`` 当前为空目录，留给未来扩展。
   实际 cosim 实现在 ``common/cosim_agent/``（注意目录名没有 ``eh2_``
   前缀，这是 Phase 2 命名规整时保留的兼容例外）。

数据通路
--------

平台的核心数据通路是 **RTL → trace_pkt → scoreboard ↔ Spike DPI**。下图按
时间顺序展示 cosim 的一次比对：

.. code-block:: text

   ① RTL retire
        │  trace_intf 采样 wb_addr/wb_data/pc/insn
        ▼
   ② eh2_trace_monitor (160 行)         ──── analysis port ────┐
        │  打包 eh2_trace_seq_item                              │
        ▼                                                       ▼
   ③ eh2_dut_probe_monitor (118 行)                  eh2_cosim_scoreboard
        │  仅采集异步 wb hint：nb_load / div_done             (769 行)
        │                                                       │
        └──────────────── analysis port ─────────────────► hint │
                                                                 │
   ④ Spike step (DPI)  ──◄── cosim_dpi.cc  ◄── DPI import ◄──────┘
        │  返回 retired 指令 + rd_addr/rd_wdata + mem_w
        ▼
   ⑤ Scoreboard 比对：PC / insn / rd / mem 全等
        │  失败：UVM_FATAL  /  成功：递增 mismatch=0

关键观察：

* RTL 提供 **同步的 wb 数据** （``rd_addr``、``rd_wdata`` 已写入 trace 包，
  详见 ADR-0004），scoreboard 不再需要重建写回时序。
* **异步通道** 仅通过 ``dut_probe_monitor`` 提示 scoreboard：
  ``nb_load_done``、``div_done`` 等长延迟事件何时落地（详见 ADR-0001）。
* Spike DPI 同步前进，每条 RTL retire 触发一次 ``riscv_cosim_step``，
  失败立即抛 ``UVM_FATAL``，因此 cosim mismatch 不会被淹没。

Spike DPI 协同仿真桥
--------------------

cosim 桥位于 ``dv/cosim/``，由 4 个文件组成：

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - 文件
     - 职责
   * - ``cosim.h``
     - 抽象基类，仅暴露 ``init / load / step / get_state`` 等纯虚接口
   * - ``spike_cosim.{h,cc}``
     - Spike-specific 适配；包装 ``processor_t`` 单步、``fixup_csr``
       注册 EH2 自定义 CSR、处理双发射 retire 顺序
   * - ``cosim_dpi.cc``
     - DPI 导出函数 ``riscv_cosim_init / step / load_elf / set_csr / ...``
   * - ``cosim_dpi.svh``
     - SystemVerilog 侧 ``import "DPI-C"`` 头

构建产物 ``build/libcosim.so`` 在 ``compile_vcs`` 阶段被 **强依赖**
（``Makefile`` ``COMPILE_LIBCOSIM_DEP``）：缺失时编译直接报错，避免
``simv`` 进入运行期才抛 ``DPI-DIFNF``。如果机器上未安装 spike-cosim，
可显式 ``make compile NO_COSIM=1`` 跳过链接（仅 ``+disable_cosim=1``
模式下可用）。

.. warning::

   ``SPIKE_INSTALL`` 默认指向 ``/home/host/spike-cosim/install``。环境与默认
   不一致时，请通过 ``make cosim SPIKE_DIR=<path>`` 覆盖。Spike 编译器
   ``SPIKE_CXX`` 默认锁定到 Vivado GCC 6.2.0，用于与 Spike 二进制 ABI 对齐。

riscv-dv 集成
-------------

平台不 fork riscv-dv，而是以 git submodule 形式锁定到
``vendor/google_riscv-dv/``。集成点全部集中在
``dv/uvm/core_eh2/riscv_dv_extension/``：

.. list-table::
   :header-rows: 1
   :widths: 32 68

   * - 文件
     - 职责
   * - ``testlist.yaml``
     - 43 个 riscv-dv entry，其中 11 个 ``skip_in_signoff``；每个 entry
       指定 ``rtl_test``、``gen_opts``、``sim_opts``、``cosim`` 等策略字段
   * - ``riscv_core_setting.sv``
     - 配置 EH2 ISA 字段（``XLEN=32``、``supported_isa = RV32IMAC``、
       ``support_pmp = 1``、``num_harts = 1`` 默认）
   * - ``eh2_asm_program_gen.sv``
     - 替换默认 program gen，注入 EH2 启动序列与 mailbox 退出
   * - ``eh2_directed_instr_lib.sv``
     - EH2 自定义 directed scene（dual-issue 矩阵、PMP 边界、bitmanip）
   * - ``eh2_debug_triggers_overrides.sv``
     - 调试触发器覆盖，避免 riscv-dv 默认假设与 EH2 实际不匹配
   * - ``user_extension.svh``
     - SV 编译时的扩展挂钩

调用顺序：``run_regress.py --testlist riscv_dv_extension/testlist.yaml``
→ ``run_instr_gen.py``（包装 riscv-dv 的 ``run.py``）→ 生成 ``.S`` →
``riscv32-unknown-elf-gcc`` 编译为 ELF → ``compile_test.py`` 转 hex →
``run_rtl.py`` 启动 ``simv``。

环境配置（``env.sh``）
----------------------

进入仓库后第一步 ``source env.sh``，会建立以下变量：

.. list-table::
   :header-rows: 1
   :widths: 24 18 58

   * - 变量
     - 默认
     - 用途
   * - ``EH2_VERIF_ROOT``
     - 仓库根
     - 被 Python 与 Make 文件用作绝对路径锚点
   * - ``RV_ROOT``
     - ``/home/host/Cores-VeeR-EH2``
     - VeeR EH2 RTL 源
   * - ``GCC_PREFIX``
     - ``/home/host/gcc-riscv64-unknown-elf``
     - RISC-V 工具链根；``$PATH`` 自动追加 ``${GCC_PREFIX}/bin``
   * - ``QEMU_BIN``
     - ``eh2-verification`` 旁路 QEMU
     - 仅用于 cross-validate 烟囱（非默认路径）
   * - ``EH2_SIMULATOR``
     - ``vcs``
     - 选择 ``vcs`` / ``xlm`` / ``questa`` 流水
   * - ``ABI``
     - ``-mabi=ilp32 -march=rv32imac``
     - 工具链编译选项
   * - ``EH2_DV_ROOT`` / ``EH2_UVM_ROOT`` / ``EH2_SHARED_ROOT`` / ``EH2_VENDOR_ROOT``
     - 派生
     - 各子树根，便于脚本相对引用

与 Ibex 验证平台的对照
----------------------

平台原型来自 ``ibex/dv/uvm/core_ibex/``，下表对照保留、修改与新增点。

.. list-table::
   :header-rows: 1
   :widths: 28 36 36

   * - 维度
     - Ibex 原型
     - EH2 平台差异
   * - 顶层 TB
     - ``core_ibex_tb_top.sv``
     - ``core_eh2_tb_top.sv``，新增双线程时钟域与 EH2 PIC 接口
   * - cosim 路径
     - DPI Spike，单线程
     - 同 DPI Spike，但 trace 包内嵌 ``rd_addr/rd_wdata`` （RVFI 等价，
       ADR-0004），scoreboard 不重建 wb 时序
   * - testlist
     - ``riscv_dv_extension/testlist.yaml``
     - 同位置；新增 ``skip_in_signoff: true`` 字段供 sign-off 显式忽略
   * - functional coverage
     - ``ibex_fcov_if.sv``
     - ``eh2_fcov_if.sv`` 797 行，新增 dual-issue / PIC / EH2 自定义 CSR
   * - 命名约定
     - ``ibex_*`` 前缀
     - 全部改为 ``eh2_*``（少数文件以 ``core_eh2_*`` 与 UVM test 类名对齐）

UVM 命名约定
~~~~~~~~~~~~

* **agent / interface / monitor / driver**：``eh2_<protocol>_*``，例如
  ``eh2_jtag_intf.sv`` / ``eh2_irq_driver.sv``。
* **env / scoreboard / cfg / vseqr**：``core_eh2_<role>``，与 UVM 类名
  保持一致，例如 ``core_eh2_env.sv`` / ``core_eh2_vseqr.sv``。
* **functional coverage**：``eh2_<aspect>_fcov_if.sv``，例如
  ``eh2_pmp_fcov_if.sv``。
* **测试类**：``core_eh2_<purpose>_test``（``core_eh2_base_test`` /
  ``core_eh2_cosim_test``）。

env/ 与 common/ 的归属规则
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* 与 EH2 强绑定、不可在其他 core 复用 → ``env/``
  （``eh2_csr_if.sv`` 持有 EH2 自定义 CSR 列表）。
* 协议层、接口可被其他 core 复用 → ``common/<protocol>_agent/``
  （``axi4_agent``、``jtag_agent``、``irq_agent`` 都按此放置）。
* cosim 桥与 scoreboard：因为 Spike 桥本身是 RV32 通用的，但 EH2
  fixup 已经渗透进 ``eh2_cosim_scoreboard.sv``，整体放在
  ``common/cosim_agent/`` 而非 ``env/``。

.. seealso::

   * :doc:`testbench` — ``core_eh2_tb_top.sv`` 的逐字段说明。
   * :doc:`environment` — ``core_eh2_env_cfg`` 与 env 构造细节。
   * :doc:`cosim_scoreboard` — Spike DPI 比对算法与 mismatch 处理。
   * :doc:`architecture_decisions` — ADR 0001-0005 全文。
