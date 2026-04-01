# ScholarMind | 灵感科研情报中心

[English](./README_EN.md)

---

## 📖 简介
**ScholarMind** 是专为 macOS 设计的下一代 AI 驱动个人科研情报中心。它通过整合先进的 AI 模型（Gemini, Claude, Codex），帮助科研工作者自动化追踪、阅读并孵化科研灵感。

## ✨ 核心特性
- **科研洞察日报**: 自动同步 Scholar Inbox 论文，并生成今日研究趋势的 AI 摘要日报。
- **多维知识图谱**: 通过领域大类、技术标签和实验数据集，以交互式图谱管理你的文献库。
- **沉浸式 AI 阅读**: 在阅读 PDF 原文的同时查看 AI 深度分析，并能针对论文内容进行追问对话。
- **博闻笔记**: 支持抓取并总结技术博客或网页，将其转化为结构化的科研笔记。
- **灵感实验室**: 专门的灵感孵化空间，支持 AI 对话启发，并可同步 Chrome 浏览足迹以辅助 Idea 生成。

## 🚀 快速上手

### 环境要求
- **操作系统**: macOS 13.0+ (原生 SwiftUI 开发)
- **Python 3**: 用于运行后台处理脚本（论文提取、网页爬取）。
  - 请在 Python 环境中安装 `requirements.txt` 中的依赖。
- **AI 命令行工具**: 需安装 `gemini`、`claude` 或 `codex` 等 CLI 工具以驱动 AI 功能。
  - 需要提前登录（如运行 `gemini login`）并完成相关配置。
  - 推荐gemini，整体体验速度更快，而且主要是pro用户免费

### 配置步骤
1. 打开应用并进入 **系统设置**。
2. 设置 **资产存储路径**（用于存放论文、总结及日报文件）。
3. 配置本地 **Python 解释器路径** 和 **AI CLI 所在目录**。
4. 填入 **Scholar Inbox Cookie** 以开启每日论文自动同步。

### Cookie 获取方法
1. 打开浏览器，登录 [Scholar Inbox](https://www.scholar-inbox.com/).
2. 打开开发者工具（F12），切换到网络（Network）标签。
3. 刷新页面，过滤关键词 "api"。
4. 找到 `api/` 请求，查看请求头（Headers）中的 `Cookie` 字段。
5. 复制 `Cookie` 字段的值（需包含 `session=` 部分），粘贴到 ScholarMind 的系统设置中。

## 🛠️ 技术栈
- **前端**: SwiftUI (macOS 原生)
- **脚本层**: Python (使用 PyMuPDF, BeautifulSoup 等)
- **AI 集成**: 基于 CLI 的多引擎调度 (Gemini/Claude/Codex)
