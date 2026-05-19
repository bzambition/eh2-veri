.. _appendix_f_scripts_yaml_configs:
.. _appendix_f_scripts/yaml_configs:

YAML 与覆盖率配置文件
=====================

:status: draft
:source: eh2_configs.yaml, dv/uvm/core_eh2/yaml/rtl_simulation.yaml, dv/uvm/core_eh2/directed_tests/directed_testlist.yaml, dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml, dv/uvm/core_eh2/waivers/cosim-disabled.yaml
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本章解释 EH2-Veri 中直接参与构建、仿真、directed test、cosim proof test 和
cosim-disabled waiver gate 的 YAML 文件。所有字段说明均来自上方 ``:commit:``
对应源码；代码片段按逻辑切片，每段不超过 30 行。

§1 YAML 文件总览
--------------------------------------------------------------------------------

EH2-Veri 的 YAML 文件分成四类：DUT 参数 profile、模拟器命令模板、directed/cosim
测试列表，以及 cosim-disabled waiver 列表。调用关系如下：

.. code-block:: text

   Makefile / wrapper.mk
      |
      +-- metadata.py
      |      |
      |      +-- eh2_configs.yaml
      |      +-- directed_testlist.yaml
      |      +-- cosim_testlist.yaml
      |
      +-- run_rtl.py / riscvdv_interface.py
      |      |
      |      +-- dv/uvm/core_eh2/yaml/rtl_simulation.yaml
      |
      +-- signoff.py
             |
             +-- directed_testlist.yaml
             +-- cosim_testlist.yaml
             +-- dv/uvm/core_eh2/waivers/cosim-disabled.yaml

当前源码事实：

* `eh2_configs.yaml` 是 YAML mapping，包含 4 个顶层 profile：
  `default`、`minimal`、`dual_thread`、`ahb_lite`。
* `rtl_simulation.yaml` 是 simulator mapping，包含 `vcs`、`xlm`、`questa`
  三个 simulator key，每个 key 下有 `compile` 和 `sim` 阶段。
* `directed_testlist.yaml` 是 YAML list，共 43 个条目，其中 3 个是 config 条目，
  40 个是 test 条目。
* `cosim_testlist.yaml` 是 YAML list，共 8 个条目，其中 1 个是 config 条目，
  7 个是 test 条目。
* `cosim-disabled.yaml` 是 YAML list，共 9 个 waiver 条目。

§2 ``eh2_configs.yaml`` — DUT 参数 profile
--------------------------------------------------------------------------------

职责：为 EH2 DUT 构建提供 profile 名称、说明和 `parameters` 字段。脚本侧通过
`eh2_cmd.py` 读取该文件，并把整数参数渲染成 simulator `+define+KEY=VALUE`。

关键代码（``eh2_configs.yaml:L1-L17``）：

.. code-block:: yaml

   # EH2 Configuration Profiles
   # This file defines different EH2 configurations for verification.
   # Each profile specifies the parameters to use when building the DUT.

   default:
     description: "Default EH2 configuration (AXI4, single-thread, full features)"
     parameters:
       # Threading
       NUM_THREADS: 1
       # Bus
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       BUILD_AXI_NATIVE: 1
       LSU_BUS_TAG: 4
       IFU_BUS_TAG: 4
       SB_BUS_TAG: 1
       DMA_BUS_TAG: 1

逐段解释：

* 第 L1-L3 行：文件注释说明该 YAML 定义 EH2 verification 使用的配置 profile，
  每个 profile 指定构建 DUT 时使用的参数。
* 第 L5-L7 行：`default` 是一个顶层 profile，含 `description` 和 `parameters`
  两个字段。
* 第 L8-L17 行：`default.parameters` 首先设置 thread 和 bus 相关参数：
  `NUM_THREADS=1`、`BUILD_AXI4=1`、`BUILD_AHB_LITE=0`、`BUILD_AXI_NATIVE=1`，
  以及 LSU/IFU/SB/DMA bus tag 数值。

接口关系：

* 被调用：`dv/uvm/core_eh2/scripts/eh2_cmd.py:get_config()`。
* 调用：无；这是数据文件。
* 共享状态：为 build command 提供 `parameters` 字典。

关键代码（``eh2_configs.yaml:L18-L38``）：

.. code-block:: yaml

       # DCCM
       DCCM_ENABLE: 1
       DCCM_SIZE: 64
       # ICCM
       ICCM_ENABLE: 1
       ICCM_SIZE: 64
       # ICache
       ICACHE_ENABLE: 1
       ICACHE_SIZE: 32
       # ISA Extensions
       ATOMIC_ENABLE: 1
       BITMANIP_ZBA: 1
       BITMANIP_ZBB: 1
       BITMANIP_ZBC: 1
       BITMANIP_ZBS: 1
       # Interrupts
       PIC_TOTAL_INT: 127
       # Branch Predictor
       BHT_SIZE: 512
       BTB_SIZE: 512
       RET_STACK_SIZE: 4

逐段解释：

* 第 L18-L26 行：`default` profile 打开 DCCM、ICCM 和 ICache，并分别给出
  `DCCM_SIZE=64`、`ICCM_SIZE=64`、`ICACHE_SIZE=32`。
* 第 L27-L32 行：`ATOMIC_ENABLE` 和四个 bitmanip 子扩展 `ZBA/ZBB/ZBC/ZBS`
  均置 1。
* 第 L33-L38 行：`PIC_TOTAL_INT=127`，branch predictor 参数包含 `BHT_SIZE=512`、
  `BTB_SIZE=512` 和 `RET_STACK_SIZE=4`。

接口关系：

* 被调用：`eh2_cmd.get_isas_for_config()` 会读取 bitmanip 参数来构造 ISA 字符串。
* 调用：无。
* 共享状态：为 simulator defines 和 ISA 字符串生成提供参数。

关键代码（``eh2_configs.yaml:L40-L56``）：

.. code-block:: yaml

   minimal:
     description: "Minimal EH2 configuration (no ICache, no DCCM, few interrupts)"
     parameters:
       NUM_THREADS: 1
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       DCCM_ENABLE: 0
       ICCM_ENABLE: 0
       ICACHE_ENABLE: 0
       ATOMIC_ENABLE: 0
       BITMANIP_ZBA: 0
       BITMANIP_ZBB: 0
       BITMANIP_ZBC: 0
       BITMANIP_ZBS: 0
       PIC_TOTAL_INT: 16
       BHT_SIZE: 64
       BTB_SIZE: 64

逐段解释：

* 第 L40-L42 行：`minimal` profile 的说明写明关闭 ICache 和 DCCM，并减少中断数。
* 第 L43-L48 行：thread 和 bus 仍为单线程 AXI4；DCCM、ICCM、ICache 均关闭。
* 第 L49-L53 行：atomic 和四个 bitmanip 子扩展都关闭。
* 第 L54-L56 行：`PIC_TOTAL_INT` 降到 16，`BHT_SIZE` 和 `BTB_SIZE` 降到 64。

接口关系：

* 被调用：用户通过 `CONFIG=minimal` 或 `EH2_CONFIG=minimal` 选择该 profile。
* 调用：无。
* 共享状态：为小配置构建提供参数集合。

关键代码（``eh2_configs.yaml:L58-L75``）：

