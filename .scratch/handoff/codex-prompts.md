# Codex 任务派发包 — 后续 A–I 工作分工

**版本**：2026-05-07  
**作者**：Claude（基于会话评估）+ 用户  
**用法**：每个 §"任务卡 N" 是 self-contained prompt，可直接复制给 codex（推荐用 codex CLI 交互式或 web）。每张卡都包含：背景、做什么、acceptance、stop conditions、完成后回报格式。

---

## 顶层分工原则（再确认一次）

| 类别 | 谁主导 | 卡号 |
|------|--------|------|
| **codex 独立干**（边界清楚、风险低、可机械验收） | codex | 1, 2, 3, 6, 8, 9 |
| **codex 干 + Claude/人 review**（动核心代码或需技术取舍） | codex 写 → 人审 | 4, 5, 7, 10 |
| **必须人主导**（架构决策、技术路线选择） | 人（参考 Claude 建议） | 11, 12 |
| **不在本派发包内**（需要先做决策） | — | RVFI lockstep / RISCOF 认证 / multi-hart cosim |

**通用纪律**（每张卡的隐含前提，不必在 prompt 里重复）：

1. 仓库根：`/home/host/eh2-veri`
2. 重要事实：仓库领域语境在 `CONTEXT.md`，工程化阶段记录在 `.scratch/platform-industrialization/PHASE*_PROGRESS.md`，sign-off 证据在 `build/sf_full2/`，issue 跟踪在 `.scratch/<feature>/issues/`
3. **任何让既有 PASS bank（`build/sf_full2/signoff_status.json` 32/32）出现 mismatch_count > 0 的改动立即停下回退**，不准用 waiver 绕过
4. commit message 用中文 `feat: / fix: / refactor: / docs: / chore:` 前缀
5. 每个 commit 落地前必须 `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 跑一次回归
6. 不动 EH2 RTL（`rtl/design/`）—— fixup 永远只在 cosim/UVM 一侧；唯一例外是 issue 11 Phase 1 已经改过的 RTL trace 信号，那部分已稳定
7. 任何无法在仓库内确认的事实，明确写 "UNKNOWN: 需要 xxx 才能判断"，不要编造

---

# 任务卡 1（A）— 文档持续维护

**难度**：⭐ 低  
**主导**：codex  
**预估 token**：~50K  
**预估墙钟**：30 分钟

## Prompt（直接复制）

```
你是 EH2 验证平台（/home/host/eh2-veri）的文档维护负责人。本任务只动文档，不动 RTL/DV 代码、不动 testlist、不跑仿真。

任务：把以下三件事一次性做完。

1. 同步 docs/sphinx_cn/ 与当前平台状态
   - 读 CONTEXT.md（截至 2026-05-07，sign-off full PASS）
   - 读 build/sf_full2/signoff_report.md 与 signoff_status.json（最新签发证据）
   - 读 .scratch/platform-industrialization/PHASE3_PROGRESS.md / PHASE3_SWEEP_PROGRESS.md
   - 把 Phase 1–5 的成果落地到 docs/sphinx_cn/source/ 下对应章节，重点更新：
     * sign-off 当前结果表（32/32 PASS, 4 stage）
     * cosim:disabled 名单（从 signoff_report.md 的 cosim_disabled_tests 段落直接抓 34 项）
     * RISK-1/9/10/11 当前状态（OPEN，分别对应 issue 14/11/12/13）
   - 不要发明新章节；改既有章节即可

2. 生成或刷新 docs/build_manual_pdf.sh 能用的中文手册 PDF
   - 检查 docs/build_manual_pdf.sh 是否能跑通；不能则修;环境原因导致我们就不再本地生成了，可以不生成
   - 跑出 PDF 后归档到 docs/sphinx_cn/_build/manual_cn.pdf
   - 在 README.md 顶部 "Quick start" 之前加一行链接指向该 PDF

3. 提交一个 commit
   - commit message：`docs: 同步 Phase 5 sign-off 状态到中文手册`
   - 仅 git add docs/ README.md；不要 add 任何其它路径
   - 不要 push

完成后用一段话回报：
- 改了哪几个文件（带相对路径）
- PDF 大小与页数
- 是否成功 commit（给 commit hash）
- 任何被你跳过或标 UNKNOWN 的事

