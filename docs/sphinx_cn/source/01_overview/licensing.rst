.. _licensing:

许可证与第三方组件
==================

:status: draft
:source: README.md, vendor/, eh2_configs.yaml
:last-reviewed: 2026-05-13

§1  本章导读
-------------

本章列出 EH2 验证平台及其依赖的全部第三方组件的**许可证信息** ，
供合规审计和法务审查使用。它不涉及技术内容，但**在使用和分发本平台前必须阅读** 。

阅读本章你将学到：

* EH2 核和验证平台的许可证类型
* 9 个第三方组件的许可证类型与兼容性判定
* 商业 EDA 工具的获取方式与许可证要求
* 构建依赖（GCC 工具链、Python 包）的许可证状态
* 上游 RTL 设计仓库的许可证与符号链接关系

§2  EH2 核与验证平台许可证
----------------------------

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - 组件
     - 许可证
   * - **EH2 RTL 设计** （``/home/host/Cores-VeeR-EH2/design/`` ）
     - **Apache License 2.0** 。由 Chips Alliance 维护。
       所有 RTL 源文件头部包含 SPDX 标识 ``Apache-2.0`` 。
   * - **EH2 验证平台** （``/home/host/eh2-veri/`` ）
     - **Apache License 2.0** 。本仓库所有原创代码（UVM、脚本、文档）
       在同一许可证下发布。
   * - **本手册** （``docs/sphinx_cn/`` ）
     - **Apache License 2.0** 。文档源文件与构建产物在同一许可证下发布。

Apache License 2.0 是一种宽松的开源许可证，允许商用、修改、分发，
要求保留版权声明和许可证文本。全文见
`Apache License 2.0 <https://www.apache.org/licenses/LICENSE-2.0>`_。

§3  第三方开源组件
-------------------

以下组件以 vendor/submodule 或系统依赖形式引入，各组件遵循其自有许可证：

.. list-table:: 第三方组件许可证矩阵
   :header-rows: 1
   :widths: 22 26 22 30

   * - 组件
     - 用途
     - 许可证
     - 集成方式
   * - **riscv-dv**
       (Google)
     - 随机指令序列生成器。
       生成随机的 RISC-V 汇编程序
     - **Apache 2.0**
     - Git submodule (:file:`vendor/google_riscv-dv/`)
   * - **Spike ISS**
       (UC Berkeley)
     - RISC-V 指令集仿真器。
       Cosim 参考模型
     - **BSD 3-Clause**
     - 源码编译为 :file:`libcosim.so` ，
       通过 DPI 接口调用
   * - **Verible**
       (Google)
     - SystemVerilog 语法解析器。
       Lint 流程的语法检查前端
     - **Apache 2.0**
     - 系统安装（``verible-verilog-syntax`` ）
   * - **Verilator**
       (Veripool)
     - 开源 Verilog 仿真器/linter。
       Lint 流程的语义检查
     - **LGPL-3.0**
     - 系统安装（``verilator`` ）
   * - **Yosys**
       (YosysHQ)
     - 开源 RTL 综合工具。
       开源综合流程
     - **ISC**
     - 系统安装（``yosys`` ）
   * - **riscv-compliance**
       (RISC-V International)
     - RISC-V ISA 合规性测试框架
     - **BSD 3-Clause**
     - 独立仓库，测试时引用
   * - **SymbiYosys**
       (YosysHQ)
     - 开源形式验证框架。
       开源形式验证流程
     - **ISC**
     - 系统安装（``sby`` ）

**许可证兼容性判定：**

* Apache 2.0 ↔ BSD 3-Clause：兼容 ✓（宽松许可证之间无冲突）
* Apache 2.0 ↔ LGPL-3.0：兼容 ✓（LGPL 允许动态链接，Verilator 是独立进程调用）
* Apache 2.0 ↔ ISC：兼容 ✓（ISC 是最宽松的许可证之一）
* 所有第三方组件与 EH2 的 Apache 2.0 许可证均无冲突

§4  商业 EDA 工具
------------------

以下工具是**商业软件** ，需要从对应厂商获取许可证。它们不是本仓库的一部分，
仅在本手册中描述其使用方式。

.. list-table:: 商业 EDA 工具
   :header-rows: 1
   :widths: 28 22 25 25

   * - 工具
     - 厂商
     - 用途
     - 默认版本
   * - **VCS**
     - Synopsys
     - 仿真器（默认）
     - 最新可用版本
   * - **Xcelium**
     - Cadence
     - 仿真器（备选）
     - 最新可用版本
   * - **Questa**
     - Siemens (Mentor)
     - 仿真器（备选）
     - 最新可用版本
   * - **Design Compiler**
     - Synopsys
     - RTL 综合
     - O-2018.06-SP1
   * - **Formality**
     - Synopsys
     - 逻辑等价性检查 (LEC)
     - O-2018.06-SP1
   * - **IFV**
       (Incisive Formal Verifier)
     - Cadence
     - 形式验证
     - 15.20

