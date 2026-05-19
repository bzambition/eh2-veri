.. _ci_pipeline:
.. _06_flows/ci_pipeline:

CI 流水线 - 详细参考
================================================================================

:status: draft
:source: .github/workflows/unit-tests.yml; .github/workflows/lint.yml; .github/workflows/sim.yml; .github/workflows/nightly.yml; Makefile; docs/build_manual_pdf.sh; docs/sphinx_cn/source/conf.py; README.md; syn/build/lec_summary.txt
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  流水线边界
--------------------------------------------------------------------------------

本章描述仓库当前存在的 CI 入口。实际 workflow 文件是
:file:`.github/workflows/unit-tests.yml`、:file:`.github/workflows/lint.yml`、
:file:`.github/workflows/sim.yml` 和 :file:`.github/workflows/nightly.yml`。
当前仓库没有 :file:`.github/workflows/ci.yml`，因此本章不再引用该路径。

CI 被分成两类 runner：

* GitHub-hosted `ubuntu-latest`：只运行不需要 VCS、Spike DPI 或内部 license 的
  Python 单元测试、YAML sanity 和 Verible lint。
* self-hosted runner：运行需要 VCS、spike-cosim 或内部环境的 simulation
  sign-off。

当前代码中的数据流可以概括为：

.. code-block:: bash

   push / pull_request
        |
        +-- unit-tests.yml: unittest + riscv-dv YAML sanity
        |
        +-- lint.yml: install Verible + lint DV SystemVerilog + upload report

   workflow_dispatch or PR label run-sim
        |
        +-- sim.yml on [self-hosted, eh2-sim]
              |
              +-- source env.sh
              +-- make cosim
              +-- make compile SIMULATOR=vcs
              +-- make signoff PROFILE=<profile> PARALLEL=4 COV=1

   schedule 0 2 * * * or workflow_dispatch
        |
        +-- nightly.yml on self-hosted
              |
              +-- make signoff PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1 COV=1

这个图只表达 YAML 文件中的触发和命令。当前 CI/sign-off 口径以 2026-05-19
01:02 VCS demo 为准：9/9 stages PASS、formal 46/46、LEC 31635/31635、
compliance 85/88 (96.59%)、riscv-dv 370/395 (93.67%)、CSR 20/20、
directed 40/40、cosim 7/7、实跑覆盖率 102/104 (98.1%)。coverage dashboard
为 LINE 95.05%、BRANCH 84.97%、TOGGLE 53.52%、ASSERT 33.33%、FSM 54.74%、
GROUP 69.42%、OVERALL 65.17%。

**接口关系**：

* **上层触发**：GitHub Actions 的 `push`、`pull_request`、
  `workflow_dispatch` 和 `schedule`。
* **下层调用**：顶层 :file:`Makefile` 的 `ci_unit`、`ci_lint`、`cosim`、
  `compile`、`signoff`、`manual`、`manual_html`。
* **共享状态**：GitHub artifact、`build/ci_signoff`、`build/signoff`、
  `lint_report.txt`、VCS coverage dashboard 和 Sphinx 输出目录。

§2  `.github/workflows/unit-tests.yml`
--------------------------------------------------------------------------------

§2.1  workflow 触发边界
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：`unit-tests.yml` 在 `master` 或 `main` 的 push 和 pull request 上
运行，不依赖 EDA 工具。

**关键代码** （`.github/workflows/unit-tests.yml:L1-L12`）：

.. code-block:: yaml

   name: unit-tests
   # Unit tests for the EH2 verification harness scripts. These are pure-Python
   # checks that don't need VCS or spike-cosim, so they run on any GitHub-hosted
   # runner. RTL simulation belongs on the internal self-hosted runner — see
   # .github/workflows/sim.yml.
   
   on:
     push:
       branches: [master, main]
     pull_request:
       branches: [master, main]

**逐段解释**：

* 第 L1 行：workflow 名称是 `unit-tests`。
* 第 L2-L5 行：注释把该 workflow 的范围限定为纯 Python 检查；RTL simulation
  被放到 `sim.yml`。
* 第 L7-L11 行：触发器只覆盖 `master` 和 `main` 分支上的 push 与 pull request。

**接口关系**：

* **被调用**：GitHub Actions 在对应事件发生时调用。
* **调用**：后续两个 job：`unit-tests` 和 `yaml-lint`。
* **共享状态**：GitHub checkout 后的工作区。

§2.2  `unit-tests` job - Python regression-framework tests
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：安装 Python 3.10 和 PyYAML，然后运行 regression framework 的
`unittest`。

**关键代码** （`.github/workflows/unit-tests.yml:L13-L35`）：

.. code-block:: yaml

   jobs:
     unit-tests:
       name: Python regression-framework tests
       runs-on: ubuntu-latest
       timeout-minutes: 5
       steps:
         - uses: actions/checkout@v4
   
         - name: Set up Python
           uses: actions/setup-python@v5
           with:
             python-version: "3.10"
   
         - name: Install dependencies
           run: |
             python -m pip install --upgrade pip
             pip install pyyaml
   
         - name: Run regression-framework tests
           run: |
             cd dv/uvm/core_eh2/scripts
             python -m unittest tests.test_regression_framework -v

**逐段解释**：

* 第 L14-L17 行：job 名为 `Python regression-framework tests`，运行在
  `ubuntu-latest`，超时 5 分钟。
* 第 L19-L24 行：先 checkout，再安装 Python 3.10。
* 第 L26-L29 行：升级 pip，并安装 `pyyaml`。该 job 没有安装 VCS、Spike 或
  Verible。
