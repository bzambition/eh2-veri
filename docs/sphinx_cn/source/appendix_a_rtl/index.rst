.. _appendix_a_rtl_index:
.. _appendix_a_rtl/index:

附录 A — RTL 模块字典
=====================

:status: draft
:source: dv/uvm/core_eh2/eh2_rtl.f
:last-reviewed: 2026-05-19

§1  本附录边界
--------------

本附录按 :file:`dv/uvm/core_eh2/eh2_rtl.f` 和
:file:`dv/uvm/core_eh2/eh2_shared.f` 的编译边界组织 RTL 字典。
:file:`rtl/design` 在当前工作树中是符号链接，指向
:file:`/home/host/Cores-VeeR-EH2/design`；本文档引用仍使用仓库内相对路径。

当前 :file:`eh2_rtl.f` 中有 51 个非注释编译条目：

* 1 个 snapshot 参数类型定义：:file:`rtl/snapshots/default/eh2_pdef.vh`。
* 1 个 include/package 文件：:file:`rtl/design/include/eh2_def.sv`。
* 3 个 library-mode 文件：:file:`rtl/design/lib/beh_lib.sv`、
  :file:`rtl/design/lib/eh2_lib.sv`、:file:`rtl/design/lib/mem_lib.sv`。
* 2 个 bus bridge 文件：:file:`rtl/design/lib/ahb_to_axi4.sv` 和
  :file:`rtl/design/lib/axi4_to_ahb.sv`。
* 10 个 IFU 文件、8 个 DEC 文件、4 个 EXU 文件、12 个 LSU 文件。
* 1 个 DBG 文件、3 个 DMI Verilog 文件。
* 5 个 top-level/core integration 文件：DMA、memory wrapper、PIC、core top 和
  wrapper。
* 1 个 RVFI wrapper 文件：:file:`rtl/eh2_veer_wrapper_rvfi.sv`。

:file:`eh2_shared.f` 另列 3 个 shared AXI4 文件：
:file:`shared/rtl/axi4_pkg.sv`、:file:`shared/rtl/axi4_intf.sv` 和
:file:`shared/rtl/axi4_slave_mem.sv`。它们在本附录的
:ref:`appendix_a_rtl/shared_axi4` 中说明，不计入 :file:`eh2_rtl.f` 的 51 个条目。

§2  编译顺序
------------

关键代码（``dv/uvm/core_eh2/eh2_rtl.f:L1-L18``）：

.. code-block:: systemverilog

   // RTL file list for EH2
   // Include path for parameter definitions
   +incdir+rtl/snapshots/default

   // Parameter type definition (must be first - defines eh2_param_t)
   rtl/snapshots/default/eh2_pdef.vh

   // Package definitions (must be compiled before library files)
   rtl/design/include/eh2_def.sv

   // Library files (compiled with -v = library mode, only when needed)
   -v rtl/design/lib/beh_lib.sv
   -v rtl/design/lib/eh2_lib.sv
   -v rtl/design/lib/mem_lib.sv

   // AXI/AHB converters
   rtl/design/lib/ahb_to_axi4.sv
   rtl/design/lib/axi4_to_ahb.sv

逐段解释：

* 第 3 行：filelist 先把 :file:`rtl/snapshots/default` 加入 include path。
* 第 6 行：:file:`eh2_pdef.vh` 必须先出现，因为注释明确说明它定义
  ``eh2_param_t``。
* 第 9 行：:file:`eh2_def.sv` 在 library files 之前编译，提供 package/type
  依赖。
* 第 12~14 行：``beh_lib.sv``、``eh2_lib.sv``、``mem_lib.sv`` 使用 ``-v``，
  表示按 library mode 供后续实例化解析。
* 第 17~18 行：AXI/AHB converter 文件在各功能单元之前进入 filelist。

接口关系：

* 被调用：仿真编译、lint、formal filelist 派生和综合 wrapper 生成都依赖类似顺序。
* 调用：EDA 编译器的 filelist 解析。
* 共享状态：include path、``eh2_param_t``、library module lookup。

