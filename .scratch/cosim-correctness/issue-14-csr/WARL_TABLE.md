# EH2 自定义 CSR WARL 行为表

> **issue-14 前置调研** — 从 RTL 源码中抽取的位级 WARL 行为，用于指导 Spike cosim fixup 实现。
>
> 生成日期：2026-05-07
>
> RTL 来源：`Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv`（per-thread CSR）、`eh2_dec_tlu_top.sv`（global CSR）
> Cosim 来源：`dv/cosim/spike_cosim.cc`

---

## 1. 总览表

| # | CSR 名 | 地址 | Reset Value | Writable Mask | WARL 行为 | 特殊读取 fixup | RTL 引用 | set_csr 状态 | fixup_csr 状态 | 优先级 |
|---|--------|------|-------------|---------------|-----------|---------------|----------|-------------|---------------|--------|
| 1 | **mscause** | 0x7FF | 0x0000_0000 | 0x0000_000F | raw (bits [3:0] only) | 读时高28位返回0 | tlu_ctl:1441,1455-1460; read:2314 | 已注册 | 已实现 | P1 |
| 2 | **mrac** | 0x7C0 | 0x0000_0000 | 0xFFFF_FFFF (WARL) | cacheable & sideeffect 互斥: bit[2n+1] &= ~bit[2n] | 否（写入后读出相同） | tlu_top:750,755-772; read:893 | 已注册 | 已实现 | P0 |
| 3 | **mfdc** | 0x7F9 | 见 Note 1 | 0x0007_0D4D (WARL) | 位重映射+反转; bits [18:16],[12],[11:8],[6],[3:2],[0] 有效, 其余读0; bit[9] 置反(AXI4) | 写入值经 flip/remap, 读出≠写入 | tlu_top:716,720-735; read:895 | 已注册 | **未实现** | **P0** |
| 4 | **mcgc** | 0x7F8 | 0x0000_0200 | 0x0000_03FF | bits [9:0] 有效; bit[9]存储时取反 | 读时 bit[9] 再次反转 | tlu_top:680,683-686; read:894 | 已注册 | **未实现** | **P0** |
| 5 | **mpmc** | 0x7C6 | 0x0000_0002 | 0x0000_0002 | R0W1; only bit[1] writable | 读: `{30'b0, mpmc[1], 1'b0}` | tlu_ctl:1517,1525-1527; read:2340 | 已注册 | 已实现 | P1 |
| 6 | **meivt** | 0xBC8 | 0x0000_0000 | 0xFFFF_FC00 | bits [31:10] writable, [9:0] hardwired 0 | 读: `{meivt[31:10], 10'b0}` | tlu_ctl:1533,1537; read:2317 | 已注册 | 已实现 | P1 |
| 7 | **meipt** | 0xBC9 | 0x0000_0000 | 0x0000_000F | bits [3:0] writable, [31:4] hardwired 0 | 读: `{28'b0, meipt[3:0]}` | tlu_ctl:1589,1591-1592; read:2321 | 已注册 | 已实现 | P1 |
| 8 | **meicurpl** | 0xBCC | 0x0000_0000 | 0x0000_000F | bits [3:0] writable, [31:4] hardwired 0 | 读: `{28'b0, meicurpl[3:0]}` | tlu_ctl:1555,1557-1558; read:2319 | 已注册 | 已实现 | P1 |
| 9 | **meicidpl** | 0xBCB | 0x0000_0000 | 0x0000_000F | bits [3:0] writable; also HW-updated by meicpct/ext_int | 读: `{28'b0, meicidpl[3:0]}`; 写 meicpct 时 HW 覆盖为 pic_pl | tlu_ctl:1570,1572-1574; read:2320 | 已注册 | 已实现 | P1 |
| 10 | **meicpct** | 0xBCA | 0x0000_0000 | N/A (W-only trigger) | 写入触发 claimid 捕获到 meihap、pic_pl 到 meicidpl; 读返回 0 | 读返回 0x0 (无存储) | tlu_ctl:1581,1583 | 已注册 | 未实现（default 分支 basic_csr_t） | P1 |
| 11 | **meihap** | 0xFC8 | 0x0000_0000 | 0x0000_0000 (read-only) | HW-only: `{meivt[31:10], claimid[7:0], 2'b0}` | 读: 组合 meivt 和 claimid; 纯只读 | tlu_ctl:1544,1548-1549; read:2318 | 已注册 | 未实现（default 分支 basic_csr_t） | **P0** |
| 12 | **mfdht** | 0x7CE | 0x0000_0000 | 0x0000_003F | bits [5:0] writable, [31:6] hardwired 0 | 读: `{26'b0, mfdht[5:0]}` | tlu_top:828,830-834; read:899 | 已注册 | **未实现** | P2 |
| 13 | **mfdhs** | 0x7CF | 0x0000_0000 | 0x0000_0003 | bits [1:0] writable; also HW-updated on debug halt | 读: `{30'b0, mfdhs[1:0]}` | tlu_ctl:2241,2243-2245; read:2345 | 已注册 | **未实现** | P2 |
| 14 | **dmst** | 0x7C4 | N/A | N/A (debug-only trigger) | 写 0x7C4 触发 debug fence; 无数据存储 | 无读数据路径（postsync-only, debug mode only） | dec_csr:208,557; ib_ctl:312 | 已注册 | **未实现** | P2 |
| 15 | **dicawics** | 0x7C8 | 0x0000_0000 | 0x0131_FFF8 (WARL) | 写入选取 bits {[24],[21:20],[16:3]}→17b 存储; 其余位忽略 | 读: `{7'b0, [16], 2'b0, [15:14], 3'b0, [13:0], 3'b0}` — 重排 | tlu_ctl:1670,1672-1675; read:2344 | 未注册 | **未实现** | P2 |
| 16 | **dicad0** | 0x7C9 | 0x0000_0000 | 0xFFFF_FFFF | raw (full 32b); 也可被 ifu debug read 覆盖 | 否 | tlu_ctl:1689,1691-1695; read:2341 | 未注册 | **未实现** | P2 |
| 17 | **dicad0h** | 0x7CC | 0x0000_0000 | 0xFFFF_FFFF | raw (full 32b); 也可被 ifu debug read 覆盖 | 否 | tlu_ctl:1703,1705-1709; read:2342 | 未注册 | **未实现** | P2 |
| 18 | **dicad1** | 0x7CA | 0x0000_0000 | ECC: 0x0000_007F / Parity: 0x0000_000F | generate-block 条件: `ICACHE_ECC==1` → [6:0]; else → [3:0] | 读: ECC→`{25'b0, [6:0]}`; Parity→`{28'b0, [3:0]}` | tlu_ctl:1717-1739; read:2343 | 未注册 | **未实现** | P2 |
| 19 | **dicago** | 0x7CB | N/A | N/A (trigger-only) | 写触发 icache 写操作, 读触发 icache 读操作; 无数据存储 | 读返回 0 (由 icache 操作副作用驱动) | tlu_ctl:1744,1754-1755 | 未注册 | **未实现** | P2 |
| 20 | **micect** | 0x7F0 | 0x0000_0000 | 0xFFFF_FFFF (WARL) | [31:27] threshold (saturated ≤26), [26:0] count; HW auto-inc | 写: threshold clamped to 26; 读: raw 32b | tlu_top:780,782-788; read:896 | 已注册 | **未实现** | **P0** |
| 21 | **miccmect** | 0x7F1 | 0x0000_0000 | 0xFFFF_FFFF (WARL) | [31:27] threshold (saturated ≤26), [26:0] count; HW auto-inc | 写: threshold clamped to 26; 读: raw 32b | tlu_top:796,798-802; read:897 | 已注册 | **未实现** | P1 |
| 22 | **mdccmect** | 0x7F2 | 0x0000_0000 | 0xFFFF_FFFF (WARL) | [31:27] threshold (saturated ≤26), [26:0] count; HW auto-inc | 写: threshold clamped to 26; 读: raw 32b | tlu_top:810,816-820; read:898 | 已注册 | **未实现** | P1 |
| 23 | **mcpc** | 0x7C2 | 0x0000_0000 | 0xFFFF_FFFF | raw 32b; 用作 pause counter, 在 decode_ctl 中递减 | 读始终返回 0（CSR read mux 中无 mcpc 项） | tlu_ctl:1489-1490 | 已注册 | **未实现** | P1 |
| 24 | **mdeau** | 0xBC0 | 0x0000_0000 | N/A (W-only trigger) | 写入解锁 mdseac; 无数据存储 | 读返回 0（CSR read mux 中无 mdeau 项） | tlu_ctl:1495,1497 | 已注册 | 未实现（default 分支 basic_csr_t） | P1 |
| 25 | **mdseac** | 0xFC0 | 0x0000_0000 | 0x0000_0000 (read-only) | HW-only: 捕获 imprecise error 地址, mdseac_locked 控制 | 纯只读, HW 捕获 | tlu_ctl:1504,1507-1511; read:2316 | 已注册 | 未实现（default 分支 basic_csr_t） | P1 |
| 26 | **mhartstart** | 0x7FC | 0x0000_0001 | 0x0000_0002 (W1-only) | 写1置位 (sticky); bit[0] 硬连线 1; NUM_THREADS==1 时 bit[1]=0 | 读: `{30'b0, mhartstart[1:0]}` | tlu_top:842,844-852; read:900 | 已注册 | **未实现** | P2 |
| 27 | **mnmipdel** | 0x7FE | 0x0000_0001 | 0x0000_0003 | bits [1:0], 值 0b00 非法时忽略写入 | 读: `{30'b0, mnmipdel[1:0]}` | tlu_top:859,861-871; read:901 | 已注册 | **未实现** | P2 |
| 28 | **mhartnum** | 0xFC4 | (config) | 0x0000_0000 (read-only) | 硬连线: NUM_THREADS>1 → 0x2, else → 0x1 | 纯只读 | tlu_top:878-882,892 | 已注册 | **未实现** | P2 |
| 29 | **mip** (EH2 ext) | 0x344 | 0x0000_0000 | 0x0000_0000 (read-only) | bits [5:0] 有效: {mceip, mitip0, mitip1, meip, mtip, msip}; 全部 HW-driven | 读: 非标准位映射 `{1'b0, mip[5:3], 16'b0, mip[2], 3'b0, mip[1], 3'b0, mip[0], 3'b0}` | tlu_ctl:286; read:2305 | N/A (标准) | N/A | P1 |
| 30 | **mie** (EH2 ext) | 0x304 | 0x0000_0000 | 0x7000_0888 (WARL) | bits [5:0] 有效: {mceie, mitie0, mitie1, meie, mtie, msie} | 读: 同 mip 映射 `{1'b0, mie[5:3], 16'b0, mie[2], 3'b0, mie[1], 3'b0, mie[0], 3'b0}` | tlu_ctl:287; read:2306 | N/A (标准) | N/A | P1 |
| 31 | **mitcnt0** | 0x7D2 | 0x0000_0000 | 0xFFFF_FFFF | raw 32b; HW auto-inc, match 时清零 | 否 | tlu_ctl(timer):2410,2412-2419; read:2509 | 已注册 | 未实现（default 分支） | P2 |
| 32 | **mitcnt1** | 0x7D5 | 0x0000_0000 | 0xFFFF_FFFF | raw 32b; HW auto-inc, match 时清零 | 否 | tlu_ctl(timer):2443; read:2510 | 已注册 | 未实现（default 分支） | P2 |
| 33 | **mitb0** | 0x7D3 | 0xFFFF_FFFF | 0xFFFF_FFFF | raw 32b | 否 | tlu_ctl(timer); read:2511 | 已注册 | 未实现（default 分支） | P2 |
| 34 | **mitb1** | 0x7D6 | 0xFFFF_FFFF | 0xFFFF_FFFF | raw 32b | 否 | tlu_ctl(timer); read:2512 | 已注册 | 未实现（default 分支） | P2 |
| 35 | **mitctl0** | 0x7D4 | 0x0000_0001 | 0x0000_0007 | bits [2:0]: {enable_paused, enable_halted, enable} | 读: `{29'b0, mitctl0[2:0]}` | tlu_ctl(timer):2380-2385; read:2513 | 已注册 | 未实现（default 分支） | P2 |
| 36 | **mitctl1** | 0x7D7 | 0x0000_0001 | 0x0000_000F | bits [3:0]: {cascade, enable_paused, enable_halted, enable} | 读: `{28'b0, mitctl1[3:0]}` | tlu_ctl(timer):2386; read:2514 | 已注册 | 未实现（default 分支） | P2 |

