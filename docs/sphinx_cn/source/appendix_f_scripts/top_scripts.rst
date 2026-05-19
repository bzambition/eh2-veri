.. _appendix_f_scripts_top_scripts:
.. _appendix_f_scripts/top_scripts:

顶层 Shell 脚本
================

:status: draft
:source: env.sh, docs/build_manual_pdf.sh, scripts/clean_workspace.sh, scripts/rc4_self_check.sh, scripts/rc5_self_check.sh, dv/uvm/core_eh2/scripts/objdump.sh, dv/uvm/core_eh2/scripts/prettify.sh
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

本章解释 EH2-Veri 仓库中的顶层 Shell 入口、清理脚本、RC 自检脚本、中文手册
PDF 构建脚本，以及 UVM 输出目录下的两个后处理辅助脚本。所有行为说明均从
上方 ``:commit:`` 对应源码倒推；每段代码片段不超过 30 行。

§1 Shell 脚本总览
--------------------------------------------------------------------------------

顶层 Shell 脚本不实现 UVM testbench 本身，也不替代 Makefile flow。它们承担
三类外部入口职责：准备环境变量、清理或归档工具产物、对 release candidate
状态做只读检查。`dv/uvm/core_eh2/scripts/` 下的两个小脚本只处理仿真输出文件。