§3  RTL 分组图
--------------

::

   eh2_veer_wrapper
      |
      v
   eh2_veer
      |
      +--> IFU  -> alignment, branch predict, ICCM/I$, memory control
      +--> DEC  -> decode, GPR, issue buffer, TLU, CSR, trigger
      +--> EXU  -> ALU, MUL, DIV
      +--> LSU  -> addrcheck, AMO, bus buffer, DCCM, ECC, stbuf
      +--> DBG  -> debug module
      +--> DMI  -> JTAG/DMI bridge
      +--> PIC  -> interrupt controller
      +--> DMA  -> DMA controller
      +--> MEM  -> memory wrapper
      |
      +--> shared AXI4 files from eh2_shared.f

逐段解释：

* :file:`eh2_veer_wrapper.sv` 和 :file:`eh2_veer.sv` 是 core integration 的主要入口，
  对应 :ref:`appendix_a_rtl/wrapper`。
* IFU、DEC、EXU 和 LSU 是 filelist 中最大四组，分别对应 fetch、decode/commit、
  execute 和 load/store。
* DBG、DMI、PIC、DMA、MEM 是独立集成块，分别有对应章节解释源文件端口、状态机和
  wrapper 关系。
* shared AXI4 文件来自 :file:`eh2_shared.f`，不是 EH2 core RTL 源目录的一部分，
  但在 UVM verification platform 中与 DUT/TB 连接有关。

§4  章节目录
------------

.. list-table::
   :header-rows: 1
   :widths: 24 22 54

   * - 章节
     - filelist 条目
     - 范围
   * - :ref:`appendix_a_rtl/wrapper`
     - 2 个 core top + RVFI wrapper
     - :file:`rtl/design/eh2_veer.sv`、:file:`rtl/design/eh2_veer_wrapper.sv`、:file:`rtl/eh2_veer_wrapper_rvfi.sv`
   * - :ref:`appendix_a_rtl/ifu`
     - 10 个
     - :file:`rtl/design/ifu/*.sv`
   * - :ref:`appendix_a_rtl/dec`
     - 8 个
     - :file:`rtl/design/dec/*.sv`
   * - :ref:`appendix_a_rtl/exu`
     - 4 个
     - :file:`rtl/design/exu/*.sv`
   * - :ref:`appendix_a_rtl/lsu`
     - 12 个
     - :file:`rtl/design/lsu/*.sv`
   * - :ref:`appendix_a_rtl/dbg`
     - 1 个
     - :file:`rtl/design/dbg/eh2_dbg.sv`
   * - :ref:`appendix_a_rtl/dmi`
     - 3 个
     - :file:`rtl/design/dmi/*.v`
   * - :ref:`appendix_a_rtl/pic`
     - 1 个
     - :file:`rtl/design/eh2_pic_ctrl.sv`
   * - :ref:`appendix_a_rtl/dma`
     - 1 个
     - :file:`rtl/design/eh2_dma_ctrl.sv`
   * - :ref:`appendix_a_rtl/mem`
     - 1 个
     - :file:`rtl/design/eh2_mem.sv`
   * - :ref:`appendix_a_rtl/lib`
     - 5 个
     - :file:`rtl/design/lib/*.sv`
   * - :ref:`appendix_a_rtl/include`
     - 2 个输入边界
     - :file:`rtl/snapshots/default/eh2_pdef.vh`、:file:`rtl/design/include/eh2_def.sv`
   * - :ref:`appendix_a_rtl/shared_axi4`
     - 3 个 shared 条目
     - :file:`shared/rtl/axi4_pkg.sv`、:file:`shared/rtl/axi4_intf.sv`、:file:`shared/rtl/axi4_slave_mem.sv`

§5  共享 AXI4 filelist
----------------------

关键代码（``dv/uvm/core_eh2/eh2_shared.f:L1-L12``）：

