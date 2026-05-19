.. _configuration:
.. _03_integration/configuration:

配置参数说明
============

:status: draft
:source: Makefile; eh2_configs.yaml; dv/uvm/core_eh2/wrapper.mk; dv/uvm/core_eh2/scripts/metadata.py; dv/uvm/core_eh2/scripts/render_config_template.py
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  集成者需要区分的三类配置
-----------------------------

EH2-Veri 当前有三类容易混淆的配置入口。第一类是 EH2 profile，也就是
:file:`eh2_configs.yaml` 中的 ``default``、``minimal``、``dual_thread`` 和
``ahb_lite``。第二类是 regression/sign-off 变量，例如 ``TEST``、``SEED``、
``SIMULATOR``、``COV``、``WAVES``、``PARALLEL`` 和 ``PROFILE``。第三类是完整
RTL/synthesis 参数快照，例如 :file:`syn/include/eh2_param.vh` 中的
``eh2_param_t pt``。这三类配置不是同一个层级。

本章面向集成使用，说明变量从命令行进入 metadata、template、riscv-dv 和 sign-off 的路径。
完整 profile 字典见 :ref:`appendix_e_config/eh2_configs`。

::

   User CLI
       |
       +-- CONFIG=<profile> -------> metadata.eh2_config
       |                               |
       |                               v
       |                         riscv_core_setting.tpl.sv
       |
       +-- PROFILE=<signoff> ------> signoff.py stage list
       |
       +-- SIMULATOR/COV/WAVES ----> compile/sim command selection

**关键边界**：当前源码没有名为 ``CFG`` 的主入口；Makefile 使用的是 ``CONFIG``。当前
YAML 也没有 8 个 profile，不存在 ``2thread``、``no_icache``、``no_dccm``、
``fpga``、``no_pmp`` 或 ``full`` 这些旧文档名称。

§2  ``eh2_configs.yaml`` — 当前 profile 集合
--------------------------------------------

**职责**：:file:`eh2_configs.yaml` 定义验证 flow 可选择的 EH2 profile。当前文件只有
4 个 profile，每个 profile 都包含 ``description`` 和 ``parameters``。

**关键代码** （``eh2_configs.yaml:L1-L7``）：

.. code-block:: yaml

   # EH2 Configuration Profiles
   # This file defines different EH2 configurations for verification.
   # Each profile specifies the parameters to use when building the DUT.

   default:
     description: "Default EH2 configuration (AXI4, single-thread, full features)"
     parameters:

**逐段解释**：

* 第 L1-L3 行：YAML 文件声明用途是 verification profile，并非完整 RTL 参数数据库。
* 第 L5-L7 行：profile 顶层结构由名称、描述和参数字典组成。Python helper 按这个 schema 读取。

**关键代码** （``eh2_configs.yaml:L40-L58,L77-L82``）：

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

   dual_thread:
   ...
   ahb_lite:
     description: "AHB-Lite bus configuration"

**逐段解释**：

* 第 L40-L57 行：``minimal`` 是当前 YAML 中的简化 profile，关闭 cache/DCCM/ICCM、
  Atomic 和 bitmanip，并把 PIC/BHT/BTB 参数调小。
* 第 L58 行：双线程 profile 名称为 ``dual_thread``。
* 第 L77-L82 行：AHB-Lite profile 名称为 ``ahb_lite``，通过 ``BUILD_AXI4=0`` 和
  ``BUILD_AHB_LITE=1`` 选择 bus。

**接口关系**：

* **被调用**：``eh2_cmd.get_config``、``render_config_template.py`` 和 ``signoff.py`` precheck 读取。
* **调用**：YAML 不调用代码。
* **共享状态**：profile 参数通过 metadata 选择后进入 riscv-dv template。

§3  顶层 Makefile staged 分支 — ``CONFIG`` 进入 metadata
--------------------------------------------------------

**职责**：当 ``GOAL`` 非空时，顶层 Makefile 进入 Ibex-style staged flow。该分支把
``CONFIG`` 默认设为 ``default``，并通过 ``metadata.py --op create_metadata`` 写入
metadata。

**关键代码** （``Makefile:L30-L62``）：

.. code-block:: makefile

   ifneq ($(GOAL),)

   CONFIG      ?= default
   SEED        ?= 1
   TEST        ?= all
   SIMULATOR   ?= vcs
   WAVES       ?= 0
   COV         ?= 0
   ITERATIONS  ?=
   PARALLEL    ?= 1
   RTL_TEST    ?= core_eh2_base_test
   SIM_OPTS    ?=
   GEN_OPTS    ?=
   ISS         ?= spike
   VERBOSE     ?= 0
   SIGNATURE_ADDR ?= d0580000

