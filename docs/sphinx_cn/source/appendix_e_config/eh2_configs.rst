.. _eh2_configs:
.. _appendix_e_config/eh2_configs:

EH2 配置矩阵 — 详细参考
========================

:status: draft
:source: eh2_configs.yaml; dv/uvm/core_eh2/scripts/eh2_cmd.py; dv/uvm/core_eh2/scripts/render_config_template.py; dv/uvm/core_eh2/scripts/metadata.py; dv/uvm/core_eh2/wrapper.mk
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  源码边界与当前配置事实
---------------------------

本章描述当前仓库中 :file:`eh2_configs.yaml` 的实际结构，以及它在 staged
riscv-dv flow、metadata、RTL simulation runner 和 sign-off precheck 中的消费路径。
旧版本文档曾描述 8 个 profile 和 180+ 参数；当前源码并不支持该说法。当前
:file:`eh2_configs.yaml` 只有 4 个顶层 profile：``default``、``minimal``、
``dual_thread`` 和 ``ahb_lite``。各 profile 的 ``parameters`` 数量分别为
23、14、15、15，且并非直接等同于 :file:`syn/include/eh2_param.vh` 中完整
``eh2_param_t`` 参数集合。

配置数据流如下：

::

   make run GOAL=<stage> CONFIG=<profile>
       |
       v
   metadata.py 记录 md.eh2_config 和 md.eh2_configs
       |
       v
   wrapper.mk: core_config
       |
       v
   render_config_template.py
       |
       v
   eh2_cmd.py:get_config()
       |
       v
   eh2_configs.yaml -> riscv_core_setting.sv

direct ``run_rtl.py`` 路径与 staged 路径不同：``run_rtl.py`` 会保存
``md.eh2_config``，但当前 ``build_compile_cmd()`` 没有把该 profile 转换成 RTL
compile define。因此本文把 :file:`eh2_configs.yaml` 定义为验证 flow 配置输入，主要服务
riscv-dv core setting 渲染和 sign-off 配置检查，而不是把它写成完整 RTL 参数生成器。

§2  ``eh2_configs.yaml`` — 顶层 schema
--------------------------------------

**职责**：该 YAML 文件定义 profile 名称、描述和参数字典。每个 profile 下都有
``description`` 和 ``parameters`` 两层。

**关键代码** （``eh2_configs.yaml:L1-L7``）：

.. code-block:: yaml

   # EH2 Configuration Profiles
   # This file defines different EH2 configurations for verification.
   # Each profile specifies the parameters to use when building the DUT.

   default:
     description: "Default EH2 configuration (AXI4, single-thread, full features)"
     parameters:

**逐段解释**：

* 第 L1-L3 行：文件注释把该 YAML 定义为 verification 用的 EH2 configuration profiles，
  每个 profile 给出构建 DUT 时使用的参数。
* 第 L5-L7 行：``default`` profile 由 ``description`` 和 ``parameters`` 组成。后续
  ``eh2_cmd.get_config`` 正是按这两个键读取。

**接口关系**：

* **被调用**：``eh2_cmd.get_config`` 和 ``signoff.py`` 的 precheck 读取该 YAML。
* **调用**：YAML 本身不调用代码。
* **共享状态**：profile 名称和 ``parameters`` 字典是后续 template 渲染的共享输入。

§3  ``default`` profile — AXI4 单线程完整特性
---------------------------------------------

**职责**：``default`` 是顶层 Makefile 和 metadata 的默认 profile。当前源码把它描述为
AXI4、single-thread、full features，并开启 DCCM、ICCM、ICache、Atomic 与 4 组 bitmanip。

**关键代码** （``eh2_configs.yaml:L5-L38``）：

.. code-block:: yaml

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
       # DCCM
       DCCM_ENABLE: 1
       DCCM_SIZE: 64

**逐段解释**：

* 第 L5-L9 行：``default`` 明确是单线程，``NUM_THREADS`` 为 1。
* 第 L10-L17 行：bus 相关参数打开 ``BUILD_AXI4`` 和 ``BUILD_AXI_NATIVE``，
  关闭 ``BUILD_AHB_LITE``，并给 LSU/IFU/SB/DMA 设置 tag 宽度。
* 第 L18-L20 行：DCCM 在默认 profile 中启用，``DCCM_SIZE`` 为 64。

**关键代码** （``eh2_configs.yaml:L21-L38``）：

.. code-block:: yaml

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

**逐段解释**：

* 第 L21-L26 行：ICCM 和 ICache 都启用，ICCM size 为 64，ICache size 为 32。
* 第 L27-L32 行：``ATOMIC_ENABLE`` 和 ``BITMANIP_ZBA/ZBB/ZBC/ZBS`` 都为 1；
  riscv-dv template 会据此保留 RV32A 和对应 bitmanip ISA group。
* 第 L33-L38 行：``PIC_TOTAL_INT`` 为 127，BHT/BTB size 均为 512，return stack size 为 4。

**接口关系**：

* **被调用**：Makefile 默认 ``CONFIG ?= default``；sign-off precheck 检查该 profile 的
  ``NUM_THREADS`` 是否为 1。
* **调用**：无。
* **共享状态**：``default`` 参数通过 ``get_config("default")`` 进入 template 渲染。

§4  ``minimal`` profile — 关闭 cache/DCCM/ICCM 与扩展
------------------------------------------------------

**职责**：``minimal`` profile 用 YAML 参数表达简化配置。当前源码关闭 DCCM、ICCM、ICache、
Atomic 和 bitmanip，并把 interrupt、BHT、BTB 参数调小。

