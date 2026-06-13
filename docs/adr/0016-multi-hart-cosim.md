# ADR-0008: NUM_THREADS=2 Co-simulation Support

- 状态：Accepted
- 日期：2026-05-08
- 相关：ADR-0003（superseded）

## 上下文

ADR-0003 记录了 NUM_THREADS=2 cosim 不可行的限制。随着平台成熟，需要支持 EH2 的双线程 cosim。

## 决策

1. SpikeCosim 创建 2 个 processor_t 实例（当 num_threads==2）
2. 每个 hart 独立维护：processor state、pending_dside_accesses、mip/prev_mip
3. DPI 接口通过 thread_id 参数路由到对应 hart
4. scoreboard 按 trace_seq_item.thread_id 路由到对应比对路径
5. 每个 hart 独立维护 pending_trace_q 和 async_wb_q

## 后果

### 正面
- 双线程配置有完整 cosim 闭环
- 与单线程路径共用同一 scoreboard 逻辑

### 负面
- Spike 内存仍然共享（两个 hart 看同一个地址空间）
- PIC 中断仲裁 Spike 不模型（每 hart 独立 set_mip）