**逐段解释**：

* 第 L30-L33 行：只有 ``GOAL`` 非空时才使用 staged 分支，``CONFIG`` 默认是
  ``default``。
* 第 L34-L45 行：该分支同时定义 seed、test、simulator、coverage、RTL test、ISS 和
  signature address 等 staged flow 变量。

**关键代码** （``Makefile:L52-L74``）：

.. code-block:: makefile

   .PHONY: run
   run:
   	+@env PYTHONPATH=$(PYTHONPATH) python3 dv/uvm/core_eh2/scripts/metadata.py \
   	  --op "create_metadata" \
   	  --dir-metadata $(METADATA-DIR) \
   	  --dir-out $(OUT-DIR) \
   	  --args-list "\
   	  SEED=$(SEED) WAVES=$(WAVES) COV=$(COV) SIMULATOR=$(SIMULATOR) \
   	  ISS=$(ISS) TEST=$(TEST) VERBOSE=$(VERBOSE) ITERATIONS=$(ITERATIONS) \
   	  SIGNATURE_ADDR=$(SIGNATURE_ADDR) CONFIG=$(CONFIG) RTL_TEST=$(RTL_TEST) \
   	  SIM_OPTS=$(SIM_OPTS) GEN_OPTS=$(GEN_OPTS)"
   	+@$(MAKE) -C dv/uvm/core_eh2 --file wrapper.mk \
   	  OUT-DIR=$(abspath $(OUT-DIR)) \
   	  METADATA-DIR=$(abspath $(METADATA-DIR)) \

**逐段解释**：

* 第 L52-L62 行：``run`` target 把 ``CONFIG=$(CONFIG)`` 放入 metadata 的
  ``--args-list``。
* 第 L63-L74 行：metadata 创建后，Makefile 进入 :file:`dv/uvm/core_eh2/wrapper.mk`
  执行 ``$(GOAL)``。

**接口关系**：

* **被调用**：用户运行 ``make run GOAL=<stage> CONFIG=<profile>``。
* **调用**：调用 ``metadata.py`` 和 ``wrapper.mk``。
* **共享状态**：``CONFIG`` 在 staged flow 中不直接改 RTL，而是先写入 metadata。

§4  ``metadata.py`` — ``CONFIG`` 与 ``EH2_CONFIG`` 优先级
----------------------------------------------------------------

**职责**：metadata 创建阶段把命令行传入的配置名保存到 ``RegressionMetadata.eh2_config``，
并记录 :file:`eh2_configs.yaml` 的路径。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L390-L427``）：

.. code-block:: python

       md = RegressionMetadata()
       md.seed = int(args.get("SEED", 1) or 1)
       md.test_name = args.get("TEST", "all") or "all"
       md.simulator = args.get("SIMULATOR", "vcs") or "vcs"
       md.iterations = (int(args["ITERATIONS"])
                        if args.get("ITERATIONS", "") not in ("", None)
                        else None)
       md.waves = _str_to_bool(args.get("WAVES", "0"))
       md.coverage = _str_to_bool(args.get("COV", "0"))
       md.verbose = _str_to_bool(args.get("VERBOSE", "0"))
       md.iss = args.get("ISS", "spike") or "spike"
       md.signature_addr = args.get("SIGNATURE_ADDR", md.signature_addr)
       md.eh2_config = args.get("CONFIG", args.get("EH2_CONFIG", "default"))
       md.eh2_root = str(root)

**逐段解释**：

* 第 L390-L402 行：metadata 把常用 regression 变量写入对象，包括 seed、test、simulator、
  coverage 和 signature address。
* 第 L403 行：配置名优先读取 ``CONFIG``，如果没有再读取 ``EH2_CONFIG``，二者都缺失时使用
  ``default``。
* 第 L404-L427 行：metadata 继续保存仓库根目录和 canonical input 路径，其中
  ``md.eh2_configs`` 指向根目录下的 :file:`eh2_configs.yaml`。

**接口关系**：

* **被调用**：顶层 Makefile staged 分支调用。
* **调用**：后续 ``render_config_template.py`` 和 ``run_rtl.py`` 读取 metadata。
* **共享状态**：metadata 目录中的 ``eh2_config`` 是 staged flow 的配置选择状态。

§5  ``wrapper.mk:core_config`` — profile 到 riscv-dv setting
------------------------------------------------------------