* 第 L31-L35 行：进入 `dv/uvm/core_eh2/scripts`，运行
  `python -m unittest tests.test_regression_framework -v`。

**接口关系**：

* **被调用**：`unit-tests.yml` workflow。
* **调用**：Python 标准库 `unittest` 和 `tests.test_regression_framework`。
* **共享状态**：依赖 PyYAML；不写 release artifact。

§2.3  `yaml-lint` job - riscv-dv testlist sanity
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：用 Python 和 PyYAML 校验 riscv-dv testlist 是非空 list、测试名不重复、
每个 entry 含必需字段。

**关键代码** （`.github/workflows/unit-tests.yml:L36-L65`）：

.. code-block:: yaml

     yaml-lint:
       name: YAML / testlist sanity
       runs-on: ubuntu-latest
       timeout-minutes: 2
       steps:
         - uses: actions/checkout@v4
   
         - name: Set up Python
           uses: actions/setup-python@v5
           with:
             python-version: "3.10"
   
         - name: Install pyyaml
           run: pip install pyyaml
   
         - name: Validate testlist.yaml
           run: |
             python - <<'EOF'

**逐段解释**：

* 第 L36-L39 行：`yaml-lint` job 运行在 `ubuntu-latest`，超时 2 分钟。
* 第 L41-L49 行：checkout 后安装 Python 3.10 和 PyYAML。
* 第 L51-L53 行：用 here-doc 运行内联 Python，而不是调用仓库脚本。

**关键代码** （`.github/workflows/unit-tests.yml:L54-L65`）：

.. code-block:: python

   import yaml, sys, pathlib
   tl = pathlib.Path("dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml")
   tests = yaml.safe_load(tl.read_text())
   assert isinstance(tests, list) and tests, "testlist must be a non-empty list"
   names = [t["test"] for t in tests]
   dups = [n for n in set(names) if names.count(n) > 1]
   assert not dups, f"duplicate test names: {dups}"
   for t in tests:
       for required in ("test", "description", "rtl_test"):
           assert required in t, f"{t.get('test')} missing {required}"
   print(f"testlist.yaml OK: {len(tests)} tests, no duplicates")

**逐段解释**：

* 第 L54-L57 行：读取
  `dv/uvm/core_eh2/riscv_dv_extension/testlist.yaml`，要求顶层是非空 list。
* 第 L58-L60 行：提取每个 entry 的 `test` 字段，并拒绝重复名称。
* 第 L61-L64 行：每个 riscv-dv entry 必须包含 `test`、`description` 和
  `rtl_test`。
* 第 L64 行：通过时打印 test 数和无重复结论。

**接口关系**：

* **被调用**：`yaml-lint` job。
* **调用**：PyYAML。
* **共享状态**：riscv-dv testlist。

§2.4  `yaml-lint` job - directed/cosim testlist 类型检查
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：确认 directed 和 cosim testlist 文件存在时可被 PyYAML 解析为 list。

**关键代码** （`.github/workflows/unit-tests.yml:L67-L79`）：

.. code-block:: yaml

         - name: Validate cosim_testlist.yaml
           run: |
             python - <<'EOF'
             import yaml, pathlib
             for fname in ("cosim_testlist.yaml", "directed_testlist.yaml"):
                 p = pathlib.Path(f"dv/uvm/core_eh2/directed_tests/{fname}")
                 if not p.exists():
                     print(f"{fname}: not present, skipping")
                     continue
                 tests = yaml.safe_load(p.read_text())
                 assert isinstance(tests, list)
                 print(f"{fname}: OK ({len(tests)} entries)")
             EOF

**逐段解释**：

* 第 L67-L71 行：步骤名仍写成 `Validate cosim_testlist.yaml`，但循环实际检查
  `cosim_testlist.yaml` 和 `directed_testlist.yaml` 两个文件。
* 第 L72-L75 行：文件不存在时只打印 skipping，不失败。
* 第 L76-L78 行：文件存在时要求 YAML 顶层是 list，并打印 entry 数。

**接口关系**：

* **被调用**：`yaml-lint` job。
* **调用**：PyYAML。
* **共享状态**：`dv/uvm/core_eh2/directed_tests` 下的两个 YAML 文件。

§3  `.github/workflows/lint.yml`
--------------------------------------------------------------------------------

§3.1  workflow 触发和 lint job
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：在 push 和 pull request 上运行 Verible lint，并把 error/fatal 作为
blocking gate。

**关键代码** （`.github/workflows/lint.yml:L1-L13`）：

.. code-block:: yaml

   name: Verilog Lint
   # Blocking CI gate: DV SystemVerilog lint must pass with zero errors.
   # Any ERROR/FATAL in lint output fails the job.
   # Waivers for non-critical style issues are in lint/verible/waivers.vbl.
   
   on: [push, pull_request]
   
   jobs:
     verible-lint:
       runs-on: ubuntu-latest
       timeout-minutes: 10
       steps:
         - uses: actions/checkout@v4

**逐段解释**：

* 第 L1 行：workflow 名称是 `Verilog Lint`。
* 第 L2-L4 行：注释写明这是 blocking gate，并说明 error/fatal 会失败。
* 第 L6 行：触发器覆盖所有 push 和 pull request。
* 第 L9-L13 行：唯一 job 是 `verible-lint`，运行在 `ubuntu-latest`，
  超时 10 分钟。

**接口关系**：

* **被调用**：GitHub Actions push/pull_request。
* **调用**：Verible 安装和 lint 步骤。
* **共享状态**：`lint_report.txt` artifact。

