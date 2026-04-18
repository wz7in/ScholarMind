import sys
import os
import subprocess
import pymupdf
from pathvalidate import sanitize_filename
import json
from datetime import datetime
import time
import re
import shutil

def extract_text_from_pdf(pdf_path, max_pages=15):
    text = ""
    try:
        if not os.path.exists(pdf_path): return ""
        doc = pymupdf.open(pdf_path)
        for i in range(min(max_pages, len(doc))):
            text += doc[i].get_text()
        doc.close()
    except Exception as e: print(f"PDF 提取错误: {e}")
    return text

def get_ghostscript_path():
    gs_names = ["gs", "gswin32c", "gswin64c"]
    for name in gs_names:
        if shutil.which(name):
            return shutil.which(name)
    return None

def compress_pdf(input_file_path, output_file_path, power=2):
    """Function to compress PDF via Ghostscript command line interface"""
    quality = {
        0: "/default",
        1: "/prepress",
        2: "/printer",
        3: "/ebook",
        4: "/screen"
    }

    if not os.path.isfile(input_file_path):
        return False

    gs = get_ghostscript_path()
    if not gs:
        print("PROGRESS: ⚠️ 未找到 Ghostscript，跳过压缩。")
        return False

    initial_size = os.path.getsize(input_file_path)
    try:
        subprocess.call(
            [
                gs,
                "-sDEVICE=pdfwrite",
                "-dCompatibilityLevel=1.4",
                "-dPDFSETTINGS={}".format(quality[power]),
                "-dEmbedAllFonts=true",
                "-dSubsetFonts=true",
                "-dNOPAUSE",
                "-dQUIET",
                "-dBATCH",
                "-sOutputFile={}".format(output_file_path),
                input_file_path,
            ]
        )
        final_size = os.path.getsize(output_file_path)
        ratio = 1 - (final_size / initial_size)
        print(f"PROGRESS: PDF 压缩完成。压缩率: {ratio:.0%}，最终大小: {final_size / 1024 / 1024:.2f}MB")
        return True
    except Exception as e:
        print(f"PROGRESS: ⚠️ PDF 压缩出错: {e}")
        return False

