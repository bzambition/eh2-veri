# Issue 12 RECON - bitmanip / Zb* cosim

Scope: research only. No RTL/DV/vendor/script/doc/testlist changes, no simulation, no commit.

## 1. Spike processor construction and ISA / priv / varch strings

`dv/cosim/spike_cosim.cc` does not pass an ISA string literal directly to `processor_t`; it builds an `isa_parser_t` first:

- `dv/cosim/spike_cosim.cc:34`: `isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");`
- `dv/cosim/spike_cosim.cc:35-36`: `processor = std::make_unique<processor_t>(isa_parser.get(), DEFAULT_VARCH, this, 0, false, log_file, std::cerr);`

Current literal values visible on the construction path:

- fallback ISA string in the C++ DPI factory: `dv/cosim/spike_cosim.cc:1209` has `std::string isa_string = "rv32imac";`
- config override: `dv/cosim/spike_cosim.cc:1229` replaces it when `key == "isa"`.
- priv string: `dv/cosim/spike_cosim.cc:34` passes `"MU"`.
- varch string: `dv/cosim/spike_cosim.cc:36` passes `DEFAULT_VARCH`; in the spike-cosim installed header used by the EH2 Makefile include path, `/home/host/spike-cosim/install/include/riscv/config.h:16-17` defines `DEFAULT_VARCH "vlen:128,elen:64"`.

Normal UVM cosim path already overrides the C++ fallback with Zb enabled:

- `dv/uvm/core_eh2/tests/core_eh2_base_test.sv:196-198` sets `isa_string = "rv32imac_zba_zbb_zbc_zbs";`
- `dv/uvm/core_eh2/tests/core_eh2_base_test.sv:106-114` formats `isa=%s;...` into `cosim_cfg_str` and assigns it to the scoreboard.
- `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:666-670` calls `riscv_cosim_init(cosim_config)`.

Conclusion: direct/fallback DPI init is `rv32imac`, but the normal UVM test path is already `rv32imac_zba_zbb_zbc_zbs`.

## 2. Whether Zb* opcodes are linked into Spike / libcosim.so

Prefix-named headers do not exist:

```text
find /home/host/spike-cosim/riscv/insns -name 'zba_*.h' -> 0
find /home/host/spike-cosim/riscv/insns -name 'zbb_*.h' -> 0
find /home/host/spike-cosim/riscv/insns -name 'zbc_*.h' -> 0
find /home/host/spike-cosim/riscv/insns -name 'zbs_*.h' -> 0
```

But the opcode headers exist under instruction names and check the right extensions:

- `/home/host/spike-cosim/riscv/insns/sh1add.h:1` uses `require_extension(EXT_ZBA);`
- `/home/host/spike-cosim/riscv/insns/andn.h:1` uses `require_either_extension(EXT_ZBB, EXT_ZBKB);`
- `/home/host/spike-cosim/riscv/insns/clmul.h:1` uses `require_either_extension(EXT_ZBC, EXT_ZBKC);`
- `/home/host/spike-cosim/riscv/insns/bclr.h:1` uses `require_extension(EXT_ZBS);`
- `/home/host/spike-cosim/riscv/isa_parser.cc:119-126` recognizes `zba`, `zbb`, `zbc`, `zbs` and sets the corresponding extension bits.

Build-system linkage evidence:

- `/home/host/spike-cosim/riscv/riscv.mk.in:347-423` defines `riscv_insn_ext_b`, including representative Zb instructions such as `add_uw`, `andn`, `sh1add`, `clmul`, `bclr`, `bset`, `sext_b`, `sext_h`.
- `/home/host/spike-cosim/riscv/riscv.mk.in:1306-1316` includes `$(riscv_insn_ext_b)` in `riscv_insn_list`.
- `/home/host/spike-cosim/riscv/riscv.mk.in:52-72` adds `$(riscv_gen_srcs)` to `riscv_srcs`.
- `/home/host/spike-cosim/riscv/riscv.mk.in:1325-1335` generates `.cc` files from `insns/%.h`.
- top-level EH2 `Makefile:246-275` builds `build/libcosim.so`; specifically `Makefile:257-263` extracts `/home/host/spike-cosim/install/lib/libriscv.a`, and `Makefile:271-275` links it into `build/libcosim.so`.

