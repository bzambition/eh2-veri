# Issue: dv/formal 形式验证桥接

Status: ready-for-agent
Milestone: Phase 5
Type: AFK / multi-session
Priority: P3

## What

无 `dv/formal/` 目录。EH2 RTL 的安全关键属性（PMP 隔离、debug
mode 出入、CSR WARL）目前只通过 UVM 随机覆盖率验证，**没有 formal
proof**。

## Why

工业级签发常需要 formal sign-off 作为补充（特别是安全敏感模块）。
Ibex 在 `dv/formal/` 下已有 SVA bridge + Symbiyosys flow。

## Acceptance

- [ ] `dv/formal/` 顶层目录建立
- [ ] 至少 3 条 SVA 验证 PMP 区域隔离（无 越权 RD/WR）
- [ ] Symbiyosys / JasperGold 任一支持的脚本能跑通至少 1 个 cover
- [ ] `make formal` 顶层 target 触发流程

## References

- Ibex `/home/host/ibex/dv/formal/` — formal flow 模板
- EH2 PMP RTL: `rtl/design/lsu/eh2_lsu_pmp.sv`
- ADR：待写（formal 与 UVM 责任边界）

## Estimate

5-10 days. Requires Symbiyosys or JasperGold license + RTL property
authoring expertise.