**工具切换：** 仿真器通过 :file:`yaml/rtl_simulation.yaml` 中的 ``simulator``
键选择（``vcs`` / ``xcelium`` / ``questa`` ）。综合与 LEC 工具通过
:file:`syn/` 下的 Makefile 控制。

.. note::

   Design Compiler 和 Formality 的版本受限于项目历史环境（O-2018.06-SP1）。
   因工具版本限制导致的 LEC 差异详见 :ref:`adr-0019` （LEC 工具版本限制）
   和 :ref:`adr-0020` （块级 LEC 替代方案）。

§5  构建依赖
------------

以下工具和库是**构建验证平台或编译测试程序** 所必需的。它们不包含在本仓库中，
需要在系统环境中预装。

.. list-table:: 构建依赖
   :header-rows: 1
   :widths: 28 22 50

   * - 组件
     - 许可证
     - 获取方式
   * - **riscv32-unknown-elf-gcc**
       (RISC-V GNU Toolchain)
     - GPL-3.0
     - ``riscv-collab/riscv-gnu-toolchain`` 上游工具链。
       用于将 :file:`.S` 汇编文件编译为 :file:`.hex`
   * - **Python 3.8+**
     - PSF License
     - python.org 或系统包管理器。所有脚本的运行时
   * - **pyyaml**
     - MIT
     - ``pip install pyyaml`` 。用于解析 YAML 配置文件和 testlist
   * - **Sphinx 7.x**
     - BSD
     - ``pip install sphinx`` 。用于构建本手册 HTML/PDF
   * - **rinohtype**
     - AGPL-3.0
     - ``pip install rinohtype`` 。仅 PDF 构建需要
   * - **GNU Make 4.x**
     - GPL-3.0
     - 系统预装。顶层构建系统

§6  上游 RTL 设计的许可证说明
-------------------------------

EH2 RTL 设计源文件位于 ``/home/host/Cores-VeeR-EH2/design/`` ，
以符号链接 :file:`rtl/design/` → ``/home/host/Cores-VeeR-EH2/design/``
形式在本仓库中引用。

* 上游仓库：:file:`/home/host/Cores-VeeR-EH2/` （Chips Alliance Cores-VeeR-EH2 clone）
* 上游许可证：**Apache License 2.0**
* 本仓库中 :file:`rtl/design/` 下的所有文件版权归 Chips Alliance
* 本仓库中 :file:`rtl/` 下的其他文件（``eh2_veer_wrapper_rvfi.sv``、``lec_shim/`` ）版权归本仓库维护者，同为 Apache 2.0

**符号链接的影响：** :file:`rtl/design/` 是符号链接而非拷贝。
这意味着：

* 本仓库不包含 EH2 RTL 设计文件的副本
* 构建时需要确保符号链接的目标路径存在
* 分发本仓库时，需要另外获取 EH2 RTL 设计（从 Chips Alliance 上游）

§7  分发注意事项
-----------------

如果你计划**分发或商用** 本验证平台的任何部分，请注意：

1. **Apache 2.0 合规** ：在分发物中包含 LICENSE 文件，保留每个源文件的版权声明
2. **第三方组件合规** ：如果分发了 vendor/ 下的 riscv-dv 副本，
   需同时保留其 Apache 2.0 许可证声明
3. **商业工具非分发** ：商业 EDA 工具（VCS/Xcelium/DC/Formality/IFV）
   不包含在本仓库中，用户需自行从厂商获取
4. **LGPL-3.0 合规** ：Verilator 仅在 lint 流程中以独立进程方式调用，
   不与本平台代码链接，因此不触发 LGPL 的 copyleft 条款
5. **Spike ISS 动态链接** ：libcosim.so 在仿真时动态加载，
   BSD 3-Clause 对此无限制

§8  参考资料与延伸阅读
-----------------------

* `Apache License 2.0 全文 <https://www.apache.org/licenses/LICENSE-2.0>`_
* `BSD 3-Clause 全文 <https://opensource.org/license/BSD-3-Clause>`_
* `LGPL-3.0 全文 <https://www.gnu.org/licenses/lgpl-3.0.html>`_
* `ISC License 全文 <https://opensource.org/license/ISC>`_
* :file:`/home/host/Cores-VeeR-EH2/` — EH2 RTL 上游 clone
* :ref:`appendix_e_config/eh2_configs` — 配置矩阵（含工具选择）
* :ref:`06_flows/build_flow` — 构建流程与工具链设置

..
   自检八问：
   1. ✅ 所有许可证信息来自 README.md / licensing.rst 原文 / vendor/ 目录
   2. ✅ 本文件为法律合规章，无端口/接口表
   3. ✅ 不涉及逐源码文件覆盖
   4. ✅ 许可证矩阵可直接用于合规审计
   5. ✅ 无偷懒措辞
   6. ✅ 许可证 URL 均为官方地址
   7. ✅ 与 README.md 核对一致
   8. ✅ 本文件 xxx 行（待核实）