**关键代码** （``eh2_configs.yaml:L40-L57``）：

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

**逐段解释**：

* 第 L40-L43 行：``minimal`` 的描述写明 no ICache、no DCCM 和 few interrupts，线程数仍为 1。
* 第 L44-L48 行：bus 仍是 AXI4/AHB-Lite 二选一中的 AXI4 路径，但 DCCM、ICCM 和 ICache
  都关闭。
* 第 L49-L53 行：Atomic 与 4 组 bitmanip 均关闭；template 条件块会删除对应 ISA group。
* 第 L54-L57 行：``PIC_TOTAL_INT`` 降为 16，BHT/BTB size 为 64。

**接口关系**：

* **被调用**：用户通过 ``CONFIG=minimal`` 或 metadata ``eh2_config=minimal`` 选择该 profile。
* **调用**：无。
* **共享状态**：``minimal`` 参数被 ``render_config_template`` 用于条件渲染。

§5  ``dual_thread`` profile — 双线程配置输入
--------------------------------------------

**职责**：``dual_thread`` 只在 YAML 层把 ``NUM_THREADS`` 设置为 2，并保留 default
相同的一组主要 feature enable。

**关键代码** （``eh2_configs.yaml:L58-L76``）：

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

**逐段解释**：

* 第 L58-L62 行：profile 名称是 ``dual_thread``，不是旧文档中的 ``2thread``；
  ``NUM_THREADS`` 为 2。
* 第 L63-L69 行：AXI4、DCCM、ICCM 和 ICache 均启用，DCCM/ICCM size 为 64，
  ICache size 为 32。
* 第 L70-L76 行：Atomic 和 bitmanip 均启用，``PIC_TOTAL_INT`` 为 127。

**接口关系**：

* **被调用**：staged flow 的 ``CONFIG=dual_thread`` 会让 template 中 ``NUM_HARTS``
  渲染为 2。
* **调用**：无。
* **共享状态**：``NUM_THREADS=2`` 进入 riscv-dv setting，但 direct RTL compile 命令当前不使用该 YAML 自动改 RTL 参数。

§6  ``ahb_lite`` profile — AHB-Lite bus 选择
--------------------------------------------

**职责**：``ahb_lite`` profile 在 YAML 层关闭 ``BUILD_AXI4`` 并打开 ``BUILD_AHB_LITE``。
其它主要 cache、memory 和 ISA enable 与 ``dual_thread`` 之外的 default 类似。

**关键代码** （``eh2_configs.yaml:L77-L94``）：

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

**逐段解释**：

* 第 L77-L82 行：profile 名称为 ``ahb_lite``，线程数为 1，bus selector 从
  ``BUILD_AXI4=0`` 与 ``BUILD_AHB_LITE=1`` 表达。
* 第 L83-L88 行：DCCM、ICCM 和 ICache 仍启用，并保持 size 参数。
* 第 L89-L94 行：Atomic、bitmanip 和 PIC interrupt 数保持开启配置。

**接口关系**：

* **被调用**：用户通过 ``CONFIG=ahb_lite`` 选择该 profile。
* **调用**：无。
* **共享状态**：当前 template 只消费其中部分键；未在 template 中引用的键不会自动影响生成文件。

§7  ``eh2_cmd.get_config()`` — YAML 读取与错误处理
--------------------------------------------------

**职责**：``get_config`` 是 Python 侧读取 :file:`eh2_configs.yaml` 的基础函数。它返回
profile 名称、描述和参数字典，并对未知 profile 抛出 ``KeyError``。

**关键代码** （``dv/uvm/core_eh2/scripts/eh2_cmd.py:L13-L27``）：

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

**逐段解释**：

* 第 L13-L17 行：函数固定从仓库根目录的 :file:`eh2_configs.yaml` 读取 YAML，并使用
  ``yaml.safe_load``。
* 第 L18-L21 行：profile 名称不存在时抛 ``KeyError``，错误消息包含所有可用 profile 的排序列表。
* 第 L22-L27 行：函数复制 ``parameters`` 字典，并返回 ``name``、``description`` 和
  ``parameters`` 三个字段。

**接口关系**：

* **被调用**：``render_config_template``、``eh2_cmd`` 命令行入口和
  ``render_compile_defines`` 调用它。
* **调用**：调用 ``yaml.safe_load`` 和 ``setup_imports._EH2_ROOT``。
* **共享状态**：读取 :file:`eh2_configs.yaml`，不写文件。

§8  ``get_isas_for_config()`` — ISA 字符串推导
----------------------------------------------

**职责**：该函数从 profile 参数中提取 bitmanip 开关，生成 GCC 和 ISS ISA 字符串。

**关键代码** （``dv/uvm/core_eh2/scripts/eh2_cmd.py:L30-L45``）：

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

**逐段解释**：

* 第 L30-L34 行：基础 ISA 字符串固定为 ``rv32imac``。
* 第 L35-L42 行：函数只检查 ``BITMANIP_ZBA/ZBB/ZBC/ZBS`` 四个开关，值经 ``int`` 转换后为真才进入
  ``bitmanip`` 列表。
* 第 L43-L45 行：只要任一 bitmanip 开启，GCC 字符串固定返回 ``rv32imac_zba_zbb_zbc_zbs``，
  ISS 字符串按实际开启列表拼接；全部关闭时二者均为 ``rv32imac``。

**接口关系**：

