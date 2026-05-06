## Agent skills

### Issue tracker

Local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.

### Superpowers-ZH 中文增强版 Skills

本项目已安装 superpowers-zh 技能框架。Skills 位于 `~/.claude/skills/` 目录，使用 `Skill` 工具加载。

#### 核心规则

1. **收到任务时，先检查是否有匹配的 skill** — 哪怕只有 1% 的可能性也要检查
2. **设计先于编码** — 收到功能需求时，先用 brainstorming skill 做需求分析
3. **测试先于实现** — 写代码前先写测试（TDD）
4. **验证先于完成** — 声称完成前必须运行验证命令

#### 可用 Skills

| Skill | 用途 |
|-------|------|
| `brainstorming` | 创造性工作前的需求分析和设计探索 |
| `chinese-code-review` | 中文代码审查规范 |
| `chinese-commit-conventions` | 中文 Git 提交规范 |
| `chinese-documentation` | 中文技术文档写作规范 |
| `chinese-git-workflow` | 国内 Git 平台工作流规范 |
| `dispatching-parallel-agents` | 并行任务分发 |
| `executing-plans` | 执行书面实现计划 |
| `finishing-a-development-branch` | 开发分支收尾 |
| `mcp-builder` | 构建生产级 MCP 工具 |
| `receiving-code-review` | 接收和处理代码审查反馈 |
| `requesting-code-review` | 请求代码审查 |
| `subagent-driven-development` | 子代理驱动开发 |
| `systematic-debugging` | 系统化调试 |
| `test-driven-development` | 测试驱动开发 |
| `using-git-worktrees` | Git worktree 隔离开发 |
| `using-superpowers` | 技能查找和使用指南 |
| `verification-before-completion` | 完成前验证 |
| `workflow-runner` | 运行 YAML 工作流 |
| `writing-plans` | 编写实现计划 |
| `writing-skills` | 创建和验证技能 |
