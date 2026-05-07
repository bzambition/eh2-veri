总览
====

平台目的与范围
--------------

**EH2 UVM 验证平台** 是一套面向 **VeeR EH2** 双线程 RV32IMAC RISC-V 处理器的工业级
UVM 验证框架。它构建在 ``/home/host/eh2-veri/`` 目录树下，对标 lowRISC 的
``ibex/dv/uvm/core_ibex/`` 平台，目标是把 EH2 推到 sign-off-ready 状态。

平台的核心价值由以下几个支柱共同支撑：

* **完整 UVM testbench** ：层次化的 ``env`` / ``agent`` / ``sequence`` /
  ``test`` 体系，顶层 ``core_eh2_tb_top`` （1071 行）封装时钟、复位、AXI4 / JTAG / IRQ /
  halt-run 接口与 trace probe。
* **Spike DPI 协同仿真闭环**：通过 ``dv/cosim/`` 下的 C++ DPI 桥
  （``spike_cosim.cc`` / ``cosim_dpi.cc``）以及编译产物 ``build/libcosim.so``，
  把每条 RTL 提交的指令与 Spike 参考模型逐拍对齐。
* **riscv-dv 受约随机验证集成**：通过 ``vendor/google_riscv-dv/`` 子模块生成
  RV32IMAC 指令流，并在统一的 ``run_regress.py`` 入口下闭环执行。
* **ADR 驱动的设计决策**：``docs/adr/`` 下沉淀了 5 条架构决策记录
  （cosim 路径、AXI4 被动监控、NUM_THREADS 协同范围、RVFI 等价 trace、Spike
  store 宽度对齐），保证关键技术抉择有迹可循。
* **统一的 sign-off 流程**：``make signoff SIGNOFF_PROFILE=full`` 一键执行
  smoke / directed / cosim / riscvdv 四个 stage，并产出 ``signoff_report.md``。

.. note::

   本手册描述的状态截至 **2026-05-07**：``signoff_report.md`` 显示
   ``Status: PASS``，四个 stage 全部 100% 通过。

平台范围
~~~~~~~~

下表概括平台 **覆盖** 与 **不覆盖** 的内容。

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - 覆盖
     - 不覆盖
   * - UVM TB / env / agent / scoreboard / functional coverage
     - ASIC 后端：综合、布局布线、时序签收
   * - Spike DPI 协同仿真（默认 NUM_THREADS=1）
     - Power / IR-drop / DFT 流程
   * - riscv-dv 受约随机指令生成
     - 形式验证（formal）与等价性检查（保留为 Phase 5 议题）
   * - sign-off 4 stage（smoke / directed / cosim / riscvdv）
     - 多 hart cosim（NUM_THREADS=2 留 issue-41）
   * - VCS 主线 + Xcelium 兼容栈
     - Verilator 仅作备选流程，参见 ``dv/verilator/``
   * - functional coverage（``eh2_fcov_if.sv``，797 行）
     - 代码覆盖率合并：仅在 ``COV=1`` 时启用，未纳入 sign-off 默认门限

被验对象：VeeR EH2
------------------

EH2 是 Western Digital 开源的中端 RISC-V 处理器，关键参数如下：

.. list-table::
   :header-rows: 1
   :widths: 28 72

   * - 维度
     - 取值
   * - ISA
     - ``RV32IMAC`` （整数、乘除、原子、压缩）
   * - 自定义扩展
     - ``Zb*``：RTL 实现 ``zba/zbb/zbc/zbs``；当前工具链
       （GCC 11.1）仅支持 ``zba/zbb`` 编译落地，``zbc/zbs`` 通过 hand-written
       汇编与 riscv-dv 自定义流验证
   * - 特权模式
     - 仅 M-mode
   * - 线程模型
     - 双硬件线程，由 ``RV_NUM_THREADS`` 宏控制（默认 ``1``，可配置 ``2``）
   * - 流水线
     - 9 级，双发射，按序提交
   * - 紧耦合存储
     - ICCM / DCCM 地址可配置
   * - PIC
     - 内部可编程中断控制器，默认 ``PIC_TOTAL_INT=127`` 路外部中断源
   * - 调试
     - JTAG DTM + 调试模块，支持 hardware breakpoint / single step
   * - RTL 路径
     - ``rtl/``（链接到 ``/home/host/Cores-VeeR-EH2``）

