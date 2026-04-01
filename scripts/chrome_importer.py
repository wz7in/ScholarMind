import sqlite3
import shutil
import os
import json
import sys
from datetime import datetime, timedelta
import urllib.parse

def get_chrome_history(days=2, limit=50):
    # Chrome History 路径 (macOS)
    history_path = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/History")
    temp_path = os.path.expanduser("~/Library/CloudStorage/OneDrive-个人/ScholarMind/Data/temp/chrome_history_temp")
    
    os.makedirs(os.path.dirname(temp_path), exist_ok=True)

    if not os.path.exists(history_path):
        return {"error": "找不到 Chrome 历史记录文件"}

    try:
        shutil.copy2(history_path, temp_path)
    except Exception as e:
        return {"error": f"复制失败: {e}. 请确保给予终端'完全磁盘访问权限'。"}

    try:
        conn = sqlite3.connect(temp_path)
        cursor = conn.cursor()
        
        # 计算时间戳 (Chrome 使用 WebKit epoch: microseconds since 1601-01-01)
        start_date = datetime.now() - timedelta(days=days)
        chrome_epoch_start = int((start_date.timestamp() + 11644473600) * 1000000)
        
        # 1. 查询 Google 搜索记录
        search_query = f"""
        SELECT title, url, last_visit_time 
        FROM urls 
        WHERE last_visit_time > {chrome_epoch_start}
        AND (url LIKE '%google.com/search?q=%' OR url LIKE '%google.com.hk/search?q=%')
        ORDER BY last_visit_time DESC
        """
        cursor.execute(search_query)
        search_rows = cursor.fetchall()
        
        searches = []
        unique_searches = set()
        for title, url, visit_time in search_rows:
            parsed_url = urllib.parse.urlparse(url)
            params = urllib.parse.parse_qs(parsed_url.query)
            if 'q' in params:
                query_text = params['q'][0]
                if query_text not in unique_searches:
                    searches.append({
                        "query": query_text,
                        "time": datetime.fromtimestamp(visit_time / 1000000 - 11644473600).strftime("%m-%d %H:%M")
                    })
                    unique_searches.add(query_text)

        # 2. 查询一般访问记录 (过滤掉搜索页面，只看内容页)
        # 扩展技术点域名
        research_domains = [
            'arxiv.org', 'github.com', 'medium.com', 'notion.so', 'zhihu.com', 
            'huggingface.co', 'openai.com', 'stackoverflow.com', 'pytorch.org', 
            'tensorflow.org', 'nvidia.com', 'weightsbiases.com', 'wandb.ai'
        ]
        domain_filters = " OR ".join([f"url LIKE '%{d}%'" for d in research_domains])
        
        visit_query = f"""
        SELECT title, url, last_visit_time 
        FROM urls 
        WHERE last_visit_time > {chrome_epoch_start}
        AND url NOT LIKE '%google.com/search%'
        AND ({domain_filters} OR visit_count > 3)
        ORDER BY last_visit_time DESC
        LIMIT {limit}
        """
        cursor.execute(visit_query)
        visit_rows = cursor.fetchall()
        
        visits = []
        for title, url, visit_time in visit_rows:
            visits.append({
                "title": title,
                "url": url,
                "time": datetime.fromtimestamp(visit_time / 1000000 - 11644473600).strftime("%H:%M")
            })

        conn.close()
        return {"searches": searches, "visits": visits}
    except Exception as e:
        return {"error": f"读取数据库出错: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    if mode == "list":
        days = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        result = get_chrome_history(days=days)
        print(json.dumps(result, ensure_ascii=False))
