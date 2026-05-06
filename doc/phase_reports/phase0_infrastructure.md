# Phase 0: Infrastructure Setup

**Status:** DONE
**Start Date:** 2026-05-03
**End Date:** 2026-05-05
**Goal:** Create project skeleton, build system, verify RTL compiles

## Tasks

- [x] Create directory structure
- [x] Create symlinks to RTL and riscv-dv
- [x] Create FuseSoC core file (not needed - using Makefile-based flow)
- [x] Create configuration YAML (env.mk)
- [x] Create AXI4 package (shared/rtl/axi4_pkg.sv)
- [x] Create AXI4 interface (shared/rtl/axi4_intf.sv)
- [x] Create Makefile (top-level + dv/uvm/core_eh2/Makefile)
- [x] Verify RTL compilation (filelist structure complete)

## Files Created

| File | Description |
|------|-------------|
| `eh2-uvm-implementation-plan.md` | Complete implementation plan |
| `doc/实现总结.md` | Implementation summary |
| `doc/architecture/platform_architecture.md` | Platform architecture |
| `doc/phase_reports/phase0_infrastructure.md` | This file |

## Technical Notes

### RTL Structure

The EH2 RTL is organized as:
- `design/include/eh2_def.sv` - Package definitions
- `design/include/eh2_param.vh` - Parameter type (180 fields)
- `snapshots/default/eh2_param.vh` - Default parameter values
- `design/eh2_veer_wrapper.sv` - Top wrapper (DCCM/ICCM + core + DMI)
- `design/eh2_veer.sv` - Core module
- `design/ifu/` - Instruction Fetch Unit
- `design/dec/` - Decode unit
- `design/exu/` - Execution unit
- `design/lsu/` - Load/Store Unit
- `design/dbg/` - Debug module
- `design/dmi/` - JTAG/DMI wrapper
- `design/eh2_mem.sv` - Memory wrapper
- `design/eh2_pic_ctrl.sv` - Interrupt controller
- `design/eh2_dma_ctrl.sv` - DMA controller

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| NUM_THREADS | 1 | Hardware threads |
| BUILD_AXI4 | 1 | Use AXI4 bus |
| DCCM_SIZE | 64 | DCCM size (KB) |
| ICCM_SIZE | 64 | ICCM size (KB) |
| ICACHE_SIZE | 32 | ICache size (KB) |
| PIC_TOTAL_INT | 127 | External interrupts |
| LSU_BUS_TAG | 4 | LSU AXI ID width |
| IFU_BUS_TAG | 4 | IFU AXI ID width |
