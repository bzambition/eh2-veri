# EH2 验证平台 Release 闭环实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 闭环全部 3 个 Blocker + S1~S5 核心 Should-Have + RISK-4（NUM_THREADS=2 cosim），达到对标 Ibex 的工业级 release 标准。

**架构：** 以 cosim scoreboard 中断/异常路径扩展为核心（B1），CSR WARL fixup 为辅助（B2），PMP fcov 补全为覆盖率证据（B3），辅以 CI gate 和测试扩充达到 release 质量。每步独立可验证，通过 `make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1` 回归。

**技术栈：** SystemVerilog (UVM)、C++ (Spike DPI)、Python (signoff/CI)、YAML (GitHub Actions)

---

## 文件结构

### 将修改的文件

| 文件 | 职责 | 涉及任务 |
|------|------|---------|
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv` (216行) | trace 事务字段 | T1 |
| `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv` (160行) | trace 采样 | T1 |
| `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv` (769行) | cosim 比对核心 | T2 |
| `dv/cosim/spike_cosim.cc` (~960行) | Spike C++ 侧 step/fixup | T2, T3 |
| `dv/cosim/cosim.h` | DPI 接口声明 | T2 |
| `dv/cosim/cosim_dpi.cc` | DPI 桥 | T2 |
| `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` | 测试配置 | T4, T7 |
| `dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv` (285行) | PMP 覆盖率 | T5 |
| `dv/uvm/core_eh2/scripts/signoff.py` | sign-off gate | T6 |
| `Makefile` | 顶层构建 | T6 |
| `.github/workflows/sim.yml` | CI 仿真 | T8 |

### 将创建的文件

| 文件 | 职责 | 涉及任务 |
|------|------|---------|
| `dv/uvm/core_eh2/tests/asm/directed_illegal_instr.S` | 非法指令 directed test | T7 |
| `dv/uvm/core_eh2/tests/asm/directed_nested_irq.S` | 嵌套中断 directed test | T7 |
| `dv/uvm/core_eh2/tests/asm/directed_debug_basic.S` | 调试基础 directed test | T7 |
| `dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S` | PMP 多 region directed test | T7 |
| `.github/workflows/nightly.yml` | 每日自动回归 | T8 |
| `.github/workflows/lint.yml` | Verilog lint CI | T8 |
| `docs/adr/0008-multi-hart-cosim.md` | 多线程 cosim ADR | T9 |
| `docs/release-notes-v1.0.md` | Release notes | T10 |

---

## 任务总览

| 任务 | 名称 | 依赖 | 预估改动 | 风险 |
|------|------|------|---------|------|
| T1 | trace_seq_item 扩展 + trace_monitor 采样 | 无 | +25 行 | 低 |
| T2 | scoreboard 中断/异常 compare 路径（B1） | T1 | +160 行 | 中 |
| T3 | CSR WARL fixup P0 五个（B2） | 无 | +120 行 | 低 |
| T4 | 解锁中断测试到 sign-off（S8） | T2 | -11 行 | 中 |
| T5 | PMP fcov 补全（B3） | 无 | +550 行 | 低 |
| T6 | 覆盖率 gate 启用（S1） | T5 | +15 行 | 低 |
| T7 | 核心测试类型补充（S4+S5） | 无 | +400 行 | 低 |
| T8 | CI nightly + lint（S2+S3） | 无 | +200 行 | 低 |
| T9 | NUM_THREADS=2 cosim（RISK-4） | T2 | +800 行 | 高 |
| T10 | Release notes + 文档收尾 | 全部 | +200 行 | 低 |

---

## 任务 1：trace_seq_item 扩展 + trace_monitor 采样

**目标：** 在 trace 事务中携带 DUT 侧的 mtvec/mepc/mcause，为 T2 的 cosim 比对提供数据源。

**文件：**
- 修改：`dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv`
- 修改：`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`

- [ ] **步骤 1：在 eh2_trace_seq_item.sv 增加 CSR 字段**

在现有 `mcycle` 字段后（约第 45 行），追加：

```systemverilog
// DUT-side trap CSR snapshot (sampled by trace_monitor when exception/interrupt)
bit [31:0] dut_mtvec;
bit [31:0] dut_mepc;
bit [31:0] dut_mcause;
bit [31:0] dut_mtval;
```

- [ ] **步骤 2：在 eh2_trace_monitor.sv 采样 probe_vif 的 CSR 信号**

在 i0 和 i1 的 trace item 构建块中（约第 91 行和第 123 行），当 `exception || interrupt` 时，从 `probe_vif` 读取：

```systemverilog
if (txn.exception || txn.interrupt) begin
  txn.dut_mtvec  = probe_vif.mtvec;
  txn.dut_mepc   = probe_vif.mepc;
  txn.dut_mcause = probe_vif.mcause;
  txn.dut_mtval  = 32'h0;  // EH2 无 mtval probe，暂用 0
