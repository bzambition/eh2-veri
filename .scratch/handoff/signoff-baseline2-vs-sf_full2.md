# Sign-off 比对：sf_baseline2 vs sf_full2

日期：2026-05-07

## 结论

**两次结果完全一致**。sf_baseline2 是用 `SIGNOFF_ITERATIONS=1` 重跑的干净 baseline，与 sf_full2 对齐。

## 对比

| 项目 | sf_full2 (15:04) | sf_baseline2 (19:36) |
|------|-------------------|----------------------|
| status | PASS | PASS |
| smoke | 1/1 PASS | 1/1 PASS |
| directed | 3/3 PASS | 3/3 PASS |
| cosim | 4/4 PASS | 4/4 PASS |
| riscvdv | 32/32 PASS | 32/32 PASS |
| cosim_disabled_tests | 34 | 34 |
| cosim_disabled 列表 | 一致 | 一致 |

## 注意事项

- sf_baseline（无 SIGNOFF_ITERATIONS=1）跑了 185 个 test（testlist.yaml 中 iterations 字段全展开），其中 114 个 FAIL（多 seed 随机失败，不是回归）
- sf_full2 的命令行带了 `--iterations 1`，所以只跑 32 个（每个 test 1 iteration）
- **后续所有 signoff 应统一使用 `SIGNOFF_ITERATIONS=1`**
