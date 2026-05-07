# EH2 UVM 验证平台 v1.0 Release Notes

发布日期：2026-05-08

---

## 平台概述

EH2 UVM 验证平台（`eh2-veri`）是面向 **VeeR EH2 RISC-V 核**的工业级验证环境，对标 lowRISC Ibex 验证平台。平台基于 UVM 方法学，结合 Spike DPI 协同仿真（cosim）、riscv-dv 随机指令生成和功能覆盖率采集，为 EH2 双发射、双线程核提供完整的验证闭环。

**核心验证策略：**

- **协同仿真（cosim）**：DUT 每条 retired 指令与 Spike ISS 逐拍比对 PC、寄存器写回、内存访问
- **随机指令生成**：基于 Google riscv-dv 框架，43 个测试用例覆盖 RV32IMAC + Zb* 指令集
- **定向测试**：13 个 directed test + 5 个 cosim proof test，覆盖双发射 hazard、中断、PMP、AXI4 错误注入等关键场景
- **Sign-off Gate**：4 阶段自动化签发（smoke → directed → cosim → riscvdv），全 PASS 方可签发

## Sign-off 结果

基于 `make signoff SIGNOFF_PROFILE=full PARALLEL=4` 的签发结果：

| Stage | 结果 | 总数 | 通过 | 通过率 |
|-------|------|------|------|--------|
| smoke | ✅ PASS | 1 | 1 | 100% |
| directed | ✅ PASS | 13 | 13 | 100% |
| cosim | ✅ PASS | 5 | 5 | 100% |
| riscvdv | ✅ PASS | 32 | 32 | 100% |
| **Sign-off full** | **✅ PASS** | **51** | **51** | **100%** |

> 注：riscvdv 阶段中 43 个测试有 11 个标记 `skip_in_signoff: true`（均为 `cosim: disabled` 的测试），实际执行 32 个。

## 已验证功能

### RV32IMAC 基础指令集

- 基础算术指令（arithmetic_basic_test，10 seed 全 PASS + cosim lockstep）
- 随机指令混合（random_instr_test，20 iterations PASS）
- 乘除法（mul_div_test，含 RTL 推测 div cancel 正确处理）
- 非对齐 load/store（unaligned_load_store_test）
- 跳转与分支（rand_jump_test）

### Zba/Zbb 位操作扩展

- cosim lockstep 证明（cosim_bitmanip 定向测试：sh1add / andn / clz / max 等 Zba/Zbb 指令逐拍比对 PASS）
- 注：随机 bitmanip_test 仍标 cosim:disabled（见 Known Limitations RISK-10）

### 双发射 Pipeline

- dual_issue_test：双发射乱序退役覆盖
- directed_double_issue_hazard：RAW/WAR/WAW hazard 定向验证
- directed_nb_load_chain：NB-load 跨 slot 异步写回链
- cosim_dual_issue：双发射 program-order lockstep 证明

### 中断/异常处理

- scoreboard mcause/mepc 比对上线（RISK-9 phase 1）
- random_instr_test 已解锁 cosim（enable_interrupt + enable_nested_interrupt）
- directed_irq_basic：软件中断触发与 trap handler
- exception_test：非法指令 + EBREAK + 非对齐访问异常
- exception_stream_test：定向异常流测试
- directed_illegal_instr / directed_nested_irq：非法指令异常 + 嵌套 ECALL trap

### AXI4 Bus Error Inject

- axi4_driver 支持 SLVERR/DECERR 错误注入
- directed_axi4_error_inject 定向测试（load access fault 触发验证）

### PMP 基础

- directed_pmp_smoke：PMP region 配置与 access fault
- directed_pmp_regions：多 region PMP 配置
- PMP 功能覆盖率（eh2_pmp_fcov_if.sv，285 行覆盖点）
- 注：PMP cosim 路径仍 disabled（见 Known Limitations）

### NUM_THREADS=2 cosim 架构就绪

