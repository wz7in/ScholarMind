import sys
import os
import subprocess
import json
from datetime import datetime, timedelta

def get_recent_context(storage_root, days=7):
    context = ""
    today = datetime.now()
    for i in range(days):
        date_str = (today - timedelta(days=i)).strftime("%Y-%m-%d")
        report_path = os.path.join(storage_root, "papers", date_str, "Daily_Overall_Summary.md")
        if os.path.exists(report_path):
            with open(report_path, "r", encoding="utf-8") as f:
                context += f"【{date_str} 日报概括】：\n{f.read()[:1000]}\n"
    for i in range(days):
        date_str = (today - timedelta(days=i)).strftime("%Y-%m-%d")
        chat_path = os.path.join(storage_root, "ideas", date_str, "chat_history.json")
        if os.path.exists(chat_path):
            with open(chat_path, "r", encoding="utf-8") as f:
                history = json.load(f)
                for msg in history[-10:]:
                    role = "用户" if msg["isUser"] else "AI"
                    context += f"{role}: {msg['text']}\n"
    return context

def generate_formal_idea(storage_root, proxy="", engine="Gemini", chrome_context=""):
    context = get_recent_context(storage_root)
    
    chrome_info = ""
    if chrome_context:
        try:
            data = json.loads(chrome_context)
            chrome_info = "\n【近期 Chrome 浏览与搜索足迹】：\n"
            if "searches" in data:
                chrome_info += "- 搜索关键词: " + ", ".join([s["query"] for s in data["searches"][:10]]) + "\n"
            if "visits" in data:
                chrome_info += "- 访问过的技术/论文页面: \n"
                for v in data["visits"][:15]:
                    chrome_info += f"  * {v['title']} ({v['url']})\n"
        except: pass

    prompt = f"""
    你是一位世界顶级的计算机科学教授和实验室负责人。
    请结合用户的【近期论文阅读日报】、【实验室对话记录】以及【最新的网页浏览足迹】，为用户生成一个高度创新、可落地的科研 Idea 或深度研究报告。
    
    背景资料：
    {context}
    {chrome_info}
    
    要求：
    1. 识别最近两天的研究热点和技术重点。
    2. 将 Chrome 中的搜索和技术点与论文背景结合，提出跨学科或跨模块的创新点。
    3. 输出 Markdown 格式，包含：核心 Idea、创新性分析、技术路线路线及潜在挑战。
    """
    
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" + os.pathsep + env.get("PATH", "")
    
    # 全覆盖代理注入
    active_proxy = proxy or os.getenv("SCHOLAR_PROXY") or os.getenv("HTTP_PROXY")
    if active_proxy:
        for p in ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"]:
            env[p] = active_proxy
        env["SCHOLAR_PROXY"] = active_proxy
    
    # --- 统一绝对路径映射 ---
    bin_name = "gemini"
    if engine.lower() == "claude": bin_name = "claude"
    elif engine.lower() == "codex": bin_name = "codex"
    
    cli_path = f"/opt/homebrew/bin/{bin_name}"
    
    # 构建命令
    if bin_name == "codex":
        cli_cmd = [cli_path, "exec", "--skip-git-repo-check", prompt]
    else:
        cli_cmd = [cli_path, "-p", prompt]

    try:
        result = subprocess.run(cli_cmd, capture_output=True, text=True, check=True, env=env)
        idea_content = result.stdout
        today_str = datetime.now().strftime("%Y-%m-%d")
        target_dir = os.path.join(storage_root, "ideas", today_str)
        os.makedirs(target_dir, exist_ok=True)
        save_path = os.path.join(target_dir, "proposals.md")
        with open(save_path, "a", encoding="utf-8") as f:
            f.write(f"\n\n{idea_content}\n")
        return idea_content
    except Exception as e: return f"❌ 生成失败: {str(e)}"

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "generate"
    storage_root = sys.argv[2] if len(sys.argv) > 2 else ""
    proxy = sys.argv[3] if len(sys.argv) > 3 else ""
    engine = sys.argv[4] if len(sys.argv) > 4 else "Gemini"
    chrome_json = sys.argv[5] if len(sys.argv) > 5 else ""
    
    if mode == "generate": print(generate_formal_idea(storage_root, proxy, engine, chrome_json))
