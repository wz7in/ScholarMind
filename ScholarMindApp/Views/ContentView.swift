import SwiftUI
import PDFKit
import WebKit

struct ContentView: View {
    @StateObject private var dataManager = DataManager()
    @State private var readingPaper: Paper?
    @State private var isSyncing = false
    @State private var syncProgress = "同步今日论文"
    @State private var wasManuallyStopped = false
    @State private var activeTab: AppTab = .home
    @State private var currentProcess: Process? 
    @State private var selectedDate: String?
    @State private var expandedDates: Set<String> = []
    
    @State private var currentImportType: ManualImportView.ImportType = .file
    @State private var isImportingBlog = false
    @State private var blogImportStatus = ""
    @State private var showCookieAlert = false
    @State private var showLoginAlert = false
    @State private var showDuplicateAlert = false
    @State private var duplicateDate = ""
    @State private var isDockHovered = false
    
    @AppStorage("scholar_storage_path") private var storagePath = ""
    @AppStorage("scholar_proxy") private var savedProxy = ""
    @AppStorage("use_system_proxy") private var useSystemProxy = false
    @AppStorage("scholar_cookie") private var savedCookie = ""
    @AppStorage("selected_ai_engine") private var selectedEngine = "Gemini"
    @AppStorage("has_entered_app") private var hasEntered = false

    // 同步策略
    @AppStorage("max_daily_papers") private var maxDailyPapers = 15
    @AppStorage("high_score_threshold") private var highScoreThreshold = 0.8
    @AppStorage("min_likes_threshold") private var minLikesThreshold = 2
    @AppStorage("max_low_score_samples") private var maxLowScoreSamples = 2

    // 环境路径配置
    @AppStorage("python_path") private var pythonPath = ""
    @AppStorage("ai_cli_path") private var aiCliPath = ""

    enum AppTab { case home, library, categoryLibrary, blogs, importPaper, researchLab, settings }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                
                mainContentSwitcher
                    .blur(radius: readingPaper != nil ? 15 : 0)
                    .scaleEffect(readingPaper != nil ? 0.96 : 1.0)
                    .disabled(readingPaper != nil)
                    .ignoresSafeArea(.all, edges: .bottom)
                