.. code-block:: text

   user shell
      |
      +-- source env.sh
      |      |
      |      +-- export EH2_VERIF_ROOT / RV_ROOT / GCC_PREFIX / PATH
      |
      +-- bash docs/build_manual_pdf.sh
      |      |
      |      +-- sphinx-build -b rinoh -> docs/sphinx_cn/build/rinoh/*.pdf
      |
      +-- bash scripts/clean_workspace.sh [mode]
      |      |
      |      +-- remove locks / archive historical build runs / move old docs
      |
      +-- bash scripts/rc4_self_check.sh
      +-- bash scripts/rc5_self_check.sh
             |
             +-- grep/find checks over RTL, formal build, syn build and docs

脚本边界：

* `env.sh` 只通过 `export` 修改当前 shell 的环境，因此必须用 `source env.sh`
  而不是直接执行。
* `docs/build_manual_pdf.sh` 调用 `sphinx-build -b rinoh`，输出 PDF，不修改
  Sphinx 源文件。
* `scripts/clean_workspace.sh` 是唯一会删除、移动或归档文件的脚本；它通过
  `--dry-run` 提供命令预览。
* `scripts/rc4_self_check.sh` 和 `scripts/rc5_self_check.sh` 主要通过
  `grep`、`find`、`wc` 和文件存在性检查生成 PASS/WARN/FAIL 文本。
* `objdump.sh` 与 `prettify.sh` 在仿真输出树中查找文件，并把反汇编或排版后的
  结果写回同级目录。

§2 ``env.sh`` — 交互式环境入口
--------------------------------------------------------------------------------

职责：设置 EH2-Veri 的仓库根目录、外部 RTL 根目录、RISC-V GCC 工具链路径、
仿真器默认值、ABI 编译参数和验证平台子目录变量。

关键代码（``env.sh:L1-L13``）：

.. code-block:: bash

   #!/bin/bash
   # EH2 UVM Verification Platform - Environment Setup
   # Source this file: source env.sh

   # Project root
   export EH2_VERIF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

   # RTL source
   export RV_ROOT="/home/host/Cores-VeeR-EH2"

   # RISC-V GCC toolchain
   export GCC_PREFIX="/home/host/gcc-riscv64-unknown-elf"
   export PATH="${GCC_PREFIX}/bin:${PATH}"

逐段解释：

* 第 L1-L3 行：脚本声明为 Bash，并在注释中要求使用 `source env.sh`。这与
  后续 `export` 变量有关；若以子进程执行，变量不会留在调用者 shell 中。
* 第 L5-L6 行：`EH2_VERIF_ROOT` 通过 `${BASH_SOURCE[0]}` 所在目录计算，而不是
  依赖当前工作目录。
* 第 L8-L9 行：`RV_ROOT` 固定指向 `/home/host/Cores-VeeR-EH2`，作为外部 RTL
  源码位置。
* 第 L11-L13 行：`GCC_PREFIX` 指向 RISC-V bare-metal GCC 安装目录，并把
  `$GCC_PREFIX/bin` 放到 `PATH` 前端。

接口关系：

* 被调用：用户交互式 shell 或 README 中的环境准备步骤。
* 调用：无外部命令调用，除命令替换中的 `cd`、`dirname`、`pwd`。
* 共享状态：写当前 shell 环境变量 `EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX`
  和 `PATH`。

关键代码（``env.sh:L15-L28``）：

.. code-block:: bash

   # QEMU (for co-simulation)
   export QEMU_BIN="/home/host/eh2-verification/qemu-eh2/build/qemu-system-riscv32"

   # Simulator selection (vcs/xlm/questa)
   export EH2_SIMULATOR="vcs"

   # Architecture flags
   export ABI="-mabi=ilp32 -march=rv32imac"

   # Verification platform paths
   export EH2_DV_ROOT="${EH2_VERIF_ROOT}/dv"
   export EH2_UVM_ROOT="${EH2_DV_ROOT}/uvm/core_eh2"
   export EH2_SHARED_ROOT="${EH2_VERIF_ROOT}/shared"
   export EH2_VENDOR_ROOT="${EH2_VERIF_ROOT}/vendor"

逐段解释：

* 第 L15-L16 行：`QEMU_BIN` 固定到本地 `qemu-system-riscv32` 可执行文件路径。
  注释说明用途是 co-simulation。
* 第 L18-L19 行：`EH2_SIMULATOR` 默认值是 `vcs`；注释列出可选名称
  `vcs/xlm/questa`。
* 第 L21-L22 行：`ABI` 保存 GCC 编译参数，源码中使用 `-mabi=ilp32` 和
  `-march=rv32imac`。
* 第 L24-L28 行：`EH2_DV_ROOT`、`EH2_UVM_ROOT`、`EH2_SHARED_ROOT`、
  `EH2_VENDOR_ROOT` 都从 `EH2_VERIF_ROOT` 派生，避免重复硬编码仓库子目录。

接口关系：

* 被调用：后续 shell 命令、Makefile 或用户手工命令可以读取这些变量。
* 调用：无。
* 共享状态：只修改环境变量，不创建文件。

关键代码（``env.sh:L30-L37``）：

.. code-block:: bash

   echo "=========================================="
   echo "EH2 UVM Verification Platform"
   echo "=========================================="
   echo "EH2_VERIF_ROOT: ${EH2_VERIF_ROOT}"
   echo "RV_ROOT:        ${RV_ROOT}"
   echo "GCC_PREFIX:     ${GCC_PREFIX}"
   echo "SIMULATOR:      ${EH2_SIMULATOR}"
   echo "=========================================="

逐段解释：

* 第 L30-L32 行：打印固定标题，帮助用户确认脚本已经被执行。
* 第 L33-L36 行：打印 `EH2_VERIF_ROOT`、`RV_ROOT`、`GCC_PREFIX` 和
  `EH2_SIMULATOR` 的最终值。脚本没有打印 `PATH`、`QEMU_BIN` 或所有派生目录。
* 第 L37 行：输出结束分隔线。

接口关系：

* 被调用：`source env.sh` 的终端会直接看到这些 `echo` 输出。
* 调用：`echo`。
* 共享状态：只读前面已经导出的变量。

§3 ``docs/build_manual_pdf.sh`` — 中文手册 PDF 构建
--------------------------------------------------------------------------------

职责：检查 `sphinx-build` 是否可用，并用 `rinoh` builder 从
`docs/sphinx_cn/source` 生成 `EH2_UVM_Verification_Platform.pdf`。

关键代码（``docs/build_manual_pdf.sh:L1-L13``）：

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

逐段解释：

* 第 L1-L5 行：脚本注释明确输入是中文 Sphinx 手册，依赖是 `sphinx` 和
  `rinohtype`，输出 PDF 位于 `docs/sphinx_cn/build/rinoh/`。
* 第 L6 行：`set -euo pipefail` 使未定义变量、命令失败、管道失败都能让脚本
  终止。
* 第 L8-L10 行：`ROOT` 从脚本所在目录上一级计算，`SRC` 和 `OUT` 都由 `ROOT`
  派生。
* 第 L12-L13 行：把 `$HOME/.local/bin` 放入 `PATH`，覆盖注释中提到的
  `pip install --user` 场景。

接口关系：

* 被调用：用户执行 `bash docs/build_manual_pdf.sh`。
* 调用：`cd`、`dirname`、`pwd`。
* 共享状态：读取仓库中的 Sphinx 源目录，写 `docs/sphinx_cn/build/rinoh`。

关键代码（``docs/build_manual_pdf.sh:L15-L24``）：

.. code-block:: bash

   if ! command -v sphinx-build >/dev/null 2>&1; then
       cat <<EOF
   错误：未找到 sphinx-build。请先安装依赖：

       pip install --user -r $ROOT/docs/requirements-docs.txt

   然后将 ~/.local/bin 加入 PATH。
   EOF
       exit 1
   fi

逐段解释：

* 第 L15 行：用 `command -v sphinx-build` 判断当前 `PATH` 是否能找到
  `sphinx-build`。
* 第 L16-L22 行：缺失依赖时通过 heredoc 打印中文错误提示和安装命令，安装路径
  使用前面计算出的 `$ROOT`。
* 第 L23-L24 行：依赖缺失时返回 exit code 1，不继续创建输出目录。

接口关系：

* 被调用：脚本主流程在调用 `sphinx-build` 之前执行该检查。
* 调用：`command`、`cat`。
* 共享状态：读取 `PATH` 和 `ROOT`。

关键代码（``docs/build_manual_pdf.sh:L26-L38``）：

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

逐段解释：

* 第 L26 行：确保 `rinoh` 输出目录存在。
* 第 L27 行：实际构建命令是 `sphinx-build -b rinoh "$SRC" "$OUT"`。
* 第 L29-L33 行：构建后检查固定 PDF 文件名是否存在；存在时打印路径并执行
  `ls -la`。
* 第 L34-L38 行：PDF 缺失时列出输出目录内容，`ls` 本身失败也不覆盖后续
  `exit 1`。

接口关系：

* 被调用：依赖检查通过后的主流程。
* 调用：`mkdir`、`sphinx-build`、`echo`、`ls`。
* 共享状态：写 `docs/sphinx_cn/build/rinoh`，读取 `SRC`、`OUT`、`PDF`。

§4 ``scripts/clean_workspace.sh`` — 工作区清理与归档
--------------------------------------------------------------------------------

职责：从仓库根目录执行 EDA 锁文件清理、历史 sign-off 输出归档、历史临时 run
归档、历史诊断文档移动，并在不同模式下跳过或限制部分动作。

§4.1 严格模式、根目录和保留名单
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L1-L24``）：

.. code-block:: bash

   #!/bin/bash
   # Clean EDA tool residuals and archive obsolete EH2 sign-off outputs.
   #
   # Default mode removes root/syn lock and session leftovers, archives loose
   # build logs plus historical run directories, trims coverage backups, and moves
   # old diagnostic documents into stable locations.

   set -euo pipefail

   ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
   cd "${ROOT_DIR}"

   shopt -s nullglob

   DRY_RUN=0
   ARCHIVE_ONLY=0
   ALL=0
   LCK_ONLY=0

   BUILD_ARCHIVE_STAMP="$(date +%Y%m%d)"
   BUILD_ARCHIVE_BACKING_DIR=".scratch/r5_build_archive_${BUILD_ARCHIVE_STAMP}"
   BUILD_ARCHIVE_LINK="build/archive_signoffs_${BUILD_ARCHIVE_STAMP}"
   BUILD_ARCHIVE_READY=0

逐段解释：

* 第 L1-L6 行：注释说明默认模式会删除根目录和 `syn/` 的锁/session 残留，
  归档 build log 和历史 run，并移动旧诊断文档。
* 第 L8 行：使用 `set -euo pipefail`，使脚本在错误、未定义变量或管道失败时
  退出。
* 第 L10-L11 行：根据脚本位置计算仓库根目录，并立即 `cd` 到根目录。后续相对
  路径都基于仓库根。
* 第 L13 行：开启 `nullglob`，使不存在的 glob 展开为空列表。
* 第 L15-L18 行：四个模式开关默认都是 0。
* 第 L20-L23 行：归档目录名包含当天 `YYYYMMDD`，真实目录在 `.scratch/`，
  `build/` 下只放符号链接。

接口关系：

* 被调用：脚本启动时先执行该初始化段。
* 调用：`date`、`cd`、`dirname`、`pwd`、`shopt`。
* 共享状态：设置全局变量 `ROOT_DIR`、`DRY_RUN`、`ARCHIVE_ONLY`、`ALL`、
  `LCK_ONLY`、`BUILD_ARCHIVE_*`。

关键代码（``scripts/clean_workspace.sh:L25-L42``）：

.. code-block:: bash

   BUILD_PRESERVE_BASENAMES=(
     nightly
     cov.vdb
     cov
     simv
     simv.daidir
     simv.vdb
     simv_compliance
     simv_compliance.daidir
     libcosim.so
     spike_objs
     csrc
     compile.log
     compliance_tb_compile.log
     archive_signoffs_*
   )

逐段解释：

* 第 L25 行：定义 `BUILD_PRESERVE_BASENAMES` 数组，后续用 basename 匹配
  `build/` 下需要保留的条目。
* 第 L26-L41 行：保留名单覆盖 nightly、coverage 数据库、
  VCS 可执行文件及目录、compliance 编译产物、cosim 动态库、Spike object 目录、
  compile log，以及 `archive_signoffs_*` 链接。

接口关系：

* 被调用：`build_entry_is_preserved()` 读取该数组。
* 调用：无。
* 共享状态：定义全局数组 `BUILD_PRESERVE_BASENAMES`。

§4.2 ``usage()`` 与参数解析
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L44-L64``）：

.. code-block:: bash

   usage() {
     cat <<'USAGE'
   Usage: bash scripts/clean_workspace.sh [--dry-run] [--archive-only] [--all] [--lck-only]

     --dry-run       Print actions without removing or moving files.
     --archive-only  Only archive historical sign-off/docs; do not delete tool files.
     --all           Also remove existing archive_signoffs links and backing archives.
     --lck-only      Remove only Formality lock/session files from root and syn/.
   USAGE
   }

   for arg in "$@"; do
     case "$arg" in
       --dry-run) DRY_RUN=1 ;;
       --archive-only) ARCHIVE_ONLY=1 ;;
       --all) ALL=1 ;;
       --lck-only) LCK_ONLY=1 ;;
       -h|--help) usage; exit 0 ;;
       *) echo "ERROR: unknown argument: $arg" >&2; usage; exit 2 ;;
     esac
   done

逐段解释：

* 第 L44-L53 行：`usage()` 只打印用法，不修改模式变量。
* 第 L55-L60 行：四个长选项分别把全局模式变量置为 1。
* 第 L61 行：`-h` 或 `--help` 打印 usage 后以 0 退出。
* 第 L62 行：未知参数输出到 stderr，打印 usage，并以 exit code 2 退出。

接口关系：

* 被调用：参数解析中的 `-h|--help` 和未知参数分支。
* 调用：`cat`、`echo`。
* 共享状态：写 `DRY_RUN`、`ARCHIVE_ONLY`、`ALL`、`LCK_ONLY`。

§4.3 ``say()`` 与 ``run()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L66-L80``）：

.. code-block:: bash

   say() {
     echo "$@"
   }

   run() {
     if [[ "$DRY_RUN" == "1" ]]; then
       printf '[dry-run]'
       for arg in "$@"; do
         printf ' %q' "$arg"
       done
       printf '\n'
     else
       "$@"
     fi
   }

逐段解释：

* 第 L66-L68 行：`say()` 是 `echo "$@"` 的薄封装，用于统一状态输出。
* 第 L70-L77 行：`run()` 在 `DRY_RUN=1` 时不执行命令，而是用 `%q` 打印 shell
  可读的参数列表。
* 第 L78-L79 行：非 dry-run 模式下，`run()` 直接执行传入命令和参数。

接口关系：

* 被调用：清理、归档和移动函数都通过 `say()` 输出状态，通过 `run()` 执行
  可能修改文件系统的命令。
* 调用：`echo`、`printf`，或调用者传入的实际命令。
* 共享状态：读取 `DRY_RUN`。

§4.4 ``build_entry_is_preserved()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L82-L91``）：

.. code-block:: bash

   build_entry_is_preserved() {
     local base="$1"
     local keep
     for keep in "${BUILD_PRESERVE_BASENAMES[@]}"; do
       case "$base" in
         $keep) return 0 ;;
       esac
     done
     return 1
   }

逐段解释：

* 第 L83 行：函数输入是一个 basename，而不是完整路径。
* 第 L85-L88 行：遍历 `BUILD_PRESERVE_BASENAMES`，用 shell `case` 支持
  `archive_signoffs_*` 这类通配模式。
* 第 L87 行：命中保留模式时返回 0。
* 第 L90 行：遍历完成仍未命中时返回 1。

接口关系：

* 被调用：`archive_signoffs()` 和 `archive_legacy_runs()`。
* 调用：无外部命令。
* 共享状态：读取 `BUILD_PRESERVE_BASENAMES`。

§4.5 ``ensure_build_archive()``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L93-L115``）：

.. code-block:: bash

   ensure_build_archive() {
     if [[ "$BUILD_ARCHIVE_READY" == "1" ]]; then
       return
     fi

     if [[ "$ALL" == "1" ]]; then
       say "  --all: removing existing archive links and backing archives"
       remove_paths "archive links" build/archive_signoffs_*
       remove_paths "archive backing directories" .scratch/r5_build_archive_*
     fi

     if [[ "$DRY_RUN" == "0" ]]; then
       mkdir -p build "$BUILD_ARCHIVE_BACKING_DIR"
       if [[ ! -e "$BUILD_ARCHIVE_LINK" && ! -L "$BUILD_ARCHIVE_LINK" ]]; then
         ln -s "../${BUILD_ARCHIVE_BACKING_DIR}" "$BUILD_ARCHIVE_LINK"
       fi
     else
       say "[dry-run] mkdir -p build $BUILD_ARCHIVE_BACKING_DIR"
       say "[dry-run] ln -s ../$BUILD_ARCHIVE_BACKING_DIR $BUILD_ARCHIVE_LINK"
     fi

     BUILD_ARCHIVE_READY=1
   }

逐段解释：

* 第 L94-L96 行：`BUILD_ARCHIVE_READY=1` 时直接返回，避免重复创建目录或链接。
* 第 L98-L102 行：`--all` 模式会先删除已有 `build/archive_signoffs_*` 链接和
  `.scratch/r5_build_archive_*` 归档目录。
* 第 L104-L108 行：非 dry-run 模式下创建 `build` 和 backing directory；如果
  `BUILD_ARCHIVE_LINK` 不存在，则创建指向 `.scratch` backing directory 的符号链接。
* 第 L109-L112 行：dry-run 模式只打印将要执行的 `mkdir` 和 `ln -s`。
* 第 L114 行：成功或 dry-run 打印后，把 `BUILD_ARCHIVE_READY` 标记为 1。

接口关系：

* 被调用：`archive_signoffs()`、`archive_legacy_runs()`。
* 调用：`say()`、`remove_paths()`、`mkdir`、`ln`。
* 共享状态：读写 `BUILD_ARCHIVE_READY`，读取 `ALL`、`DRY_RUN` 和
  `BUILD_ARCHIVE_*`。

§4.6 路径计数、删除和归档原语
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L117-L140``）：

.. code-block:: bash

   count_existing() {
     local n=0
     local item
     for item in "$@"; do
       [[ -e "$item" || -L "$item" ]] && n=$((n + 1))
     done
     echo "$n"
   }

   remove_paths() {
     local kind="$1"
     shift
     local existing=()
     local p
     for p in "$@"; do
       [[ -e "$p" || -L "$p" ]] && existing+=("$p")
     done
     if [[ "${#existing[@]}" -eq 0 ]]; then
       say "  no ${kind} found"
       return
     fi
     say "  removing ${#existing[@]} ${kind}"
     run rm -rf -- "${existing[@]}"
   }

逐段解释：

* 第 L117-L124 行：`count_existing()` 统计参数中存在的普通路径或符号链接，
  并把数量输出到 stdout。
* 第 L126-L133 行：`remove_paths()` 第一个参数是显示用的 `kind`，其余参数是
  候选路径；函数先过滤出实际存在的路径。
* 第 L134-L137 行：没有可删路径时只打印状态并返回。
* 第 L138-L139 行：存在候选时通过 `run rm -rf --` 执行删除；dry-run 模式下
  由 `run()` 打印命令。

接口关系：

* 被调用：多个清理函数和 `ensure_build_archive()`。
* 调用：`say()`、`run()`、`rm`。
* 共享状态：`remove_paths()` 间接读取 `DRY_RUN`。

关键代码（``scripts/clean_workspace.sh:L142-L177``）：

.. code-block:: bash

   archive_dir() {
     local src="$1"
     local archive_dir="$2"
     if [[ ! -d "$src" ]]; then
       return
     fi
     run mkdir -p "$archive_dir"
     say "  archive $src -> $archive_dir/"
     run mv "$src" "$archive_dir/"
   }

   archive_file() {
     local src="$1"
     local archive_dir="$2"
     if [[ ! -f "$src" ]]; then
       return
     fi

逐段解释：

* 第 L142-L151 行：`archive_dir()` 只处理存在的目录；不存在时返回。归档动作
  是先创建目标目录，再把源目录 `mv` 到归档目录中。
* 第 L153-L158 行：`archive_file()` 对普通文件执行同类检查；不存在时返回。
* 第 L159-L162 行：文件归档同样先 `mkdir -p`，再 `mv` 到归档目录。

接口关系：

* 被调用：`archive_signoffs()`、`archive_legacy_runs()`。
* 调用：`run()`、`say()`、`mkdir`、`mv`。
* 共享状态：间接读取 `DRY_RUN`。

关键代码（``scripts/clean_workspace.sh:L164-L177``）：

.. code-block:: bash

   move_file_to_dir() {
     local src="$1"
     local dst="$2"
     if [[ ! -f "$src" ]]; then
       return
     fi
     run mkdir -p "$dst"
     say "  move $src -> $dst/"
     if [[ "$DRY_RUN" == "1" ]]; then
       printf '[dry-run] git mv %q %q/ || mv %q %q/\n' "$src" "$dst" "$src" "$dst"
     else
       git mv "$src" "$dst/" 2>/dev/null || mv "$src" "$dst/"
     fi
   }

逐段解释：

* 第 L164-L169 行：函数只移动存在的普通文件。
* 第 L170-L171 行：先确保目标目录存在，并打印移动方向。
* 第 L172-L173 行：dry-run 模式下打印 `git mv ... || mv ...`，但不执行移动。
* 第 L174-L176 行：非 dry-run 模式优先 `git mv`，如果失败则回退到普通 `mv`。

接口关系：

* 被调用：`archive_historical_docs()`。
* 调用：`run()`、`say()`、`printf`、`git mv`、`mv`。
* 共享状态：读取 `DRY_RUN`。

§4.7 root、``syn/`` 和 ``build/`` 清理阶段
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L179-L193``）：

.. code-block:: bash

   clean_root_locks() {
     local root_lck=(fm_shell_command*.lck formality*.lck)
     local root_fss=(*.fss)
     if [[ "$ARCHIVE_ONLY" == "1" ]]; then
       say "=== 1. 根目录 EDA 锁文件：archive-only 跳过删除 ==="
       return
     fi
     say "=== 1. 根目录 EDA 锁文件 ==="
     remove_paths "root .lck files" "${root_lck[@]:-}"
     remove_paths "root .fss session files" "${root_fss[@]:-}"
     if [[ "$LCK_ONLY" == "0" ]]; then
       remove_paths "root formal/DC residual files" formalverifier.log eh2_pkg.pvk
     fi
     say "  root lck remaining: $(count_existing ./*.lck)"
   }

逐段解释：

* 第 L180-L181 行：根目录候选包括 `fm_shell_command*.lck`、`formality*.lck` 和
  `*.fss`。
* 第 L182-L185 行：`ARCHIVE_ONLY=1` 时跳过删除。
* 第 L187-L188 行：删除根目录 `.lck` 和 `.fss` 候选。
* 第 L189-L191 行：非 `LCK_ONLY` 模式才删除 `formalverifier.log` 和
  `eh2_pkg.pvk`。
* 第 L192 行：通过 `count_existing ./*.lck` 报告剩余根目录 `.lck` 数量。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`remove_paths()`、`count_existing()`。
* 共享状态：读取 `ARCHIVE_ONLY`、`LCK_ONLY`。

关键代码（``scripts/clean_workspace.sh:L195-L212``）：

.. code-block:: bash

   clean_syn_residuals() {
     local syn_lck=(syn/*.lck)
     local syn_fss=(syn/*.fss)
     local syn_logs=(syn/*.log syn/command.log)
     local syn_misc=(syn/default.svf syn/FM_WORK syn/FM_WORK1)
     if [[ "$ARCHIVE_ONLY" == "1" ]]; then
       say "=== 2. syn/ 工具残留：archive-only 跳过删除 ==="
       return
     fi
     say "=== 2. syn/ 工具残留 ==="
     remove_paths "syn .lck files" "${syn_lck[@]:-}"
     remove_paths "syn .fss session files" "${syn_fss[@]:-}"
     if [[ "$LCK_ONLY" == "0" ]]; then
       remove_paths "syn logs" "${syn_logs[@]:-}"
       remove_paths "syn work residuals" "${syn_misc[@]:-}"
     fi
     say "  syn lck remaining: $(count_existing syn/*.lck)"
   }

逐段解释：

* 第 L196-L199 行：`syn/` 清理候选分成 lock、session、log 和 work residual。
* 第 L200-L203 行：`ARCHIVE_ONLY=1` 跳过整个 `syn/` 删除阶段。
* 第 L205-L206 行：删除 `syn/*.lck` 和 `syn/*.fss`。
* 第 L207-L210 行：非 `LCK_ONLY` 模式才删除 `syn` 日志和 Formality work 目录。
* 第 L211 行：报告剩余 `syn/*.lck` 数量。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`remove_paths()`、`count_existing()`。
* 共享状态：读取 `ARCHIVE_ONLY`、`LCK_ONLY`。

关键代码（``scripts/clean_workspace.sh:L214-L226``）：

.. code-block:: bash

   clean_build_loose() {
     if [[ "$ARCHIVE_ONLY" == "1" || "$LCK_ONLY" == "1" ]]; then
       say "=== 3. build/ 散落文件：当前模式跳过 ==="
       return
     fi
     say "=== 3. build/ 散落文件 ==="
     if [[ -d build ]]; then
       say "  loose build/*.log files are archived in the build archive stage"
       remove_paths "coverage vdb backups" build/cov.vdb.backup_* build/cov.vdb.pre_*
     else
       say "  build/ not found"
     fi
   }

逐段解释：

* 第 L215-L218 行：`ARCHIVE_ONLY` 或 `LCK_ONLY` 任一模式启用时跳过该阶段。
* 第 L219-L222 行：`build/` 存在时不在此处处理 loose log，只删除 coverage vdb
  备份。
* 第 L223-L225 行：`build/` 不存在时只打印状态，不报错。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`remove_paths()`。
* 共享状态：读取 `ARCHIVE_ONLY`、`LCK_ONLY`。

§4.8 sign-off 和历史 run 归档
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L228-L254``）：

.. code-block:: bash

   archive_signoffs() {
     if [[ "$LCK_ONLY" == "1" ]]; then
       say "=== 4. build/ 历史 sign-off 子目录：lck-only 跳过 ==="
       return
     fi

     say "=== 4. build/ 历史 sign-off 子目录 ==="
     ensure_build_archive

     local candidates=()
     local d base
     for d in build/r*_final build/sf_* build/signoff* build/final_signoff*; do
       [[ -d "$d" || -L "$d" ]] || continue
       base="$(basename "$d")"
       build_entry_is_preserved "$base" && continue
       candidates+=("$d")
     done

     if [[ "${#candidates[@]}" -eq 0 ]]; then
       say "  no historical sign-off directories found"
       return
     fi

逐段解释：

* 第 L229-L232 行：`LCK_ONLY=1` 时跳过 sign-off 目录归档。
* 第 L234-L235 行：进入阶段后先调用 `ensure_build_archive()`，确保归档目录和
  `build/` 下链接存在。
* 第 L237-L244 行：扫描历史 final、`build/sf_*`、
  `build/signoff*`、`build/final_signoff*`，只收集目录或符号链接，并跳过保留名单。
* 第 L246-L249 行：没有候选时打印状态并返回。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`ensure_build_archive()`、`basename`、`build_entry_is_preserved()`。
* 共享状态：读取 `LCK_ONLY`、`BUILD_ARCHIVE_BACKING_DIR`。

关键代码（``scripts/clean_workspace.sh:L251-L254``）：

.. code-block:: bash

     for d in "${candidates[@]}"; do
       archive_dir "$d" "$BUILD_ARCHIVE_BACKING_DIR"
     done
   }

逐段解释：

* 第 L251-L253 行：逐个候选调用 `archive_dir()`，把目录移动到 `.scratch` backing
  archive。
* 第 L254 行：结束 `archive_signoffs()`。

接口关系：

* 被调用：`archive_signoffs()` 内部候选收集完成后。
* 调用：`archive_dir()`。
* 共享状态：读取 `candidates` 和 `BUILD_ARCHIVE_BACKING_DIR`。

关键代码（``scripts/clean_workspace.sh:L256-L278``）：

.. code-block:: bash

   legacy_run_dir_should_archive() {
     local base="$1"

     case "$base" in
       r*_final|sf_*|signoff*|final_signoff*)
         return 1
         ;;
       verify_*|verify2_*|verify3_*|verify4_*|verify5_*|verify6_*|verify7_*|verify8_*)
         return 0
         ;;
       sweep_*|issue12_*|cosim_*|dryrun_*|finalcheck_*|final_*|t4_*|t7_*|post_unlock*)
         return 0
         ;;
       csr_unit_*|dret_*|test_directed*|r2*_*|r3*_*|r5_*)
         return 0
         ;;
       r5_*|cov_*|smoke)
         return 0
         ;;
     esac

     return 1
   }

逐段解释：

* 第 L256-L258 行：函数输入同样是 basename。
* 第 L260-L262 行：sign-off 类目录由 `archive_signoffs()` 处理，因此这里返回 1。
* 第 L263-L274 行：多组历史 run 命名模式返回 0，表示应该归档。
* 第 L277 行：不匹配任何模式时返回 1。

接口关系：

* 被调用：`archive_legacy_runs()`。
* 调用：无外部命令。
* 共享状态：无全局变量读写。

关键代码（``scripts/clean_workspace.sh:L280-L319``）：

.. code-block:: bash

   archive_legacy_runs() {
     if [[ "$LCK_ONLY" == "1" ]]; then
       say "=== 5. build/ 历史临时 run 与散落日志：lck-only 跳过 ==="
       return
     fi

     say "=== 5. build/ 历史临时 run 与散落日志 ==="
     if [[ ! -d build ]]; then
       say "  build/ not found"
       return
     fi

     ensure_build_archive

     local candidates=()
     local path base
     for path in build/*; do

逐段解释：

* 第 L281-L284 行：`LCK_ONLY=1` 时跳过历史 run 和 loose log 归档。
* 第 L286-L290 行：`build/` 不存在时只打印状态并返回。
* 第 L292 行：归档前调用 `ensure_build_archive()`。
* 第 L294-L296 行：初始化候选数组，准备遍历 `build/*`。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`ensure_build_archive()`。
* 共享状态：读取 `LCK_ONLY`、`BUILD_ARCHIVE_BACKING_DIR`。

关键代码（``scripts/clean_workspace.sh:L296-L319``）：

.. code-block:: bash

     for path in build/*; do
       [[ -e "$path" || -L "$path" ]] || continue
       base="$(basename "$path")"
       build_entry_is_preserved "$base" && continue
       if [[ -d "$path" ]] && legacy_run_dir_should_archive "$base"; then
         candidates+=("$path")
       elif [[ -f "$path" && "$base" == *.log ]]; then
         candidates+=("$path")
       fi
     done

     if [[ "${#candidates[@]}" -eq 0 ]]; then
       say "  no legacy runs or loose logs found"
       return
     fi

     for path in "${candidates[@]}"; do
       if [[ -d "$path" ]]; then
         archive_dir "$path" "$BUILD_ARCHIVE_BACKING_DIR"

逐段解释：

* 第 L296-L304 行：遍历 `build/*`，跳过不存在路径和保留名单；目录候选必须命中
  `legacy_run_dir_should_archive()`，普通文件候选必须是 `.log`。
* 第 L307-L310 行：没有候选时打印状态并返回。
* 第 L312-L315 行：目录候选调用 `archive_dir()`。

接口关系：

* 被调用：`archive_legacy_runs()` 内部。
* 调用：`basename`、`build_entry_is_preserved()`、`legacy_run_dir_should_archive()`、
  `say()`、`archive_dir()`。
* 共享状态：读取 `BUILD_ARCHIVE_BACKING_DIR`。

关键代码（``scripts/clean_workspace.sh:L315-L319``）：

.. code-block:: bash

       else
         archive_file "$path" "$BUILD_ARCHIVE_BACKING_DIR"
       fi
     done
   }

逐段解释：

* 第 L315-L317 行：非目录候选被视为 loose log，调用 `archive_file()`。
* 第 L318-L319 行：结束候选循环和 `archive_legacy_runs()`。

接口关系：

* 被调用：`archive_legacy_runs()` 内部候选处理分支。
* 调用：`archive_file()`。
* 共享状态：读取 `BUILD_ARCHIVE_BACKING_DIR`。

§4.9 历史文档归档和主执行序列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

关键代码（``scripts/clean_workspace.sh:L321-L337``）：

.. code-block:: bash

   archive_historical_docs() {
     if [[ "$LCK_ONLY" == "1" ]]; then
       say "=== 6. 历史诊断/快照文件归档：lck-only 跳过 ==="
       return
     fi
     say "=== 6. 历史诊断/快照文件归档 ==="
     local round0=".scratch/round0-archive"
     move_file_to_dir DEEPSEEK_RC4_PROMPTS.md "$round0"
     move_file_to_dir eh2-uvm-implementation-plan.md "$round0"
     move_file_to_dir PHASE1_PLAN.md "$round0"
     move_file_to_dir fsm_uncovered_states.md docs/fsm_diagnostics
   }

   report_sizes() {
     say "=== Clean complete ==="
     du -sh build/ syn/ 2>/dev/null || true
   }

逐段解释：

* 第 L322-L325 行：`LCK_ONLY=1` 时跳过历史文档移动。
* 第 L327-L331 行：三个根目录 markdown 文件移动到 `.scratch/round0-archive`，
  `fsm_uncovered_states.md` 移动到 `docs/fsm_diagnostics`。
* 第 L334-L337 行：清理结束后运行 `du -sh build/ syn/`；stderr 被丢弃，
  `|| true` 使缺失目录不会让脚本失败。

接口关系：

* 被调用：脚本末尾主执行序列。
* 调用：`say()`、`move_file_to_dir()`、`du`。
* 共享状态：读取 `LCK_ONLY`。

关键代码（``scripts/clean_workspace.sh:L339-L345``）：

.. code-block:: bash

   clean_root_locks
   clean_syn_residuals
   clean_build_loose
   archive_signoffs
   archive_legacy_runs
   archive_historical_docs
   report_sizes

逐段解释：

* 第 L339-L341 行：先处理删除类动作：根目录锁、`syn/` 残留、`build/` 散落文件。
* 第 L342-L344 行：再处理移动类动作：sign-off 目录、历史 run、历史诊断文档。
* 第 L345 行：最后报告 `build/` 和 `syn/` 大小。

接口关系：

* 被调用：脚本加载完成后立即执行。
* 调用：本脚本内定义的 7 个阶段函数。
* 共享状态：所有阶段共享参数解析阶段写入的模式变量。

§5 RC 自检脚本
--------------------------------------------------------------------------------

`rc4_self_check.sh` 和 `rc5_self_check.sh` 是 release candidate 状态检查脚本。
它们读取既有源码、构建产物和报告文件，输出 PASS/WARN/FAIL 或 INFO 文本。

§5.1 ``rc4_self_check.sh`` — RC4 检查项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：检查 RVFI wrapper 连线、testbench 实例化、LEC 报告状态、formal build 中的
伪 PASS 文件、`sby_shim.py` 是否存在、IFV 是否在 `PATH` 中，以及 coverage 和
compliance 报告是否存在。

关键代码（``scripts/rc4_self_check.sh:L1-L16``）：

.. code-block:: bash

   #!/bin/bash
   set -e
   echo "=== RC4 Self-Check ==="
   echo "Date: $(date)"
   echo

   PROJ_ROOT="/home/host/eh2-veri"

   # 1. RVFI wrapper must have real assign statements (≥ 16)
   N_ASSIGN=$(grep -c "^\s*assign\s\+trace_\|^\s*assign\s\+wb_seq\|^\s*assign\s\+lsu_bus_" $PROJ_ROOT/rtl/eh2_veer_wrapper_rvfi.sv 2>/dev/null || echo 0)
   if [ "$N_ASSIGN" -ge 16 ]; then
       echo "PASS: RVFI wrapper assign count = $N_ASSIGN (≥ 16)"
   else
       echo "FAIL: RVFI wrapper assign count = $N_ASSIGN (< 16)"
       exit 1
   fi

逐段解释：

* 第 L1-L5 行：脚本使用 Bash 和 `set -e`，先打印标题和当前日期。
* 第 L7 行：`PROJ_ROOT` 固定为 `/home/host/eh2-veri`。
* 第 L10 行：用 `grep -c` 统计 RVFI wrapper 中以 `assign trace_`、`assign wb_seq`
  或 `assign lsu_bus_` 开头的赋值行，grep 失败时输出 0。
* 第 L11-L16 行：赋值行数大于等于 16 时 PASS，否则 FAIL 并 `exit 1`。

接口关系：

* 被调用：用户执行 `bash scripts/rc4_self_check.sh`。
* 调用：`date`、`grep`、`echo`。
* 共享状态：读取 `rtl/eh2_veer_wrapper_rvfi.sv`。

关键代码（``scripts/rc4_self_check.sh:L18-L37``）：

.. code-block:: bash

   # 2. RVFI wrapper must be instantiated in tb_top
   if grep -rn "eh2_veer_wrapper_rvfi" $PROJ_ROOT/dv/uvm/core_eh2/tb/ 2>/dev/null | grep -q "u_"; then
       echo "PASS: RVFI wrapper instantiated in tb_top"
   else
       echo "FAIL: RVFI wrapper not instantiated in tb_top"
       exit 1
   fi

   # 3. Formality LEC status check
   if [ -f "$PROJ_ROOT/syn/build/lec_rc4_report.txt" ]; then
       if grep -q "Verification PASSED" $PROJ_ROOT/syn/build/lec_rc4_report.txt 2>/dev/null; then
           echo "PASS: Formality LEC Verification PASSED"
       elif grep -q "Verification FAILED" $PROJ_ROOT/syn/build/lec_rc4_report.txt 2>/dev/null; then
           echo "WARN: Formality LEC Verification FAILED (see lec_rc4_report.txt)"
       else
           echo "WARN: Formality LEC report exists but status unclear"
       fi
   else
       echo "WARN: Formality LEC report not yet generated (tool still running or needs re-run)"
   fi

逐段解释：

* 第 L19-L24 行：在 UVM `tb/` 目录递归查找 `eh2_veer_wrapper_rvfi`，再要求结果中
  包含 `u_`；未命中时 FAIL 并退出。
* 第 L27-L28 行：只有 `syn/build/lec_rc4_report.txt` 存在时才检查 LEC 状态文本。
* 第 L29-L34 行：报告中包含 `Verification PASSED` 输出 PASS；包含
  `Verification FAILED` 输出 WARN；两者都没有则输出状态不明确的 WARN。
* 第 L35-L37 行：LEC 报告不存在时输出 WARN，不退出。

接口关系：

* 被调用：RC4 主流程。
* 调用：`grep`、`echo`。
* 共享状态：读取 `dv/uvm/core_eh2/tb/` 和 `syn/build/lec_rc4_report.txt`。

关键代码（``scripts/rc4_self_check.sh:L39-L61``）：

.. code-block:: bash

   # 4. No 5-byte PASS fake files in formal/build
   N_FAKE=$(find $PROJ_ROOT/dv/formal/build -size 5c -name "PASS" 2>/dev/null | wc -l)
   if [ "$N_FAKE" -eq 0 ]; then
       echo "PASS: No 5-byte fake PASS files"
   else
       echo "FAIL: $N_FAKE fake PASS files still present"
       exit 1
   fi

   # 5. sby_shim.py must be removed
   if [ -f "$PROJ_ROOT/dv/formal/scripts/sby_shim.py" ]; then
       echo "FAIL: sby_shim.py still present (cargo-cult shim)"
       exit 1
   else
       echo "PASS: sby_shim.py removed"
   fi

   # 6. Formal tools: IFV must be available
   if which ifv > /dev/null 2>&1; then
       echo "PASS: IFV found at $(which ifv)"
   else
       echo "WARN: IFV not found in PATH (check /home/cadence/INCISIVE152/tools/bin/ifv)"
   fi

逐段解释：

* 第 L40-L46 行：在 `dv/formal/build` 下查找大小为 5 字节且名为 `PASS` 的文件；
  数量非 0 时 FAIL 并退出。
* 第 L49-L54 行：`dv/formal/scripts/sby_shim.py` 存在时 FAIL 并退出，不存在时 PASS。
* 第 L57-L61 行：用 `which ifv` 检查 IFV 是否在 `PATH` 中。缺失时只输出 WARN。

接口关系：

* 被调用：RC4 主流程。
* 调用：`find`、`wc`、`which`、`echo`。
* 共享状态：读取 `dv/formal/build`、`dv/formal/scripts` 和 `PATH`。

关键代码（``scripts/rc4_self_check.sh:L63-L88``）：

.. code-block:: bash

   # 7. Formal build must have real reports (>1KB, not 5 bytes)
   N_REAL_REPORTS=$(find $PROJ_ROOT/dv/formal/build -size +1k \( -name "*.log" -o -name "*.rpt" -o -name "*.txt" \) 2>/dev/null | wc -l)
   if [ "$N_REAL_REPORTS" -ge 1 ]; then
       echo "PASS: $N_REAL_REPORTS real formal report(s) found (>1KB)"
   else
       echo "WARN: No real formal reports found (>1KB). IFV compilation may need fixing."
   fi

   # 8. Coverage check (if available)
   if [ -f "$PROJ_ROOT/build/cov_fulltext/dashboard.txt" ]; then
       LINE_COV=$(grep -E "^\s*LINE" $PROJ_ROOT/build/cov_fulltext/dashboard.txt 2>/dev/null | awk '{print $2}' | head -1)
       echo "INFO: Current line coverage = $LINE_COV (gate is 60%)"
   else
       echo "INFO: Coverage dashboard not found (P0-D regression not yet run)"
   fi

逐段解释：

* 第 L64-L69 行：查找大于 1 KB 的 `.log`、`.rpt`、`.txt` formal 报告；数量大于等于
  1 时 PASS，否则 WARN。
* 第 L72-L77 行：coverage dashboard 存在时提取 `LINE` 行第 2 列并输出，缺失时
  输出 INFO。
* 第 L80-L84 行：检查 compliance 的 `report.json` 是否存在，只输出 INFO，不解析
  PASS 计数。
* 第 L86-L88 行：打印结束标题和固定 summary 文本。

接口关系：

* 被调用：RC4 主流程末段。
* 调用：`find`、`wc`、`grep`、`awk`、`head`、`echo`。
* 共享状态：读取 `dv/formal/build`、`build/cov_fulltext/dashboard.txt`、
  `dv/uvm/riscv_compliance/work/report.json`。

§5.2 ``rc5_self_check.sh`` — RC5 检查项
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：读取 IFV proven 数量，检查 formal 假 PASS、`sby_shim.py`、ADR 编号重复和
sign-off gate 阈值文本，并打印仍需额外工具运行时间的项目。

关键代码（``scripts/rc5_self_check.sh:L1-L16``）：

.. code-block:: bash

   #!/bin/bash
   set -e
   ROOT=/home/host/eh2-veri
   echo "=== RC5 自检 ==="

   # P0-1 LEC PASSED
   # (Pending — waiting for Formality run)
   echo "P0-1: LEC — PENDING (diagnosis in progress)"

   # P0-2 IFV proven ≥ 20
   PROVEN=$(grep -E "Pass\s+:" $ROOT/dv/formal/build/ifv_prove_rc5c.log | head -1 | grep -oE "[0-9]+")
   if [ "${PROVEN:-0}" -ge 20 ]; then
     echo "P0-2: IFV PASS — $PROVEN assertions proven"
   else
     echo "FAIL P0-2: IFV proven $PROVEN < 20"
   fi

逐段解释：

* 第 L1-L4 行：脚本使用 Bash、`set -e`，根目录固定为 `/home/host/eh2-veri`。
* 第 L6-L8 行：P0-1 LEC 不读取文件，直接输出 pending 文本。
* 第 L10-L11 行：从 `dv/formal/build/ifv_prove_rc5c.log` 中匹配 `Pass\s+:`，
  取第一行，再提取数字。
* 第 L12-L16 行：`PROVEN` 大于等于 20 时输出 PASS，否则输出 FAIL 文本。该分支
  没有 `exit 1`。

接口关系：

* 被调用：用户执行 `bash scripts/rc5_self_check.sh`。
* 调用：`grep`、`head`、`echo`。
* 共享状态：读取 `dv/formal/build/ifv_prove_rc5c.log`。

关键代码（``scripts/rc5_self_check.sh:L18-L32``）：

.. code-block:: bash

   # P0-3 Coverage line ≥ 60
   # (Pending — full regression not yet run)
   echo "P0-3: Coverage — NOT YET RUN (requires full regression ~250 sims)"

   # P0-4 Compliance ≥ 50 PASS
   # (Pending — signature_mismatch not yet debugged)
   echo "P0-4: Compliance — NOT YET RUN (signature_mismatch bug pending)"

   # 反伪造 1: 5 字节 PASS 必须为空
   N=$(find $ROOT/dv/formal/build -size 5c -name "PASS" 2>/dev/null | wc -l)
   if [ "$N" -eq 0 ]; then
     echo "Anti-fake 1: No 5-byte PASS files ✓"
   else
     echo "FAIL: $N fake PASS files found"
   fi

逐段解释：

* 第 L18-L24 行：P0-3 coverage 和 P0-4 compliance 都只输出固定 NOT YET RUN 文本。
* 第 L27 行：反伪造检查 1 与 RC4 类似，查找 5 字节 `PASS` 文件。
* 第 L28-L32 行：数量为 0 输出通过文本；否则输出 FAIL 文本。该分支没有 `exit 1`。

接口关系：

* 被调用：RC5 主流程。
* 调用：`find`、`wc`、`echo`。
* 共享状态：读取 `dv/formal/build`。

关键代码（``scripts/rc5_self_check.sh:L34-L54``）：

.. code-block:: bash

   # 反伪造 2: sby_shim.py 不存在
   if [ ! -f $ROOT/dv/formal/scripts/sby_shim.py ]; then
     echo "Anti-fake 2: sby_shim.py absent ✓"
   else
     echo "FAIL: sby_shim.py still exists"
   fi

   # 反伪造 3: ADR 编号无重复
   DUP=$(ls $ROOT/docs/adr/ 2>/dev/null | grep -E "^[0-9]{4}" | sed 's/-.*//' | sort | uniq -d | wc -l)
   if [ "$DUP" -eq 0 ]; then
     echo "Anti-fake 3: No duplicate ADR numbers ✓"
   else
     echo "FAIL: $DUP duplicate ADR numbers"
   fi

   # 反伪造 4: signoff-gates.md 阈值未被改
   if grep -q "line ≥ 60%" $ROOT/docs/signoff-gates.md 2>/dev/null; then

