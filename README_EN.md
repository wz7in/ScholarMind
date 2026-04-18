# ScholarMind | Research Intelligence & Inspiration Center

[简体中文](./README.md)

---

## 📖 Introduction
**ScholarMind** is a next-generation, AI-driven personal research intelligence center designed for macOS. It helps researchers automate the process of tracking, reading, and incubating ideas by leveraging advanced AI models (Gemini, Claude, Codex, DeepSeek).

## ✨ Key Features

### 1. Research Dashboard
A next-generation AI-driven research portal for quick access to core functions.
![Dashboard](./assets/dashboard.png)

### 2. Daily Insight Report
Automatically syncs papers from Scholar Inbox and generates a summarized daily research briefing on the latest trends.
![Daily Report](./assets/daily_report.png)

### 3. Multi-Dimensional Knowledge Graph
Navigate your research library through an interactive map of categories, technical tags, and experimental datasets.
![Knowledge Graph](./assets/knowledge_graph.png)

### 4. Inspiration Lab
A dedicated space for incubating research ideas, featuring AI brainstorming and integration with your Chrome browsing history to help generate new insights.
![Research Lab](./assets/lab.png)

### 5. Blog & Web Capture
Import and summarize technical blogs or web pages as structured research notes.
![Blog Notes](./assets/blogs.png)

### 📚 Other Features
- **Immersive AI Reader**: Read PDFs alongside AI-generated summaries and engage in deep-dive chats with your papers.

## 🚀 Getting Started

### Prerequisites
- **macOS**: 13.0+ (SwiftUI based)
- **Python 3**: For running background processors (Paper extraction, Web scraping).
  - Install dependencies via `pip install -r requirements.txt` in your Python environment.
- **AI CLI**: Installed tools like `gemini`, `claude`, or `codex` for core AI functions.
  - You must log in (e.g., `gemini login`) and complete configurations beforehand.
- **DeepSeek via SiliconFlow HTTP**:
  - DeepSeek does not rely on local CLI and uses native HTTP requests.
  - Set API key in the environment before launching the app: `SILICONFLOW_API_KEY` (or `AI_API_KEY`).
  - Fixed model: `Pro/deepseek-ai/DeepSeek-V3.2`, endpoint: `https://api.siliconflow.cn/v1/chat/completions`.

### Configuration
1. Open the app and navigate to **Settings**.
2. Set your **Asset Storage Path** (where papers and summaries will be stored).
3. Configure your **Python Interpreter Path** and **AI CLI Directory**.
4. Provide your **Scholar Inbox Cookie** for automatic syncing.

### How to get the Cookie
1. Open your browser and log in to [Scholar Inbox](https://www.scholar-inbox.com/).
2. Open Developer Tools (F12) and switch to the **Network** tab.
3. Refresh the page and filter by "api".
4. Find the `api/` request, click on it, and look for the `Cookie` field in **Request Headers**.
5. Copy the value of the Cookie field (including `session=`) and paste it into ScholarMind's settings.

## 🛠️ Tech Stack
- **Frontend**: SwiftUI (macOS Native)
- **Scripting**: Python (PyMuPDF, BeautifulSoup)
- **AI Integration**: Hybrid orchestration (CLI for Gemini/Claude/Codex, HTTP for DeepSeek on SiliconFlow)