这些特性直接决定了平台的若干关键策略：

* 仅 M-mode 意味着 ``riscv-dv`` 生成的 ``riscv_pmp_*`` / ``riscv_epmp_*``
  系列测试需要走 EH2 自定义路径，而不是参考实现的 S/U-mode 默认；
* 双线程要求 cosim 在 ``NUM_THREADS=2`` 下显式扩展（详见 ADR-0003），
  当前 sign-off 锁定在单线程，多线程作为遗留 issue；
* ``Zb*`` 与 ``Zicsr`` / ``Zifencei`` 自定义 CSR 由 ``eh2_cosim_csr_preregister.svh``
  与 Spike 桥的 ``fixup_csr`` 共同保持一致。

平台核心目标
------------

整套平台围绕 4 个工程化目标设计：

#. **Cosim 闭环 0 mismatch**：每条 RTL 提交的指令都必须经 Spike 校验，
   而非依赖结果寄存器的 mailbox 比对。``cosim`` stage 的 4 个 directed 测试
   （``cosim_smoke / cosim_alu / cosim_load_store / cosim_dual_issue``）
   是这一目标的最小证据集。
#. **Sign-off 4 stage 全 PASS**：``smoke + directed + cosim + riscvdv``
   四个 stage 串行评估，任一阶段失败即阻塞。当前 ``full`` profile 下
   ``1/1 + 3/3 + 4/4 + 32/32`` 全 PASS。
#. **Skip 项可追踪**：11 个 ``skip_in_signoff: true`` 的 riscv-dv 测试
   均在 ``testlist.yaml`` 中显式标注并在 issue tracker 中保留追踪条目，
   而不是悄悄跳过；这一约定由 Phase 5 引入。
#. **ADR 驱动决策**：所有跨模块、不可逆的架构选择必须先经 ADR
   讨论再落地，避免 cosim 路径、trace 包格式之类的核心契约被默默修改。

与 eh2-verification 项目的关系
------------------------------

仓库根目录与 ``/home/host/eh2-verification`` 下的 **指令级验证平台** 是 **互补**
而非替代关系。两者在抽象层次、关注点与产出物上完全不同。

.. list-table::
   :header-rows: 1
   :widths: 22 39 39

   * - 维度
     - eh2-veri（本平台）
     - eh2-verification（指令级平台）
   * - 抽象层次
     - UVM testbench + DPI cosim
     - 裸金属 ELF + RTL 仿真器
   * - 参考模型
     - Spike，DPI 链接到仿真器进程内
     - QEMU ``veer-eh2`` 自定义机器，独立进程离线 trace 比对
   * - 测试形态
     - SystemVerilog 类层次（``core_eh2_*_test``）+ 汇编 binary
     - 直接 ``.S`` / ``.c`` 程序 + ``run_all.sh``
   * - 验证侧重
     - 协议 / 接口 / 双发射 / 异步 wb / coverage
     - ISA 一致性、compliance suite、随机 trace diff
   * - sign-off 单位
     - ``smoke / directed / cosim / riscvdv``
     - ``directed / compliance / mini / regression / random``

两个平台共享相同的 RISC-V 工具链（``GCC_PREFIX``）与 mailbox 协议
（``0xD0580000``），因此同一份汇编测试可以在两个平台分别落地以交叉验证。
本手册的全部内容仅适用于 **eh2-veri**；如需查阅指令级流程，请参考
``/home/host/eh2-verification/docs/sphinx_en/``。

