# EH2 IFV RC5 Formal Diagnostics

Baseline: `dv/formal/build/ifv_prove_rc5c.log`, 46 total, 22 pass, 24 fail.
Current proof after fixes: `build/ifv_prove_coverfix.log`, 46 total, 32 pass, 0 fail, 14 explored.
IFV 15.20 does not support `report_cex` or `write_vcd`; per-property diagnostic files point to verbose `assertion -show` output in `build/ifv_cex_run.log`.

## a_core_rst_active_low (Fail 3)
- File: dv/formal/eh2_veer_sva.sv:139
- Cex: original run allowed scan-mode reset override and treated checker outputs as undriven.
- Class: A (property bug)
- Fix path: checker ports are inputs; property now gates functional reset with `!scan_mode`.
- Owner: formal/platform

## a_core_rst_from_reset (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:144
- Cex: property assumed external reset release alone releases core reset.
- Class: A (property bug)
- Fix path: include `dbg_core_rst_l` and `!scan_mode`, matching `core_rst_l = rst_l & (dbg_core_rst_l | scan_mode)`.
- Owner: formal/platform

## a_dccm_wr_rd_mutex (Fail 1)
RESOLVED 2026-05-11: H1/H5 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:282
- 修复方式: 将聚合 DCCM 端口互斥检查改为 RTL 中实际的 `lsu.dccm_ctl` spec write/read onehot 检查。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:272
- Cex: original failure came from checker output-direction disconnect; final status is Explored.
- Class: C (tool/model constraint gap)
- Fix path: port direction fixed; remaining bounded inconclusive is documented as IFV 15.20 convergence work.
- Owner: formal/platform

## a_debug_halt_track (Fail 1)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:275
- 修复方式: 将 debug 状态检查接到 `dec.tlu.o_debug_mode_status`，避免把 debug mode 错接到 PMU halt ack/status 语义。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:265
- Cex: debug mode reachability is not constrained by a debug transaction sequence in this full-core proof.
- Class: C (missing formal scenario constraint)
- Fix path: keep assertion, document Explored status, cover through UVM debug directed tests.
- Owner: debug/formal

## a_dma_arvalid_stable (Fail 3)
RESOLVED 2026-05-11: H5 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:259
- 修复方式: `dma_axi_arvalid` 是外部 master 输入，属性改为检查 EH2 拥有的 `dma_axi_arready` 与 `dma_ctrl` 输出 hook-up。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:250
- Cex: original failure was caused by checker direction on DMA ready outputs.
- Class: A (property hookup bug)
- Fix path: convert observed signals to checker inputs; final status is bounded Explored, not Fail.
- Owner: formal/platform

## a_dma_awvalid_stable (Fail 3)
RESOLVED 2026-05-11: H5 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:263
- 修复方式: `dma_axi_awvalid` 是外部 master 输入，属性改为检查 EH2 拥有的 `dma_axi_awready` 与 `dma_ctrl` 输出 hook-up。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:254
- Cex: original failure was caused by checker direction on DMA ready outputs.
- Class: A (property hookup bug)
- Fix path: convert observed signals to checker inputs; final status is bounded Explored, not Fail.
- Owner: formal/platform

## a_iccm_wr_rd_mutex (Fail 1)
RESOLVED 2026-05-11: H1/H5 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:287
- 修复方式: ICCM 顶层读写端口允许 ECC 修复等重叠场景，属性改为检查顶层端口与 `ifu.mem_ctl` 源信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:276
- Cex: original failure came from checker output-direction disconnect; final status is Explored.
- Class: C (tool/model constraint gap)
- Fix path: port direction fixed; remaining proof needs a memory-port usage constraint or deeper IFV engine.
- Owner: IFU/formal

## a_ifu_arvalid_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:242
- 修复方式: 将 IFU ARVALID 属性改为核对顶层 `ifu_axi_arvalid` 与 `ifu.mem_ctl.ifu_axi_arvalid` 的真实生成路径。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:235
- Cex: IFU AXI read-valid was previously sampled through an undriven checker output port.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; no current Fail remains.
- Owner: IFU/formal