.. code-block:: systemverilog

   // Shared RTL file list for EH2 UVM Verification Platform
   // Contains AXI4 package, interface, and memory model
   // Paths are relative to eh2-veri/ project root

   // AXI4 package
   shared/rtl/axi4_pkg.sv

   // AXI4 interface
   shared/rtl/axi4_intf.sv

   // AXI4 slave memory model
   shared/rtl/axi4_slave_mem.sv

逐段解释：

* 第 1~3 行：该 filelist 是验证平台 shared RTL，不是
  :file:`rtl/design` 下的 EH2 core filelist。
* 第 6 行：:file:`axi4_pkg.sv` 提供 AXI4 package。
* 第 9 行：:file:`axi4_intf.sv` 提供 AXI4 interface。
* 第 12 行：:file:`axi4_slave_mem.sv` 提供 AXI4 slave memory model。

接口关系：

* 被调用：UVM TB 编译 filelist。
* 调用：SystemVerilog package/interface/module 编译。
* 共享状态：AXI4 类型、接口信号和 memory model 行为。

§6  阅读顺序
------------

建议按编译依赖和调试需求选择入口：

* 参数、package、宏问题：先读 :ref:`appendix_a_rtl/include`，再读使用该类型的
  目标模块章节。
* 顶层连接、RVFI、LEC packed-port 相关问题：先读
  :ref:`appendix_a_rtl/wrapper`。
* 取指、branch predictor、ICCM/I$ 问题：读 :ref:`appendix_a_rtl/ifu`。
* CSR、TLU、dual issue、wb、trigger 问题：读 :ref:`appendix_a_rtl/dec`。
* ALU/MUL/DIV 或 branch compare 问题：读 :ref:`appendix_a_rtl/exu`。
* DCCM、load/store、AMO、bus error、store buffer 问题：读
  :ref:`appendix_a_rtl/lsu`。
* debug、DMI、JTAG 问题：分别读 :ref:`appendix_a_rtl/dbg` 和
  :ref:`appendix_a_rtl/dmi`。
* PIC、DMA、memory wrapper 和 shared AXI4 问题：读对应独立章节。

§7  v2-7 覆盖审计
-----------------

v2-7 先做 RTL 附录的覆盖审计，而不是直接重写所有模块页。当前审计结论是：
:file:`/home/host/Cores-VeeR-EH2/design/` 下 46 个 ``.sv`` 文件名均已在
``appendix_a_rtl`` 中出现；每个模块页已经至少包含一个 ``§4`` 源码精读入口和一个
``§8`` 相关小节。这个结论只证明“文件级覆盖已建立”，不代表每个状态机和每条组合
路径都已经讲到足够教学深度。

审计命令如下：

.. code-block:: bash

   find /home/host/Cores-VeeR-EH2/design -name '*.sv' | sort
   python3 - <<'PY'
   from pathlib import Path
   svs = sorted(Path('/home/host/Cores-VeeR-EH2/design').rglob('*.sv'))
   text = '\n'.join(p.read_text(errors='ignore')
                    for p in Path('docs/sphinx_cn/source/appendix_a_rtl').glob('*.rst'))
   missing = [str(p) for p in svs if p.name not in text]
   print('total', len(svs), 'missing', len(missing))
   for item in missing:
       print(item)
   PY

本轮实测输出：

.. code-block:: text

   total 46 missing 0

.. note::

   这里的 46 是当前上游 clone 实际 ``.sv`` 文件数。DMI 目录内的
   ``dmi_wrapper.v``、``dmi_jtag_to_core_sync.v``、``rvjtag_tap.v`` 是 Verilog
   ``.v`` 文件，也已由 :ref:`appendix_a_rtl/dmi` 覆盖，但不计入这个 ``.sv`` 统计。

§8  全局失败模式与排查
----------------------