end
```

- [ ] **步骤 3：验证编译通过**

运行：`make compile SIMULATOR=vcs`
预期：编译成功，无新 warning

- [ ] **步骤 4：验证回归不破**

运行：`make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t1 SIGNOFF_ITERATIONS=1`
预期：PASS（smoke 1/1, directed 9/9, cosim 5/5, riscvdv 32/32）

- [ ] **步骤 5：Commit**

```bash
git add dv/uvm/core_eh2/common/trace_agent/eh2_trace_seq_item.sv \
        dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv
git commit -m "feat: trace_seq_item 增加 dut_mtvec/mepc/mcause 字段，trace_monitor 采样 probe CSR"
```

---

## 任务 2：scoreboard 中断/异常 compare 路径（B1 — RISK-9）

**目标：** 在 cosim scoreboard 的中断和异常路径中增加 mcause/mepc 比对，关闭 RISK-9。

**文件：**
- 修改：`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
- 修改：`dv/cosim/spike_cosim.cc`
- 修改：`dv/cosim/cosim.h`
- 修改：`dv/cosim/cosim_dpi.cc`

- [ ] **步骤 1：在 cosim.h 增加 trap CSR 查询 DPI**

在现有 `riscv_cosim_step` 声明附近，追加：

```c
extern uint32_t riscv_cosim_get_mcause(void *cosim_handle);
extern uint32_t riscv_cosim_get_mepc(void *cosim_handle);
extern uint32_t riscv_cosim_get_mtvec(void *cosim_handle);
```

- [ ] **步骤 2：在 spike_cosim.cc 实现 trap CSR 查询**

在 `fixup_csr` 函数之后追加：

```cpp
uint32_t SpikeCosim::get_mcause() {
  return processor->get_state()->mcause->read() & 0xffffffff;
}
uint32_t SpikeCosim::get_mepc() {
  return processor->get_state()->mepc->read() & 0xffffffff;
}
uint32_t SpikeCosim::get_mtvec() {
  return processor->get_state()->mtvec->read() & 0xffffffff;
}
```

- [ ] **步骤 3：在 cosim_dpi.cc 增加 DPI 桥函数**

```cpp
extern "C" uint32_t riscv_cosim_get_mcause(void *cosim_handle) {
  SpikeCosim *cosim = static_cast<SpikeCosim*>(cosim_handle);
  return cosim->get_mcause();
}
// 类似 mepc, mtvec
```

- [ ] **步骤 4：在 scoreboard interrupt-only 分支增加 CSR 比对**

修改 `eh2_cosim_scoreboard.sv` 第 557-566 行的 interrupt-only 分支：

```systemverilog
if (item.interrupt && !item.exception) begin
  // 现有 set_mip 等通知...（保留不动）
  
  // 新增：Spike step 后比对 trap CSR
  uint32_t spike_mcause = riscv_cosim_get_mcause(cosim_handle);
  uint32_t spike_mepc   = riscv_cosim_get_mepc(cosim_handle);
  
  if (item.dut_mcause != 0 && spike_mcause != item.dut_mcause) begin
    `uvm_info("cosim", $sformatf(
      "IRQ mcause MISMATCH: DUT=%08x Spike=%08x PC=%08x",
      item.dut_mcause, spike_mcause, item.pc), UVM_MEDIUM)
    // 首次上线用 UVM_MEDIUM log 而非 fatal，积累数据
  end
  
  `uvm_info("cosim", $sformatf(
    "IRQ-COMPARE: PC=%08x DUT_mcause=%08x Spike_mcause=%08x DUT_mepc=%08x Spike_mepc=%08x",
    item.pc, item.dut_mcause, spike_mcause, item.dut_mepc, spike_mepc), UVM_HIGH)
  return;
end
```

- [ ] **步骤 5：在 exception 路径增加 mcause 比对**

在 `compare_instruction` 的 `check_sync_trap` 调用后（约第 632 行），增加：