Stop conditions（任意命中立即停下并回报）：
- docs/build_manual_pdf.sh 跑出 LaTeX/Sphinx 错误
- 发现 docs 与 RTL/DV 冲突（应该不会有，本卡只动文档）
- git diff 显示有 docs/ 之外的文件被改
```

## Claude 验收要点

- diff 是否真的只在 docs/ + README.md
- 中文术语对齐 CONTEXT.md（cosim / scoreboard / writeback 等）
- PDF 能打开

---

# 任务卡 2（B）— 重跑 sign-off 并归档证据

**难度**：⭐ 低  
**主导**：codex  
**预估 token**：~30K  
**预估墙钟**：~5 分钟仿真 + 几分钟整理

## Prompt（直接复制）

```
你是 EH2 验证平台的回归运行人员。任务：跑一次完整 sign-off，归档为新的"当前证据"目录。

步骤：

1. 跑回归
   cd /home/host/eh2-veri
   source env.sh   # 如不存在则跳过
   make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_current
   预期 wall time ~3 分钟（参考 build/sf_full2/ 历史值 165s）

2. 验证产物
   - build/sf_current/signoff_status.json 顶层 status 必须是 "PASS"
   - 4 个 stage 全 PASS：smoke 1/1, directed 3/3, cosim 4/4, riscvdv 32/32
   - 任何一个 stage 不是 PASS 立即停下回报，不许再改任何代码

3. 比对前一次
   - diff build/sf_current/signoff_status.json build/sf_full2/signoff_status.json
   - 重点看：cosim_disabled_tests 列表是否变化、stage 通过数是否变化
   - 把 diff 摘要（不要全文）写到 .scratch/handoff/signoff-current-vs-sf_full2.md

4. 不要 commit。这次只是重跑证据，不改任何代码或 testlist。

完成后回报：
- build/sf_current/signoff_report.md 的 Status 行原文
- diff 摘要的前 30 行
- 总 wall time

Stop conditions：
- status != PASS
- 任何 stage 失败
- 发现 build/sf_current/ 已存在且非空（先 ls 确认）
```

## Claude 验收要点

- json 顶层 status=PASS
- 与 sf_full2 的差异是否合理（cosim_disabled_tests 应一致，34 项）

---

# 任务卡 3（C）— 扩展 directed 测试库

**难度**：⭐⭐ 中低  
**主导**：codex  
**预估 token**：~100K  
**预估墙钟**：1–2 小时

## Prompt（直接复制）

```
你是 EH2 验证平台的 directed test 编写者。任务：在 dv/uvm/core_eh2/directed_tests/ 下加 5 个新 directed test，把 directed stage 从 3 个扩到 8 个。

设计目标（按重要性排序）：

1. directed_irq_basic.S
   - 触发一次 timer interrupt，trap handler 写 mtvec/mepc，正常返回
   - cosim 默认开启（不要 disabled）

2. directed_pmp_smoke.S
   - 配置一组 PMP region，触发一次访问越界异常
   - cosim 默认开启

3. directed_csr_warl.S
   - 写 mscause / mrac / mfdc 三个 EH2 自定义 CSR
   - 读回校验 WARL 行为
   - cosim 默认禁用（cosim: disabled）—— RISK-1 未闭合时 CSR 类不开 cosim

4. directed_double_issue_hazard.S
   - 构造 i0/i1 同周期的 RAW/WAR/WAW hazard 各两个
   - 验证写回顺序符合 trace_pkt 的 program order
   - cosim 默认开启

5. directed_nb_load_chain.S
   - 三条非阻塞 load 连续发射，最后用结果做 branch
   - 验证 RISK-5（NB-load wb 跨 slot）不复现
   - cosim 默认开启

每个 .S 必须：
- 编译通过（make directed_compile 或参考 directed_alu 的 makefile 规则）
- 至少有一处 mailbox PASS（store 0xFF 到 0xD0580000）
- 不要让 sim 跑超过 100K cycles（用 +max_cycles=100000）
- 加入 dv/uvm/core_eh2/directed_tests/directed_testlist.yaml

参考已有的：dv/uvm/core_eh2/directed_tests/directed_alu.S（最简单的模板）和 directed_load_store.S。

验证：
   make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_directed_expand
预期：directed stage 从 3/3 升到 8/8 PASS，cosim/riscvdv 不变。

提交：
- commit message：`feat: 新增 5 个 directed test，covering IRQ/PMP/CSR/hazard/NB-load`
- 仅 add：dv/uvm/core_eh2/directed_tests/directed_*.S 与 directed_testlist.yaml
- 不要 add build/

Stop conditions：
- 任何一个 .S 编译失败 —— 别绕过，停下来报告原始 GCC 错���
- directed stage 任意 case mismatch_count > 0 —— 立即回退该 .S
- 既有 cosim/riscvdv stage 出现新的失败 —— 立即停下，重写该 .S 加 cosim:disabled