§3.2  安装 Verible
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：下载指定版本 Verible tarball，解压后把 bin 目录加入 GitHub Actions
PATH。

**关键代码** （`.github/workflows/lint.yml:L14-L19`）：

.. code-block:: yaml

         - name: Install Verible
           run: |
             VERIBLE_VERSION=v0.0-3644-g6882e2b7
             wget -q "https://github.com/chipsalliance/verible/releases/download/${VERIBLE_VERSION}/verible-${VERIBLE_VERSION}-linux-static-x86_64.tar.gz" -O verible.tar.gz
             tar xf verible.tar.gz
             echo "$PWD/verible-${VERIBLE_VERSION}/bin" >> $GITHUB_PATH

**逐段解释**：

* 第 L14-L16 行：步骤固定使用 `VERIBLE_VERSION=v0.0-3644-g6882e2b7`。
* 第 L17 行：从 chipsalliance/verible release 下载 linux static x86_64 tarball。
* 第 L18-L19 行：解压 tarball，并把解压目录下的 `bin` 追加到
  `$GITHUB_PATH`。

**接口关系**：

* **被调用**：`verible-lint` job。
* **调用**：`wget`、`tar` 和 GitHub Actions PATH 文件。
* **共享状态**：workflow 工作目录下的 `verible.tar.gz` 和解压目录。

§3.3  Lint DV SystemVerilog sources
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：查找 `dv/uvm/core_eh2` 下的 SystemVerilog 文件，并运行
`verible-verilog-lint`。

**关键代码** （`.github/workflows/lint.yml:L20-L26`）：

.. code-block:: yaml

         - name: Lint DV SystemVerilog sources
           run: |
             find dv/uvm/core_eh2 -name '*.sv' -o -name '*.svh' | \
               xargs verible-verilog-lint \
                 --rules=-line-length,-no-trailing-spaces \
                 --waiver_files=dv/uvm/core_eh2/fcov/cov_waivers/*.yaml \
                 2>&1 | tee lint_report.txt

**逐段解释**：

* 第 L20-L22 行：`find` 命令查找 `.sv` 和 `.svh` 文件，然后通过 pipe 交给
  `xargs`。
* 第 L23-L24 行：lint 工具是 `verible-verilog-lint`，规则关闭
  `line-length` 和 `no-trailing-spaces`。
* 第 L25 行：实际命令使用的 waiver 路径是
  `dv/uvm/core_eh2/fcov/cov_waivers/*.yaml`。这与第 L4 注释中提到的
  `lint/verible/waivers.vbl` 不是同一个路径，文档按命令行为准。
* 第 L26 行：stderr 合并到 stdout，并用 `tee` 写入 `lint_report.txt`。

**接口关系**：

* **被调用**：`verible-lint` job。
* **调用**：`find`、`xargs`、`verible-verilog-lint`、`tee`。
* **共享状态**：`lint_report.txt`。

§3.4  Check lint errors 和 artifact
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：扫描 `lint_report.txt` 中的 error/fatal 行，失败时退出 1；无错误时上传报告。

**关键代码** （`.github/workflows/lint.yml:L27-L40`）：

.. code-block:: yaml

         - name: Check lint errors
           run: |
             if grep -qE "^(E|FATAL)" lint_report.txt; then
               echo "BLOCKING: lint errors found in lint_report.txt"
               grep -E "^(E|FATAL)" lint_report.txt
               exit 1
             fi
             echo "Lint passed with zero errors."
         - name: Upload lint report
           if: always()
           uses: actions/upload-artifact@v4
           with:
             name: lint-report
             path: lint_report.txt

**逐段解释**：

* 第 L27-L33 行：`grep -qE "^(E|FATAL)"` 命中时打印 blocking 信息、
  回显错误行并 `exit 1`。
* 第 L34 行：没有匹配项时打印 lint 通过信息。
* 第 L35-L40 行：无论前一步是否失败，都上传名为 `lint-report` 的 artifact，
  内容是 `lint_report.txt`。

**接口关系**：

* **被调用**：`verible-lint` job。
* **调用**：`grep`、`actions/upload-artifact@v4`。
* **共享状态**：lint report artifact。

§4  `.github/workflows/sim.yml`
--------------------------------------------------------------------------------

§4.1  workflow 触发和 self-hosted 约束
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：把需要 VCS 和 spike-cosim 的 RTL simulation 放到内部 self-hosted
runner，并通过手动触发或 PR label 控制执行。

**关键代码** （`.github/workflows/sim.yml:L1-L18`）：

.. code-block:: yaml

   name: sim-regression
   # RTL simulation regression. Requires VCS + spike-cosim, so this runs only on
   # the internal self-hosted runner labelled "eh2-sim". GitHub-hosted runners
   # don't have these tools — they would always fail.
   #
   # Trigger manually via "Run workflow" or on a label. The label gate keeps PR
   # noise low; CI maintainers can attach `run-sim` to a PR they want exercised.
   
   on:
     workflow_dispatch:
       inputs:
         profile:
           description: "Sign-off profile: quick | cosim | nightly | full"
           required: true
           default: "quick"
     pull_request:
       types: [labeled]

**逐段解释**：

* 第 L1-L4 行：workflow 名为 `sim-regression`，注释说明它需要 VCS 和
  spike-cosim，因此不能放在 GitHub-hosted runner。
* 第 L6-L7 行：PR 上通过 `run-sim` label 控制是否执行。
* 第 L9-L15 行：手动触发时要求输入 `profile`，默认 `quick`。
* 第 L16-L18 行：PR 触发只监听 `labeled` 事件。

**接口关系**：

* **被调用**：`workflow_dispatch` 或 PR label 事件。
* **调用**：`sim` job。
* **共享状态**：GitHub event input 和 PR label 集合。

§4.2  `sim` job 条件和 runner
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：只有手动触发或 PR 带 `run-sim` label 时才运行，并绑定
`[self-hosted, eh2-sim]` runner。

**关键代码** （`.github/workflows/sim.yml:L19-L28`）：

.. code-block:: yaml

   jobs:
     sim:
       name: ${{ github.event.inputs.profile || 'quick' }} sign-off
       if: |
         github.event_name == 'workflow_dispatch' ||
         (github.event_name == 'pull_request' &&
          contains(github.event.pull_request.labels.*.name, 'run-sim'))
       runs-on: [self-hosted, eh2-sim]
       timeout-minutes: 240
       steps:

**逐段解释**：

* 第 L20-L21 行：job 名称使用输入 profile；没有输入时显示 `quick sign-off`。
* 第 L22-L25 行：job 条件要求事件是 `workflow_dispatch`，或 PR label 集合包含
  `run-sim`。
* 第 L26-L27 行：runner label 是 `[self-hosted, eh2-sim]`，超时 240 分钟。

**接口关系**：

* **被调用**：`sim-regression` workflow。
* **调用**：checkout、cosim build、compile、sign-off、artifact upload。
* **共享状态**：self-hosted runner 上的 EDA 环境。

§4.3  cosim 和 VCS testbench 编译
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：在 simulation job 中先编译 cosim shared library，再编译 VCS testbench。

**关键代码** （`.github/workflows/sim.yml:L29-L40`）：

.. code-block:: yaml

       - uses: actions/checkout@v4
   
       - name: Compile cosim shared library
         run: |
           source env.sh
           make cosim
   
       - name: Compile RTL testbench (VCS)
         run: |
           source env.sh
           make compile SIMULATOR=vcs

**逐段解释**：

* 第 L29 行：先 checkout 仓库。
* 第 L31-L34 行：cosim step 在同一个 shell 中 `source env.sh`，再执行
  `make cosim`。
* 第 L36-L39 行：compile step 同样在本 step 内 `source env.sh`，再执行
  `make compile SIMULATOR=vcs`。

**接口关系**：

* **被调用**：`sim` job。
* **调用**：:file:`env.sh`、顶层 `make cosim`、`make compile`。
* **共享状态**：`build/libcosim.so`、`build/simv` 或编译产物。

§4.4  Run sign-off gate 和上传 artifact
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：按输入 profile 调用顶层 `make signoff`，并上传 sign-off JSON、
Markdown、stage log 和 stage report。

**关键代码** （`.github/workflows/sim.yml:L41-L57`）：

.. code-block:: yaml

       - name: Run sign-off gate
         run: |
           source env.sh
           PROFILE="${{ github.event.inputs.profile || 'quick' }}"
           make signoff PROFILE="$PROFILE" SIGNOFF_OUT=build/ci_signoff PARALLEL=4 COV=1
   
       - name: Upload sign-off report
         if: always()
         uses: actions/upload-artifact@v4
         with:
           name: signoff-${{ github.event.inputs.profile || 'quick' }}-${{ github.run_id }}
           path: |
             build/ci_signoff/signoff_status.json
             build/ci_signoff/signoff_report.md
             build/ci_signoff/runs/**/regr.log
             build/ci_signoff/runs/**/report.json
           retention-days: 30

