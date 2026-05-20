.. _appendix_c_tools/cosim_cpp:
.. _appendix_c_tools_cosim_cpp:

Spike DPI 协同仿真 C++ 源码
================================================================================

:status: draft
:source: dv/cosim/cosim.h; dv/cosim/cosim_dpi.cc; dv/cosim/cosim_dpi.svh; dv/cosim/spike_cosim.cc; dv/cosim/spike_cosim.h
:last-reviewed: 2026-05-19
:authors: GPT-doc-author

§1  总览
--------------------------------------------------------------------------------

本章逐段解释 :file:`dv/cosim/` 下的 Spike DPI 协同仿真 C++ 层。该层的边界很清楚：
SystemVerilog 侧只看见 `DPI-C` 函数，C++ 侧先把 `chandle` 还原成 `Cosim` 抽象接口，
再由 `SpikeCosim` 调用 Spike ISS 的 `processor_t`、`bus_t`、`mmu` 和 CSR API 完成逐条
指令比对。

数据路径如下：

.. code-block:: text

   eh2_cosim_scoreboard.sv
      │
      │  import "DPI-C" declarations
      ▼
   cosim_dpi.svh
      │
      │  C ABI: chandle + int/longint/string/open array
      ▼
   cosim_dpi.cc
      │
      │  static_cast<Cosim*>(handle)
      ▼
   cosim.h
      │
      │  virtual interface
      ▼
   spike_cosim.h / spike_cosim.cc
      │
      ├─ per-hart processor_t[0..1]
      ├─ shared bus_t + mem_t regions
      ├─ pending D-side AXI notifications
      └─ Spike step / CSR / interrupt / debug / memory callbacks

关键行为可以分成 5 类：

* `cosim_dpi.svh` 声明 SystemVerilog 可调用的 DPI 函数，所有 per-hart 函数都带 `thread_id`。
* `cosim_dpi.cc` 是薄 C shim：检查 `handle`、做基础类型转换、调用 `Cosim` 虚函数，并把失败返回成 SV 能理解的 `0/1`。
* `cosim.h` 定义 `Cosim` 抽象接口和 `DSideAccessInfo`，把 DUT 的 D-side 访问、CSR 同步、trap CSR 查询统一成 C++ 方法。
* `spike_cosim.h` 保存 `SpikeCosim` 的状态模型：最多 2 个 `processor_t`，共享 `bus_t`，每个 hart 独立维护 NMI、iside error、pending D-side、LR reservation 和指令计数。
* `spike_cosim.cc` 实现主逻辑：初始化 Spike、解析 config、执行 `step()`、比较 retired PC/GPR/CSR、处理中断/debug/NMI、比较内存访问、应用 EH2 特定 CSR WARL 与原子指令 fixup。

本章只描述源码已经实现的行为。和 cosim 架构、Scoreboard 三路 FIFO、trace/probe/AXI 时序有关的 SystemVerilog 解释见 :ref:`cosim_scoreboard`。

§2  DPI 声明层：`cosim_dpi.svh`
--------------------------------------------------------------------------------

§2.1  `riscv_cosim_init()` 与生命周期入口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`cosim_dpi.svh` 把 C++ 工厂函数暴露成 SystemVerilog `chandle` 返回值。SV 侧不直接知道 `SpikeCosim` 类型，只保存这个 `chandle`，后续所有 DPI 调用都把它传回 C++。

关键代码（`dv/cosim/cosim_dpi.svh:L8-L23`）：

.. code-block:: text

   // Initialize co-simulation
   import "DPI-C" function chandle riscv_cosim_init(
     input string config
   );

   // Destroy co-simulation instance
   import "DPI-C" function void riscv_cosim_destroy(
     input chandle handle
   );

   // Add memory region
   import "DPI-C" function void riscv_cosim_add_memory(
     input chandle handle,
     input int     base_addr,
     input int     size
   );

逐段解释：

* 第 8-L11 行：`riscv_cosim_init()` 只接收一个 `string config`。配置解析不在 SV 层做，而是在 C++ 工厂函数里解析 `isa`、`pc`、`mtvec`、`pmp_regions`、`pmp_granularity`、`mhpm_counters`、`trace` 和 `num_threads`。
* 第 13-L16 行：`riscv_cosim_destroy()` 接收同一个 `chandle`。C++ 侧会把它转成 `Cosim*` 后 `delete`。
* 第 18-L23 行：`riscv_cosim_add_memory()` 注册一段 Spike 可访问内存。Scoreboard 初始化时会把 boot、debug、external data、ICCM、DCCM、PIC、mailbox、NMI vector 等内存区域逐个传入。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:init_cosim()` 调用 `riscv_cosim_init()` 和多次 `riscv_cosim_add_memory()`。
* 调用：SV import 只声明符号，实际 C++ 实现在 `spike_cosim.cc:riscv_cosim_init()` 和 `cosim_dpi.cc:riscv_cosim_add_memory()`。
* 共享状态：返回的 `chandle` 是后续所有 DPI 调用共享的 cosim 对象句柄。

§2.2  `riscv_cosim_step()` 和状态通知函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：step 前的通知函数把 DUT trace item 中的 debug、NMI、MIP、mcycle 和 iside error 状态写进 Spike；`riscv_cosim_step()` 再让 Spike 执行或处理一条对应事件。

关键代码（`dv/cosim/cosim_dpi.svh:L25-L71`）：

.. code-block:: text

   // Step one instruction
   // Returns 1 on match, 0 on mismatch
   import "DPI-C" function int riscv_cosim_step(
     input chandle handle,
     input int     write_reg,
     input int     write_reg_data,
     input int     pc,
     input int     sync_trap,
     input int     suppress_reg_write,
     input int     thread_id
   );

   // Set MIP (pre and post values)
   import "DPI-C" function void riscv_cosim_set_mip(
     input chandle handle,
     input int     pre_mip,
     input int     post_mip,
     input int     thread_id
   );

   // Set NMI
   import "DPI-C" function void riscv_cosim_set_nmi(
     input chandle handle,
     input int     nmi,
     input int     thread_id
   );

逐段解释：

* 第 25-L35 行：`riscv_cosim_step()` 的输入来自 trace item 和异步 wb hint。`write_reg/write_reg_data` 是 DUT 观察到的 GPR 写回；`pc` 是 DUT retired PC；`sync_trap` 表示同步异常；`suppress_reg_write` 表示 EH2 抑制了一个本应写回的 load/div 写回；`thread_id` 把同一个 C++ 对象中的 per-hart 状态路由到 T0 或 T1。
* 第 37-L43 行：`riscv_cosim_set_mip()` 同时传 `pre_mip` 和 `post_mip`。C++ 侧用 `pre_mip` 判断本条指令开始时是否有可触发中断，用 `post_mip` 写入 Spike 的 MIP CSR 状态。
* 第 45-L57 行：`riscv_cosim_set_nmi()` 和 `riscv_cosim_set_nmi_int()` 分开声明，因为 Spike 的 `nmi` 与 `nmi_int` 是两个不同状态位。
* 第 59-L71 行：`riscv_cosim_set_debug_req()` 设置 halt request，`riscv_cosim_set_mcycle()` 保留与 Ibex 相同的通知顺序，但 C++ 侧不直接写 Spike 的 `mcycle` CSR。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:compare_instruction()` 在普通 retired 指令路径和 IRQ-only 路径都会按固定顺序调用通知函数。
* 调用：这些 import 对应 `cosim_dpi.cc` 中同名 C ABI 包装函数，再调用 `Cosim::step()`、`Cosim::set_mip()` 等虚函数。
* 共享状态：`thread_id` 选择 `SpikeCosim::thread_state[thread_id]` 和 `processors[thread_id]`。

§2.3  D-side、错误和 trap CSR 查询接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：这些 DPI import 让 SV 侧把 AXI 观测到的 D-side 访问送给 Spike，同时在 mismatch 后取回 C++ 层记录的错误字符串和 trap CSR 值。

关键代码（`dv/cosim/cosim_dpi.svh:L81-L152`）：

.. code-block:: text

   // Notify dside access
   import "DPI-C" function void riscv_cosim_notify_dside_access(
     input chandle handle,
     input int     store,
     input int     data,
     input int     addr,
     input int     be,
     input int     error,
     input int     misaligned_first,
     input int     misaligned_second,
     input int     misaligned_first_saw_error,
     input int     m_mode_access,
     input int     widened_load,
     input int     thread_id
   );

   // Set iside error
   import "DPI-C" function void riscv_cosim_set_iside_error(
     input chandle handle,
     input int     addr,
     input int     thread_id
   );

逐段解释：

* 第 81-L95 行：`riscv_cosim_notify_dside_access()` 的字段一一对应 `DSideAccessInfo`。`store/data/addr/be/error` 是基础访问信息；`misaligned_first/misaligned_second/misaligned_first_saw_error` 描述未对齐访问拆分；`m_mode_access` 保留 M-mode 访问信息；`widened_load` 标记 64-bit AXI beat 拆成两个 32-bit 通知的 widened load。
* 第 97-L102 行：`riscv_cosim_set_iside_error()` 把即将发生的取指错误地址传给 C++。C++ 的 `mmio_load()` 在取指地址对齐匹配时把 Spike 这次访问强制成 bus error。
* 第 111-L130 行：错误接口包括 `get_num_errors()`、`get_error()`、`get_result()` 和 `clear_errors()`。Scoreboard 在 `riscv_cosim_step()` 返回 0 后读取这些字符串，再清空 C++ 错误数组。
* 第 132-L152 行：`get_insn_cnt()` 用于报告 per-hart matched 指令数；`get_mcause/get_mepc/get_mtvec()` 用于 IRQ/exception 路径的 trap CSR 比对。

接口关系：

* 被调用：`notify_memory_access()` 调用 `riscv_cosim_notify_dside_access()`；`get_cosim_error_str()` 调用错误接口；`report_phase()` 和 `final_phase()` 调用 `get_insn_cnt()`。
* 调用：C++ 侧分别落到 `SpikeCosim::notify_dside_access()`、`SpikeCosim::set_iside_error()`、`get_errors()`、`clear_errors()`、`get_insn_cnt()` 和 trap CSR getter。
* 共享状态：D-side 通知进入 per-hart `pending_dside_accesses` 队列；错误字符串进入对象级 `errors` 向量。

§3  C shim 层：`cosim_dpi.cc`
--------------------------------------------------------------------------------

§3.1  `riscv_cosim_step()` 包装函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：C shim 把 SystemVerilog 的整数参数转换成 C++ 类型，调用 `Cosim::step()`，并把 C++ 异常转换为 SV 可见的失败返回值。

关键代码（`dv/cosim/cosim_dpi.cc:L62-L92`）：

