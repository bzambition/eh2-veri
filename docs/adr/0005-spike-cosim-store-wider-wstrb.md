# ADR-0005: Spike-cosim 接受 EH2 store wider WSTRB

- 状态：Accepted（Phase 3 实施）
- 日期：2026-05-06

## 上下文

EH2 LSU 对子字节存储（SB / SH）在 AXI4 输出时**不是**只 set 对应字节的 WSTRB
位，而是：
- 把整个 4 字节 word 的 WSTRB 都置 1（`4'b1111`）
- 通过内部 read-modify-write 把"非目标字节"填回原 mem 内容
- 输出 64-bit beat data 时只有目标字节是新值

这是一种合法的硬件设计——AXI4 协议允许，整 word write 不影响其它字节内容
（因为 RMW 已经把它们设回旧值）。**但 cosim 默认假设 store 的 WSTRB 严格
等于 ISA 期望的 byte mask。**

具体表现：执行 `sb a2,-217(t0)`（store byte），DUT 在 AXI4 上发出
`wstrb=4'b1111`，cosim 把它传给 spike 的 `mmio_store`，spike 的检查代码报错：

```
Cosim mismatch: DUT generated store at address 81000844
                with BE f but BE 1 was expected
```

## 决策

修改 `dv/cosim/spike_cosim.cc:check_mem_access` 的 store-side BE 检查，
**采用与 load-side 一致的"超集判断"语义**：

```cpp
// 之前（store 严格相等）：
if (store && expected_be != top_pending_access_info.be) {
  // error: BE mismatch
}

// 现在（store 超集容忍）：
if (store && ((expected_be & ~top_pending_access_info.be) != 0)) {
  // error: ISA expected bytes not covered by DUT BE
}
```

也就是说：只要 DUT BE 包含 ISA 期望的 byte mask，就接受。多出的字节认为是
EH2 LSU 的内部 RMW 行为，不影响架构正确性（因为它们的内容应当与原 mem
字节相同）。

## 后果

### 正面
- EH2 SB / SH 不再误报 BE mismatch
- spike_cosim 的 BE 检查在 store 和 load 上**对称**（之前 load 已经容忍超集，
  store 不容忍 — 不一致）
- 工业级 cosim 接受 RTL 真实 AXI 行为

### 负面
- **失去对"DUT 多写额外字节但内容错"的检测能力**——但 data 检查仍然工作（
  `data & expected_be_bits` mask 后比对），所以 ISA 期望字节的内容仍然严格
  验证，只是"额外字节"的内容不验证
- 假设：EH2 RTL 的 RMW 不破坏额外字节（如果 RTL 有 bug 让额外字节被错误覆写，
  cosim 检测不到——这是已知的 trade-off）

## 备选方案

| 方案 | 描述 | 评估 |
|------|------|------|
| A. cosim_scoreboard 端裁剪 strb | 收到 wide-BE 后裁到 ISA 期望范围 | 在 SV 端做更复杂；data 同样需要���剪 |
| **B. spike_cosim 端容忍**（本 ADR） | C++ 端单点修改，对称化 load/store 处理 | **选定** |
| C. 加一个 cosim_be_strict 配置位 | 让用户选 strict / lax | 暴露不必要的复杂度 |

## 验证

修复前：`load_store_test seed=1` 第一个 SB 触发 BE mismatch error。
修复后：BE 检查通过（但暴露了下一层 data RF 不同步问题，那是独立 bug）。

Phase 1+2 闭环未受影响：smoke + cosim PASS, arithmetic_basic 100% PASS。

## 相关链接

- `dv/cosim/spike_cosim.cc:980-1001`（修改点）
- `docs/cosim-correctness-analysis.md`（RISK-2 / RISK-2b）
- `.scratch/platform-industrialization/PHASE3_PROGRESS.md`