**逐段解释**：

* 第 L41-L45 行：sign-off step 在同一个 shell 中 source 环境，解析 profile。
  仓库 workflow 可能仍保留历史变量名；本章推荐命令使用当前 Makefile 主线
  `PROFILE="$PROFILE"`、`SIGNOFF_OUT=build/ci_signoff`、`PARALLEL=4` 和 `COV=1`。
* 第 L47-L52 行：上传步骤无论 sign-off 是否成功都会执行；artifact 名包含
  profile 和 `github.run_id`。
* 第 L53-L56 行：上传内容包括 sign-off JSON、Markdown、每个 stage 的
  `regr.log` 和 `report.json`。
* 第 L57 行：artifact 保留 30 天。

**接口关系**：

* **被调用**：`sim` job。
* **调用**：顶层 `make signoff` 和 `actions/upload-artifact@v4`。
* **共享状态**：`build/ci_signoff`。

§5  `.github/workflows/nightly.yml`
--------------------------------------------------------------------------------

§5.1  schedule 和手动触发
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：每天 UTC 02:00 或手动触发一个 self-hosted full sign-off job。

**关键代码** （`.github/workflows/nightly.yml:L1-L13`）：

.. code-block:: yaml

   name: Nightly Regression
   # 每日凌晨 2 点（UTC）自动跑完整回归，确保主干持续可签收。
   # 使用 self-hosted runner，因为需要 VCS license 和 spike-cosim。
   
   on:
     schedule:
       - cron: '0 2 * * *'
     workflow_dispatch:
   
   jobs:
     signoff:
       runs-on: self-hosted
       timeout-minutes: 60

**逐段解释**：

* 第 L1 行：workflow 名称是 `Nightly Regression`。
* 第 L2-L3 行：注释说明每日 UTC 02:00 自动跑，且使用 self-hosted runner。
* 第 L5-L8 行：触发器是 cron `0 2 * * *` 和手动 `workflow_dispatch`。
* 第 L10-L13 行：唯一 job 是 `signoff`，运行在 `self-hosted`，超时 60 分钟。

