# EH2 验证平台工业级整改 — 总览

**Feature 目标**：把 EH2 UVM 验证平台从"结构七成对齐 Ibex、关键闭环未收敛"提升到"工业级签发就绪"，对标 Ibex `dv/uvm/core_ibex/` 的成熟度。

**对标基准**：`/home/host/ibex/dv/uvm/core_ibex/`
**RTL DUT**：`/home/host/eh2-veri/rtl/design/`
**当前 sign-off 状态**：smoke + directed PASS；cosim + riscvdv 未通过（BLOCKING）

---

## 5 个 Phase 一览

| Phase | 主题 | 优先级 | 工时（开发者） | 关键产出 |
|-------|------|--------|--------------|---------|
| **1** | cosim 闭环修复 | P0 | 2–3 天 | scoreboard 1026→~500 行；signoff full PASS |
| **2** | 结构整理（去耦合） | P1 | 2–3 天 | env/ 接口归位；TB top 1287→~400 行；agent 前缀统一 |
| **3** | 覆盖率与 CSR 补齐 | P1 | 3–5 天 | EH2 18+ CSR fixup；cosim disabled 测试归 0；新 fcov |
| **4** | 文档与工程化 | P2 | 1–2 天 | CONTEXT.md / ADR / issue triage / build 清理 |
| **5** | 工业级特性 | P3 | 5–10 天 | 多 hart cosim / formal / CI gate |

> **节奏约定**：每个 Phase 完成后停下汇报，等用户确认再继续下一 Phase。

---

## Phase 1 issues（P0，已就绪）

| # | 文件 | 描述 |
|---|------|------|
| 01 | `01-rtl-add-rvfi-equivalent.md` | RTL trace 包加 rd_addr/rd_wdata 字段 |
| 02 | `02-trace-monitor-sample-wb.md` | trace_monitor 直接采样 wb 数据 |
| 03 | `03-scoreboard-simplify.md` | scoreboard 删除 pending_wb_q 与 wb_search_depth |
| 04 | `04-probe-monitor-keep-async.md` | probe_monitor 仅保留 nb_load/div 异步通道 |
| 05 | `05-testlist-enable-cosim.md` | testlist 把 cosim:disabled 改回 enabled |
| 06 | `06-signoff-full-pass.md` | 跑通 signoff full profile |

## Phase 2 issues（P1）

| # | 描述 |
|---|------|
| 10 | env/ 接口归位（csr_if/dut_probe_if/instr_monitor_if 移到 env/） |
| 11 | tb_top 拆分（信号束抽成 *_intf.sv） |
| 12 | agent 前缀统一为 `eh2_*` |
| 13 | scoreboard 拆分（wb_correlator / mem_correlator / spike_notify 子模块） |

## Phase 3 issues（P1）

| # | 描述 |
|---|------|
| 20 | Spike fixup_csr 补 EH2 自定义 CSR（mscause/mrac/mfdc/...） |
| 21 | testlist 9 个 disabled cosim 全部恢复 |
| 22 | 新增 eh2_mrac_fcov_if.sv（区域访问控制覆盖率） |
| 23 | 新增 eh2_dual_issue_fcov_if.sv（双发射组合矩阵） |
| 24 | 新增 eh2_pic_fcov_if.sv（PIC 中断覆盖率） |

## Phase 4 issues（P2）

| # | 描述 |
|---|------|
| 30 | CONTEXT.md（已完成 ✅） |
| 31 | docs/adr/ 0001–0004（已完成 ✅） |
| 32 | build/ 目录清理 |
| 33 | 全部 issue 走完 triage 状态机 |

## Phase 5 issues（P3，可选）

| # | 描述 |
|---|------|
| 40 | 多 hart SpikeCosim |
| 41 | dv/formal/ 形式验证桥接 |
| 42 | CI gate（GitHub Actions / Jenkinsfile） |
| 43 | AXI4 active driver（错误注入） |

---

## 当前进展（更新于 2026-05-07，Phase 3 sweep 完成）

- ✅ Phase 1 cosim 闭环完成（smoke + arithmetic 100% PASS）
- ✅ Phase 2 结构整理完成（env 归位 / 命名统一 / TB 拆分 / scoreboard 模块化）
- ✅ Phase 3 完成（cosim-enabled testlist 9/9 PASS：arith/rand_jump/load_store/
      unaligned_ls/mul_div/dual_issue/exception/invalid_csr/fetch_en_chk）
  - 修了 8 个 EH2 directed stream 的结构性 bug（gen_instr → post_randomize 桥接）
  - 修了 testlist 错名（riscv_mul_instr_stream / riscv_branch_instr 等）
  - 修了 imm_str 缺失、SLLI shamt、atomic BNE 等多处 stream 编码 bug
- ✅ Phase 4 文档对齐（CONTEXT.md / ADR 0001-0005 / PHASE3_SWEEP_PROGRESS.md）
- ⚠️ Phase 3 cosim-disabled 留 issue：random_instr (+enable_interrupt) /
      bitmanip (zba/zbb illegal-instr 速率) / amo (SC.W 写回与 Spike 分歧)
- ⬜ Phase 5 未开始（多 hart cosim / formal / CI gate）

## Issue 状态统计（2026-05-07 sweep 后）

| 状态 | 数量 | 说明 |
|------|------|------|
| done | 13 | Phase 1-3 已完成的 issue，含本次 8 个 stream 修复 |
| ready-for-agent | 3 | random_instr 中断 / bitmanip 异常路径 / amo SC.W |
| wontfix | 1 | NUM_THREADS=2 限制（Phase 5 scope） |

## 进入下一会话的 checklist

1. 阅读 `CONTEXT.md` 了解领域语言和当前状态
2. 看 Phase 3 sweep 结果：`PHASE3_SWEEP_PROGRESS.md`（cosim-enabled 9/9 PASS 已达成）
3. 选择进路：
   - 跑通 signoff full profile（验证 cosim stage 真的 PASS）
   - 修 cosim:disabled 留 issue（interrupt/bitmanip/amo）
   - 进入 Phase 5：CI gate / 多 hart cosim / formal / AXI4 active