.. code-block:: yaml

   dual_thread:
     description: "Dual-thread EH2 configuration"
     parameters:
       NUM_THREADS: 2
       BUILD_AXI4: 1
       BUILD_AHB_LITE: 0
       DCCM_ENABLE: 1
       DCCM_SIZE: 64
       ICCM_ENABLE: 1
       ICCM_SIZE: 64
       ICACHE_ENABLE: 1
       ICACHE_SIZE: 32
       ATOMIC_ENABLE: 1
       BITMANIP_ZBA: 1
       BITMANIP_ZBB: 1
       BITMANIP_ZBC: 1
       BITMANIP_ZBS: 1
       PIC_TOTAL_INT: 127

逐段解释：

* 第 L58-L61 行：`dual_thread` profile 将 `NUM_THREADS` 设为 2。
* 第 L62-L69 行：bus 仍为 AXI4，DCCM、ICCM、ICache 均打开，并保留对应 size。
* 第 L70-L75 行：atomic、bitmanip 子扩展和 PIC 中断数量与 `default` 保持打开状态。

接口关系：

* 被调用：metadata 中的 `md.eh2_config` 可保存该 profile 名称。
* 调用：无。
* 共享状态：为双线程配置构建提供参数集合。

关键代码（``eh2_configs.yaml:L77-L94``）：

.. code-block:: yaml

   ahb_lite:
     description: "AHB-Lite bus configuration"
     parameters:
       NUM_THREADS: 1
       BUILD_AXI4: 0
       BUILD_AHB_LITE: 1
       DCCM_ENABLE: 1
       DCCM_SIZE: 64
       ICCM_ENABLE: 1
       ICCM_SIZE: 64
       ICACHE_ENABLE: 1
       ICACHE_SIZE: 32
       ATOMIC_ENABLE: 1
       BITMANIP_ZBA: 1
       BITMANIP_ZBB: 1
       BITMANIP_ZBC: 1
       BITMANIP_ZBS: 1
       PIC_TOTAL_INT: 127

逐段解释：

* 第 L77-L82 行：`ahb_lite` profile 明确关闭 `BUILD_AXI4`，打开
  `BUILD_AHB_LITE`。
* 第 L83-L88 行：DCCM、ICCM 和 ICache 保持打开，并设置 size。
* 第 L89-L94 行：atomic、bitmanip 子扩展和 PIC 中断数量保持打开状态。

接口关系：

* 被调用：`eh2_cmd.get_config("ahb_lite")` 可取回该 profile。
* 调用：无。
* 共享状态：为 AHB-Lite bus 配置构建提供参数集合。

关键代码（``dv/uvm/core_eh2/scripts/eh2_cmd.py:L13-L27``）：

.. code-block:: python

   def get_config(config_name: str) -> Dict:
       """Return one EH2 configuration from eh2_configs.yaml."""
       cfg_path = setup_imports._EH2_ROOT / "eh2_configs.yaml"
       with open(cfg_path, "r", encoding="utf-8") as f:
           configs = yaml.safe_load(f) or {}
       if config_name not in configs:
           raise KeyError(
               "Unknown EH2 config '{}'; available: {}".format(
                   config_name, ", ".join(sorted(configs))))
       params = dict(configs[config_name].get("parameters", {}) or {})
       return {
           "name": config_name,
           "description": configs[config_name].get("description", ""),
           "parameters": params,
       }

逐段解释：

* 第 L15-L17 行：调用者传入 `config_name` 后，函数固定读取仓库根目录下的
  `eh2_configs.yaml`，用 `yaml.safe_load()` 解析。
* 第 L18-L21 行：请求的 profile 不存在时抛出 `KeyError`，错误文本列出可用 profile。
* 第 L22-L27 行：返回值保留 profile 名称、说明和 `parameters` 字典。

接口关系：

* 被调用：`render_compile_defines()` 和命令行入口。
* 调用：`yaml.safe_load()`。
* 共享状态：读 `/home/host/eh2-veri/eh2_configs.yaml`。

关键代码（``dv/uvm/core_eh2/scripts/eh2_cmd.py:L30-L55``）：

.. code-block:: python

   def get_isas_for_config(cfg: Dict) -> Tuple[str, str]:
       """Return GCC and ISS ISA strings for one EH2 configuration."""
       params = cfg.get("parameters", {})
       base = "rv32imac"
       bitmanip = [
           name for name, enabled in [
               ("zba", params.get("BITMANIP_ZBA", 0)),
               ("zbb", params.get("BITMANIP_ZBB", 0)),
               ("zbc", params.get("BITMANIP_ZBC", 0)),
               ("zbs", params.get("BITMANIP_ZBS", 0)),
           ]
           if int(enabled)
       ]
       if bitmanip:
           return (base + "_zba_zbb_zbc_zbs", base + "_" + "_".join(bitmanip))
       return (base, base)

逐段解释：

* 第 L32-L40 行：函数只读取 `BITMANIP_ZBA/ZBB/ZBC/ZBS` 四个参数来构造扩展列表。
* 第 L43-L44 行：只要至少一个 bitmanip 参数为真，GCC ISA 固定返回
  `rv32imac_zba_zbb_zbc_zbs`，ISS ISA 使用实际开启的 bitmanip 名称拼接。
* 第 L45 行：没有 bitmanip 扩展时，GCC 和 ISS ISA 都返回 `rv32imac`。
* 第 L48-L55 行：`render_compile_defines()` 会遍历 `parameters` 中的整数值，并
  渲染为 `+define+KEY=VALUE`。

接口关系：

* 被调用：`eh2_cmd.py` 的命令行入口和其它构建脚本。
* 调用：`get_config()`。
* 共享状态：读取 `parameters` 中的 integer 参数。

§3 ``rtl_simulation.yaml`` — simulator 命令模板
--------------------------------------------------------------------------------

职责：定义 VCS、Xcelium 和 Questa 的 compile/sim 命令模板，以及 coverage、wave、
cosim 选项模板。模板中的 `<...>` 变量由 Python 脚本替换。

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L1-L7``）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 RTL Simulation Configuration
   #
   # Defines compile and simulation commands for each simulator.
   # Uses template variables: <tb_dir>, <build_dir>, <seed>, <binary>,
   # <rtl_test>, <sim_opts>, <cov_opts>, <wave_opts>

逐段解释：

* 第 L1 行：文件声明 Apache-2.0 SPDX。
* 第 L2-L4 行：注释说明该 YAML 定义每个 simulator 的 compile 和 simulation
  命令。
* 第 L5-L6 行：注释列出模板变量 `<tb_dir>`、`<build_dir>`、`<seed>`、
  `<binary>`、`<rtl_test>`、`<sim_opts>`、`<cov_opts>`、`<wave_opts>`。

接口关系：

* 被调用：`run_rtl.py`、`riscvdv_interface.py` 和 `eh2_sim.mk` 相关 flow。
* 调用：无。
* 共享状态：提供 simulator 命令模板。

§3.1 ``vcs`` compile/sim 模板
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L11-L29``）：

.. code-block:: yaml

   vcs:
     compile:
       cmd: >
         vcs -full64 -sverilog -ntb_opts uvm-1.2
         -f <tb_dir>/eh2_rtl.f
         -f <tb_dir>/eh2_shared.f
         -f <tb_dir>/eh2_tb.f
         -top core_eh2_tb_top
         -Mdir=<build_dir>/csrc
         -o <build_dir>/simv
         +define+UVM_NO_DEPRECATED
         +incdir+<tb_dir>/common/axi4_agent
         +incdir+<tb_dir>/common/trace_agent
         +incdir+<tb_dir>/common/irq_agent
         +incdir+<tb_dir>/common/jtag_agent
         +incdir+<tb_dir>/common/cosim_agent
         -l <build_dir>/compile.log
       cov_opts: "-cm line+tgl+assert+fsm+branch -cm_dir <build_dir>/cov -cm_hier dv/uvm/core_eh2/cover.cfg -cm_fsmcfg dv/uvm/core_eh2/cov_fsm.cfg -cm_fsmresetfilter dv/uvm/core_eh2/cov_fsm_reset_filter.cfg -cm_fsmopt report2StateFsms+allowTmp+reportvalues+reportWait+upto64"
       wave_opts: "-debug_access+all -kdb"