def summarize_and_tag_paper(paper_title, text, storage_root, engine="Gemini", priority="low", force_date=None, pdf_path=None):
    if not text and not pdf_path: return None, None
    tag_pool, cat_pool, ds_pool = [], [], []
    try:
        with open(os.path.join(storage_root, "tags_pool.json"), "r", encoding="utf-8") as f: tag_pool = json.load(f)
        with open(os.path.join(storage_root, "categories_pool.json"), "r", encoding="utf-8") as f: cat_pool = json.load(f)
        with open(os.path.join(storage_root, "datasets_pool.json"), "r", encoding="utf-8") as f: ds_pool = json.load(f)
    except: pass

    date_task = ""
    if not force_date:
        date_task = """
    【关键任务：锁定真实发表日期】
    1. 特别留意 arXiv 左侧边栏垂直日期（如 3 Mar 2026）。
    2. 提取最晚的修订/提交日期，格式 YYYY-MM-DD。
    """

    # 根据优先级选择总结 Prompt
    if priority in ["high", "manual", "manual_force"]:
        summary_instruction = """
        【总结任务 - 深度讲解】：
        请严格按照以下 Markdown 格式输出：
        ## 1. 一句话总结与背景 (TL;DR & Context)
        > 简述论文解决的核心问题及主要创新点。
        
        ## 2. 核心模型与网络架构 (Model & Network Architecture)
        - **架构拆解**：深入描述注意力机制、Backbone、感知融合、策略网络等。
        - **结构图解**：必须使用 Mermaid.js 语法绘制。
        ```mermaid
        graph TD
          A["输入"] --> B["核心模块"]
        ```
        
        ## 3. 实验设计与核心结论 (Experiments & Conclusions)
        - **设置**：数据集、Baseline。
        - **结论**：提炼最关键实验数据。
        
        ## 4. 局限性与启发 (Limitations & Insights)
        - 讨论局限及对后续研究的启发。
        """
    else:
        summary_instruction = """
        【总结任务 - 简单摘要】：
        请严格按照以下 Markdown 格式输出：
        ## 核心贡献
        - 点明论文最主要的 1-2 个创新点。
        
        ## 关键结果
        - 简述实验达到的效果。
        
        ## 领域标签
        - 3-5个核心关键词。
        """

    # 智能清理：寻找参考文献位置并截断，节省 Token 和时间
    ref_keywords = ["References", "REFERENCES", "Bibliography", "BIBLIOGRAPHY", "参考文献"]
    clean_text = text[:12000]
    for kw in ref_keywords:
        ref_idx = clean_text.rfind(kw)
        if ref_idx > 5000: # 确保不是摘要里的误伤
            clean_text = clean_text[:ref_idx]
            break

    prompt = f"""
    你是一位顶尖的 AI 算法科学家与学术导师。请分析以下论文内容。
    {date_task}
    【元数据提取】：从闭集：大类 {json.dumps(cat_pool, ensure_ascii=False)}, 标签 {json.dumps(tag_pool, ensure_ascii=False)}, 数据集 {json.dumps(ds_pool, ensure_ascii=False)} 中选。
    {summary_instruction}
    
    JSON_START
    {{ "actual_title": "...", "category": "...", "tags": [], "datasets": [], "extracted_date": "{force_date if force_date else 'YYYY-MM-DD'}" }}
    JSON_END
    """
    
    # 智能决定是否在 Prompt 中包含全文
    if pdf_path and os.path.exists(pdf_path) and engine.lower() != "codex":
        # 如果有 PDF 文件且引擎支持，我们只发送指令，不贴原文，防止命令行超长
        prompt += "\n请直接分析附件中的 PDF 文件内容。"
    else:
        # 否则（如 Codex 或无 PDF 时），才贴入提取的文本
        prompt += f"\n正文内容：\n{clean_text}\n"

    env = os.environ.copy()
    cli_base_path = os.getenv("AI_CLI_PATH", "/usr/local/bin")
    env["PATH"] = cli_base_path + os.pathsep + "/usr/local/bin:/usr/bin:/bin" + os.pathsep + env.get("PATH", "")

    # 自动继承父进程的代理，并确保大小写全覆盖
    proxy = os.getenv("SCHOLAR_PROXY") or os.getenv("HTTP_PROXY") or os.getenv("http_proxy")
    if proxy:
        for p in ["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"]:
            env[p] = proxy
        env["SCHOLAR_PROXY"] = proxy

    bin_name = "gemini"
    if engine.lower() == "claude": bin_name = "claude"
    elif engine.lower() == "codex": bin_name = "codex"

    # 智能搜索路径
    cli_base_path = os.getenv("AI_CLI_PATH", "")
    cli_cmd_path = os.path.join(cli_base_path, bin_name) if cli_base_path else ""
    
    if not cli_cmd_path or not os.path.exists(cli_cmd_path):
        for sp in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]:
            test_path = os.path.join(sp, bin_name)
            if os.path.exists(test_path):
                cli_cmd_path = test_path
                break
    
    if not cli_cmd_path or not os.path.exists(cli_cmd_path):
        print(f"PROGRESS: ❌ 找不到 {bin_name} 工具。请检查设置。")
        return None, None

    # 根据引擎构建命令
    if bin_name == "codex":
        cli_cmd = [cli_cmd_path, "exec", "--skip-git-repo-check", prompt]
    else:
        # 修正：Gemini CLI 不允许同时使用 -p 和位置参数（PDF 路径）
        # 如果提供了 PDF，我们将 Prompt 和 PDF 都作为位置参数传递
        if pdf_path and os.path.exists(pdf_path):
            cli_cmd = [cli_cmd_path, prompt, pdf_path]
        else:
            cli_cmd = [cli_cmd_path, "-p", prompt]

    print(f"DEBUG: AI Command: {' '.join(cli_cmd[:2])} ... [PDF: {pdf_path if pdf_path else 'None'}]")


    for attempt in range(3):
        try:
            # 调高超时至 240s，开启 check=True 以捕获错误
            print(f"DEBUG: 正在执行 AI 命令 (尝试 {attempt+1}/3): {' '.join(cli_cmd)}")
            result = subprocess.run(cli_cmd, capture_output=True, text=True, env=env, timeout=240)
            
            if result.returncode != 0:
                print(f"DEBUG: AI 命令返回非零状态码: {result.returncode}")
                print(f"DEBUG: STDERR: {result.stderr.strip()}")
                print(f"DEBUG: STDOUT: {result.stdout.strip()}")
                if "Opening authentication page" in result.stdout or "Opening authentication page" in result.stderr:
                    print(f"PROGRESS: ❌ AI 引擎未登录。请在终端运行 '{bin_name} login'。")
                    return None, None
                time.sleep(5)
                continue

            full = result.stdout
            if not full.strip():
                print(f"DEBUG: AI 返回内容为空。STDERR: {result.stderr.strip()}")
                time.sleep(5)
                continue

            json_match = re.search(r'JSON_START(.*?)JSON_END', full, re.DOTALL)
            if json_match:
                meta = json.loads(json_match.group(1).strip())
                summary = full.replace(f"JSON_START{json_match.group(1)}JSON_END", "").strip()
                return summary, meta
            else:
                print(f"DEBUG: AI 返回内容未包含 JSON 标记。收到的前 200 字符: {full[:200]}...")
        except subprocess.TimeoutExpired:
            print(f"DEBUG: AI 分析超时 (240s)")
            if attempt == 2: return None, None
            time.sleep(5)
        except Exception as e:
            print(f"DEBUG: AI 分析发生意外错误: {e}")
            if attempt == 2: return None, None
            time.sleep(5)
    return None, None