完成后回报：
- 5 个 .S 的相对路径与各自字节数
- sign-off 8/8 directed 的 status 行
- commit hash
```

## Claude 验收要点

- 是否真的 8/8 directed PASS
- 5 个测试覆盖说明（IRQ/PMP/CSR/hazard/NB-load）是否名实相符
- CSR 那个是不是确实标了 cosim:disabled（避免提前踩 RISK-1）

---

# 任务卡 4（D-12）— bitmanip cosim 真机现场调研 + 修复

**难度**：⭐⭐⭐ 中（已有 RECON，但根因 UNKNOWN）  
**主导**：codex 写 → Claude/人 审 → 人决定 commit  
**预估 token**：~200K（包含真跑仿真）  
**预估墙钟**：30 分钟–1 小时

## 背景上下文（必须先看）

`.scratch/cosim-correctness/issue-12-bitmanip/RECON.md` 已经由 codex 做过只读调研，证伪了原 issue 假设：
- Spike 实际已链入 Zba/Zbb/Zbc/Zbs（`libcosim.so` 含 `rv32i_andn/sh1add/clmul/bclr` 符号）
- UVM 路径 `core_eh2_base_test.sv:196-198` 已传 `rv32imac_zba_zbb_zbc_zbs`
- 真正根因 UNKNOWN，要看真机现场

## Prompt（直接复制）

```
你是 EH2 验证平台 issue 12（bitmanip cosim）的修复负责人。先读以下两份文件：

- .scratch/cosim-correctness/issue-12-bitmanip/RECON.md（前一次只读调研，重要：原 issue 假设已被证伪）
- .scratch/cosim-correctness/issues/12-cosim-bitmanip-zb-extensions.md（原 issue 描述，仅作历史参考）

你的任务分两步，按顺序，每一步走完都暂停回报。

—— 第 1 步：dry-run 取现场（必做） ——

跑一次 cosim-enabled 的 bitmanip 单 seed run：

   cd /home/host/eh2-veri
   make compile SIMULATOR=vcs   # 如未编译
   python3 dv/uvm/core_eh2/scripts/run_regress.py \
     --simulator vcs --seed 42 \
     --output build/issue12_dryrun \
     --testlist dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml \
     --test riscv_bitmanip_test --iterations 1 \
     --sim-opts "+enable_cosim=1 +cosim_fatal_on_mismatch=0 +max_cycles=500000"
     
   # 注意：testlist 里 cosim:disabled 仍在，但用 +enable_cosim=1 sim opt 强行开启

把现场打包到 .scratch/cosim-correctness/issue-12-bitmanip/DRYRUN.md，必须包含：

1. 退出原因（PASS / mismatch / cycle_timeout / hang / vcs error）—— 给 sim log 行号
2. 如果 mismatch：
   - 第一次 mismatch 的 PC + RTL rd value + Spike rd value + insn disasm
   - 出错前 10 条已成功比对的指令
   - mismatch 类型分布（GPR / mem / mcause / 其它）
3. 如果 timeout/hang：
   - 最后 100 条 trace 的 PC 走向（是否在某段循环卡住）
   - 是否触发了 illegal-instr exception 但没正确处理
4. cosim init log 中实际生效的 ISA 字符串（grep "isa="）
5. 一句话根因假设

—— 第 2 步：根据现场决定下一步（暂停回报，等人指示） ——

不要在没有人确认的情况下进入第 2 步。

第 1 步完成后，给出三选一推荐：

A. 修 spike_cosim 端语义不一致（具体哪个 opcode）
B. 修 trace_monitor 过滤规则（仅当某 opcode 在 EH2 是 illegal 但 Spike 是 legal）
C. 修 testlist 的 +max_cycles / generator 约束（如果是测试本身行为而非 cosim）

每个推荐给出：要改的具体文件 + 行号 + 预估改动量 + 风险。

Stop conditions（第 1 步）：
- make compile 失败 —— 停下报错，不要 force rebuild
- run_regress.py 报参数错误 —— 停下回报，不要瞎试参数
- 编译/仿真超过 30 分钟还没出结果 —— 停下回报，可能 license 队列
- 现有 build/sf_full2/ 被任何方式破坏 —— 立即停下