逐段解释：

* 第 L35-L39 行：`sby_shim.py` 不存在时通过，存在时输出 FAIL。
* 第 L42 行：列出 `docs/adr/` 下以 4 位数字开头的文件，截取编号、排序、查重，
  再统计重复编号数量。
* 第 L43-L47 行：重复数量为 0 输出通过，否则输出 FAIL。
* 第 L50 行：检查 `docs/signoff-gates.md` 是否包含字面文本 `line ≥ 60%`。

接口关系：

* 被调用：RC5 主流程。
* 调用：`ls`、`grep`、`sed`、`sort`、`uniq`、`wc`、`echo`。
* 共享状态：读取 `dv/formal/scripts/sby_shim.py`、`docs/adr/`、
  `docs/signoff-gates.md`。

关键代码（``scripts/rc5_self_check.sh:L50-L58``）：

.. code-block:: bash

   if grep -q "line ≥ 60%" $ROOT/docs/signoff-gates.md 2>/dev/null; then
     echo "Anti-fake 4: signoff gates unmodified ✓"
   else
     echo "FAIL: signoff threshold may be tampered"
   fi

   echo ""
   echo "=== RC5 自检完成 (部分) ==="
   echo "Note: P0-1/P0-3/P0-4 需要额外工具运行时间"