* **被调用**：当前搜索结果未显示主 flow 调用该函数；它属于 ``eh2_cmd.py`` 提供的 helper。
* **调用**：只读取传入 ``cfg`` 字典。
* **共享状态**：无外部状态写入。

§9  ``render_compile_defines()`` — 简单 define 渲染
----------------------------------------------------------------

**职责**：该函数把 profile 中的整数参数转换为 ``+define+KEY=VALUE`` 字符串。当前
``run_rtl.py`` 的 compile 命令未调用它，因此它是 helper 能力，不是 direct compile 主路径。

**关键代码** （``dv/uvm/core_eh2/scripts/eh2_cmd.py:L48-L69``）：

.. code-block:: python

   def render_compile_defines(config_name: str) -> str:
       """Render Verilog defines for simple simulator command integrations."""
       cfg = get_config(config_name)
       defines = []
       for key, value in sorted(cfg["parameters"].items()):
           if isinstance(value, int):
               defines.append("+define+{}={}".format(key, value))
       return " ".join(defines)

   if __name__ == "__main__":
       import argparse

       parser = argparse.ArgumentParser(description="EH2 config helper")
       parser.add_argument("config", nargs="?", default="default")
       parser.add_argument("--defines", action="store_true")
       args = parser.parse_args()

       if args.defines:
           print(render_compile_defines(args.config))
       else:
           print(get_config(args.config))

**逐段解释**：

* 第 L48-L55 行：函数调用 ``get_config``，按 key 排序遍历参数，只把 Python ``int`` 类型值输出成
  Verilog define。
* 第 L58-L69 行：脚本命令行默认打印 profile 字典；带 ``--defines`` 时打印 define 串。

**接口关系**：

* **被调用**：可由命令行 ``python3 dv/uvm/core_eh2/scripts/eh2_cmd.py <profile> --defines``
  调用。
* **调用**：调用 ``get_config``。
* **共享状态**：只读 YAML，不写文件。

§10  ``render_config_template.py`` — token 与条件块渲染
-------------------------------------------------------

**职责**：该脚本从 metadata 读取 ``eh2_config``，加载 YAML profile，并渲染小型 token
template。它支持 ``{{ KEY }}`` 替换和 ``//% if KEY`` / ``//% endif`` 条件块。

**关键代码** （``dv/uvm/core_eh2/scripts/render_config_template.py:L14-L24``）：

.. code-block:: python

   TOKEN_RE = re.compile(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")
   IF_RE = re.compile(r"^\s*//%\s*if\s+([A-Za-z0-9_]+)\s*$")
   ENDIF_RE = re.compile(r"^\s*//%\s*endif\s*$")


   def render_template(config_name: str, template_filename: str) -> str:
       """Render a small token template using values from eh2_configs.yaml."""
       cfg = get_config(config_name)
       params = cfg["parameters"]
       text = Path(template_filename).read_text(encoding="utf-8")
       rendered_lines = []

**逐段解释**：

* 第 L14-L16 行：三个正则分别识别 token、条件开始和条件结束。
* 第 L19-L24 行：``render_template`` 先调用 ``get_config``，再读取 template 文件并初始化输出行列表。

**关键代码** （``dv/uvm/core_eh2/scripts/render_config_template.py:L25-L44``）：

.. code-block:: python

       keep_stack = [True]

       for line in text.splitlines():
           if_match = IF_RE.match(line)
           if if_match:
               key = if_match.group(1)
               keep_stack.append(keep_stack[-1] and bool(int(params.get(key, 0))))
               continue
           if ENDIF_RE.match(line):
               if len(keep_stack) == 1:
                   raise ValueError("Unexpected //% endif in {}".format(
                       template_filename))
               keep_stack.pop()
               continue
           if keep_stack[-1]:
               rendered_lines.append(line)

       if len(keep_stack) != 1:
           raise ValueError("Unclosed //% if block in {}".format(template_filename))
       text = "\n".join(rendered_lines) + "\n"

**逐段解释**：

* 第 L25-L32 行：条件块使用 ``keep_stack`` 支持嵌套；未知 key 默认取 0，因此条件块被丢弃。
* 第 L33-L38 行：遇到多余 ``//% endif`` 会抛 ``ValueError``。
* 第 L39-L44 行：只有当前 ``keep_stack`` 为真时才保留行；循环结束后如果还有未关闭条件块也会抛
  ``ValueError``。

**关键代码** （``dv/uvm/core_eh2/scripts/render_config_template.py:L46-L65``）：

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

* 第 L46-L52 行：token 替换把 ``CONFIG_NAME`` 特判为 profile 名称；其它 key 必须存在于
  ``parameters``，否则抛 ``KeyError``。
* 第 L54 行：替换通过 ``TOKEN_RE.sub`` 一次完成。
* 第 L57-L65 行：命令行入口要求 template 文件和 ``--dir-metadata``，从 metadata 读取
  ``md.eh2_config`` 后输出渲染文本。

**接口关系**：

* **被调用**：``wrapper.mk:core_config`` 调用该脚本。
* **调用**：调用 ``RegressionMetadata.construct_from_metadata_dir`` 和 ``get_config``。
* **共享状态**：读取 metadata 目录和 YAML，输出到 stdout，由 Makefile 重定向到生成文件。

§11  riscv-dv core setting template — 实际消费的参数键
------------------------------------------------------

**职责**：:file:`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv`
是当前 staged flow 中被渲染的模板。它实际使用 ``NUM_THREADS``、``ATOMIC_ENABLE`` 和
4 个 bitmanip 开关。

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
   //% if BITMANIP_ZBB
     ,RV32ZBB
   //% endif
   //% if BITMANIP_ZBC
     ,RV32ZBC
   //% endif
   //% if BITMANIP_ZBS
     ,RV32ZBS
   //% endif
   };