第 2 步：在人没明确说"进入第 2 步"前，绝不动代码、不创建 commit。
```

## Claude 验收要点（第 1 步交还时）

- DRYRUN.md 必须有第一次 mismatch 的具体证据，否则要求 codex 补充
- 三选一推荐的"具体文件 + 行号"是不是真在那里
- 根因假设是否能解释 ALL 观测（特别是为什么之前就被标 cosim:disabled）

## 人决策点

第 2 步走 A/B/C 哪条，由人定（Claude 可以提建议，但不替你拍）。

---

# 任务卡 5（D-14）— EH2 自定义 CSR WARL 表抽取（**只产出表，不动代码**）

**难度**：⭐⭐ 中  
**主导**：codex 抽 → Claude/人 审表 → 人决定后续  
**预估 token**：~150K  
**预估墙钟**：30 分钟

## 为什么先抽表不写 fixup

issue 14 真正的瓶颈是"WARL 行为表"——只有这张表 review 过了，后续 spike fixup hook 才有意义。先单独把表抽出来交给人审。

## Prompt（直接复制）

```
你是 EH2 验证平台 issue 14（自定义 CSR WARL fixup）的前置调研员。本卡只做"抽 WARL 表"，不写 spike fixup hook、不动 testlist、不跑仿真。

任务：从 EH2 RTL 中抽出 18+ 个自定义 CSR 的 WARL 行为表，输出到一份 markdown。

参考输入：
- 主要源：rtl/design/dec/eh2_dec_decode_ctl.sv（CSR 写路径与 mask 在这里）
- 次要源：rtl/design/include/eh2_def.sv（CSR 字段定义）
- 现有部分缓解：dv/cosim/eh2_csr_setup.cc（已有 28 个 set_csr 静态注册可作起点）
- CONTEXT.md §6 RISK-1 列出当前 OPEN 状态

输出：.scratch/cosim-correctness/issue-14-csr/WARL_TABLE.md

每个 CSR 列：

| 字段 | 内容 |
|------|------|
| CSR 名 | 如 mscause |
| 地址 | 如 0x7FF |
| reset value | 32-bit hex |
| writable mask | 32-bit hex（哪些 bit 写时被保留） |
| WARL 行为 | "raw" / "read-only" / "specific values only" / "其它" |
| 特殊读取 fixup | 是否读时跟写入值不同 |
| RTL 引用 | 文件:行号 |
| 当前 set_csr 状态 | 已注册 / 未注册 |
| 优先级 | P0/P1/P2（建议先修哪些） |

至少覆盖：mscause, mrac, mfdc, meivt, meipt, mip, mie, meihap, dmst, dicawics, dicad0, dicad0h, dicad1, dicago, mcgc, mfdht, mfdhs, micect, mvendorid, marchid（如 EH2 重定义）

至少给出 P0（建议先做）的 5 个 CSR：依据是"在 testlist 中 cosim:disabled 的 CSR/PMP 类 test 引用最多"。

Stop conditions：
- 找不到某个 CSR 的写 mask —— 标 UNKNOWN，不要编造
- RTL 中有 generate-block 条件 mask（按配置不同）—— 列出所有分支
- 任何对 dv/ rtl/ vendor/ 的修改 —— 不允许，本卡只输出 markdown

完成后回报：
- WARL_TABLE.md 路径
- 表中 CSR 总数
- P0 候选名单
- 任何 UNKNOWN 项
```

## Claude/人 验收要点

- WARL 表是否覆盖 CONTEXT.md §6 RISK-1 提到的 18+ 个
- mask hex 与 RTL 行号能不能对得上（抽样 3 个验证）
- P0 候选合理性（应优先 PMP 与 mscause/mrac 这种被 test 大量触发的）

## 人决策点

P0 名单定后，issue 14 的子任务才真正能拆。表本身是后续 fixup commit 的输入。

---

# 任务卡 6（F）— AXI4 active driver（issue 40）

**难度**：⭐⭐ 中（acceptance 边界清楚）  
**主导**：codex  
**预估 token**：~180K  
**预估墙钟**：2–3 小时

## Prompt（直接复制）

```
你是 EH2 验证平台 issue 40 的实现负责人。完整 issue 描述见 .scratch/platform-industrialization/issues/40-axi4-active-driver.md。

核心任务：把 dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv 从 stub 升级为可工作的 active driver，能注入 5% SLVERR/DECERR，触发 EH2 mcause=5/7 trap。

参考：
- Ibex 模板：/home/host/ibex/dv/uvm/core_ibex/common/ibex_mem_intf_agent/ibex_mem_intf_response_driver.sv（同概念实现，照抄结构）
- 现有 stub：dv/uvm/core_eh2/common/axi4_agent/axi4_driver.sv
- 现有 monitor：dv/uvm/core_eh2/common/axi4_agent/axi4_monitor.sv（passive 已工作，本卡不动）
- 现有 slave mem：dv/uvm/core_eh2/common/axi4_agent/axi4_slave_mem.sv（默认 RTL responder，要在 active 模式下让位）
- env_cfg：dv/uvm/core_eh2/env/core_eh2_env_cfg.sv（加 enable_error_inject 等开关）