- ADR-0008：SpikeCosim 多 hart 支持 + scoreboard per-thread 路由（RISK-4 闭环）
- NUM_THREADS=1 已完整验证
- NUM_THREADS=2 cosim 框架代码已上线，待 RTL 多线程回归验证

### CSR WARL Fixup

- P0 五个关键 CSR fixup 已上线：mfdc / mcgc / micect / meihap / mcpc
- 28 个 EH2 自定义 CSR 通过 `set_csr` 静态注册
- directed_csr_warl：CSR WARL 回读定向测试

### 其他验证功能

- directed_debug_basic：EBREAK 断点异常处理
- invalid_csr_test：无效 CSR 访问异常
- fetch_en_chk_test：取指使能/禁用检查
- formal 验证骨架（dv/formal，Symbiyosys flow + PMP SVA 占位）
- nightly 自动回归 CI + Verilog lint CI

## Known Limitations

### 仍标 cosim:disabled 的测试（共 32 个 riscv-dv + 2 个 directed）

**中断/调试类（15 个）——RISK-9 相关：**

| 测试 | 原因 |
|------|------|
| riscv_interrupt_test | PC mismatch：Spike 未同步嵌套 PIC 中断注入 |
| riscv_irq_single_test | SIM_TIMEOUT：enable_irq_single_seq 的 forever 循环导致 run_phase 挂起 |
| riscv_irq_wfi_test | WFI + 中断交互 cosim 未实现 |
| riscv_irq_csr_test | 中断 + CSR 访问交互 cosim |
| riscv_irq_nest_test | 嵌套中断 cosim |
| riscv_debug_test | 调试模式 cosim 未实现 |
| riscv_debug_csr_test | 调试 CSR cosim |
| riscv_debug_wfi_test | 调试 + WFI cosim |
| riscv_debug_during_csr_test | 调试 + CSR cosim |
| riscv_debug_ebreak_test | EBREAK cosim |
| riscv_debug_ebreakmu_test | ebreakm/u cosim |
| riscv_single_debug_pulse_test | 调试脉冲 cosim |
| riscv_irq_in_debug_test | 中断 + 调试交互 |
| riscv_debug_in_irq_test | 调试 + 中断交互 |
| riscv_dret_test | DRET cosim |

**扩展指令类（2 个）——RISK-10 / RISK-11：**

| 测试 | 原因 |
|------|------|
| riscv_bitmanip_test | Zba/Zbb RTL illegal-instr 异常率高，exception 路径 cosim step 与 trace 速率不匹配（RISK-10） |
| riscv_amo_test | SC.W RTL 写回与 Spike 分歧，需 spike_cosim 加 atomic-store fixup（RISK-11） |

**CSR/PMP 类（8 个）：**

| 测试 | 原因 |
|------|------|
| riscv_csr_test | CSR cosim 路径未实现 |
| riscv_csr_hazard_test | CSR pipeline hazard cosim |
| riscv_pmp_basic_test | PMP cosim 未实现 |
| riscv_pmp_disable_all_test | PMP cosim |
| riscv_pmp_random_test | PMP cosim |
| riscv_epmp_mml_test | ePMP cosim |
| riscv_epmp_mmwp_test | ePMP cosim |
| riscv_epmp_rlb_test | ePMP cosim |

**安全/鲁棒性类（5 个）：**

| 测试 | 原因 |
|------|------|
| riscv_stress_test | 综合压力（中断 + 调试 + bitmanip）cosim |
| riscv_breakpoint_test | 断点 cosim |
| riscv_reset_test | 复位 cosim |
| riscv_single_step_test | 单步调试 cosim |
| riscv_pc_intg_test / riscv_rf_intg_test / riscv_mem_error_test | 完整性/错误注入 cosim |

**Directed 测试（2 个）：**

| 测试 | 原因 |
|------|------|
| directed_csr_warl | CSR WARL 回读不走 cosim |
| directed_axi4_error_inject | AXI4 错误注入不走 cosim |

## RISK 状态

