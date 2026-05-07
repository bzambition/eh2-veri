# Issue 05: testlist 恢复 cosim 默认开启

Status: done (Phase 1+3 完成)
Phase: 1
Type: AFK
Blocked by: Issue 04

## 要做什么

把 `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml` 中所有 `cosim: disabled` 标记，根据 ADR-0004 完成情况逐条审查，能恢复的全部恢复。

### 当前状态（grep cosim: disabled）

```bash
grep -A1 "cosim: disabled" dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml
```

预计影响测试（需要确认实际 yaml）：
- `riscv_random_instr_test`（中断启用，需要确认 cosim 中断处理通了）
- `riscv_csr_test`（自定义 CSR 访问，需要 Phase 3 的 fixup_csr 才能恢复）
- `riscv_csr_hazard_test`
- `riscv_exception_stream_test`
- 其它 4–5 个

### 恢复策略

| 分类 | 处理 |
|------|------|
| 仅因 wb 关联问题禁用 | Phase 1 后**直接恢复 cosim** |
| 因 EH2 自定义 CSR 不模型禁用 | Phase 1 保持 disabled，Phase 3 处理 |
| 因 NUM_THREADS=2 禁用 | 永久 disabled（ADR-0003） |

每条 disabled 项必须在 yaml 注释中标明 reason 与 unblock 条件。

## 验收标准

- [ ] 至少 5 个 random test 的 cosim 恢复（mismatch == 0）
- [ ] 所有保留 disabled 的 test 都有 reason 注释
- [ ] testlist 改动通过 yaml 语法检查

## 阻塞依赖

- Issue 04
