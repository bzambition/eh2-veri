已完成调研报告，路径：

`/home/host/eh2-veri/.scratch/cosim-correctness/issue-12-bitmanip/RECON.md`

推荐方案：**A**。原因是 Spike 已经解析并链接了 Zba/Zbb/Zbc/Zbs；过滤 Zb* 会绕过本 issue 要恢复的核心比对价值。注意：正常 UVM cosim 路径已经传入 `rv32imac_zba_zbb_zbc_zbs`，所以 commit A 更像是补齐 fallback 与可观测日志，再用实际 cosim run 证明。

是否建议下一步让我直接动手 commit A：**建议**。commit A 应只改 `dv/cosim/spike_cosim.cc`，不动 testlist，内容控制在 fallback ISA 字符串和初始化日志。