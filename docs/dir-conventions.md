# EH2 目录与工具产物规范

本文档定义 EH2 验证平台中 EDA 工具产物的落盘位置、清理方式和排查规则。
目标是让仓库根目录保持干净，同时保留可复现 sign-off、覆盖率和 LEC 结果。

## 基本原则

1. 仓库根目录只放源码、脚本、文档和少量顶层配置。
2. 可再生的大文件统一进入 `build/`、`syn/build/` 或对应子系统的 build 目录。
3. EDA 工具默认在当前工作目录生成的文件，必须通过脚本切换工作目录或显式输出路径收敛。
4. `build/r3b_final/` 是 v1.0.2 GA 交付物，不纳入自动清理。
5. `syn/build/lec_summary.txt` 是 R3-C/D LEC 闭环摘要，不纳入自动清理。
6. `.gitignore` 负责避免误提交，`scripts/clean_workspace.sh` 负责回收根目录残留。

## EDA 工具产物去向

所有 EDA 工具都必须在专用 run 目录中启动，不能依赖 `.gitignore` 遮住污染。

| 工具 / 流程 | 启动目录 | 正式输出 | 可清理残留 |
|---|---|---|---|
| VCS compile | `build/` 或脚本指定目录 | `build/simv`、`build/compile.log`、`build/csrc/` | 根目录 `csrc/`、`ucli.key`、`vc_hdrs.h` |
| VCS run | `build/<run>/` | 每个 test 目录下的 `sim_*.log`、`trr.yaml`、`report.json` | 根目录波形、散落 `*_seed*.log` |
| URG | `build/<run>/` | `build/<run>/cov_report/` 或 `build/r3b_cov_report/` | `build/cov.vdb.backup_*`、`build/cov.vdb.pre_*` |
| Design Compiler | `syn/build/dc_run/` 或 `syn/build/lec_blocklevel/run/dc/<module>/` | `syn/build/`、`syn/build/lec_blocklevel/synth/` | 根目录 `*.mr`、`*.pvk`、`*-verilog.*` |
| Formality | `syn/build/lec_blocklevel/run/fm/<label>/` | `syn/build/lec_blocklevel/lec_*.rpt`、`syn/build/lec_summary.txt` | `*.lck`、`*.fss`、`FM_WORK*`、`formality*.log` |
| Cadence IFV | `dv/formal/build/` | `dv/formal/build/ifv_*.log` | 根目录 `formalverifier.log` |
| Verdi / Novas | debug run 目录 | 用户指定波形数据库 | 根目录 `verdiLog/`、`novas.*`、`*.fsdb` |

每次 full sign-off、block-level LEC 或手动 Formality/IFV 运行后，执行：

```bash
make clean_workspace
```

只想确认会清什么时，执行：

```bash
make clean_workspace_dry
```

CI 或自动化 flow 如果只需要去掉工具锁文件，可以使用：

```bash
bash scripts/clean_workspace.sh --lck-only
```

## 推荐目录布局

| 路径 | 内容 | 是否可清理 |
|---|---|---|
| `rtl/` | RTL 引用、软链接和 LEC-only shim | 不自动清理 |
| `dv/` | UVM、formal、coverage、cosim 脚本 | 不自动清理 |
| `syn/scripts/` | DC/Formality 脚本 | 不自动清理 |
| `syn/build/` | 综合、LEC、block-level report | 可按任务清理，保留最终摘要 |
| `build/` | 仿真、sign-off、覆盖率、HTML 报告 | 可按任务清理，保留发布产物 |
| `docs/` | ADR、release notes、操作手册 | 不自动清理 |

## DC 产物约定

Design Compiler 常见根目录残留包括：

- `*.mr`
- `*-verilog.pvl`
- `*-verilog.syn`
- `alib-52/`
- `default.svf`

这些文件不应该出现在仓库根目录。顶层综合应从 `syn/build/dc_run/` 运行，
block-level 综合应从 `syn/build/lec_blocklevel/run/dc/` 运行。
脚本仍然把 netlist、DDC、SVF 和 report 写到 `syn/build/` 下的稳定路径。

## Formality 产物约定

Formality 常见根目录残留包括：

- `formality.log`
- `formality<N>.log`
- `fm_shell_command.log`
- `fm_shell_command<N>.log`
- `formality_svf/`
- `formality<N>_svf/`
- `FM_WORK*/`

这些文件由 `fm_shell` 基于当前工作目录生成。所有 LEC target 必须先进入
`syn/build/lec_blocklevel/run/fm/`，再调用 `fm_shell -f ...`。正式 report 继续写入
`syn/build/lec_blocklevel/lec_*.rpt`，不要手工编辑工具 report。

## VCS 与 Verdi 产物约定

VCS 编译必须指定：

- `-o build/simv`
- `-Mdir=build/csrc`
- `-l build/compile.log`

仿真日志必须写到对应 run 目录，例如 `build/<run>/sim.log` 或
`build/r3b_final/runs/<stage>/.../sim_*.log`。波形、coverage 和 Verdi 数据应位于
`build/` 子目录，不应落在仓库根目录。

