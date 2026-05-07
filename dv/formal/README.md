# Formal Verification 骨架

> **状态：** 骨架已就位，SVA 属性内容待人工填充。

本目录是 EH2 验证平台的 formal verification 基础设施骨架，用于承载
Symbiyosys (开源) 和 JasperGold (商业) 两条 formal 验证流程。

## 目录结构

```
dv/formal/
├── README.md                       # 本文件
├── Makefile                        # formal 构建入口
├── properties/
│   └── eh2_pmp_assert.sv           # MPU/PMP 占位 SVA（含 TODO）
└── scripts/
    └── sby_pmp.sby                  # Symbiyosys 配置文件
```

## TODO 清单

以下工作需要由**验证工程师**后续完成：

- [ ] 在 `properties/eh2_pmp_assert.sv` 中填写真正的 SVA 属性
- [ ] 补充更多 property 文件（中断、CSR、流水线等）
- [ ] 根据实际 RTL 信号路径调整 bind 语句
- [ ] 添加 cover property 以确认可达性
- [ ] 完善 `scripts/sby_pmp.sby` 中的引擎参数调优
- [ ] 接入 CI（可选，当 SVA 稳定后）

## 使用方式

### Symbiyosys（开源流程）

```bash
# 在项目根目录执行
make formal

# 清理产物
make formal_clean
```

前置条件：

- [Symbiyosys](https://symbiyosys.readthedocs.io/) (`sby` 命令)
- [Yosys](https://yosyshq.net/yosys/)（综合前端）
- SMT solver（如 Z3、Boolector）

### JasperGold（商业流程）

```tcl
# 在 JasperGold 中加载 property
clear -all
analyze -sv -f ../../dv/uvm/core_eh2/eh2_rtl.f
analyze -sv dv/formal/properties/eh2_pmp_assert.sv
elaborate -top eh2_lsu_addrcheck

# 设定 clock 和 reset
clock clk
reset rst_l -low

# 运行证明
prove -all
```

> **注意：** JasperGold 的 TCL 脚本尚未模板化，上述为参考流程，需根据实际
> 许可证和项目配置调整。

## 与 sign-off 的关系

当前 formal 骨架**未接入** sign-off gate（`make signoff`），不会影响现有
回归测试流程。待 SVA 属性稳定并通过评审后，再由团队决定是否纳入 sign-off。

## 负责人

| 事项 | 负责人 |
|------|--------|
| 骨架搭建 | Agent (issue #42) |
| SVA 属性编写 | 验证工程师（待分配） |
| JasperGold 集成 | 验证工程师（待分配） |
| CI 接入 | DevOps（待分配） |