**接口关系**：

* **被调用**：GitHub Actions schedule 或手动触发。
* **调用**：nightly sign-off steps。
* **共享状态**：self-hosted runner 工作区。

§5.2  nightly steps 和输出路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：checkout 后运行 full sign-off，并上传默认 `build/signoff` 下的报告。

**关键代码** （`.github/workflows/nightly.yml:L14-L27`）：

.. code-block:: yaml

       steps:
         - uses: actions/checkout@v4
         - name: Source environment
           run: source env.sh || true
         - name: Run full sign-off
           run: make signoff PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1 COV=1
         - name: Upload sign-off report
           if: always()
           uses: actions/upload-artifact@v4
           with:
             name: signoff-report-${{ github.run_id }}
             path: |
               build/signoff/signoff_report.md
               build/signoff/signoff_status.json

**逐段解释**：

* 第 L15 行：先 checkout 仓库。
* 第 L16-L17 行：单独的 `Source environment` step 执行 `source env.sh || true`。
* 第 L18-L19 行：sign-off step 推荐执行
  `make signoff PROFILE=full PARALLEL=4 SIGNOFF_ITERATIONS=1 COV=1`。命令本身
  没有指定 `SIGNOFF_OUT`，因此使用顶层 :file:`Makefile` 的默认
  `build/signoff`。
* 第 L20-L27 行：无论 sign-off 是否成功，都上传 `build/signoff/signoff_report.md`
  和 `build/signoff/signoff_status.json`。

**接口关系**：

* **被调用**：nightly `signoff` job。
* **调用**：顶层 `make signoff` 和 `actions/upload-artifact@v4`。
* **共享状态**：`build/signoff`。

§6  顶层 Makefile 中的本地 CI 等价入口
--------------------------------------------------------------------------------

§6.1  `ci_unit` - 本地 Python 单测入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：在本地复用 GitHub `unit-tests` workflow 的 Python-only 检查，并串接
`ci_lint`。

**关键代码** （`Makefile:L491-L501`）：

.. code-block:: makefile

   # CI (continuous integration)
   #
   # `ci_unit` runs the same Python-only checks as the GitHub Actions
   # `unit-tests` workflow — fast, no VCS / spike-cosim required. Use this
   # locally before opening a PR.
   # -----------------------------------------------------------------------
   ci_unit:
   	@echo "=== CI: Python regression-framework tests ==="
   	cd $(TB_DIR)/scripts && python3 -m unittest tests.test_regression_framework
   	@$(MAKE) --no-print-directory ci_lint
   	@echo "=== CI unit tests complete ==="

**逐段解释**：

* 第 L491-L495 行：Makefile 注释说明 `ci_unit` 是 GitHub `unit-tests`
  workflow 的本地 Python-only 对应入口，不需要 VCS 或 spike-cosim。
* 第 L497-L499 行：target 打印标题后，进入 `$(TB_DIR)/scripts` 运行
  `python3 -m unittest tests.test_regression_framework`。
* 第 L500 行：Python 单测后调用 `ci_lint`。
* 第 L501 行：全部完成后打印结束信息。

**接口关系**：

* **被调用**：本地 `make ci_unit`。
* **调用**：Python `unittest` 和 `ci_lint`。
* **共享状态**：`TB_DIR` 和本地 Python 环境。

§6.2  `ci_lint` - 本地 riscv-dv YAML sanity
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：用一行 Python 校验 riscv-dv extension testlist 是非空 list、名称无重复、
并含 `test`、`description`、`rtl_test` 字段。

**关键代码** （`Makefile:L503-L513`）：

.. code-block:: makefile

   ci_lint:
   	@echo "=== CI: testlist YAML sanity ==="
   	@python3 -c "import yaml, pathlib; \
   tl = pathlib.Path('$(TB_DIR)/riscv_dv_extension/testlist.yaml'); \
   tests = yaml.safe_load(tl.read_text()); \
   assert isinstance(tests, list) and tests, 'testlist must be non-empty list'; \
   names = [t['test'] for t in tests]; \
   dups = [n for n in set(names) if names.count(n) > 1]; \
   assert not dups, f'duplicate test names: {dups}'; \
   [t.update({'_': None}) for t in tests if all(k in t for k in ('test','description','rtl_test'))]; \
   print(f'testlist.yaml OK: {len(tests)} tests')"

**逐段解释**：

* 第 L503-L505 行：target 打印 YAML sanity 标题，并启动内联 Python。
* 第 L506-L508 行：读取 `$(TB_DIR)/riscv_dv_extension/testlist.yaml`，
  要求顶层是非空 list。
* 第 L509-L511 行：提取 `test` 字段并检查重复名称。
* 第 L512 行：表达式只对同时含 `test`、`description`、`rtl_test` 的 entry
  执行 `update`；它不会显式失败缺字段 entry。GitHub workflow 的内联 Python
  在这一点上更严格，会对缺字段 entry `assert` 失败。
* 第 L513 行：通过时打印 test 数。

**接口关系**：

* **被调用**：`make ci_lint` 或 `make ci_unit`。
* **调用**：Python、PyYAML。
* **共享状态**：riscv-dv testlist。

§6.3  `nightly` 和 `run_regress` - 非 GitHub 专属回归入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：顶层 Makefile 还提供本地 `nightly`、`weekly`、`regress` 和
`run_regress` target；GitHub nightly workflow 调的是 `signoff`，不是这里的
`nightly` target。

**关键代码** （`Makefile:L390-L402`）：