---

## 2. 注释

### Note 1: mfdc 默认值

mfdc 的物理寄存器为 12 位 `mfdc_int[11:0]`，reset 后全 0。但读出经过反转/重排映射：
- **AXI4 build** (`BUILD_AXI4==1`)：bit[9]（对应 mfdc[6] sideeffect posting）存储时取反，读时再取反
- bits [18:16] (DMA QoS) 存储时取反、读时取反 → 复位后读出 0x0007_0000（默认 DMA QoS = 7）

Cosim fixup 需要精确复制这个反转逻辑，否则 CSRRW mfdc 操作会引起 mismatch。

### Note 2: mcgc bit[9] 反转

mcgc bit[9] (`picio_clk_override`) 存储时取反：`mcgc_ns[9] = ~wrdata[9]`，读时再反转：`mcgc[9] = ~mcgc_int[9]`。因此对外呈现的是正常 R/W 语义，但 Spike 的 basic_csr_t 不做这个反转，需要 fixup。

### Note 3: micect/miccmect/mdccmect threshold saturation

这三个 CSR 的 [31:27] 字段在写入时做饱和处理：`csr_sat = (wrdata[31:27] > 26) ? 26 : wrdata[31:27]`。Spike 的 basic_csr_t 不做这个 clamp，写入 threshold > 26 的值会导致 read-back mismatch。