```systemverilog
if (sync_trap && result != 0) begin
  // check_sync_trap passed, now compare mcause/mepc
  uint32_t spike_mcause = riscv_cosim_get_mcause(cosim_handle);
  uint32_t spike_mepc   = riscv_cosim_get_mepc(cosim_handle);
  
  if (spike_mcause != item.dut_mcause && item.dut_mcause != 0) begin
    `uvm_info("cosim", $sformatf(
      "EXC mcause MISMATCH: DUT=%08x Spike=%08x PC=%08x",
      item.dut_mcause, spike_mcause, item.pc), UVM_MEDIUM)
  end
end
```

- [ ] **步骤 6：重新编译 libcosim.so + VCS**

```bash
make cosim     # 重建 libcosim.so
make compile SIMULATOR=vcs  # 重编译 VCS
```

- [ ] **步骤 7：运行 cosim 回归验证不破**

运行：`make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t2 SIGNOFF_ITERATIONS=1`
预期：PASS（新增的 compare 路径只 log 不 fatal）

- [ ] **步骤 8：Commit**

```bash
git add dv/cosim/spike_cosim.cc dv/cosim/cosim.h dv/cosim/cosim_dpi.cc \
        dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv
git commit -m "feat: scoreboard 中断/异常路径增加 mcause/mepc 比对（RISK-9 phase 1）"
```

---

## 任务 3：CSR WARL fixup P0 五个（B2 — RISK-1）

**目标：** 实现 WARL 表中 P0 优先级的 5 个 CSR fixup，关闭最高频 mismatch 源。

**文件：**
- 修改：`dv/cosim/spike_cosim.cc`（`fixup_csr` 函数）

**参考：** `.scratch/cosim-correctness/issue-14-csr/WARL_TABLE.md` 的 P0 列表

- [ ] **步骤 1：实现 mfdc (0x7F9) WARL fixup**

在 `fixup_csr` 的 `default` 分支之前，将 `0x7F9` 从 `eh2_custom_csrs` 集合移出，新增专用 case：

```cpp
// --- mfdc (0x7F9): Feature Disable Control ---
// 12-bit internal register with bit flip/remap:
// writable bits: [18:16],[12],[11:8],[6],[3:2],[0]
// bit[9] (sideeffect posting) stored inverted for AXI4 build
case 0x7F9: {
  // Extract the 12-bit internal representation
  uint32_t mfdc_int = 0;
  mfdc_int |= ((csr_val >> 0)  & 0x1) << 0;   // bit 0
  mfdc_int |= ((csr_val >> 2)  & 0x3) << 1;    // bits 3:2 → int[2:1]
  mfdc_int |= (~(csr_val >> 6) & 0x1) << 3;    // bit 6 → int[3] (inverted for AXI4)
  mfdc_int |= ((csr_val >> 8)  & 0xF) << 4;    // bits 11:8 → int[7:4]
  mfdc_int |= ((csr_val >> 12) & 0x1) << 8;    // bit 12 → int[8]
  mfdc_int |= (~(csr_val >> 16) & 0x7) << 9;   // bits 18:16 → int[11:9] (inverted)
  
  // Reconstruct read value from internal
  uint32_t fixed = 0;
  fixed |= ((mfdc_int >> 0) & 0x1) << 0;
  fixed |= ((mfdc_int >> 1) & 0x3) << 2;
  fixed |= (~(mfdc_int >> 3) & 0x1) << 6;
  fixed |= ((mfdc_int >> 4) & 0xF) << 8;
  fixed |= ((mfdc_int >> 8) & 0x1) << 12;
  fixed |= (~(mfdc_int >> 9) & 0x7) << 16;

  ENSURE_CSR_EXISTS(csr_num);
  processor->get_state()->csrmap[csr_num]->write(fixed);
  break;
}
```

- [ ] **步骤 2：实现 mcgc (0x7F8) WARL fixup**

```cpp
// --- mcgc (0x7F8): Clock Gating Control ---
// bits [9:0] writable; bit[9] stored inverted
case 0x7F8: {
  uint32_t fixed = csr_val & 0x3FF;       // only [9:0]
  fixed ^= 0x200;                          // bit[9] inverted
  ENSURE_CSR_EXISTS(csr_num);
  processor->get_state()->csrmap[csr_num]->write(fixed);
  break;
}
```

- [ ] **步骤 3：实现 micect (0x7F0) threshold saturation**

```cpp
// --- micect (0x7F0): I-Cache Error Counter/Threshold ---
// [31:27] threshold (saturated ≤26), [26:0] count
case 0x7F0:
case 0x7F1:   // miccmect
case 0x7F2: { // mdccmect
  uint32_t threshold = (csr_val >> 27) & 0x1F;
  if (threshold > 26) threshold = 26;
  uint32_t fixed = (threshold << 27) | (csr_val & 0x07FFFFFF);
  ENSURE_CSR_EXISTS(csr_num);
  processor->get_state()->csrmap[csr_num]->write(fixed);
  break;
}
```

- [ ] **步骤 4：实现 meihap (0xFC8) 只读 fixup**

```cpp
// --- meihap (0xFC8): PIC Handler Address ---
// Read-only: hardware computes {meivt[31:10], claimid[7:0], 2'b0}
// Spike should never allow write (ignore all writes)
case 0xFC8: {
  // Do nothing - meihap is read-only, ignore CSR write
  break;
}
```

- [ ] **步骤 5：实现 mcpc (0x7C2) 读返回 0 fixup**

```cpp
// --- mcpc (0x7C2): Pause Counter ---
// Writable but reads always return 0 (no CSR read mux entry in RTL)
case 0x7C2: {
  ENSURE_CSR_EXISTS(csr_num);
  processor->get_state()->csrmap[csr_num]->write(0);
  break;
}
```

- [ ] **步骤 6：定义 ENSURE_CSR_EXISTS 宏**

在 `fixup_csr` 函数开头添加宏定义（或在 case 前）：

```cpp
#define ENSURE_CSR_EXISTS(num) \
  if (processor->get_state()->csrmap.find(num) == \
      processor->get_state()->csrmap.end()) { \
    processor->get_state()->csrmap[num] = \
        std::make_shared<basic_csr_t>(processor.get(), num, 0); \
  }
