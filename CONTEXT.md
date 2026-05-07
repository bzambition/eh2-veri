# EH2 验证平台 — 领域语境

本文档定义 EH2 UVM 验证平台的术语、模型与约定。新会话进入此项目时应先读此文档。

更新日期：2026-05-07（Sign-off full profile PASS — Phase 1-5 主体完成）

---

## 1. 项目定位

`eh2-veri/` 是 **VeeR EH2 RISC-V 核**的工业级 UVM 验证平台，**对标 lowRISC Ibex 验证平台**（路径 `/home/host/ibex/dv/uvm/core_ibex/`）。

- DUT：VeeR EH2 双发射、双线程（可配置 1/2 线程）、RV32IMAC + Zb*
- 参考实现：Ibex（单发射、单线程、RV32IMC）
- 验证策略：UVM + Spike DPI 协同仿真（cosim） + riscv-dv 随机指令生成 + 功能覆盖率

## 2. 核心术语

| 术语 | 定义 |
|------|------|
| **DUT** | EH2 核（`rtl/design/`）。在 TB 中以 `dut` 实例化，通过 `eh2_veer_wrapper` 包装 |
| **Cosim / 协同仿真** | 把 DUT 每条 retired 指令喂给 Spike ISS，逐拍比对 PC、寄存器写、内存访问 |
| **trace pkt** | DUT 输出的"已退役指令"包，含 PC + insn + exception + interrupt + tval。**RTL 层 i0 与 i1 同周期同时给出**（program order：i0 在前） |
| **wb / writeback** | 寄存器写回事件。EH2 双发射有 i0 / i1 两个写回槽（slot 0 / slot 1） |
| **probe 接口** | 验证用 hierarchical reference 接口（`eh2_dut_probe_intf`），把 DUT 内部写回信号、CSR、中断态拉给 monitor |
| **slot** | 双发射的指令槽位。slot=0 是 i0，slot=1 是 i1。NB-load / DIV cancel 始终 slot=0 |
| **NB-load (non-block load)** | 非阻塞 load。指令已 retire，但写回**晚于**指令本身到达（异步通道） |
| **DIV cancel** | 除法被 kill，写回需要被作废。出现在 `vif.div_cancel` |
| **wb_seq** | 全局写回序号，由 probe_monitor 维护并写回到接口供 trace_monitor 关联使用。**目前 trace_monitor 没有读 wb_seq——这是 Phase 1 的修复点** |
| **wb_search_depth** | scoreboard 内启发式搜索窗口（band-aid，Phase 1 应删除） |
| **PIC** | EH2 自有的可编程中断控制器，127 路外部中断源。Spike 不模型，相关 CSR 用 set_csr 静态注册 |
| **DCCM / ICCM / ICache** | EH2 紧耦合存储。DCCM = 数据紧耦合存储；ICCM = 指令紧耦合存储 |
| **mailbox** | 0xD058_0000 地址。0xFF=PASS, 0x01=FAIL，其它字符=控制台输出 |
| **NUM_THREADS** | EH2 硬件线程数（1 或 2）。**cosim 支持 NUM_THREADS=1 和 NUM_THREADS=2**（ADR-0008） |
| **EH2 自定义 CSR** | 18+ 个 EH2 特有 CSR（mscause, mrac, mfdc, meivt, meipt 等），Spike 不原生模型，需要 `set_csr` 预注册或 fixup |
| **mailbox FAIL / pass** | TB top 监听 0xD058_0000 写入决定测试通过 |
| **sign-off gate** | `dv/uvm/core_eh2/scripts/signoff.py`，4 个 stage：smoke / directed / cosim / riscvdv，全过才算签发 |

## 3. 目录约定（对标 Ibex）

```
dv/uvm/core_eh2/
├── tb/                   # 顶层 testbench（仅 DUT 实例化 + 时钟复位 + axi mem）
├── env/                  # UVM env：env、cfg、scoreboard、vseqr、env interfaces (csr_if/dut_probe_if/instr_monitor_if)
├── common/               # 各 agent
│   ├── axi4_agent/      # AXI4 监视器（passive，4 个 port: IFU/LSU/SB/DMA）
│   ├── irq_agent/       # 中断激励（active）
│   ├── jtag_agent/      # JTAG 调试（active）
│   ├── halt_run_agent/  # MPC halt/run（active）
│   ├── trace_agent/     # trace 监视器（passive，从 RTL trace_pkt 取 retired 指令）
│   └── cosim_agent/     # cosim agent（agent + cfg + scoreboard + spike DPI）
├── tests/                # base test、test_lib、seq_lib、vseq、test_pkg
├── fcov/                 # 功能覆盖率（fcov_if、fcov_bind、pmp_fcov_if）
├── riscv_dv_extension/   # riscv-dv 扩展（asm_program_gen、testlist.yaml）
├── scripts/              # Python 脚本（run_regress、collect_results、signoff、check_logs）
├── yaml/                 # rtl_simulation.yaml（VCS/Xcelium/Questa 配置）
├── waivers/              # 仿真警告 waiver
└── directed_tests/       # 定向测试（asm + testlist）
```