Binary/link precision checks:

- `ar t /home/host/spike-cosim/install/lib/libriscv.a` contains `andn.o`, `sh1add.o`, `clmul.o`, `bclr.o`.
- `nm -D build/libcosim.so` contains `_Z12rv32i_sh1addP11processor_t6insn_tm`, `_Z10rv32i_andnP11processor_t6insn_tm`, `_Z11rv32i_clmulP11processor_t6insn_tm`, `_Z10rv32i_bclrP11processor_t6insn_tm`.

Conclusion: yes, representative Zba/Zbb/Zbc/Zbs opcode implementations are compiled into the Spike archive and linked into `build/libcosim.so`. The filenames are not `zba_*.h` etc.

## 3. Current `riscv_bitmanip_test` disabled path

`dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml:64-76`:

- `:64`: `- test: riscv_bitmanip_test`
- `:67-69`: `gen_opts: '+instr_cnt=5000 +boot_mode=m +directed_instr_0=eh2_bitmanip_stream,20 ...'`
- `:71-73`: `sim_opts: '+max_cycles=500000 +timeout_ns=50000000 ...'`
- `:75`: `cosim: disabled`
- `:76`: `skip_in_signoff: true`

## 4. EH2 RTL Zb subset support

Configuration says the default enabled subset is Zba/Zbb/Zbc/Zbs:

- `eh2_configs.yaml:29-32`: default enables `BITMANIP_ZBA/ZBB/ZBC/ZBS`.
- `eh2_configs.yaml:50-53`: minimal disables all four.
- `eh2_configs.yaml:71-74`: dual_thread enables all four.
- `eh2_configs.yaml:90-93`: ahb_lite enables all four.
- Generated default RTL snapshot confirms old draft groups are off: `rtl/snapshots/default/eh2_param.vh:9-16` sets `BITMANIP_ZBA=1`, `ZBB=1`, `ZBC=1`, `ZBS=1`, and `ZBE/ZBF/ZBP/ZBR=0`.

RTL decode and execute evidence:

- `rtl/design/dec/eh2_dec_decode_ctl.sv:1162-1166` and `:1194-1198` classify `zbb/zbs/zbc/zba` as `BITMANIPU`.
- `rtl/design/dec/eh2_dec_decode_ctl.sv:1834-1849` gates Zbb and Zbs legality with `pt.BITMANIP_ZBB/ZBS`.
- `rtl/design/dec/eh2_dec_decode_ctl.sv:1870-1878` gates Zbc legality with `pt.BITMANIP_ZBC`.
- `rtl/design/dec/eh2_dec_decode_ctl.sv:1918-1926` gates Zba legality with `pt.BITMANIP_ZBA`.
- `rtl/design/dec/eh2_dec_decode_ctl.sv:1967-1969` combines all bitmanip legality terms.
- `rtl/design/dec/eh2_dec_decode_ctl.sv:3685-3718` decodes Zbb examples (`clz`, `ctz`, `cpop`, `sext_b`, `sext_h`, `min/max`, `pack`, `rol/ror`, `zbb`).
- `rtl/design/dec/eh2_dec_decode_ctl.sv:3720-3729` decodes Zbs examples (`bset/bclr/binv/bext`, `zbs`).
- `rtl/design/dec/eh2_dec_decode_ctl.sv:3739-3745` decodes Zbc examples (`clmul/clmulh/clmulr`, `zbc`).
- `rtl/design/dec/eh2_dec_decode_ctl.sv:3791-3797` decodes Zba examples (`sh1add/sh2add/sh3add`, `zba`).
- `rtl/design/exu/eh2_exu_alu_ctl.sv:110-138` enables Zbb ALU signals when `pt.BITMANIP_ZBB == 1`.
- `rtl/design/exu/eh2_exu_alu_ctl.sv:150-155` enables Zbs ALU signals when `pt.BITMANIP_ZBS == 1`.
- `rtl/design/exu/eh2_exu_alu_ctl.sv:188-193` enables Zba ALU signals when `pt.BITMANIP_ZBA == 1`.
- `rtl/design/exu/eh2_exu_mul_ctl.sv:104-108` enables Zbc carry-less multiply signals when `pt.BITMANIP_ZBC == 1`.
- `rtl/design/include/eh2_def.sv:217-239`, `:307-333`, `:349-352`, and `:417-421` define the packet fields used by these decoders/execution units.

