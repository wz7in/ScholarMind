import sys
import os
import subprocess
import requests
from bs4 import BeautifulSoup
import json
from datetime import datetime
import re
from pathvalidate import sanitize_filename

def extract_web_content(url):
    try:
        res = requests.get(url, timeout=30)
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, 'html.parser')
        # 移除脚本和样式
        for script in soup(["script", "style"]): script.decompose()
        # 寻找文章主体
        title = soup.title.string if soup.title else "Untitled Blog"
        text = soup.get_text(separator='\n')
        # 简单清理
        lines = (line.strip() for line in text.splitlines())
        chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
        text = '\n'.join(chunk for chunk in chunks if chunk)
        return title, text[:15000]
    except Exception as e:
        return None, str(e)

def summarize_blog(url, title, text, storage_root, engine="Gemini"):
    prompt = f"""
    你是一位资深的科技博文编辑。请分析这篇博客内容：
    URL: {url}
    标题: {title}
    
    【任务要求】：
    请严格按照以下 Markdown 格式输出总结：
    # 📝 博文总结: {title}
    
    ## 💡 核心观点
    - 提炼文章最核心的 1-3 个观点。
    
    ## 🛠️ 技术细节/深度分析
    - 详细描述文中提到的技术实现、逻辑推导或核心论据。
    
    ## 🌟 启发与思考
    - 这篇文章对科研或工程实践有哪些参考价值？
    
    JSON_START
    {{
      "actual_title": "{title}",
      "category": "博文笔记",
      "tags": ["AI博文"],
      "extracted_date": "{datetime.now().strftime('%Y-%m-%d')}"
    }}
    JSON_END
    
    原文内容：{text}
    """
    
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" + os.pathsep + env.get("PATH", "")
    bin_name = "gemini"
    if engine.lower() == "claude": bin_name = "claude"
    elif engine.lower() == "codex": bin_name = "codex"
    
    try:
        res = subprocess.run([f"/opt/homebrew/bin/{bin_name}", "-p", prompt], capture_output=True, text=True, env=env)
        full = res.stdout
        summary = full.split("JSON_START")[0].strip()
        metadata = {}
        json_match = re.search(r'JSON_START(.*?)JSON_END', full, re.DOTALL)
        if json_match: metadata = json.loads(json_match.group(1).strip())
        return summary, metadata
    except: return None, None

if __name__ == "__main__":
    if len(sys.argv) < 4: sys.exit(1)
    url, storage_root, engine = sys.argv[1], sys.argv[2], sys.argv[3]
    
    title, text = extract_web_content(url)
    if title:
        summary, meta = summarize_blog(url, title, text, storage_root, engine)
        if summary:
            date_str = meta.get("extracted_date", datetime.now().strftime("%Y-%m-%d"))
            target_dir = os.path.join(storage_root, "blogs", date_str, sanitize_filename(title))
            os.makedirs(target_dir, exist_ok=True)
            with open(os.path.join(target_dir, "summary.md"), "w", encoding="utf-8") as f: f.write(summary)
            with open(os.path.join(target_dir, "metadata.json"), "w", encoding="utf-8") as f:
                meta["url"] = url
                json.dump(meta, f, ensure_ascii=False, indent=4)
            print("PROGRESS: BLOG_DONE")
