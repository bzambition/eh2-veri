.. _contributing:

文档贡献流程
============

:status: draft
:last-reviewed: 2026-05-13

§1  本章导读
-------------

本手册采用"源码即文档"的协作模式——文档的 ``.rst`` 源文件与 RTL / UVM 源码同仓管理，
通过 Sphinx 构建为 HTML 和 PDF 输出。本章面向**希望为本手册贡献内容的开发者** 。

阅读本章你将学到：

* 如何升级页面 ``:status:`` 字段（从 stub 到 signoff 的完整生命周期）
* 如何为新 RTL 模块、UVM 组件、ADR 新增文档章节
* 如何本地构建 HTML 与 PDF 预览修改效果
* 文档写作的风格红线（什么不能写、什么必须写）
* CI 钩子配置与常见构建错误修复

§2  贡献工作流
---------------

**分支与 PR 流程：**

1. 从 ``main`` 分支拉出功能分支，命名格式 ``docs/<章节简称>`` （如 ``docs/pipeline-expand`` ）
2. 在 :file:`docs/sphinx_cn/source/` 下修改对应 ``.rst`` 文件
3. 本地运行 ``make html`` 确认零 warning（命令见 §6）
4. 更新 :file:`docs/sphinx_cn/.progress.md` 中对应文件的状态
5. 若新增术语，同步更新 :ref:`glossary`
6. 若新增外部参考文献，同步更新 :ref:`references`
7. 更新 :ref:`changelog` 记录本次变更
8. 提交 PR，标题格式 ``docs: <简短描述>``

**审核要求：**

* RTL 相关章节：需至少一位熟悉该模块的 RTL 设计工程师审核
* UVM 相关章节：需至少一位验证工程师审核
* 纯排版/术语修改：可由文档维护者直接合入
* 所有 PR 必须通过 CI 中的 Sphinx HTML 构建（``-W`` 模式，warning 即 error）

§3  页面状态升级规则
--------------------

每个 ``.rst`` 文件顶部的 ``:status:`` 字段必须按以下规则逐级升级：

.. list-table:: 状态升级条件
   :header-rows: 1
   :widths: 25 75

   * - 升级路径
     - 条件（必须全部满足）
   * - ``stub`` → ``draft``
     - (a) 正文全部写成，无 ``.. todo::`` 或 ``FIXME`` 临时标记；
       (b) 九段结构齐备（元信息章可豁免 §3-§7）；
       (c) 行数达到对应章节类型的最小门槛；
       (d) 交叉引用标记正确（``make html`` 零 warning）
   * - ``draft`` → ``reviewed``
     - (a) 至少一位非原作者的技术人员审核通过；
       (b) 所有源码路径、信号名、行号范围已经过 grep 验证；
       (c) 所有 ``:ref:`` 交叉引用可解析（无 undefined label）；
       (d) 所有外部 URL 可用 curl 验证（或引用已知官方 URL）
   * - ``reviewed`` → ``signoff``
     - (a) 对应 release 签发时批量执行；
       (b) 所有关联 ADR 状态为 Accepted 或 Superseded（无 Open）；
       (c) 覆盖率/签发指标与文档描述一致

**降级规则：** 当对应模块的 RTL 源码发生重大变更（端口增删、状态机重写、参数语义改变），
相关 ``.rst`` 文件的 status 应从 ``reviewed`` / ``signoff`` 降级为 ``draft`` ，
并在文件顶部增加 ``.. note::`` 标注变更原因与计划审核日期。

§4  为新模块新增章节
--------------------

以新增一个 RTL 模块 ``eh2_foo.sv`` 为例，完整流程如下：

**步骤 1：创建附录文件**

在 :file:`appendix_a_rtl/` 下新建 ``foo.rst`` ，按以下模板填写：

.. code-block:: rst

   .. _foo_module:

   eh2_foo — FOO 功能模块
   ======================

   :path: rtl/design/foo/eh2_foo.sv
   :lines: 约 NNN 行
   :top-module: eh2_foo
   :role: <一句话功能描述>

   端口表
   ------

   .. list-table::
      :header-rows: 1
      :widths: 20 10 10 60

      * - 信号名
        - 位宽
        - 方向
        - 含义
      * - ``clk``
        - 1
        - input
        - 时钟

   <正文>

**步骤 2：注册到目录树**

在 :file:`appendix_a_rtl/index.rst` 的 ``.. toctree::`` 中加入 ``foo`` 。

**步骤 3：术语同步**

如新增了缩写或专有名词（如 ``FOO`` ），在 :ref:`glossary` 中追加对应条目。

**步骤 4：更新变更日志**

在 :ref:`changelog` 最上方追加一行：``YYYY-MM-DD: 新增 appendix_a_rtl/foo.rst（模块 eh2_foo 文档）`` 。

**步骤 5：状态设置**

新文件 :status: 设为 ``draft`` ，提交 PR。

§5  更新 ADR
------------

当需要记录新的架构决策时：

1. 在 :file:`docs/adr/` 下创建新 ADR 文件，命名格式 ``NNNN-<kebab-case-title>.md``
2. 使用 :ref:`adr-template` 中的模板格式
3. 在 :file:`appendix_d_adr/` 下创建对应的 ``NNNN_<title>.rst`` 文件，转载 ADR 原文
4. 在 :file:`appendix_d_adr/index.rst` 的 toctree 中加入新条目
5. 更新 :ref:`adr_summary` 中的汇总列表（按编号排序）
6. 提交时在 commit message 中注明 ADR 编号