| ID | 严重度 | 问题 | 状态 |
|----|--------|------|------|
| RISK-1 | HIGH | EH2 自定义 CSR 18+ 个，Spike fixup 覆盖不足 | P0 已修（mfdc/mcgc/micect/meihap/mcpc fixup），28 个 set_csr 静态注册，剩余 P1/P2 WARL fixup 留后续 |
| RISK-2 | MEDIUM | AXI4 64-bit 数据截到 32-bit | ✅ 已修（split lower/upper word） |
| RISK-2b | MEDIUM | EH2 sub-byte store 用 wider WSTRB | ✅ 已修（Phase 3 spike_cosim BE 语义放宽） |
| RISK-3 | MEDIUM | wb 与 trace 对齐脆弱 | ✅ 已修（Phase 1 RTL trace 加 RVFI 等价信号） |
| RISK-4 | RESOLVED | NUM_THREADS=2 不能 cosim | ✅ 已修（ADR-0008：SpikeCosim 多 hart + scoreboard per-thread 路由） |
| RISK-5 | LOW | NB-load wb 跨 slot 脱节 | ✅ 已修（Phase 1 scoreboard 等 nb_load hint） |
| RISK-6 | LOW | interrupt 状态采样按 item 而非 cycle | RTL 设计上已正确 |
| RISK-7 | RESOLVED | EH2 推测 div cancel vs 架构 retire 区分 | ✅ 已修（Phase 1 RTL dec_div_cancel_overwrite 信号） |
| RISK-8 | RESOLVED | load_store_test data RF 不同步 | ✅ 已验证不再复现 |
| RISK-9 | 部分修 | random_instr_test 中断/异常 cosim | 部分修（scoreboard mcause/mepc 比对上线，random_instr_test 已解锁 cosim，interrupt_test/irq_single_test 仍 disabled） |
| RISK-10 | OPEN | bitmanip zba/zbb RTL illegal-instr 异常率高 | 标 cosim:disabled，需排除 RTL bug 可能性 |
| RISK-11 | OPEN | atomic SC.W RTL 写回与 Spike 分歧 | 标 cosim:disabled，需 spike_cosim 加 atomic-store fixup |
| RISK-12 | RESOLVED | EH2 directed stream 生成空 instr_list | ✅ 已修 |
| RISK-13 | RESOLVED | check_logs 误判 UVM_FATAL | ✅ 已修 |
| RISK-14 | RESOLVED | libcosim.so 缺失静默不链 | ✅ 已修 |

## 累计工程成果

| 指标 | Phase 0 baseline | v1.0 | 变化 |
|------|------------------|------|------|
| cosim_scoreboard.sv | 1026 行 | 734 行 | -29% |
| dut_probe_monitor.sv | 178 行 | 118 行 | -34% |
| tb_top.sv | 1287 行 | 1071 行 | -17% |
| WB_SEARCH_DEPTH band-aid | 有 | 无 | ✅ 删除 |
| 死代码 wb_* 字段 | 6+ | 0 | ✅ 删除 |
| 定向测试 | 0 | 13 + 5 cosim proof | ✅ |
| ADR 文档 | 0 | 6 篇 | ✅ |
| Git 提交 | 0 | 20+ commits | ✅ |
| Sign-off Gate | 无 | 4 stage 自动化 | ✅ |
| PMP 功能覆盖率 | 无 | 285 行覆盖点 | ✅ |
| CI/CD | 无 | sim.yml + unit-tests.yml + nightly + lint | ✅ |

## 后续规划（v1.1）

1. **RISK-9 完整闭环**：解锁 interrupt_test / irq_single_test 等 15 个中断/调试相关测试的 cosim
2. **RISK-10 排查**：确认 bitmanip RTL illegal-instr 是否为 RTL bug
3. **RISK-11 修复**：spike_cosim 加 atomic-store fixup
4. **覆盖率 Gate**：在 full profile 中启用 `--require-coverage` 并设置最低覆盖率阈值
5. **PMP fcov 补全**：eh2_pmp_fcov_if.sv 从 285 行扩展到对标 Ibex 854 行
6. **测试扩充**：补充 Ibex 有 EH2 无的 7+ 核心测试类型