**逐段解释**：

* 第 L20 行：``NUM_THREADS`` 只在模板中替换为 ``NUM_HARTS``。
* 第 L21-L27 行：SATP、privileged mode、unsupported instruction list 和 unaligned support
  是模板中的固定值，不来自 YAML。
* 第 L29-L49 行：ISA group 固定包含 ``RV32I``、``RV32M`` 和 ``RV32C``；
  ``RV32A`` 由 ``ATOMIC_ENABLE`` 控制，``RV32ZBA/ZBB/ZBC/ZBS`` 分别由同名 bitmanip key 控制。

**接口关系**：

* **被调用**：``render_config_template.py`` 读取并渲染该模板。
* **调用**：模板本身不调用代码。
* **共享状态**：渲染结果写入 :file:`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.sv`。

§12  ``wrapper.mk:core_config`` — staged flow 生成点
----------------------------------------------------

**职责**：``wrapper.mk`` 的 ``core_config`` target 调用
``render_config_template.py``，把 riscv-dv template 渲染成 ``riscv_core_setting.sv``。

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

* 第 L66-L67 行：build、tests 和 metadata 目录通过 order-only prerequisite 创建。
* 第 L69-L70 行：``core_config`` 的实际产物是 ``$(METADATA-DIR)/core.config.stamp``。
* 第 L71-L76 行：Makefile 设置 ``PYTHONPATH`` 后运行 ``render_config_template.py``，
  指定 metadata 目录和 template 文件，并把 stdout 重定向到 ``riscv_core_setting.sv``。
* 第 L77 行：渲染成功后 touch stamp，供后续 riscv-dv build 依赖。

**接口关系**：

* **被调用**：``riscvdv.mk`` 中 ``instr_gen_build`` 依赖 ``CORE-CONFIG-STAMP``。
* **调用**：调用 ``scripts/render_config_template.py``。
* **共享状态**：读 ``$(METADATA-DIR)``，写 ``riscv_core_setting.sv`` 和 stamp 文件。

§13  ``riscvdv.mk`` — core_config 对随机指令生成器的依赖
---------------------------------------------------------

**职责**：``riscvdv.mk`` 把 core configuration stamp 接入 riscv-dv generator build
依赖链，确保 generator 构建前先生成 core setting。

**关键代码** （``dv/uvm/core_eh2/scripts/riscvdv.mk:L11-L18``）：

.. code-block:: makefile

   CORE-CONFIG-STAMP = $(METADATA-DIR)/core.config.stamp
   core_config: $(CORE-CONFIG-STAMP)
   core-config-var-deps := EH2_CONFIG

   INSTR-GEN-BUILD-STAMP = $(METADATA-DIR)/instr.gen.build.stamp
   instr_gen_build: $(METADATA-DIR)/instr.gen.build.stamp
   instr-gen-build-var-deps := SIMULATOR SIGNATURE_ADDR

**逐段解释**：

* 第 L11-L13 行：``CORE-CONFIG-STAMP`` 指向 metadata 目录下的 stamp，并把
  ``EH2_CONFIG`` 标为 core config 变量依赖。
* 第 L15-L18 行：instruction generator build stamp 是另一个 stamp，变量依赖包括
  simulator 和 signature address。

**关键代码** （``dv/uvm/core_eh2/scripts/riscvdv.mk:L36-L45``）：

.. code-block:: makefile

   $(METADATA-DIR)/instr.gen.build.stamp: \
     $(instr-gen-build-vars-prereq) $(riscv-dv-files) $(CORE-CONFIG-STAMP) \
     scripts/build_instr_gen.py \
     | $(BUILD-DIR)
           @echo Building randomized test generator
           $(verb)env PYTHONPATH=$(PYTHONPATH) \
             scripts/build_instr_gen.py \
               --dir-metadata $(METADATA-DIR)
           $(call dump-vars,$(ig-build-vars-path),gen,$(instr-gen-build-var-deps))
           @touch $@

**逐段解释**：

* 第 L36-L39 行：``instr.gen.build.stamp`` 明确依赖 ``$(CORE-CONFIG-STAMP)``，所以 core
  setting 先于 generator build。
* 第 L40-L45 行：构建 generator 后 dump 变量依赖并 touch stamp。

**接口关系**：

* **被调用**：staged flow 执行 ``instr_gen_build`` 或依赖它的 target。
* **调用**：调用 ``scripts/build_instr_gen.py``。
* **共享状态**：读取 core config stamp，写 instr-gen build stamp。

§14  ``metadata.py`` — CONFIG 写入 metadata
-------------------------------------------

**职责**：metadata 创建阶段从 Makefile 传入的 ``CONFIG`` 或 ``EH2_CONFIG`` 读取 profile 名称，
并记录 canonical input 文件路径。

**关键代码** （``dv/uvm/core_eh2/scripts/metadata.py:L44-L80``）：

.. code-block:: python

       # EH2 configuration
       eh2_config: str = "default"  # default, fast, secure
       eh2_root: str = ""

       # Directories
       work_dir: str = ""
       build_dir: str = ""
       out_dir: str = ""
       log_dir: str = ""
       binary_dir: str = ""
       coverage_dir: str = ""
       dir_out: str = ""
       dir_metadata: str = ""
       dir_build: str = ""
       dir_run: str = ""
       dir_tests: str = ""
       dir_tb: str = ""