接收标准（来自 issue 40，不要打折扣）：

- [ ] active driver 子类在 enable_error_inject=1 时**取代** axi4_slave_mem 响应（不是叠加）
- [ ] 新建 directed test：dv/uvm/core_eh2/directed_tests/directed_axi4_error_inject.S + 加入 directed_testlist.yaml，跑通后 DUT 进入 mcause=5（load access fault）或 mcause=7（store access fault）trap handler 然后 PASS
- [ ] 默认 passive 模式下既有 cosim 4/4 + riscvdv 32/32 PASS 不破
- [ ] tb_top 绑定 driver vif；env 连接 sequencer；默认配置 disabled

提交：分两个 commit
- commit A: feat: AXI4 active driver 实现 + env 接线（不加测试，验证既有回归不破）
- commit B: feat: directed_axi4_error_inject 触发 access fault trap

每个 commit 落地前跑：
   make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_axi4_inject_<commitA|B>

Stop conditions：
- driver 与 slave_mem 同时响应同一笔 transaction —— 必须互斥（issue 40 Risk 段已警告）
- error inject 在 init 阶段（boot 早期 load）触发 —— 用 issue 40 建议的 post_initial_pc 窗口
- 既有 32/32 任意 case 出现 mismatch / 新失败 —— 立即回退
- Ibex 参考实现完全 copy 不过来（接口不同）—— 停下报告差异，不要瞎改 EH2 接口

完成后回报：
- 改了哪些文件（带行数 delta）
- 两次 sf 的 status
- mcause=5/7 在 directed_axi4_error_inject 的 sim log 中可见的行号
- commit A/B 的 hash
```

## Claude 验收要点

- driver 与 slave_mem 互斥逻辑（grep enable_error_inject 看是否两边对称 disable）
- mcause trap 真触发了不是仿真 PASS 但实际 trap 没进
- cosim 32/32 不破

---

# 任务卡 7（H）— formal bridge 骨架（issue 42，仅骨架）

**难度**：⭐⭐ 中  
**主导**：codex 搭骨架 → 人决定 SVA 内容  
**预估 token**：~120K  
**预估墙钟**：1–2 小时

## Prompt（直接复制）

```
你是 EH2 验证平台 issue 42（formal bridge）的骨架搭建者。完整 issue 见 .scratch/platform-industrialization/issues/42-formal-bridge.md。

⚠️ 本卡只搭骨架，不写真正的 SVA 属性内容。SVA 设计是人主导的事。

任务：在 dv/formal/ 下建立目录与流程骨架，照抄 Ibex 的 dv/formal/ 模板。

参考：
- Ibex 模板：/home/host/ibex/dv/formal/（完整流程参考）
- EH2 PMP RTL（仅 read 用作骨架占位，不分析）：rtl/design/lsu/eh2_lsu_pmp.sv

骨架要求：

1. dv/formal/ 顶层目录 + README.md（中文，说明这是骨架）
2. dv/formal/Makefile：包含 `make formal`、`make formal_clean` 两个 target，调用 Symbiyosys 或 JasperGold（先用 Symbiyosys，理由：开源）
3. dv/formal/properties/eh2_pmp_pmp.sv：放 3 条**占位** SVA（必须明确写 "// TODO: real property by human"），仅做"PMP region disable 后访问会触发异常"骨架
4. dv/formal/scripts/sby_pmp.sby：Symbiyosys config 文件
5. 顶层 Makefile 加一行 `make formal:` 转发到 dv/formal/Makefile

非目标：
- 不要写真正的 PMP 隔离 SVA —— 留 TODO，由人后续填
- 不要把 dv/formal 接入 sign-off gate —— 留作未来
- 不要修改 RTL 添加 formal-only 信号

接收标准：
- [ ] dv/formal/ 目录建立，5 个文件齐全
- [ ] make formal 在 Symbiyosys 不存在时友好报错（不是 silent fail）
- [ ] make formal 在 Symbiyosys 存在时能跑过至少 1 个 cover（占位 cover 即可：PMP region 被写一次）
- [ ] 既有 sign-off 32/32 不破（本卡不该影响 sign-off）
- [ ] README.md 说明：哪些是 TODO，下一步谁负责

提交：
- commit message：`feat: dv/formal 骨架（Symbiyosys flow + PMP 占位 SVA）`