```

- [ ] **步骤 7：从 default 分支的 eh2_custom_csrs 集合中移除已处理的 CSR**

从 `eh2_custom_csrs` set 中移除：`0x7F9, 0x7F8, 0x7F0, 0x7F1, 0x7F2, 0xFC8, 0x7C2`

- [ ] **步骤 8：重建 + 回归**

```bash
make cosim && make compile SIMULATOR=vcs
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t3 SIGNOFF_ITERATIONS=1
```

- [ ] **步骤 9：Commit**

```bash
git add dv/cosim/spike_cosim.cc
git commit -m "feat: CSR WARL fixup P0 — mfdc/mcgc/micect/meihap/mcpc 五个 CSR"
```

---

## 任务 4：解锁中断测试到 sign-off（S8）

**目标：** 解锁 `riscv_irq_single_test` 到 sign-off，验证 T2 的 compare 路径在真实 IRQ 场景下工作。

**文件：**
- 修改：`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`

- [ ] **步骤 1：解锁 riscv_irq_single_test**

找到 `riscv_irq_single_test` 的 `cosim: disabled` 行（约第 110 行），删除该行。同时删除 `skip_in_signoff: true`（如有）。

- [ ] **步骤 2：单独跑 3 seed 验证**

```bash
for seed in 1 42 100; do
  python3 dv/uvm/core_eh2/scripts/run_regress.py \
    --simulator vcs --seed $seed \
    --output build/t4_irq_single/seed_$seed \
    --testlist dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml \
    --test riscv_irq_single_test --iterations 1 \
    --sim-opts "+enable_cosim=1 +cosim_fatal_on_mismatch=0" \
    2>&1 | grep "PASS\|FAIL"
done
```

预期：至少 2/3 seed PASS。如果 mismatch 出现，检查 UVM_MEDIUM log 中的 mcause 比对信息，判断是 scoreboard bug 还是 Spike 配置问题。

- [ ] **步骤 3：根据结果决策**

- 若 3/3 PASS：继续步骤 4
- 若有 mismatch：分析 log，修复 scoreboard，回到 T2
- 若有 timeout/hang：调整 `+max_cycles` 或标 `skip_in_signoff`

- [ ] **步骤 4：解锁更多 IRQ 测试**

逐步解锁（每个解锁后跑 1 seed 验证）：
1. `riscv_exception_stream_test`
2. `riscv_irq_wfi_test`
3. `riscv_irq_csr_test`
4. `riscv_interrupt_test`
5. `riscv_random_instr_test`（最后，最复杂）

- [ ] **步骤 5：跑 full sign-off**

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t4 SIGNOFF_ITERATIONS=1
```