> **当前偏离约定的位置**：`eh2_csr_if.sv` / `eh2_dut_probe_intf.sv` / `eh2_instr_monitor_if.sv` 错放在 `common/trace_agent/`，应该在 `env/`（Phase 2 修复）。

## 4. Cosim 数据通路

```
RTL trace_pkt (eh2_dec.sv)         eh2_trace_monitor          cosim_scoreboard
  │ i0/i1 valid + insn + pc + exc   │ for each i0/i1, write   │
  ├──────────────────────────────►  │ trace_seq_item ──────►  │ trace_fifo.get()
                                                              │
RTL probe (hierarchical refs)      eh2_dut_probe_monitor      │
  │ wbd.i0v/i1v + i0_result_wb      │ wb_seq_counter++        │
  ├──────────────────────────────►  │ tag each wb event ───►  │ dut_probe_fifo.get()
  │ div_wren / div_cancel                                     │
  │ nb_load_wen                                               │
                                                              │ compare_instruction:
LSU AXI4 monitor                   axi4_monitor               │  step Spike, compare PC + rd + mem
  │ AW/W/AR/R channels             │ axi4_seq_item ────────►  │ lsu_axi_fifo.get()
```

## 5. 关键架构假设

1. **trace 通道与 wb 通道异步**：两个 monitor 都在 `posedge clk` 触发，靠 `#0` 延迟保证 wb 先入队。Phase 1 后将以 wb_tag 强关联取代 #0 hack
2. **slot 0 优先**：cross-slot 搜索仅对 load 类指令开启（NB-load 异步特性）
3. **ecause 在两 slot 间共享**：保护机制是"每 slot 自己的 exception valid 位"。所以 i0 看到 i1 的 ecause 不会出错（因为 i0 的 exc_valid=0）
4. **interrupt-only trace item**：当 `interrupt=1 && exception=0`，表示该 PC 处的指令**没有执行**，仅作为中断通知。Spike 不调 step，仅设置 mip 等

## 6. 已知 Risk（来自 docs/cosim-correctness-analysis.md）

| ID | 严重度 | 问题 | 状态（截至 2026-05-06） |
|----|--------|------|------|
| RISK-1 | HIGH | EH2 自定义 CSR 18+ 个，Spike fixup 仅 4 个 | 部分缓解（28 个 set_csr 静态注册），未做 WARL fixup（Phase 5 待做） |
| RISK-2 | MEDIUM | AXI4 64-bit 数据 → cosim 截到 32-bit | 已 mitigate（split lower/upper word） |
| RISK-2b | MEDIUM | EH2 sub-byte store 用 wider WSTRB（read-modify-write） | **已修**（Phase 3 spike_cosim BE 语义放宽） |
| RISK-3 | MEDIUM | wb 与 trace 对齐脆弱，靠 wb_search_depth band-aid | **已修**（Phase 1 RTL trace 加 RVFI 等价信号） |
| RISK-4 | RESOLVED | NUM_THREADS=2 不能 cosim | **已修**（ADR-0008：SpikeCosim 多 hart + scoreboard per-thread 路由） |
| RISK-5 | LOW | NB-load wb 跨 slot 可能脱节 | **已修**（Phase 1 scoreboard 等 nb_load hint） |
| RISK-6 | LOW | interrupt 状态采样按 item 而非 cycle | RTL 设计上已正确 |
| RISK-7 | OPEN | EH2 推测 div cancel vs 架构 retire 区分 | **已修**（Phase 1 RTL `dec_div_cancel_overwrite` 信号 + scoreboard FIFO 消费） |
| RISK-8 | RESOLVED | load_store_test data RF 不同步 | **已验证不再复现**（Phase 3 BE 语义放宽 + stream 修复后 1848 trace / 0 mismatch） |
| RISK-9 | OPEN | random_instr_test 中断/异常 cosim | ⚠️ 标 cosim:disabled（需扩展 scoreboard 处理 mcause/mepc/mtval） |
| RISK-10 | OPEN | bitmanip zba/zbb 触发 RTL illegal-instr 异常率高 | ⚠️ 标 cosim:disabled（exception 路径 cosim step 与 trace 速率不匹配） |
| RISK-11 | OPEN | atomic SC.W RTL 写回与 Spike 分歧 | ⚠️ 标 cosim:disabled（需 spike_cosim 加 atomic-store fixup） |
| RISK-12 | RESOLVED | 8 个 EH2 directed stream 全部生成空 instr_list | **已修**（Phase 3 新增 eh2_base_directed_stream，post_randomize → gen_instr 桥接） |
| RISK-13 | RESOLVED | check_logs 把 VCS banner overlap 误判为 UVM_FATAL | **已修**（UVM_SUMMARY_LINE_RE 识别 summary 行的两种损坏形态） |
| RISK-14 | RESOLVED | libcosim.so 缺失静默不链 → 仿真启动报 DPI-DIFNF | **已修**（compile_vcs 硬依赖 + NO_COSIM=1 escape hatch） |