### Note 4: dicawics 位重排

dicawics 写入选取 `{wrdata[24], wrdata[21:20], wrdata[16:3]}`（17 位），读出重排为 `{7'b0, [16], 2'b0, [15:14], 3'b0, [13:0], 3'b0}`。Spike 的 basic_csr_t 会原样存储 32 位，导致 read-back 与 RTL 不同。

### Note 5: dicad1 generate-block 条件

dicad1 的位宽取决于 `ICACHE_ECC` 参数：
- `ICACHE_ECC == 1`：[6:0] 有效（ECC），读出 `{25'b0, dicad1[6:0]}`
- `ICACHE_ECC == 0`：[3:0] 有效（Parity），读出 `{28'b0, dicad1[3:0]}`

当前 EH2 config 默认 ICACHE_ECC=1。

### Note 6: meihap 只读组合 CSR

meihap 不是普通的 R/W CSR：
- 写入 meicpct (0xBCA) 时，HW 捕获 `pic_claimid[7:0]` 到 `meihap[9:2]`
- 读出时组合 `{meivt[31:10], meihap[9:2], 2'b0}`
- 直接 CSRW 到 meihap 无效（read-only 地址 0xFC8）

当前 Spike 用 basic_csr_t 注册了 meihap，允许任意写入，这与 RTL 行为不一致。