                if activeTab != .home && readingPaper == nil {
                    floatingDock()
                        .padding(.bottom, 25)
                        .opacity(isDockHovered ? 1.0 : 0.05)
                        .scaleEffect(isDockHovered ? 1.0 : 0.9)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDockHovered)
                        .onHover { isDockHovered = $0 }
                }
                
                // 全局底部感应区 (收窄触发范围，防止遮挡内容或输入)
                if activeTab != .home && readingPaper == nil {
                    Color.clear
                        .frame(height: 10)
                        .contentShape(Rectangle())
                        .onHover { isDockHovered = $0 }
                }
                
                if let paper = readingPaper {
                    UnifiedReaderView(paper: paper, onClose: { withAnimation(.easeInOut(duration: 0.3)) { readingPaper = nil; dataManager.loadPapers() } }).environmentObject(dataManager).zIndex(10).transition(.move(edge: .trailing))
                }
            }
        }
        .onAppear { dataManager.loadPapers(); activeTab = .home }
        .alert(isPresented: $showCookieAlert) {
            Alert(
                title: Text("认证失败"),
                message: Text("Scholar Inbox 的 Cookie 已失效或不正确，请前往设置页面更新。"),
                primaryButton: .default(Text("前往设置")) {
                    activeTab = .settings
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
        .alert(isPresented: $showLoginAlert) {
            Alert(
                title: Text("AI 引擎未登录"),
                message: Text("检测到 \(selectedEngine) 尚未完成授权。请在终端运行 '\(selectedEngine.lowercased()) login' 完成登录，然后重试。"),
                dismissButton: .default(Text("知道了"))
            )
        }
        .alert(isPresented: $showDuplicateAlert) {
            Alert(
                title: Text("论文已存在"),
                message: Text("该论文此前已导入过，存放于 \(duplicateDate) 的归档目录中。"),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    @ViewBuilder
    private var mainContentSwitcher: some View {
        Group {
            switch activeTab {
            case .home: welcomeDashboard
            case .library: libraryMainView
            case .categoryLibrary: CategoryLibraryView(dataManager: dataManager, onSelectPaper: { p in withAnimation { readingPaper = p } }).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .blogs: blogListView
            case .importPaper: ManualImportView(dataManager: dataManager, importType: $currentImportType, onStart: { t, p, u, d, f, a in startManualImport(title: t, path: p, url: u, fallbackDate: d, isFolder: f, isAutoDate: a) }).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .researchLab: ResearchLabView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings: LoginView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private var libraryMainView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    ForEach(sortedDates.filter { date in
                        groupedPapers[date]?.contains(where: { $0.type == "paper" }) ?? false
                    }, id: \.self) { date in
                        DisclosureGroup(isExpanded: Binding(get: { expandedDates.contains(date) }, set: { if $0 { expandedDates.insert(date) } else { expandedDates.remove(date) } })) {
                            let papersForDate = groupedPapers[date]?.filter { $0.type == "paper" } ?? []
                            
                            // 1. 精读论文
                            let highPriority = papersForDate.filter { $0.priority == "high" }
                            if !highPriority.isEmpty {
                                subgroupSection(title: "精读", papers: highPriority, color: .orange)
                            }
                            
                            // 2. 粗读论文
                            let lowPriority = papersForDate.filter { $0.priority == "low" }
                            if !lowPriority.isEmpty {
                                if !highPriority.isEmpty { Divider().padding(.horizontal, 10).opacity(0.5) }
                                subgroupSection(title: "粗读", papers: lowPriority, color: .gray)
                            }
                            
                            // 3. 手动导入
                            let manualPriority = papersForDate.filter { $0.priority == "manual" }
                            if !manualPriority.isEmpty {
                                if !highPriority.isEmpty || !lowPriority.isEmpty { Divider().padding(.horizontal, 10).opacity(0.5) }
                                subgroupSection(title: "手动", papers: manualPriority, color: .blue)
                            }
                        } label: { 
                            let paperCount = groupedPapers[date]?.filter { $0.type == "paper" }.count ?? 0
                            let isSelected = selectedDate == date
                            
                            HStack { 
                                Image(systemName: "calendar").font(.system(size: 11))
                                Text(date).font(.system(size: 13, weight: isSelected ? .black : .bold))
                                Spacer()
                                Text("\(paperCount)").font(.system(size: 9)).foregroundColor(isSelected ? .white : .secondary) 
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue.opacity(0.8) : Color.clear)
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.spring()) { selectedDate = date } }
                            .contextMenu {
                                Button {
                                    regenerateReport(for: date)
                                } label: {
                                    Label("重新生成该日日报", systemImage: "arrow.clockwise.doc.fill")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    dataManager.deleteDateFolder(date: date)
                                } label: {
                                    Label("删除该日所有内容", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar).scrollContentBackground(.hidden)
                
                Spacer(minLength: 20)
                
                syncSection.padding(.bottom, 25).padding(.top, 10).background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6)).padding(.leading, 12).navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 350)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { withAnimation { dataManager.loadPapers() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新本地论文文件")
                }
            }
        } detail: {
            ZStack(alignment: .top) { if let date = selectedDate, let daily = findDailySummary(for: date) { DailyReportHomeView(paper: daily).id(date) } else { emptyStateView } }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var blogListView: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .bottom) { Text("博闻笔记").font(.system(size: 32, weight: .black)); Text("\(dataManager.papers.filter { $0.type == "blog" }.count) 篇收藏").font(.headline).foregroundColor(.secondary).padding(.leading, 10).padding(.bottom, 5) }.padding(.top, 40)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 25)], spacing: 25) {
                        ForEach(dataManager.papers.filter { $0.type == "blog" }) { blog in
                            Button(action: { withAnimation { readingPaper = blog } }) { blogCard(blog: blog) }
                            .buttonStyle(.plain).contextMenu { Button(role: .destructive) { dataManager.deleteItem(blog) } label: { Label("删除", systemImage: "trash") } }
                        }
                    }
                    Spacer().frame(height: 120)
                }.padding(.horizontal, 40)
            }
            HStack(spacing: 12) {
                if isImportingBlog { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(blogImportStatus).font(.system(size: 12, weight: .bold)) }.padding(.horizontal, 15).padding(.vertical, 10).background(.ultraThinMaterial).cornerRadius(20) }
                else { Button(action: { withAnimation { currentImportType = .url; activeTab = .importPaper } }) { HStack { Image(systemName: "plus.circle.fill"); Text("添加博文") }.padding(.horizontal, 15).padding(.vertical, 10).background(Color.green).foregroundColor(.white).cornerRadius(20) }.buttonStyle(.plain) }
            }.padding(30)
        }
    }

    private func blogCard(blog: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "safari.fill").foregroundColor(.green); Text(blog.date).font(.caption).foregroundColor(.secondary); Spacer(); Text("BLOG").font(.system(size: 8, weight: .black)).padding(4).background(Color.green.opacity(0.1)).cornerRadius(4) }
            Text(blog.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            HStack { 
                if let cat = blog.category, cat != "博文笔记" { Text(cat).font(.system(size: 9)).padding(4).background(Color.purple.opacity(0.1)).foregroundColor(.purple).cornerRadius(4) }
                ForEach(blog.tags?.prefix(2) ?? [], id: \.self) { tag in Text(tag).font(.system(size: 9)).padding(4).background(Color.blue.opacity(0.08)).cornerRadius(4) } 
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(NSColor.controlBackgroundColor).opacity(0.5)).cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }

    private var welcomeDashboard: some View {
        ZStack {
            ZStack { Circle().fill(Color.blue.opacity(0.12)).frame(width: 600, height: 600).blur(radius: 80).offset(x: -200, y: -200); Circle().fill(Color.purple.opacity(0.1)).frame(width: 500, height: 500).blur(radius: 90).offset(x: 250, y: 200) }
            VStack(spacing: 50) {
                VStack(spacing: 15) { Image(systemName: "brain.head.profile").font(.system(size: 80, weight: .ultraLight)).foregroundStyle(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .top, endPoint: .bottom)); Text("ScholarMind").font(.system(size: 64, weight: .black, design: .rounded)); Text("下一代 AI 驱动的个人科研情报中心").font(.title3).foregroundColor(.secondary).italic() }.padding(.top, 40)
                LazyVGrid(columns: [GridItem(.fixed(220), spacing: 25), GridItem(.fixed(220), spacing: 25), GridItem(.fixed(220), spacing: 25)], spacing: 25) {
                    dashCard(title: "每日研究", subtitle: "查看今日日报与论文", icon: "book.closed.fill", color: .blue) { enterApp(to: .library); autoSelectLatestDate() }
                    dashCard(title: "知识图谱", subtitle: "多维交叉领域检索", icon: "square.grid.3x3.fill", color: .indigo) { enterApp(to: .categoryLibrary) }
                    dashCard(title: "博闻笔记", subtitle: "网页/博客精读总结", icon: "safari.fill", color: .green) { enterApp(to: .blogs) }
                    dashCard(title: "导入资料", subtitle: "PDF/文件夹/URL", icon: "plus.viewfinder", color: .purple) { currentImportType = .file; enterApp(to: .importPaper) }
                    dashCard(title: "灵感实验室", subtitle: "对话孵化与 Idea 生成", icon: "lightbulb.fill", color: .orange) { enterApp(to: .researchLab) }
                    dashCard(title: "系统设置", subtitle: "路径与代理配置", icon: "gearshape.fill", color: .gray) { enterApp(to: .settings) }
                }
                Spacer(); HStack(spacing: 15) { Circle().fill(Color.green).frame(width: 8, height: 8); Text("论文: \(dataManager.papers.filter{$0.type == "paper"}.count) | 博客: \(dataManager.papers.filter{$0.type == "blog"}.count)").font(.caption).foregroundColor(.secondary); Text("|"); Text("AI 引擎: \(selectedEngine)").font(.caption).foregroundColor(.secondary) }.padding(.bottom, 30)
            }
        }
    }

    private func dashCard(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(alignment: .leading, spacing: 12) { Image(systemName: icon).font(.title).foregroundColor(color); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundColor(.primary); Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(RoundedRectangle(cornerRadius: 22).fill(Color(NSColor.controlBackgroundColor).opacity(0.4))).overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.2), lineWidth: 1)).shadow(color: .black.opacity(0.03), radius: 10, y: 5) }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func subgroupSection(title: String, papers: [Paper], color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(color.opacity(0.12))
                .foregroundColor(color)
                .cornerRadius(3)
            Spacer()
        }
        .padding(.leading, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        
        ForEach(papers) { paper in
            paperRow(for: paper, accentColor: color)
        }
    }

    private func enterApp(to tab: AppTab) { withAnimation(.spring()) { hasEntered = true; activeTab = tab } }
    private func autoSelectLatestDate() { if let latest = sortedDates.first { selectedDate = latest } }
    
    private func paperRow(for paper: Paper, accentColor: Color) -> some View { 
        VStack(alignment: .leading, spacing: 6) { 
            HStack(spacing: 6) { 
                if paper.priority == "high" { 
                    Image(systemName: "star.fill").foregroundColor(.orange).font(.system(size: 10)) 
                } else if paper.priority == "manual" { 
                    Image(systemName: "tray.and.arrow.down.fill").foregroundColor(.blue).font(.system(size: 10)) 
                } else {
                    Image(systemName: "circle.fill").foregroundColor(.gray.opacity(0.5)).font(.system(size: 7))
                }
                Text(paper.title).lineLimit(1).font(.system(size: 13, weight: paper.priority == "high" ? .bold : .semibold)).foregroundColor(.primary) 
            }
            
            HStack(spacing: 4) { 
                if let cat = paper.category, cat != "未分类" { 
                    Text(cat).font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1).background(Color.purple.opacity(0.1)).foregroundColor(.purple).cornerRadius(4) 
                }
                if let tags = paper.tags, !tags.isEmpty { 
                    ForEach(tags.prefix(3), id: \.self) { tag in 
                        Text(tag).font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 1).background(Color.blue.opacity(0.08)).foregroundColor(.blue).cornerRadius(4) 
                    } 
                } 
            } 
        }
        .padding(.vertical, 10).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .background(accentColor.opacity(0.03)) // 背景只加在行内，不再包裹整个组
        .cornerRadius(8)
        .padding(.horizontal, 8)
        .onTapGesture { withAnimation(.easeInOut) { readingPaper = paper } }
        .contextMenu {
            Button(role: .destructive) {
                dataManager.deleteItem(paper)
            } label: {
                Label("物理删除", systemImage: "trash")
            }
        }
    }
    
    private var syncSection: some View {
        HStack(spacing: 8) {
            Button(action: { syncPapers() }) { HStack { if isSyncing { ProgressView().controlSize(.small).padding(.trailing, 5) } else { Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)) }; Text(syncProgress).font(.system(size: 11, weight: .bold)) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(LinearGradient(gradient: Gradient(colors: [isSyncing ? .orange : .blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing)).foregroundColor(.white).cornerRadius(10) }.buttonStyle(.plain).disabled(isSyncing || storagePath.isEmpty)
            if isSyncing { Button(action: stopGeneration) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red.opacity(0.8)) }.buttonStyle(.plain) }
        }.padding(.horizontal, 12)
    }

    private func floatingDock() -> some View {
        HStack(spacing: 20) {
            DockItem(icon: "book.closed.fill", label: "学术库", isActive: activeTab == .library) { withAnimation { activeTab = .library } }
            DockItem(icon: "square.grid.3x3.fill", label: "图谱", isActive: activeTab == .categoryLibrary) { withAnimation { activeTab = .categoryLibrary } }
            DockItem(icon: "safari.fill", label: "博闻", isActive: activeTab == .blogs) { withAnimation { activeTab = .blogs } }
            DockItem(icon: "plus.viewfinder", label: "添加", isActive: activeTab == .importPaper) { withAnimation { currentImportType = .file; activeTab = .importPaper } }
            DockItem(icon: "brain.head.profile", label: "实验室", isActive: activeTab == .researchLab) { withAnimation { activeTab = .researchLab } }
            DockItem(icon: "gearshape.fill", label: "设置", isActive: activeTab == .settings) { withAnimation { activeTab = .settings } }
        }.padding(.horizontal, 25).padding(.vertical, 12).background(.ultraThinMaterial).clipShape(Capsule()).shadow(color: .black.opacity(0.15), radius: 15, y: 10)
    }

    func stopGeneration() { 
        wasManuallyStopped = true
        currentProcess?.terminate(); isSyncing = false; isImportingBlog = false; syncProgress = "已中断"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.syncProgress = "同步今日论文" } 
    }

    private func getScriptPath(_ name: String) -> String {
        // 1. 优先从 App Bundle 内部查找 (Xcode 打包后的位置)
        // 第一顺位：scripts 子目录下 (蓝色文件夹模式)
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "py", inDirectory: "scripts") { 
            print("[Debug] 在 Bundle(scripts/) 中找到脚本: \(bundlePath)")
            return bundlePath 
        }
        // 第二顺位：根目录下 (黄色文件夹模式)
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "py") {
            print("[Debug] 在 Bundle 根目录找到脚本: \(bundlePath)")
            return bundlePath
        }
        
        // 2. 备选方案：从用户设置的存储目录查找
        if !storagePath.isEmpty {
            let userScriptPath = URL(fileURLWithPath: storagePath).appendingPathComponent("scripts/\(name).py").path
            if FileManager.default.fileExists(atPath: userScriptPath) {
                print("[Debug] 在存储路径中找到脚本: \(userScriptPath)")
                return userScriptPath
            }
            // 兼容性查找：storagePath 直接目录下
            let userScriptPathAlt = URL(fileURLWithPath: storagePath).appendingPathComponent("\(name).py").path
            if FileManager.default.fileExists(atPath: userScriptPathAlt) {
                print("[Debug] 在存储路径根目录中找到脚本: \(userScriptPathAlt)")
                return userScriptPathAlt
            }
            print("[Debug] 尝试查找所有可能路径失败")
        }
        
        print("[Debug] ❌ 警告: 无法在任何地方找到脚本 \(name).py")
        return ""
    }

    func startManualImport(title: String, path: String, url: String, fallbackDate: String, isFolder: Bool, isAutoDate: Bool) {
        let effectiveProxy = useSystemProxy ? "" : savedProxy
        if !url.isEmpty && !url.contains("arxiv.org") {
            withAnimation { activeTab = .blogs; isImportingBlog = true; blogImportStatus = "抓取中..." }
            let scriptPath = getScriptPath("blog_processor")
            DispatchQueue.global().async {
                let process = Process(); process.executableURL = URL(fileURLWithPath: pythonPath); process.arguments = [scriptPath, url, storagePath, selectedEngine]
                self.currentProcess = process; var env = ProcessInfo.processInfo.environment
                if !effectiveProxy.isEmpty { env["HTTP_PROXY"] = effectiveProxy; env["HTTPS_PROXY"] = effectiveProxy; env["ALL_PROXY"] = effectiveProxy }; process.environment = env
                try? process.run(); process.waitUntilExit()
                DispatchQueue.main.async { self.isImportingBlog = false; self.currentProcess = nil; self.dataManager.loadPapers() }
            }
        } else {
            withAnimation { activeTab = .library; isSyncing = true; syncProgress = "下载论文中..." }
            let scriptPath = getScriptPath("processor")
            DispatchQueue.global(qos: .userInitiated).async {
                var tasks: [(String, String)] = []
                if isFolder { if let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) { let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }; for pdf in pdfs { tasks.append((pdf.deletingPathExtension().lastPathComponent, pdf.path)) } } } 
                else if !url.isEmpty { let downloadedPath = downloadFromUrl(url); if !downloadedPath.isEmpty { tasks.append((title, downloadedPath)) } } 
                else { tasks.append((title, path)) }
                
                let priority = isAutoDate ? "manual" : "manual_force"
                
                for (index, task) in tasks.enumerated() {
                    if !self.isSyncing { break }
                    let progressLabel = "[\(index+1)/\(tasks.count)]"
                    DispatchQueue.main.async { 
                        self.syncProgress = "\(progressLabel) 正在进行分论文总结和归档..."
                        self.duplicateDate = "" // 每次开始前重置
                    }
                    
                    let process = Process(); process.executableURL = URL(fileURLWithPath: pythonPath); process.arguments = ["-u", scriptPath, task.0, task.1, priority, storagePath, fallbackDate, selectedEngine, "true", progressLabel]
                    self.currentProcess = process; let pipe = Pipe(); process.standardOutput = pipe
                    var env = ProcessInfo.processInfo.environment; 
                    env["AI_CLI_PATH"] = aiCliPath
                    if !effectiveProxy.isEmpty { env["HTTP_PROXY"] = effectiveProxy; env["HTTPS_PROXY"] = effectiveProxy; env["ALL_PROXY"] = effectiveProxy; env["SCHOLAR_PROXY"] = effectiveProxy }
                    process.environment = env
                    
                    // 监听输出以查找 EXIST_DATE
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if let out = String(data: data, encoding: .utf8) {
                            print("[Import Output]: \(out)")
                            if let range = out.range(of: "EXIST_DATE:([0-9-]{10})", options: .regularExpression) {
                                let dateStr = String(out[range]).replacingOccurrences(of: "EXIST_DATE:", with: "")
                                DispatchQueue.main.async {
                                    self.duplicateDate = dateStr
                                    self.showDuplicateAlert = true
                                }
                            }
                        }
                    }
                    
                    try? process.run(); 
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil // 清理监听
                    DispatchQueue.main.async { self.dataManager.loadPapers() }
                }
                DispatchQueue.main.async { self.isSyncing = false; self.currentProcess = nil; self.dataManager.loadPapers(); self.syncProgress = "完成"; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.syncProgress = "同步今日论文" } }
            }
        }
    }

    private func downloadFromUrl(_ url: String) -> String {
        let effectiveProxy = useSystemProxy ? "" : savedProxy
        var finalUrl = url; if url.contains("arxiv.org/abs/") { finalUrl = url.replacingOccurrences(of: "/abs/", with: "/pdf/") + ".pdf" }
        let tempPath = NSTemporaryDirectory() + UUID().uuidString + ".pdf"; let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/curl"); process.arguments = ["-L", "-o", tempPath, finalUrl]
        if !effectiveProxy.isEmpty { var env = ProcessInfo.processInfo.environment; env["HTTP_PROXY"] = effectiveProxy; env["HTTPS_PROXY"] = effectiveProxy; process.environment = env }
        try? process.run(); process.waitUntilExit(); return FileManager.default.fileExists(atPath: tempPath) ? tempPath : ""
    }

    func syncPapers() {
        guard !storagePath.isEmpty else { activeTab = .settings; return }
        
        let scriptPath = getScriptPath("fetcher")
        if scriptPath.isEmpty {
            self.syncProgress = "❌ 找不到 fetcher.py 脚本"
            print("[Swift] 错误: 无法定位同步脚本。请确保 scripts 文件夹已加入 Xcode 资源或存放在存储目录中。")
            return
        }

        isSyncing = true
        wasManuallyStopped = false
        syncProgress = "准备同步..."
        print("[Swift] 开始同步, Engine: \(selectedEngine), Script: \(scriptPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        let effectiveProxy = useSystemProxy ? "" : savedProxy
        process.arguments = [
            "-u", scriptPath, 
            savedCookie, 
            effectiveProxy, 
            storagePath, 
            selectedEngine,
            String(maxDailyPapers),
            String(highScoreThreshold),
            String(minLikesThreshold),
            String(maxLowScoreSamples)
        ]
        self.currentProcess = process
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(aiCliPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
        env["AI_CLI_PATH"] = aiCliPath
        if !effectiveProxy.isEmpty {
            env["HTTP_PROXY"] = effectiveProxy
            env["HTTPS_PROXY"] = effectiveProxy
            env["ALL_PROXY"] = effectiveProxy
            env["http_proxy"] = effectiveProxy
            env["https_proxy"] = effectiveProxy
            env["all_proxy"] = effectiveProxy
            env["SCHOLAR_PROXY"] = effectiveProxy
        }
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let out = String(data: data, encoding: .utf8) {
                print("[Python Output]: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
                for line in out.components(separatedBy: .newlines) where line.starts(with: "PROGRESS:") {
                    let msg = line.replacingOccurrences(of: "PROGRESS:", with: "").trimmingCharacters(in: .whitespaces)
                    DispatchQueue.main.async {
                        if msg == "PAPER_DONE" || msg.contains("完成") {
                            self.dataManager.loadPapers()
                        } else if msg.contains("API返回异常: 401") {
                            self.syncProgress = "同步失败 (401)"
                            self.showCookieAlert = true
                            self.isSyncing = false
                        } else if msg.contains("AI 引擎未登录") {
                            self.syncProgress = "❌ 未登录"
                            self.showLoginAlert = true
                            self.isSyncing = false
                        } else {
                            self.syncProgress = msg
                        }
                    }
                }
            }
        }
        
        process.terminationHandler = { p in
            DispatchQueue.main.async {
                print("[Swift] 同步进程结束, ExitCode: \(p.terminationStatus)")
                // 清理 readabilityHandler 防止异步冲突
                pipe.fileHandleForReading.readabilityHandler = nil
                
                self.isSyncing = false
                self.currentProcess = nil
                
                if !self.wasManuallyStopped {
                    self.syncProgress = "同步完成"
                    print("[Swift] 按钮文本已设为: \(self.syncProgress)")
                }
                
                self.dataManager.loadPapers()
                self.autoSelectLatestDate()
                
                // 确保重置逻辑执行
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("[Swift] 触发定时重置按钮文本")
                    withAnimation {
                        self.syncProgress = "同步今日论文"
                    }
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            print("[Swift] 启动同步进程失败: \(error)")
            isSyncing = false
            syncProgress = "启动失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.syncProgress = "同步今日论文"
            }
        }
    }

    func regenerateReport(for date: String) {
        guard !storagePath.isEmpty else { return }
        isSyncing = true
        wasManuallyStopped = false
        syncProgress = "补充 \(date) 日报..."
        
        let scriptPath = getScriptPath("processor")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-u", scriptPath, "report", storagePath, date, selectedEngine]
        self.currentProcess = process
        
        let effectiveProxy = useSystemProxy ? "" : savedProxy
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(aiCliPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
        env["AI_CLI_PATH"] = aiCliPath
        if !effectiveProxy.isEmpty {
            env["HTTP_PROXY"] = effectiveProxy
            env["HTTPS_PROXY"] = effectiveProxy
            env["ALL_PROXY"] = effectiveProxy
            env["http_proxy"] = effectiveProxy
            env["https_proxy"] = effectiveProxy
            env["all_proxy"] = effectiveProxy
            env["SCHOLAR_PROXY"] = effectiveProxy
        }
        process.environment = env
        
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.isSyncing = false
                self.currentProcess = nil
                self.syncProgress = "完成"
                self.dataManager.loadPapers()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.syncProgress = "同步今日论文"
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            print("Failed to run report regeneration: \(error)")
            isSyncing = false
            syncProgress = "重试失败"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.syncProgress = "同步今日论文"
            }
        }
    }

    private var sortedDates: [String] { Array(Set(dataManager.papers.map { $0.date })).sorted(by: >) }
    private var groupedPapers: [String: [Paper]] { Dictionary(grouping: dataManager.papers, by: { $0.date }) }
    private func findDailySummary(for date: String) -> Paper? { guard !storagePath.isEmpty else { return nil }; let path = URL(fileURLWithPath: storagePath).appendingPathComponent("papers/\(date)/Daily_Overall_Summary.md").path; if FileManager.default.fileExists(atPath: path) { return Paper(title: "今日日报 - \(date)", date: date, pdfPath: "", summaryPath: path, timestamp: date, priority: "high", tags: [], category: nil, datasets: [], short_comment: nil, type: "paper") }; return nil }
    private var emptyStateView: some View { VStack(spacing: 25) { Spacer(); Image(systemName: "brain.head.profile").font(.system(size: 80, weight: .ultraLight)).foregroundStyle(LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .top, endPoint: .bottom)); Text("ScholarMind").font(.system(size: 42, weight: .black, design: .rounded)); Text("请从左侧选择一个日期查看科研日报").foregroundColor(.secondary); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct DockItem: View {
    let icon: String; let label: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 20, weight: isActive ? .bold : .medium)).foregroundColor(isActive ? .blue : .secondary); Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(isActive ? .blue : .secondary) }.scaleEffect(isActive ? 1.1 : 1.0)
        }.buttonStyle(.plain)
    }
}

struct DailyReportHomeView: View {
    let paper: Paper
    @State private var content = ""
    @State private var isEditing = false
    @State private var editableContent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { 
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundColor(.orange)
                Text(paper.title).font(.title2).bold()
                
                Spacer()
                
                if isEditing {
                    Button("取消") { isEditing = false; editableContent = content }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("完成保存") { saveEditedReport() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button(action: { isEditing = true; editableContent = content }) {
                        Label("编辑日报", systemImage: "pencil.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(.top, 25).padding(.horizontal)
            
            Divider().padding(.top, 10)
            
            if isEditing {
                TextEditor(text: $editableContent)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(20)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.03))
            } else {
                MarkdownWebView(markdown: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(content.hashValue)
            }
        }
        .onAppear { if let d = try? String(contentsOfFile: paper.summaryPath, encoding: .utf8) { content = d } }
    }

    private func saveEditedReport() {
        guard !paper.summaryPath.isEmpty else { return }
        try? editableContent.write(to: URL(fileURLWithPath: paper.summaryPath), atomically: true, encoding: .utf8)
        content = editableContent
        isEditing = false
    }
}