def update_daily_report(storage_root, date_str, engine="Gemini"):
    print(f"PROGRESS: 正在刷新 {date_str} 日报...")
    date_dir = os.path.join(storage_root, "papers", date_str)
    
    context_data = []
    for sub in ["精读论文", "粗读论文", "manual"]:
        sub_path = os.path.join(date_dir, sub)
        if not os.path.exists(sub_path): continue
        
        for paper_folder in os.listdir(sub_path):
            folder_path = os.path.join(sub_path, paper_folder)
            if not os.path.isdir(folder_path): continue
            
            summary_path = os.path.join(folder_path, "summary.md")
            if os.path.exists(summary_path):
                try:
                    with open(summary_path, "r", encoding="utf-8") as f:
                        content = f.read()
                        # 智能提取：寻找“核心贡献”或开头部分，精简到 300 字
                        snippet = ""
                        if "## 核心贡献" in content:
                            snippet = content.split("## 核心贡献")[1].split("##")[0].strip()
                        elif "## 1." in content:
                            snippet = content.split("## 1.")[1].split("##")[0].strip()
                        else:
                            snippet = content[:300]
                        
                        context_data.append(f"### 论文标题: {paper_folder}\n摘要关键点: {snippet[:300]}...")
                except: pass
                
    if not context_data: return
    
    full_context = "\n\n".join(context_data)
    prompt = f"""
    你是一位顶尖的科研助手。请根据以下提供的 {date_str} 论文摘要信息，撰写一份高质量的「科研洞察日报」。
    请务必完成所有板块的撰写，不要截断。
    
    【日报结构要求】：
    # 🗓️ 科研洞察日报 - {date_str}
    
    ## 🎯 今日研究趋势
    - 总结今日论文所涉及的热点方向和整体技术演进趋势。
    
    ## 🔬 重点论文深度点评
    - 对 1-2 篇最具创新性的论文进行重点点评，分析其对领域的长远影响。
    
    ## 📚 论文简览
    - 简要列出其余论文的核心贡献。
    
    背景信息（论文摘要）：
    {full_context}
    """
    
    env = os.environ.copy()
    cli_base_path = os.getenv("AI_CLI_PATH", "/usr/local/bin")
    env["PATH"] = cli_base_path + os.pathsep + "/usr/local/bin:/usr/bin:/bin" + os.pathsep + env.get("PATH", "")
    
    # 继承代理
    proxy = os.getenv("SCHOLAR_PROXY") or os.getenv("HTTP_PROXY")
    if proxy:
        env["HTTP_PROXY"] = env["HTTPS_PROXY"] = env["ALL_PROXY"] = proxy
        
    bin_name = "gemini"
    if engine.lower() == "claude": bin_name = "claude"
    elif engine.lower() == "codex": bin_name = "codex"
        
    # 智能搜索路径
    cli_base_path = os.getenv("AI_CLI_PATH", "")
    bin_path = os.path.join(cli_base_path, bin_name) if cli_base_path else ""
    
    # 如果指定路径下没有，则搜索常见系统路径
    if not bin_path or not os.path.exists(bin_path):
        search_paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for sp in search_paths:
            test_path = os.path.join(sp, bin_name)
            if os.path.exists(test_path):
                bin_path = test_path
                break
    
    # 最终防御
    if not bin_path or not os.path.exists(bin_path):
        print(f"PROGRESS: ❌ 无法在任何路径下找到 {bin_name}。请在 App 设置中检查 AI CLI 路径。")
        return
    
    try:
        # 调高超时至 300s，并增加未登录检测
        res = subprocess.run([bin_path, "-p", prompt], capture_output=True, text=True, env=env, timeout=300)
        
        if "Opening authentication page" in res.stdout or "Opening authentication page" in res.stderr:
            print(f"PROGRESS: ❌ AI 引擎未登录。请在终端运行 '{bin_name} login'。")
            return

        if res.stdout:
            with open(os.path.join(date_dir, "Daily_Overall_Summary.md"), "w", encoding="utf-8") as f:
                f.write(res.stdout)
    except subprocess.TimeoutExpired:
        print(f"DEBUG: 日报生成超时 ({date_str})")
    except Exception as e:
        print(f"DEBUG: 日报生成错误: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(1)
    if sys.argv[1] == "report":
        update_daily_report(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "Gemini"); sys.exit(0)
        
    title, pdf_source, priority, storage_root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    date_fallback = sys.argv[5] if len(sys.argv) > 5 else datetime.now().strftime("%Y-%m-%d")
    engine = sys.argv[6] if len(sys.argv) > 6 else "Gemini"
    skip_report = (sys.argv[7].lower() == "true") if len(sys.argv) > 7 else False
    progress_label = sys.argv[8] if len(sys.argv) > 8 else ""
    
    # 归一化函数
    def normalize_title(t): return re.sub(r'[^a-zA-Z0-9]', '', t).lower()
    
    # 提取 PDF 文字以获取更精准的标题（防止 Swift 传来的只是文件名）
    print(f"PROGRESS: {progress_label} 正在预扫描 PDF 内容...")
    text = extract_text_from_pdf(pdf_source, max_pages=2)
    
    # 尝试从前几行提取真实标题
    extracted_title = title
    lines = [l.strip() for l in text.split('\n') if len(l.strip()) > 10]
    if lines: extracted_title = lines[0]
    
    target_prefix_orig = normalize_title(title)[:30]
    target_prefix_ext = normalize_title(extracted_title)[:30]
    
    # 执行查重
    if os.path.exists(os.path.join(storage_root, "papers")):
        for d in os.listdir(os.path.join(storage_root, "papers")):
            date_dir = os.path.join(storage_root, "papers", d)
            if not os.path.isdir(date_dir): continue
            for s in ["精读论文", "粗读论文", "manual"]:
                sub_dir = os.path.join(date_dir, s)
                if not os.path.exists(sub_dir): continue
                for folder in os.listdir(sub_dir):
                    norm_folder = normalize_title(folder)
                    if (target_prefix_orig and norm_folder.startswith(target_prefix_orig)) or \
                       (target_prefix_ext and norm_folder.startswith(target_prefix_ext)):
                        if os.path.exists(os.path.join(sub_dir, folder, "summary.md")):
                            print(f"EXIST_DATE:{d}")
                            print(f"PROGRESS: {progress_label} 该论文已存在于 {d} 文件夹，跳过"); sys.exit(0)
    
    print(f"PROGRESS: {progress_label} AI 正在分析并提取元数据...")
    
    # 智能处理：如果 PDF 过大，则尝试压缩后再发送给 AI
    processed_pdf = pdf_source
    is_temp_pdf = False
    if os.path.exists(pdf_source) and os.path.getsize(pdf_source) > 10 * 1024 * 1024:
        print(f"PROGRESS: {progress_label} PDF 过大 ({os.path.getsize(pdf_source)/1024/1024:.1f}MB)，正在执行 Ghostscript 压缩...")
        temp_compressed = os.path.join(os.path.dirname(pdf_source), "temp_compressed_" + os.path.basename(pdf_source))
        if compress_pdf(pdf_source, temp_compressed, power=2):
            processed_pdf = temp_compressed
            is_temp_pdf = True

    full_text = extract_text_from_pdf(processed_pdf)
    
    force_d = date_fallback if priority != "manual" else None
    summary, metadata = summarize_and_tag_paper(title, full_text, storage_root, engine, priority, force_date=force_d, pdf_path=processed_pdf)
    
    # 清理临时压缩文件
    if is_temp_pdf and os.path.exists(processed_pdf):
        try: os.remove(processed_pdf)
        except: pass
    
    if not summary:
        print(f"PROGRESS: {progress_label} ❌ AI 未能生成总结，请检查 API 配置或网络。")
        sys.exit(1)

    if summary:
        ai_extracted_date = metadata.get("extracted_date")
        # 如果有强制日期，则直接使用强制日期，忽略 AI 提取的结果
        doc_date = force_d if force_d else (ai_extracted_date if ai_extracted_date else date_fallback)
        
        print(f"DEBUG: AI extracted date: {ai_extracted_date}, Force date: {force_d}, Final date: {doc_date}")
        
        # 如果不是强制日期的，才需要校验格式
        if not force_d:
            if not doc_date or not re.match(r"\d{4}-\d{2}-\d{2}", doc_date) or doc_date > datetime.now().strftime("%Y-%m-%d"):
                doc_date = date_fallback
        
        actual_title = metadata.get("actual_title", title)
        sub_type = "manual" if priority.startswith("manual") else ("精读论文" if priority == "high" else "粗读论文")
        target_dir = os.path.join(storage_root, "papers", doc_date, sub_type, sanitize_filename(actual_title))
        
        print(f"DEBUG: Target directory: {target_dir}")
        try:
            os.makedirs(target_dir, exist_ok=True)
            shutil.copy2(pdf_source, os.path.join(target_dir, "paper.pdf")) if os.path.abspath(pdf_source) != os.path.abspath(os.path.join(target_dir, "paper.pdf")) else None
            with open(os.path.join(target_dir, "summary.md"), "w", encoding="utf-8") as f: f.write(summary)
            with open(os.path.join(target_dir, "metadata.json"), "w", encoding="utf-8") as f: json.dump(metadata, f, ensure_ascii=False, indent=4)
            print(f"PROGRESS: {progress_label} 文件已保存到: {target_dir}")
        except Exception as e:
            print(f"PROGRESS: {progress_label} ❌ 保存文件失败: {e}")
            sys.exit(1)
        
        if not skip_report and not priority.startswith("manual"):
            print(priority)
            update_daily_report(storage_root, doc_date, engine)
        
        print(f"PROGRESS: {progress_label} PAPER_DONE")
        print(f"RESULT_DATE:{doc_date}")
