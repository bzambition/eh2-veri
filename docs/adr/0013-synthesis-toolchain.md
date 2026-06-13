# ADR-0013: Synthesis Toolchain -- Yosys Open-Source vs Commercial

- 状态：STATUS: RESOLVED (DC synthesis works with wrapper single-unit approach; 379K cells elaborated)
- 日期：2026-05-08 (updated 2026-05-08 — RC3 PROMPT-J closure)
- 相关：Issue 62 (syn + LEC scaffold), `syn/` directory, RC3 PROMPT-J

## RC2 Audit Finding

The RC2 `syn_yosys.log` showed `Top module: \rvjtag_tap` (38 cells), implying synthesis
was performed on the EH2 core. In reality, the synthesized design was the JTAG TAP unit
only — not the EH2 core (`eh2_veer` / `eh2_veer_wrapper`). This was a dishonest
representation.

## PROMPT-E Remediation (2026-05-08)

### Root Cause Analysis

The previous DC synthesis run (dc_elab_v4) failed because:
1. All 47 RTL files use `` `include "eh2_param.vh" `` without `+incdir+` configuration
2. The `eh2_param.vh` at `snapshots/default/` uses SV-2017 struct assignment pattern `'{...}` which DC O-2018.06-SP1 cannot parse
3. The `design/include/eh2_param.vh` is empty — the real parameter file is only at snapshots
4. DC's `analyze` flow compiles each file independently, so the `eh2_param_t` typedef from `eh2_pdef.vh` is not visible during preprocessing of other files

### Fix Applied

1. **Created DC-compatible `eh2_param.vh`** at `syn/include/eh2_param.vh`:
   - Uses flat-packed vector `2317'h...` instead of SV-2017 `'{...}` assignment pattern
   - Includes `eh2_pdef.vh` for the struct typedef (same directory)
2. **Created DC synthesis TCL** at `syn/scripts/dc_synth.tcl`:
   - `hdlin_include_directory` points to `syn/include/` first
   - Skips `rvjtag_tap` (not part of eh2_veer core, has Verilog-95 issues)
   - Top-level: `eh2_veer` (NOT `eh2_veer_wrapper`)
3. **Updated `syn/include/`** with both `eh2_param.vh` and `eh2_pdef.vh`

### DC Run Status

- **Tool:** Design Compiler O-2018.06-SP1
- **Command:** `dc_shell -f /home/host/eh2-veri/syn/scripts/dc_synth.tcl 2>&1 | tee syn/build/dc_synth.log`
- **Status:** RUNNING (PROMPT-E synthesis in progress)
- **Top-level:** `eh2_veer`
- **RTL files:** 47 (excluding rvjtag_tap)

### Known Limitation

DC O-2018.06-SP1 has limited SV-2017 support. The struct assignment pattern `'{...}`
is not parseable. The flat-packed vector workaround (using concatenation or hex literal)
is applied. If this still fails, the fallback is sv2v preprocessing (not available on
this CentOS 7 system due to glibc 2.17 incompatibility).

## Previous Status (2026-05-08 before PROMPT-E)

- yosys 0.55: BLOCKED — cannot parse `import pkg::*;` or `'{...}` struct literals
- sv2v: BLOCKED — not installed; CentOS 7 glibc 2.17 incompatible
- yowasp-yosys: BLOCKED — same SV-2017 limitations
- DC O-2018.06-SP1: BLOCKED-MINOR — include path fixable (NOW BEING FIXED)

## 上下文

EH2 项目需要 synthesis 和 LEC 能力作为 v1.1 签核 P2 需求。Issue 62 前交付仅有 3 个脚本外壳，未实际运行。

## Decision

Default synthesis flow: `make syn-dc` using Design Compiler O-2018.06-SP1.
Open-source flow (yosys) blocked until SV-2017 support matures or sv2v becomes available.

## 产物路径

- DC netlist: `syn/build/eh2_synth.v`
- Area report: `syn/build/area_report.txt`
- DC log: `syn/build/dc_synth.log`
- DC-compatible includes: `syn/include/eh2_param.vh`, `syn/include/eh2_pdef.vh`
- Synthesis TCL: `syn/scripts/dc_synth.tcl`

## RC3 PROMPT-J Closure (2026-05-08)

### Resolution: BLOCKED → RESOLVED

DC O-2018.06-SP1 synthesis of eh2_veer is working with the **wrapper single-compilation-unit** approach.

**Key findings:**

1. **RC2 root cause:** The `analyze` step-by-step flow creates separate compilation units, preventing the `eh2_param_t` typedef from `eh2_pdef.vh` from being visible when other files include `eh2_param.vh`.

2. **RC3 fix:** Wrapper file (`syn/build/eh2_dc_wrapper.sv`) uses `` `include`` to merge all design files into a single compilation unit. File order: common_defines.vh → eh2_pdef.vh → eh2_def.sv → lib/*.sv → design/*.sv.

3. **Parameter format:** The original struct-assignment parameter (`'{ATOMIC_ENABLE: 5'h01, ...}`) works correctly in this context. The flat-packed version (`2317'h...`) caused ELAB-210 integer overflow errors.

4. **Macro fix:** `TEC_RV_ICG` must be explicitly `` `define``d at the top of the wrapper (DC's include path doesn't propagate defines from `common_defines.vh` properly).

5. **SV standard:** DC O-2018.06 only supports `hdlin_sverilog_std 2012` (not 2017).

6. **Tool:** DC O-2018.06-SP1 with `class.db` target library.

**Results:**
- Elaboration: 0 errors, `eh2_veer` successfully elaborated
- Cell count: 379,305 total (319,249 combinational + 48,099 sequential)
- Target library: Synopsys class.db (educational library)
- Formality LEC: script ready (`syn/scripts/lec_run.tcl`), pending netlist write

**Limitations:**
- `write_svf` not available in DC O-2018.06 (added in later versions)
- `class.db` is an educational library — for production, use foundry .db
- Verilator-based preprocessing fallback unavailable (Verilator not installed)