### Note 7: mhartstart W1-only (sticky)

mhartstart 写入时只能将 bit 置 1，不能清 0：`mhartstart_ns[1] = wrdata[1] | mhartstart[1]`。bit[0] 硬连线为 1。

### Note 8: mnmipdel 值约束

mnmipdel [1:0] 不允许值 `2'b00`（全代理关闭），写入 0 时忽略写操作保留原值。NUM_THREADS==1 时始终忽略写入。

---

## 3. fixup_csr 当前覆盖情况

已在 `spike_cosim.cc:fixup_csr()` 中实现的 CSR（6 个）：
1. ✅ mstatus (0x300) — 标准
2. ✅ misa (0x301) — 标准
3. ✅ mtvec (0x305) — 标准
4. ✅ mcause (0x342) — 标准
5. ✅ mrac (0x7C0) — 自定义
6. ✅ mpmc (0x7C6) — 自定义
7. ✅ meivt (0xBC8) — 自定义
8. ✅ meipt (0xBC9) — 自定义
9. ✅ meicurpl (0xBCC) — 自定义
10. ✅ meicidpl (0xBCB) — 自定义
11. ✅ mscause (0x7FF) — 自定义

**缺失的 fixup**（需新增，按优先级排序）：

### P0（最高优先级 — 5 个）