## URG 覆盖率产物约定

URG merge/report 应使用显式路径：

- 输入：各 run 目录中的 `.vdb`
- 输出：`build/<run>/cov_merged/` 或任务指定的 coverage report 目录
- 日志：同一输出目录下的 `merge.log`、`dashboard.log`

不要在根目录运行无输出路径的 `urg` 命令。

## 清理命令

清理根目录残留：

```bash
make clean_workspace
```

等价于：

```bash
bash scripts/clean_workspace.sh
```

默认清理会删除清理规则中的根目录和 `syn/` 顶层 EDA 残留，删除 coverage
备份，并把 `build/` 顶层散落日志、历史 sign-off 和临时 run 目录归档到
`.scratch/r5_build_archive_<date>/`。
它不会删除当前编译、覆盖率和发布基线产物，包括 `build/r4a_final/`、
`build/r3b_final/`、`build/nightly/`、`build/cov.vdb/`、`build/cov/`、
`build/simv*`、`build/libcosim.so`、`build/spike_objs/`、`build/csrc/`、
`build/compile.log` 和 `build/compliance_tb_compile.log`。

历史 sign-off 目录通过 `build/archive_signoffs_<date>` 入口可查回；实际归档
位置由脚本管理，避免旧 sign-off 体积继续计入当前 `build/` 工作集。

## 清理范围

当前清理规则覆盖：

- DC：`*.mr`、`*-verilog.pvl`、`*-verilog.syn`、`eh2_pkg.pvk`、`alib-52/`、`default.svf`
- Formality：`*.lck`、`*.fss`、`formality*.log`、`fm_shell_command*.log`、`formality*_svf/`、`FM_WORK*/`
- VCS：`csrc/`、`tr_db.log`、`ucli.key`、`vc_hdrs.h`、`cm.log`、`command.log`
- Verdi/Novas：`verdiLog/`、`novas.*`、`novas_*/`
- 波形和崩溃转储：`top.vcd`、`*.fsdb`、`inter.vpd`、`DVEfiles/`、`stack.info.*`
- build 顶层散落日志：除 `compile.log` 和 `compliance_tb_compile.log` 外的 `build/*.log`
- coverage 备份：`build/cov.vdb.backup_*`、`build/cov.vdb.pre_*`
- 历史 sign-off：`build/r*_final/`（保留 `r4a_final`、`r3b_final`）、`build/sf_*`、`build/signoff*`
- 历史临时 run：`build/verify_*/`、`build/verify2_*/` 到 `build/verify8_*/`、
  `build/sweep_*/`、`build/issue12_*/`、`build/cosim_*/`、`build/dryrun_*/`、
  `build/finalcheck_*/`、`build/final_*/`、`build/t4_*/`、`build/t7_*/`、
  `build/post_unlock*/`、`build/csr_unit_*/`、`build/dret_*/`、
  `build/test_directed*/`、`build/r2a_*/`、`build/r2b_*/`、`build/r2c_*/`、
  `build/r2d_*/`、`build/r3b_*/`（保留 `r3b_final/`）、`build/r3c_*/`、
  `build/r3d_*/`、`build/r5_*/`、`build/cov_*/` 和 `build/smoke/`

`scripts/clean_workspace.sh` 的 build 保留白名单是最高优先级。新增清理前缀时，
必须先确认不会覆盖 `r3b_final`、`r4a_final`、`nightly`、`cov.vdb`、`cov`、
`simv`、`simv.daidir`、`simv.vdb`、`simv_compliance`、`simv_compliance.daidir`、
`libcosim.so`、`spike_objs`、`csrc`、`compile.log`、`compliance_tb_compile.log`
和 `archive_signoffs_*`。

## 验证方式

清理后应检查：

```bash
find . -maxdepth 1 -type f -name '*.mr' | wc -l
find . -maxdepth 1 -type f -name '*-verilog.pvl' | wc -l
find . -maxdepth 1 -type f -name '*-verilog.syn' | wc -l
ls *.lck *.fss *.pvk 2>/dev/null | wc -l
ls syn/*.lck syn/*.log syn/*.fss 2>/dev/null | wc -l
find . -maxdepth 1 -type d \( -name csrc -o -name alib-52 -o -name formality_svf -o -name verdiLog \)
```

如果需要验证 LEC 流程不会再次污染根目录，运行：

```bash
make -C syn block_lec
```

然后重复上面的根目录检查，并确认 `syn/build/lec_summary.txt` 的 `TOTAL` 行仍为 PASS。

## 新脚本要求

新增 DC、Formality、VCS、URG 脚本时必须满足：

1. 输出路径显式指向 `build/` 或 `syn/build/`。
2. 工具命令需要当前目录时，先 `cd` 到对应 build run 目录。
3. 日志文件不要直接写根目录。
4. 不要依赖 `.gitignore` 掩盖工具污染。
5. 不要把临时产物混入最终 release 目录。
