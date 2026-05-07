# ADR-0003: NUM_THREADS=1 cosim 边界

- 状态：Accepted（短期），考虑 Phase 5 解锁
- 日期：2026-05-04
- 相关：docs/cosim-correctness-analysis.md §9

## 上下文

EH2 可配置 NUM_THREADS=1 或 NUM_THREADS=2（双硬件线程，每个 hart 独立 PC/regfile/CSR）。

Spike 的 `processor_t` 实例只能模型一个 hart。`SpikeCosim` 当前只创建一个 processor，无法同时跟踪两个 hart。

## 决策

**短期：cosim 仅支持 NUM_THREADS=1。**

- `eh2_configs.yaml` 的 `dual_thread` profile 必须 `+disable_cosim=1`
- testlist 里多线程 test 必须 `cosim: disabled`
- signoff full 在 dual_thread 配置下不要求 cosim stage

## 备选方案（Phase 5 评估）

| 方案 | 描述 | 工作量 |
|------|------|-------|
| A. 多 hart Spike | SpikeCosim 创建两个 processor_t，按 thread_id 路由 trace item | 5–10 天 |
| B. 双实例 SpikeCosim | 两套 SpikeCosim 实例并行，trace_monitor 按 tid 分流 | 3–5 天 |
| C. 持续禁用 | 接受限制，dual_thread 仅靠 mailbox + 自检 cooperative test | 0 天 |

## 当前选择：C（持续禁用）

dual_thread 是次要配置，工业级签发仅强制 NUM_THREADS=1 cosim 通过即可。

## 后果

- ✅ 简化短期工作量
- ❌ dual_thread 验证完整性弱于 single_thread（依赖 self-check assembly tests）

## 升级触发条件

下述任一发生，启动 Phase 5 多 hart cosim：
- 真实部署需要 dual_thread 量产
- single_thread 已通过 sign-off
- 出现 dual_thread 特有 bug 通过其它手段无法定位