Stop conditions：
- 系统没有 Symbiyosys 又找不到 JasperGold —— 在 Makefile 里加 detect 后报错即可，不必装
- Ibex 模板某个文件依赖 Ibex-specific 信号 —— 不要照抄那部分，改用 EH2 信号占位
- dv/formal/ 已存在 —— 停下确认是不是已经有人搭过

完成后回报：
- 5 个文件路径
- make formal 在本机的实际表现（PASS / Symbiyosys 不存在）
- README.md 中 TODO 列表的条目数
- commit hash
```

## Claude 验收要点

- 真的是骨架，不是塞了一堆假 SVA
- Symbiyosys detection 工作正确
- README 中 TODO 指向明确

---

# 任务卡 8（I）— issue 归档与 PROGRESS 收尾

**难度**：⭐ 低  
**主导**：codex  
**预估 token**：~30K  
**预估墙钟**：15 分钟

## Prompt（直接复制）

```
你是 EH2 验证平台的 issue 收尾员。任务：把 Phase 5 sign-off PASS 之后还没归档的 issue 标 done，并刷新 PROGRESS。

步骤：

1. 把以下 issue 的 status 改为 done，并在文件底部加 "## 完成证据" 段，引用 build/sf_full2/signoff_status.json：
   - .scratch/platform-industrialization/issues/06-signoff-full-pass.md（acceptance 已满足）

2. 检查以下 issue 是否真的 done（如已 done 不动；如不是则保持原状不动）：
   - 任何 .scratch/cosim-correctness/issues/ 下 status 标 "done" 但没引用证据的，补上证据指针

3. 刷新 .scratch/platform-industrialization/PHASE5_PROGRESS.md（如不存在则创建）：
   - 标题：Phase 5 — Sign-off full PASS
   - 时间：2026-05-07
   - 内容（不要超过 100 行）：
     * sign-off 4 stage 当前结果（引 build/sf_full2/signoff_report.md）
     * 仍 cosim:disabled 的 34 项一句话提及（引 issue 11/12/13/14 作为后续）
     * 已关闭 issue 列表
     * 仍 OPEN 的 issue 列表（11/12/13/14/15/40/41/42 + cosim 03/05）

4. 提交：
   - commit message：`chore: Phase 5 sign-off PASS 后的 issue 归档与 PROGRESS 收尾`
   - 仅 add .scratch/

Stop conditions：
- 任何对 dv/ rtl/ docs/sphinx_cn/ 的修改 —— 不允许
- 发现某 issue 文件 git status 是 modified 却不是你改的 —— 停下回报

完成后回报：
- 改了哪几个 issue 文件（路径列表）
- PHASE5_PROGRESS.md 路径与行数
- commit hash
```

## Claude 验收要点

- diff 只在 .scratch/
- PHASE5_PROGRESS.md 不超 100 行（避免 codex 写散）

---

# 任务卡 9（meta）— D 路线进度跟踪刷新

**难度**：⭐ 低  
**主导**：codex  
**预估 token**：~25K  
**预估墙钟**：10 分钟

## Prompt（直接复制）

```
你是 EH2 验证平台 D 路线（cosim:disabled 清零）的跟踪员。

任务：刷新 .scratch/cosim-correctness/issues/15-cosim-disabled-zero-out-meta.md，把它从"4 个子 issue 都 ready-for-agent"更新到当前真实状态。

步骤：

1. 读这 4 张子 issue 的当前 status 字段：
   - 11-cosim-interrupt-exception-scoreboard.md
   - 12-cosim-bitmanip-zb-extensions.md
   - 13-cosim-atomic-sc-fixup.md
   - 14-cosim-eh2-csr-warl-fixup.md

2. 读以下两份产出（如存在）确认 12/14 的实际进度：
   - .scratch/cosim-correctness/issue-12-bitmanip/RECON.md
   - .scratch/cosim-correctness/issue-12-bitmanip/DRYRUN.md（可能不存在）
   - .scratch/cosim-correctness/issue-14-csr/WARL_TABLE.md（可能不存在）

3. 在 #15 的子 issue 表格上加一列"实际进度"，可选值：
   - 未启动 / 调研中 / 表已抽出待审 / commit A 已合 / commit B 已合 / done

4. 在文件末尾加一段"快照 N — yyyy-mm-dd"，列出当前 4 张子 issue 的实际进度。

5. 提交：
   - commit message：`chore: D 路线 #15 跟踪表刷新`
   - 仅 add .scratch/cosim-correctness/issues/15-*.md

Stop conditions：
- 4 张子 issue 任何一张 file 已被你之外的人 modified —— 停下回报，不动
- 发现某 issue status 与 PROGRESS 文档冲突 —— 停下回报，让人裁决

