# ADR-0002: AXI4 总线 passive monitoring + slave behavioral mem

- 状态：Accepted
- 日期：2026-05-03

## 上下文

EH2 有 4 个 AXI4 端口（IFU 取指、LSU 读写、SB 调试系统总线、DMA），数据宽度 64-bit。Ibex 用简单 req/gnt/rvalid，Ibex 的 mem_intf_response_agent 会主动驱动响应。

## 决策

- **AXI4 agent 设为 passive 模式**：仅监视器，不驱动
- **TB top 实例化 4 个 `axi4_slave_mem`** 行为级模型（独立内存区，地址空间预映射）
- monitor 把 AW/AR 与 W/R/B 通道按事务关联，发出 `axi4_seq_item`（包含 burst 全部 beats）
- LSU 通道挂到 cosim agent 的 `dmem_port`，给 Spike 通知内存访问

## 后果

### 正面
- 行为级 mem 简化 TB（不需要建模 cache 一致性）
- passive agent 跟真实 SoC 解耦——AXI 主控由 DUT 完全决定
- 64-bit beat 数据完整保留（cosim 通知时 split 成两个 32-bit 调用）

### 负面
- 不能注入 AXI 错误响应、退避（Ibex `mem_intf_response_seq_lib` 能注入 OOB / SLVERR / DECERR）
- 没有 AXI 协议合规检查 assertion
- 不支持 AXI lock / exclusive access 验证

## 待办

- Phase 5：增加 active driver，支持错误注入与协议测试
- Phase 5：增加 AXI 协议合规 assertion bind

## 相关链接

- `dv/uvm/core_eh2/common/axi4_agent/`
- `dv/uvm/core_eh2/tb/core_eh2_tb_top.sv`（4 × axi4_slave_mem 实例化）
