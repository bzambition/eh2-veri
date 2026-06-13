# EH2 验证平台 VCS 主线化重构

- 日期：2026-05-18
- 状态：已批准
- 类型：架构重构

---

## 一、问题陈述

### 1.1 现状回顾

EH2-VeeR UVM 验证平台前期切换默认仿真器到 Cadence Incisive 152 (NC/irun)。
切换后陆续暴露 12 个数据真实性 / 配置 bug（Bug A 至 Bug L），主要源于：

- **Incisive 152 已 EOL**，2016 年版本无新功能与修复。
- **默认覆盖率范围保守**：
  `-coverage all` 不真正"全部"，必须额外 CCF 配 `set_expr_coverable_operators -all` 才 instrument 完整。
- **IMC 不输出 URG 兼容 dashboard**：需要自定义 200+ 行合成代码。
- **NC sim returncode 经常 ≠ 0** 即便 `TEST PASSED`：需 log 解析反转。
- **svdpi.h 不在标准路径**：需手工查找。
- **ncelab 不自动 import package**：testbench top 必须显式 import。
- **NC `-coverage all` instrument 范围窄**：dut 子树仅识别 12 个 expression bins，与 EH2 实际 ~1050 个表达式构造严重不符。

### 1.2 工业实践对照

主流 RISC-V 开源 UVM 验证项目（lowRISC Ibex / OpenTitan / chipsalliance riscv-dv）**默认 VCS**。Western Digital VeeR (EH2 RTL 上游) 同样 VCS-friendly。

Ibex 工业实现关键模式（已经从 `/home/host/ibex/dv/uvm/core_ibex/` 验证）：

```
# cover.cfg
+tree core_ibex_tb_top.dut
begin tgl
  -tree core_ibex_tb_top.dut.*
end
```

```
# cov_opts
-cm line+tgl+assert+fsm+branch
-cm_tgl portsonly -cm_tgl structarr
-cm_report noinitial -cm_seqnoconst
-cm_hier cover.cfg
```

```python
# merge_cov.py
urg -full64 -format both -dbname merged.vdb -report report -dir <cov_dirs>
```

**关键特征**：
- 编译时 `-cm_hier cover.cfg` 限定 dut 子树 → 编译时就过滤 testbench stub，**从源头杜绝 stub 假高数字**。
- 不收集 cond/expression 维度 → Ibex 工业实践证明 line+toggle+branch 已覆盖大部分 condition 路径。
- urg 默认输出 dashboard.txt，**零后处理**。

### 1.3 决策

**默认仿真器切换回 VCS。完全对齐 Ibex 工业实现**。
**NC 仅保留为"跑单测看波形"的辅助调试通道**，不参与 sign-off / 覆盖率收集。

---

## 二、目标与非目标

### 目标

1. 全平台所有 stage（compile / smoke / regress / signoff / demo / cosim / compliance / csr_unit）默认 SIMULATOR=vcs。
2. 覆盖率配置完全对齐 Ibex 工业实现：5 维度 + cover.cfg 编译时 scope 限定 + urg 默认输出。
3. NC 路径仅支持 `make smoke SIMULATOR=nc WAVES=1` 与 `make regress SIMULATOR=nc TEST=<name> WAVES=1` 两种命令，用于单测仿真+波形查看。
4. 删除所有 NC 专用 sign-off / 覆盖率合成代码（merge_cov.py NC 段、cov_full_nc.ccf 等）。
5. 保留 NC 单测必需的最小适配（nc_waves.tcl / tb_top.sv import / run_rtl.py NC 分支 / check_logs.py TEST PASSED 反转）。
6. 数据真实性绝对保证：通过编译时 hier scope 限定，**不能再出现 67.77% 那种含 stub 假阳性**。

### 非目标

- 不升级 EH2 RTL 设计（Cores-VeeR-EH2 保持原样）。
- 不切换到 Xcelium（未来工作）。
- 不重写 signoff.py / gen_html_report.py 基础架构。
- 不强制追求"覆盖率 100%"（这是 RTL 测试本身的工作）。

---

## 三、覆盖率体系设计（核心）

### 3.1 cover.cfg（新增）

路径：`dv/uvm/core_eh2/cover.cfg`

内容（完全对齐 Ibex 模式）：
```
+tree core_eh2_tb_top.dut
begin tgl
  -tree core_eh2_tb_top.dut.*
end
```

**作用**：
- `+tree core_eh2_tb_top.dut` 启用 `dut` 子树所有 metric 的 instrumentation。**仅 dut 子树**，不含 tb_intf / lsu_mem / ifu_mem / sb_mem / axi_intf / u_fcov_if / u_rvfi_converter 等 testbench 外围。
- `begin tgl ... end` 对 toggle 单独配置。
- `-tree core_eh2_tb_top.dut.*` 排除 dut 内部所有子模块的端口 toggle，避免端口在父子模块重复计数。

### 3.2 cov_opts（VCS 编译 + 仿真）