**逐段解释**：

* 第 L44-L46 行：metadata 数据类有 ``eh2_config`` 字段，默认值为 ``default``。行尾旧注释中的
  ``fast, secure`` 不对应当前 YAML profile，本文按 YAML 实际 profile 描述。
* 第 L48-L64 行：metadata 同时记录 work/build/out/log/binary/coverage 等目录，供后续 staged target 读取。

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

* 第 L390-L402 行：metadata 创建函数把 seed、test、simulator、iterations、waves、coverage、
  verbosity、ISS 和 signature address 从参数列表写入对象。
* 第 L403 行：``eh2_config`` 优先取 ``CONFIG``，没有时取 ``EH2_CONFIG``，再没有才是 ``default``。
* 第 L404-L427 行：metadata 继续记录仓库根目录、输出目录和 canonical input 文件，其中
  ``md.eh2_configs`` 在第 L426 行设置为仓库根的 :file:`eh2_configs.yaml`。

**接口关系**：

* **被调用**：顶层 Makefile staged 分支调用 ``metadata.py --op create_metadata``。
* **调用**：metadata 创建后被 ``render_config_template`` 和 ``run_rtl.py`` 读取。
* **共享状态**：写 metadata 目录中的序列化字段，包含 ``eh2_config`` 和 ``eh2_configs``。

§15  顶层 Makefile — CONFIG 从用户入口进入 metadata
---------------------------------------------------

**职责**：顶层 Makefile 在 ``GOAL`` 非空的 staged 分支中定义 ``CONFIG ?= default``，
并把它写入 metadata 参数列表。

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
   OUT ?= out
   OUT-DIR := $(dir $(OUT)/)
   METADATA-DIR := $(OUT-DIR)metadata

   export PYTHONPATH := $(shell cd dv/uvm/core_eh2 && python3 -c 'from scripts.setup_imports import get_pythonpath; print(get_pythonpath())')

**逐段解释**：

* 第 L30-L33 行：staged 分支只有 ``GOAL`` 非空时生效，``CONFIG`` 默认值为 ``default``。
* 第 L34-L45 行：同一分支还定义 test、simulator、waves、coverage、RTL test、ISS 和
  signature address 等变量。
* 第 L46-L50 行：输出目录和 metadata 目录在这里派生，``PYTHONPATH`` 由
  ``scripts.setup_imports.get_pythonpath`` 生成。

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
             PRJ_DIR=$(CURDIR) \

**逐段解释**：

* 第 L52-L62 行：``run`` target 调用 metadata 创建命令，并把 ``CONFIG=$(CONFIG)`` 放入
  ``--args-list``。
* 第 L63-L74 行：metadata 创建完成后，Makefile 委托 ``dv/uvm/core_eh2/wrapper.mk`` 执行
  ``$(GOAL)`` target。

**接口关系**：

* **被调用**：用户执行 ``make run GOAL=<target> CONFIG=<profile>``。
* **调用**：调用 ``metadata.py`` 和 ``wrapper.mk``。
* **共享状态**：``CONFIG`` 只通过 metadata 传给 staged flow。

§16  local ``dv/uvm/core_eh2/Makefile`` — CONFIG 转发
----------------------------------------------------------------

**职责**：core_eh2 子目录 Makefile 是本地开发入口。它定义 ``CONFIG ?= default``，
并在 ``compile`` target 中把 ``CONFIG`` 转发给顶层 Makefile。

**关键代码** （``dv/uvm/core_eh2/Makefile:L22-L36``）：

.. code-block:: makefile

   # Pass-through variables
   CONFIG     ?= default
   SEED       ?= 1
   TEST       ?= riscv_arithmetic_basic_test
   SIMULATOR   ?= vcs
   BINARY      ?=
   WAVES       ?= 0
   COV         ?= 0
   ITERATIONS  ?= 1
   PARALLEL    ?= 1
   RTL_TEST    ?= core_eh2_base_test
   VERBOSITY   ?= UVM_MEDIUM
   SIGNOFF_ITERATIONS ?=
   LEC_BLOCKLEVEL ?= 0
   LEC_SUMMARY_PATH ?= syn/build/lec_summary.txt

**逐段解释**：

* 第 L22-L36 行：本地 Makefile 把 ``CONFIG`` 列为 pass-through 变量，默认仍是
  ``default``；同区块还定义 test、seed、simulator、waves、coverage 和 LEC 参数。

**关键代码** （``dv/uvm/core_eh2/Makefile:L67-L73``）：

.. code-block:: makefile

   compile:
           cd $(PROJ_ROOT) && $(MAKE) compile SIMULATOR=$(SIMULATOR) CONFIG=$(CONFIG)

   run: compile
           cd $(PROJ_ROOT) && $(MAKE) run TEST=$(TEST) SEED=$(SEED) \
             SIMULATOR=$(SIMULATOR) BINARY=$(BINARY) WAVES=$(WAVES) COV=$(COV) \
             RTL_TEST=$(RTL_TEST) VERBOSITY=$(VERBOSITY)

**逐段解释**：

* 第 L67-L68 行：``compile`` 转到仓库根目录执行顶层 ``compile``，并显式传递
  ``CONFIG=$(CONFIG)``。
* 第 L70-L73 行：``run`` 依赖 ``compile``，但 run 命令本身没有再次传递 ``CONFIG``。

**接口关系**：