**职责**：``core_config`` target 根据 metadata 中的 ``eh2_config`` 渲染
:file:`riscv_core_setting.tpl.sv`，生成 riscv-dv 使用的
:file:`riscv_core_setting.sv`。

**关键代码** （``dv/uvm/core_eh2/wrapper.mk:L66-L77``）：

.. code-block:: makefile

   $(BUILD-DIR) $(TESTS-DIR) $(METADATA-DIR):
   	@mkdir -p $@

   core_config: $(METADATA-DIR)/core.config.stamp
   $(METADATA-DIR)/core.config.stamp: scripts/render_config_template.py | $(BUILD-DIR) $(METADATA-DIR)
   	@echo Generating EH2 riscv-dv core configuration
   	$(verb)env PYTHONPATH=$(PYTHONPATH) \
   	  python3 scripts/render_config_template.py \
   	    --dir-metadata $(METADATA-DIR) \
   	    riscv_dv_extension/riscv_core_setting.tpl.sv \
   	    > riscv_dv_extension/riscv_core_setting.sv
   	@touch $@

**逐段解释**：

* 第 L66-L70 行：target 先确保 build、tests 和 metadata 目录存在，并把 stamp 文件作为
  ``core_config`` 的完成标记。
* 第 L71-L76 行：Makefile 调用 ``render_config_template.py``，传入 metadata 目录和 template，
  并把输出重定向为 ``riscv_core_setting.sv``。
* 第 L77 行：渲染完成后更新 stamp。

**接口关系**：

* **被调用**：riscv-dv generator build 依赖该 stamp。
* **调用**：调用 ``render_config_template.py``。
* **共享状态**：读 metadata，写 ``riscv_core_setting.sv``。

§6  ``render_config_template.py`` — 配置渲染语义
------------------------------------------------

**职责**：该脚本支持两种 template 语法：``{{ KEY }}`` token 替换，以及
``//% if KEY`` / ``//% endif`` 条件块。

**关键代码** （``dv/uvm/core_eh2/scripts/render_config_template.py:L19-L32``）：

.. code-block:: python

   def render_template(config_name: str, template_filename: str) -> str:
       """Render a small token template using values from eh2_configs.yaml."""
       cfg = get_config(config_name)
       params = cfg["parameters"]
       text = Path(template_filename).read_text(encoding="utf-8")
       rendered_lines = []
       keep_stack = [True]

       for line in text.splitlines():
           if_match = IF_RE.match(line)
           if if_match:
               key = if_match.group(1)
               keep_stack.append(keep_stack[-1] and bool(int(params.get(key, 0))))
               continue

**逐段解释**：

* 第 L19-L24 行：脚本先用 ``get_config`` 读取 profile，再读取 template 文本。
* 第 L25-L32 行：条件块使用 ``keep_stack``；缺失 key 在条件语义中按 0 处理，因此对应块不会输出。

**关键代码** （``dv/uvm/core_eh2/scripts/render_config_template.py:L46-L64``）：

.. code-block:: python

       def repl(match):
           key = match.group(1)
           if key == "CONFIG_NAME":
               return cfg["name"]
           if key not in params:
               raise KeyError(f"Unknown EH2 template key: {key}")
           return str(params[key])

       return TOKEN_RE.sub(repl, text)

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description=__doc__)
       parser.add_argument("template_filename")
       parser.add_argument("--dir-metadata", type=Path, required=True)
       args = parser.parse_args(argv)
       md = RegressionMetadata.construct_from_metadata_dir(args.dir_metadata)
       sys.stdout.write(render_template(md.eh2_config, args.template_filename))

**逐段解释**：

* 第 L46-L52 行：token 替换要求 key 存在于 profile 参数，只有 ``CONFIG_NAME`` 是特例。
* 第 L54-L64 行：CLI 从 metadata 目录读取 ``md.eh2_config``，再渲染传入 template。

**接口关系**：

* **被调用**：``wrapper.mk:core_config`` 调用。
* **调用**：调用 ``RegressionMetadata.construct_from_metadata_dir`` 和 ``eh2_cmd.get_config``。
* **共享状态**：读取 metadata 与 YAML，向 stdout 输出生成文本。

§7  riscv-dv template — 当前真正使用的 profile 参数
---------------------------------------------------

**职责**：当前 riscv-dv setting template 只消费 ``NUM_THREADS``、``ATOMIC_ENABLE`` 和
``BITMANIP_ZBA/ZBB/ZBC/ZBS``。其它 YAML 参数目前不会自动出现在该 template 输出中。