Generator-side note: `dv/uvm/core_eh2/riscv_dv_extension/riscv_core_setting.tpl.sv:29-48` exposes only RV32I/M/A/C plus RV32ZBA/ZBB/ZBC/ZBS to riscv-dv. `dv/uvm/core_eh2/riscv_dv_extension/eh2_directed_instr_lib.sv:118-136` says the directed `eh2_bitmanip_stream` currently emits a trimmed Zba/Zbb subset, with Zbc/Zbs arrays empty because the host GCC 11.1 assembler does not support them.

Conclusion: for the default EH2 verification configuration, the intended RTL subset is Zba/Zbb/Zbc/Zbs. Legacy draft groups Zbe/Zbf/Zbp/Zbr exist in RTL plumbing but are off in the default generated parameters and are not present in `eh2_configs.yaml`.

## 5. Feasibility of Scheme A: enable Zb* in Spike

Feasible for Spike legality/disasm/execute:

- Spike parses `zba/zbb/zbc/zbs`: `/home/host/spike-cosim/riscv/isa_parser.cc:119-126`.
- Representative insn headers require those extension bits and implement execution: `/home/host/spike-cosim/riscv/insns/sh1add.h:1-2`, `/home/host/spike-cosim/riscv/insns/andn.h:1-2`, `/home/host/spike-cosim/riscv/insns/clmul.h:1-6`, `/home/host/spike-cosim/riscv/insns/bclr.h:1-3`.
- Those objects are linked into `build/libcosim.so` as shown in section 2.

Important caveat: changing only `dv/cosim/spike_cosim.cc:1209` from fallback `"rv32imac"` to `"rv32imac_zba_zbb_zbc_zbs"` helps only direct/fallback DPI init. The normal UVM path already passes `"rv32imac_zba_zbb_zbc_zbs"` via `dv/uvm/core_eh2/tests/core_eh2_base_test.sv:196-198` and `:106-114`.

Therefore, if a cosim-enabled `riscv_bitmanip_test` still fails, the missing piece is not obviously Spike opcode linkage or ISA parsing. UNKNOWN: need an actual cosim-enabled bitmanip run to determine whether the remaining failure is trap-rate mismatch, DUT timeout/hang, toolchain/generated-instruction mismatch, or another scoreboard issue.

## 6. Cost of Scheme B: filter Zb* before cosim compare

Current trace/cosim enqueue path:

- Trace monitor creates i0 items and writes them at `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:82-112`; the actual `ap.write(txn)` is `:111`.
- Trace monitor creates i1 items and writes them at `dv/uvm/core_eh2/common/trace_agent/eh2_trace_monitor.sv:114-144`; the actual `ap.write(txn)` is `:143`.
- Env connects trace monitor to cosim at `dv/uvm/core_eh2/env/core_eh2_env.sv:121-124`.
- The same trace monitor also feeds the double-fault scoreboard at `dv/uvm/core_eh2/env/core_eh2_env.sv:136-137`; filtering inside `trace_monitor` would hide those instructions from non-cosim consumers too.
- Cosim scoreboard receives from `trace_fifo`, pushes into `pending_trace_q`, and processes it at `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:192-203`.
- It pops and compares at `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:318-327`.
- `compare_instruction()` calls `riscv_cosim_step()` at `dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:546-630`.

There is no existing skip helper: `rg compare_skip_item` under `dv/uvm/core_eh2` returned no hits.

Estimated implementation size:

