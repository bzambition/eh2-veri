# 博士课题调研与路线规划：面向松耦合多核异构处理器的自动化验证环境

日期：2026-06-12
状态：v3（v2 联网复核版 + 总体验证框架与三阶段工具链定稿，见 §2.5；框架设计决策由用户 2026-06-12 给定，评估与修正已合入）
关联项目：`eh2-veri`（VeeR EH2 验证平台，作为课题第一个案例载体）

---

## 0. 摘要与总结论

**课题可行性判断：可行，且定位准确。** 三个支柱（UVM 环境自动化、模板化参考模型生成、spec 驱动激励生成）各自都有成熟的"单点"先例，但**没有任何已知工作把"验证侧四件套"（UVM 环境 + 参考模型 + 激励 + 覆盖率/故障注入活动）从同一份语义规格协同生成**，更没有面向**松耦合异构多核**做这件事。"松耦合"这个定界是整个课题可行性的关键——它避开了共享内存弱序一致性检查这个最难的坑（那是 RTLCheck/MTraceCheck 一脉的独立难题），使"窗口化/事务级比对"成为可判定且可实现的 oracle 机制。

四个可防御的创新点（详见 §5）：
1. **统一语义元规格（Meta-Spec）驱动的验证四件套协同生成机制**（研究内容二的核心主张）；
2. **松耦合异构多核参考模型的自动装配 + hart/IP 感知的标准化比对接口与窗口化等价判据**；
3. **spec 驱动的异构系统级随机激励生成器（"hetero-dv"）**，与 ISS/VP oracle 闭环；
4. **与功能验证平台同构的故障注入与容错有效性量化环境**（研究内容三），含跨 IP 故障传播度量。

---

## 1. 调研方法声明（v2 更新）

v1 撰写时三条外部通道全部不可用，全部外部事实来自模型内置知识库。**本次（同日，网络恢复后）已完成联网复核**，方法：

1. **deep-research 多代理工作流**：103 个检索/核查 agent，对声明做三票对抗式核实。方向 1（UVM 自动化）与方向 3（激励生成）的核心结论以 3-0 票存活；方向 2/4/5 的核查环节因中转 API 额度耗尽大量中断（0-0 票 = 未核完，非证伪）。
2. **官方仓库第一手核实（curl 原文，2026-06-12）**：RVVI、FORCE-RISCV、sail-riscv、QBox、core-v-verif、riscv-dv 的 README 逐字核对，补上了工作流没核完的最关键事实。
3. 方向 5（容错/ISO 26262）的外部声明**仍未经联网核实**，维持 v1 的内置知识置信度标注，投稿引用前需专项复核。

复核结果汇总见 §1.5；§8 速查表中已核实项在行内标注【已核实】。本地审计部分（§7）在 v2 中又抽查验证了一次：ADR×20、`rtl/eh2_veer_wrapper_rvfi.sv:117-118` 的 ecause 共享/截断问题逐字应验，审计结论可信。

---

## 1.5 联网复核结果（v2 新增）