逐段解释：

* 第 L11-L13 行：`vcs.compile.cmd` 使用 folded scalar `>` 保存多行命令。
* 第 L14-L20 行：VCS compile 命令包含 `-full64`、SystemVerilog、UVM 1.2、
  三个 filelist、top module、csrc 目录和 simv 输出路径。
* 第 L21-L27 行：加入 `UVM_NO_DEPRECATED` define 和 5 个 UVM/cosim include 目录，
  compile log 写到 `<build_dir>/compile.log`。
* 第 L28-L29 行：coverage 选项启用 ``line+tgl+assert+fsm+branch`` 五维覆盖率，
  指定 :file:`cover.cfg` DUT-only hierarchy、FSM cfg、reset filter 和 FSM opt；
  wave 选项是 `-debug_access+all -kdb`。

接口关系：

* 被调用：`run_rtl.build_compile_cmd()` 或 riscv-dv 接口读取 `vcs.compile`。
* 调用：无。
* 共享状态：依赖 `<tb_dir>` 和 `<build_dir>` 替换。

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L30-L52``）：

.. code-block:: yaml

       cosim_opts: >-
         -f <tb_dir>/eh2_dv_cosim_dpi.f
         -LDFLAGS '<ISS_LDFLAGS>'
         -CFLAGS '<ISS_CFLAGS> <EXTRA_COSIM_CFLAGS>'
         -CFLAGS '-I<tb_dir>/../../cosim'
         <ISS_LIBS>
         -lstdc++

     sim:
       cmd: >
         <build_dir>/simv
         +UVM_TESTNAME=<rtl_test>
         +bin=<binary>
         +seed=<seed>
         +timeout_ns=<timeout>
         <sim_opts>
         -l <out_dir>/sim_<test>_<seed>.log
         +UVM_VERBOSITY=<uvm_verbosity>
       cov_opts: "+enable_eh2_fcov=1 -cm line+tgl+assert+fsm+branch -cm_dir <build_dir>/cov -cm_name <test>_<seed>"
       wave_opts: >-
         -ucli
         -do <tb_dir>/vcs.tcl

逐段解释：

* 第 L30-L36 行：`vcs.compile.cosim_opts` 引入 cosim DPI filelist、ISS linker flags、
  ISS CFLAGS、额外 cosim CFLAGS、ISS libs 和 `-lstdc++`。
* 第 L38-L47 行：`vcs.sim.cmd` 运行 `<build_dir>/simv`，通过 plusarg 传入
  UVM test、binary、seed、timeout、sim opts、log path 和 UVM verbosity。
* 第 L48 行：simulation coverage 选项打开 EH2 functional coverage，并给 VCS
  coverage database 命名 `<test>_<seed>`。
* 第 L49-L52 行：VCS wave 选项用 `-ucli` 和 `<tb_dir>/vcs.tcl`。

接口关系：

* 被调用：`run_rtl.build_sim_cmd()` 读取 `vcs.sim`。
* 调用：无。
* 共享状态：依赖 `<binary>`、`<seed>`、`<timeout>`、`<out_dir>`、`<test>`、
  `<uvm_verbosity>` 等模板变量替换。

§3.2 ``xlm`` compile/sim 模板
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L56-L79``）：

.. code-block:: yaml

   xlm:
     compile:
       cmd: >
         xrun -uvm -sv
         -f <tb_dir>/eh2_rtl.f
         -f <tb_dir>/eh2_shared.f
         -f <tb_dir>/eh2_tb.f
         -top core_eh2_tb_top
         +incdir+<tb_dir>/common/axi4_agent
         +incdir+<tb_dir>/common/trace_agent
         +incdir+<tb_dir>/common/irq_agent
         +incdir+<tb_dir>/common/jtag_agent
         +incdir+<tb_dir>/common/cosim_agent
         -l <build_dir>/compile.log
       cov_opts: "-covoverwrite -covfile <tb_dir>/cov.ccf"
       wave_opts: "-access +rwc -linedebug"
       cosim_opts: >-
         -f <tb_dir>/eh2_dv_cosim_dpi.f
         -I<tb_dir>/../../cosim
         <ISS_LIBS>
         <ISS_CFLAGS>
         <EXTRA_COSIM_CFLAGS>
         <ISS_LDFLAGS>
         -lstdc++

逐段解释：

* 第 L56-L63 行：Xcelium key 名为 `xlm`，compile 命令使用 `xrun -uvm -sv`，
  读取 RTL、shared、TB filelist，并设置 top 为 `core_eh2_tb_top`。
* 第 L64-L69 行：include 目录覆盖 AXI4、trace、IRQ、JTAG 和 cosim agent。
* 第 L70-L71 行：coverage 使用 `<tb_dir>/cov.ccf`，wave/debug 选项是
  `-access +rwc -linedebug`。
* 第 L72-L79 行：cosim opts 使用 DPI filelist、cosim include、ISS libs/CFLAGS/
  LDFLAGS 和 `-lstdc++`。

接口关系：

* 被调用：simulator 选择为 `xlm` 时读取。
* 调用：无。
* 共享状态：依赖 `<tb_dir>`、`<build_dir>` 和 ISS 模板变量替换。

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L81-L95``）：

.. code-block:: yaml

     sim:
       cmd: >
         xrun
         +UVM_TESTNAME=<rtl_test>
         +bin=<binary>
         +seed=<seed>
         +timeout_ns=<timeout>
         <sim_opts>
         -l <out_dir>/sim_<test>_<seed>.log
         +UVM_VERBOSITY=<uvm_verbosity>
       cov_opts: "+enable_eh2_fcov=1 -covoverwrite -covfile <tb_dir>/cov.ccf"
       wave_opts: >-
         -input @"database -open <out_dir>/waves -shm -default"
         -input @"probe -create core_eh2_tb_top -all -memories -depth all"
         -input @"run"

逐段解释：

* 第 L81-L90 行：Xcelium sim 命令用 `xrun`，plusarg 集合与 VCS sim 模板保持同类
  字段。
* 第 L91 行：Xcelium sim coverage 选项打开 EH2 functional coverage，并使用
  `<tb_dir>/cov.ccf`。
* 第 L92-L95 行：wave 选项通过三条 `-input @` 命令创建 SHM database、probe
  `core_eh2_tb_top`，然后执行 `run`。

接口关系：

* 被调用：simulator 选择为 `xlm` 的 simulation 阶段。
* 调用：无。
* 共享状态：依赖 `<out_dir>`、`<test>`、`<seed>` 等模板变量替换。

§3.3 ``questa`` compile/sim 模板
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L100-L129``）：

