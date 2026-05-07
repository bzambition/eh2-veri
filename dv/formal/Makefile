# dv/formal/Makefile — Formal verification (Symbiyosys flow)
#
# Targets:
#   formal       - 运行 Symbiyosys formal 验证
#   formal_clean - 清理 formal 产物

SHELL := /bin/bash

# Symbiyosys 配置文件目录
SBY_DIR   := scripts
SBY_FILES := $(wildcard $(SBY_DIR)/*.sby)

# 产物目录（Symbiyosys 默认在 .sby 同级生成）
SBY_WORKDIRS := $(patsubst $(SBY_DIR)/%.sby,%,$(SBY_FILES))

.PHONY: formal formal_clean _check_sby

# -------------------------------------------------------------------
# 前置检查：Symbiyosys 是否可用
# -------------------------------------------------------------------
_check_sby:
	@command -v sby >/dev/null 2>&1 || { \
	  echo ""; \
	  echo "========================================================"; \
	  echo "  错误：未找到 Symbiyosys (sby)"; \
	  echo ""; \
	  echo "  请先安装 Symbiyosys："; \
	  echo "    https://symbiyosys.readthedocs.io/en/latest/install.html"; \
	  echo ""; \
	  echo "  或通过 OSS CAD Suite 一键安装："; \
	  echo "    https://github.com/YosysHQ/oss-cad-suite-build"; \
	  echo "========================================================"; \
	  echo ""; \
	  exit 1; \
	}

# -------------------------------------------------------------------
# 运行所有 .sby 配置
# -------------------------------------------------------------------
formal: _check_sby
	@echo "=== Formal verification (Symbiyosys) ==="
	@for f in $(SBY_FILES); do \
	  echo "--- Running: $$f ---"; \
	  sby -f $$f || exit 1; \
	done
	@echo "=== Formal verification complete ==="

# -------------------------------------------------------------------
# 清理
# -------------------------------------------------------------------
formal_clean:
	@echo "=== Cleaning formal artifacts ==="
	@for d in $(SBY_WORKDIRS); do \
	  rm -rf $$d; \
	done
	@echo "=== Clean complete ==="