**编译时（compile_vcs）**：
```
-cm line+tgl+assert+fsm+branch
-cm_tgl portsonly
-cm_tgl structarr
-cm_report noinitial
-cm_seqnoconst
-cm_hier dv/uvm/core_eh2/cover.cfg
```

**仿真时**：
```
-cm line+tgl+assert+fsm+branch
-cm_dir <build_dir>/cov.vdb
-cm_name <test>_<seed>
```

### 3.3 merge_cov.py 回滚

恢复到 HEAD（Ibex 抄来的）风格：

```python
def merge_cov_vcs(cov_dirs, output_dir):
    cmd = ['urg', '-full64',
           '-format', 'both',
           '-dbname', str(output_dir / 'merged.vdb'),
           '-report', str(output_dir / 'report'),
           '-log', str(output_dir / 'merge.log'),
           '-dir'] + [str(d) for d in cov_dirs]
    return run_command(cmd)
```

- 删除：`merge_imc()` 函数、`_parse_imc_summary()`、`_parse_cumulative_metric()`、`_write_urg_compat_dashboard()`、`find_nc_run_dirs()`。
- 保留并扩展：`merge_cov_vcs()` 用作 signoff.py auto_merge 调用接口（standalone mode）。
- dashboard.txt 由 urg 原生生成，路径 `<output_dir>/report/dashboard.txt`。

### 3.4 signoff.py 调整

- `auto_merge_stage_coverage()` 仅识别 VCS .vdb，调用 urg；删除 NC cov_work / .ucd 检测分支。
- `coverage_candidate_files()` 寻找 urg 生成的 dashboard.txt：默认在 `<output_dir>/cov_merged/report/dashboard.txt`。
- `_parse_urg_dashboard_header()` 保留（URG 原生格式解析）。删除 `n/a` 占位符特殊处理（因为不再合成假 n/a）。
- precheck `sim_tool` 默认 vcs。
- `compute_real_run_count()` 保留（与 simulator 无关，按 testlist entry 数计）。
- `MAX_STAGE_FAIL_RATE_FOR_WAIVER = 0.25` 保留（与 simulator 无关）。

---

## 四、NC 极简路径

### 4.1 NC 仅支持两个命令

```bash
make smoke SIMULATOR=nc WAVES=1
make regress SIMULATOR=nc TEST=<test_name> WAVES=1
```

**这两个命令需要的最小适配**：

| 文件 | 保留内容 |
|------|---------|
| `dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` | `import core_eh2_test_pkg::*;`（NC 必需，VCS 无害） |
| `dv/uvm/core_eh2/nc_waves.tcl` | NC SHM 波形 dump 配置 |
| `dv/uvm/core_eh2/yaml/rtl_simulation.yaml` | NC 段保留：cmd（含 sv_lib libcosim.so），cov_opts 空字符串，wave_opts 指向 nc_waves.tcl |
| `dv/uvm/core_eh2/scripts/run_rtl.py` | NC INCA_libs readiness 检测保留 |
| `dv/uvm/core_eh2/scripts/check_logs.py` | NC TEST PASSED 反转保留（NC exit≠0 但 PASS 的特性必需）|
| `dv/uvm/core_eh2/scripts/run_regress.py` | `--simulator nc` choice 保留 |
| `Makefile` | compile_nc target 保留（用于上述两个命令） |
| `Makefile` | NC compile cov_opts 设为空（NC 单测不收 cov） |

### 4.2 NC 不再支持的命令

```bash
make demo SIMULATOR=nc        # 不支持
make signoff SIMULATOR=nc     # 不支持
make compliance SIMULATOR=nc  # 不支持（compliance 子环境强制 vcs）
```

具体策略（在实施阶段确认细节）：
- 在 demo/signoff target 入口处检查 `$(SIMULATOR)`，若非 vcs 则报错退出（推荐，避免静默误用）。
- 或者：demo/signoff target 内部 hardcode 调用 compile/regress 时不传 SIMULATOR 变量，让其用 vcs 默认。

### 4.3 NC 路径删除的文件

| 文件 | 处置 |
|------|------|
| `dv/uvm/core_eh2/cov_full_nc.ccf` | **删除**（NC 不再参与覆盖率收集） |

---

## 五、文件改动清单（实施时参照）

### 新增
- `dv/uvm/core_eh2/cover.cfg`

### 删除
- `dv/uvm/core_eh2/cov_full_nc.ccf`