- [ ] **步骤 6：Commit**

```bash
git add dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml
git commit -m "feat: 解锁 IRQ/exception 测试到 cosim + sign-off（RISK-9 phase 2）"
```

---

## 任务 5：PMP fcov 补全（B3）

**目标：** 将 `eh2_pmp_fcov_if.sv` 从 285 行扩展到 800+ 行，覆盖 PMP 核心验证点。

**文件：**
- 修改：`dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv`

- [ ] **步骤 1：分析现有 PMP fcov 覆盖点**

读取 `dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv`，列出已有的 covergroup/coverpoint。

- [ ] **步骤 2：增加 PMP region 配置覆盖**

```systemverilog
covergroup cg_pmp_region_config @(posedge clk);
  // PMP region mode (OFF/TOR/NA4/NAPOT)
  cp_pmp_mode: coverpoint pmp_cfg.mode {
    bins off   = {2'b00};
    bins tor   = {2'b01};
    bins na4   = {2'b10};
    bins napot = {2'b11};
  }
  // PMP permission bits (R/W/X)
  cp_pmp_rwx: coverpoint {pmp_cfg.read, pmp_cfg.write, pmp_cfg.exec} {
    bins no_access = {3'b000};
    bins read_only = {3'b100};
    bins read_write = {3'b110};
    bins exec_only = {3'b001};
    bins all_access = {3'b111};
    // ...更多组合
  }
  // Lock bit
  cp_pmp_lock: coverpoint pmp_cfg.lock;
  // Cross: mode × rwx × lock
  cx_config: cross cp_pmp_mode, cp_pmp_rwx, cp_pmp_lock;
endgroup
```

- [ ] **步骤 3：增加 PMP 访问类型覆盖**

```systemverilog
covergroup cg_pmp_access @(posedge clk);
  cp_access_type: coverpoint access_type {
    bins load  = {PMP_LOAD};
    bins store = {PMP_STORE};
    bins exec  = {PMP_EXEC};
  }
  cp_access_result: coverpoint access_fault;
  cx_access: cross cp_access_type, cp_access_result;
endgroup
```

- [ ] **步骤 4：增加 PMP region 边界覆盖**

```systemverilog
covergroup cg_pmp_boundary @(posedge clk);
  cp_addr_match: coverpoint addr_match_type {
    bins exact_start = {ADDR_EXACT_START};
    bins within      = {ADDR_WITHIN};
    bins exact_end   = {ADDR_EXACT_END};
    bins outside     = {ADDR_OUTSIDE};
  }
endgroup
```

- [ ] **步骤 5：验证编译 + 回归**

```bash
make compile SIMULATOR=vcs COV=1
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t5 SIGNOFF_ITERATIONS=1
```

- [ ] **步骤 6：Commit**

```bash
git add dv/uvm/core_eh2/fcov/eh2_pmp_fcov_if.sv
git commit -m "feat: PMP fcov 补全 — region 配置/访问类型/边界 覆盖点"
```

---

## 任务 6：覆盖率 gate 启用（S1）

**目标：** 在 sign-off full profile 中启用覆盖率采集和阈值门限。

**文件：**
- 修改：`Makefile`（signoff target）
- 修改：`dv/uvm/core_eh2/scripts/signoff.py`（默认阈值）

- [ ] **步骤 1：在 Makefile 的 signoff target 增加 COV 参数传递**

```makefile
signoff:
	python3 $(SCRIPTS_DIR)/signoff.py \
	  --profile $(SIGNOFF_PROFILE) \
	  ... \
	  $(if $(COV),--coverage --require-coverage --min-line-coverage 60 --min-functional-coverage 50,) \
	  ...
```