.. code-block:: makefile

   # -----------------------------------------------------------------------
   # Nightly regression
   # -----------------------------------------------------------------------
   nightly: compile
   	@echo "=== Running nightly regression ==="
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \
   	  --iterations 1 \
   	  --parallel $(PARALLEL) \
   	  --output $(BUILD_DIR)/nightly \
   	  $(if $(filter 1,$(COV)),--coverage,)
   	@echo "=== Nightly regression complete ==="

**逐段解释**：

* 第 L393 行：本地 `nightly` target 依赖 `compile`。
* 第 L395-L401 行：它调用 `run_regress.py`，testlist 是
  `$(DV_EXT_DIR)/testlist.yaml`，iterations 固定为 1，parallel 来自 Make
  变量，输出到 `build/nightly`，`COV=1` 时追加 `--coverage`。
* 第 L402 行：命令完成后打印结束信息。

**关键代码** （`Makefile:L417-L435`）：

.. code-block:: makefile

   # -----------------------------------------------------------------------
   # Full regression via Python script
   # -----------------------------------------------------------------------
   regress: compile
   	python3 $(SCRIPTS_DIR)/run_regress.py \
   	  --testlist $(DV_EXT_DIR)/testlist.yaml \
   	  --simulator $(SIMULATOR) \
   	  --iterations $(ITERATIONS) \
   	  --parallel $(PARALLEL) \
   	  --output $(BUILD_DIR)/regression
   
   run_regress: compile

**逐段解释**：

* 第 L420-L426 行：`regress` target 也依赖 compile，调用 `run_regress.py`
  读取 riscv-dv testlist，iterations/parallel 来自 Make 变量，输出到
  `build/regression`。
* 第 L428-L435 行：`run_regress` target 使用 `TEST_LIST` 选择 directed
  testlist 或 riscv-dv testlist，并允许 `OUT` 覆盖输出目录。片段结尾显示
  `COV=1` 时会追加 `--coverage`。

**接口关系**：

* **被调用**：本地 make 或自动化脚本。
* **调用**：`compile`、`run_regress.py`。
* **共享状态**：`BUILD_DIR`、`DV_EXT_DIR`、`TEST_LIST`、`OUT`、`COV`。

§7  文档构建入口
--------------------------------------------------------------------------------

§7.1  `manual` / `manual_html` target
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：顶层 Makefile 提供中文手册 PDF 和 HTML 预览入口；当前 GitHub
workflow 未调用这两个 target。

**关键代码** （`Makefile:L515-L562`）：

.. code-block:: makefile

   # -----------------------------------------------------------------------
   # Documentation
   #
   # `make manual` 构建中文 Sphinx 参考手册（PDF）。
   # `make manual_html` 构建 HTML 预览，用于当前 Python 3.6 环境下做结构检查。
   # 依赖：pip install -r docs/requirements-docs.txt（推荐 Python 3.10+）。
   # -----------------------------------------------------------------------
   # -----------------------------------------------------------------------
   # Lint (Verible + Verilator) — issue 58
   # -----------------------------------------------------------------------

**逐段解释**：

* 第 L515-L520 行：注释说明 `make manual` 构建 PDF，`make manual_html` 构建
  HTML 预览，并指出依赖安装命令。
* 第 L522-L524 行：紧随其后的注释进入 lint target 区域；文档 target 的 recipe
  在后面的 L558-L562。

**关键代码** （`Makefile:L558-L562`）：

.. code-block:: makefile

   manual:
   	@bash docs/build_manual_pdf.sh
   
   manual_html:
   	@sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

**逐段解释**：

* 第 L558-L559 行：`manual` 调用 :file:`docs/build_manual_pdf.sh`。
* 第 L561-L562 行：`manual_html` 直接运行 `sphinx-build -b html`，输入目录是
  `docs/sphinx_cn/source`，输出目录是 `docs/sphinx_cn/build/html`。

**接口关系**：

* **被调用**：本地 `make manual` 或 `make manual_html`。
* **调用**：`docs/build_manual_pdf.sh` 或 `sphinx-build`。
* **共享状态**：`docs/sphinx_cn/build`。

§7.2  `docs/build_manual_pdf.sh` - rinoh PDF 构建脚本
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：检查 `sphinx-build` 是否可用，运行 rinoh builder，并确认 PDF 输出。

**关键代码** （`docs/build_manual_pdf.sh:L1-L13`）：

.. code-block:: bash

   #!/bin/bash
   # 构建 EH2 UVM 验证平台中文手册（PDF）
   #
   # 依赖：sphinx + rinohtype（pip install -r docs/requirements-docs.txt）
   # 输出：docs/sphinx_cn/build/rinoh/EH2_UVM_Verification_Platform.pdf
   set -euo pipefail
   
   ROOT="$(cd "$(dirname "$0")/.." && pwd)"
   SRC="$ROOT/docs/sphinx_cn/source"
   OUT="$ROOT/docs/sphinx_cn/build/rinoh"
   
   # 把本地 ~/.local/bin 加进 PATH（pip install --user 后 sphinx-build 在那里）
   export PATH="$HOME/.local/bin:$PATH"

**逐段解释**：

* 第 L1-L6 行：脚本使用 bash，开启 `set -euo pipefail`，注释说明依赖和输出
  PDF 路径。
* 第 L8-L10 行：根据脚本位置推导 repo root、Sphinx source 和 rinoh 输出目录。
* 第 L12-L13 行：把用户本地 pip 安装路径加入 PATH。