完成后回报：
- 4 张子 issue 当前实际进度一句话
- commit hash
```

## Claude 验收要点

- 进度状态准确（与会话事实一致）
- 不要让 codex 自己改子 issue 的 status，只能改 #15 的总跟踪表

---

# 任务卡 10（D-11）— 中断/异常 cosim 调研（只调研，不动代码）

**难度**：⭐⭐⭐⭐ 高（最高优先级也最难的卡）  
**主导**：codex 调研 → Claude 审 → 人决定后续  
**预估 token**：~250K  
**预估墙钟**：1 小时

## 为什么先调研不动代码

issue 11 动 scoreboard 主路径，历史踩过 wb_seq / div_cancel 这种坑（PHASE1_PROGRESS 有记录）。**先把现状摸清楚再决定改法**，比让 codex 直接动手安全。

## Prompt（直接复制）

```
你是 EH2 验证平台 issue 11（中断/异常 cosim）的前置调研员。本卡**只调研，不写代码、不动 testlist、不跑仿真、不创建 commit**。

完整 issue 描述：.scratch/cosim-correctness/issues/11-cosim-interrupt-exception-scoreboard.md
背景上下文：CONTEXT.md §6 RISK-9（OPEN），ADR-0001 cosim 契约，PHASE1_PROGRESS.md（历史踩坑记录）

输出：.scratch/cosim-correctness/issue-11-irq-exc/RECON.md

回答（每条带文件路径 + 行号）：

1. **当前 cosim_scoreboard 中"interrupt-only trace item"如何处理**
   - 在 dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv 中找到 trace_pkt.interrupt 的判断分支
   - 当前只 set_mip 还是已经做了别的
   - 是否有 mtvec/mepc/mcause 比对路径

2. **当前 exception trace item 处理**
   - trace_pkt.exception 分支位置
   - 是否调 Spike step
   - mcause/mepc/mtval 当前怎么对（如果有）

3. **interrupt 与 exception 同周期的优先级**
   - RTL：trace_pkt 当 interrupt=1 && exception=0 时，DUT 实际行为（CONTEXT.md §5 第 4 点说"该 PC 处的指令没有执行"，验证这条在 RTL 是否真成立）
   - cosim：当前如何处理这种"指令未退役但 trace_pkt 仍 valid"的情况

4. **现有 disabled 的 10 个测试的失败模式**
   - 在 testlist.yaml 找到 10 个 IRQ/exception 相关 test 的 cosim:disabled 行，列行号
   - 任何一个有过去的失败 log 归档？grep build/ 找已归档失败现场

5. **EH2 自定义中断 CSR**
   - mip / mie / meihap / meivt / meipt 这些 CSR 当前 set_csr 注册情况（dv/cosim/eh2_csr_setup.cc）
   - 哪些 PIC 路径 Spike 不模型（CONTEXT.md §2 提到）

6. **改动风险评估**
   - 历史 PHASE1 改 scoreboard 时哪些 band-aid 删过（grep PHASE1_PROGRESS WB_SEARCH_DEPTH / pending_wb_q）
   - 本次中断/异常路径与那些 band-aid 是否相关
   - 如果改坏了，回归会先在哪个 case 暴露（既有 cosim 4/4 中哪个最敏感）

7. **建议的 commit 拆分**（最小化每次 review 的 surface）
   - commit A：纯加 compare 路径 + UVM_HIGH log，不改 testlist，不破现有 32/32
   - commit B：testlist 解锁某个最简单的 IRQ test（建议 cosim_smoke + 1 个）
   - commit C：解锁剩余 9 个
   - 每个 commit 预估改动行数

8. **最终建议**
   - 是 codex 主导（issue 11 写的"HIGH risk"是不是其实 OK）还是必须人主导
   - 哪些子任务可以先单独抽出来给 codex 做（如 mip CSR 注册）

Stop conditions：
- 任何对 dv/ rtl/ vendor/ 的修改 —— 不允许，本卡只输出 markdown
- 发现 scoreboard 已经有完整的 mcause 比对 —— 停下重新评估 issue 11 假设
- 发现 RTL trace_pkt.interrupt 含义与 CONTEXT.md §5 不一致 —— 停下报告矛盾

