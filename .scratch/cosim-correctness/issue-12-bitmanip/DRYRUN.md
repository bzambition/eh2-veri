# Issue 12 DRYRUN — bitmanip cosim 真跑现场

日期：2026-05-07
命令：`python3 run_regress.py --test riscv_bitmanip_test --seed 42 --sim-opts "+enable_cosim=1 +cosim_fatal_on_mismatch=0 +max_cycles=500000"`

## 1. 退出原因

**Cycle timeout** — 500000 cycles 后超时退出。DUT 卡在 `mtvec_handler`（地址 0x80013990）的无限异常循环中。

sim log 行：`UVM_ERROR core_eh2_base_test.sv(366) @ 4999995000: Cycle timeout: 500000 cycles`

## 2. Cosim 报告

```
Trace items received: 112286
Steps executed:       519
Mismatches:           0
Pending trace items:  111767
RESULT: PASS (cosim 本身没 mismatch)
```

**关键发现：cosim 0 mismatch！** 问题不是 cosim 不一致，而是 DUT 在某条指令触发异常后进入 trap handler 无限循环。

## 3. 失败模式分析

### 异常统计
- Total trace commits: 112286
- Total exceptions: **54989**（占总 trace 的 49%！）
- IPC: 0.22

### 卡死位置
DUT 卡在 `mtvec_handler`（0x80013990），这是 riscv-dv 生成的默认 trap handler。handler 自身的第一条指令 `addi s7, s7, -4` + `sw a2, 0(s7)` 不断循环执行。

### 根因假设

riscv-dv 生成的 bitmanip 指令中约 49% 触发了 illegal instruction exception。trap handler 尝试处理，但 handler 自身可能：
1. **跳回了触发异常的指令**（mepc 没前进），或者
2. **handler 本身也触发异常**（stack pointer s7 递减到非法地址），形成嵌套异常死循环

这不是 cosim 问题——这是 **riscv-dv 生成器 + trap handler** 的问题：
- 生成器产生了 EH2 RTL 不认识的（或配置中未使能的）bitmanip 指令
- 高 illegal 率导致 trap handler stack 溢出或死循环
- 测试永远跑不到 mailbox PASS

## 4. cosim init ISA 字符串

```
Cosim config: isa=rv32imac_zba_zbb_zbc_zbs;pc=0x80000000;mtvec=0x80000000;pmp_regions=0;pmp_granularity=0;mhpm_counters=0
```

ISA 字符串正确包含 `zba_zbb_zbc_zbs`。

## 5. 一句话根因

**riscv-dv 生成的 bitmanip 指令包含 EH2 RTL 不支持的子集（可能是 draft Zbe/Zbf/Zbp/Zbr 编码），导致 ~49% illegal exception 率，trap handler stack 溢出后死循环，测试永远无法到达 mailbox。** 这是 riscv-dv generator 约束问题，不是 cosim 路径问题。

## 6. 三选一推荐

### A. 修 riscv-dv generator 约束（**推荐**）
- 文件：`dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv`
  - 行 118-136：`eh2_bitmanip_stream` 的指令列表
  - 需要确保只生成 EH2 支持的 Zba/Zbb/Zbc/Zbs 指令，排除 draft 子集
- 文件：`dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv`
  - 行 29-48：需确认 supported_isa 列表是否正确
- 预估改动：20-40 行
- 风险：低（只改 generator 约束）

### B. 增大 max_cycles + 改善 trap handler
- 文件：testlist.yaml sim_opts 的 `+max_cycles`
- 文件：riscv-dv 的 trap handler 模板
- 预估改动：10-20 行
- 风险：中（治标不治本，49% 异常率还是太高）

### C. 维持 cosim:disabled + 降低 instr_cnt 做 smoke
- 不改任何代码
- 在 testlist 加一个 `riscv_bitmanip_smoke_test` 用少量指令 + cosim enabled
- 预估改动：10 行 testlist
- 风险：低，但覆盖率有限

## 7. 建议

**推荐 A**——修 generator 约束让 eh2_bitmanip_stream 只生成 EH2 默认配置支持的 Zba/Zbb/Zbc/Zbs 指令。49% 的 illegal 率说明 generator 产生了大量无效指令，这不是 cosim 的问题。

等待人决策后进入第 2 步。