.. list-table:: RTL 附录阅读时的常见失败模式
   :header-rows: 1
   :widths: 24 32 28 16

   * - 现象
     - 根因
     - 排查命令
     - 修复/阅读入口
   * - Sphinx 中某个 RTL 文件名找不到
     - 上游 RTL clone 新增文件，但 appendix A 未同步
     - ``find /home/host/Cores-VeeR-EH2/design -name '*.sv' | sort``
     - 先更新本页 §7 审计，再补对应模块页
   * - 仿真 compile 报 module not found
     - ``eh2_rtl.f`` 或 ``eh2_shared.f`` 编译顺序/路径漂移
     - ``sed -n '1,120p' dv/uvm/core_eh2/eh2_rtl.f``
     - 从本页 §2 filelist 顺序回查
   * - 某个 packet 字段连线不明
     - ``eh2_def.sv`` typedef 与顶层 ``.*`` 连接混在一起
     - ``rg -n "eh2_.*_pkt_t|\\$bits" /home/host/Cores-VeeR-EH2/design``
     - 读 :ref:`appendix_a_rtl/include`
   * - branch flush 或 PC 纠错看不懂
     - IFU/DEC/EXU 三章共同决定最终 redirect
     - ``rg -n "flush_path|misp|predict" /home/host/Cores-VeeR-EH2/design``
     - 先读 :ref:`appendix_a_rtl/exu`，再回 :ref:`appendix_a_rtl/ifu`
   * - load/store 返回顺序与 trace 对不上
     - LSU bus buffer、NB-load 和 DEC writeback tag 交叉
     - ``rg -n "nb_load|wb_tag|bus_buffer" /home/host/Cores-VeeR-EH2/design``
     - 读 :ref:`appendix_a_rtl/lsu` 与 :ref:`appendix_a_rtl/dec`
   * - LEC 数字与模块页不一致
     - 手工复制了旧 summary 或把子块结果当顶层结果
     - ``sed -n '1,40p' syn/build/lec_summary.txt``
     - 以 :ref:`lec_flow` 和 :ref:`adr-0020` 为准

§9  参考资料
------------

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_rtl.f`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/eh2_shared.f`
* :file:`/home/host/eh2-veri/rtl/snapshots/default/eh2_pdef.vh`
* :file:`/home/host/eh2-veri/rtl/design/include/eh2_def.sv`
* :file:`/home/host/eh2-veri/rtl/design/eh2_veer.sv`
* :file:`/home/host/eh2-veri/rtl/design/eh2_veer_wrapper.sv`
* :file:`/home/host/eh2-veri/rtl/eh2_veer_wrapper_rvfi.sv`
* :file:`/home/host/eh2-veri/shared/rtl/axi4_pkg.sv`
* :file:`/home/host/eh2-veri/shared/rtl/axi4_intf.sv`
* :file:`/home/host/eh2-veri/shared/rtl/axi4_slave_mem.sv`

关联章节：

* :ref:`appendix_a_rtl/wrapper`
* :ref:`appendix_a_rtl/ifu`
* :ref:`appendix_a_rtl/dec`
* :ref:`appendix_a_rtl/exu`
* :ref:`appendix_a_rtl/lsu`
* :ref:`appendix_a_rtl/dbg`
* :ref:`appendix_a_rtl/dmi`
* :ref:`appendix_a_rtl/pic`
* :ref:`appendix_a_rtl/dma`
* :ref:`appendix_a_rtl/mem`
* :ref:`appendix_a_rtl/lib`
* :ref:`appendix_a_rtl/include`
* :ref:`appendix_a_rtl/shared_axi4`

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页讲到的 RTL 模块或接口在当前 DUT hierarchy 中承担什么职责？
2. 哪一段源码或 literalinclude 最能证明该职责，而不是只依赖文字描述？
3. 该模块的输入、输出或状态机如果接错，最可能先在哪个 sign-off stage 暴露？
4. 本页引用的 coverage、LEC 或 demo 数字是否仍与 2026-05-19 VCS 主线一致？
5. 与 Ibex 对照时，EH2 的双线程、存储层次或 wrapper 差异在哪里需要单独标注？