| CSR | 理由 |
|-----|------|
| **mfdc** (0x7F9) | 位反转/重排逻辑导致任何 CSRRW 都会 mismatch；`riscv_csr_test`、`riscv_csr_hazard_test`、`riscv_debug_csr_test`、`riscv_debug_during_csr_test` 全部引用此 CSR |
| **mcgc** (0x7F8) | bit[9] 反转逻辑；与 mfdc 同组，同类测试均会触发 |
| **micect** (0x7F0) | threshold saturation 逻辑；`riscv_csr_test`、`riscv_mem_error_test` 引用 |
| **meihap** (0xFC8) | 当前 basic_csr_t 允许写入 read-only CSR，写后读不一致；`riscv_interrupt_test`、`riscv_irq_*` 系列引用 |
| **mcpc** (0x7C2) | 读始终返回 0，但 Spike basic_csr_t 保存写入值原样返回；`riscv_csr_test` 引用 |

### P1（中等优先级）

miccmect, mdccmect, mdeau, mdseac, meicpct, mip (ext bits), mie (ext bits)

### P2（低优先级 — debug-mode only 或 timer）

mfdht, mfdhs, dmst, dicawics, dicad0, dicad0h, dicad1, dicago, mhartstart, mnmipdel, mhartnum, mitcnt0, mitcnt1, mitb0, mitb1, mitctl0, mitctl1

---

## 4. P0 推荐清单及理由

| 排名 | CSR | 原因 |
|------|-----|------|
| 1 | **mfdc** (0x7F9) | 位反转/重排最复杂，任何 CSR 测试写 mfdc 必然 mismatch。cosim:disabled 的 `riscv_csr_test`（涉及全部 custom CSR）、`riscv_csr_hazard_test`、`riscv_debug_csr_test`、`riscv_debug_during_csr_test` 都会触发 |
| 2 | **mcgc** (0x7F8) | 同样有位反转逻辑，与 mfdc 一起在所有 CSR 扫描测试中被触发 |
| 3 | **micect** (0x7F0) | threshold saturation 使得写入 > 26 的值后 read-back 不一致；`riscv_csr_test` 和 `riscv_mem_error_test` 都会触发 |
| 4 | **meihap** (0xFC8) | read-only CSR 被 basic_csr_t 误注册为 R/W，写后读不一致；所有中断测试 (`riscv_interrupt_test`, `riscv_irq_*`) 读取此 CSR |
| 5 | **mcpc** (0x7C2) | 读始终返回 0 但 Spike 保存写入值；`riscv_csr_test` 直接写读此 CSR 会 mismatch |

---

## 5. 文件位置索引

| 文件 | 路径 | 内容 |
|------|------|------|
| TLU CTL (per-thread CSR) | `Cores-VeeR-EH2/design/dec/eh2_dec_tlu_ctl.sv` | mscause, mpmc, meivt, meihap, meicurpl, meicidpl, meicpct, meipt, dcsr, dpc, dicawics, dicad0/0h/1, dicago, mfdhs, mcpc, mdeau, mdseac, timer CSRs |
| TLU TOP (global CSR) | `Cores-VeeR-EH2/design/dec/eh2_dec_tlu_top.sv` | mcgc, mfdc, mrac, micect, miccmect, mdccmect, mfdht, mhartstart, mnmipdel, mhartnum |
| CSR decode | `Cores-VeeR-EH2/design/dec/eh2_dec_csr.sv` | 地址→信号 decode，包括 dmst |
| DEF 包 | `Cores-VeeR-EH2/design/include/eh2_def.sv` | `eh2_csr_tlu_pkt_t` 结构体（CSR read select 信号） |
| Spike cosim | `dv/cosim/spike_cosim.cc` | `initial_proc_setup()` (28 个 set_csr) + `fixup_csr()` |
| CSR description | `dv/uvm/core_eh2/riscv_dv_extension/csr_description.yaml` | riscv-dv CSR 字段描述 |