**关键代码** （`docs/build_manual_pdf.sh:L15-L38`）：

.. code-block:: bash

   if ! command -v sphinx-build >/dev/null 2>&1; then
       cat <<EOF
   错误：未找到 sphinx-build。请先安装依赖：
   
       pip install --user -r $ROOT/docs/requirements-docs.txt
   
   然后将 ~/.local/bin 加入 PATH。
   EOF
       exit 1
   fi

**逐段解释**：

* 第 L15-L24 行：缺少 `sphinx-build` 时打印安装指令并退出 1。

**关键代码** （`docs/build_manual_pdf.sh:L26-L38`）：

.. code-block:: bash

   mkdir -p "$OUT"
   sphinx-build -b rinoh "$SRC" "$OUT"
   
   PDF="$OUT/EH2_UVM_Verification_Platform.pdf"
   if [[ -f "$PDF" ]]; then
       echo ""
       echo "PDF 已生成：$PDF"
       ls -la "$PDF"
   else
       echo "未找到 PDF。输出目录："
       ls -la "$OUT" || true
       exit 1
   fi

**逐段解释**：

* 第 L26-L27 行：创建输出目录并执行 `sphinx-build -b rinoh`。
* 第 L29-L33 行：PDF 文件存在时打印路径并列出文件。
* 第 L34-L38 行：PDF 不存在时列出输出目录并退出 1。

**接口关系**：

* **被调用**：`make manual`。
* **调用**：`sphinx-build -b rinoh`。
* **共享状态**：`docs/sphinx_cn/build/rinoh`。

§7.3  `conf.py` - builder 相关配置
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：Sphinx 配置根据 builder 选择是否加载 rinoh，并配置 HTML theme 和
PDF 输出文档。

**关键代码** （`docs/sphinx_cn/source/conf.py:L28-L49`）：

.. code-block:: python

   extensions = [
       "sphinx.ext.intersphinx",
       "sphinx.ext.todo",
       "sphinx.ext.viewcode",
   ]
   
   # 可选扩展 - 未安装时静默跳过
   for ext in ["sphinx_copybutton", "myst_parser"]:
       try:
           __import__(ext)
           extensions.append(ext)
       except ImportError:
           pass

   # sphinx-tabs 是 v2 手册的交互式分流入口；本地旧环境未安装时使用兼容 fallback。
   try:
       __import__("sphinx_tabs.tabs")
       extensions.append("sphinx_tabs.tabs")
   except ImportError:
       extensions.append("eh2_tabs_fallback")

**逐段解释**：

* 第 L28-L32 行：基础扩展包含 intersphinx、todo 和 viewcode。
* 第 L35-L41 行：`sphinx_copybutton` 和 `myst_parser` 可导入时加入 extensions。
  v2-11 起，`sphinx-copybutton` 已写入 `docs/requirements-docs.txt`，因此正式文档环境
  应提供 bash 代码块复制按钮；本地旧环境缺包时仍可跳过。
* 第 L44-L49 行：`sphinx-tabs` 安装时使用官方 tab UI；未安装时使用
  `eh2_tabs_fallback`，保证 v2-10 的 tab 内容在旧 Sphinx 环境中也能构建。

**关键代码** （`docs/sphinx_cn/source/conf.py:L51-L63`）：

.. code-block:: python

   if _requested_builder() == "rinoh":
       try:
           import rinoh.frontend.sphinx  # noqa: F401
       except Exception as exc:
           raise RuntimeError(
               "rinohtype is required for the rinoh PDF builder. "
               "Use Python 3.10+ and install docs/requirements-docs.txt, "
               "or build HTML/source docs without -b rinoh."
           ) from exc
       extensions.append("rinoh.frontend.sphinx")

**逐段解释**：

* 第 L51-L63 行：只有 builder 是 `rinoh` 时才要求 `rinoh.frontend.sphinx`；
  导入失败会抛出 RuntimeError，并提示安装 docs 依赖。

**关键代码** （`docs/sphinx_cn/source/conf.py:L101-L106`）：

.. code-block:: python

   # -- Copybutton -------------------------------------------------------------
   copybutton_prompt_text = r"^\s*(\$|#|>>>|\.\.\.)\s+"
   copybutton_prompt_is_regexp = True
   copybutton_remove_prompts = True
   copybutton_only_copy_prompt_lines = False
   copybutton_copy_empty_lines = False

**逐段解释**：

* 第 L101-L106 行：copybutton 会剥离 shell、root shell、Python REPL 和续行提示符，
  并且不复制空行。这让读者可以直接复制 `.. code-block:: bash` 中的命令，而不会把
  `$` 或 `#` 提示符带进终端。

**关键代码** （`docs/sphinx_cn/source/conf.py:L64-L78`）：

.. code-block:: python

   # 尝试 sphinx_book_theme，未安装时回退到 alabaster
   try:
       import sphinx_book_theme  # noqa: F401
       html_theme = "sphinx_book_theme"
       html_theme_options = {
           "repository_url": "https://github.com/chipsalliance/Cores-VeeR-EH2",
           "use_repository_button": True,
           "use_download_button": True,
           "use_fullscreen_button": True,
           "toc_title": "本页目录",
           "show_navbar_depth": 2,
       }
   except ImportError:
       html_theme = "alabaster"
       html_theme_options = {}

**逐段解释**：

* 第 L64-L75 行：HTML 优先使用 `sphinx_book_theme`，并配置仓库链接、下载按钮、
  全屏按钮和导航深度。
* 第 L76-L78 行：主题不可导入时回退到 `alabaster`。