### 已核实、且与 v1 一致的关键事实
| 声明 | 核实来源 |
|---|---|
| RVVI = RVFI 超集；RVVI-TRACE v1.7 **明确支持多 hart、多发射、乱序、异步中断、debug 模式**；RVVI-API v1.37 为 C/C++ + SV DPI，解耦 testbench 与参考模型；另有 RVVI-TEXT v0.5、RVVI-VVP（WIP）；ImperasDV（Synopsys）与 core-v-verif CV32E40X 在用 | riscv-verification/RVVI README 原文 |
| FORCE-RISCV：Python 测试模板、内置 Handcar（基于 Spike）、RV64G/RV32G、V 1.0、U/S/M 全特权、Sv32/39/48 全页大小、**"Multiprocess/multithread instruction generation"** 明确列入能力表、与 core-v-verif UVM TB 有对接路径 | openhwgroup/force-riscv README 原文 |
| sail-riscv：RISC-V International 官方采纳；**Sail 编译器从规格自动生成可执行模拟器**（→C++ 模型→`sail_riscv_sim`），配置 JSON schema 也从 Sail 源生成；支持自动指令序列测试生成、定理证明器定义；**SystemVerilog 参考模型生成进行中** | riscv/sail-riscv README 原文 |
| QBox：QEMU 以 TLM-2.0 接入 SystemC；支持 ARM（A53–Neoverse）/RISC-V（rv32/64、SiFive X280）/**Hexagon DSP** 的异构混合虚拟平台 | quic/qbox README 原文 |
| riscv-dv：SV/UVM 生成器，RV32/64IMAFDC，M/S/U；README 列出与 whisper/spike/riscv-ovpsim/sail-riscv 的 cosim；生成为单 hart（多 hart 薄弱判断维持） | chipsalliance/riscv-dv README（工作流 3-0 核实） |

**结论：v1 的"待核"高风险项中，对路线图起支撑作用的全部关键假设均成立**（RVVI 异构扩展的基础、FORCE-RISCV 多线程先例、Sail spec→ISS、QBox 异构底座）。

### v2 新增情报（v1 知识截止后的新工作，需修正 §3.1 的边界）
- **UVMarvel**（arXiv 2605.04704，**DAC 2026 录用**，2026-05 预印本）：LLM 驱动 spec→UVM，核心机制 = 中间表示（IR）+ 总线协议库，自称**首个跨主流总线协议自动构建"子系统级" UVM testbench 的框架**（对抗式检索未找到反例）；自报 95.65% 平均代码覆盖率、构建时间数人日→4.5 小时。⚠️ 预印本自报数字、人工基线模糊，当"边界标定"用，不当复现基线。
- **LLM4DV**（arXiv 2310.04535 v2，剑桥/帝国理工/lowRISC，开源）：6 LLM×6 prompting×8 设计的激励生成基准；在 Ibex 译码器/完整 Ibex CPU 上最优配置 89.74%–100% 功能覆盖（自定义覆盖计划，196 bins，非工业收敛）；**作者明确承认复杂设计上失效，全文不涉及 multicore/coherence**。
- **UVLLM**（arXiv 2411.16238）：LLM+UVM 的自动测试 + RTL 修复闭环（定位是 debug-repair 而非 TB 生成；自报修复率未通过独立核查，引用谨慎）。

**对课题边界的修正**：LLM 路线已把"环境级自动生成"推进到**子系统级（2026 年的 first）**，v1 §3.1 "环境级自动化=骨架模板"的表述需收窄；但**系统级（多核异构、互联、一致性、SMT）仍是经对抗式核查确认的空白**——这反而把你的创新点 1 的边界钉得更准了：差异化不在"用不用 LLM 生成 UVM"，而在**处理器/异构系统域 + 验证四件套同源 + cosim oracle 闭环 + 系统级**。UVMarvel 必须进创新点 1 的 prior-art 对比表。

### 仍未核实（投稿前必须专项复核）
Genesys-Pro/Threadmill/X-Gen/McVerSi/STING 的具体能力声明；RVVI 之外的 core-v-verif tandem 架构细节；方向 5 全部外部声明（Z01X/Xcelium FS/Veloce FA/Chiffre/ETH 容错谱系/SELENE）。

---

## 2. 课题定位与问题定义

- **对象**：多核异构处理器系统（仅处理器范畴），**松耦合**架构（消息/mailbox/DMA/非一致共享存储通信，无硬件 cache 一致性协议）。
- **研究内容二**：自动化验证环境构建 → 支柱 1（UVM 自动化）+ 支柱 2（参考模型生成）+ 支柱 3（激励生成）。
- **研究内容三**：面向容错设计的有效性验证环境 → 支柱 4（故障注入 + 有效性度量）。
- **方法学底座**：UVM + cosim（ISS/VP 金模型逐指令/逐事务比对）+ 约束随机激励 + 功能覆盖率收敛。
- **案例路径**：EH2（单核双线程）→ 同构双核 → 异构多核（+第二种核/加速器）→ 容错有效性层。

“自动化”的诚实边界（与你的判断一致）：**不追求全自动**。寄存器域、接口适配、配置装配可全自动；协议 agent 内核、scoreboard 语义、定向场景永远需要人——自动化的学术主张应该是“**单一规格源 + 生成式装配 + 人工只写语义增量**”，并用工时/代码行占比量化。

---

## 2.5 总体验证框架与三阶段工具链（v3 新增，设计决策定稿）

### 2.5.1 设计决策（用户 2026-06-12 给定的约束，已采纳）

| # | 决策 | 说明 |
|---|---|---|
| C1 | 对象处理器均为 **RISC-V** | "异构"= 不同微架构/不同扩展组合的 RISC-V 核（大核+小核+DSP 风格核等），不跨 ISA |
| C2 | "自动化"= **模板化生成**，非全自动 | 用户给定模板/配置 → 生成 interface / sequence / agent / scoreboard / coverage；顶层采用**标准化 DUT shell 信号约定**（同名信号直连，core-v-verif core wrapper 同款做法） |
| C3 | **RVVI 为统一基础接口** | 默认核支持 RVVI；EH2 需自行加 RVVI 适配 module（基于现有 ADR-0015 sidecar `rtl/eh2_veer_wrapper_rvfi.sv` 升级为标准 `rvviTrace`，非从零开发） |
| C4 | EDA：**VCS + Cadence Xcelium（NC 系）** | eh2-veri 的 `yaml/rtl_simulation.yaml` 已同时支持两者，无新增成本 |
| C5 | 参考模型以 **QEMU/QBox 为底座**，模板化装配为 ISS | 终局正确（异构+平台级只有 VP 路线可达）；阶段一风险对冲见 2.5.4-E1/E2 |
| C6 | hex 加载**只考虑外部 flash** 一种 | 合理定界，flash 模型做成库组件 |
| C7 | 功能覆盖率组件同走统一模板 | 公认难点，按 2.5.4-E4 的三层模型处理 |

### 2.5.2 总体框架图

```
                ┌──────────────────────────────────────────────────┐
                │       统一元规格 Meta-Spec（用户模板 + 配置，单一事实源）   │
                │  核描述 · 平台拓扑 · 总线/接口 · CSR · 覆盖意图 · 故障域     │
                └────────┬───────────┬───────────┬───────────┬──────┘
                         │           │           │           │
                ┌────────▼───┐ ┌─────▼─────┐ ┌───▼───────┐ ┌─▼────────┐
                │ ① gen-uvm  │ │ ② gen-ref │ │ ③ gen-stim│ │ ④ gen-fi │
                │ UVM 环境生成 │ │ 参考模型装配 │ │ 激励生成    │ │ 故障活动   │
                │            │ │ QEMU/QBox │ │ riscv-dv/ │ │ (研究内容三)│
                │            │ │ 配置+接线   │ │ hetero-dv │ │          │
                └─────┬──────┘ └─────┬─────┘ └────┬──────┘ └────┬─────┘
                      ▼              ▼            ▼             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        生成的验证平台实例（每项目一套）                      │
│                                                                     │
│   ┌──────────┐  RVVI-TRACE  ┌───────────────┐  RVVI-API  ┌────────┐ │
│   │ DUT      ├─────────────►│   UVM 环境      ├───────────►│ 参考模型 │ │
│   │ (shell   │              │ agents/sb/cov │            │ QEMU/  │ │
│   │ 标准化信号)│◄────────────►│               │            │ QBox   │ │
│   └────▲─────┘ 总线/中断/调试  └───────────────┘ (可插拔:    └────────┘ │
│        │                                      Spike 交叉校验)         │
│        └── 外部 flash 模型(hex 加载，库组件) ◄── ③ 产物                   │
│                                                                     │
│   比对语义：核内逐指令 lock-step ＋ 核间窗口化事件比对（松耦合判据）            │
└─────────────────────────────────────────────────────────────────────┘
                      ▼
          回归 / 覆盖率合并 / 签发门（VCS · Xcelium；signoff 框架泛化 = 第 ⑤ 产物）
```

### 2.5.3 生成的 UVM 环境内部结构（标注生成方式）

```
tb_top                              【生成】
├─ DUT shell（标准化信号约定）          【生成：meta-spec 端口表 → wrapper】
├─ 外部 flash 模型 + hex 加载          【库组件，固定一种】
├─ rvvi_trace_if #(NHART, RETIRE)    【标准库组件，参数化】
└─ env                              【生成】
    ├─ 总线 agent ×N（AXI/AHB…）      【模板→ interface/driver/monitor/
    │                                 sequencer + L2 协议 covergroup】
    ├─ irq / debug / boot agent      【模板生成】
    ├─ rvvi trace agent              【库组件】
    ├─ cosim scoreboard              【生成壳 + 比对策略为模板一等公民字段：
    │                                 lock-step / 窗口化 / 豁免窗(自定义CSR)】
    ├─ coverage 层                   【L1 spec 派生(全自动) + L2 随 agent +
    │                                 L3 用户扩展点(人工)，见 2.5.4-E4】
    └─ virtual sequencer + seq 库    【模板生成骨架，语义序列人工】
```

### 2.5.4 对方案的评估与修正（诚实记录，防止路线踩坑）

- **E1（采纳但对冲）Spike 不在阶段一丢弃**："Spike 不支持多核异构"需修正——Spike 支持多 hart（eh2-veri 双 hart cosim 即跑在其上），不支持的是**异构核与平台级建模**，故 QEMU/QBox 终局决策正确；但 RVVI-API 使参考模型可插拔，阶段一保留已跑通的 Spike 通路作为 QEMU 适配器的**交叉校验 oracle**（成本≈0），且"同一环境插拔两种参考模型"= 框架通用性的最强实证。
- **E2（v3.1 修正：从"最高技术风险"改判为"无先例的核心交付物"）QEMU-RVVI 桥**。证据链（2026-06-12 第一手核实）：
  - 反面：riscv-dv 官方 `yaml/iss.yaml` 支持 spike/ovpsim/sail/whisper/renode，**无 QEMU**；香山 DiffTest 的参考模型为 **NEMU+Spike**；Ibex→Spike、CVA6→Spike tandem、BOOM→Dromajo、core-v-verif→ImperasDV——**主流开源 RISC-V 核验证流程无一使用 QEMU 做 retire 级 lock-step**（QEMU 的既有角色是平台级协同仿真与软件 bring-up）。
  - 正面：QEMU stable-9.2 `qemu-plugin.h` 已提供 `qemu_plugin_register_vcpu_insn_exec_cb`（逐指令回调）与 `qemu_plugin_read_register`（寄存器读取，9.x 新增）——做桥的官方 API 通道近两年才成熟，"没人走"≠"不可行"，而是路刚铺好。性能非问题（RTL 仿真 kHz 量级才是瓶颈）。
  - 结论：桥 = ① one-insn-per-tb/icount 单步 + 插件导出 retire 流到 RVVI-API；② **保真度核查**（QEMU 设计目标是快而非逐指令架构精确：WARL/计数器/异常优先级等角例需逐项对照 ISA 规范——这是真正无人做过、可发表的部分）；③ EH2 自定义 CSR 豁免窗或 patch。**该桥即创新点 2 的核心交付物**（等于填上 riscv-dv ISS 列表的空位）。
  - Spike 交叉校验维持（E1）：保真度核查需要已知正确的对照系，eh2-veri 现成 Spike 通路免费充当。
  - 选型理由的严谨表述（论文用）：弃 Spike 选 QEMU 的理由**不是"Spike 不能扩展"**（Spike 有 customext/自定义 CSR 机制，eh2-veri 已注册 18+ EH2 CSR），而是 **Spike 缺平台级/异构/设备建模与软件生态，QEMU/QBox 是唯一同时覆盖异构核、互联设备模型与多实例平台装配的开源底座**。
- **E3（边界修正）参考模型"生成"= 装配与配置，不是合成语义**：模板生成 QBox 平台接线、内存映射、每核 ISA/CSR 配置表、自定义指令 stub；指令语义合成是 Sail 的领地（§1.5 已核实 Sail spec→ISS），可留接口未来对接，论文主张不写"生成参考模型语义"。
- **E4（C7 难点的解法）覆盖率是横切面而非单一 agent，三层模板化**：
  - **L1 规格可派生（全自动）**：ISA×特权×trap×异常×hart 交织×双发射配对覆盖，从 meta-spec 直接生成（先例：riscv-dv 覆盖流程、core-v-verif ISACOV 的 YAML 驱动）；
  - **L2 协议/接口覆盖（随模板）**：每个生成的 agent 自带 covergroup 骨架——满足"每个组件统一模板"的要求；
  - **L3 微架构角例（人工）**：模板预留扩展点，不承诺自动生成。
  - 论文指标：报告 L1+L2 自动生成占比，L3 人工占比即"语义增量"。
- **E5（补充）scoreboard 比对策略必须进模板语言**：lock-step / 窗口化 / 豁免窗是模板一等公民字段，只生成壳无意义——这是 UVM 生成的真难点，也是与 UVMarvel（总线子系统域，无 cosim）的差异所在。
- **E6（补充）签发自动化是第 ⑤ 产物**：signoff.py（4-stage gate + profile）泛化为框架组件，否则"生成完环境怎么跑回归"无闭环。
- **E7（v3.2 定稿）"全 QEMU 基底的分层 oracle"架构成立**（回应"QEMU 一套体系能否从单核撑到多核异构"，2026-06-12 第二轮核查）：
  - **核级 lock-step oracle = QEMU 实例**：`one-insn-per-tb=on`（每翻译块一条指令）与 `-icount`（含 record/replay 确定性重放）均为 QEMU 官方运行模式（qemu-options.hx 第一手核实），加上 9.x plugin API（E2），逐指令、确定性、可导出的执行模式三要素齐备。
  - **系统级 oracle = QBox TLM 平台**：同一 QEMU 基底经 libqemu-cxx 多实例组合（ARM/RISC-V/Hexagon 已核实），承担核间窗口化事件比对 + 后续效能评估扩展。
  - **阶段一到阶段三同一基底**，不存在"换体系"断点；Spike 的角色限定为**阶段一桥保真度标定的对照系**（造新尺子需要旧尺子校一次），标定完成即退场，阶段二/三不出现——不破坏"QEMU 一套体系"。
  - **业界异构处理器验证现状**（回应"别人怎么做"）：分层——核级各自 ISS lock-step；系统级 = 虚拟平台/混合仿真（Virtualizer+ZeBu、Helium+Palladium、Veloce HYCON，训练知识待核）+ PSS 自检式测试 + 软件驱动验证。**系统级普遍没有指令级金模型比对**——"VP 作系统参考 + 核级 lock-step 同基底"正是空白，亦与 §3.5（ESP/Chipyard 仅软件测试+FPGA）互证。
  - **最接近的现有物 = Renode**（Antmicro，第一手核实）：明确支持"异构多核 SoC 与多节点系统"仿真、在 riscv-dv 官方 ISS 列表中、另有 Renode+Verilator HDL 协同仿真——是论文必引、必差异化的 prior art；但它同样不做 retire 级 UVM lock-step，生态定位是嵌入式软件测试而非 RTL 验证 oracle。
  - GitHub 检索 QEMU+Verilator 协同仿真仅见零星个人仓库，无成型生态——再次确认桥是空位。

### 2.5.5 三阶段工具链对照（方法论同构，工具实现递进）
| | 阶段一：处理器 | 阶段二：异构处理器 | 阶段三：多核异构 |
|---|---|---|---|
| ① gen-uvm | 单核环境模板库，EH2 实例化 | 模板库泛化：第二类核（含自定义扩展），验证"换核零重写" | 平台级装配：互联 agent、多核 virtual sequence、系统级 scoreboard |
| ② gen-ref | QEMU 单核 ISS 适配（**QEMU-RVVI 桥**）；Spike 交叉校验兜底 | QBox 单核平台 + 自定义 CSR/指令适配表 | QBox 多实例异构平台自动装配（拓扑 spec → SystemC 接线）|
| ③ gen-stim | riscv-dv 配置生成（core_setting/testlist 从 meta-spec 派生）| riscv-dv + custom instr 扩展生成 | **hetero-dv**：场景 DSL → 各核程序 + 通信/同步骨架 + 预期事件序 |
| 比对语义 | 核内逐指令 lock-step（RVVI-API）| 同左 + 自定义指令豁免窗 | 核内 lock-step + 核间窗口化事件比对 |
| 覆盖率 | L1+L2 自动，L3 扩展点 | 同左 + 自定义扩展覆盖派生 | + 互联/通信场景覆盖、跨核交织覆盖 |
| 案例 | EH2（加 RVVI module）| 第二核（建议含自定义扩展的 RISC-V 核）| 互联组织的多核异构系统 |
| 对应 Phase | A | B–C 前半 | C 后半 |
| ④ gen-fi（研究内容三）| 单核试点（ECC/parity，cosim-as-oracle）| 保护域模板化 | 跨 IP 故障传播度量 |

---



## 3. 分支柱调研

### 3.1 支柱 1：UVM 验证环境自动化

**工业界现状（成熟度：寄存器域已解决，环境级仍是模板+人工）**

| 做法 | 代表 | 覆盖范围 | 置信度 |
|---|---|---|---|
| IP-XACT 元数据驱动 | IEEE 1685-2022；Arteris Magillem、Agnisys IDesignSpec、Defacto | 寄存器模型、互联装配、部分 TB 骨架 | 高 |
| SystemRDL 2.0 → UVM RAL | Accellera SystemRDL；开源 PeakRDL（systemrdl-compiler + peakrdl-uvm） | 寄存器域单源生成（RTL+RAL+文档+头文件） | 高 |
| UVM 框架生成器 | Siemens UVM Framework（UVMF，免费，Python 模板生成 bench/agent 骨架） | 环境骨架 | 高 |
| 单源寄存器流（开源标杆） | **lowRISC OpenTitan**：hjson 单源 → `reggen` 生成 RTL 寄存器+RAL+文档+DIF；`uvmdvgen` 生成 agent/env 骨架 | 寄存器域 SSOT + 骨架 codegen，**最接近你支柱 1 的开源实践** | 高 |
| AI 辅助（商业） | Cadence Verisium（AI 调试/回归）、Synopsys VSO.ai（覆盖率收敛/回归优化） | 不做环境构建，做收敛优化 | 高 |

**学术界（LLM 浪潮 2023–2026）**
- AutoSVA：模块接口注解 → SVA 自动生成（Orenes-Vera 等，DAC 2021，置信度高）。
- AssertLLM：从自然语言 spec 生成 SVA（2024，ASP-DAC 2025 前后，置信度中）。
- AutoBench / CorrectBench：LLM 生成 RTL testbench 并自校正（Qiu 等，MLCAD 2024 / 2025，置信度中）。
- LLM4DV：LLM 生成验证激励的探索（剑桥/帝国理工，arXiv 2023，置信度中）。
- ChipNeMo：NVIDIA 领域适配 LLM 用于 EDA 生产力（arXiv 2023/DAC 2024 受邀，置信度高）。
- 综述类："Survey of ML in functional verification"（2023 前后，置信度中）。

**结论/缺口（v2 修正）**：(a) 自动化只在寄存器域达成了"单源生成"；(b) 模板路线的环境级自动化=骨架（UVMF/uvmdvgen），语义仍人工；(c) **LLM 路线已于 2026 年推进到子系统级（UVMarvel，DAC 2026，见 §1.5）**，但处理器级/系统级（多核异构、互联、一致性、SMT）UVM 环境无人做到，且 LLM4DV 作者自承复杂设计失效；(d) **没有人把环境生成与参考模型、激励、覆盖率的生成共享同一份语义规格**。→ 你的支柱 1 应定位为"处理器/异构系统专用的生成式装配框架 + 可复用组件库"，与 UVMarvel 的差异 = 域（处理器 vs 总线子系统）+ 四件套同源 + cosim oracle 闭环 + 系统级规模。

### 3.2 支柱 2：参考模型与 cosim

**标准接口**
- **RVFI**（RISC-V Formal Interface，YosysHQ/riscv-formal，C. Wolf）：retire 级标准信号集（含 `rs1/rs2_rdata`、`rd_wdata`、`pc_rdata/wdata`、`mem_*`、`trap/halt/intr/mode/ixl`，NRET 可参数化），是 riscv-formal 形式检查器套件的输入契约。置信度高。
- **RVVI**（RISC-V Verification Interface，github riscv-verification/RVVI）：RVVI-TRACE（SV 接口，显式含 **hart 维度**与 CSR 通道）+ RVVI-API（C 接口）；ImperasDV 的输入契约。Imperas 已于 **2023 年被 Synopsys 收购**（置信度高）。
- 行业惯例：核内 tracer → RVFI/RVVI → 比对器（ISS 在后面）。**RVVI 比 RVFI 更适合做 cosim 总线**（RVFI 起源是 formal，无 hart/CSR 全集约定）。

**单核 cosim 方法学标杆**
- **lowRISC Ibex**：Spike 改造版逐指令 lockstep，RVFI 驱动，**异步事件契约**（先注入 mip/debug_req/nmi 再 step，错误响应/内存副作用单独握手）——eh2-veri 已明确对标此方法学（这是正确的选择）。置信度高。
- **OpenHW core-v-verif**：CV32E40P 用 ImperasDV 完成工业级 sign-off（DVCon Europe 2021–2023 系列论文）；CVA6 有开源 **Spike tandem** 路径；附 ISA 功能覆盖模型（ISACOV 思路）。置信度高/中高。
- **CHIPS Alliance VeeR 官方**：自带 SV TB + **Whisper/VeeR-ISS** 离线 trace 比对（非在线 lockstep；Whisper 支持 EH2 平台 CSR 和多 hart，有 server 模式）。你的 eh2-veri（在线 DPI lockstep + UVM）**已经超越官方 TB 的方法学水平**。置信度高。
- **TestRIG**（剑桥）：RVFI-DII 直接指令注入 + 与 **Sail** 金模型并行差分（QuickCheck 式收缩反例），IEEE D&T 2023 前后。对你的价值：标准接口让"换 DUT/换金模型"即插即用的范例。置信度中高。

**spec → ISS（参考模型自动生成的先例）**
- **Sail**：RISC-V 官方形式 ISA 规格语言，自动生成 C/OCaml 模拟器 + 定理证明器定义（Armstrong 等，POPL 2019）；新版架构兼容性测试（ACT/RISCOF）以 Sail 为参考模型。置信度高。
- **CoreDSL 生态（Scale4Edge，TUM/MINRES）**：CoreDSL 描述 ISA/微行为 → **M2-ISA-R** 生成 ETISS ISS；→ DBT-RISE/TGC 生成快速 ISS；→ Longnail（ASPLOS 2024，待核）做自定义指令 HLS；→ Seal5（2024）生成 LLVM 后端。**这是"单源规格→多工件"在设计侧最强的先例**，但全部在设计/软件侧，不含验证环境与激励。置信度中高。
- **MicroTESK**（ISPRAS）：nML 规格 → ISS + **测试程序生成器**（spec→两个工件，最接近你的"spec→多工件"主张的验证侧先例），支持 RISC-V/MIPS/ARM，多核模板有限。置信度中高。
- Pydrofoil（Sail→RPython JIT 加速 ISS，2023–2025）。置信度中。

**虚拟平台（异构参考模型底座）**
- **QBox**（Qualcomm 开源，quic/qbox，源自 GreenSocs）：QEMU 封装为 SystemC TLM-2.0 组件，支持**多实例、多架构异构**（ARM+RISC-V 混合 VP）。是你"QEMU/QBox 模板化参考模型"设想的直接底座。置信度高。
- AMD/Xilinx `libsystemctlm-soc`（remote-port 协议）：QEMU↔SystemC/RTL 协同仿真的成熟开源实现（Zynq 流程标配）。置信度高。
- PULP **GVSoC**（ICCD 2021，Bruschi 等）：可配置全平台 VP，PULP 多核系统的事实参考模型，但与 RTL 非 lockstep。置信度中高。
- 商业对照：Synopsys Virtualizer、Cadence Helium、MachineWare SIM-V——VP 装配是 GUI/库驱动的人工流程，**无人从 spec 自动装配 VP 并把它接成 UVM cosim oracle**。置信度中高。
- UVM↔TLM 桥：Accellera UVM-SystemC、Siemens UVM-Connect（UVMC）。置信度中高。

**多核/多 hart cosim 检查**
- Dromajo（Esperanto/CHIPS）：为 RTL cosim 设计的 RV64 ISS，BlackParrot/BOOM 用其做多核 cosim（每核退休流分别比对，共享内存交错由 cosim hint 处理）。置信度高/中高。
- 共享内存弱序检查（**你应明确排除的硬核领域**）：TSOtool（ISCA 2004）、MTraceCheck（ISCA 2017）、RTLCheck（MICRO 2017，RTL vs 公理化内存模型）。引用它们来论证"松耦合定界"的合理性。置信度高。

**结论/缺口**：单核 lockstep cosim 完全成熟（你已在用）；spec→ISS 有强先例（Sail/CoreDSL/MicroTESK）；**异构 VP 的"自动装配"与"作为 UVM cosim oracle 的标准化接入"是空白**；多 IP/多 hart 的标准比对接口（RVVI 只到多 hart 单核语义）与松耦合系统的等价判据（窗口化/事务级）是可发表的方法学贡献。

### 3.3 支柱 3：随机激励生成

**单核（成熟，直接复用）**
- **riscv-dv**（Google→CHIPS Alliance）：SV/UVM 约束随机汇编生成器，特权态/页表/陷入处理齐全；`num_harts` 选项存在但**多 hart 支持薄弱**（独立代码段，无核间共享内存/同步场景协同，置信度中，待核）。
- **FORCE-RISCV**（Futurewei→OpenHW）：C++/Python RV64 生成器，宣称多线程/多核测试生成能力（置信度中，待核）。
- **MicroTESK**：nML 驱动 + Ruby 模板，学术可引用性强。
- IBM 谱系（模型驱动生成的学理源头，必引）：**Genesys-Pro**（IEEE D&T 2004）、**Threadmill**（DAC 2011，post-Si 多核 exerciser）、**X-Gen**（HLDVT 2002 前后，SoC 系统级场景生成）。置信度高/中高。
- 商业：Valtrix STING（裸机可移植激励内核）。置信度高（存在性）。

**异构/系统级（你的"对标 riscv-dv 的异构工具"所在的空间）**
- **Accellera PSS**（Portable Test and Stimulus Standard）：v1.0=2018、v2.0=2021、v2.1≈2023、v3.0≈2024（行为覆盖率等，年份待核）。DSL 语义：action/component/resource/buffer-stream-state 对象 + 调度约束求解 → 生成跨核 C 测试 + UVM 序列 + transactor 活动。**这就是工业界对"异构系统级随机激励"的回答**——但全部闭源商业：Breker TrekSoC/RISC-V TrekApps（CoreAssurance/SoCReady）、Cadence Perspec、Siemens Questa inFact/PSS。置信度高。
- **开源 PSS 实现≈空白**：M. Ballance 的 zuspec/pyvsc 等处于早期（置信度中）。→ **开源、处理器中心、与 cosim oracle 闭环的"hetero-dv"没有先例**。
- 学术探索：RL/覆盖率引导生成（Design2Vec，Google 2021/2022 置信度中；多篇 DATE/ICCAD RL-on-riscv-dv 论文，置信度中）；LLM4DV（2023）。均未达生产水位 → 可作为你框架的"可选增强"而非根基。

**结论/缺口**：核内激励直接复用 riscv-dv；**核间/异构场景层**（通信、同步、DMA、并发资源竞争）只有商业 PSS 工具覆盖，且它们是"自检式测试"（无指令级金模型比对闭环）。你的差异化：开源 + spec 同源 + 与 VP/ISS oracle 闭环 + 面向松耦合处理器系统的场景语义子集（不必实现整个 PSS）。

### 3.4 支柱 4（研究内容三）：容错设计有效性验证

**工业（ISO 26262 语境，"有效性"=诊断覆盖率 DC + FMEDA 指标 SPFM/LFM/PMHF）**
- 仿真故障注入：Synopsys **Z01X**（+VC-FuSa）、Cadence **Xcelium Fault Simulator**、Siemens **Veloce Fault App**（仿真器/硬件加速 FI）；Siemens Austemper（Kaleidoscope/Annealer，安全综合+FI，2018 收购）。置信度高。
- 形式故障传播：Cadence **JasperGold FSV** app（故障可达性/可观测性剪枝 + 传播证明）。置信度高。
- 流程：FMEDA 驱动故障空间 → 统计采样注入（置信区间）→ DC 度量 → 安全机制定级。

**学术/开源**
- **Chiffre**（Eldridge 等，CARRV 2018，IBM）：FIRRTL 编译期插桩的运行时故障注入框架——"编译期自动插注入点"思路可借鉴到你的生成器。置信度高。
- **ETH PULP 容错谱系**（你做容错有效性最该对标的组）：ODRG"On-Demand Redundancy Grouping"（Rogenmoser 等，2022，ISVLSI 前后待核）、**Trikarenos** TMR-Ibex 芯片（ESSCIRC/JSSC 2023–24 待核）、Hybrid Modular Redundancy（2023–24）。其有效性量化=RTL/网表级注入活动 + 检出率/恢复率统计——但用脚本化专用流程，**不与 UVM/cosim 平台同构**。置信度中高。
- **BSC/欧洲项目**：SELENE（H2020，NOEL-V 安全平台）、De-RISC、FRACTAL；SafeTI 流量注入器、SafeSU 等安全 IP（DATE/IEEE Access 2021–22 待核）。置信度中。
- UVM+FI：DVCon（欧/美）多篇工业实践论文（Infineon/Bosch 等，"UVM-based fault injection"），共性=force/release 或仿真器原生 FI 命令封装为 UVM agent/sequence。置信度中高。
- QEMU/VP 级 FI（FIES 等，嵌入式软件容错评估线）。置信度中。

**结论/缺口**：FI 工具与度量体系成熟，但 (a) 学术开源侧**没有与功能验证平台（UVM+cosim+覆盖率+回归）共享基础设施的 FI 环境**——FI 总是"另一套脚本"；(b) **故障判决 oracle 通常是"与无故障仿真 diff"**，用 cosim 金模型当 oracle（可区分 masked/SDC/DUE、可量化检测延迟）的系统化方法有论文空间；(c) **跨 IP 故障传播**（核内故障→互联→另一核/系统级效应）在松耦合多核语境下几乎无人量化。→ 研究内容三的定位：同一 meta-spec 派生故障空间与保护域映射，FI agent 与功能环境同构，cosim/VP 为判决 oracle，输出 DC/检测延迟分布/传播图谱。

### 3.5 异构开源平台的验证现状（证明缺口真实存在）

- **ESP**（哥伦比亚，Carloni 组，ICCAD 2020 受邀"Agile SoC Development with Open ESP"待核）：松耦合加速器+NoC 的旗舰开源平台；验证=每加速器单元测试 + 全系统 FPGA 原型跑软件，**无系统级约束随机/cosim 方法学**。置信度中高。
- **Chipyard/FireSim**（Berkeley，IEEE Micro 2020 / ISCA 2018）：Spike tether、BOOM 用 Dromajo cosim；系统级靠软件测试 + FPGA 加速仿真。置信度高。
- **OpenPiton**（ASPLOS 2016）、**PULP Occamy/Snitch**（GVSoC 为 VP，无 lockstep）：同样模式。置信度中高。
- gem5+RTL 混合（BSC 2021 框架）：性能验证向。置信度中。
- 互联 VIP：商业 AXI/CHI VIP 成熟；开源有 pulp-platform/axi 等监视器级组件。置信度中高。

**含义**：开源异构平台的功能验证普遍停留在"软件测试+单核 cosim+FPGA"，**没有任何平台提供异构系统级的约束随机激励 + 金模型比对 + 覆盖率收敛闭环**。这是你课题成立的最有力外部证据。

---

## 4. Gap 分析（对四个关键问题的直接回答）

**(a) 有没有人从单一 spec 协同生成 UVM 环境+参考模型+激励+覆盖率？**
没有发现。最接近的：OpenTitan hjson（仅寄存器域）、MicroTESK（ISS+TPG 两件）、Scale4Edge CoreDSL（设计侧 ISS+RTL+编译器）。验证侧四件套协同生成 + spec 变更一致性闭环 = **空白，可作为论文级主张**（需在论文中如实对比上述三者）。

**(b) 松耦合异构多核的参考模型/cosim 支持？**
单核 lockstep 成熟；多 hart 同核（Whisper/Spike 多 hart）可用；**异构多实例 VP 作为 UVM cosim oracle 的自动装配与标准接口（RVVI 的异构扩展）不存在**。QBox 提供了底座但装配是人工 C++/SystemC。

**(c) 自动化程度 vs 人工？**
工业共识：寄存器域全自动，骨架半自动，语义人工。你的量化指标应设计为：生成代码占比、跨核移植人时（EH2→第二核）、spec 变更后再生一致性（防三处人工同步漂移——eh2-veri 现状 CSR 信息就有三处独立维护，见 §7.2，是天然的 motivating example）。

**(d) 容错有效性验证与 UVM+cosim 平台一体化？**
工业工具链（Z01X 等）独立于功能验证环境；学术 FI 框架（Chiffre、ETH 流程）亦独立。**一体化 + cosim-as-oracle + 跨 IP 传播度量 = 空白**。

---

## 5. 创新点（4 个，含防御性论证）

### 创新点 1：统一语义元规格（Meta-Spec）驱动的"验证四件套"协同生成
- **内容**：定义机器可读规格（核类型/ISA 扩展/特权/CSR 语义/内存映射/总线拓扑/通信原语/中断/调试/保护域），生成器装配出：① UVM 环境（agent 选型与例化、RAL、scoreboard 绑定、接口适配）；② 参考模型配置（ISS 启动参数、CSR 预注册表、VP 拼装清单）；③ 激励配置（riscv-dv core_setting、异构场景约束）；④ 覆盖率骨架与 FI 故障空间。
- **最近邻 prior art 及差异**：OpenTitan（仅寄存器）、MicroTESK（ISS+TPG，无 UVM/覆盖率）、CoreDSL/Scale4Edge（设计侧）、**UVMarvel（DAC 2026，LLM spec→子系统级 UVM，见 §1.5——必须对比：其边界是总线子系统级、单 DUT、无参考模型/cosim/故障维度）**。差异=验证侧全要素 + 一致性闭环 + 异构拓扑维度 + 处理器域。
- **度量**：自动生成代码/配置占比；EH2→第二核移植人时下降；spec 单点修改的全工件再生正确性。
- **发表**：DVCon（方法学）→ DATE/ASP-DAC（机制）→ TCAD/TVLSI（体系）。

### 创新点 2：异构参考模型自动装配 + hart/IP 感知比对接口 + 窗口化等价判据
- **内容**：以 QBox/QEMU+SystemC TLM（或先期多 Spike 实例）为底座，meta-spec → VP 自动装配（N 异构核 ISS + mailbox/DMA/共享存储的事务级镜像）；定义 RVVI 的异构扩展（每 retire 流带 hart/IP 标识 + 事务流通道）；**等价判据**：以通信事件（mailbox 写、DMA 完成、同步屏障）切分时间窗，窗内各核独立指令级 lockstep，窗界做消息序/数据一致性检查。
- **防御**：松耦合定界使判据可判定（与 RTLCheck/MTraceCheck 的共享内存公理检查正交，引用其论证难度）；商业 VP 装配（Virtualizer/Helium）人工且不接 UVM oracle。
- **发表**：DAC/ICCAD（机制+正确性论证）+ 工件开源。

### 创新点 3：spec 驱动的异构系统级激励生成器（"hetero-dv"）
- **内容**：场景 DSL（PSS 语义子集：action/resource/dataflow，自定义文本格式即可，不必兼容 PSS 全集）→ 求解展开为每核裸机程序（核内指令流复用 riscv-dv）+ 核间通信/同步/DMA 场景代码 + **预期事件序**（直接喂创新点 2 的检查器）。
- **防御**：商业 PSS 工具闭源且自检式（无指令级金模型闭环）；开源 PSS 空白；riscv-dv 多 hart 薄弱（核内强、系统级无）。
- **发表**：DATE/DAC + 开源工具论文（如 TCAD tool track）。

### 创新点 4：与功能验证平台同构的容错有效性验证环境（研究内容三）
- **内容**：meta-spec 标注保护域（ECC/奇偶/锁步/TMR）→ 自动派生故障空间与注入活动；FI agent 复用 UVM 环境（force/release 或仿真器 FI 命令）；**cosim/VP 为故障判决 oracle**（自动分类 masked/detected/SDC/DUE）；输出诊断覆盖率、检测延迟分布、**跨 IP 故障传播图谱**（核内注入→互联→他核效应）。
- **防御**：商业流（Z01X 等）与功能环境割裂且闭源；ETH/BSC 的 FI 量化为专用脚本流；cosim-as-oracle + 松耦合传播度量无先例。
- **发表**：ITC/ETS/DATE + 期刊（TVLSI/ToR）。

---

## 6. 博士总体路线图（Phase A–D）

> 原则：每阶段产出"平台增量 + 量化数据 + 论文 + 开源工件"四样；EH2 贯穿始终作为基线案例。

### Phase A（2026 H2）：EH2 案例硬化 + Meta-Spec v0
- 完成 eh2-veri 改进 R1+R2（§7）；
- 把 `eh2_configs.yaml` 升级为 meta-spec v0（JSON Schema 校验），写第一个生成器原型（Python/jinja2）：生成 Spike 启动参数与 CSR 预注册表、riscv-dv core_setting、fcov 骨架、testlist、TB 参数——**验收：换 `minimal` 配置零手改跑通 smoke+cosim**；
- 论文/产出：DVCon China/Europe 经验论文或国内核心期刊 + eh2-veri v2 开源 + 自动化占比基线数据。

### Phase B（2027 H1）：同构双核
- 2×EH2（或 EH2+EL2）经 AXI fabric + mailbox + DMA 组成小系统 TB；
- 多 ISS 实例协调 cosim（每核一 Spike + 共享存储镜像同步协议）；窗口化检查器 v0；
- hetero-dv v0：双核同步/通信场景 DSL 雏形（生成两份裸机程序 + 预期消息序）；
- 论文：DATE/ASP-DAC（多核 cosim 窗口化检查机制）。

### Phase C（2027 H2 – 2028 H1）：异构
- 引入第二种核（建议 CV32E40P：开源、有 RVFI、有 core-v-verif 对照组；或 CVA6 拉开 RV32/RV64 差异）+ 一个加速器 TLM stub；
- QBox VP 自动装配（meta-spec v1：拓扑/通道/同步原语）；RVVI 异构扩展接口定稿；
- 四件套生成闭环完整演示 + 移植人时数据（EH2→CV32E40P）；
- 论文：DAC/ICCAD（核心机制）+ TCAD/TVLSI（体系化长文）。

### Phase D（2028）：容错有效性 + 学位论文
- FI 层落地：EH2 ICCM/DCCM ECC、icache 奇偶作为第一保护域案例（eh2-veri ADR-0017 的 integrity 测试翻转为 FI 一等公民）；可选在一个核上加 DCLS 包装做锁步案例；
- 跨 IP 传播度量在异构平台上跑通；DC/延迟/SDC 率报告自动化；
- 论文：ITC/ETS/DATE + 期刊；学位论文整合。

### 关键风险与降级路径
| 风险 | 对策/降级 |
|---|---|
| QBox/SystemC 上手成本高 | Phase B 先用"多 Spike 实例 + 共享存储镜像"，VP 推迟到 Phase C；QBox 不行就 QEMU 多机 + remote-port |
| **QEMU 逐指令 lock-step 无开源先例，保真度待核查**（v3.1 修正，见 2.5.4-E2：API 通道已具备，定性为核心交付物而非可行性风险） | 预研提前（§9.6 最小实验：plugin insn_exec_cb + read_register + icount 单步）；降级 = Spike 通路保核内 lock-step，QEMU/QBox 只承担核间窗口化事件比对层 |
| 场景 DSL 语义工程量大 | 只做 PSS 语义子集（action/resource/序列化约束），先覆盖 mailbox/DMA/屏障三类原语 |
| EH2 双线程 cosim 角例多 | 已有 ADR-0016 基础；SMT 深水区问题如不可收敛，定界为"双 hart 顺序交错可判定子集"并文档化 |
| riscv-dv 多 hart 不可用 | 核内单 hart 生成 + 生成器在链接层做多核布局（每核独立段+共享通信区），绕开 riscv-dv 多 hart |
| LLM 辅助生成不可靠 | 仅作为可选增强（骨架草稿），不进入核心主张 |

---

## 7. eh2-veri 现状审计与改进路线

### 7.1 现状（今日实地审计，整体评价：远好于你自述，方法学已对标 Ibex，v1.1 已签发）

已具备：真 UVM 环境（env + 6 agents：axi4 passive×4 口/irq/jtag/halt_run/trace/cosim + scoreboard + vseq）；Spike DPI 在线 lockstep cosim（`dv/cosim/spike_cosim.cc`，Ibex 式异步事件注入次序，NUM_THREADS=1/2 均支持，per-hart 队列路由，ADR-0016）；RVFI 适配 sidecar（ADR-0015，`rtl/eh2_veer_wrapper_rvfi.sv`）；riscv-dv 集成（`riscv_dv_extension/`）；功能覆盖（`fcov/`）+ 波形/覆盖率报告 + 4-stage signoff gate（smoke/directed/cosim/riscvdv，profile 化）+ CI；formal（SymbiYosys+IFV）；DC 综合 + Formality 块级 LEC；lint（verible/verilator）；ADR×20 + CONTEXT.md + Sphinx 中文文档。

### 7.2 结构性短板（带证据）

1. **RVFI 不标准、不完整**（你的判断正确，但具体问题在这里）：
   - 缺 `rvfi_rs1_rdata/rs2_rdata`（trace 端口无 rs 数据；标准 RVFI 必备，riscv-formal 检查器依赖）；缺 `rvfi_halt/rvfi_ixl`；无 CSR 通道（`rvfi_csr_*`）；
   - **无 hart 维度**：双通道是 i0/i1 双发射（`eh2_rvfi_if.sv:5`），NUM_THREADS=2 时 RVFI 流无法区分 hart（cosim 是靠 trace_seq_item.thread_id 走的另一条路）；
   - 疑似 bug：`eh2_veer_wrapper_rvfi.sv:117-118` 两通道共享同一 `trace_ecause` 且 `[4:0]→[3:0]` 截断；
   - **mem 通道盲区**：RVFI 的 mem_* 只从 LSU AXI 总线 probe（`:34-40`）——**DCCM/ICCM 内部访问不走 AXI，在 RVFI 上不可见**，而 DCCM 是 EH2 主数据通路。
2. **CSR 信息三处独立维护**（SSOT 反面教材，也是你课题的天然动机案例）：`riscv_dv_extension/csr_description.yaml`、uvm_reg 模型（ADR-0010 `csr_desc_t`）、`eh2_cosim_csr_preregister.svh`（18+ 自定义 CSR 的 Spike set_csr 注册）。
3. **compliance 框架过时**：用的是已废弃的 riscv-compliance（ADR-0011）；上游已迁移到 riscv-arch-test + RISCOF（参考模型 Sail/Spike）。
4. **dual_thread 非签发一等公民**：默认 profile NUM_THREADS=1（`eh2_configs.yaml: default`），SMT 是 EH2 的灵魂特性。
5. **dv/verilator 为空**：无开源仿真路径，影响可复现性与开源影响力。
6. **formal 用 IFV（过时工具）**；RVFI 标准化后应接 riscv-formal 标准检查器（白拿一套 insn/reg/pc 检查器）。
7. **Makefile `clean`/`demo` 危险**：`make demo` 隐式 full clean，曾实际删除 `build/r3b_final`、`build/r4a_final` 签发证据（2026-05-17 事故）；`clean_workspace.sh` 的 archive 白名单机制存在但不是默认。
8. ADR-0017：integrity 故障注入测试 cosim-disabled + 豁免——恰是研究内容三的入口。

### 7.3 改进路线

**R1 标准化与还债（2–4 周）**
1. RVFI 补全至 riscv-formal 标准子集（新 ADR-0021）：补 `rs1/rs2_rdata`（probe 拉寄存器堆读口，或 sidecar 影子寄存器堆——Ibex tracer 即影子法）、`halt/ixl`、CSR 通道（先 mstatus/mepc/mcause/mtval/mip）；**加 hart 维度**（NRET×NHART 通道布局 + 每通道 hartid 旁带，写明这是对 RVFI 的自定义扩展）；修 ecause 截断/共享问题；DCCM 访问补入 mem 通道（从 probe 接口取 DCCM 读写口）或明确文档化盲区。
2. 新增 RVVI-TRACE 薄壳（rvfi→rvvi 映射），scoreboard 输入改走标准接口——这是课题"标准化组件库"的第一块砖，也为将来接 ImperasDV/其他核留口。
3. compliance 升级：riscv-arch-test + RISCOF（ADR-0022）。
4. Makefile 安全化：`demo` 不再隐式 full clean；`clean` 默认 `MODE=archive`；CI 加 `make -n` 守护检查 `build/*_final` 不在删除集合。
5. （顺手）formal 侧把标准化 RVFI 接入 riscv-formal 检查器，替代 IFV 老路径。

**R2 单核深化（4–8 周）**
6. dual_thread 进 nightly/full 签发矩阵（signoff.py 增加 CONFIG 维度）；SMT 定向场景：共享 DCCM 仲裁、`mhartstart` 启停、线程间 fence/AMO、PIC 双 hart 分发。
7. riscv-dv 多 hart 路径试通（`num_harts=2`）；不可用则按 §6 风险表的链接层绕行方案。
8. fcov 扩展：ISA 级覆盖（riscv-dv cov 流程或 ISACOV 思路）+ 双发射配对交叉（i0/i1 类别×stall×flush×trap）+ 收敛看板进 signoff_report。
9. 补全 dv/verilator 开源仿真路径（Verilator 5 + DPI 可移植性改造）。

**R3 平台化（2–3 个月，正式对接课题）**
10. meta-spec v0：合并 `eh2_configs.yaml` 与 CSR 三源 → 单一 schema；生成器吐出 CSR 预注册表、RAL、csr_description、Spike 参数、core_setting、fcov 骨架、testlist。验收=minimal 配置零手改通 smoke+cosim；量化=三源一致性漂移问题就此消失（写进论文）。
11. FI 预研：TB 层 force/release FI agent v0，复活 ADR-0017 integrity 测试为注入活动，统计 ECC 检出率/检测延迟——研究内容三的第一个数据点。

**R4 多核起步（衔接 Phase B）**
12. 2×EH2 AXI fabric + mailbox 小系统 TB；双 Spike 实例 + 共享存储镜像；窗口化比对器原型。

---

## 8. 文献与工具速查（按支柱，含置信度）

> 高=可直接引用（仍建议核对年份）；中=题名/主张可信但出处细节需核；联网后用 deep-research 复核全表。

- 标准/接口：IEEE 1685-2022 IP-XACT（高）；Accellera SystemRDL 2.0（高）；Accellera PSS 2.0/2.1/3.0（版本年份中）；RVFI/riscv-formal（高）；RVVI（**已核实**，多 hart/多发射/乱序支持确认）；UVM-SystemC、UVMC（中高）。
- 环境自动化：OpenTitan reggen/uvmdvgen（高）；PeakRDL（高）；Siemens UVMF（高）；AutoSVA DAC'21（高）；ChipNeMo（高）；AutoBench MLCAD'24（中）；AssertLLM（中）；LLM4DV（**已核实**，arXiv 2310.04535）；**UVMarvel DAC 2026（已核实，arXiv 2605.04704，v2 新增）**；UVLLM（**已核实**，arXiv 2411.16238，修复率数字除外）；Verisium/VSO.ai（高）。
- 参考模型/cosim：Sail POPL'19 + RISCOF/ACT（**已核实**，spec→模拟器自动生成确认，SV 参考模型 in progress）；CoreDSL/ETISS/M2-ISA-R（中高）；Seal5（中）；Longnail ASPLOS'24（中）；MicroTESK/ISPRAS（中高）；Pydrofoil（中）；Ibex cosim 方法学（高）；core-v-verif（**已核实**存在性与 RVVI 采用；tandem 细节待核）；Synopsys 收购 Imperas 2023（高）；VeeR-ISS/Whisper（高）；TestRIG/RVFI-DII，IEEE D&T'23（中高）；QBox quic/qbox（**已核实**，ARM/RISC-V/Hexagon 异构确认）；libsystemctlm-soc（高）；GVSoC ICCD'21（中高）；Dromajo（高）；BlackParrot IEEE Micro'20（中高）；**QEMU one-insn-per-tb/icount/rr 与 plugin API（已核实，E2/E7）**；**Renode（已核实：异构多核 SoC 仿真 + riscv-dv ISS 列表成员 + Verilator HDL cosim，E7 必引 prior art）**；**香山 DiffTest（已核实：REF=NEMU+Spike）**。
- 多核检查（用于定界论证）：TSOtool ISCA'04（高）；MTraceCheck ISCA'17（中高）；RTLCheck MICRO'17（高）。
- 激励：riscv-dv（**已核实** README 基本能力与 cosim 列表；多 hart 薄弱判断维持）；FORCE-RISCV（**已核实**：Python 模板、Handcar/Spike、Sv32/39/48、multiprocess/multithread 生成明确列入 README；实际成熟度仍需上手验证）；Genesys-Pro IEEE D&T'04（高）；Threadmill DAC'11（中高）；X-Gen（中）；STING（高）；Breker TrekApps / Cadence Perspec / Questa inFact（高）；zuspec/pyvsc（中）；Design2Vec（中）。
- 容错：Z01X/VC-FuSa、Xcelium FS、Veloce FA、Austemper、JasperGold FSV（均高）；Chiffre CARRV'18（高）；ETH ODRG/Trikarenos/HMR（中高，年份待核）；SELENE/De-RISC/FRACTAL、SafeTI/SafeSU（中）；ISO 26262 FMEDA/DC/SPFM（高）。
- 异构平台：ESP/ICCAD'20 受邀（中高）；Chipyard IEEE Micro'20、FireSim ISCA'18（高）；OpenPiton ASPLOS'16（高）；PULP Occamy/Snitch（中高）；gem5+RTL BSC'21（中）。

---

## 9. 下一步行动建议（按优先级，v3 更新）

1. ~~网络恢复后跑 deep-research 复核~~ **已完成关键项**（§1.5）。剩余待核：方向 5 全部外部声明（Z01X/Chiffre/ETH 容错谱系等）、Genesys-Pro/Threadmill/McVerSi/STING 细节、core-v-verif tandem 架构——投稿前补一轮专项复核即可，不阻塞动手。
2. 立即可做：R1.4 Makefile 安全化（半天，消除签发证据再次被删的风险）；R1.1 RVFI 标准化（课题红利最大的单项；v2 补充：标准化目标按 §1.5 核实结论**直接对齐 RVVI-TRACE**——其多 hart/多发射参数化原生覆盖 EH2 双 hart 双发射，比裸 RVFI 更省一次迁移）。
3. 一个月内：R1 全部 + R2.6（dual_thread 进签发矩阵）——EH2 案例的"含金量"主要看 SMT。
4. 开题报告/中期里引用 §4 的 Gap 表和 §5 的防御性论证结构；**UVMarvel（DAC 2026）必须纳入 prior-art 对比**，它同时是"该方向热度"的证据和"系统级空白"的反衬。
5. 动手做异构激励生成器前，先花 1–2 天上手实测 FORCE-RISCV 的 multithread 生成（README 声明已核实，可用性未验证），决定"扩展它"还是"riscv-dv + 链接层多核布局"路线。
6. **（v3.1 更新）QEMU-RVVI 桥预研提前到 Phase A 后半**：2.5.4-E2 已确认 API 通道存在（QEMU 9.x plugin：`vcpu_insn_exec_cb` 逐指令回调 + `read_register`），且无开源先例 = 创新点 2 的核心交付物。最小实验 = QEMU rv32 + icount/one-insn-per-tb 单步 + plugin 导出指令级 PC/rd 流，经 RVVI-API 喂给现有 eh2 cosim scoreboard 跑通 `cosim_smoke.S`，与 Spike 通路结果交叉对照（保真度核查的对照系）。跑通 → 逐项扩展角例保真度核查（WARL/计数器/异常优先级）；受阻 → 降级路径为"Spike 保 lock-step，QEMU/QBox 做核间窗口化比对层"，框架叙事不受影响。

---

## 附录：v2 已核实来源（2026-06-12 联网核对）

- UVMarvel: https://arxiv.org/abs/2605.04704 （DAC 2026 录用）
- LLM4DV: https://arxiv.org/abs/2310.04535 · https://github.com/ZixiBenZhang/llm4dv
- UVLLM: https://arxiv.org/abs/2411.16238
- riscv-dv: https://github.com/chipsalliance/riscv-dv
- FORCE-RISCV: https://github.com/openhwgroup/force-riscv
- RVVI: https://github.com/riscv-verification/RVVI
- core-v-verif: https://github.com/openhwgroup/core-v-verif
- sail-riscv: https://github.com/riscv/sail-riscv
- QBox: https://github.com/quic/qbox