**关键代码** （``dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv:L20-L49``）：

.. code-block:: systemverilog

   parameter int NUM_HARTS = {{ NUM_THREADS }};
   parameter satp_mode_t SATP_MODE = BARE;

   privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE};

   riscv_instr_name_t unsupported_instr[] = {};

   bit support_unaligned_load_store = 1'b1;

   // EH2 supports RV32IMAC plus configuration-selected bitmanip groups.
   riscv_instr_group_t supported_isa[$] = {
     RV32I,
     RV32M,
   //% if ATOMIC_ENABLE
     RV32A,
   //% endif
     RV32C
   //% if BITMANIP_ZBA
     ,RV32ZBA
   //% endif

**逐段解释**：

* 第 L20 行：``NUM_THREADS`` 只被替换成 riscv-dv 的 ``NUM_HARTS``。
* 第 L21-L27 行：SATP、privileged mode、unsupported instruction 和 unaligned load/store 是固定设置。
* 第 L29-L49 行：ISA 列表固定包含 RV32I、RV32M、RV32C；Atomic 和 bitmanip 由条件块决定。

**接口关系**：

* **被调用**：``render_config_template.py`` 读取该 template。
* **调用**：无。
* **共享状态**：渲染后写入 riscv-dv extension 目录。

§8  direct ``run_rtl.py`` — ``--config`` 保存但不驱动 compile
-------------------------------------------------------------

**职责**：direct RTL runner 提供 ``--config`` 参数并写入 metadata 对象，但当前
``build_compile_cmd`` 没有把该字段传给顶层 compile。

**关键代码** （``dv/uvm/core_eh2/scripts/run_rtl.py:L47-L51``）：

.. code-block:: python

   def build_compile_cmd(md: RegressionMetadata, sim_cfg: dict) -> str:
       """Build the compilation command."""
       del sim_cfg
       return "make -C {} compile SIMULATOR={} WAVES={} COV={}".format(
           md.eh2_root, md.simulator, int(md.waves), int(md.coverage))

**逐段解释**：

* 第 L47-L51 行：compile command 只包含 repo 根目录、simulator、waves 和 coverage；
  没有 ``CONFIG``、``EH2_CONFIG`` 或 YAML define。

**关键代码** （``dv/uvm/core_eh2/scripts/run_rtl.py:L326-L373``）：

.. code-block:: python

   def main(argv=None) -> int:
       parser = argparse.ArgumentParser(description="EH2 RTL Simulation Runner")
       parser.add_argument("--test", default="", help="Test name")
       parser.add_argument("--seed", type=int, default=1, help="Random seed")
       parser.add_argument("--binary", default="", help="Test binary path")
       parser.add_argument("--simulator", default="vcs", choices=["vcs", "xlm", "questa"])
       parser.add_argument("--config", default="default", help="EH2 configuration")
       parser.add_argument("--waves", action="store_true", help="Enable waveform dump")
       parser.add_argument("--coverage", action="store_true", help="Enable coverage")
       parser.add_argument("--timeout", type=int, default=10000000, help="Sim timeout (ns)")
       parser.add_argument("--rtl-test", default="core_eh2_base_test", help="UVM test class")
       parser.add_argument("--sim-opts", default="", help="Simulation plusargs")

**逐段解释**：

* 第 L326-L337 行：CLI 确实定义 ``--config``，默认值为 ``default``。
* 第 L367-L373 行：非 metadata 模式创建 ``RegressionMetadata`` 时把 ``args.config`` 写入
  ``md.eh2_config``。

**接口关系**：

* **被调用**：direct simulation 或 staged ``rtl_sim_run`` 调用。
* **调用**：调用 ``build_compile_cmd`` 和 ``build_sim_cmd``。
* **共享状态**：保存 ``md.eh2_config``，但 compile command 当前未消费。

§9  ``PROFILE`` — sign-off 阶段集合，不是 EH2 profile
------------------------------------------------------

**职责**：顶层 ``PROFILE`` 变量传给 :file:`signoff.py`，用于选择 sign-off stage 集合。
它与 :file:`eh2_configs.yaml` 的 profile 名称无关。

**关键代码** （``dv/uvm/core_eh2/scripts/signoff.py:L37-L44``）：

.. code-block:: python

   PROFILE_STAGES = {
       "quick": ["smoke", "directed"],
       "cosim": ["smoke", "cosim"],
       "riscvdv_smoke": ["riscvdv"],
       "nightly": ["smoke", "directed", "cosim", "riscvdv"],
       "full": ["smoke", "directed", "cosim", "riscvdv", "lint", "csr_unit",
                "compliance", "formal", "syn"],
   }

**逐段解释**：

* 第 L37-L44 行：``PROFILE`` 的合法值来自 ``PROFILE_STAGES``，例如 ``quick``、
  ``cosim``、``riscvdv_smoke``、``nightly`` 和 ``full``。这些值表示 stage 集合。

**关键代码** （``Makefile:L607-L618``）：

.. code-block:: makefile

   signoff:
   	@echo "=== [signoff] profile=$(PROFILE) gate_only=$(GATE_ONLY) out=$(SIGNOFF_OUT) ==="
   	python3 $(SCRIPTS_DIR)/signoff.py \
   	  --profile $(PROFILE) \
   	  --simulator $(SIMULATOR) \
   	  --seed $(SEED) \
   	  --parallel $(PARALLEL) \
   	  --output $(SIGNOFF_OUT) \
   	  $(if $(filter 1,$(GATE_ONLY)),--gate-only,) \
   	  $(if $(SIGNOFF_ITERATIONS),--iterations $(SIGNOFF_ITERATIONS),) \
   	  $(if $(filter 1,$(LEC_KNOWN_LIMITED)),--lec-known-limited,) \
   	  $(if $(filter 1,$(LEC_BLOCKLEVEL)),--lec-blocklevel --lec-summary-path $(LEC_SUMMARY_PATH),) \

**逐段解释**：

* 第 L607-L614 行：顶层 ``make signoff`` 把 ``PROFILE`` 映射为 ``signoff.py --profile``。
* 第 L615-L618 行：``GATE_ONLY``、``SIGNOFF_ITERATIONS`` 和 LEC 相关变量也在这里转成命令行参数。

**接口关系**：

* **被调用**：用户运行 ``make signoff PROFILE=<name>``。
* **调用**：调用 ``signoff.py``。
* **共享状态**：``PROFILE`` 控制 stage 列表，不控制 EH2 RTL profile。

§10  ``signoff.py`` precheck — default 必须单线程
-------------------------------------------------

**职责**：sign-off precheck 对 :file:`eh2_configs.yaml` 做最小健康检查：文件存在、可解析，
并确认 ``default.parameters.NUM_THREADS`` 等于 1。

**关键代码** （``dv/uvm/core_eh2/scripts/signoff.py:L182-L193``）：

.. code-block:: python

       cfg_path = EH2_ROOT / "eh2_configs.yaml"
       if cfg_path.exists():
           try:
               cfg = _load_yaml(cfg_path) or {}
               default_threads = cfg.get("default", {}).get(
                   "parameters", {}).get("NUM_THREADS")
               add("default_single_thread", default_threads == 1,
                   "default NUM_THREADS={}".format(default_threads))
           except Exception as err:
               add("eh2_config_parse", False, "{}: {}".format(cfg_path, err))
       else:
           add("eh2_config", False, str(cfg_path))

**逐段解释**：

* 第 L182-L185 行：precheck 固定寻找根目录 :file:`eh2_configs.yaml`，存在时解析 YAML。
* 第 L186-L189 行：只检查 default profile 的 ``NUM_THREADS`` 是否为 1。
* 第 L190-L193 行：解析失败或文件缺失都会记录失败项。

**接口关系**：

* **被调用**：sign-off precheck 阶段。
* **调用**：调用 ``_load_yaml`` 和 ``add``。
* **共享状态**：只读 YAML。

§11  完整 RTL 参数快照 — 不等同于 YAML profile
-----------------------------------------------

**职责**：:file:`syn/include/eh2_param.vh` 是综合侧完整 ``eh2_param_t`` 默认快照。
它包含大量 YAML 未覆盖的派生参数，因此不能把 ``eh2_configs.yaml`` 写成完整 RTL 参数来源。

**关键代码** （``syn/include/eh2_param.vh:L1-L17``）：

.. code-block:: systemverilog

   parameter eh2_param_t pt = '{
       ATOMIC_ENABLE          : 5'h01         ,
       BHT_ADDR_HI            : 8'h09         ,
       BHT_ADDR_LO            : 6'h03         ,
       BHT_ARRAY_DEPTH        : 16'h0080       ,
       BHT_GHR_HASH_1         : 5'h00         ,
       BHT_GHR_SIZE           : 8'h07         ,
       BHT_SIZE               : 17'h00200      ,
       BITMANIP_ZBA           : 5'h01         ,
       BITMANIP_ZBB           : 5'h01         ,
       BITMANIP_ZBC           : 5'h01         ,
       BITMANIP_ZBE           : 5'h00         ,
       BITMANIP_ZBF           : 5'h00         ,
       BITMANIP_ZBP           : 5'h00         ,
       BITMANIP_ZBR           : 5'h00         ,
       BITMANIP_ZBS           : 5'h01         ,

**逐段解释**：

* 第 L1 行：该文件直接声明 ``eh2_param_t pt``。
* 第 L2-L17 行：完整参数包含 Atomic、BHT 细分参数和多组 bitmanip；YAML profile 只覆盖其中一部分高层 knob。

**关键代码** （``syn/include/eh2_param.vh:L166-L179``）：

.. code-block:: systemverilog

       NUM_THREADS            : 6'h01         ,
       PIC_2CYCLE             : 5'h01         ,
       PIC_BASE_ADDR          : 36'h0F00C0000  ,
       PIC_BITS               : 9'h00F        ,
       PIC_INT_WORDS          : 8'h04         ,
       PIC_REGION             : 8'h0F         ,
       PIC_SIZE               : 13'h0020       ,
       PIC_TOTAL_INT          : 12'h07F        ,
       PIC_TOTAL_INT_PLUS1    : 13'h0080       ,
       RET_STACK_SIZE         : 8'h04         ,
       SB_BUS_ID              : 5'h01         ,
       SB_BUS_PRTY            : 6'h02         ,
       SB_BUS_TAG             : 8'h01         ,
       TIMER_LEGAL_EN         : 5'h01

**逐段解释**：

* 第 L166-L174 行：完整参数中的 ``NUM_THREADS`` 和 PIC 参数使用 SystemVerilog literal；
  YAML ``PIC_TOTAL_INT`` 是高层整数输入，不包含 ``PIC_BASE_ADDR`` 等字段。
* 第 L175-L179 行：return stack、SB bus 和 timer 参数也在 ``eh2_param_t`` 中，当前 YAML
  只覆盖 ``RET_STACK_SIZE`` 和部分 bus tag。

**接口关系**：

* **被调用**：综合和 RTL include 路径使用该参数快照。
* **调用**：无。
* **共享状态**：``pt`` 是完整 RTL 参数结构。

§12  集成命令示例
-----------------

**staged riscv-dv 配置渲染**：

.. code-block:: bash

   make run GOAL=core_config CONFIG=default
   make run GOAL=core_config CONFIG=minimal
   make run GOAL=core_config CONFIG=dual_thread
   make run GOAL=core_config CONFIG=ahb_lite

这些命令会经过 metadata 和 ``wrapper.mk:core_config``，最终重写
:file:`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv`。

**sign-off profile 选择**：

.. code-block:: bash

   make signoff PROFILE=quick
   make signoff PROFILE=cosim
   make signoff PROFILE=nightly
   make signoff PROFILE=full

这些命令选择的是 sign-off stage 集合，不会选择 :file:`eh2_configs.yaml` 中的 EH2 profile。

**direct simulation 边界**：

.. code-block:: bash

   python3 dv/uvm/core_eh2/scripts/run_rtl.py \
     --test directed_smoke \
     --config minimal \
     --simulator vcs

该命令会把 ``minimal`` 写入 ``md.eh2_config``，但当前 ``build_compile_cmd`` 不把它转成
compile define；若需要 RTL 参数变化，必须先确认具体 compile/filelist 生成链路。

§13  参考资料
--------------

* :ref:`appendix_e_config/eh2_configs` — YAML profile 与消费脚本源码字典。
* :doc:`../06_flows/regression_flow` — staged regression flow。
* :doc:`../06_flows/signoff_flow` — sign-off profile 与 gate。
* :file:`/home/host/eh2-veri/eh2_configs.yaml`
* :file:`/home/host/eh2-veri/Makefile`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/render_config_template.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv`
* :file:`/home/host/eh2-veri/syn/include/eh2_param.vh`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页面向的读者是工具使用者、SoC 集成人员还是 release 维护者？
2. 读者需要设置哪些环境变量或 Make 变量才能复现页面中的命令？
3. 哪些连接或脚本属于验证平台便利设施，不能写成真实 SoC 集成约束？
4. NC/Incisive 在本页中是完整备选 simulator，还是被误写成单测波形专用路径？
5. 本页和 build、regression、sign-off 章节之间的交叉引用是否足以让读者继续排查？