.. code-block:: yaml

   questa:
     compile:
       cmd: >
         vlib <build_dir>/work && vlog -work <build_dir>/work -sv
         -f <tb_dir>/eh2_rtl.f
         -f <tb_dir>/eh2_shared.f
         -f <tb_dir>/eh2_tb.f
         -top core_eh2_tb_top
         +incdir+<tb_dir>/common/axi4_agent
         +incdir+<tb_dir>/common/trace_agent
         +incdir+<tb_dir>/common/irq_agent
         +incdir+<tb_dir>/common/jtag_agent
         +incdir+<tb_dir>/common/cosim_agent
         -l <build_dir>/compile.log
       cov_opts: ""
       cosim_opts: >-
         -f <tb_dir>/eh2_dv_cosim_dpi.f

     sim:
       cmd: >
         vsim -c <build_dir>/work.core_eh2_tb_top
         -do "run -all"
         +UVM_TESTNAME=<rtl_test>
         +bin=<binary>
         +seed=<seed>
         +timeout_ns=<timeout>
         <sim_opts>
         -l <out_dir>/sim_<test>_<seed>.log
         +UVM_VERBOSITY=<uvm_verbosity>
       cov_opts: "+enable_eh2_fcov=1"

逐段解释：

* 第 L100-L107 行：Questa compile 命令先 `vlib <build_dir>/work`，再用 `vlog`
  编译三个 filelist 并设置 top。
* 第 L108-L113 行：Questa include 目录与 VCS/Xcelium 覆盖同一组 agent 和 cosim
  目录。
* 第 L114-L117 行：Questa compile coverage 选项为空，cosim opts 只列出
  `eh2_dv_cosim_dpi.f`。
* 第 L118-L128 行：Questa sim 命令使用 `vsim -c <build_dir>/work.core_eh2_tb_top`，
  执行 `run -all`，并传入同类 plusarg。
* 第 L129 行：Questa sim coverage 只包含 `+enable_eh2_fcov=1`。

接口关系：

* 被调用：simulator 选择为 `questa` 时读取。
* 调用：无。
* 共享状态：依赖 `<build_dir>`、`<tb_dir>`、`<rtl_test>`、`<binary>` 等模板变量替换。

§3.4 调用端替换逻辑
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/run_rtl.py:L121-L132``）：

.. code-block:: python

       # Load simulator config
       sim_cfg_path = os.path.join(md.eh2_root, "dv", "uvm", "core_eh2", "yaml", "rtl_simulation.yaml")
       if os.path.exists(sim_cfg_path):
           sim_cfg = load_sim_config(sim_cfg_path) or {}
       else:
           trr.failure_mode = "CONFIG_ERROR"
           trr.sim_log_path = os.path.join(
               md.out_dir, f"sim_{md.test_name}_{md.seed}.log")
           os.makedirs(md.out_dir, exist_ok=True)
           with open(trr.sim_log_path, "w") as log_f:
               log_f.write(f"ERROR: simulator config not found: {sim_cfg_path}\n")
           return trr

逐段解释：

* 第 L122 行：`run_rtl_simulation()` 固定把 simulator config path 拼到
  `dv/uvm/core_eh2/yaml/rtl_simulation.yaml`。
* 第 L123-L124 行：文件存在时调用 `load_sim_config()`。
* 第 L125-L132 行：文件缺失时把 `failure_mode` 设为 `CONFIG_ERROR`，写入 per-test
  sim log，并返回 `TestRunResult`。

接口关系：

* 被调用：`run_rtl_simulation()` 的主流程。
* 调用：`os.path.exists()`、`load_sim_config()`。
* 共享状态：读 `md.eh2_root`、`md.out_dir`、`md.test_name`、`md.seed`。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv_interface.py:L106-L140``）：

.. code-block:: python

   def get_tool_cmds(yaml_path: str, variables: dict = None) -> dict:
       """
       Parse rtl_simulation.yaml and produce final commands with variable substitution.

       Args:
           yaml_path: Path to rtl_simulation.yaml
           variables: Dict of variable substitutions

       Returns:
           Dict with 'compile' and 'sim' command strings
       """
       with open(yaml_path, "r", encoding="utf-8") as f:
           cfg = yaml.safe_load(f)

       if variables is None:

逐段解释：

* 第 L106-L116 行：docstring 明确该函数解析 `rtl_simulation.yaml`，并返回 compile
  和 sim 命令字符串。
* 第 L117-L118 行：函数用 UTF-8 打开 YAML，并用 `yaml.safe_load()` 解析。
* 第 L120-L121 行：未传入变量字典时使用空字典。

接口关系：

* 被调用：riscv-dv tool command 生成流程。
* 调用：`yaml.safe_load()`。
* 共享状态：读取 `yaml_path` 指向的 simulator YAML。

关键代码（``dv/uvm/core_eh2/scripts/riscvdv_interface.py:L123-L140``）：

.. code-block:: python

       result = {}

       for simulator, sim_cfg in cfg.items():
           result[simulator] = {}

           for stage in ["compile", "sim"]:
               if stage not in sim_cfg:
                   continue

               cmd = sim_cfg[stage].get("cmd", "")

               # Substitute variables
               for key, value in variables.items():
                   cmd = cmd.replace(f"<{key}>", str(value))

               result[simulator][stage] = cmd.strip()

       return result

逐段解释：

* 第 L125-L128 行：函数按 YAML 顶层 simulator key 遍历，例如 `vcs`、`xlm`、
  `questa`。
* 第 L128-L132 行：只处理 `compile` 和 `sim` 两个 stage，缺失的 stage 会被跳过。
* 第 L134-L136 行：对变量字典中的每个 key 执行字符串替换，把 `<key>` 替换为值。
* 第 L138-L140 行：保存去除首尾空白后的命令字符串并返回结果字典。

接口关系：

* 被调用：工具命令生成流程。
* 调用：字符串 `replace()`。
* 共享状态：读取 YAML 中各 stage 的 `cmd` 字段。

§4 ``directed_testlist.yaml`` — directed test 池
--------------------------------------------------------------------------------

职责：定义 directed test 使用的公共 config 条目和具体 test 条目。当前文件包含
3 个 config 条目和 40 个 test 条目。

§4.1 公共 config 条目
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L1-L23``）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 directed tests, modeled after Ibex's directed_tests/directed_testlist.yaml.

   - config: eh2_directed
     rtl_test: core_eh2_base_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - config: eh2_directed_pic
     rtl_test: core_eh2_pic_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - config: eh2_directed_fetch_toggle
     rtl_test: core_eh2_fetch_toggle_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

逐段解释：

* 第 L1-L2 行：文件声明 SPDX，并说明 modeled after Ibex 的 directed testlist。
* 第 L4-L9 行：`eh2_directed` 使用 `core_eh2_base_test`，timeout 为 300 秒，
  GCC 选项是 `-O2 -g -static -nostdlib -nostartfiles`，linker script 和 include
  目录都指向 `tests/asm`。
* 第 L11-L16 行：`eh2_directed_pic` 只把 `rtl_test` 改成 `core_eh2_pic_test`。
* 第 L18-L23 行：`eh2_directed_fetch_toggle` 把 `rtl_test` 改成
  `core_eh2_fetch_toggle_test`。

接口关系：

* 被调用：`directed_test_schema.import_model()` 先收集 config 条目，再给 test 条目
  匹配 config。
* 调用：无。
* 共享状态：为后续 test 条目提供默认 RTL test、timeout、GCC 和 linker 设置。

§4.2 smoke、ALU、load/store 和基础异常类 test
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L25-L61``）：

.. code-block:: yaml

   - test: directed_smoke
     desc: "Mailbox smoke test running through the directed-test pipeline"
     config: eh2_directed
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

   - test: directed_alu
     desc: "Deterministic ALU directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_alu.S
     iterations: 1

   - test: directed_load_store
     desc: "Deterministic load/store directed test"
     config: eh2_directed
     test_srcs: tests/asm/cosim_load_store.S
     iterations: 1

   - test: directed_irq_basic

逐段解释：