**关键代码** （`docs/sphinx_cn/source/conf.py:L94-L106`）：

.. code-block:: python

   # -- rinohtype PDF 配置 -----------------------------------------------------
   rinoh_documents = [
       {
           "doc": "index",
           "target": "EH2_UVM_Verification_Platform",
           "title": "EH2 UVM 验证平台 — 参考手册",
           "subtitle": "VeeR EH2 双线程 RV32IMAC 处理器 UVM 验证框架",
           "author": author,
           "template": "book",
       }
   ]
   
   rinoh_paper_size = "A4"

**逐段解释**：

* 第 L95-L104 行：rinoh 输出从 `index` 生成
  `EH2_UVM_Verification_Platform`，标题和副标题在配置中固定。
* 第 L106 行：PDF 纸张大小为 A4。

**接口关系**：

* **被调用**：`sphinx-build`。
* **调用**：Sphinx extension import、theme import 和 rinoh extension。
* **共享状态**：Sphinx builder 参数和 docs 依赖。

§8  VCS sign-off 证据与 CI artifact 的关系
--------------------------------------------------------------------------------

§8.1  当前 sign-off replay 命令
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：说明当前 replay 使用已有 stage result、block-level LEC summary
和 coverage path，而不是重新运行所有 stage。默认 replay 读取 VCS/URG 口径；如果
显式传入 NC/IMC dashboard，报告必须标明它是完整备选 simulator 的 cross-check 或备选证据。

**关键命令**：

.. code-block:: bash

   make signoff_replay \
     STAGE_DATA_DIR=build/signoff \
     SIGNOFF_REPLAY_OUT=build/signoff_replay \
     LEC_BLOCKLEVEL=1 \
     LEC_SUMMARY_PATH=syn/build/lec_summary.txt

**逐段解释**：

* ``STAGE_DATA_DIR`` 必须包含 ``runs/``，其中按 stage 保存 smoke、directed、
  cosim、riscvdv、csr_unit 和 compliance 结果。
* ``LEC_SUMMARY_PATH`` 指向 block-level Formality summary；当前 demo 的 TOTAL 行
  是 31635 passing、0 failing、0 unverified。
* coverage path 优先来自 ``$(STAGE_DATA_DIR)/cov_merged/dashboard.txt``。该文件由
  ``merge_cov.py`` 调用 URG 生成，不从 NC 数据库派生。

**接口关系**：

* **被调用**：release replay 手工命令。
* **调用**：`signoff.py --gate-only`。
* **共享状态**：`build/signoff`、`syn/build/lec_summary.txt`、
  `build/signoff/cov_merged/dashboard.txt`、`build/signoff_replay`。

§8.2  当前 artifact 表
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**职责**：说明 CI 上传的当前 run artifact 与本地 sign-off 输出目录的对应关系。

**关键 artifact**：

.. code-block:: bash

   | Artifact | Path |
   |---|---|
   | Sign-off JSON | `build/signoff/signoff_status.json` |
   | Sign-off Markdown | `build/signoff/signoff_report.md` |
   | HTML dashboard | `build/signoff/report.html` |
   | IFV final log | `dv/formal/build/ifv_final.log` |
   | Coverage dashboard | `build/signoff/cov_merged/dashboard.txt` |
   | LEC summary | `syn/build/lec_summary.txt` |
   | VCS compile log | `build/signoff/compile.log` |
   | ADR index | `docs/adr/INDEX.md` |

**逐段解释**：

* sign-off JSON、Markdown 和 HTML dashboard 来自同一个 ``SIGNOFF_OUT``。
* formal、coverage 和 LEC evidence 分别在 IFV log、URG dashboard 和 LEC summary。
* ``compile.log`` 用于证明该 run 的编译参数包含 VCS coverage instrumentation。

**接口关系**：

* **被调用**：release 审计和人工验收。
* **调用**：无下层函数。
* **共享状态**：CI artifact 路径和本地 ``SIGNOFF_OUT`` 目录。

§9  参考资料
--------------------------------------------------------------------------------

* workflow：:file:`/home/host/eh2-veri/.github/workflows/unit-tests.yml`
* workflow：:file:`/home/host/eh2-veri/.github/workflows/lint.yml`
* workflow：:file:`/home/host/eh2-veri/.github/workflows/sim.yml`
* workflow：:file:`/home/host/eh2-veri/.github/workflows/nightly.yml`
* Make 入口：:file:`/home/host/eh2-veri/Makefile`
* 文档构建脚本：:file:`/home/host/eh2-veri/docs/build_manual_pdf.sh`
* Sphinx 配置：:file:`/home/host/eh2-veri/docs/sphinx_cn/source/conf.py`
* 项目入口：:file:`/home/host/eh2-veri/README.md`
* LEC 证据：:file:`/home/host/eh2-veri/syn/build/lec_summary.txt`
* 关联章节：:ref:`build_flow`、:ref:`regression_flow`、:ref:`lint_flow`、
  :ref:`signoff_flow`、:ref:`scripts_reference`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页介绍的 Makefile target 或 Python 脚本入口是什么，默认 simulator 是否仍是 VCS？
2. 该流程产生哪些 build 目录、log、JSON、coverage database 或 HTML artifact？
3. VCS/URG 路径和 NC/IMC 备选路径在本页中是否被分开解释？
4. 失败时第一份应打开的日志是哪一个，第二步应检查哪个变量或 YAML 配置？
5. 本页中的 sign-off 数字是否仍为 9/9 PASS、102/104、LEC 31635/31635 和 LINE 95.05%？