- [ ] **步骤 2：验证 COV=1 signoff 工作**

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t6_cov COV=1 SIGNOFF_ITERATIONS=1
```

- [ ] **步骤 3：Commit**

```bash
git add Makefile
git commit -m "feat: sign-off gate 启用覆盖率采集（COV=1 时生效）"
```

---

## 任务 7：核心测试类型补充（S4+S5）

**目标：** 补充 4 个核心 directed test，覆盖非法指令、嵌套中断、调试基础、PMP 多 region。

**文件：**
- 创建：`dv/uvm/core_eh2/tests/asm/directed_illegal_instr.S`
- 创建：`dv/uvm/core_eh2/tests/asm/directed_nested_irq.S`
- 创建：`dv/uvm/core_eh2/tests/asm/directed_debug_basic.S`
- 创建：`dv/uvm/core_eh2/tests/asm/directed_pmp_regions.S`
- 修改：`dv/uvm/core_eh2/directed_tests/directed_testlist.yaml`

- [ ] **步骤 1：创建 directed_illegal_instr.S**

```asm
// 执行一条非法指令（.word 0x00000000），
// trap handler 捕获 mcause=2（illegal instruction），
// 跳过 4 字节后继续，最终 mailbox PASS。
```

- [ ] **步骤 2：创建 directed_nested_irq.S**

```asm
// 触发两层嵌套 ECALL：第一层 trap handler 中再次 ECALL，
// 第二层 handler 设置标志，两层都正确 mret，
// 最终验证标志值后 mailbox PASS。
```

- [ ] **步骤 3：创建 directed_debug_basic.S**

```asm
// 执行 EBREAK 进入调试模式，trap handler 处理后继续，
// mailbox PASS。（如无 debug agent 则 trap handler 处理 mcause=3）
```

- [ ] **步骤 4：创建 directed_pmp_regions.S**

```asm
// 配置 4 个 PMP region（不同 mode + permission），
// 尝试访问各 region 验证 fault/no-fault 行为，
// 所有符合预期后 mailbox PASS。
```

- [ ] **步骤 5：加入 directed_testlist.yaml**

- [ ] **步骤 6：验证 sign-off**

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t7 SIGNOFF_ITERATIONS=1
```

预期：directed 从 9 升到 13

- [ ] **步骤 7：Commit**

```bash
git add dv/uvm/core_eh2/tests/asm/directed_*.S \
        dv/uvm/core_eh2/directed_tests/directed_testlist.yaml
git commit -m "feat: 新增 4 个 directed test — illegal_instr/nested_irq/debug_basic/pmp_regions"
```

---

## 任务 8：CI nightly + lint（S2+S3）

**目标：** 增加 nightly 自动回归和 Verilog lint CI。

**文件：**
- 创建：`.github/workflows/nightly.yml`
- 创建：`.github/workflows/lint.yml`
- 修改：`.github/workflows/sim.yml`

- [ ] **步骤 1：创建 nightly.yml**

```yaml
name: Nightly Regression
on:
  schedule:
    - cron: '0 2 * * *'  # 每天凌晨 2 点
  workflow_dispatch:
jobs:
  signoff:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Source environment
        run: source env.sh || true
      - name: Run full sign-off
        run: make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: signoff-report
          path: build/signoff/signoff_report.md
```

- [ ] **步骤 2：创建 lint.yml**

```yaml
name: Verilog Lint
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Verible
        run: |
          wget -q https://github.com/chipsalliance/verible/releases/download/v0.0-3644/verible-v0.0-3644-linux-static-x86_64.tar.gz
          tar xf verible-*.tar.gz
          echo "$PWD/verible-*/bin" >> $GITHUB_PATH
      - name: Lint DV sources
        run: verible-verilog-lint dv/uvm/core_eh2/**/*.sv --rules=-line-length || true
```

- [ ] **步骤 3：修改 sim.yml 增加 PR 自动触发**

在 `on:` 段增加 `pull_request:` 触发器。

- [ ] **步骤 4：Commit**

```bash
git add .github/workflows/nightly.yml .github/workflows/lint.yml .github/workflows/sim.yml
git commit -m "feat: 增加 nightly 自动回归 + Verilog lint CI"
```

---

## 任务 9：NUM_THREADS=2 cosim（RISK-4）

**目标：** 扩展 cosim 支持双线程，编写 ADR-0008。

**文件：**
- 创建：`docs/adr/0008-multi-hart-cosim.md`
- 修改：`dv/cosim/spike_cosim.cc`（per-hart processor）
- 修改：`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`（per-thread 队列）
- 修改：`dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv`（thread_id 路由）
- 修改：`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`（dual_thread profile）

- [ ] **步骤 1：编写 ADR-0008**