* 第 L25-L29 行：`directed_smoke` 使用 `cosim_smoke.S`，iterations 为 1。
* 第 L31-L35 行：`directed_alu` 使用 `cosim_alu.S`，iterations 为 1。
* 第 L37-L41 行：`directed_load_store` 使用 `cosim_load_store.S`，iterations 为 1。
* 第 L43-L61 行：后续基础条目包括 IRQ、PMP smoke、CSR WARL；其中
  `directed_pmp_smoke` 标记 `cosim: enabled`，`directed_csr_warl` 标记
  `cosim: disabled`。

接口关系：

* 被调用：metadata test selection 和 sign-off directed stage 读取这些 test 名称。
* 调用：无。
* 共享状态：test entry 中的 `test_srcs` 指向 assembly 源文件。

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L63-L106``）：

.. code-block:: yaml

   - test: directed_double_issue_hazard
     desc: "Dual-issue RAW/WAR/WAW hazard ordering"
     config: eh2_directed
     test_srcs: tests/asm/directed_double_issue_hazard.S
     iterations: 1

   - test: directed_nb_load_chain
     desc: "Three consecutive NB-loads + dependent branch (RISK-5)"
     config: eh2_directed
     test_srcs: tests/asm/directed_nb_load_chain.S
     iterations: 1

   - test: directed_axi4_error_inject
     desc: "AXI4 SLVERR/DECERR injection triggers load access fault"
     config: eh2_directed
     test_srcs: tests/asm/directed_axi4_error_inject.S
     cosim: disabled
     sim_opts: '+enable_axi4_error_inject=1 +axi4_error_pct=100'
     iterations: 1

逐段解释：

* 第 L63-L67 行：`directed_double_issue_hazard` 绑定
  `directed_double_issue_hazard.S`。
* 第 L69-L73 行：`directed_nb_load_chain` 的描述明确涉及 NB-load 和 dependent
  branch。
* 第 L75-L81 行：`directed_axi4_error_inject` 关闭 cosim，并通过 `sim_opts` 打开
  AXI4 error injection plusarg。
* 第 L83-L106 行：同一段后续还定义 illegal instruction、nested IRQ、debug basic
  和 PMP regions；`directed_pmp_regions` 标记 `cosim: enabled`。

接口关系：

* 被调用：directed stage 根据 `test` 和 `iterations` 形成运行矩阵。
* 调用：无。
* 共享状态：`sim_opts` 字段保存仿真 plusarg。

§4.3 PMP directed test 组
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L110-L150``）：

.. code-block:: yaml

   - test: directed_pmp_tor_basic
     desc: "PMP TOR mode basic access + out-of-bounds"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_tor_basic.S
     cosim: enabled
     iterations: 1

   - test: directed_pmp_napot_basic
     desc: "PMP NAPOT mode at 4B/16B/256B/4KB sizes"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_napot_basic.S
     cosim: enabled
     iterations: 1

   - test: directed_pmp_na4_basic
     desc: "PMP NA4 4-byte naturally-aligned region"

逐段解释：

* 第 L110-L115 行：`directed_pmp_tor_basic` 覆盖 PMP TOR 基础访问和越界。
* 第 L117-L122 行：`directed_pmp_napot_basic` 覆盖 NAPOT 多种 region size。
* 第 L124-L150 行：后续 PMP 条目覆盖 NA4、OFF、lock、priority；这些条目均显式
  `cosim: enabled`。

接口关系：

* 被调用：directed test pool 和 sign-off pool 统计读取这些条目。
* 调用：无。
* 共享状态：每个条目通过 `test_srcs` 绑定 `tests/asm/directed_pmp_*.S`。

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L152-L220``）：

.. code-block:: yaml

   - test: directed_pmp_iside
     desc: "PMP enforcement on instruction-side fetches"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_iside.S
     cosim: enabled
     iterations: 1

   - test: directed_pmp_dside_load
     desc: "PMP enforcement on data-side loads"
     config: eh2_directed
     test_srcs: tests/asm/directed_pmp_dside_load.S
     cosim: enabled
     iterations: 1

   - test: directed_pmp_dside_store
     desc: "PMP enforcement on data-side stores"

逐段解释：

* 第 L152-L157 行：`directed_pmp_iside` 覆盖 instruction-side fetch 的 PMP enforcement。
* 第 L159-L164 行：`directed_pmp_dside_load` 覆盖 data-side load。
* 第 L166-L220 行：后续条目覆盖 data-side store、X/W/R 组合、地址对齐、跨 region、
  CSR WARL、no-match default deny、trap 后内容和 EH2 `mscause` secondary cause。
  这些 PMP 条目均显式 `cosim: enabled`。

接口关系：

* 被调用：directed test pool。
* 调用：无。
* 共享状态：同一组条目复用 `eh2_directed` config。

§4.4 Coverage pump 和 toggle directed test 组
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L222-L268``）：

.. code-block:: yaml

   # Coverage pump directed tests (Task-D)

   - test: directed_pic_state_walk
     desc: "PIC/trap claim-complete state stimulus with IRQ sideband"
     config: eh2_directed_pic
     test_srcs: tests/asm/directed_pic_state_walk.S
     sim_opts: '+enable_irq_seq=1 +enable_irq_single_seq=1 +max_interval=20'
     cosim: disabled
     iterations: 1

   - test: directed_dbg_dret_walk
     desc: "Debug halt/resume and breakpoint trap stimulus"
     config: eh2_directed
     test_srcs: tests/asm/directed_dbg_dret_walk.S
     sim_opts: '+enable_debug_seq=1 +enable_debug_single=1 +max_interval=20'

逐段解释：

* 第 L222 行：注释把这一组标为 coverage pump directed tests。
* 第 L224-L230 行：`directed_pic_state_walk` 使用 `eh2_directed_pic`，并启用 IRQ
  sequence plusarg；cosim 被关闭。
* 第 L232-L238 行：`directed_dbg_dret_walk` 启用 debug sequence plusarg；cosim
  被关闭。
* 第 L240-L268 行：后续 `directed_dma_burst`、`directed_ifu_bp_btb`、
  `directed_lsu_stbuf_full`、`directed_iccm_eccerror` 也都关闭 cosim；其中 IFU 和
  ICCM 条目带有 `sim_opts`。

接口关系：

* 被调用：directed stage 和 coverage-oriented regression。
* 调用：无。
* 共享状态：`sim_opts` 保存 testbench sequence 开关。

关键代码（``dv/uvm/core_eh2/directed_tests/directed_testlist.yaml:L270-L303``）：

.. code-block:: yaml

   - test: directed_toggle_axi4_data_walk
     desc: "AXI4 data bus toggle pump (R3-B)"
     config: eh2_directed
     test_srcs: tests/asm/directed_toggle_axi4_data_walk.S
     cosim: disabled
     iterations: 1

   - test: directed_toggle_csr_walk
     desc: "CSR toggle pump (R3-B)"
     config: eh2_directed
     test_srcs: tests/asm/directed_toggle_csr_walk.S
     cosim: disabled
     iterations: 1

   - test: directed_toggle_rf_walk
     desc: "Integer register file toggle pump (R3-B)"

逐段解释：

* 第 L270-L275 行：`directed_toggle_axi4_data_walk` 关闭 cosim，绑定 AXI4 data bus
  toggle assembly。
* 第 L277-L282 行：`directed_toggle_csr_walk` 关闭 cosim，绑定 CSR toggle assembly。
* 第 L284-L303 行：后续 toggle 条目覆盖 RF、DCCM、mul/div；都关闭 cosim，iterations
  均为 1。