* **被调用**：开发者在 :file:`dv/uvm/core_eh2` 内运行 ``make compile`` 或 ``make run``。
* **调用**：调用顶层 Makefile。
* **共享状态**：``CONFIG`` 在 compile target 中转发；当前 direct run target 不转发该变量。

§17  ``run_rtl.py`` — direct simulation 中的 config 边界
----------------------------------------------------------------

**职责**：``run_rtl.py`` 接受 ``--config`` 并保存到 ``RegressionMetadata.eh2_config``，
但当前 compile command 不使用该字段生成 compile define。

**关键代码** （``dv/uvm/core_eh2/scripts/run_rtl.py:L47-L85``）：

.. code-block:: python

   def build_compile_cmd(md: RegressionMetadata, sim_cfg: dict) -> str:
       """Build the compilation command."""
       del sim_cfg
       return "make -C {} compile SIMULATOR={} WAVES={} COV={}".format(
           md.eh2_root, md.simulator, int(md.waves), int(md.coverage))

   def build_sim_cmd(md: RegressionMetadata, sim_cfg: dict) -> str:
       """Build the simulation command."""
       cfg = sim_cfg.get(md.simulator, sim_cfg.get("vcs", {}))
       sim_cfg_inner = cfg.get("sim", {})

       variables = {
           "build_dir": md.build_dir,
           "out_dir": md.out_dir,
           "test": md.test_name,
           "seed": md.seed,

**逐段解释**：

* 第 L47-L51 行：compile command 只使用 ``eh2_root``、``simulator``、``waves`` 和
  ``coverage``，没有使用 ``md.eh2_config``。
* 第 L54-L85 行：simulation command 从 :file:`rtl_simulation.yaml` 读取模板并替换变量。
  变量集合也不包含 ``eh2_config``。

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

* 第 L326-L337 行：CLI 定义 ``--config``，默认值为 ``default``。
* 第 L367-L373 行：非 metadata 模式下创建 ``RegressionMetadata``，并把
  ``args.config`` 写入 ``md.eh2_config``。

**接口关系**：

* **被调用**：direct regression 或 wrapper 的 RTL simulation target 调用该脚本。
* **调用**：调用 ``build_compile_cmd`` 和 ``build_sim_cmd``。
* **共享状态**：保存 ``md.eh2_config``，但当前 direct compile/sim 命令没有消费该字段。

§18  ``rtl_simulation.yaml`` — 仿真命令模板不含 CONFIG
-------------------------------------------------------

**职责**：该 YAML 提供 VCS/Xcelium/Questa 的 compile 和 sim command 模板。当前模板变量中
没有 ``CONFIG`` 或 ``EH2_CONFIG``。

**关键代码** （``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L1-L7``）：

.. code-block:: yaml

   # SPDX-License-Identifier: Apache-2.0
   # EH2 RTL Simulation Configuration
   #
   # Defines compile and simulation commands for each simulator.
   # Uses template variables: <tb_dir>, <build_dir>, <seed>, <binary>,
   # <rtl_test>, <sim_opts>, <cov_opts>, <wave_opts>

**逐段解释**：

* 第 L1-L7 行：注释列出的模板变量包括 testbench dir、build dir、seed、binary、RTL test、
  sim/cov/wave opts，没有配置 profile 变量。

**关键代码** （``dv/uvm/core_eh2/yaml/rtl_simulation.yaml:L11-L28``）：

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
      cov_opts: "-cm line+tgl+assert+fsm+branch -cm_dir <build_dir>/cov -cm_hier dv/uvm/core_eh2/cover.cfg -cm_tgl portsonly -cm_tgl structarr -cm_report noinitial -cm_seqnoconst -cm_fsmcfg dv/uvm/core_eh2/cov_fsm.cfg -cm_fsmresetfilter dv/uvm/core_eh2/cov_fsm_reset_filter.cfg -cm_fsmopt report2StateFsms+allowTmp+reportvalues+reportWait+upto64"

**逐段解释**：

* 第 L11-L20 行：VCS compile 命令使用 filelist、top、Mdir 和 output executable。
* 第 L21-L27 行：compile define 只有 ``UVM_NO_DEPRECATED`` 和 include dirs；没有
  ``+define+NUM_THREADS`` 或其它 YAML profile 参数。
* 第 L28 行：coverage option 单独保存在 ``cov_opts``。当前 VCS 主线使用
  ``line+tgl+assert+fsm+branch`` 五维覆盖率，不启用 cond 维度；层次过滤文件为
  :file:`dv/uvm/core_eh2/cover.cfg`，其中 ``+tree core_eh2_tb_top.dut``
  将覆盖率限定在 DUT subtree。

**接口关系**：

* **被调用**：``run_rtl.py`` 的 ``load_sim_config`` 和 ``build_sim_cmd`` 读取该文件。
* **调用**：YAML 本身不调用代码。
* **共享状态**：提供 simulator command 模板。

§19  ``signoff.py`` — 配置文件存在性和 default 单线程检查
---------------------------------------------------------

**职责**：sign-off precheck 只检查 :file:`eh2_configs.yaml` 是否存在、能否解析，并确认
``default.parameters.NUM_THREADS`` 为 1。

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

* 第 L182-L185 行：precheck 固定读取仓库根目录的 :file:`eh2_configs.yaml`，存在时用
  ``_load_yaml`` 解析。
* 第 L186-L189 行：检查 ``default`` profile 下的 ``NUM_THREADS``，只有等于 1 时
  ``default_single_thread`` 通过。
* 第 L190-L193 行：解析异常或文件缺失会分别记录 ``eh2_config_parse`` 或 ``eh2_config`` 失败项。

**接口关系**：

* **被调用**：sign-off flow 的 precheck 阶段调用。
* **调用**：调用 ``_load_yaml`` 和 ``add``。
* **共享状态**：只读 YAML；不修改 profile。

§20  ``syn/include/eh2_param.vh`` — 完整 RTL 参数不是 YAML 全量镜像
--------------------------------------------------------------------

**职责**：:file:`syn/include/eh2_param.vh` 展示综合侧完整 ``eh2_param_t`` 默认参数。
它包含远多于 YAML 的字段。当前文档不能把 YAML 的 4 个 profile 写成该文件的全量生成源，
除非源码中出现明确生成链路。

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

* 第 L1 行：该文件直接声明 ``parameter eh2_param_t pt``，这是 RTL/synthesis 参数结构。
* 第 L2-L17 行：字段包括 Atomic、BHT 和多组 bitmanip。YAML 只覆盖 ``ATOMIC_ENABLE``、
  ``BHT_SIZE`` 和 4 个 bitmanip key，没有覆盖 ``BHT_ADDR_HI`` 等派生字段。

**关键代码** （``syn/include/eh2_param.vh:L64-L83``）：

.. code-block:: systemverilog

       DCCM_BANK_BITS         : 7'h03         ,
       DCCM_BITS              : 9'h010        ,
       DCCM_BYTE_WIDTH        : 7'h04         ,
       DCCM_DATA_WIDTH        : 10'h020        ,
       DCCM_ECC_WIDTH         : 7'h07         ,
       DCCM_ENABLE            : 5'h01         ,
       DCCM_FDATA_WIDTH       : 10'h027        ,
       DCCM_INDEX_BITS        : 8'h0B         ,
       DCCM_NUM_BANKS         : 9'h008        ,
       DCCM_REGION            : 8'h0F         ,
       DCCM_SADR              : 36'h0F0040000  ,
       DCCM_SIZE              : 14'h0040       ,
       DCCM_WIDTH_BITS        : 6'h02         ,
       DIV_BIT                : 7'h04         ,
       DIV_NEW                : 5'h01         ,
       DMA_BUF_DEPTH          : 7'h05         ,
       DMA_BUS_ID             : 9'h001        ,
       DMA_BUS_PRTY           : 6'h02         ,
       DMA_BUS_TAG            : 8'h01         ,

**逐段解释**：

* 第 L64-L76 行：DCCM 在完整 RTL 参数里不仅有 ``DCCM_ENABLE`` 和 ``DCCM_SIZE``，
  还包括 bank、width、ECC、region 和 start address 等派生/结构字段。
* 第 L77-L83 行：DIV 和 DMA 参数也出现在完整 ``eh2_param_t`` 中；YAML profile 只在
  ``default`` 中包含 ``DMA_BUS_TAG``，不包含其它 DMA 字段。

**关键代码** （``syn/include/eh2_param.vh:L97-L107,L166-L179``）：

.. code-block:: systemverilog

       ICACHE_ENABLE          : 5'h01         ,
       ICACHE_FDATA_WIDTH     : 11'h047        ,
       ICACHE_INDEX_HI        : 9'h00C        ,
       ICACHE_LN_SZ           : 11'h040        ,
       ICACHE_NUM_BEATS       : 8'h08         ,
       ICACHE_NUM_BYPASS      : 8'h04         ,
       ICACHE_NUM_BYPASS_WIDTH : 8'h03         ,
       ICACHE_NUM_WAYS        : 7'h04         ,
       ICACHE_ONLY            : 5'h00         ,
       ICACHE_SCND_LAST       : 8'h06         ,
       ICACHE_SIZE            : 13'h0020       ,
       ...
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

**逐段解释**：

* 第 L97-L107 行：ICache 完整参数包括 enable、width、index、line size、way 数和 size 等；
  YAML 只覆盖 ``ICACHE_ENABLE`` 与 ``ICACHE_SIZE``。
* 第 L166-L179 行：完整参数中的 ``NUM_THREADS``、PIC base/size/total、return stack 和 timer
  等值是 SystemVerilog literal；YAML 只提供部分高层 knob。

**接口关系**：

* **被调用**：综合和 RTL include 路径使用该参数文件。
* **调用**：无。
* **共享状态**：``pt`` 是完整 RTL 参数结构；不要把 YAML profile 未覆盖的字段写成由 YAML 自动生成。

§21  单元测试证据 — template 条件渲染
--------------------------------------

**职责**：测试用例验证 ``CONFIG=minimal`` 时，``NUM_THREADS`` 会渲染到 template，
而 Atomic 和 ZBA 条件块会被移除。

**关键代码** （``dv/uvm/core_eh2/scripts/tests/test_regression_framework.py:L1568-L1600``）：

.. code-block:: python

       def test_render_config_template_uses_eh2_config_parameters(self):
           with tempfile.TemporaryDirectory() as td:
               root = Path(td)
               md_dir = root / "metadata"
               out_dir = root / "out"
               template = root / "setting.tpl.sv"
               template.write_text(
                   "parameter int NUM_HARTS = {{ NUM_THREADS }};\n"
                   "riscv_instr_group_t supported_isa[$] = {\n"
                   "  RV32I\n"
                   "//% if ATOMIC_ENABLE\n"
                   "  ,RV32A\n"
                   "//% endif\n"
                   "//% if BITMANIP_ZBA\n"
                   "  ,RV32ZBA\n"
                   "//% endif\n"

**逐段解释**：

* 第 L1568-L1576 行：测试创建临时 metadata、out 和 template，并写入 ``NUM_THREADS`` token。
* 第 L1577-L1584 行：template 中包含 ``ATOMIC_ENABLE`` 和 ``BITMANIP_ZBA`` 条件块。

**关键代码** （``dv/uvm/core_eh2/scripts/tests/test_regression_framework.py:L1587-L1600``）：

.. code-block:: python

               metadata.main([
                   "--op", "create_metadata",
                   "--dir-metadata", str(md_dir),
                   "--dir-out", str(out_dir),
                   "--args-list",
                   "SEED=1 TEST=directed_smoke CONFIG=minimal",
               ])

               rendered = render_config_template.render_template(
                   "minimal", str(template))

               self.assertIn("NUM_HARTS = 1", rendered)
               self.assertNotIn("RV32A", rendered)
               self.assertNotIn("RV32ZBA", rendered)

**逐段解释**：

* 第 L1587-L1593 行：测试通过 metadata 创建命令传入 ``CONFIG=minimal``。
* 第 L1595-L1600 行：渲染结果必须包含 ``NUM_HARTS = 1``，并且不包含 ``RV32A`` 与
  ``RV32ZBA``。这直接证明 minimal profile 的 Atomic/ZBA 关闭会影响 template 输出。

**接口关系**：

* **被调用**：Python 单元测试运行时执行。
* **调用**：调用 ``metadata.main`` 和 ``render_config_template.render_template``。
* **共享状态**：临时目录中的 metadata 和 template 文件。

§22  配置误读防护
------------------

* 当前 YAML profile 名称是 ``default``、``minimal``、``dual_thread`` 和 ``ahb_lite``；
  不存在 ``2thread``、``no_icache``、``no_dccm``、``fpga``、``no_pmp`` 或 ``full``。
* 当前 YAML 不是完整 ``eh2_param_t`` 数据库。完整 RTL/synthesis 参数可见
  :file:`syn/include/eh2_param.vh`。
* ``CONFIG`` 在 staged flow 中通过 metadata 进入 ``render_config_template.py``；
  direct ``run_rtl.py`` compile command 当前没有把它转成 simulator define。
* ``render_config_template.py`` 对 ``//% if KEY`` 中缺失的 key 默认按 0 处理；
  对 ``{{ KEY }}`` 中缺失的 key 则抛 ``KeyError``。
* sign-off precheck 只验证 ``default.parameters.NUM_THREADS == 1``，不验证每个 profile 的完整参数一致性。

§23  覆盖率与波形配置的当前边界
--------------------------------

当前覆盖率配置完全以 VCS 为主线。:file:`dv/uvm/core_eh2/cover.cfg` 是编译期
DUT-only scope 文件，内容很短但语义关键：

.. code-block:: text

   +tree core_eh2_tb_top.dut
   begin tgl
     -tree core_eh2_tb_top.dut.*
   end

第一行把 line、branch、assert、FSM 等 structural coverage 限定在 DUT subtree；
``begin tgl`` block 排除 DUT 子层 toggle 的过深递归，配合
``-cm_tgl portsonly`` 与 ``-cm_tgl structarr`` 让 VCS toggle 口径稳定。URG
dashboard 直接消费 VCS ``simv.vdb``，不通过二次合成脚本改写百分比。2026-05-19
01:02 demo 的报告值为 LINE ``95.05%``、BRANCH ``84.97%``、TOGGLE
``53.52%``、ASSERT ``33.33%``、FSM ``54.74%``、GROUP ``69.42%``、
OVERALL ``65.17%``。

:file:`dv/uvm/core_eh2/cov_fsm.cfg` 和
:file:`dv/uvm/core_eh2/cov_fsm_reset_filter.cfg` 只服务 VCS FSM coverage。
前者列出 debug、LSU bus buffer、DMA pointer、LSU store buffer 和 IFU memory
controller 等 FSM；后者把 ``rst_l``、``dbg_rst_l``、``dbg_dm_rst_l`` 的 active-low
reset transition 从 FSM coverage 中过滤出去。二者不是 functional coverage
covergroup，也不影响 :file:`eh2_fcov_if.sv` 内部的 covergroup 采样。

:file:`dv/uvm/core_eh2/nc_waves.tcl` 是 NC 单测波形脚本，只在如下命令中使用：

.. code-block:: bash

   make smoke SIMULATOR=nc WAVES=1
   make regress SIMULATOR=nc TEST=<name> WAVES=1

NC/Incisive 当前参与 :command:`make signoff`、:command:`make demo` 和覆盖率
cross-check/备选签核。默认 release 参考仍是 VCS/URG；当配置同时给出 VCS 和
NC coverage 字段时，应分别解释 ``cover.cfg``/URG 与 ``cov_full_nc.ccf``/IMC 的口径，
不能把 NC branch/block 限制误写成 VCS 数字。

§24  参考资料
--------------

* :doc:`../03_integration/configuration` — 配置系统使用说明。
* :doc:`../06_flows/regression_flow` — staged regression 与 metadata flow。
* :doc:`../06_flows/signoff_flow` — sign-off precheck 与配置检查。
* :file:`/home/host/eh2-veri/eh2_configs.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/eh2_cmd.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/render_config_template.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/metadata.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/wrapper.mk`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/riscvdv.mk`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/run_rtl.py`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/yaml/rtl_simulation.yaml`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/scripts/signoff.py`
* :file:`/home/host/eh2-veri/syn/include/eh2_param.vh`