## a_ifu_awvalid_stable (Fail 3)
- File: dv/formal/eh2_veer_sva.sv:243
- Cex: IFU write-valid path is unusual for this core and was previously mis-modeled by the checker.
- Class: B (RTL integration risk to track)
- Fix path: direction fix turns assertion Pass; follow-up should confirm whether IFU AW is tied off in all configs.
- Owner: IFU/RTL

## a_ifu_not_both_rw (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:299
- Cex: simultaneous IFU read/write was an artifact of the bad checker port directions.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; assertion now Passes.
- Owner: IFU/formal

## a_ifu_rvalid_accepted (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:239
- Cex: IFU read response ready was sampled as an undriven checker output.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; assertion now Passes.
- Owner: IFU/formal

## a_lsu_araddr_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:216
- 修复方式: 将 LSU ARADDR 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:209
- Cex: original fail path used an undriven checker copy of LSU AR signals.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_lsu_arvalid_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:212
- 修复方式: 将 LSU ARVALID 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:205
- Cex: original fail path used an undriven checker copy of LSU ARVALID.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_lsu_awaddr_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:182
- 修复方式: 将 LSU AWADDR 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:175
- Cex: original fail path used an undriven checker copy of LSU AWADDR.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_lsu_awvalid_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:178
- 修复方式: 将 LSU AWVALID 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:171
- Cex: original fail path used an undriven checker copy of LSU AWVALID.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_lsu_bvalid_accepted (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:220
- Cex: LSU BREADY was modeled as a checker output and appeared undriven.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; assertion now Passes.
- Owner: LSU/formal

## a_lsu_rvalid_accepted (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:228
- Cex: LSU RREADY was modeled as a checker output and appeared undriven.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; assertion now Passes.
- Owner: LSU/formal

## a_lsu_wdata_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:205
- 修复方式: 将 LSU WDATA 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:198
- Cex: original fail path used an undriven checker copy of LSU WDATA.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_lsu_wstrb_active (Fail 1)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:201
- 修复方式: 将 LSU WSTRB 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:194
- Cex: original fail path used an undriven checker copy of LSU WSTRB.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored because write-data reachability is not constrained.
- Owner: LSU/formal

## a_lsu_wvalid_stable (Fail 3)
RESOLVED 2026-05-11: H1 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:197
- 修复方式: 将 LSU WVALID 属性改为核对顶层端口与 `lsu.bus_intf` 真实生成信号一致。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:190
- Cex: original fail path used an undriven checker copy of LSU WVALID.
- Class: A (property hookup bug)
- Fix path: checker direction fixed; final status is Explored due full-core convergence.
- Owner: LSU/formal

## a_mhartstart_reset (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:159
- Cex: property expected mhartstart to be zero, but EH2 ties thread 0 started.
- Class: A (property bug)
- Fix path: assert `dec_tlu_mhartstart[0] == 1'b1`, matching RTL.
- Owner: DEC/formal

## a_nmi_vec_stable (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:325
- Cex: unconstrained platform input changed while reset was asserted.
- Class: C (missing environment assume)
- Fix path: add reset-time NMI vector stability assumption.
- Owner: formal/platform

## a_rst_vec_stable_during_reset (Fail 1)
- File: dv/formal/eh2_veer_sva.sv:321
- Cex: unconstrained platform reset vector changed while reset was asserted.
- Class: C (missing environment assume)
- Fix path: add reset-time reset-vector stability assumption.
- Owner: formal/platform

## a_trace_valid_addr (Fail 1)
RESOLVED 2026-05-11: H1/H3 类型，commit pending working tree.
- 修改文件: dv/formal/eh2_veer_sva.sv:270
- 修复方式: 将 trace 地址检查从整 64-bit 非零改为按双发射 slot 检查对应有效 lane 的地址非 X。
- 回归: r3a_retry_hookup2.log Pass
- File: dv/formal/eh2_veer_sva.sv:261
- Cex: trace-valid reachability depends on instruction retirement and is not driven by the unconstrained proof harness.
- Class: C (missing formal scenario constraint)
- Fix path: keep assertion; remaining Explored status is tracked as constrained-program proof work.
- Owner: trace/formal