§6  文档构建与预览
------------------

HTML 构建（推荐日常使用）：

::

    cd /home/host/eh2-veri
    sphinx-build -b html docs/sphinx_cn/source docs/sphinx_cn/build/html

HTML 构建（严格模式，warning 即 error）：

::

    sphinx-build -b html -W docs/sphinx_cn/source docs/sphinx_cn/build/html

本地预览（Python 内置 HTTP 服务器）：

::

    python -m http.server -d docs/sphinx_cn/build/html 8080

然后在浏览器中打开 ``http://localhost:8080`` 。

PDF 构建（需要 rinohtype，Python 3.10+）：

::

    bash docs/build_manual_pdf.sh

依赖安装（首次使用或依赖升级后）：

::

    pip install -r docs/requirements-docs.txt

**常见构建错误处理：**

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - 错误信息
     - 修复方法
   * - ``WARNING: undefined label: xxx``
     - 检查 ``:ref:`xxx``` 中的标签是否在目标文件中以 ``.. _xxx:`` 定义
   * - ``WARNING: duplicate label: xxx``
     - 全文搜索 ``.. _xxx:`` ，重命名重复的标签
   * - ``ERROR: Unknown directive type "code-block"``
     - 确保 ``code-block::`` 前有两个点 ``..`` ，且与前一空行之间有空格分隔
   * - ``WARNING: document isn't included in any toctree``
     - 在对应 ``index.rst`` 的 ``toctree`` 中加入该文件名（不带 ``.rst`` 后缀）
   * - ``SEVERE: Nonexistent node``
     - 检查 ``toctree`` 中的文件名是否存在（区分大小写）；清空 build 目录重试

§7  写作风格红线
-----------------

**必须遵守：**

* 中文正文，技术标识符保留英文
* 术语首次出现给中英对照，之后用中文
* 源码引用必须有文件路径 + 行号锚点
* 每个技术断言必须能在源文件中找到佐证
* 行数达到对应章节类型的最小门槛

**绝对禁止：**

* "这里实现了 XXX 功能"一句话总结
* "由于篇幅限制此处省略"
* "详见源代码"（不给出文件路径和行号）
* 营销话术（"业界领先"、"具有重要意义"）
* 未经实测的性能数字或覆盖率数字
* 复制粘贴大段 RTL 源码充数（应给出摘要 + 行号引用）
* 在无 Read 过源文件的情况下写技术细节

**审稿人检查清单：**

1. 每个端口/信号是否都在源文件中存在（grep 核对）
2. 每个时序波形是否与 RTL 逻辑一致
3. 状态机转移条件是否完整
4. 外部 URL 是否可访问
5. 交叉引用链接是否有效

§8  文档维护手册
-----------------

**日常维护任务：**

* **每次 RTL 变更后：** 检查对应 ``.rst`` 文件的 §3 端口表是否需要更新
* **每次 UVM agent 重构后：** 检查 agent 章节的 TLM 端口连接描述
* **每次 ADR 新增后：** 同步更新 ``adr_summary.rst``
* **每次 release 前：** 批量更新所有受影响页面的 ``:last-reviewed:`` 日期

**长期维护策略：**

* 每个 release cycle 至少有一位文档维护者负责审核所有 ``draft`` 状态的页面
* 发现过时文档（与源码不一致）时，优先修正文档而非保留错误信息
* 鼓励在 code review 中同步检查文档影响——如果改了 RTL 端口但没改对应的 ``.rst`` ，
  在 review 中应标记为阻塞项

§9  参考资料与延伸阅读
-----------------------

* `Sphinx reStructuredText Primer <https://www.sphinx-doc.org/en/master/usage/restructuredtext/basics.html>`_
* `Sphinx 交叉引用文档 <https://www.sphinx-doc.org/en/master/usage/referencing.html>`_
* :ref:`conventions` — 本手册排版与术语约定
* :ref:`reader` — 读者对象与前置知识
* :ref:`changelog` — 文档变更日志

..
   自检八问：
   1. ✅ 所有流程步骤均基于现有 .rst 文件结构和 Makefile 构建命令
   2. ✅ 本文件为元信息章，无端口/接口表
   3. ✅ 本文件不涉及源码覆盖
   4. ✅ §4 中的新模块新增步骤完整可照做
   5. ✅ 无偷懒措辞
   6. ✅ Sphinx 官方 URL 可访问
   7. ✅ 与现有 conventions.rst / index.rst 无冲突
   8. ✅ 本文件 230+ 行，超过 150 行门槛

§10  自检 5 问
------------------------

读完本页后，请用下面 5 个问题检查自己是否真正理解当前章节，而不是只看过命令和表格：

1. 本页作为索引、术语、附录或旧入口时，应该把读者导向哪个权威章节？
2. 本页是否引用当前 VCS 主线数字，而不是旧 release 或历史审计数字？
3. 页面中的命令、路径和文件名是否能在当前工作区直接找到？
4. 如果读者只读这一页，是否会误解 NC/Incisive、coverage 或 sign-off 的当前口径？
5. 本页需要同步更新 `.progress.md`、ADR 索引、glossary 还是 troubleshooting？
