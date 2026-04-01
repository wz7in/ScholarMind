import sys
import os
import subprocess
import requests
from bs4 import BeautifulSoup
from datetime import datetime
import time
import re

def fetch_papers(cookie, proxy, storage_root, engine="Gemini", max_daily=15, score_threshold=0.85, likes_threshold=2, low_score_limit=2):
    api_url = "https://api.scholar-inbox.com/api/"
    
    clean_cookie = cookie.strip()
    cookie_header = clean_cookie if clean_cookie.startswith("session=") else f"session={clean_cookie}"
        
    headers = {
        "Cookie": cookie_header,
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    proxies = {"http": proxy, "https": proxy} if proxy else None
    
    print(f"DEBUG: Starting fetch_papers with max_daily: {max_daily}, score_threshold: {score_threshold}")
    
    try:
        import urllib3
        urllib3.disable_warnings()
        response = requests.get(api_url, headers=headers, proxies=proxies, timeout=30, verify=False)
        
        if response.status_code != 200:
            print(f"PROGRESS: API返回异常: {response.status_code}")
            return

        try:
            data = response.json()
            
            # --- 精准解析推送日期 ---
            api_date = datetime.now().strftime("%Y-%m-%d")
            from_date_str = data.get("from_date")
            
            if from_date_str:
                try:
                    # 解析格式: "Fri, 27 Mar 2026 00:00:00 GMT"
                    from email.utils import parsedate_to_datetime
                    dt = parsedate_to_datetime(from_date_str)
                    api_date = dt.strftime("%Y-%m-%d")
                    print(f"DEBUG: 解析到 API 推送日期 (from_date): {api_date}")
                except Exception as e:
                    print(f"DEBUG: 解析 from_date 失败 ({from_date_str}): {e}")
            
            raw_papers = data.get("digest_df", [])
            # ---------------------
            
            # 1. High Score Papers
            high_score_papers = [p for p in raw_papers if p.get("ranking_score", 0) > score_threshold]
            # 2. Low Score Papers Sampling
            low_score_papers = [p for p in raw_papers if p.get("ranking_score", 0) <= score_threshold]
            
            import random
            sampled_low_score = random.sample(low_score_papers, min(len(low_score_papers), low_score_limit))
            
            # Combine and limit
            papers = (high_score_papers + sampled_low_score)[:max_daily]
            
            print(f"DEBUG: Found {len(raw_papers)} total, selected {len(papers)} (High: {len(high_score_papers)}, Low Sampled: {len(sampled_low_score)})")
        except Exception as json_e:
            print(f"PROGRESS: 解析API返回数据失败")
            return

        total_to_process = len(papers)
        if not papers:
            print("PROGRESS: 今日暂无新论文")
            print("PROGRESS: PAPER_DONE")
            return
        
        # 在处理前，先做一次简单的查重检查，减少下载压力
        def is_already_exists(title, storage_root):
            def normalize(t): return re.sub(r'[^a-zA-Z0-9]', '', t).lower()
            target = normalize(title)[:30] # 只取前30位进行前缀匹配
            if not target: return False
            
            papers_path = os.path.join(storage_root, "papers")
            if not os.path.exists(papers_path): return False
            for d in os.listdir(papers_path):
                date_dir = os.path.join(papers_path, d)
                if not os.path.isdir(date_dir): continue
                for s in ["精读论文", "粗读论文", "manual"]:
                    sub_dir = os.path.join(date_dir, s)
                    if not os.path.exists(sub_dir): continue
                    for folder in os.listdir(sub_dir):
                        if normalize(folder).startswith(target): return True
            return False

        for index, paper in enumerate(papers, 1):
            title = paper.get("title", "Untitled")
            
            progress_label = f"[{index}/{total_to_process}]"
            if is_already_exists(title, storage_root):
                print(f"PROGRESS: {progress_label} 该论文已存在，跳过: {title}")
                continue

            pdf_url = paper.get("url", "")
            if pdf_url.startswith("/"): pdf_url = "https://www.scholar-inbox.com" + pdf_url
            
            score = paper.get("ranking_score", 0)
            likes = paper.get("total_likes", 0)
            priority = "high" if score > score_threshold or likes >= likes_threshold else "low"
            
            print(f"PROGRESS: {progress_label} 正在获取: {title} (Score: {score:.2f})")

            try_time = 4
            for t in range(try_time):
                pdf_path = download_pdf(pdf_url, storage_root, proxies)
                if pdf_path:
                    script_path = os.path.join(os.path.dirname(__file__), "processor.py")
                    # 使用 sys.executable 确保使用相同的 Python 环境
                    # 继承所有环境变量（含 AI_CLI_PATH, HTTP_PROXY 等）
                    run_env = os.environ.copy()
                    result = subprocess.run([sys.executable, "-u", script_path, title, pdf_path, priority, storage_root, api_date, engine, "true", progress_label], env=run_env)
                    if result.returncode == 0:
                        print(f"PROGRESS: {progress_label} 处理完成")
                        break
                    else:
                        print(f"PROGRESS: {progress_label} 分析脚本执行失败 (ExitCode: {result.returncode})，准备重试...")
                else:
                    print(f"PROGRESS: {progress_label} PDF 下载失败，请检查网络或代理设置，准备重试...")

                time.sleep(2) # 稍微等待再重试
                print(f"PROGRESS: {progress_label} 正在进行第 {t+1}/{try_time} 次重试...")


            if not pdf_path:
                print(f"PROGRESS: {progress_label} 下载失败")

        # 所有论文处理完后，统一刷新一次日报
        print(f"PROGRESS: 正在生成今日 ({api_date}) 洞察日报...")
        script_path = os.path.join(os.path.dirname(__file__), "processor.py")
        
        # 显式传递 AI_CLI_PATH 环境变量，确保子进程能找到工具
        report_env = os.environ.copy()
        if 'AI_CLI_PATH' not in report_env:
            report_env['AI_CLI_PATH'] = os.path.dirname(sys.executable) # 兜底

        report_result = subprocess.run([sys.executable, "-u", script_path, "report", storage_root, api_date, engine], env=report_env)
        
        if report_result.returncode == 0:
            print(f"PROGRESS: 今日日报生成成功")
        else:
            print(f"PROGRESS: ⚠️ 日报生成可能存在异常")
                
        print("PROGRESS: PAPER_DONE")
    except Exception as e:
        print(f"PROGRESS: 同步失败: {e}")

def download_pdf(url, storage_root, proxies):
    try:
        # ArXiv 链接规范化处理
        if "arxiv.org/abs/" in url:
            url = url.replace("/abs/", "/pdf/")
        if "arxiv.org" in url and not url.endswith(".pdf"):
            url = url + ".pdf"

        temp_dir = os.path.join(storage_root, "temp")
        os.makedirs(temp_dir, exist_ok=True)
        filename = re.sub(r'[^\w\s-]', '', url.split('/')[-1])
        if not filename.endswith(".pdf"): filename += ".pdf"
        path = os.path.join(temp_dir, filename)
        
        # 伪装成更像浏览器的请求头
        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.scholar-inbox.com/"
        }

        # 调高超时至 90 秒，防止大文件断连
        res = requests.get(url, headers=headers, proxies=proxies, timeout=90, stream=True, verify=False)
        if res.status_code != 200: 
            print(f"DEBUG: 下载失败，HTTP 状态码: {res.status_code} URL: {url}")
            return None
            
        with open(path, 'wb') as f:
            for chunk in res.iter_content(chunk_size=8192): f.write(chunk)
        return path
    except Exception as e: 
        print(f"DEBUG: 下载异常: {e}")
        return None

if __name__ == "__main__":
    cookie = sys.argv[1] if len(sys.argv) > 1 else ""
    proxy = sys.argv[2] if len(sys.argv) > 2 else ""
    storage_root = sys.argv[3] if len(sys.argv) > 3 else ""
    engine = sys.argv[4] if len(sys.argv) > 4 else "Gemini"
    max_daily = int(sys.argv[5]) if len(sys.argv) > 5 else 15
    score_threshold = float(sys.argv[6]) if len(sys.argv) > 6 else 0.8
    likes_threshold = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    low_score_limit = int(sys.argv[8]) if len(sys.argv) > 8 else 2
    
    fetch_papers(cookie, proxy, storage_root, engine, max_daily, score_threshold, likes_threshold, low_score_limit)