.. code-block:: cpp

   // Step one instruction
   // Returns 1 on match, 0 on mismatch
   int riscv_cosim_step(void* handle, int write_reg, int write_reg_data,
                        int pc, int sync_trap, int suppress_reg_write,
                        int thread_id) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (!cosim) {
       return 0;
     }
     try {
       int result = cosim->step(static_cast<uint32_t>(write_reg),
                                static_cast<uint32_t>(write_reg_data),
                                static_cast<uint32_t>(pc),
                                sync_trap != 0,
                                suppress_reg_write != 0,
                                thread_id)
                  ? 1
                  : 0;
       return result;
     } catch (const std::exception &e) {
       fprintf(stderr, "COSIM WARNING: step exception at PC=0x%08x T%d: %s\n",
               (unsigned)pc, thread_id, e.what());
       fflush(stderr);
       return 0;
     } catch (...) {

逐段解释：

* 第 64-L70 行：`handle` 被解释成 `Cosim*`。空指针直接返回 0，SV 侧会把它当成 mismatch 或初始化失败后的 step 失败。
* 第 71-L80 行：`write_reg`、`write_reg_data` 和 `pc` 转成 `uint32_t`，`sync_trap` 与 `suppress_reg_write` 转成 `bool`，然后调用虚函数 `Cosim::step()`。返回 `true` 映射为 1，返回 `false` 映射为 0。
* 第 81-L91 行：C++ 标准异常和未知异常都不会穿过 DPI 边界继续传播，而是打印包含 PC 与 `thread_id` 的警告并返回 0。这样 SV 侧仍然通过同一条 mismatch 路径收敛。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:compare_instruction()` 第 653-L656 行调用。
* 调用：`Cosim::step()`，实际动态派发到 `SpikeCosim::step()`。
* 共享状态：不直接改状态，只通过 `Cosim` 虚函数改 `SpikeCosim` 对象。

§3.2  内存 backdoor 与单字节加载
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：DPI shim 支持 SV 侧添加内存区域、批量 backdoor 读写，以及按字节把测试 binary 加载到 Spike 内存模型。

关键代码（`dv/cosim/cosim_dpi.cc:L23-L60`）：

.. code-block:: cpp

   // Add memory region
   void riscv_cosim_add_memory(void* handle, int base_addr, int size) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (cosim) {
       cosim->add_memory(static_cast<uint32_t>(base_addr),
                         static_cast<size_t>(size));
     }
   }

   // Backdoor write memory
   int riscv_cosim_backdoor_write_mem(void* handle, int addr, int len,
                                      const svOpenArrayHandle data) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (!cosim) return 0;

     const uint8_t* data_ptr = static_cast<const uint8_t*>(
         svGetArrayPtr(data));
     if (!data_ptr) return 0;

逐段解释：

* 第 23-L29 行：`riscv_cosim_add_memory()` 只在 `cosim` 非空时调用虚函数。地址转为 `uint32_t`，长度转为 `size_t`，防止 SV 的有符号 `int` 直接进入 C++ 内存 API。
* 第 32-L39 行：backdoor write 从 `svOpenArrayHandle` 取连续数组指针；若 SV open array 不能映射为 C 指针，则返回 0。
* 第 41-L44 行：实际写入由 `Cosim::backdoor_write_mem()` 完成，C++ `bool` 被压成 SV `int`。

关键代码（`dv/cosim/cosim_dpi.cc:L171-L178`）：

.. code-block:: cpp

   // Write a single byte to co-simulation memory (for binary loading)
   void riscv_cosim_write_mem_byte(void* handle, int addr, int data) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (cosim) {
       uint8_t byte = static_cast<uint8_t>(data & 0xFF);
       cosim->backdoor_write_mem(static_cast<uint32_t>(addr), 1, &byte);
     }
   }

逐段解释：

* 第 171-L178 行：binary loader 使用单字节 DPI 写入。`data & 0xFF` 保证 SV 传入的 `int` 只取低 8 位，随后按长度 1 写入 Spike bus。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:init_cosim()` 调用 `add_memory()`；`eh2_cosim_binary_loader.svh` 和 `eh2_cosim_agent.sv` 调用 `write_mem_byte()`。
* 调用：`SpikeCosim::add_memory()`、`SpikeCosim::backdoor_write_mem()`、`SpikeCosim::backdoor_read_mem()`。
* 共享状态：改动 `SpikeCosim::bus` 与 `mems` 中挂载的 `mem_t` 内容。

§3.3  `DSideAccessInfo` 组包
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：C shim 把 `riscv_cosim_notify_dside_access()` 的扁平 `int` 参数组装成强类型 `DSideAccessInfo`，再交给 C++ 对象入队。

关键代码（`dv/cosim/cosim_dpi.cc:L139-L163`）：

.. code-block:: cpp

   // Notify dside access
   void riscv_cosim_notify_dside_access(void* handle, int store, int data,
                                        int addr, int be, int error,
                                        int misaligned_first,
                                        int misaligned_second,
                                        int misaligned_first_saw_error,
                                        int m_mode_access,
                                        int widened_load,
                                        int thread_id) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (cosim) {
       DSideAccessInfo info;
       info.store = (store != 0);
       info.data = static_cast<uint32_t>(data);
       info.addr = static_cast<uint32_t>(addr);
       info.be = static_cast<uint32_t>(be);

逐段解释：

* 第 140-L147 行：函数签名和 SV import 保持同顺序，避免 DPI 位置参数错位。
* 第 148-L150 行：空 `handle` 被忽略；非空时创建局部 `DSideAccessInfo`。
* 第 151-L160 行：布尔语义的字段用 `!= 0` 转换，地址、数据、BE 用 `uint32_t` 保存。
* 第 161 行：`notify_dside_access()` 负责真正入队，C shim 不做地址对齐和 thread 范围检查。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:notify_memory_access()` 在 AXI read/write 路径调用。
* 调用：`Cosim::notify_dside_access()`，实际派发到 `SpikeCosim::notify_dside_access()`。
* 共享状态：写入 `thread_state[thread_id].pending_dside_accesses`。

§3.4  错误读取与结果函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：DPI shim 把 C++ `errors` 向量暴露给 SV 日志路径，并提供一个聚合的 pass/fail 查询。

关键代码（`dv/cosim/cosim_dpi.cc:L180-L225`）：

.. code-block:: cpp

   // Get error count
   int riscv_cosim_get_num_errors(void* handle) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (!cosim) {
       return 0;
     }
     try {
       return static_cast<int>(cosim->get_errors().size());
     } catch (...) {
       return 0;
     }
   }

   // Get error message at index
   const char* riscv_cosim_get_error(void* handle, int index) {
     Cosim* cosim = static_cast<Cosim*>(handle);
     if (!cosim) return "null handle";
     try {
       const auto& errors = cosim->get_errors();
       if (index >= 0 && index < static_cast<int>(errors.size())) {

逐段解释：

* 第 181-L191 行：错误数量读取包在 `try/catch` 里。异常时返回 0，避免错误报告路径再次中断仿真。
* 第 194-L203 行：按 index 返回 `std::string::c_str()`。只有 index 在当前 `errors` 范围内才返回实际字符串，否则返回空字符串。
* 第 207-L215 行：`get_result()` 的语义是 `errors.empty()` 返回 pass，否则 fail；空 handle 或异常返回 `-1`。
* 第 218-L225 行：`clear_errors()` 清理 C++ 错误数组，SV 侧在拼接完错误字符串后调用。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:get_cosim_error_str()` 调用数量、逐条字符串和清理函数。
* 调用：`Cosim::get_errors()` 与 `Cosim::clear_errors()`。
* 共享状态：读取并清空 `SpikeCosim::errors`。

§4  抽象接口：`cosim.h`
--------------------------------------------------------------------------------

§4.1  `DSideAccessInfo` 的字段语义
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`DSideAccessInfo` 是 C++ 层承载 DUT D-side 访问的唯一结构。它把 SV 的 AXI 观察结果和未对齐、错误、widened load 元数据一起入队。

关键代码（`dv/cosim/cosim.h:L20-L32`）：

.. code-block:: cpp

   // Information about a dside transaction observed on the DUT memory interface
   struct DSideAccessInfo {
     bool store;
     uint32_t data;
     uint32_t addr;
     uint32_t be;
     bool error;
     bool misaligned_first;
     bool misaligned_second;
     bool misaligned_first_saw_error;
     bool m_mode_access;
     bool widened_load;
   };

逐段解释：

* 第 22-L25 行：`store` 区分 load/store；`data` 是 32-bit 数据片；`addr` 是 32-bit 对齐地址；`be` 是 4-bit byte enable，但用 `uint32_t` 保存。
* 第 26-L29 行：`error` 与 misaligned 标志描述 AXI 侧观察到的异常和拆分位置。`check_mem_access()` 使用这些字段判断是否该等待第二半、是否返回 bus error。
* 第 30-L31 行：`m_mode_access` 目前随 DPI 传入并保存；`widened_load` 用于识别 64-bit read beat 拆成两个 32-bit pending entry 的场景。

接口关系：

* 被调用：`cosim_dpi.cc:riscv_cosim_notify_dside_access()` 创建该结构。
* 调用：无成员函数；结构被 `SpikeCosim::notify_dside_access()` 和 `SpikeCosim::check_mem_access()` 消费。
* 共享状态：作为 `PendingMemAccess::dut_access_info` 保存在 per-hart pending 队列。

§4.2  `Cosim` 虚接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`Cosim` 把 DPI shim 和具体 Spike 实现解耦。DPI 层只依赖这些虚函数，因此 `riscv_cosim_init()` 必须返回可安全转换回 `Cosim*` 的指针。

关键代码（`dv/cosim/cosim.h:L34-L61`）：

.. code-block:: cpp

   class Cosim {
   public:
     virtual ~Cosim() {}

     // Add a memory region to the co-simulator environment.
     virtual void add_memory(uint32_t base_addr, size_t size) = 0;

     // Write bytes to co-simulator memory via backdoor.
     virtual bool backdoor_write_mem(uint32_t addr, size_t len,
                                     const uint8_t *data_in) = 0;

     // Read bytes from co-simulator memory via backdoor.
     virtual bool backdoor_read_mem(uint32_t addr, size_t len,
                                    uint8_t *data_out) = 0;

     // Step the co-simulator.
     //
     // write_reg: destination register index (0 = no write)
     // write_reg_data: data written to register
     // pc: program counter of the instruction
     // sync_trap: true if instruction caused synchronous trap
     // suppress_reg_write: true if register write was suppressed

逐段解释：

* 第 34-L36 行：抽象类提供虚析构函数，允许 `riscv_cosim_destroy()` 通过 `Cosim*` 删除派生类对象。
* 第 38-L47 行：内存接口分成区域注册和 backdoor 读写。区域注册改变 Spike bus 拓扑；backdoor 读写用于 binary 加载和指令解码 helper。
* 第 49-L61 行：`step()` 是核心比对接口，输入来自 DUT retired trace 与异步写回处理结果。

关键代码（`dv/cosim/cosim.h:L63-L104`）：

.. code-block:: cpp

     // Set MIP (interrupt pending) with pre/post values.
     // pre_mip: value used to determine if interrupt is pending
     // post_mip: value observed by next instruction
     virtual void set_mip(uint32_t pre_mip, uint32_t post_mip,
                          int thread_id = 0) = 0;

     // Set NMI state.
     virtual void set_nmi(bool nmi, int thread_id = 0) = 0;

     // Set NMI internal state.
     virtual void set_nmi_int(bool nmi_int, int thread_id = 0) = 0;

     // Set debug request.
     virtual void set_debug_req(bool debug_req, int thread_id = 0) = 0;

     // Set mcycle CSR value (full 64-bit).
     virtual void set_mcycle(uint64_t mcycle, int thread_id = 0) = 0;

逐段解释：

* 第 63-L79 行：中断、NMI、debug 和 `mcycle` 都是 step 前状态同步接口。它们不返回 `bool`，因为 C++ 层把 mismatch 统一记录在后续 `step()` 或错误查询路径。
* 第 81-L90 行：`set_csr()`、`notify_dside_access()` 和 `set_iside_error()` 分别服务 CSR 同步、AXI D-side 通知、I-side error 注入。
* 第 92-L104 行：错误、指令计数和 trap CSR getter 支撑 SV 报告与 IRQ/exception 路径比对。

接口关系：

* 被调用：所有 `cosim_dpi.cc` 包装函数都只看见 `Cosim`。
* 调用：具体实现全部由 `SpikeCosim` override。
* 共享状态：抽象类不保存状态，状态属于派生对象。

§5  SpikeCosim 状态模型：`spike_cosim.h`
--------------------------------------------------------------------------------

§5.1  继承关系与公开接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`SpikeCosim` 同时继承 `simif_t` 和 `Cosim`。`simif_t` 让 Spike 的 MMU/load/store 回调进入本对象，`Cosim` 让 DPI shim 通过统一接口调用本对象。

关键代码（`dv/cosim/spike_cosim.h:L30-L52`）：

.. code-block:: cpp

   class SpikeCosim : public simif_t, public Cosim {
   public:
     SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                uint32_t start_mtvec, const std::string &trace_log_path,
                uint32_t pmp_num_regions, uint32_t pmp_granularity,
                uint32_t mhpm_counter_num, int num_threads = 1);

     // simif_t implementation
     virtual char *addr_to_mem(reg_t addr) override;
     virtual bool mmio_load(reg_t addr, size_t len, uint8_t *bytes) override;
     virtual bool mmio_store(reg_t addr, size_t len,
                             const uint8_t *bytes) override;
     virtual void proc_reset(unsigned id) override;
     virtual const char *get_symbol(uint64_t addr) override;

     // Cosim implementation
     void add_memory(uint32_t base_addr, size_t size) override;
     bool backdoor_write_mem(uint32_t addr, size_t len,

逐段解释：

* 第 30-L35 行：构造函数的参数来自 config parser：ISA、起始 PC、起始 mtvec、trace log 路径、PMP 区域数、PMP granularity、MHPM counter 数和 `num_threads`。
* 第 37-L43 行：`simif_t` override 是 Spike 内部访问外部内存时调用的回调。`mmio_load()` 和 `mmio_store()` 是内存比对的入口。
* 第 45-L52 行：公开 `Cosim` override 承接 DPI shim，包括内存、step 和 per-hart 同步接口。

接口关系：

* 被调用：Spike `processor_t` 在执行访存指令时调用 `simif_t` 方法；DPI shim 调用 `Cosim` 方法。
* 调用：构造函数创建 `processor_t` 并把 `this` 作为 sim interface 传给 Spike。
* 共享状态：同一个 `SpikeCosim` 对象同时被 Spike 内部和 SV DPI 入口访问。

§5.2  双线程与共享内存状态
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：类成员把 `NUM_THREADS=1/2` 的 hart 状态分开，同时保持 EH2 的共享地址空间模型。

关键代码（`dv/cosim/spike_cosim.h:L74-L91`）：

.. code-block:: cpp

   private:
     // Number of hardware threads (1 or 2)
     int num_threads;

     // Spike processor(s) and ISA
     std::unique_ptr<isa_parser_t> isa_parser;
     std::unique_ptr<processor_t> processors[COSIM_MAX_THREADS];
     std::unique_ptr<log_file_t> log;

     // Active thread for mmio callbacks (set before each step)
     int active_thread;

     // Memory bus (shared across threads — EH2 shares address space)
     bus_t bus;
     std::vector<std::unique_ptr<mem_t>> mems;

     // Error tracking
     std::vector<std::string> errors;

逐段解释：

* 第 75-L81 行：`num_threads` 控制有效 hart 数，`processors` 数组最大长度由 `COSIM_MAX_THREADS` 固定为 2。`isa_parser` 作为成员存在，保证 Spike processor 生命周期内 ISA parser 不悬空。
* 第 83-L84 行：`active_thread` 在每次 `step()` 或 interrupt step 前设置。Spike 的 MMIO 回调没有显式 `thread_id` 参数，因此 C++ 层用该成员把回调归属到当前 hart。
* 第 86-L88 行：所有 hart 共享一个 `bus_t` 和同一组 `mem_t`，对应 EH2 双线程共享地址空间。
* 第 90-L91 行：`errors` 是对象级错误数组，不按 hart 拆分；错误字符串内部会带 `T<thread_id>` 前缀。

接口关系：

* 被调用：`get_processor()` 根据 `thread_id` 取 `processors[thread_id]`；`mmio_load()` 和 `mmio_store()` 根据 `active_thread` 找 per-hart 状态。
* 调用：`add_memory()` 往 `bus` 上挂 `mem_t`。
* 共享状态：`bus` 共享，`thread_state` 分 hart，`errors` 全局聚合。

§5.3  per-hart 状态与 pending D-side 队列
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`PerThreadState` 保存每个 hart 独有的 NMI、iside error、instruction count、pending D-side、LR reservation 和最近 step PC。

关键代码（`dv/cosim/spike_cosim.h:L93-L125`）：

.. code-block:: cpp

     // Pending dside accesses from DUT
     struct PendingMemAccess {
       DSideAccessInfo dut_access_info;
       uint32_t be_spike;
       bool is_atomic_store = false;  // true for SC/AMO store half
     };

     // Per-thread state
     struct PerThreadState {
       bool nmi_mode = false;
       bool pending_iside_error = false;
       uint32_t pending_iside_err_addr = 0;
       unsigned int insn_cnt = 0;

       // Mstack for NMI handling
       struct {
         uint8_t mpp = 0;
         bool mpie = false;
         uint32_t epc = 0;
         uint32_t cause = 0;
       } mstack;

逐段解释：

* 第 93-L98 行：`PendingMemAccess` 包含 DUT access、Spike 已经观察到的 byte enable 累积值 `be_spike`，以及原子 store 半程标记。
* 第 100-L105 行：NMI 模式、pending iside error 和指令计数都按 hart 独立保存。
* 第 107-L113 行：`mstack` 保存 NMI 进入前的 `mstatus`、`mepc` 和 `mcause` 关键信息，`leave_nmi_mode()` 在 `mret` 时恢复。

关键代码（`dv/cosim/spike_cosim.h:L115-L125`）：

.. code-block:: cpp

       // Pending dside accesses from DUT
       std::vector<PendingMemAccess> pending_dside_accesses;

       // LR reservation tracking for atomic cosim (issue 52)
       uint32_t lr_reservation_addr = 0;
       bool lr_reservation_valid = false;

       // PC of last stepped instruction (for commit-log-free instr type checks)
       uint32_t last_step_pc = 0;
     };
     PerThreadState thread_state[COSIM_MAX_THREADS];

逐段解释：

* 第 115-L116 行：`pending_dside_accesses` 是 AXI monitor 通知进入 C++ 后的待匹配队列。`check_mem_access()` 在 Spike 发起 load/store 回调时消费它。
* 第 118-L120 行：LR reservation 只用于原子 cosim fixup，记录 LR.W 地址和有效性。
* 第 122-L125 行：`last_step_pc` 记录当前被 Spike step 的 DUT PC。指令类型 helper 通过 backdoor 读内存，再结合该 PC 判断 atomic、SC、LR、load、div/rem 等情况。

接口关系：

* 被调用：`notify_dside_access()` push 队列，`check_mem_access()` erase 队列，`atomic_store_fixup()` 更新 LR reservation。
* 调用：无外部 API，全部是 `SpikeCosim` 内部状态。
* 共享状态：每个 hart 独立，防止 T0 的 AXI 通知被 T1 的 Spike step 消费。

§6  初始化：构造函数与 `riscv_cosim_init()`
--------------------------------------------------------------------------------

§6.1  `SpikeCosim::SpikeCosim()` 构造函数
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：构造函数创建 ISA parser、每个 hart 的 Spike `processor_t`，配置 PMP/MHPM，并调用 `initial_proc_setup()` 补齐 EH2 特有 CSR 与初始 PC/mtvec。

关键代码（`dv/cosim/spike_cosim.cc:L24-L54`）：

.. code-block:: cpp

   SpikeCosim::SpikeCosim(const std::string &isa_string, uint32_t start_pc,
                          uint32_t start_mtvec, const std::string &trace_log_path,
                          uint32_t pmp_num_regions, uint32_t pmp_granularity,
                          uint32_t mhpm_counter_num, int num_threads)
       : num_threads(num_threads), active_thread(0) {
     assert(num_threads >= 1 && num_threads <= COSIM_MAX_THREADS);

     FILE *log_file = nullptr;
     if (trace_log_path.length() != 0) {
       log = std::make_unique<log_file_t>(trace_log_path.c_str());
       log_file = log->get();
     }

     isa_parser = std::make_unique<isa_parser_t>(isa_string.c_str(), "MU");

     for (int t = 0; t < num_threads; ++t) {
       processors[t] = std::make_unique<processor_t>(
           isa_parser.get(), DEFAULT_VARCH, this, t, false, log_file, std::cerr);

逐段解释：

* 第 24-L29 行：构造函数保存 `num_threads` 并断言范围。上层 `riscv_cosim_init()` 已经 clamp，但构造函数仍保留内部断言。
* 第 31-L35 行：只有 `trace_log_path` 非空时才创建 Spike log file。`log_file` 指针随后传入每个 `processor_t`。
* 第 37 行：`isa_parser` 用配置中的 ISA 字符串和 `"MU"` privilege 字符串创建。
* 第 39-L41 行：每个 hart 创建一个 `processor_t`，`this` 被传为 `simif_t`，hart id 使用循环变量 `t`。

关键代码（`dv/cosim/spike_cosim.cc:L43-L53`）：

.. code-block:: cpp

       processors[t]->set_pmp_num(pmp_num_regions);
       processors[t]->set_mhpm_counter_num(mhpm_counter_num);
       processors[t]->set_pmp_granularity(1 << (pmp_granularity + 2));

       initial_proc_setup(t, start_pc, start_mtvec, mhpm_counter_num);

       if (log) {
         processors[t]->set_debug(true);
         processors[t]->enable_log_commits();
       }
     }

逐段解释：

* 第 43-L45 行：PMP region 数、MHPM counter 数和 PMP granularity 写入 Spike processor。granularity 按 `1 << (pmp_granularity + 2)` 转换。
* 第 47 行：`initial_proc_setup()` 写 PC、mtvec、marchid、MMU capability、trigger、MHPM event 和 EH2 custom CSR map。
* 第 49-L52 行：有 trace log 时打开 Spike debug 和 commit log，用于生成 Spike commit 记录。

接口关系：

* 被调用：`riscv_cosim_init()` 通过 `new SpikeCosim(...)` 调用。
* 调用：Spike `processor_t` 构造、PMP/MHPM setter、`initial_proc_setup()`。
* 共享状态：初始化 `processors[]`、`isa_parser`、`log`、`active_thread`。

§6.2  `initial_proc_setup()` 初始化 EH2 CSR
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数把 Spike 初始状态对齐 EH2：设置 PC、mtvec、`marchid`、MMU capability、trigger、MHPM event，并给 Spike csrmap 补充 EH2 自定义 CSR。

关键代码（`dv/cosim/spike_cosim.cc:L685-L710`）：

.. code-block:: cpp

   void SpikeCosim::initial_proc_setup(int thread_id, uint32_t start_pc,
                                       uint32_t start_mtvec,
                                       uint32_t mhpm_counter_num) {
     auto *proc = get_processor(thread_id);

     proc->get_state()->pc = start_pc;
     proc->get_state()->mtvec->write(start_mtvec);

     // Set EH2 marchid
     proc->get_state()->csrmap[CSR_MARCHID] =
         std::make_shared<const_csr_t>(proc, CSR_MARCHID, EH2_MARCHID);

     proc->set_mmu_capability(IMPL_MMU_SBARE);

     // Configure trigger modules
     for (int i = 0; i < proc->TM.count(); ++i) {
       proc->TM.tdata2_write(proc, i, 0);
       proc->TM.tdata1_write(proc, i, 0x28001048);

逐段解释：

* 第 685-L691 行：取对应 hart 的 `processor_t`，写入初始 `pc` 和 `mtvec`。
* 第 693-L695 行：用 `const_csr_t` 覆盖 `CSR_MARCHID`，值为 `EH2_MARCHID`。
* 第 697 行：MMU capability 设置为 `IMPL_MMU_SBARE`。
* 第 699-L703 行：遍历 Spike trigger module，把 `tdata2` 清零，把 `tdata1` 写为 `0x28001048`。
* 第 705-L710 行：按 `mhpm_counter_num` 创建 `CSR_MHPMEVENT3 + i` 的 const CSR，值为 `1 << i`。

关键代码（`dv/cosim/spike_cosim.cc:L712-L752`，节选）：

.. code-block:: cpp

     // Initialize EH2 custom CSRs in csrmap so they can be read/written
     // These are WD/Microchip extensions not natively supported by Spike
     static const int eh2_init_csrs[] = {
       0x7FF,  // mscause
       0x7C0,  // mrac
       0x7F9,  // mfdc
       0x7F8,  // mcgc
       0x7C6,  // mpmc
       0x7C2,  // mcpc
       0x7C4,  // dmst
       0x7CE,  // mfdht
       0x7CF,  // mfdhs
       0x7FC,  // mhartstart
       0x7FE,  // mnmipdel
       0x7D2,  // mitcnt0
       0x7D5,  // mitcnt1
       0x7D3,  // mitb0
       0x7D6,  // mitb1
       0x7D4,  // mitctl0
       0x7D7,  // mitctl1

逐段解释：

* 第 712-L714 行：C++ 侧把 EH2 自定义 CSR 预先放入 Spike `csrmap`，因为 Spike 原生不支持这些 WD/Microchip 扩展。
* 第 715-L744 行：列表包含 `mscause`、`mrac`、`mfdc`、`mcgc`、`mpmc`、`mcpc`、`dmst`、`mfdht`、`mfdhs`、`mhartstart`、`mnmipdel`、`mitcnt*`、`mitb*`、`mitctl*`、`mdeau`、`mdseac`、`micect`、`miccmect`、`mdccmect`、PIC 相关 CSR 和 `mhartnum`。
* 第 746-L752 行：只有当 csrmap 中还没有对应 CSR 时，才创建 `basic_csr_t`，避免覆盖 Spike 已有 CSR 对象。

接口关系：

* 被调用：构造函数对每个 hart 调用一次。
* 调用：Spike CSR map、trigger module 和 MMU capability API。
* 共享状态：修改每个 hart 的 `processor_t::state`。

§6.3  `riscv_cosim_init()` config 解析与返回指针
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：C ABI 工厂函数解析 SV 传来的分号分隔 config 字符串，创建 `SpikeCosim`，并返回调整后的 `Cosim` 子对象指针。

关键代码（`dv/cosim/spike_cosim.cc:L1608-L1622`）：

.. code-block:: cpp

   extern "C" void *riscv_cosim_init(const char *config) {
     // Parse config string: "isa=<ISA>;pc=<PC>;mtvec=<MTVEC>;pmp_regions=<N>;"
     //                       "pmp_granularity=<G>;mhpm_counters=<N>;trace=<PATH>"
     //                       ";num_threads=<N>"
     std::string config_str(config);
     // Default ISA string includes Zba/Zbb/Zbc/Zbs per default EH2 config.
     // If the config string contains ``isa=...`` the parsed value overrides this.
     std::string isa_string = "rv32imac_zba_zbb_zbc_zbs";
     uint32_t start_pc = 0;
     uint32_t start_mtvec = 0;
     uint32_t pmp_num_regions = 0;
     uint32_t pmp_granularity = 0;
     uint32_t mhpm_counter_num = 0;
     int num_threads = 1;
     std::string trace_log_path;

逐段解释：

* 第 1608-L1612 行：函数是 `extern "C"`，符号名必须和 SV import 完全一致。输入是 `const char *config`。
* 第 1615 行：默认 ISA 是 `rv32imac_zba_zbb_zbc_zbs`。如果 config 含 `isa=`，后续解析会覆盖。
* 第 1616-L1622 行：PC、mtvec、PMP、MHPM、`num_threads` 和 trace log path 都有默认值，允许 SV 只传部分字段。

关键代码（`dv/cosim/spike_cosim.cc:L1624-L1650`）：

.. code-block:: cpp

     // Simple config parser
     size_t pos = 0;
     while (pos < config_str.length()) {
       size_t eq_pos = config_str.find('=', pos);
       if (eq_pos == std::string::npos) break;

       size_t semi_pos = config_str.find(';', eq_pos);
       if (semi_pos == std::string::npos) semi_pos = config_str.length();

       std::string key = config_str.substr(pos, eq_pos - pos);
       std::string val = config_str.substr(eq_pos + 1, semi_pos - eq_pos - 1);

       if (key == "isa") isa_string = val;
       else if (key == "pc") start_pc = strtoul(val.c_str(), nullptr, 0);
       else if (key == "mtvec") start_mtvec = strtoul(val.c_str(), nullptr, 0);
       else if (key == "pmp_regions") pmp_num_regions = strtoul(val.c_str(), nullptr, 0);
       else if (key == "pmp_granularity") pmp_granularity = strtoul(val.c_str(), nullptr, 0);

逐段解释：

* 第 1624-L1634 行：解析器按 `key=value;` 格式扫描，不使用 YAML/JSON。没有 `=` 时结束，最后一个字段没有分号也能解析。
* 第 1636-L1643 行：字符串字段直接赋值；数值字段用 `strtoul()` 或 `strtol()`，base 参数为 0，因此十进制和 `0x` 前缀都可接受。
* 第 1648-L1650 行：`num_threads` 被 clamp 到 `[1, COSIM_MAX_THREADS]`，其中 `COSIM_MAX_THREADS` 在头文件中定义为 2。

关键代码（`dv/cosim/spike_cosim.cc:L1652-L1660`）：

.. code-block:: cpp

     SpikeCosim *cosim = new SpikeCosim(
         isa_string, start_pc, start_mtvec, trace_log_path,
         pmp_num_regions, pmp_granularity, mhpm_counter_num, num_threads);

     // SpikeCosim inherits simif_t first and Cosim second. Return the adjusted
     // Cosim subobject pointer because every DPI wrapper casts the chandle back to
     // Cosim*. Returning the raw SpikeCosim* would make the wrapper read the
     // simif_t vtable as a Cosim vtable and can crash on virtual calls.
     return static_cast<void *>(static_cast<Cosim *>(cosim));

逐段解释：

* 第 1652-L1654 行：工厂函数创建具体 `SpikeCosim` 对象，传入解析后的所有字段。
* 第 1656-L1659 行：源码明确说明多重继承布局风险：`SpikeCosim` 先继承 `simif_t`，再继承 `Cosim`。DPI 包装函数会把 `chandle` 转回 `Cosim*`，所以必须返回 `Cosim` 子对象地址。
* 第 1660 行：返回值做了两层 cast：先转 `Cosim*` 触发指针调整，再转 `void*` 交给 SV `chandle`。

接口关系：

* 被调用：`eh2_cosim_scoreboard.sv:init_cosim()` 调用。
* 调用：`SpikeCosim` 构造函数。
* 共享状态：创建整个 cosim 对象；返回的指针由 SV 保存，析构时传回 `riscv_cosim_destroy()`。

§7  主循环：`SpikeCosim::step()`
--------------------------------------------------------------------------------

§7.1  step 前置检查与 debug ebreak 快路径
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`step()` 先确认寄存器和 hart 参数范围，再特殊处理会进入 debug mode 的 `ebreak`，因为 Spike 执行这类 `ebreak` 时会直接进入 debug handler，不能按普通 retired 指令路径处理。

关键代码（`dv/cosim/spike_cosim.cc:L303-L319`）：

.. code-block:: cpp

   bool SpikeCosim::step(uint32_t write_reg, uint32_t write_reg_data, uint32_t pc,
                         bool sync_trap, bool suppress_reg_write,
                         int thread_id) {
     assert(write_reg < 32);
     assert(thread_id >= 0 && thread_id < num_threads);

     auto *proc = get_processor(thread_id);
     auto &ts = thread_state[thread_id];

     // First check if this is an ebreak that should enter debug mode. These need
     // specific handling. When spike steps over an ebreak entering debug mode it
     // immediately steps the next instruction (first instruction of debug handler)
     // too. To deal with this, skip the rest of the function for debug ebreaks.
     if (pc_is_debug_ebreak(thread_id, pc)) {
       check_debug_ebreak(thread_id, write_reg, pc, sync_trap);
       return errors.size() == 0;
     }

逐段解释：

* 第 306-L307 行：`write_reg` 必须是 0-31，`thread_id` 必须落在已创建的 hart 数内。
* 第 309-L310 行：`proc` 和 `ts` 分别是当前 hart 的 Spike processor 和 per-thread 状态。
* 第 312-L319 行：如果当前 PC 解码为会进入 debug 的 `ebreak`，函数只检查 DUT 不应写 GPR 且不应报告同步 trap，然后直接返回。源码注释说明原因是 Spike 对 debug ebreak 会连带 step debug handler 第一条指令。

接口关系：

* 被调用：`cosim_dpi.cc:riscv_cosim_step()`。
* 调用：`pc_is_debug_ebreak()`、`check_debug_ebreak()`。
* 共享状态：读取 `errors` 决定返回值；debug ebreak 快路径不递增 `insn_cnt`。

§7.2  suppressed writeback 保护与 Spike step
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：当 DUT 报告写回被抑制时，C++ 先验证该抑制只用于 load 或 div/rem，并保存 Spike 即将写的寄存器旧值；Spike step 后再恢复，防止 killed load 或取消的非阻塞 DIV/REM 污染后续比对。

关键代码（`dv/cosim/spike_cosim.cc:L321-L355`）：

.. code-block:: cpp

     uint32_t initial_spike_pc;
     uint32_t suppressed_write_reg;
     uint32_t suppressed_write_reg_data;
     bool pending_sync_exception = false;

     if (suppress_reg_write) {
       if (!check_suppress_reg_write(thread_id, write_reg, pc,
                                     suppressed_write_reg)) {
         return false;
       }
       suppressed_write_reg_data =
           proc->get_state()->XPR[suppressed_write_reg];
     }

     // Record current spike PC before stepping
     initial_spike_pc = (proc->get_state()->pc & 0xffffffff);

     ts.last_step_pc = pc;

逐段解释：

* 第 321-L324 行：函数记录 step 前 PC、可能被抑制的寄存器号和旧值，并初始化同步异常标志。
* 第 326-L333 行：如果 `suppress_reg_write` 为真，先调用 `check_suppress_reg_write()`。通过后，从 Spike XPR 读取该寄存器旧值。
* 第 335-L338 行：保存 Spike 当前 PC，并把 DUT PC 写入 `last_step_pc`，后续 MMIO 回调和指令类型 helper 会用它判断当前指令类型。

关键代码（`dv/cosim/spike_cosim.cc:L340-L355`）：

.. code-block:: cpp

     active_thread = thread_id;
     try {
       proc->step(1);
     } catch (const std::exception &e) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " Spike step exception at PC " << std::hex
               << initial_spike_pc << ": " << e.what();
       errors.emplace_back(err_str.str());
       return false;
     } catch (...) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " Spike unknown step exception at PC "
               << std::hex << initial_spike_pc;
       errors.emplace_back(err_str.str());
       return false;
     }

逐段解释：

* 第 340 行：设置 `active_thread`，让后续 `mmio_load()` 或 `mmio_store()` 能找到正确的 per-hart 队列。
* 第 341-L343 行：调用 Spike `processor_t::step(1)` 执行一个 Spike 步进。
* 第 343-L355 行：任何异常都转成 `errors` 字符串并返回 false，避免异常越过 `SpikeCosim::step()`。

接口关系：

* 被调用：普通 retired 指令路径调用。
* 调用：`check_suppress_reg_write()`、Spike `processor_t::step()`。
* 共享状态：写 `last_step_pc` 和 `active_thread`，可能向 `errors` 添加异常字符串。

§7.3  trap 分类与 IRQ ISR 二次 step
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：Spike step 后，如果没有 retired instruction，C++ 根据 `mcause` 和 debug mode 区分同步异常与异步中断。异步中断路径会再 step 一次，以执行 ISR 第一条指令。

关键代码（`dv/cosim/spike_cosim.cc:L357-L397`）：

.. code-block:: cpp

     if (proc->get_state()->last_inst_pc == PC_INVALID) {
       if (!(proc->get_state()->mcause->read() & 0x80000000) ||
           proc->get_state()->debug_mode) {
         // Synchronous trap
         pending_sync_exception = true;
       } else {
         // Asynchronous trap - step to first instruction of ISR
         initial_spike_pc = (proc->get_state()->pc & 0xffffffff);
         active_thread = thread_id;
         try {
           proc->step(1);
         } catch (const std::exception &e) {
           std::stringstream err_str;
           err_str << "T" << thread_id << " Spike ISR step exception at PC "
                   << std::hex << initial_spike_pc << ": " << e.what();
           errors.emplace_back(err_str.str());
           return false;
         }

逐段解释：

* 第 357-L362 行：`last_inst_pc == PC_INVALID` 表示本次 Spike step 没有普通 retired PC。若 `mcause` 不是 interrupt 或 Spike 在 debug mode，则视为同步 trap。
* 第 363-L374 行：异步 trap 路径把 `initial_spike_pc` 更新为 ISR PC，再 step 一次。若 ISR step 抛异常，记录错误并返回 false。
* 第 376-L379 行：如果 ISR step 后仍然没有 retired instruction，则把它转成待处理的同步异常。
* 第 381-L397 行：若最终是同步异常而 DUT 没报 `sync_trap`，记录 mismatch；否则调用 `check_sync_trap()` 比对异常入口 PC 和写回约束。

接口关系：

* 被调用：`step()` 内部。
* 调用：Spike `processor_t::step()`、`check_sync_trap()`。
* 共享状态：读取 Spike `mcause`、`debug_mode`、`last_inst_pc`；错误进入 `errors`。

§7.4  retired PC/GPR/CSR 比对
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：普通 retired 指令路径先处理 NMI 退出和 pending iside error，再恢复 suppressed 写回，清理诊断性内存错误，最后调用 `check_retired_instr()` 做 PC/GPR/CSR 比对。

关键代码（`dv/cosim/spike_cosim.cc:L400-L453`）：

.. code-block:: cpp

     // We reached a retired instruction

     // Check for mret - handle NMI mode exit
     if (!sync_trap && pc_is_mret(thread_id, pc)) {
       if (ts.nmi_mode) {
         leave_nmi_mode(thread_id);
       }
     }

     // Check for unconsumed iside error
     if (ts.pending_iside_error) {
       std::stringstream err_str;
       err_str << "T" << thread_id
               << " DUT generated an iside error for address: " << std::hex
               << ts.pending_iside_err_addr
               << " but the ISS didn't produce one";
       errors.emplace_back(err_str.str());
       ts.pending_iside_error = false;

逐段解释：

* 第 402-L407 行：如果 DUT PC 是 `mret` 且当前 hart 在 NMI 模式，调用 `leave_nmi_mode()` 恢复 NMI 进入前保存的 CSR 状态。
* 第 409-L419 行：如果 SV 侧此前设置了 pending iside error，但 Spike step 没有在 `mmio_load()` 中消费它，则记录错误并清掉 pending 标志。
* 第 421-L424 行：对 suppressed writeback，把 Spike XPR 恢复到 step 前旧值。
* 第 426-L431 行：清理 `mmio_store()` 期间生成的诊断性错误，避免 store coalescing 或 widened store 诊断影响 retired 指令结构比对。
* 第 433-L436 行：调用 `check_retired_instr()`。失败时直接返回 false。
* 第 438-L453 行：atomic memory 指令后 flush TLB；如果还有诊断性错误，再清空；最后 per-hart `insn_cnt++` 并返回 true。

接口关系：

* 被调用：`step()` 内部。
* 调用：`pc_is_mret()`、`leave_nmi_mode()`、`check_retired_instr()`、`pc_is_atomic_mem_instr()`、Spike `flush_tlb()`。
* 共享状态：读取和清理 `pending_iside_error`、`errors`，递增 `thread_state[thread_id].insn_cnt`。

§7.5  `check_retired_instr()` PC 与写回比对
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数是普通 retired 指令的结构化比对点：先比对 DUT PC 和 Spike retired PC，再遍历 Spike commit log 中的 GPR/CSR 写记录。

关键代码（`dv/cosim/spike_cosim.cc:L456-L512`）：

.. code-block:: cpp

   bool SpikeCosim::check_retired_instr(int thread_id, uint32_t write_reg,
                                        uint32_t write_reg_data, uint32_t dut_pc,
                                        bool suppress_reg_write) {
     auto *proc = get_processor(thread_id);

     // Check PC matches
     if ((proc->get_state()->last_inst_pc & 0xffffffff) != dut_pc) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " PC mismatch, DUT retired : " << std::hex
               << dut_pc << " , but the ISS retired: " << std::hex
               << (proc->get_state()->last_inst_pc & 0xffffffff);
       errors.emplace_back(err_str.str());
       return false;
     }

     // Check register writes match
     auto &reg_changes = proc->get_state()->log_reg_write;

逐段解释：

* 第 456-L459 行：函数只拿当前 hart 的 `processor_t`，不再解析 SV item。
* 第 461-L469 行：DUT retired PC 必须等于 Spike `last_inst_pc` 的低 32 位。失败时记录包含 hart、DUT PC 和 ISS PC 的错误。
* 第 471-L474 行：读取 Spike commit log 的 `log_reg_write`，并用 `gpr_write_seen` 防止多个 GPR 写回。

关键代码（`dv/cosim/spike_cosim.cc:L476-L511`）：

.. code-block:: cpp

     for (auto reg_change : reg_changes) {
       // Ignore writes to x0
       if (reg_change.first == 0)
         continue;

       if ((reg_change.first & 0xf) == 0) {
         // GPR write
         assert(!gpr_write_seen);

         if (!suppress_reg_write &&
             !check_gpr_write(thread_id, reg_change, write_reg, write_reg_data)) {
           return false;
         }

         gpr_write_seen = true;
       } else if ((reg_change.first & 0xf) == 4) {
         // CSR write
         on_csr_write(thread_id, reg_change);

逐段解释：

* 第 476-L479 行：Spike commit log 中写 x0 的记录被忽略。
* 第 481-L490 行：低 4 位为 0 表示 GPR 写。没有 suppressed writeback 时调用 `check_gpr_write()` 比对 DUT 和 Spike 的目标寄存器及数据。
* 第 491-L494 行：低 4 位为 4 表示 CSR 写，调用 `on_csr_write()`，再进入 `fixup_csr()` 对齐 EH2 WARL 行为。
* 第 499-L505 行：如果 DUT 报告写 GPR 但 Spike commit log 没有 GPR 写，记录 mismatch。
* 第 507-L511 行：只要 `errors` 非空就返回 false，否则返回 true。

接口关系：

* 被调用：`step()`。
* 调用：`check_gpr_write()`、`on_csr_write()`。
* 共享状态：读取 Spike commit log；可能向 `errors` 写入 PC/GPR mismatch。

§7.6  `check_gpr_write()` 的 SC.W 与 NB-load 容忍
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：该函数比对 Spike commit log 中的 GPR 写回和 DUT 写回。源码中对 SC.W 和 EH2 store-buffer forwarding 时序做了特殊容忍。

关键代码（`dv/cosim/spike_cosim.cc:L559-L610`）：

.. code-block:: cpp

   bool SpikeCosim::check_gpr_write(int thread_id,
                                    const commit_log_reg_t::value_type &reg_change,
                                    uint32_t write_reg, uint32_t write_reg_data) {
     auto *proc = get_processor(thread_id);
     uint32_t cosim_write_reg = (reg_change.first >> 4) & 0x1f;

     if (write_reg == 0) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " DUT didn't write to register x"
               << cosim_write_reg << ", but a write was expected";
       errors.emplace_back(err_str.str());
       return false;
     }

     if (write_reg != cosim_write_reg) {
       std::stringstream err_str;
       err_str << "T" << thread_id << " Register write index mismatch, DUT: x"

逐段解释：

* 第 562-L563 行：从 Spike commit log 的 encoded key 中取目标 GPR 编号。
* 第 565-L571 行：如果 Spike 期望有 GPR 写，但 DUT `write_reg` 为 0，记录错误。
* 第 573-L579 行：DUT 和 Spike 目标寄存器编号不一致时记录 index mismatch。
* 第 581-L592 行：数据不一致且当前指令是 SC.W 时，DUT 的 SC 结果被视作 authoritative；函数把 Spike GPR 改写成 DUT 的值并返回 true。
* 第 595-L607 行：非 SC.W 的数据不一致也返回 true。源码注释解释为 EH2 store-buffer forwarding timing 下的 NB-load 数据时序差异：Spike 保持 ISA-correct 值，不修改 Spike GPR。

接口关系：

* 被调用：`check_retired_instr()`。
* 调用：`is_sc_instr()`，必要时写 Spike XPR。
* 共享状态：可能写 `processor_t` 的 GPR 状态；不直接消费 pending D-side 队列。

§8  中断、NMI、debug 与 CSR 同步
--------------------------------------------------------------------------------

§8.1  `set_mip()` 与 `early_interrupt_handle()`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`set_mip()` 把 DUT 的 MIP pre/post 值写进 Spike，并在新的 enabled interrupt 出现时提前调用 `early_interrupt_handle()`。后者让 Spike 处理 interrupt 状态但期望不 retire 普通指令。

关键代码（`dv/cosim/spike_cosim.cc:L759-L784`）：

.. code-block:: cpp

   void SpikeCosim::set_mip(uint32_t pre_mip, uint32_t post_mip,
                            int thread_id) {
     auto *proc = get_processor(thread_id);

     uint32_t old_mip = proc->get_state()->mip->read();

     proc->get_state()->mip->write_with_mask(0xffffffff, post_mip);
     proc->get_state()->mip->write_pre_val(pre_mip);

     if (proc->get_state()->debug_mode ||
         (proc->halt_request == processor_t::HR_REGULAR) ||
         (!get_field(proc->get_csr(CSR_MSTATUS), MSTATUS_MIE) &&
          proc->get_state()->prv == PRV_M)) {
       return;
     }

逐段解释：

* 第 761-L767 行：读取旧 MIP，写入 post 值，并把 pre 值写入 Spike 的 pre-value 通道。
* 第 768-L773 行：debug mode、常规 halt request、或 M-mode 下 `MSTATUS.MIE` 未置位时，函数直接返回，不触发 early interrupt。
* 第 775-L783 行：用旧 enabled IRQ 与新 enabled IRQ 比较。只有从无到有时调用 `early_interrupt_handle()`。

关键代码（`dv/cosim/spike_cosim.cc:L278-L297`）：

.. code-block:: cpp

   void SpikeCosim::early_interrupt_handle(int thread_id) {
     auto *proc = get_processor(thread_id);

     // Execute a spike step on the assumption an interrupt will occur so no new
     // instruction is executed just the state altered to reflect the interrupt.
     uint32_t initial_spike_pc = (proc->get_state()->pc & 0xffffffff);

     active_thread = thread_id;
     proc->step(1);

     if (proc->get_state()->last_inst_pc != PC_INVALID) {
       std::stringstream err_str;
       err_str << "T" << thread_id
               << " Attempted step for interrupt, expecting no instruction would "

逐段解释：

* 第 278-L286 行：函数记录 Spike PC，设置 `active_thread`，然后执行一次 Spike step。
* 第 288-L296 行：如果这次 step 产生了 `last_inst_pc`，说明 Spike retire 了普通指令，和函数预期不符，于是记录错误。

接口关系：

* 被调用：`cosim_dpi.cc:riscv_cosim_set_mip()` 调用 `set_mip()`；`set_mip()` 内部调用 `early_interrupt_handle()`。
* 调用：Spike `mip` CSR API、`processor_t::step()`。
* 共享状态：写 Spike MIP pre/post 值，可能更新 trap 状态并写 `errors`。

§8.2  NMI 进入与 `mret` 恢复
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`set_nmi()` 和 `set_nmi_int()` 在可进入 NMI 时保存 `mstack`，设置 Spike NMI 状态，并调用 early interrupt。`leave_nmi_mode()` 在 `mret` 路径恢复保存的 CSR 状态。

关键代码（`dv/cosim/spike_cosim.cc:L790-L807`）：

.. code-block:: cpp

   void SpikeCosim::set_nmi(bool nmi, int thread_id) {
     auto *proc = get_processor(thread_id);
     auto &ts = thread_state[thread_id];

     if (nmi && !ts.nmi_mode && !proc->get_state()->debug_mode &&
         proc->halt_request != processor_t::HR_REGULAR) {
       proc->get_state()->nmi = true;
       ts.nmi_mode = true;

       // Save CSR state for recoverable NMI to mstack
       ts.mstack.mpp = get_field(proc->get_csr(CSR_MSTATUS), MSTATUS_MPP);
       ts.mstack.mpie = get_field(proc->get_csr(CSR_MSTATUS), MSTATUS_MPIE);
       ts.mstack.epc = proc->get_csr(CSR_MEPC);
       ts.mstack.cause = proc->get_csr(CSR_MCAUSE);

逐段解释：

* 第 790-L795 行：只有 `nmi` 为真、当前不在 NMI mode、不在 debug mode、且没有常规 halt request 时才进入。
* 第 796-L798 行：设置 Spike `nmi`，并把 per-hart `nmi_mode` 标为真。
* 第 799-L803 行：保存 `MSTATUS.MPP`、`MSTATUS.MPIE`、`MEPC` 和 `MCAUSE`。
* 第 805 行：调用 `early_interrupt_handle()` 让 Spike 进入对应中断状态。

关键代码（`dv/cosim/spike_cosim.cc:L669-L683`）：

.. code-block:: cpp

   void SpikeCosim::leave_nmi_mode(int thread_id) {
     auto *proc = get_processor(thread_id);
     auto &ts = thread_state[thread_id];

     ts.nmi_mode = false;

     // Restore CSR status from mstack
     uint32_t mstatus = proc->get_csr(CSR_MSTATUS);
     mstatus = set_field(mstatus, MSTATUS_MPP, ts.mstack.mpp);
     mstatus = set_field(mstatus, MSTATUS_MPIE, ts.mstack.mpie);
     proc->put_csr(CSR_MSTATUS, mstatus);

     proc->put_csr(CSR_MEPC, ts.mstack.epc);
     proc->put_csr(CSR_MCAUSE, ts.mstack.cause);
   }

逐段解释：

* 第 669-L674 行：取当前 hart 状态并退出 NMI mode。
* 第 676-L679 行：读取当前 `mstatus`，只恢复 `MPP` 和 `MPIE` 字段，再写回。
* 第 681-L682 行：恢复 NMI 进入前保存的 `MEPC` 和 `MCAUSE`。

接口关系：

* 被调用：SV 通过 `riscv_cosim_set_nmi()` 和 `riscv_cosim_set_nmi_int()` 进入；`step()` 遇到 `mret` 时调用 `leave_nmi_mode()`。
* 调用：Spike CSR getter/setter、`early_interrupt_handle()`。
* 共享状态：修改 `thread_state[thread_id].nmi_mode` 和 `mstack`。

§8.3  debug request、debug ebreak 与 `mcycle`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：debug request 直接映射到 Spike halt request；debug ebreak 通过指令解码和 `dcsr` 位判断；`set_mcycle()` 只消费样本，不写 Spike CSR。

关键代码（`dv/cosim/spike_cosim.cc:L172-L199`）：

.. code-block:: cpp

   bool SpikeCosim::pc_is_debug_ebreak(int thread_id, uint32_t pc) {
     auto *proc = get_processor(thread_id);
     uint32_t dcsr = proc->get_csr(CSR_DCSR);

     // ebreak debug entry is controlled by ebreakm (bit 15) and ebreaku (bit 12).
     // If the appropriate bit of the current privilege level isn't set, ebreak
     // won't enter debug mode so return false.
     if (((proc->get_state()->prv == PRV_M) && ((dcsr & 0x1000) == 0)) ||
         ((proc->get_state()->prv == PRV_U) && ((dcsr & 0x8000) == 0))) {
       return false;
     }

     // Check for 16-bit c.ebreak
     uint16_t insn_16;

逐段解释：

* 第 172-L174 行：函数读取当前 hart 的 `DCSR`。
* 第 176-L182 行：M-mode 需要 `dcsr` bit 12，U-mode 需要 bit 15；否则 `ebreak` 不进入 debug。
* 第 184-L190 行：backdoor 读取 16-bit 指令，匹配 `c.ebreak` 编码 `0x9002`。
* 第 193-L198 行：再读取 32-bit 指令，匹配 `ebreak` 编码 `0x00100073`。

关键代码（`dv/cosim/spike_cosim.cc:L836-L855`）：

.. code-block:: cpp

   void SpikeCosim::set_debug_req(bool debug_req, int thread_id) {
     auto *proc = get_processor(thread_id);
     proc->halt_request =
         debug_req ? processor_t::HR_REGULAR : processor_t::HR_NONE;
   }

   // ---------------------------------------------------------------
   // set_mcycle() - Consume DUT mcycle samples without touching Spike CSR state
   // ---------------------------------------------------------------

   void SpikeCosim::set_mcycle(uint64_t mcycle, int thread_id) {
     // EH2 samples mcycle every retired instruction to keep the same DPI
     // ordering as Ibex. This Spike build has no public no-log backdoor for
     // mcycle; writing CSR_MCYCLE/CSR_MCYCLEH from this DPI callback can enter

逐段解释：

* 第 836-L840 行：`debug_req` 为真时设置 `processor_t::HR_REGULAR`，否则清为 `HR_NONE`。
* 第 846-L855 行：`set_mcycle()` 只把参数标记为已使用，不修改 Spike CSR。源码注释说明写 `CSR_MCYCLE/CSR_MCYCLEH` 可能进入 commit-log CSR side path 并导致 VCS 崩溃。

接口关系：

* 被调用：SV 的通知序列调用 `riscv_cosim_set_debug_req()` 和 `riscv_cosim_set_mcycle()`。
* 调用：Spike halt request 字段、backdoor memory 读取和 CSR 读取。
* 共享状态：debug request 修改 `processor_t::halt_request`；`mcycle` 不修改 Spike 状态。

§8.4  `fixup_csr()` 的 EH2 WARL 对齐
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：Spike 与 EH2 对某些 CSR 的 WARL 行为不同。`on_csr_write()` 在看到 Spike commit log 的 CSR 写后调用 `fixup_csr()`，把 Spike CSR 状态改成 EH2 语义。

关键代码（`dv/cosim/spike_cosim.cc:L659-L667`）：

.. code-block:: cpp

   void SpikeCosim::on_csr_write(int thread_id,
                                  const commit_log_reg_t::value_type &reg_change) {
     int cosim_write_csr = (reg_change.first >> 4) & 0xfff;
     uint32_t cosim_write_csr_data = reg_change.second.v[0];

     // Spike and EH2 have different WARL behaviours so after any CSR write
     // check the fields and adjust to match EH2 behaviour.
     fixup_csr(thread_id, cosim_write_csr, cosim_write_csr_data);
   }

逐段解释：

* 第 661-L662 行：从 Spike commit log key 和 value 中提取 CSR 编号和值。
* 第 664-L666 行：所有 CSR 写都统一走 `fixup_csr()`，不在 `check_retired_instr()` 中分散处理。

关键代码（`dv/cosim/spike_cosim.cc:L1070-L1102`）：

.. code-block:: cpp

   void SpikeCosim::fixup_csr(int thread_id, int csr_num, uint32_t csr_val) {
     auto *proc = get_processor(thread_id);

   #define ENSURE_CSR_EXISTS(num) \
     if (proc->get_state()->csrmap.find(num) == \
         proc->get_state()->csrmap.end()) { \
       proc->get_state()->csrmap[num] = \
           std::make_shared<basic_csr_t>(proc, num, 0); \
     }

     switch (csr_num) {
       case CSR_MSTATUS: {
         // EH2 mstatus: only M-mode, no S/U mode bits
         uint32_t mask = MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP |
                         MSTATUS_MPRV | MSTATUS_TW | MSTATUS_FS;

逐段解释：

* 第 1070-L1078 行：`ENSURE_CSR_EXISTS` 宏在写自定义 CSR 前确保 csrmap 有对象。
* 第 1080-L1088 行：`CSR_MSTATUS` 只保留 EH2 支持的字段，并强制 `MPP` 为 `PRV_M`。
* 第 1090-L1094 行：`CSR_MISA` 固定为 `0x40001105`，源码注释标明这是 RV32IMAC。
* 第 1096-L1102 行：`CSR_MTVEC` 只保留 BASE 和 bit 0 mode，清 bit 1。

关键代码（`dv/cosim/spike_cosim.cc:L1198-L1248`，节选）：

.. code-block:: cpp

       // --- mfdc (0x7F9): Feature Disable Control ---
       // Bit-reverse/rearrange: RTL stores internal representation differently
       // from the architectural value. Convert arch→internal, then internal→arch.
       case 0x7F9: {
         uint32_t mfdc_int = 0;
         mfdc_int |= ((csr_val >> 0) & 0x1) << 0;
         mfdc_int |= ((csr_val >> 2) & 0x3) << 1;
         mfdc_int |= (~(csr_val >> 6) & 0x1) << 3;
         mfdc_int |= ((csr_val >> 8) & 0xF) << 4;
         mfdc_int |= ((csr_val >> 12) & 0x1) << 8;
         mfdc_int |= (~(csr_val >> 16) & 0x7) << 9;
         uint32_t fixed = 0;
         fixed |= ((mfdc_int >> 0) & 0x1) << 0;
         fixed |= ((mfdc_int >> 1) & 0x3) << 2;

逐段解释：

* 第 1198-L1218 行：`mfdc` 先从 architectural value 变换到内部表示，再变回 architectural fixed 值，最后写入 csrmap。
* 第 1221-L1228 行：`mcgc` 保留低 10 位并翻转 bit 9。
* 第 1231-L1241 行：`micect/miccmect/mdccmect` 的 threshold 字段在大于 26 时饱和到 26。
* 第 1244-L1248 行：`meihap` 被当成只读，写入被忽略。

接口关系：

* 被调用：`on_csr_write()` 和部分路径的 `set_csr()` 后续行为共同依赖 CSR map 已存在。
* 调用：Spike `put_csr()`、CSR map `write()`。
* 共享状态：直接修改当前 hart 的 Spike CSR 状态。

§9  内存访问、PMP 与原子指令
--------------------------------------------------------------------------------

§9.1  MMIO load/store 回调
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：Spike 访存时会进入 `mmio_load()` 或 `mmio_store()`。C++ 先操作共享 bus，再把 Spike 的访存与 SV 侧已入队的 DUT AXI 通知进行比较。

关键代码（`dv/cosim/spike_cosim.cc:L73-L111`）：

.. code-block:: cpp

   bool SpikeCosim::mmio_load(reg_t addr, size_t len, uint8_t *bytes) {
     // Reject oversized accesses (e.g. from mem_t initialization) without DUT checking
     if (len > 8) {
       return bus.load(addr, len, bytes);
     }

     bool bus_error = !bus.load(addr, len, bytes);

     int tid = active_thread;
     auto *proc = get_processor(tid);
     auto &ts = thread_state[tid];

     // Incoming access may be an iside or dside access. Use PC to help determine
     // which. PC is 64 bits in spike, we only care about the bottom 32-bit so mask
     // off the top bits.

逐段解释：

* 第 73-L77 行：长度大于 8 的访问只走 `bus.load()`，不做 DUT 比对。
* 第 79-L83 行：普通访问先从 Spike bus 读数据，再通过 `active_thread` 找对应 hart 状态。
* 第 85-L99 行：函数用 Spike 当前 PC 判断访问是否可能是 iside fetch。取指可能从 PC 开始访问最多 8 byte。
* 第 101-L107 行：如果访问不在 iside 范围，则调用 `check_mem_access()` 做 D-side load 比对，但返回值被显式丢弃，注释说明 load check failures 是诊断性信息，Spike 已经从自身 memory 读到数据。
* 第 110 行：返回 `!bus_error`，决定 Spike 是否看到 bus error。

关键代码（`dv/cosim/spike_cosim.cc:L113-L138`）：

.. code-block:: cpp

   bool SpikeCosim::mmio_store(reg_t addr, size_t len, const uint8_t *bytes) {
     // Reject oversized accesses (e.g. from mem_t initialization) without DUT checking
     if (len > 8) {
       return bus.store(addr, len, bytes);
     }

     bool bus_error = !bus.store(addr, len, bytes);

     int tid = active_thread;

     // EH2 store-buffer coalescing / RMW semantics: store comparison failures
     // must NOT cause Spike to trap.  Reasons:
     //   1. Coalesced stores: sb+sw to the same word are merged; the AXI data

逐段解释：

* 第 113-L119 行：store 也先写 Spike bus，并记录 bus error。
* 第 121-L135 行：源码注释明确说明 store 比对失败不能让 Spike trap，原因包括 EH2 store coalescing、避免级联失步、PC 和 rd=x0 仍由 `step()` 验证。
* 第 135-L137 行：调用 `check_mem_access()` 后丢弃返回值，并返回 `!bus_error`。

接口关系：

* 被调用：Spike MMU 在执行 load/store 指令时调用。
* 调用：`bus.load()`、`bus.store()`、`check_mem_access()`。
* 共享状态：读取 `active_thread`，消费或检查 per-hart pending D-side 队列。

§9.2  `notify_dside_access()` 和 widened load pair
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：SV 侧 AXI monitor 先调用 `notify_dside_access()` 把 DUT 访问入队；Spike 后续访存时由 `check_mem_access()` 匹配该队列。widened load pair 用于识别一个 64-bit read beat 拆成两个 32-bit entry 的场景。

关键代码（`dv/cosim/spike_cosim.cc:L863-L892`）：

.. code-block:: cpp

   void SpikeCosim::notify_dside_access(const DSideAccessInfo &access_info,
                                        int thread_id) {
     assert((access_info.addr & 0x3) == 0);
     assert(thread_id >= 0 && thread_id < num_threads);

     PendingMemAccess pending_access;
     pending_access.dut_access_info = access_info;
     pending_access.be_spike = 0;
     thread_state[thread_id].pending_dside_accesses.push_back(pending_access);
   }

   bool SpikeCosim::is_widened_load_pair(int thread_id,
                                         size_t first_idx) const {
     auto &pending = thread_state[thread_id].pending_dside_accesses;

逐段解释：

* 第 863-L867 行：地址必须 32-bit 对齐，`thread_id` 必须有效。
* 第 868-L871 行：函数复制 `DSideAccessInfo`，把 `be_spike` 初始化为 0，再 push 到当前 hart 队列尾部。
* 第 874-L880 行：`is_widened_load_pair()` 先确认队列里至少有两个 entry。
* 第 882-L891 行：只有两个 entry 都是 load、都标记 `widened_load`、都不是 misaligned、BE 都是 `0xf`、第二个地址等于第一个地址加 4、错误标志相同，才返回 true。

接口关系：

* 被调用：DPI shim 的 `riscv_cosim_notify_dside_access()` 调用 `notify_dside_access()`；`check_mem_access()` 调用 `is_widened_load_pair()`。
* 调用：无外部库，只操作 per-hart vector。
* 共享状态：写入和读取 `pending_dside_accesses`。

§9.3  `check_mem_access()` 的地址、类型和 BE 比对
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：`check_mem_access()` 是 Spike 内存访问与 DUT AXI 通知的主要比对点。它检查 pending 队列、地址、load/store 类型、byte enable、数据和错误语义。

关键代码（`dv/cosim/spike_cosim.cc:L1345-L1382`）：

.. code-block:: cpp

   SpikeCosim::check_mem_result_e SpikeCosim::check_mem_access(
       int thread_id, bool store, uint32_t addr, size_t len,
       const uint8_t *bytes) {
     assert(len >= 1 && len <= 4);
     // Expect that no spike memory accesses cross a 32-bit boundary
     assert(((addr + (len - 1)) & 0xfffffffc) == (addr & 0xfffffffc));

     auto &pending_dside_accesses = thread_state[thread_id].pending_dside_accesses;
     std::string iss_action = store ? "store" : "load";

     // Check if there are any pending DUT accesses to check against
     if (pending_dside_accesses.size() == 0) {
       // EH2 can satisfy a load internally without an external AXI transaction,

逐段解释：

* 第 1345-L1350 行：Spike 单次比较只接受 1-4 byte，并断言不跨 32-bit word 边界。
* 第 1352-L1357 行：取得当前 hart pending 队列，并构造日志中的 ISS action 字符串。
* 第 1356-L1372 行：如果没有 pending entry 且是 load，返回 `kCheckMemOk`。源码注释给出的理由是 EH2 可能通过 store-buffer forwarding 满足 load，最终 GPR 写回仍由 `step()` 检查。
* 第 1374-L1381 行：如果没有 pending entry 且是 store，也返回 `kCheckMemOk`，源码注释把它归因于 EH2 store coalescing。

关键代码（`dv/cosim/spike_cosim.cc:L1384-L1424`）：

.. code-block:: cpp

     size_t pending_access_idx = 0;
     if (!store && is_widened_load_pair(thread_id, 0)) {
       for (size_t idx = 0; idx < 2; ++idx) {
         const auto &candidate_info = pending_dside_accesses[idx].dut_access_info;
         if ((addr & 0xfffffffc) == candidate_info.addr) {
           pending_access_idx = idx;
           break;
         }
       }
     }

     auto &top_pending_access = pending_dside_accesses[pending_access_idx];
     auto &top_pending_access_info = top_pending_access.dut_access_info;

     std::string dut_action = top_pending_access_info.store ? "store" : "load";

逐段解释：

* 第 1384-L1393 行：widened load pair 情况下，不固定消费队列第一个 entry，而是在前两个 entry 中找和 Spike aligned address 匹配的那个。
* 第 1395-L1398 行：取出待比对 entry 和 DUT action 字符串。
* 第 1400-L1410 行：aligned address 必须等于 DUT pending entry 的地址，否则记录 address mismatch。
* 第 1412-L1420 行：load/store 类型必须一致，否则记录 type mismatch。
* 第 1422-L1423 行：`expected_be` 根据 Spike 访问长度和地址低 2 位计算。

§9.4  widened store/load 与数据比对
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：非 misaligned 访问允许 EH2 的 AXI BE 是 ISA-expected BE 的超集；store 和 load 都按相同方式检查 expected BE 是否被 DUT BE 完整覆盖。

关键代码（`dv/cosim/spike_cosim.cc:L1458-L1489`）：

.. code-block:: cpp

     } else {
       // Ibex's memory interface reports byte enables at architectural access
       // width. EH2 widens both loads AND stores at the AXI4 boundary: byte/half
       // accesses are reported as a full aligned word with WSTRB covering 4 bytes
       // (the LSU performs a read-modify-write internally). For cosim, accept any
       // BE that is a superset of the ISA-expected BE — the architectural data
       // bytes still match, the extra bytes are "non-modifying writebacks" of
       // existing memory contents.
       if (store && ((expected_be & ~top_pending_access_info.be) != 0)) {
         std::stringstream err_str;
         err_str << "T" << thread_id << " DUT generated " << dut_action
                 << " at address " << std::hex << top_pending_access_info.addr
                 << " with BE " << top_pending_access_info.be

逐段解释：

* 第 1458-L1465 行：源码注释明确说 EH2 在 AXI4 边界会 widen loads 和 stores；byte/half 访问可能以 full aligned word 形式出现。
* 第 1466-L1475 行：store 情况下，`expected_be` 的每一位都必须被 DUT `be` 覆盖，否则报错。
* 第 1477-L1486 行：load 情况下也使用相同的覆盖检查。
* 第 1488 行：非 misaligned 且 BE 覆盖通过后，pending entry 可完成。

关键代码（`dv/cosim/spike_cosim.cc:L1491-L1513`）：

.. code-block:: cpp

     // Check data
     if (store || !top_pending_access_info.error) {
       uint32_t expected_data = 0;
       for (size_t i = 0; i < len; ++i) {
         expected_data |= bytes[i] << (i * 8);
       }
       expected_data <<= (addr & 0x3) * 8;

       uint32_t expected_be_bits = (((uint64_t)1 << (len * 8)) - 1)
                                   << ((addr & 0x3) * 8);
       uint32_t masked_dut_data = top_pending_access_info.data & expected_be_bits;

       if (expected_data != masked_dut_data) {

逐段解释：

* 第 1492 行：store 总是检查数据；load 只有在 DUT pending entry 没有 error 时检查数据。
* 第 1493-L1497 行：从 Spike bytes 重组小端 `expected_data`，再按地址低 2 位移到 32-bit word 对应 byte lane。
* 第 1499-L1501 行：构造 data mask，只比较 ISA 访问覆盖的 byte lane。
* 第 1503-L1511 行：数据不一致时记录包含 DUT/expected 数据和 byte mask 的错误。

接口关系：

* 被调用：`mmio_load()` 和 `mmio_store()`。
* 调用：`is_widened_load_pair()`。
* 共享状态：可能 erase `pending_dside_accesses`，可能写 `errors`。

§9.5  PMP misaligned fixup
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：当 PMP/ePMP 与 misaligned 访问组合产生 access fault 时，`misaligned_pmp_fixup()` 清理 faulting half 对应的 pending D-side entry，避免 Spike 后续继续匹配已经 fault 的访问。

关键代码（`dv/cosim/spike_cosim.cc:L927-L974`）：

.. code-block:: cpp

   void SpikeCosim::misaligned_pmp_fixup(int thread_id, uint32_t addr,
                                         bool store) {
     auto &ts = thread_state[thread_id];
     auto *proc = get_processor(thread_id);
     if (!proc || !proc->get_state()) return;

     // Check if any PMP regions are configured
     uint32_t pmpcfg0 = proc->get_csr(CSR_PMPCFG0);
     bool any_pmp_enabled = false;
     for (int r = 0; r < 8 && r < proc->n_pmp; r++) {
       if ((pmpcfg0 >> (r * 8)) & 0x1) {  // PMP region r is enabled (L bit)
         any_pmp_enabled = true;
         break;
       }

逐段解释：

* 第 927-L931 行：函数取 per-hart 状态和 processor；processor 或 state 不存在时直接返回。
* 第 933-L941 行：读取 `PMPCFG0`，检查前 8 个 region 的 L bit。
* 第 942-L949 行：读取 `PMPCFG1`，检查 region 8-15；没有任何 PMP region enabled 时返回。
* 第 951-L955 行：取 pending 队列；为空时返回。
* 第 957-L973 行：遍历 pending entry，删除 `error` 标志为真的 entry；misaligned 但无 error 的 half 保留。

接口关系：

* 被调用：`check_sync_trap()` 在 Spike `mcause` 为 0x5 或 0x7 时调用。
* 调用：Spike PMP CSR getter、pending vector erase。
* 共享状态：修改 `thread_state[thread_id].pending_dside_accesses`。

§9.6  Atomic helper 与 `atomic_store_fixup()`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：原子 helper 通过 backdoor 读取当前 PC 指令编码识别 RV32A、SC.W 和 LR.W；`atomic_store_fixup()` 维护 LR reservation，并在 SC/AMO store half 后对齐状态。

关键代码（`dv/cosim/spike_cosim.cc:L997-L1023`）：

.. code-block:: cpp

   bool SpikeCosim::pc_is_atomic_mem_instr(int thread_id, uint32_t pc) {
     uint32_t instr = 0;
     if (thread_id < 0 || thread_id >= num_threads) return false;
     if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&instr))) return false;
     // RV32A opcode: 0101111 (AMO), funct3 determines type
     return ((instr & 0x7f) == 0x2f) && (((instr >> 12) & 0x7) == 2);
   }

   bool SpikeCosim::is_sc_instr(int thread_id, uint32_t pc) {
     uint32_t instr = 0;
     if (thread_id < 0 || thread_id >= num_threads) return false;
     if (!backdoor_read_mem(pc, 4, reinterpret_cast<uint8_t *>(&instr))) return false;
     // SC.W: opcode=0101111 funct3=010 funct5=00011

逐段解释：

* 第 997-L1003 行：RV32A memory 指令识别条件是 opcode `0x2f` 且 `funct3 == 2`。
* 第 1005-L1013 行：SC.W 进一步要求 `funct5 == 0x03`。
* 第 1015-L1023 行：LR.W 进一步要求 `funct5 == 0x02`。

关键代码（`dv/cosim/spike_cosim.cc:L1025-L1068`）：

.. code-block:: cpp

   void SpikeCosim::atomic_store_fixup(int thread_id, bool store,
                                        uint32_t addr, uint32_t rd_data,
                                        bool is_sc) {
     auto &ts = thread_state[thread_id];
     auto *proc = get_processor(thread_id);
     if (!proc || !proc->get_state()) return;

     if (!store) {
       // LR.W (load): track reservation address
       if (is_lr_instr(thread_id, ts.last_step_pc)) {
         ts.lr_reservation_addr = addr;
         ts.lr_reservation_valid = true;
       }
       return;

逐段解释：

* 第 1028-L1030 行：函数需要 per-hart 状态和 processor；缺少 processor state 时返回。
* 第 1032-L1039 行：非 store 路径只处理 LR.W，记录 reservation 地址并置 valid。
* 第 1041-L1063 行：SC.W store path 清理 reservation valid。源码注释说明 DUT 的 SC 成功/失败结果由 `check_gpr_write()` 接受并同步 GPR。
* 第 1065-L1067 行：AMO store half 的数据比较仍由 `check_mem_access()` 默认路径处理，BE 超集容忍和 store coalescing 已覆盖。

接口关系：

* 被调用：源码定义了 `atomic_store_fixup()` 和 helper；`step()` 中使用 `pc_is_atomic_mem_instr()` 做 TLB flush，`check_gpr_write()` 使用 `is_sc_instr()`。
* 调用：`backdoor_read_mem()`、`is_lr_instr()`、Spike processor state。
* 共享状态：写 LR reservation 字段；SC.W mismatch 时的 GPR 对齐由 `check_gpr_write()` 完成。

§10  SV 调用关系与编译链接
--------------------------------------------------------------------------------

§10.1  Scoreboard 调用通知与 step 的顺序
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：C++ 层的 step 语义依赖 SV 侧先通知状态、再调用 `riscv_cosim_step()`。该顺序在 `eh2_cosim_scoreboard.sv` 中固定。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L642-L656`）：

.. code-block:: verilog

       // Spike notification ordering (Ibex pattern)
       riscv_cosim_set_debug_req(cosim_handle, int'(item.debug_req), tid);
       riscv_cosim_set_nmi(cosim_handle, int'(item.nmi), tid);
       riscv_cosim_set_nmi_int(cosim_handle, int'(item.nmi_int), tid);
       riscv_cosim_set_mip(cosim_handle, int'(prev_mip[tid]), int'(item.mip), tid);
       prev_mip[tid] = item.mip;
       riscv_cosim_set_mcycle(cosim_handle, longint'(item.mcycle), tid);
       if (item.exception && !item.interrupt && item.ecause == 5'd1) begin
         riscv_cosim_set_iside_error(cosim_handle, int'(item.pc), tid);
       end

       result = riscv_cosim_step(cosim_handle,
         int'(write_reg), int'(write_reg_data),
         int'(item.pc), sync_trap ? 1 : 0,

逐段解释：

* 第 642-L648 行：SV 先同步 debug request、NMI、NMI internal、MIP pre/post 和 mcycle。这个顺序决定 C++ step 前 Spike 已经拥有本条 item 的外部状态。
* 第 649-L651 行：只有同步异常且 `ecause == 5'd1` 时，SV 设置 iside error。
* 第 653-L656 行：最后调用 `riscv_cosim_step()`，传入 GPR 写回、PC、同步 trap 标志、抑制写回标志和 `tid`。

接口关系：

* 被调用：`compare_instruction()` 从 trace FIFO 消费 item 后执行。
* 调用：所有 step 前通知函数和 `riscv_cosim_step()`。
* 共享状态：`prev_mip[tid]` 在 SV 侧维护，用于生成 `pre_mip`。

§10.2  D-side AXI 通知调用关系
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：SV AXI monitor 看到 LSU 事务后，Scoreboard 将 64-bit AXI beat 拆成最多两个 32-bit DPI 通知，C++ pending 队列再与 Spike MMIO 回调匹配。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L506-L531`）：

.. code-block:: verilog

     // Notify Spike about a memory access from the AXI4 bus.
     // AXI4 bus is 64-bit; split 64-bit beats into two 32-bit notifications.
     function void notify_memory_access(int tid, axi4_seq_item txn);
       if (txn.tx_type == axi4_seq_item::AXI4_WRITE) begin
         bit write_error = (txn.resp[0] != axi4_seq_item::AXI4_RESP_OKAY);

         for (int i = 0; i < txn.get_beat_count(); i++) begin
           bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
           bit [63:0] beat_data = txn.data[i];
           bit [7:0]  beat_strb = txn.strb[i];
           int beat_bytes = (1 << txn.size);

           if (beat_strb[3:0] != 4'b0) begin
             riscv_cosim_notify_dside_access(cosim_handle,

逐段解释：

* 第 506-L508 行：函数注释说明 AXI4 bus 是 64-bit，通知给 Spike 时拆成 32-bit。
* 第 509-L522 行：write path 对低 32-bit lane 的非零 strobe 调用一次 `riscv_cosim_notify_dside_access()`。
* 第 527-L531 行：如果 beat 超过 4 byte 且高 32-bit lane 有 strobe，再对 `beat_addr + 4` 调用第二次通知。

关键代码（`dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv:L537-L559`）：

.. code-block:: verilog

       for (int i = 0; i < txn.get_beat_count(); i++) begin
         bit [31:0] beat_addr = txn.addr + (i * (1 << txn.size));
         bit [63:0] beat_data = txn.rdata[i];
         bit read_error = (txn.resp[i] != axi4_seq_item::AXI4_RESP_OKAY);
         int beat_bytes = (1 << txn.size);
         bit widened_load = (beat_bytes > 4);
         bit [3:0] read_be = ((4'b0001 << beat_bytes) - 1) << beat_addr[1:0];

         riscv_cosim_notify_dside_access(cosim_handle,
           0, int'(beat_data[31:0]), int'(beat_addr),
           int'(read_be), int'(read_error),
           0, 0, 0, 1, int'(widened_load), tid);

逐段解释：

* 第 537-L543 行：read path 计算 beat 地址、数据、错误标志、beat byte 数、`widened_load` 和低 lane read BE。
* 第 545-L548 行：低 32-bit lane 总是发一个 load 通知。
* 第 552-L556 行：当 beat 超过 4 byte 时，高 32-bit lane 用 `addr + 4` 和 `be=4'hf` 发第二个 load 通知，并保留 `widened_load` 标志。

接口关系：

* 被调用：Scoreboard Dmem 路径在获得 AXI item 后调用。
* 调用：`riscv_cosim_notify_dside_access()`。
* 共享状态：C++ per-hart pending D-side 队列必须先于 Spike 对应访存或在可容忍时被跳过。

§10.3  `libcosim.so` 构建与 VCS 链接
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

职责：顶层 Makefile 把 `spike_cosim.cc` 和 `cosim_dpi.cc` 编译成 `build/libcosim.so`，并把该库作为 `compile_vcs` 的显式依赖和链接输入。

关键代码（`Makefile:L236-L244`）：

.. code-block:: makefile

   LIBCOSIM := $(BUILD_DIR)/libcosim.so

   ifeq ($(NO_COSIM),1)
   COMPILE_LIBCOSIM_DEP :=
   COMPILE_LIBCOSIM_LINK :=
   else
   COMPILE_LIBCOSIM_DEP := $(LIBCOSIM)
   COMPILE_LIBCOSIM_LINK := $(CURDIR)/$(LIBCOSIM)
   endif

逐段解释：

* 第 236 行：`LIBCOSIM` 固定为 `$(BUILD_DIR)/libcosim.so`。
* 第 238-L244 行：`NO_COSIM=1` 时不把 `libcosim.so` 放进 compile 依赖和链接输入；否则 `compile_vcs` 依赖并链接该 shared library。

关键代码（`Makefile:L246-L265`）：

.. code-block:: makefile

   compile_vcs: $(COMPILE_LIBCOSIM_DEP) | $(BUILD_DIR)
           @echo "=== Compiling with VCS ==="
           $(VCS) -full64 -assert svaext -sverilog \
             -ntb_opts uvm-1.2 \
             +error+500 \
             +define+GTLSIM \
             $(DEFINES) \
             +incdir+$(SNAPSHOTS) \
             +incdir+$(TB_DIR)/common/axi4_agent \
             +incdir+$(TB_DIR)/common/trace_agent \
             +incdir+$(TB_DIR)/common/irq_agent \
             +incdir+$(TB_DIR)/common/jtag_agent \
             +incdir+$(TB_DIR)/common/cosim_agent \
             +incdir+$(COSIM_DIR) \
             -f $(RTL_F) \
             -f $(SHARED_F) \
             -f $(TB_F) \
             -top core_eh2_tb_top \
             $(COMPILE_LIBCOSIM_LINK) \

逐段解释：

* 第 246 行：`compile_vcs` 的正常路径依赖 `$(LIBCOSIM)`。
* 第 253-L259 行：VCS include path 包含 TB common agents 和 `$(COSIM_DIR)`，使 `cosim_dpi.svh` 可被 SystemVerilog package include。
* 第 260-L264 行：RTL、shared RTL、TB filelist 和顶层 testbench 一起编译；`$(COMPILE_LIBCOSIM_LINK)` 被直接放在链接行。

关键代码（`Makefile:L288-L318`）：

.. code-block:: makefile

   $(LIBCOSIM): $(COSIM_DIR)/spike_cosim.cc $(COSIM_DIR)/cosim_dpi.cc \
                $(COSIM_DIR)/spike_cosim.h $(COSIM_DIR)/cosim.h | $(BUILD_DIR)
           @if [ ! -d "$(SPIKE_INSTALL)" ]; then \
             echo "ERROR: SPIKE_INSTALL=$(SPIKE_INSTALL) does not exist."; \
             echo "       Build spike-cosim first, set SPIKE_DIR=<path>, or pass"; \
             echo "       NO_COSIM=1 to skip cosim linkage."; \
             exit 1; \
           fi
           @echo "=== Building co-simulation library (Spike) ==="
           @mkdir -p $(SPIKE_BUILD)
           @# Extract Spike library objects into a single directory
           @cd $(SPIKE_BUILD) && \
             ar x $(SPIKE_INSTALL)/lib/libriscv.a && \

逐段解释：

* 第 288-L289 行：`libcosim.so` 的显式源码依赖是 `spike_cosim.cc`、`cosim_dpi.cc`、`spike_cosim.h` 和 `cosim.h`。
* 第 290-L295 行：缺少 `SPIKE_INSTALL` 时直接报错，并提示可以构建 spike-cosim、设置 `SPIKE_DIR`，或用 `NO_COSIM=1` 跳过 linkage。
* 第 299-L305 行：把 Spike 静态库对象抽取到 `$(SPIKE_BUILD)`，再打包成 `libspike_all.a`。
* 第 307-L318 行：用 `$(SPIKE_CXX)` 生成 shared library，include `$(COSIM_DIR)`、Spike include、softfloat include 和 VCS include，并链接 `libspike_all`、softfloat、pthread 和 dl。

接口关系：

* 被调用：`make cosim` 或 `make compile_vcs` 间接构建。
* 调用：系统 `ar`、`g++`、Spike 静态库和 VCS DPI include。
* 共享状态：输出 `build/libcosim.so`，不属于源码文档修改范围。

§11  参考资料
--------------------------------------------------------------------------------

关联 ADR：

* :ref:`adr-0001` — Cosim via trace and probe。
* :ref:`adr-0005` — Spike cosim store wider WSTRB。
* :ref:`adr-0006` — Atomic cosim fixup。
* :ref:`adr-0007` — Interrupt cosim closure。
* :ref:`adr-0008` — Debug cosim closure。
* :ref:`adr-0009` — PMP/ePMP cosim closure。
* :ref:`adr-0016` — Multi-hart cosim。

关联章节：

* :ref:`cosim_scoreboard` — SV Scoreboard、trace/probe/AXI 三路输入和 Spike 通知顺序。
* :doc:`../06_flows/scripts_reference` — CLI 与脚本层对 cosim 使能、禁用和 sign-off 检查的说明。
* :doc:`../appendix_f_scripts/makefiles` — `Makefile` 中 `libcosim.so` 与 `compile_vcs` 的构建关系。

源文件绝对路径：

* :file:`/home/host/eh2-veri/dv/cosim/cosim.h`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.cc`
* :file:`/home/host/eh2-veri/dv/cosim/cosim_dpi.svh`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.cc`
* :file:`/home/host/eh2-veri/dv/cosim/spike_cosim.h`
* :file:`/home/host/eh2-veri/dv/uvm/core_eh2/common/cosim_agent/eh2_cosim_scoreboard.sv`
* :file:`/home/host/eh2-veri/Makefile`

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

§12  v2-27 cosim C++/DPI 全文行段级精读
--------------------------------------------------------------------------------

本节用于 v2-27 行级门禁：把 ``dv/cosim`` 目录中 5 个 C++/DPI 源文件全部
纳入 ``literalinclude``，并按源码顺序解释每一段承担的职责。前面 §2-§10 已经
围绕关键函数讲过调用关系，本节更像源码旁注：读者可以从文件第一行一路读到
最后一行，知道每个结构、包装函数和 fixup 分支为什么存在。

§12.1  ``cosim_dpi.svh``：SystemVerilog 可见的 DPI 合约
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完整源码（``dv/cosim/cosim_dpi.svh``）：

.. literalinclude:: ../../../../dv/cosim/cosim_dpi.svh
   :language: text
   :linenos:
   :caption: dv/cosim/cosim_dpi.svh

源码精读：

* 第 1-L7 行是文件身份和约束说明：这是 SystemVerilog DPI-C import 声明层，
  所有 per-hart API 都显式带 ``thread_id``。这避免双线程 EH2 平台在 C++ 侧
  只能靠全局状态猜当前 hart。
* 第 8-L23 行定义生命周期和内存映射入口。``riscv_cosim_init`` 返回
  ``chandle``，SV 侧不理解 C++ 类型，只保存一个不透明句柄；
  ``destroy`` 负责释放实例，``add_memory`` 负责把 testbench 加载出来的内存
  区间告诉 Spike 侧 bus。
* 第 25-L35 行是每条 retired instruction 的主入口。Scoreboard 把 DUT 写回寄存器、
  写回数据、退休 PC、同步 trap 标志、被 kill 的写回标志和 hart 编号传给
  C++，C++ 再让 Spike 走一步并做 PC、GPR、trap 状态比对。
* 第 37-L79 行是状态同步 API。``set_mip`` 区分 pre/post MIP，供 C++ 判断
  这条指令入口是否应该取中断；``set_nmi``、``set_nmi_int``、``set_debug_req``
  和 ``set_mcycle`` 把 DUT 的异步状态、debug 请求和计数器采样顺序传给 Spike；
  ``set_csr`` 用于直接把 DUT 观察到的 CSR 值灌入参考模型。
* 第 81-L95 行是 D-side 访问通知。SV 侧把 AXI 监控得到的 store/load、数据、
  word 对齐地址、byte enable、错误、misaligned 两半、M-mode 访问和 widened
  load 标志全部传入 C++。这些字段会被打包成 ``DSideAccessInfo`` 并进入 per-hart
  pending 队列。
* 第 97-L109 行处理取指侧错误和二进制加载。``set_iside_error`` 告诉 C++ 下一次
  Spike 取到对应 aligned PC 时应产生取指错误；``write_mem_byte`` 是最小粒度的
  backdoor 写入口，常用于把程序镜像逐字节装入 Spike 内存。
* 第 111-L130 行是错误通道。SV 侧先读错误数量和字符串，再调用 ``clear_errors``
  清空本次 step 的诊断，避免旧 mismatch 污染下一条指令。
* 第 132-L152 行是统计和 trap CSR 查询。``get_insn_cnt`` 给 scoreboard 或报告层
  读取已匹配指令数；``get_mcause``、``get_mepc``、``get_mtvec`` 用于 RISK-9
  这类 trap CSR 对齐检查。

§12.2  ``cosim.h``：SV/C++ 之间的抽象接口
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完整源码（``dv/cosim/cosim.h``）：

.. literalinclude:: ../../../../dv/cosim/cosim.h
   :language: cpp
   :linenos:
   :caption: dv/cosim/cosim.h

源码精读：

* 第 1-L12 行说明接口定位。EH2 没有像 Ibex 那样直接拿 RVFI 的完整每指令视图，
  而是把 trace、DUT probe 和 AXI monitor 的观测拼成比较输入，所以这个抽象层
  必须同时覆盖 PC/写回、CSR、取指错误和 D-side 访存。
* 第 13-L19 行是 include guard 和标准库依赖。``cstdint`` 固定跨 DPI 的位宽，
  ``string``、``vector`` 用于错误消息集合，避免把 C++ 容器细节暴露给 SV。
* 第 20-L32 行定义 ``DSideAccessInfo``。``store``、``data``、``addr`` 和 ``be``
  描述 AXI word 级访问；``error``、``misaligned_first``、``misaligned_second``
  和 ``misaligned_first_saw_error`` 描述异常/拆分访存；``m_mode_access`` 与
  ``widened_load`` 保留 EH2 特有的权限和总线扩宽语义。
* 第 34-L47 行是 ``Cosim`` 生命周期和 backdoor memory 接口。C++ 实现类可以是
  Spike，也可以将来换成其他 ISS；SV 侧只通过 ``chandle`` 间接调用这些虚函数。
* 第 49-L61 行是核心 ``step`` 合约。``write_reg=0`` 表示无 GPR 写回，``pc`` 是 DUT
  retire PC，``sync_trap`` 区分正常退休和同步异常，``suppress_reg_write`` 表示
  DUT 取消了原本 Spike 会看到的 load/div 写回。
* 第 63-L90 行定义运行时状态同步合约。中断、NMI、debug、``mcycle``、CSR、D-side
  和 I-side error 都在 ``step`` 前后按 scoreboard 既定顺序调用，因此 Spike 状态
  可以跟 DUT 的异步边界对齐。
* 第 92-L105 行是只读结果接口。错误列表给 SV 侧打印 UVM 报告；``clear_errors``
  划分 step 边界；``get_insn_cnt`` 和 3 个 trap CSR getter 给统计与 trap 对比复用。
* 第 107 行关闭 include guard。这个文件没有任何 Spike 头依赖，是刻意保留的窄接口，
  这样 ``cosim_dpi.cc`` 可以只面向 ``Cosim`` 编译，而不需要知道 ``SpikeCosim``
  的内部数据结构。

§12.3  ``cosim_dpi.cc``：DPI C shim 和类型转换层
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完整源码（``dv/cosim/cosim_dpi.cc``）：

.. literalinclude:: ../../../../dv/cosim/cosim_dpi.cc
   :language: cpp
   :linenos:
   :caption: dv/cosim/cosim_dpi.cc

源码精读：

* 第 1-L14 行把 C++ 实现包进 ``extern "C"``。DPI import 需要 C ABI 名字，
  不能暴露 C++ name mangling；``svdpi.h`` 提供 ``svOpenArrayHandle`` 访问函数，
  ``stdexcept`` 用于 step 异常保护。
* 第 16-L29 行实现销毁和内存区添加。每个函数先把 ``void*`` 转回 ``Cosim*``，
  再检查空指针；``base_addr`` 和 ``size`` 显式转成 C++ 侧无符号地址与长度。
* 第 31-L60 行实现 open array backdoor read/write。SV 动态数组不能直接当作 C
  指针使用，必须通过 ``svGetArrayPtr`` 拿到底层连续存储；拿不到指针时直接返回
  失败，避免 C++ 侧解引用无效内存。
* 第 62-L92 行包装 ``step``。这里把 SV 的 ``int`` 参数转成 C++ 的 ``uint32_t`` 和
  ``bool``，并捕获 ``std::exception`` 与未知异常。任何异常都转成 mismatch 返回，
  同时打印 PC 和 thread，防止 VCS 因 C++ 异常穿过 DPI 边界而崩溃。
* 第 94-L137 行是中断、NMI、debug、``mcycle`` 和 CSR 的薄包装。每个函数只做空句柄
  检查与类型转换，真正语义都在 ``Cosim`` 实现里。这种分层让 DPI 层保持机械、可审计。
* 第 139-L163 行把 12 个 SV 标量参数组装为 ``DSideAccessInfo``。这一步是 D-side
  比对的关键边界：SV 看到的是 AXI/scoreboard 字段，C++ 看到的是一个结构化 pending
  access，后续 ``check_mem_access`` 只消费这个结构。
* 第 165-L178 行处理取指错误和逐字节写内存。``write_mem_byte`` 把 ``data & 0xFF``
  截断为 ``uint8_t``，保证 SV 传入的 ``int`` 不会把高位误写进 Spike 内存。
* 第 180-L225 行是错误读取、结果查询和清错。这里把 C++ vector size 映射为 SV ``int``，
  把字符串返回为 ``const char*``，并在越界或异常时返回空字符串/失败码。
* 第 227-L255 行暴露指令计数和 trap CSR getter。getter 不捕获异常，依赖上层在合法
  handle 和合法 thread 下调用；返回类型为 32-bit，正好匹配 EH2 RV32 CSR 宽度。
* 第 257 行关闭 ``extern "C"``。本文件没有定义 ``riscv_cosim_init``，因为 factory
  位于 ``spike_cosim.cc``，那里才知道该构造哪个具体 ``Cosim`` 实现。

§12.4  ``spike_cosim.h``：Spike 适配器的状态模型
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完整源码（``dv/cosim/spike_cosim.h``）：

.. literalinclude:: ../../../../dv/cosim/spike_cosim.h
   :language: cpp
   :linenos:
   :caption: dv/cosim/spike_cosim.h

源码精读：

* 第 1-L23 行声明文件身份、include guard、标准库依赖和 Spike 头文件。这里首次引入
  ``processor_t``、``bus_t``、``mem_t``、``simif_t`` 等 Spike 类型，因此它属于具体
  实现层，而不是通用 DPI 合约层。
* 第 24-L28 行定义 EH2 ``marchid`` 和最大线程数。``0x56524545`` 对应 ``VEER``，
  ``COSIM_MAX_THREADS=2`` 与 EH2 双硬件线程配置对齐。
* 第 30-L44 行声明 ``SpikeCosim`` 的双重继承：它既是 Spike 需要的 ``simif_t``，
  负责处理 MMIO/load/store 回调；也是 SV 侧需要的 ``Cosim``，负责 step 和状态同步。
* 第 45-L72 行列出对 ``Cosim`` 的全部实现。这里与 ``cosim.h`` 一一对应，读者可以
  用这段确认 SV import、DPI shim、抽象接口和 Spike 实现没有漏接。
* 第 74-L91 行是全局共享状态：线程数、ISA parser、每个 hart 的 Spike processor、
  可选 commit log、当前 MMIO 回调对应的 ``active_thread``、共享 memory bus 以及
  错误列表。
* 第 93-L99 行定义 ``PendingMemAccess``。它保存 DUT 侧 D-side 访问、Spike 已经看过
  的 byte enable，以及 atomic store 标志；这是把 AXI monitor 时序和 Spike MMIO
  时序解耦的缓冲节点。
* 第 100-L125 行定义 per-hart 状态。NMI mode、pending I-side error、指令计数、
  NMI ``mstack``、pending D-side 队列、LR/SC reservation 和上一条 step PC 都按 hart
  分开，避免双线程运行时状态串扰。
* 第 127-L131 行是 ``get_processor`` 辅助函数。它用断言保护 thread 范围，并返回
  对应 ``processor_t``，后续所有 helper 都从这里取得 Spike hart。
* 第 133-L165 行是内部 helper 清单。初始化、CSR fixup、PMP misaligned 修正、atomic
  修正、指令分类、retire 比对、GPR 写回比对、suppress 写回、CSR 写回、NMI 退出、
  中断/debug 处理和 widened load pair 判断都在这里列清楚。
* 第 167-L174 行定义 D-side 比对结果枚举和 ``check_mem_access``。返回值区分普通通过、
  比对失败和 bus error，调用方可以决定是记录错误、让 Spike trap，还是把错误作为
  DUT 已知异常消费掉。

§12.5  ``spike_cosim.cc``：Spike 驱动、比对和 EH2 语义修正
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完整源码（``dv/cosim/spike_cosim.cc``）：

.. literalinclude:: ../../../../dv/cosim/spike_cosim.cc
   :language: cpp
   :linenos:
   :caption: dv/cosim/spike_cosim.cc

源码精读：

* 第 1-L23 行引入实现依赖。除了本地头文件，还需要 Spike 的 config、CSR、decode、
  device、MMU、processor 和 simif API；这说明本文件直接站在 ISS 内部接口上工作。
* 第 24-L54 行是构造函数。它创建可选 trace log、解析 ISA 字符串，为每个 hart 创建
  ``processor_t``，配置 PMP region、MHPM counter、PMP granularity，再调用
  ``initial_proc_setup`` 填入 EH2 特有 CSR 和初始 PC/mtvec。
* 第 56-L71 行实现 ``addr_to_mem``。普通访存保持走 MMIO 回调，方便和 DUT D-side
  通知比较；只有 atomic memory instruction 需要 host-backed memory 时才返回
  ``mem_t`` 指针，绕开 Spike 对纯 MMIO LR/SC 的限制。
* 第 73-L111 行实现 ``mmio_load``。它先让 Spike bus 读数据，再用当前 PC 区分取指
  范围和 D-side 访问；若命中 pending I-side error，就把这次 load 变成 bus error；
  若不是取指范围，则调用 ``check_mem_access`` 做 D-side load 诊断。
* 第 113-L138 行实现 ``mmio_store``。store 先写入 Spike bus，让参考模型内存保持
  ISA 结果；随后调用 ``check_mem_access`` 记录诊断，但不让 store 比对失败直接让
  Spike trap，避免 EH2 store buffer 合并造成后续指令级联失配。
* 第 140-L158 行是 simif 的剩余基础接口与 backdoor memory。``proc_reset`` 和
  ``get_symbol`` 在当前集成中为空实现；``add_memory`` 创建 ``mem_t`` 并挂到 bus；
  backdoor read/write 直接调用 bus。
* 第 160-L272 行是指令分类 helper。``pc_is_mret``、``pc_is_debug_ebreak``、
  ``pc_is_load`` 和 ``pc_is_div_or_rem`` 都通过 backdoor 从 Spike memory 取当前 PC
  处指令，服务于 NMI 退出、debug ebreak 快路径、suppress load/div 写回判断。
* 第 278-L297 行实现早期中断处理。它让 Spike 在「应该只改变 trap 状态、不退休新指令」
  的假设下 step 一次，如果 ``last_inst_pc`` 不是 ``PC_INVALID``，就说明 Spike 意外
  执行了指令，需要记录错误。
* 第 303-L454 行是 ``step`` 主循环。它先处理 debug ebreak 特例，再在 suppress 写回
  时保存 Spike 原寄存器值，记录初始 PC 并执行 ``proc->step(1)``；随后区分同步 trap、
  异步 trap 进入 ISR 和正常 retired instruction，最后做 mret/NMI 退出、I-side error
  消费、寄存器恢复、retire 比对、atomic TLB flush、诊断错误清理和指令计数递增。
* 第 456-L557 行处理 retired instruction 与同步 trap。PC 必须与 DUT retire PC 匹配；
  GPR 写回只能有一个，CSR 写回进入 ``on_csr_write``；同步 trap 要求 DUT 不写 GPR，
  并在 load/store access fault 或内部 NMI cause 下修正 pending D-side 队列。
* 第 559-L657 行处理 GPR 数据和 suppress 写回。SC.W 的 rd 结果以 DUT 为准，必要时
  写回 Spike GPR 保持后续同步；非阻塞 load 的数据差异被当作 EH2 store-forwarding
  时序容忍；suppress 写回只允许 load 或 div/rem，并从压缩/非压缩指令中解出目标 rd。
* 第 659-L683 行处理 CSR 写回和 NMI 退出。CSR 写回统一进入 ``fixup_csr``，把 Spike
  的标准 WARL 行为调整到 EH2；``leave_nmi_mode`` 从保存的 ``mstack`` 恢复 ``mstatus``、
  ``mepc`` 和 ``mcause``。
* 第 685-L753 行初始化每个 Spike hart。除了 PC、``mtvec``、``marchid`` 和 MMU 能力，
  还初始化 trigger module、MHPM event CSR，以及 Spike 原生不认识的 EH2 custom CSR。
* 第 755-L872 行是 DUT 状态通知入口。``set_mip`` 用 pre/post MIP 决定是否提前触发
  interrupt；``set_nmi`` 和 ``set_nmi_int`` 保存 NMI 入口前 CSR；``set_debug_req``
  控制 halt request；``set_mcycle`` 只消费顺序元数据；``set_csr`` 直接写 CSR；
  ``notify_dside_access`` 把 DUT 访存压入 per-hart 队列。
* 第 874-L908 行处理 widened load、取指错误、错误列表和指令计数。widened load pair
  必须是两个连续 full-word load，地址相差 4，错误标志一致；取指错误保存 aligned
  地址，等待下一次 Spike fetch 消费。
* 第 910-L974 行是 PMP misaligned fixup。它只在 PMP region 启用后工作，扫描 pending
  D-side 队列并移除已经标记 error 的半边，保留未出错半边给后续比对消费。
* 第 976-L1068 行是 atomic 辅助。``pc_is_atomic_mem_instr``、``is_sc_instr`` 和
  ``is_lr_instr`` 识别 RV32A 指令；``atomic_store_fixup`` 追踪 LR reservation，并在
  SC/AMO store 半边接受 EH2 LSU 级 reservation 与 Spike 内部 reservation 的差异。
* 第 1070-L1339 行是 ``fixup_csr``。它对 ``mstatus``、``misa``、``mtvec``、``mcause``、
  ``mrac``、``mpmc``、PIC 相关 CSR、``mscause``、``mfdc``、``mcgc``、ECC threshold、
  debug CSR、PMP CSR 和剩余 EH2 custom CSR 分别应用 EH2 WARL 或只读/写零行为。
* 第 1345-L1586 行是 ``check_mem_access``。它先处理无 pending access 的 load/store
  容忍，再处理 widened load pair 选择、地址/类型比对、byte enable 比对、数据比对、
  misaligned 两半一致性、bus error 返回和 pending 队列弹出，是 D-side AXI 观测与
  Spike MMIO 访问真正汇合的地方。
* 第 1588-L1602 行暴露 trap CSR getter。每个 getter 直接读 Spike state 并截成
  32-bit，供 SV 侧在 trap 比对点读取 ``mcause``、``mepc`` 和 ``mtvec``。
* 第 1604-L1661 行是 DPI factory。它解析 ``isa``、``pc``、``mtvec``、PMP、MHPM、
  trace 和 ``num_threads`` 配置，限制线程数到 1 到 ``COSIM_MAX_THREADS``，创建
  ``SpikeCosim``，最后返回调整后的 ``Cosim`` 子对象指针；这是双重继承场景下避免
  DPI wrapper 把 ``simif_t`` vtable 当作 ``Cosim`` vtable 的关键细节。