### 改动（按改动量从大到小）
1. `dv/uvm/core_eh2/scripts/merge_cov.py` — 删除 NC IMC 合成（约 200 行），简化为 Ibex 风格 urg 调用
2. `dv/uvm/core_eh2/scripts/signoff.py` — 删除 NC cov_work 检测、auto_merge NC 分支、SIMULATOR default
3. `dv/uvm/core_eh2/yaml/rtl_simulation.yaml` — VCS cov_opts 改 Ibex 模式（含 `-cm_hier`、`-cm_tgl portsonly` 等），NC 段简化为单测+波形
4. `Makefile` — `SIMULATOR ?= vcs`，NC_COMPILE_COV_OPTS 删除，VCS_COMPILE_COV_OPTS 改 Ibex 模式，demo/signoff 强制 VCS
5. `Makefile help` — 反映 VCS 默认 + NC 极简用途
6. `dv/uvm/core_eh2/scripts/run_regress.py` — `--simulator vcs` 默认
7. `dv/uvm/core_eh2/scripts/run_rtl.py` — `--simulator vcs` 默认
8. `env.sh` / `env.mk` — `EH2_SIMULATOR=vcs` 默认
9. `README.md` / `CLAUDE.md` / `CONTEXT.md` — 反映 VCS 主线

### 保留不动
- `dv/uvm/core_eh2/nc_waves.tcl`
- `dv/uvm/core_eh2/scripts/check_logs.py`（NC TEST PASSED 反转保留）
- `dv/uvm/core_eh2/cov_fsm.cfg` / `cov_fsm_reset_filter.cfg` — VCS FSM 配置文件保留（其它 -cm_fsmcfg 参数继续用）
- `dv/uvm/core_eh2/tb/core_eh2_tb_top.sv` — `import core_eh2_test_pkg::*;` 保留

---

## 六、验证策略

### 6.1 重构后必跑

1. `make compile` — 验证默认 VCS 编译通过，产物 `build/compile/simv`
2. `make smoke` — 验证默认 VCS smoke 通过
3. `make smoke SIMULATOR=nc WAVES=1` — 验证 NC 单测+波形可用，产出 `build/smoke/smoke_s1/waves.shm/`
4. `make demo` — 验证完整 demo 通过，dashboard 数据真实（dut scope）
5. `make signoff_replay` — 验证 sign-off gate 工作

### 6.2 数据真实性检查清单

- [ ] dashboard.txt 来自 urg 原生输出，无任何合成
- [ ] cov.vdb 中的 instrument scope 仅为 dut 子树（不含 tb_intf）
- [ ] urg 报告中 line coverage 数字 = IMC 报 `dut subtree` 数字（cross-validate）
- [ ] sign-off 不再出现 67.77% 这种含 stub 假高数字
- [ ] `make demo SIMULATOR=nc` 应被拒绝或不收 cov，不产生假阳性

### 6.3 风险与回滚

- 风险：VCS license 在某时段不可用 → mitigation：NC 单测+波形作 fallback 调试通道
- 风险：旧 build/r3b_final / build/demo 数据基于 NC → 归档到 `.scratch/r5_nc_archive_<date>/`，重跑生成新的 VCS 数据。
  归档命令：`make clean MODE=archive`（既有脚本 `scripts/clean_workspace.sh` 支持智能归档）
- 回滚：保留 git tag `pre-vcs-mainline-<date>`，可一键回到当前 NC-default 状态

---

## 七、实施顺序（writing-plans 阶段细化）

实施阶段建议按以下顺序，每步独立可测试：

1. **新增 cover.cfg + Makefile VCS cov_opts 改 Ibex 模式**（不动 NC，先验证 VCS 路径数据真实性）
2. **回滚 merge_cov.py 到 Ibex 风格**（删除 NC IMC 合成代码）
3. **signoff.py 默认 VCS + 删除 NC cov_work 检测**
4. **`SIMULATOR ?= vcs` 全局默认变更**
5. **NC 单测路径精简（删除 cov_full_nc.ccf，yaml NC 段简化）**
6. **demo/signoff 入口拒绝 SIMULATOR≠vcs（或静默降级）**
7. **文档与 help 同步**
8. **端到端验证 + 旧数据归档**

---

## 八、参考来源

- 本地 Ibex 镜像：`/home/host/ibex/dv/uvm/core_ibex/`
  - `cover.cfg`
  - `yaml/rtl_simulation.yaml`
  - `scripts/merge_cov.py`
- Cadence Incisive 152 文档：`/home/cadence/INCISIVE152/doc/iccug/`（论证 NC 默认配置限制）
- 当前项目 git HEAD：`dv/uvm/core_eh2/scripts/merge_cov.py` 是 Ibex 抄来的原版

---

## 九、决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 默认仿真器 | VCS | 行业事实标准；UVM/riscv-dv 默认；EH2 RTL 上游 VCS-friendly |
| 覆盖率维度 | line+tgl+assert+fsm+branch（5 维度）| Ibex 工业实现；不收 cond/expression 是工业实践合理简化 |
| scope 限定方式 | 编译时 `-cm_hier cover.cfg` | 源头过滤，杜绝 stub 假阳性 |
| NC 范围 | 极简：单测+波形 | 用户明确选择，代码最干净 |
| merge_cov.py | 回滚 Ibex 风格 | urg 原生输出已工业级，无需任何包装 |
| 旧 NC 数据 | 归档到 .scratch/ | 不破坏现有证据，但不混淆新流程 |