完成后回报：
- RECON.md 路径
- 第 8 项的最终建议（一句话）
- 是否建议下一步让 codex 直接动 commit A
```

## Claude 验收要点（最关键的一张卡）

- 第 1–3 项的行号必须真在那里（这关系到改动安全性）
- 第 6 项历史踩坑分析 codex 是否真懂（看它有没有引用具体的 PHASE1 commit）
- 第 8 项建议保守度（这是 HIGH risk 卡，倾向"必须人主导"才是诚实答案）

## 人决策点

读完 RECON 后，决定：
- (a) 直接放 codex 上 commit A（如风险确实低）
- (b) 让 Claude 先把 commit A 的 patch 写出来给 codex 当蓝图
- (c) 暂缓，先做 task 4（D-12 bitmanip）和 task 5（D-14 CSR）

---

# 任务卡 11–12（**不发给 codex，留给人决策**）

## 11. E — 功能覆盖率门（fcov gate）

**为什么不能给 codex 独立干**：bin/cross 的设计是平台架构决策，写错了"看起来像覆盖率但其实没意义"——这种损伤是隐性的，机械验收发现不了。

**建议先做的事**（人主导）：

1. 决定覆盖率目标矩阵：
   - functional：哪些场景要覆盖（dual issue 路径、interrupt nest 深度、PMP region count、CSR write 模式 …）
   - structural：line / cond / fsm / toggle 各定多少阈值
2. 决定哪些已有的 fcov_if（dv/uvm/core_eh2/fcov/）需要扩、哪些重写
3. 决定 sign-off 是否在所有 stage 都加 coverage required，还是只在 weekly 加

定好了再写一张面向 codex 的"机械执行"卡（实现 covergroup + 接 sign-off threshold）。

## 12. G — multi-hart cosim（issue 41）

**为什么不能给 codex**：issue 41 自己写明 "Risk: HIGH (architectural)"。改 spike glue + per-hart scoreboard，需要重新论证 ADR-0001 的 cosim 契约能否扩展到 dual_thread。**这不是 codex 该做的决策**。

**建议先做的事**（人主导）：

1. 写 ADR-0008（草案）：multi-hart cosim 的 trace/probe/scoreboard per-hart 拆分契约
2. 决定 NUM_THREADS=2 cosim 是否仍维持"不动 RTL"的纪律（很可能要破例）
3. 决定 dual_thread profile 是否纳入 sign-off full（current 默认是单 thread）

定好了再分子任务派给 codex（ADR、scoreboard 拆分、testlist dual profile 等可机械执行的部分）。

---

# 派发顺序建议

按 ROI 与风险递增排序，建议这样跑：

1. **任务卡 2（B）** — 最小代价拿到当前证据，5 分钟完事，作为后续所有改动的 baseline
2. **任务卡 8（I）** — 收尾既有 issue，保持仓库整洁
3. **任务卡 1（A）** — 文档同步，30 分钟完事
4. **任务卡 9（meta）** — D 路线跟踪表刷新（10 分钟）
5. **任务卡 3（C）** — directed 测试扩到 8 个（需要真跑仿真，~2h）
6. **任务卡 4（D-12 第 1 步）** — bitmanip dry-run 取现场（~30 分钟），**第 2 步暂停回到人**
7. **任务卡 5（D-14）** — CSR WARL 表抽取（30 分钟，**只产出表**）
8. **任务卡 10（D-11 调研）** — 中断/异常调研（1 小时，**只调研**）
9. 此处人介入：审 4/5/10 三份产出，决定后续怎么动代码
10. **任务卡 6（F）** — AXI4 active driver（独立工作量大但风险低）
11. **任务卡 7（H）** — formal bridge 骨架

E 与 G 留给后续会话。

---

# 单次跑 codex 的最小化指令模板

每张任务卡建议这样发：

```bash
codex -C /home/host/eh2-veri --skip-git-repo-check
# 进入交互模式后粘贴对应任务卡的 Prompt 部分
```

或非交互（适合长任务）：

```bash
codex exec -C /home/host/eh2-veri --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  -o .scratch/handoff/codex-output-task-N.md \
  "$(cat .scratch/handoff/codex-prompts.md | sed -n '/# 任务卡 N/,/^---$/p')"
```

注意：`--dangerously-bypass-approvals-and-sandbox` 在这台机器是必须的（bubblewrap 在 Linux 6.12 user namespace 不可用，前次试跑已踩到）。

---

# 给人的最后提醒

- **不要让 codex 同时跑两张卡**，task 6/7 之外的几乎都改 testlist 或 PROGRESS，并发会冲突
- **每张卡完成后让 codex 回报 commit hash**，你 `git show <hash>` 自己 review 一遍 diff 再做下一张
- **任务卡 4/10 是分两步**，第 1 步完后 codex 必须停下，不要让它越权
- **任务卡 11/12 不要让 codex 去做**，那是你的决策
