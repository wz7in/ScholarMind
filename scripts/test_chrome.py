import sqlite3
import shutil
import os
from datetime import datetime, timedelta
import urllib.parse

def test_chrome_history():
    # 1. 定义 Chrome 历史记录路径
    history_path = os.path.expanduser("~/Library/Application Support/Google/Chrome/Default/History")
    temp_path = os.path.expanduser("~/chrome_history_test_temp")
    
    print(f"🔍 正在尝试访问: {history_path}")
    
    if not os.path.exists(history_path):
        print("❌ 错误: 找不到 Chrome 历史记录文件。请检查 Chrome 是否安装在默认路径。")
        return

    # 2. 复制文件以避免数据库锁定
    try:
        shutil.copy2(history_path, temp_path)
        print("✅ 已创建数据库副本")
    except Exception as e:
        print(f"❌ 复制失败: {e}")
        print("💡 提示: 这通常是因为 macOS 的 TCC 权限限制。请确保你的终端或 Xcode 有 '完全磁盘访问权限'。")
        return

    # 3. 连接并查询
    try:
        conn = sqlite3.connect(temp_path)
        cursor = conn.cursor()
        
        # 计算 3 天前的时间戳 (Chrome 使用 WebKit epoch: microseconds since 1601-01-01)
        three_days_ago = datetime.now() - timedelta(days=3)
        chrome_epoch_start = int((three_days_ago.timestamp() + 11644473600) * 1000000)
        
        # 查询最近的 Google 搜索
        query = f"""
        SELECT title, url, last_visit_time 
        FROM urls 
        WHERE last_visit_time > {chrome_epoch_start}
        AND (url LIKE '%google.com/search?q=%' OR url LIKE '%google.com.hk/search?q=%')
        ORDER BY last_visit_time DESC
        """
        
        cursor.execute(query)
        rows = cursor.fetchall()
        
        print(f"\n🎯 最近 3 天的 Google 搜索记录 (共 {len(rows)} 条):")
        print("-" * 50)
        
        unique_queries = set()
        for title, url, visit_time in rows:
            # 从 URL 中解析出搜索词
            parsed_url = urllib.parse.urlparse(url)
            params = urllib.parse.parse_qs(parsed_url.query)
            if 'q' in params:
                query_text = params['q'][0]
                if query_text not in unique_queries:
                    print(f"• {query_text}")
                    unique_queries.add(query_text)
        
        if not unique_queries:
            print("没有发现 Google 搜索记录（或者均为隐私模式）。")
            
        conn.close()
    except Exception as e:
        print(f"❌ 读取数据库出错: {e}")
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

if __name__ == "__main__":
    test_chrome_history()