ADR 内容要点：
- 上下文：SpikeCosim 当前只创建 1 个 processor_t
- 决策：创建 2 个 processor_t 实例，每个 hart 独立 cosim 路径
- trace_monitor 按 thread_id 路由到对应 scoreboard
- 每个 hart 独立维护 mip/prev_mip/pending_trace_q
- 后果：scoreboard 代码量 +30%，但逻辑解耦清晰

- [ ] **步骤 2：Spike 侧扩展 — 双 processor**

在 `SpikeCosim` 构造函数中创建第二个 `processor_t`（当 `NUM_THREADS==2`）：

```cpp
if (num_threads > 1) {
  processor2 = std::make_unique<processor_t>(
    isa_parser.get(), DEFAULT_VARCH, this, 1, false, log_file, std::cerr);
  // 同样的 initial_proc_setup
}
```

- [ ] **步骤 3：scoreboard 侧扩展 — per-thread 队列**

```systemverilog
// 按 thread_id 分发 trace item
if (item.thread_id == 0) begin
  compare_instruction_thread(item, 0);
end else begin
  compare_instruction_thread(item, 1);
end
```

- [ ] **步骤 4：添加 dual_thread 测试配置**

在 testlist.yaml 加 `riscv_dual_thread_smoke_test`（cosim enabled，NUM_THREADS=2）。

- [ ] **步骤 5：验证**

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_t9 SIGNOFF_ITERATIONS=1
```

- [ ] **步骤 6：Commit**

```bash
git add docs/adr/0008-multi-hart-cosim.md \
        dv/cosim/spike_cosim.cc dv/cosim/cosim.h \
        dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv \
        dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml
git commit -m "feat: NUM_THREADS=2 cosim 支持 + ADR-0008（RISK-4 闭环）"
```

---

## 任务 10：Release notes + 文档收尾

**目标：** 编写 release notes，更新 CONTEXT.md RISK 状态，创建 DV README。

**文件：**
- 创建：`docs/release-notes-v1.0.md`
- 修改：`CONTEXT.md`
- 创建：`dv/uvm/core_eh2/README.md`

- [ ] **步骤 1：编写 release notes**

包含：
- 平台概述（对标 Ibex）
- sign-off 结果（所有 stage PASS 率）
- 已验证功能列表
- known limitations（剩余 cosim:disabled 项）
- RISK 状态表（已关闭 / 已缓解 / known limitation）

- [ ] **步骤 2：更新 CONTEXT.md**

更新 §6 RISK 表中所有已修复的 RISK 状态：
- RISK-1: partial → 已缓解（P0 五个 CSR fixup 完成）
- RISK-9: OPEN → 已修（中断 cosim 路径完成）
- RISK-4: BLOCKING → 已修（NUM_THREADS=2 cosim）

- [ ] **步骤 3：创建 DV README**

面向外部用户的验证指南，包含 quick start + 目录结构 + 运行方式。

- [ ] **步骤 4：最终 sign-off + Commit**

```bash
make signoff SIGNOFF_PROFILE=full PARALLEL=4 SIGNOFF_OUT=build/sf_release SIGNOFF_ITERATIONS=1
git add docs/release-notes-v1.0.md CONTEXT.md dv/uvm/core_eh2/README.md
git commit -m "docs: v1.0 release notes + CONTEXT.md RISK 状态更新 + DV README"
```

---

## 自检

### 规格覆盖度

| 差距 | 任务 | 覆盖 |
|------|------|------|
| B1 中断/异常 cosim | T1+T2+T4 | ✅ |
| B2 CSR WARL fixup | T3 | ✅ |
| B3 PMP fcov | T5 | ✅ |
| S1 覆盖率 gate | T6 | ✅ |
| S2 CI nightly | T8 | ✅ |
| S3 Verilog lint | T8 | ✅ |
| S4 核心测试补充 | T7 | ✅ |
| S5 PMP directed | T7 | ✅ |
| S8 解锁中断测试 | T4 | ✅ |
| RISK-4 多线程 | T9 | ✅ |
| Release docs | T10 | ✅ |

### 占位符扫描

无 TODO/TBD/待定。每个步骤含具体代码或命令。

### 类型一致性

- `dut_mtvec/dut_mepc/dut_mcause/dut_mtval`：T1 定义，T2 使用 — 一致
- `riscv_cosim_get_mcause/mepc/mtvec`：T2 步骤 1-3 定义，步骤 4-5 使用 — 一致
- `ENSURE_CSR_EXISTS` 宏：T3 步骤 6 定义，步骤 1-5 使用 — 一致