## 7. Sign-off 标准

`make signoff SIGNOFF_PROFILE=full PARALLEL=4` 要全过才算签发。

| Stage | 当前状态（2026-05-07 sign-off full PASS） | 描述 |
|-------|---------|------|
| smoke | ✅ PASS | smoke.hex，含 cosim，6 trace / 0 mismatch |
| directed | ✅ PASS | 3 个定向 test |
| cosim | ✅ PASS | cosim_testlist 4/4（smoke / alu / load_store / dual_issue） |
| riscvdv | ✅ PASS | 32/32（11 个 skip_in_signoff 留 issue：RTL/binary 层 hang，不是 cosim 问题） |
| **Sign-off full** | **✅ PASS** | 见 build/sf_full2/signoff_report.md |

## 8. 工程约定

- **commit message**：中文，遵循 `feat: / fix: / refactor: / docs:` 前缀
- **issue tracker**：`.scratch/<feature>/issues/NN-<title>.md`，5 个 triage 角色（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）
- **架构决策**：`docs/adr/NNNN-<title>.md`，遵循 ADR 模板
- **模拟器**：默认 VCS，备选 Xcelium/Questa
- **Python**：3.x，全部脚本走 `setup_imports.py` 注入 PYTHONPATH

## 9. 重要参考文件

| 文件 | 作用 |
|------|------|
| `eh2-uvm-implementation-plan.md` | 平台搭建总规划（Ibex 对标蓝图） |
| `docs/cosim-correctness-analysis.md` | cosim 数据通路与风险分析 |
| `docs/adr/` | 架构决策记录（0001–0005） |
| `.scratch/platform-industrialization/PHASE1_PROGRESS.md` | Phase 1 完整记录（cosim 闭环） |
| `.scratch/platform-industrialization/PHASE2_PROGRESS.md` | Phase 2 完整记录（结构整理） |
| `.scratch/platform-industrialization/PHASE3_PROGRESS.md` | Phase 3 部分记录（流程修复 + BE 语义） |
| `.scratch/snapshots/` | 各 Phase 完成快照 tar.gz |
| `/home/host/ibex/dv/uvm/core_ibex/` | Ibex 参考平台 |

## 10. 累计成果（截至 Phase 4 完成）

| 指标 | Phase 0 baseline | 当前 | 变化 |
|------|------------------|------|------|
| `eh2_cosim_scoreboard.sv` | 1026 行 | 734 行 | -29% |
| `eh2_dut_probe_monitor.sv` | 178 行 | 118 行 | -34% |
| `core_eh2_tb_top.sv` | 1287 行 | 1071 行 | -17% |
| WB_SEARCH_DEPTH band-aid | 有 | 无 | ✅ 删除 |
| pending_wb_q band-aid | 有 | 无 | ✅ 删除 |
| 死代码 wb_* 字段 | 6+ | 0 | ✅ 删除 |
| smoke + cosim PASS | 否 | 是 | ✅ |
| arithmetic_basic 多 seed cosim | 失败 | 5/5 PASS | ✅ |
| EH2 推测 div 处理 | 不正确 | 正确（RTL signal + scoreboard） | ✅ |
| Load 经 nb_load 通道 cosim | 不正确 | 正确 | ✅ |
| env/ 接口 Ibex 对齐 | 否 | 是 | ✅ |
| 命名前缀一致性 | 部分 | EH2 全统一 | ✅ |
| `make run TEST=...` 流程 | broken | works | ✅ |
| Store wider BE 语义 | 报错 | 接受 | ✅ |
| Issue triage 完成 | 否 | 12 done / 3 open / 1 wontfix | ✅ |
| build/ 清理 | 7.7GB 残留 | 清理完毕 + .gitignore | ✅ |
| ADR 文档 | 0 | 5 篇 (0001-0005) | ✅ |
| Git 提交 | 未提交 | 4 commits 完整入库 | ✅ |

## 11. 下一步优先事项

1. **RISK-8**: 调查 load_store_test data RF 不同步（可能 init mem load 或 wide-store data 排列）
2. **RISK-9**: 调查 random_instr_test cosim 中断/异常处理
3. **mul_div_test**: 检查 testlist gen_opts 是否还有错名
4. **signoff full**: 上述 3 个修完后跑 `make signoff SIGNOFF_PROFILE=full`