接口关系：

* 被调用：directed stage。
* 调用：无。
* 共享状态：这些条目都复用 `eh2_directed` config。

§4.5 directed schema 解析行为
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``dv/uvm/core_eh2/scripts/directed_test_schema.py:L21-L46``）：

.. code-block:: python

   @dataclass
   class DConfig:
       """Common configuration for building directed tests.

       Contains build information shared by multiple tests to encourage reuse.
       """
       config: str                  # Config name (each DTest must specify this)
       rtl_test: str                # UVM test class name
       rtl_params: dict = field(default_factory=dict)  # RTL parameters
       timeout_s: int = 300         # Simulation timeout
       gcc_opts: str = "-O2 -g -static -nostdlib -nostartfiles"
       ld_script: Optional[str] = None   # Linker script path
       includes: Optional[str] = None    # Include path

   @dataclass
   class DTest(DConfig):
       """A single directed test entry.

逐段解释：

* 第 L21-L33 行：`DConfig` 定义 config 条目可提供的公共字段，包括 `config`、
  `rtl_test`、`rtl_params`、`timeout_s`、`gcc_opts`、`ld_script`、`includes`。
* 第 L36-L46 行：`DTest` 继承 `DConfig`，增加 `test`、`desc`、`test_srcs` 和
  `iterations` 字段。

接口关系：

* 被调用：`import_model()` 构造 `DConfig` 和 `DTest`。
* 调用：Python dataclass。
* 共享状态：定义 directed YAML 的解析目标结构。

关键代码（``dv/uvm/core_eh2/scripts/directed_test_schema.py:L65-L85``）：

.. code-block:: python

       yaml_data = scripts_lib.read_yaml(directed_test_yaml)

       if not isinstance(yaml_data, list):
           logger.error(f"Expected a list in {directed_test_yaml}, got {type(yaml_data)}")
           sys.exit(1)

       configs = []
       tests = []

       for entry in yaml_data:
           if 'test' not in entry:
               # This is a config entry
               configs.append(DConfig(
                   config=entry.get('config', ''),
                   rtl_test=entry.get('rtl_test', ''),
                   rtl_params=entry.get('rtl_params', {}),
                   timeout_s=entry.get('timeout_s', 300),
                   gcc_opts=entry.get('gcc_opts', '-O2 -g -static'),
                   ld_script=entry.get('ld_script'),

逐段解释：

* 第 L65-L69 行：`import_model()` 要求 YAML 顶层是 list；否则记录 error 并
  `sys.exit(1)`。
* 第 L71-L72 行：初始化 config 和 test 两个列表。
* 第 L74-L85 行：没有 `test` 字段的 entry 被视为 config 条目，并转换成
  `DConfig`。

接口关系：

* 被调用：`metadata._load_directed_entries()`。
* 调用：`scripts_lib.read_yaml()`。
* 共享状态：读取 directed/cosim testlist YAML。

关键代码（``dv/uvm/core_eh2/scripts/directed_test_schema.py:L86-L119``）：

.. code-block:: python

           else:
               # This is a test entry - find matching config
               config_name = entry.get('config', '')
               matching_config = None
               for c in configs:
                   if c.config == config_name:
                       matching_config = c
                       break

               if matching_config is None:
                   logger.error(
                       f"Test '{entry['test']}' references config '{config_name}' "
                       f"which does not exist in {directed_test_yaml}")
                   sys.exit(1)

逐段解释：

* 第 L86-L93 行：带 `test` 字段的 entry 被视为 test 条目，解析器按 `config` 名称
  在已读取 config 列表中查找匹配项。
* 第 L95-L99 行：找不到 config 时输出 error 并退出。
* 第 L101-L119 行：找到 config 后，解析器把公共 config 字段和 test-specific 字段
  组合成 `DTest`，最后返回 `DirectedTestsYaml`。

接口关系：

* 被调用：`import_model()`。
* 调用：无外部命令。
* 共享状态：`DTest` 继承匹配 config 的 `rtl_test`、`timeout_s`、`gcc_opts`、
  `ld_script` 和 `includes`。

§5 ``cosim_testlist.yaml`` — cosim proof test 池
--------------------------------------------------------------------------------

职责：定义使用 `core_eh2_cosim_test` 的 cosim proof tests。当前文件包含 1 个
config 条目和 7 个 test 条目。

关键代码（``dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml:L1-L16``）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 cosim proof tests. These are framework proof points and run with
   # core_eh2_cosim_test so Spike lockstep is enabled by construction.

   - config: eh2_cosim
     rtl_test: core_eh2_cosim_test
     timeout_s: 300
     gcc_opts: "-O2 -g -static -nostdlib -nostartfiles"
     ld_script: tests/asm/cosim_link.ld
     includes: tests/asm

   - test: cosim_smoke
     desc: "Cosim initialization, binary load, first Spike step, mailbox PASS"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_smoke.S
     iterations: 1

逐段解释：

* 第 L1-L3 行：文件注释说明这些是 cosim proof points，并且使用
  `core_eh2_cosim_test`，所以 Spike lockstep 被构造性启用。
* 第 L5-L10 行：`eh2_cosim` config 使用 `core_eh2_cosim_test`，timeout 为 300 秒，
  GCC/linker/include 设置与 directed config 同类。
* 第 L12-L16 行：`cosim_smoke` 绑定 `cosim_smoke.S`，iterations 为 1。

接口关系：

* 被调用：`metadata._select_test_entries()` 对 `cosim_testlist.yaml` 有专门
  `all_cosim` 选择逻辑。
* 调用：无。
* 共享状态：为 cosim proof stage 提供 test pool。

关键代码（``dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml:L18-L54``）：

.. code-block:: yaml

   - test: cosim_alu
     desc: "Register writeback correlation for deterministic ALU instructions"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_alu.S
     iterations: 1

   - test: cosim_load_store
     desc: "LSU AXI memory notification path for deterministic loads/stores"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_load_store.S
     iterations: 1

   - test: cosim_dual_issue
     desc: "Program-order lockstep for EH2 dual-issue retire traces"
     config: eh2_cosim
     test_srcs: tests/asm/cosim_dual_issue.S

逐段解释：

* 第 L18-L22 行：`cosim_alu` 覆盖 deterministic ALU instruction 的 register
  writeback correlation。
* 第 L24-L28 行：`cosim_load_store` 覆盖 LSU AXI memory notification path。
* 第 L30-L34 行：`cosim_dual_issue` 覆盖 EH2 dual-issue retire trace 的 program-order
  lockstep。
* 第 L36-L54 行：后续 proof tests 包括 bitmanip、exception compare 和 atomic
  basic；其中 exception 和 atomic 条目带 `+max_cycles=500000 +timeout_ns=50000000`。

接口关系：

* 被调用：cosim stage 和 sign-off cosim stage。
* 调用：无。
* 共享状态：每个条目通过 `test_srcs` 绑定 `tests/asm/cosim_*.S`。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L345-L357``）：

.. code-block:: python

       for directed_testlist in directed_testlists:
           directed_entries = _load_directed_entries(directed_testlist)
           is_cosim_testlist = directed_testlist.name == "cosim_testlist.yaml"
           include_all = run_all_directed or (
               is_cosim_testlist and run_all_cosim)
           for entry in directed_entries:
               name = entry.get("test")
               if not name:
                   continue
               if include_all or name in selected:
                   count = _entry_iterations(entry, override)
                   if count > 0:
                       test_matrix.append((name, count, "DIRECTED"))

逐段解释：

* 第 L345-L347 行：metadata 同时遍历 directed testlist 和 cosim testlist，并用文件名
  判断当前是否为 `cosim_testlist.yaml`。
* 第 L348-L349 行：`all_cosim` 只让 cosim testlist 全量纳入；`all_directed` 则也会
  纳入所有 directed entries。
* 第 L350-L357 行：命中 include-all 或显式 test name 时，把 `(name, count, "DIRECTED")`
  追加到 test matrix。

接口关系：

* 被调用：`create_metadata()`。
* 调用：`_load_directed_entries()`、`_entry_iterations()`。
* 共享状态：读取 directed/cosim testlist。

§6 ``cosim-disabled.yaml`` — cosim waiver gate
--------------------------------------------------------------------------------

职责：记录被允许 cosim-disabled 的 test 名称、技术原因、tracking issue 和过期日期。
该文件本身不关闭 cosim；它只为 sign-off gate 提供 waiver 名单。

关键代码（``dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L1-L15``）：

.. code-block:: yaml

   # EH2 Cosim-Disabled Waivers
   #
   # Each waiver corresponds to a test with `cosim: disabled` in the testlist
   # (riscv_dv_extension/testlist.yaml). Only waived tests pass the
   # --fail-on-cosim-disabled gate.
   #
   # Schema (per entry):
   #   test:            test name (must match testlist exactly)
   #   reason:          technical explanation of why cosim cannot run
   #   tracking_issue:  reference to issue tracker or ADR
   #   expiry_date:     YYYY-MM-DD — after this date the waiver is invalid
   #
   # cosim_reason fields in testlist.yaml are NOT waivers — only this file confers
   # formal waiver status. The gate is enforced by signoff.py.

逐段解释：

* 第 L1-L5 行：注释说明 waiver 对应 testlist 中 `cosim: disabled` 的 test，只有
  被 waiver 的 test 能通过 `--fail-on-cosim-disabled` gate。
* 第 L7-L11 行：每个 entry schema 包含 `test`、`reason`、`tracking_issue`、
  `expiry_date`。
* 第 L13-L14 行：注释明确 testlist 中的 `cosim_reason` 不是 waiver，正式 waiver
  只来自该文件，并由 `signoff.py` 执行 gate。

接口关系：

* 被调用：`signoff.py:validate_waiver_schema()` 和 `load_waiver_set()`。
* 调用：无。
* 共享状态：为 sign-off gate 提供 waived test name 集合。

关键代码（``dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L16-L39``）：

.. code-block:: yaml

   # ── CSR-directed tests ────────────────────────────────────────────────────────
   - test: riscv_csr_test
     reason: >
       Directed CSR read/write test exercises EH2-specific custom CSRs (mrac,
       mcgc, mfdc, meivt, etc.) that have WARL/U behaviours not implemented in
       Spike. Spike's CSR model does not emulate the full EH2 custom CSR space,
       leading to CSR value mismatches that cascade into GPR mismatches on CSR
       readback. The test also triggers presync/postsync side effects that Spike
       does not model.
     tracking_issue: "ADR-0006 — CSR WARL fixups in spike_cosim.cc; EH2 custom CSRs"
     expiry_date: 2026-07-31

   - test: riscv_csr_hazard_test

逐段解释：

* 第 L16 行：注释把第一组 waiver 标为 CSR-directed tests。
* 第 L17-L26 行：`riscv_csr_test` 的 reason 指向 EH2 custom CSR、WARL/U 行为、
  Spike CSR model 覆盖不足和 presync/postsync side effect；过期日期是
  2026-07-31。
* 第 L28-L39 行：`riscv_csr_hazard_test` 的 reason 指向 CSR pipeline hazard、
  bypass、CSR write-read forwarding、CSR-to-GPR data hazard 和 Spike ISA-level
  model 缺少 microarchitectural pipeline timing；过期日期是 2026-12-31。

接口关系：

* 被调用：waiver schema validator 会检查 `reason`、`tracking_issue`、
  `expiry_date` 是否存在。
* 调用：无。
* 共享状态：提供 CSR 类 waived test 名称。

关键代码（``dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L41-L77``）：

.. code-block:: yaml

   # ── Hardware integrity / fault-injection tests ────────────────────────────────
   # These tests inject hardware faults (ECC/parity errors) using RTL force
   # statements. Spike is an ISA-level simulator with no concept of ECC, parity,
   # or hardware fault injection. Cosim comparison is fundamentally impossible.

   - test: riscv_pc_intg_test
     reason: >
       PC integrity fault injection — injects parity errors on the program counter
       bus using RTL force statements. Triggers EH2-specific rfpcintg exception
       with custom mcause encoding. Spike has no PC integrity error model.
     tracking_issue: "Issue 61 — EH2 hardware integrity paths not modelable in Spike"
     expiry_date: 2026-12-31

   - test: riscv_rf_intg_test

逐段解释：

* 第 L41-L44 行：组注释说明这类测试通过 RTL force 注入 ECC/parity 等硬件 fault，
  Spike 是 ISA-level simulator，没有 ECC、parity 或 hardware fault injection 概念。
* 第 L46-L52 行：`riscv_pc_intg_test` 记录 PC parity fault、`rfpcintg` exception
  和 custom `mcause` encoding。
* 第 L54-L68 行：`riscv_rf_intg_test` 与 `riscv_rf_addr_intg_test` 分别记录 GPR
  数据和地址 integrity fault injection。
* 第 L70-L77 行：`riscv_ram_intg_test` 记录 DCCM/ICCM RAM ECC/parity fault
  injection，以及 Spike 缺少 ECC logic、error status 和 EH2 error CSR。

接口关系：

* 被调用：sign-off waiver gate。
* 调用：无。
* 共享状态：tracking issue 文本统一指向 Issue 61。

关键代码（``dv/uvm/core_eh2/waivers/cosim-disabled.yaml:L79-L108``）：

.. code-block:: yaml

   - test: riscv_icache_intg_test
     reason: >
       ICache tag/data integrity fault injection — injects parity errors into
       I$ tag and data RAM arrays. Spike has no instruction cache model; it
       fetches via backdoor_read_mem from a flat memory. Cache tag parity and
       line invalidation are EH2-specific microarchitectural features.
     tracking_issue: "Issue 61 — EH2 hardware integrity paths not modelable in Spike"
     expiry_date: 2026-12-31

   - test: riscv_mem_intg_error_test
     reason: >
       Generic memory integrity error injection — combines DCCM, ICCM, and bus-level

逐段解释：

* 第 L79-L86 行：`riscv_icache_intg_test` 记录 ICache tag/data integrity fault；
  reason 明确 Spike 没有 instruction cache model。
* 第 L88-L95 行：`riscv_mem_intg_error_test` 记录 DCCM、ICCM 和 bus-level integrity
  fault，涉及 `micect`、`mscause`、`mdeau` 等错误报告链。
* 第 L98-L108 行：`riscv_mem_error_test` 记录 AXI SLVERR/DECERR 注入、LSU AXI4
  interface、EH2-specific error handling，以及 Spike step-by-step timing 不匹配。

接口关系：

* 被调用：sign-off waiver gate。
* 调用：无。
* 共享状态：提供 integrity 和 AXI bus error 类 waived test 名称。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1133-L1165``）：

.. code-block:: python

   def validate_waiver_schema(waiver_path: Path) -> Tuple[bool, List[str]]:
       """Validate cosim-disabled waiver YAML schema.

       Each entry must have: reason, tracking_issue, expiry_date.
       Returns (valid, errors).
       """
       errors = []
       if not waiver_path.exists():
           return True, []
       try:
           waivers = _load_yaml(waiver_path)
       except Exception as e:
           return False, ["Cannot parse waiver file {}: {}".format(waiver_path, e)]

逐段解释：

* 第 L1133-L1138 行：函数 docstring 明确校验 cosim-disabled waiver YAML schema，并要求
  每个 entry 有 `reason`、`tracking_issue`、`expiry_date`。
* 第 L1140-L1141 行：waiver 文件不存在时返回 valid。
* 第 L1142-L1145 行：YAML 解析失败时返回 invalid 和错误文本。

接口关系：

* 被调用：sign-off 主流程。
* 调用：`_load_yaml()`。
* 共享状态：读取 `waiver_path`。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1146-L1165``）：

.. code-block:: python

       if waivers is None:
           return True, []
       if not isinstance(waivers, list):
           return False, ["Waiver file must contain a YAML list"]
       required_fields = ["reason", "tracking_issue", "expiry_date"]
       for i, entry in enumerate(waivers):
           if not isinstance(entry, dict):
               errors.append("Waiver entry {} is not a dict".format(i))
               continue
           for field in required_fields:
               if field not in entry or not entry[field]:
                   errors.append(
                       "Waiver entry {} ('{}'): missing or empty field '{}'".format(
                           i, entry.get("test", "unknown"), field))
           if "expiry_date" in entry and entry["expiry_date"]:
               if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(entry["expiry_date"])):

逐段解释：

* 第 L1146-L1149 行：空文件视为 valid；非 list 顶层结构直接 invalid。
* 第 L1150-L1159 行：逐 entry 检查 `reason`、`tracking_issue`、`expiry_date`
  是否存在且非空。
* 第 L1160-L1165 行：`expiry_date` 必须匹配 `YYYY-MM-DD`。

接口关系：

* 被调用：sign-off 主流程。
* 调用：`re.match()`。
* 共享状态：返回 `(valid, errors)` 给 gate 逻辑。

关键代码（``dv/uvm/core_eh2/scripts/signoff.py:L1273-L1293``）：

.. code-block:: python

       fail_on_cosim_disabled = not getattr(args, 'no_fail_on_cosim_disabled', False)
       fail_on_skip_in_signoff = not getattr(args, 'no_fail_on_skip_in_signoff', False)

       if fail_on_cosim_disabled or fail_on_skip_in_signoff:
           waiver_path_str = getattr(args, 'waivers_cosim_disabled', '')
           waiver_path = Path(waiver_path_str) if waiver_path_str else \
                         DV_DIR / "waivers" / "cosim-disabled.yaml"
           if waiver_errors:
               blockers.append("waiver schema errors: {}".format(
                   "; ".join(waiver_errors)))
           waived = load_waiver_set(waiver_path) if not waiver_errors else set()
       else:
           waived = set()

       if fail_on_cosim_disabled:

逐段解释：

* 第 L1273-L1274 行：两个 gate 默认启用，除非 CLI 参数显式关闭。
* 第 L1276-L1279 行：waiver path 来自 `--waivers-cosim-disabled`，未传时使用
  `dv/uvm/core_eh2/waivers/cosim-disabled.yaml`。
* 第 L1280-L1285 行：schema 有错误时加入 blocker；否则加载 waived test 集合。
* 第 L1287-L1293 行：如果存在 cosim-disabled 且不在 waived 集合中，会加入 blocker。

接口关系：

* 被调用：`evaluate_signoff()`。
* 调用：`load_waiver_set()`、`collect_cosim_exceptions()`。
* 共享状态：读取 waiver YAML 并写 sign-off blocker 列表。

§7 testlist 与 metadata 交互
--------------------------------------------------------------------------------

职责：说明 YAML testlist 如何被 metadata 创建阶段收集成 test matrix。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L379-L438``）：

.. code-block:: python

   def create_metadata(dir_metadata: str, dir_out: str,
                       args_list: str = "") -> RegressionMetadata:
       """Create a RegressionMetadata object using Ibex-style CLI arguments."""
       args = _parse_args_list(args_list)
       root = Path(__file__).resolve().parents[4]
       out_dir = Path(dir_out).resolve()
       metadata_dir = Path(dir_metadata).resolve()
       core_eh2 = root / "dv" / "uvm" / "core_eh2"
       run_dir = out_dir / "run"
       tests_dir = run_dir / "tests"
       cov_dir = run_dir / "coverage"

逐段解释：

* 第 L379-L382 行：metadata 创建函数接收 metadata/out 目录和 Ibex-style CLI
  参数字符串。
* 第 L383-L390 行：函数从脚本路径推导仓库根目录、UVM core 目录、run/tests/coverage
  目录。
* 第 L391-L426 行：函数把 seed、test、simulator、iterations、waves、coverage、
  ISS、signature address、EH2 config 和目录路径写入 `RegressionMetadata`。

接口关系：

* 被调用：顶层 `Makefile` 的 staged flow。
* 调用：`_parse_args_list()`。
* 共享状态：写 metadata object。

关键代码（``dv/uvm/core_eh2/scripts/metadata.py:L426-L438``）：

.. code-block:: python

       md.eh2_configs = str(root / "eh2_configs.yaml")
       md.eh2_riscvdv_customtarget = str(core_eh2 / "riscv_dv_extension")
       md.eh2_riscvdv_testlist = str(
           core_eh2 / "riscv_dv_extension" / "testlist.yaml")
       md.directed_test_dir = str(core_eh2 / "directed_tests")
       md.directed_test_data = str(
           core_eh2 / "directed_tests" / "directed_testlist.yaml")
       md.cosim_test_data = str(
           core_eh2 / "directed_tests" / "cosim_testlist.yaml")

       md.tests_and_counts = _select_test_entries(
           md, Path(md.eh2_riscvdv_testlist),
           [Path(md.directed_test_data), Path(md.cosim_test_data)])

逐段解释：

* 第 L426 行：metadata 记录顶层 `eh2_configs.yaml` 路径。
* 第 L427-L434 行：metadata 同时记录 riscv-dv testlist、directed testlist 和 cosim
  testlist 路径。
* 第 L436-L438 行：`_select_test_entries()` 同时接收 riscv-dv testlist 和
  directed/cosim testlist 列表，生成 `md.tests_and_counts`。

接口关系：

* 被调用：`create_metadata()` 内部。
* 调用：`_select_test_entries()`。
* 共享状态：读 testlist 路径，写 `md.tests_and_counts`。

§8 参考资料
--------------------------------------------------------------------------------

关联章节：

* :doc:`core_eh2_scripts` — 读取 YAML 的 Python 脚本实现。
* :doc:`makefiles` — 顶层 Makefile 如何把 testlist、coverage 和 sign-off target
  接入 flow。
* :doc:`../appendix_e_config/eh2_configs` — EH2 configuration profile 的配置视角。
* :doc:`../06_flows/regression_flow` — regression flow 如何运行 testlist。
* :doc:`../06_flows/signoff_flow` — sign-off gate 如何使用 waiver 与 stage 结果。

源文件绝对路径：

* `/home/host/eh2-veri/eh2_configs.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/yaml/rtl_simulation.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/directed_tests/cosim_testlist.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/waivers/cosim-disabled.yaml`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_cmd.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/riscvdv_interface.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/directed_test_schema.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`

关联 ADR / issue：

* :ref:`adr-0017` — integrity fault-injection tests 的 cosim waiver 边界。
* `.scratch/release-readiness/issues/61-integrity-tests.md` — waiver YAML 中
  `Issue 61` tracking text 对应的本地 issue 文件。