当前状态
--------

下表来自 ``build/sf_full2/signoff_report.md``，时间戳 ``2026-05-07T15:04:58``：

.. list-table:: Sign-off ``full`` profile（2026-05-07）
   :header-rows: 1
   :widths: 18 12 12 12 18 28

   * - Stage
     - Status
     - Total
     - Passed
     - Pass Rate
     - 说明
   * - smoke
     - PASS
     - 1
     - 1
     - 100.00%
     - ``+disable_cosim=1``，仅做 mailbox 烟囱
   * - directed
     - PASS
     - 3
     - 3
     - 100.00%
     - ``directed_smoke / directed_alu / directed_load_store``
   * - cosim
     - PASS
     - 4
     - 4
     - 100.00%
     - cosim 闭环证据集，0 mismatch
   * - riscvdv
     - PASS
     - 32
     - 32
     - 100.00%
     - 11 个 ``skip_in_signoff`` 已扣除

.. warning::

   ``riscvdv`` 的 32/32 是在剔除 11 个 ``skip_in_signoff: true`` 测试 **之后**
   的统计。报告同时列出 34 个 ``cosim:disabled`` 测试作为 waiver-reviewed
   例外。这些 skip / disabled 项不是失败，但也不是完整覆盖证据；它们对应
   的 issue 详见 :doc:`risk_register` 与 ``.scratch/platform-industrialization/issues/``。

工业化阶段（Phase 1–5）
~~~~~~~~~~~~~~~~~~~~~~~

平台演进遵循 ``.scratch/platform-industrialization/README.md`` 定义的 5 个 Phase。
截至 2026-05-07：

* **Phase 1 — cosim 闭环修复**：完成。RTL trace 包加 ``rd_addr/rd_wdata``，
  trace_monitor 直接采样 wb 数据，scoreboard 删除 ``pending_wb_q``。
* **Phase 2 — 结构整理**：完成。``eh2_cosim_scoreboard.sv`` 从 1026 行降到
  769 行；agent 前缀统一为 ``eh2_*``；``env/`` 接口归位。
* **Phase 3 — cosim-enabled testlist 9/9 PASS**：完成。
* **Phase 4 — 文档与工程化**：完成。``CONTEXT.md`` / ADR 0001-0005 / 本手册。
* **Phase 5 — CI gate / skip_in_signoff / Sign-off full PASS**：完成。CI gate 与
  ``skip_in_signoff`` 机制已落地；sign-off full profile 4 stage 全 PASS（32/32 riscvdv）。
  多 hart cosim、formal、AXI4 active driver
  作为遗留 issue（41/42/40）保留在 tracker。

手册结构
--------

本手册分 5 部分：

* **第一部分（本部分）— 总览**：``overview`` / :doc:`architecture` /
  :doc:`quickstart`，给读者一个能在 5 分钟内跑通烟囱测试的最小路径。
* **第二部分 — 平台组件**：testbench 顶层、env、agent、cosim scoreboard、
  functional coverage 与测试库的逐模块说明。
* **第三部分 — 流程与脚本**：build、regression、sign-off 三套流程的端到端
  解析，以及 ``scripts/`` 下 Python 工具的参考。
* **第四部分 — 设计决策与质量**：ADR 索引、风险登记、覆盖率计划与 CI 流水线。
* **第五部分 — 附录**：目录树、术语表、故障排查、issue tracker 索引、外部
  引用。

读者可以采用两遍阅读法：第一遍按第一部分至第三部分顺序阅读，建立平台
心智模型；第二遍把第四、第五部分作为参考查阅。

.. seealso::

   * :doc:`architecture` — 顶层组件、目录结构、数据通路。
   * :doc:`quickstart` — 5 分钟跑通 smoke + cosim 的最小步骤。
   * :doc:`architecture_decisions` — 5 条 ADR 的完整文本。