- blunt trace-monitor filter for one opcode class: about 35-60 LOC, because it needs a helper to decode/mask the Zb encodings plus two call sites before `ap.write(txn)`.
- cleaner cosim-only skip in the scoreboard: about 50-80 LOC, because it should preserve the trace stream for other scoreboards, maintain counters/reporting, and avoid disturbing memory/async writeback queues.

Cost conclusion: B is low-to-medium code size but high verification cost, because it bypasses the exact bitmanip retire comparisons this issue is meant to enable.

## 7. Recommendation

Recommend Scheme A, not B.

Reason: Spike already has Zba/Zbb/Zbc/Zbs parser support and linked execution functions; filtering Zb* would remove the target instruction class from cosim coverage. The practical A work is to align/harden the fallback/default logging and then prove the existing Zb ISA path with a cosim-enabled bitmanip run.

## 8. Recommended commit split

Commit A: Spike-side enablement / observability, no testlist change.

- Modify `dv/cosim/spike_cosim.cc` only:
  - change the fallback at `:1209` from `"rv32imac"` to `"rv32imac_zba_zbb_zbc_zbs"`;
  - add a short initialization diagnostic showing resolved ISA, priv `"MU"`, and varch `DEFAULT_VARCH`, so acceptance can see Zb in logs.
- Do not modify `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`.
- Verification target after commit A: rebuild `build/libcosim.so`, run existing cosim regression, and do a manual bitmanip dry-run with command-line override rather than testlist unlock.

Commit B: unlock sign-off only after commit A proof.

- Modify `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`:
  - remove `cosim: disabled` at `:75`;
  - remove `skip_in_signoff: true` at `:76`.
- After a passing 3-seed bitmanip cosim run and full sign-off, update `CONTEXT.md:101` from RISK-10 OPEN/disabled to resolved.
- Optionally update `.scratch/cosim-correctness/issues/12-cosim-bitmanip-zb-extensions.md` status/acceptance checkboxes when closing the issue.

Do not implement trace filtering unless a later cosim run proves a specific unsupported opcode outside Zba/Zbb/Zbc/Zbs.

## 9. Estimated cost / wall time / owner

Estimated code churn:

- Commit A: about 5-15 LOC in `dv/cosim/spike_cosim.cc`.
- Commit B: about 2 deletions in `testlist.yaml`, plus 1-5 documentation/issue lines after sign-off.
- Total expected A+B: about 10-25 changed lines if no hidden behavioral fix is needed.

Wall-clock evidence:

- Current archived full sign-off: `build/sf_full2/signoff_report.md:3-6` says PASS, full profile, timestamp `2026-05-07T15:04:58`.
- Stage totals: `build/sf_full2/reports/smoke/regr.log:10` is `0s`; `build/sf_full2/reports/directed/regr.log:10` is `0s`; `build/sf_full2/reports/cosim/regr.log:10` is `1s`; `build/sf_full2/reports/riscvdv/regr.log:10` is `163s`.
- Report timestamps span roughly `15:02:13` to `15:04:58` across the archived full run (`build/sf_full2/reports/smoke/regr.log:3`, `build/sf_full2/reports/riscvdv/regr.log:3`), so current full wall time is about 165s on this machine/profile.

Post-B sign-off estimate: UNKNOWN. The current full run skips `riscv_bitmanip_test` (`build/sf_full2/signoff_report.md:36-41`). An archived no-cosim bitmanip run hit cycle timeout at `build/verify8_bitmanip/run/tests/riscv_bitmanip_test.1/sim_riscv_bitmanip_test_1.log:272266` and reports CPU time `94.290 seconds` at `:272297`. Need a fixed cosim-enabled run before predicting final full wall time; practical expectation is current ~3 minutes plus the bitmanip test runtime if it no longer times out.

Recommended owner: Codex can lead commit A and the first proof runs. If the bitmanip test still times out or mismatches after Spike Zb visibility is confirmed, escalate to a human RTL/DV owner because the remaining issue is no longer a simple Spike ISA-string fix.