逐段解释：

* 第 L50-L54 行：sign-off gate 阈值文本存在时输出通过，否则输出 FAIL。
* 第 L56-L58 行：打印空行、结束标题和说明，说明 P0-1、P0-3、P0-4 需要额外工具
  运行时间。

接口关系：

* 被调用：RC5 主流程末段。
* 调用：`grep`、`echo`。
* 共享状态：读取 `docs/signoff-gates.md`。

§6 UVM 输出后处理辅助脚本
--------------------------------------------------------------------------------

这两个脚本位于 `dv/uvm/core_eh2/scripts/`，它们不启动仿真，只遍历输出目录并生成
便于阅读的派生文件。

§6.1 ``objdump.sh`` — 为 test object 生成反汇编
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在指定输出树中查找 `test.o`，用 `RISCV_TOOLCHAIN` 下的
`riscv32-unknown-elf-objdump` 生成同目录 `test.dump`。

关键代码（``dv/uvm/core_eh2/scripts/objdump.sh:L1-L16``）：

.. code-block:: bash

   #!/usr/bin/env bash
   # Generate objdump disassembly for all test ELF files found in the output tree.
   # Usage: ./scripts/objdump.sh [search_root]
   #   search_root defaults to ./out/run

   _SEARCH_ROOT="${1:-./out/run}"
   _GET_OBJS=$(find "$_SEARCH_ROOT" -type f -iregex '.*test\.o')

   if [[ -z "${RISCV_TOOLCHAIN}" ]]; then
      echo "Please define RISCV_TOOLCHAIN to have access to objdump."
      exit 1
   fi

   for obj in $_GET_OBJS; do
       "$RISCV_TOOLCHAIN"/bin/riscv32-unknown-elf-objdump -d "$obj" > "$(dirname "$obj")"/test.dump
   done

逐段解释：

* 第 L1-L4 行：注释说明用途和可选参数；默认 search root 是 `./out/run`。
* 第 L6-L7 行：`_SEARCH_ROOT` 取第一个参数或默认值；`find` 查找路径中匹配
  `.*test\.o` 的普通文件。
* 第 L9-L12 行：`RISCV_TOOLCHAIN` 为空时打印错误并退出。
* 第 L14-L16 行：逐个 object 调用
  `$RISCV_TOOLCHAIN/bin/riscv32-unknown-elf-objdump -d`，输出到 object 同目录的
  `test.dump`。

接口关系：

* 被调用：用户或回归后处理步骤执行该脚本。
* 调用：`find`、`echo`、`dirname`、`riscv32-unknown-elf-objdump`。
* 共享状态：读取 `RISCV_TOOLCHAIN` 和输出树；写 `test.dump`。

§6.2 ``prettify.sh`` — 格式化 trace log
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：在指定目录树中查找 `trace_core*.log`，用 `column` 按 tab 分隔重新排版为
同目录 `trace_pretty.log`。

关键代码（``dv/uvm/core_eh2/scripts/prettify.sh:L1-L11``）：

.. code-block:: bash

   #!/usr/bin/env bash
   # Format trace_core*.log files into aligned columns for readability.
   # Usage: ./scripts/prettify.sh [search_root]
   #   search_root defaults to current directory

   _SEARCH_ROOT="${1:-.}"
   _GET_TRACES=$(find "$_SEARCH_ROOT" -type f -iregex '.*trace_core.*\.log')

   for trace in $_GET_TRACES; do
       column -t -s $'\t' -o ' ' -R 1,2,3,4,5 "$trace" > "$(dirname "$trace")"/trace_pretty.log
   done

逐段解释：

* 第 L1-L4 行：注释说明用途和可选参数；默认 search root 是当前目录。
* 第 L6-L7 行：`find` 查找匹配 `.*trace_core.*\.log` 的普通文件。
* 第 L9-L11 行：对每个 trace 文件执行 `column -t`，输入分隔符是 tab，输出分隔符
  是单个空格，并对第 1 到第 5 列使用 `-R` 右对齐；结果写到同目录
  `trace_pretty.log`。

接口关系：

* 被调用：用户或回归后处理步骤执行该脚本。
* 调用：`find`、`column`、`dirname`。
* 共享状态：读取 trace log，写 `trace_pretty.log`。

§7 参考资料
--------------------------------------------------------------------------------

关联章节：

* :doc:`makefiles` — 顶层 `Makefile` 和 staged wrapper 的入口关系。
* :doc:`core_eh2_scripts` — `dv/uvm/core_eh2/scripts/` 下 Python 与 report helper。
* :doc:`../06_flows/scripts_reference` — flow 视角的脚本入口和 CLI 参数索引。

源文件绝对路径：

* `/home/host/eh2-veri/env.sh`
* `/home/host/eh2-veri/docs/build_manual_pdf.sh`
* `/home/host/eh2-veri/scripts/clean_workspace.sh`
* `/home/host/eh2-veri/scripts/rc4_self_check.sh`
* `/home/host/eh2-veri/scripts/rc5_self_check.sh`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/objdump.sh`
* `/home/host/eh2-veri/dv/uvm/core_eh2/scripts/prettify.sh`

关联 ADR：

* 本章不引用 ADR。上述脚本源码未直接声明 ADR 编号；`rc5_self_check.sh` 只检查
  `docs/adr/` 文件名编号是否重复。

§9  动手练习
------------------------

下面练习优先使用只读审计命令；需要商业 EDA license 的仿真、综合或形式化命令，请在对应工具环境就绪后再运行。

**入门题**：从脚本、Makefile 或配置文件中找到本页讲到的真实入口。

.. code-block:: bash

   rg -n "def main|argparse|subprocess|class |target:" dv/uvm/core_eh2/scripts scripts Makefile | head -80
   rg -n "cover.cfg|cov_full_nc.ccf|rtl_simulation.yaml|eh2_configs.yaml" docs/sphinx_cn/source/appendix_e_config docs/sphinx_cn/source/appendix_f_scripts

**进阶题**：检查工具职责是否按 VCS/NC/Formal/Syn/Lint 分开，而不是混成一个流程。

.. code-block:: bash

   rg -n "urg|imc|vcs|irun|xrun|dc_shell|fm_shell|verilator|verible" docs/sphinx_cn/source/appendix_c_tools docs/sphinx_cn/source/appendix_f_scripts | head -100

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲解的工具或脚本入口在哪个真实路径下，命令行参数是什么？
2. 该工具读取哪些配置文件，写出哪些日志、报告或数据库？
3. VCS、NC、URG、IMC、DC、Formality、IFV 或 lint 工具的职责是否没有混写？
4. 失败时应先看工具原生日志、wrapper 脚本返回码还是 sign-off 汇总？
5. 本页引用的代码片段是否足以让读者定位到具体函数、target 或配置行？
