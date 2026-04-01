import SwiftUI
import Combine

struct ResearchLabView: View {
    @AppStorage("scholar_storage_path") private var storagePath = ""
    @AppStorage("scholar_proxy") private var savedProxy = ""
    @AppStorage("selected_ai_engine") private var selectedEngine = "Gemini"
    
    // 环境路径配置
    @AppStorage("python_path") private var pythonPath = ""
    @AppStorage("ai_cli_path") private var aiCliPath = ""
    
    @State private var chatHistory: [ChatMessage] = []
    @State private var generatingIdea = false
    @State private var latestIdeaMarkdown = ""
    @State private var proposalsHistory: [String] = [] 
    @State private var diaryHistory: [String] = [] 
    @State private var inputText = ""
    @State private var isGeneratingChat = false
    @State private var displayMode: DisplayMode = .notebook
    @State private var isChromeSyncEnabled = false
    @State private var currentFilePath: String? = nil
    @State private var isEditing = false
    @State private var editableContent = ""

    enum DisplayMode { case notebook, proposal, diary }

    struct ChatMessage: Identifiable, Codable {
        let id: UUID; let text: String; let isUser: Bool; let date: String
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // --- 左侧：控制台 (320px) ---
                VStack(spacing: 25) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("实验室控制台").font(.system(size: 20, weight: .black))
                        Text("灵感孵化与报告管理").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 操作按钮组
                    VStack(spacing: 12) {
                        if displayMode != .notebook {
                            Button(action: { withAnimation { displayMode = .notebook } }) {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                    Text("返回聊天")
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: { generateIdea() }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("生成深度研究报告")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.orange).foregroundColor(.white).cornerRadius(10)
                        }
                        .buttonStyle(.plain).disabled(generatingIdea)
                        
                        Button(action: { saveAsDiary() }) {
                            HStack {
                                Image(systemName: "book.closed.fill")
                                Text("今日对话存为日记")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2)).foregroundColor(.primary).cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Toggle(isOn: $isChromeSyncEnabled) {
                            HStack {
                                Image(systemName: "safari.fill")
                                Text("同步 Chrome 浏览足迹")
                            }.font(.caption).bold()
                        }.toggleStyle(.switch).padding(.top, 5)
                    }
                    
                    // 双列表区域
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("灵感日记", systemImage: "book.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                            historyList(items: diaryHistory, icon: "text.book.closed.fill", color: .blue, type: "diary") { dateStr in loadDiaryFile(dateStr) }
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Label("科研报告", systemImage: "doc.text.below.ecg.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                            historyList(items: proposalsHistory, icon: "doc.text.fill", color: .orange, type: "proposal") { dateStr in loadIdeaFile(dateStr) }
                        }
                    }
                    
                    Spacer()
                }
                .padding(25)
                .frame(width: 320)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
                
                Divider()

                // --- 右侧：工作区 ---
                VStack(spacing: 0) {
                    if displayMode == .notebook {
                        notebookView
                    } else {
                        fileView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }
        }
        .onAppear {
            loadTodayChat()
            loadProposalsHistory()
        }
    }

    private var notebookView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 25) {
                        if chatHistory.isEmpty {
                            VStack(spacing: 20) {
                                ZStack {
                                    Circle().fill(Color.blue.opacity(0.05)).frame(width: 80, height: 80)
                                    Image(systemName: "brain.head.profile").font(.system(size: 32)).foregroundColor(.blue.opacity(0.6))
                                }
                                Text("科研灵感实验室").font(.system(size: 24, weight: .bold))
                                Text("记录瞬时的科研火花，AI 将协助您深度孵化 Idea\n当天的对话将自动保存，您可以随时回来继续讨论").font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 150)
                        }
                        
                        ForEach(chatHistory) { msg in
                            LabChatBubble(msg: msg)
                                .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
                        }
                        
                        if isGeneratingChat {
                            LabThinkingBubble()
                        }
                        
                        // 滚动锚点
                        Spacer().frame(height: 1).id("bottomAnchor")
                    }
                    .padding(.horizontal, 40).padding(.top, 50) 
                }
                .onChange(of: chatHistory.count) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) { scrollProxy.scrollTo("bottomAnchor", anchor: .bottom) }
                    }
                }
                .onChange(of: isGeneratingChat) { newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) { scrollProxy.scrollTo("bottomAnchor", anchor: .bottom) }
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollProxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
            }
            .background(Color.white)
            
            Divider()

            // 底部输入区
            HStack(spacing: 15) {
                TextField("输入您的科研想法或观察...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(12)
                    .onSubmit { if !inputText.isEmpty && !isGeneratingChat { sendMessage() } }
                
                Button(action: sendMessage) {
                    ZStack {
                        Circle().fill(inputText.isEmpty ? Color.gray.opacity(0.2) : Color.blue)
                            .frame(width: 38, height: 38)
                        if isGeneratingChat {
                            ProgressView().controlSize(.small).colorInvert()
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isGeneratingChat)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 25)
            .background(Color.white)
        }
    }

    private var fileView: some View {
        VStack(spacing: 0) {
            HStack {
                Label(displayMode == .proposal ? "科研报告" : "灵感日记", systemImage: displayMode == .proposal ? "doc.text.fill" : "book.fill")
                    .font(.system(size: 15, weight: .bold))
                
                Spacer()
                
                HStack(spacing: 15) {
                    if isEditing {
                        Button("取消") { isEditing = false; editableContent = latestIdeaMarkdown }
                            .buttonStyle(.bordered)
                        Button("保存修改") { saveEditedFile() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: { isEditing = true; editableContent = latestIdeaMarkdown }) {
                            Label("编辑内容", systemImage: "pencil.circle.fill")
                        }.buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 25).padding(.vertical, 15)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            if generatingIdea {
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("正在孵化深度科研蓝图...").font(.headline).foregroundColor(.secondary)
                }.frame(maxHeight: .infinity)
            } else {
                if isEditing {
                    TextEditor(text: $editableContent)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(20)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.5))
                } else {
                    MarkdownWebView(markdown: latestIdeaMarkdown)
                        .id(latestIdeaMarkdown.hashValue)
                        .background(Color.clear)
                }
            }
        }
    }

    private func saveEditedFile() {
        guard let path = currentFilePath else { return }
        try? editableContent.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        latestIdeaMarkdown = editableContent
        isEditing = false
        loadProposalsHistory()
    }

    private func getScriptPath(_ name: String) -> String {
        // 1. 优先从 App Bundle 内部查找
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "py", inDirectory: "scripts") { 
            print("[Debug] 在 Bundle(scripts/) 中找到脚本: \(bundlePath)")
            return bundlePath 
        }
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "py") {
            print("[Debug] 在 Bundle 根目录找到脚本: \(bundlePath)")
            return bundlePath
        }
        
        // 2. 备选方案：从存储目录查找
        if !storagePath.isEmpty {
            let userScriptPath = URL(fileURLWithPath: storagePath).appendingPathComponent("scripts/\(name).py").path
            if FileManager.default.fileExists(atPath: userScriptPath) {
                print("[Debug] 在存储路径中找到脚本: \(userScriptPath)")
                return userScriptPath
            }
            let userScriptPathAlt = URL(fileURLWithPath: storagePath).appendingPathComponent("\(name).py").path
            if FileManager.default.fileExists(atPath: userScriptPathAlt) {
                print("[Debug] 在存储路径根目录中找到脚本: \(userScriptPathAlt)")
                return userScriptPathAlt
            }
        }
        
        print("[Debug] ❌ 警告: 无法在任何地方找到脚本 \(name).py")
        return ""
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let userMsg = ChatMessage(id: UUID(), text: inputText, isUser: true, date: Date().description)
        
        withAnimation {
            chatHistory.append(userMsg)
            isGeneratingChat = true
        }
        saveHistory() 
        
        let query = inputText; inputText = ""; 
        let chromePath = getScriptPath("chrome_importer")
        
        if chromePath.isEmpty {
            chatHistory.append(ChatMessage(id: UUID(), text: "❌ 错误: 找不到 chrome_importer.py 脚本。请在设置中配置正确的存储路径。", isUser: false, date: Date().description))
            isGeneratingChat = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var chromeContext = ""
            if isChromeSyncEnabled {
                let chromeProcess = Process(); chromeProcess.executableURL = URL(fileURLWithPath: pythonPath)
                chromeProcess.arguments = [chromePath, "list", "2"]
                let pipe = Pipe(); chromeProcess.standardOutput = pipe
                try? chromeProcess.run(); chromeProcess.waitUntilExit()
                if let data = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                   let jsonData = data.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    chromeContext = "\n【用户近 2 天 Chrome 浏览背景】:\n"
                    if let searches = json["searches"] as? [[String: String]] {
                        chromeContext += "- 搜索: " + searches.prefix(5).map { $0["query"] ?? "" }.joined(separator: ", ") + "\n"
                    }
                    if let visits = json["visits"] as? [[String: String]] {
                        chromeContext += "- 访问: " + visits.prefix(8).map { $0["title"] ?? "" }.joined(separator: " | ") + "\n"
                    }
                }
            }

            let prompt = """
            你是一位深度科研伙伴。
            背景资料：
            \(chromeContext)
            
            用户刚才说：'\(query)'。
            请你以学术导师的身份，结合可能的浏览背景（如果有），对其进行深入探讨、提出挑战或完善建议。字数不限，重在启发。
            """

            let process = Process()
            let binName = selectedEngine.lowercased()
            let aiCliUrl = URL(fileURLWithPath: aiCliPath).appendingPathComponent(binName)
            process.executableURL = URL(fileURLWithPath: aiCliUrl.path)
            
            if binName == "codex" {
                process.arguments = ["exec", "--skip-git-repo-check", prompt]
            } else {
                process.arguments = ["-p", prompt]
            }

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(aiCliPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
            if !savedProxy.isEmpty { 
                env["HTTP_PROXY"] = savedProxy; env["HTTPS_PROXY"] = savedProxy; env["ALL_PROXY"] = savedProxy
            }
            process.environment = env
            
            let pipe = Pipe(); process.standardOutput = pipe
            try? process.run(); process.waitUntilExit()
            if let reply = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                DispatchQueue.main.async {
                    withAnimation(.spring()) {
                        chatHistory.append(ChatMessage(id: UUID(), text: reply.trimmingCharacters(in: .whitespacesAndNewlines), isUser: false, date: Date().description))
                        isGeneratingChat = false
                    }
                    saveHistory()
                }
            } else {
                DispatchQueue.main.async { isGeneratingChat = false }
            }
        }
    }

    private func saveAsDiary() {
        let todayStr = DateFormatter(); todayStr.dateFormat = "yyyy-MM-dd"
        let dateStr = todayStr.string(from: Date())
        let dir = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        var content = "# 灵感随笔日记 - \(dateStr)\n\n"
        for msg in chatHistory {
            let role = msg.isUser ? "## 我的灵感" : "## AI 启发"
            content += "\(role)\n\(msg.text)\n\n---\n\n"
        }
        
        let path = dir.appendingPathComponent("diary.md")
        try? content.write(to: path, atomically: true, encoding: .utf8)
        
        // 关键：保存后清空当前对话，开启“全新界面”
        withAnimation {
            self.chatHistory = []
            self.displayMode = .notebook
        }
        saveHistory() 
        loadProposalsHistory()
    }

    private func generateIdea() {
        let enginePath = getScriptPath("idea_engine")
        let chromePath = getScriptPath("chrome_importer")
        
        if enginePath.isEmpty {
            latestIdeaMarkdown = "❌ **错误**: 找不到 `idea_engine.py` 脚本。\n请确保已在设置中配置了正确的存储路径，或者该脚本已包含在 App 资源中。"
            generatingIdea = false; displayMode = .proposal
            return
        }

        generatingIdea = true; latestIdeaMarkdown = ""; displayMode = .proposal
        
        DispatchQueue.global(qos: .userInitiated).async {
            var chromeJson = ""
            if isChromeSyncEnabled && !chromePath.isEmpty {
                let chromeProcess = Process(); chromeProcess.executableURL = URL(fileURLWithPath: pythonPath)
                chromeProcess.arguments = [chromePath, "list", "2"]
                let pipe = Pipe(); chromeProcess.standardOutput = pipe
                try? chromeProcess.run(); chromeProcess.waitUntilExit()
                if let data = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    chromeJson = data.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            let process = Process(); process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-u", enginePath, "generate", storagePath, savedProxy, selectedEngine, chromeJson]
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(aiCliPath):/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
            process.environment = env
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try? process.run(); process.waitUntilExit()
            if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                DispatchQueue.main.async { 
                    self.latestIdeaMarkdown = output
                    self.generatingIdea = false
                    loadProposalsHistory() 
                }
            }
        }
    }

    private func saveHistory() {
        let todayStr = DateFormatter(); todayStr.dateFormat = "yyyy-MM-dd"
        let dir = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(todayStr.string(from: Date()))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(chatHistory) { try? data.write(to: dir.appendingPathComponent("chat_history.json")) }
    }

    private func loadTodayChat() {
        let todayStr = DateFormatter(); todayStr.dateFormat = "yyyy-MM-dd"
        let path = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(todayStr.string(from: Date()))/chat_history.json")
        if let data = try? Data(contentsOf: path), let history = try? JSONDecoder().decode([ChatMessage].self, from: data) { self.chatHistory = history }
    }

    private func loadProposalsHistory() {
        var pHistory: [String] = []
        var dHistory: [String] = []
        let today = Date()
        for i in 0..<15 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let dateStr = f.string(from: date)
            let pPath = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)/proposals.md")
            if FileManager.default.fileExists(atPath: pPath.path) { pHistory.append(dateStr) }
            let dPath = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)/diary.md")
            if FileManager.default.fileExists(atPath: dPath.path) { dHistory.append(dateStr) }
        }
        self.proposalsHistory = pHistory
        self.diaryHistory = dHistory
    }

    private func loadIdeaFile(_ dateStr: String) {
        let path = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)/proposals.md")
        if let d = try? String(contentsOfFile: path.path, encoding: .utf8) { 
            withAnimation { 
                self.currentFilePath = path.path
                self.latestIdeaMarkdown = d
                self.displayMode = .proposal
            } 
        }
    }
    
    private func loadDiaryFile(_ dateStr: String) {
        let path = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)/chat_history.json")
        if let data = try? Data(contentsOf: path), 
           let history = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            withAnimation {
                self.chatHistory = history
                self.displayMode = .notebook
            }
        } else {
            // 如果 JSON 不存在，回退到 Markdown 模式（兼容旧数据）
            let mdPath = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)/diary.md")
            if let d = try? String(contentsOfFile: mdPath.path, encoding: .utf8) { 
                withAnimation { 
                    self.currentFilePath = mdPath.path
                    self.latestIdeaMarkdown = d
                    self.displayMode = .diary
                } 
            }
        }
    }
    
    private func deleteHistoryItem(_ dateStr: String, type: String) {
        let dir = URL(fileURLWithPath: storagePath).appendingPathComponent("ideas/\(dateStr)")
        if type == "diary" {
            let path = dir.appendingPathComponent("diary.md")
            let jsonPath = dir.appendingPathComponent("chat_history.json")
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: jsonPath)
        } else {
            let path = dir.appendingPathComponent("proposals.md")
            try? FileManager.default.removeItem(at: path)
        }
        
        // 如果目录空了，顺便删掉目录
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), files.isEmpty {
            try? FileManager.default.removeItem(at: dir)
        }
        
        loadProposalsHistory()
    }
    
    private func historyList(items: [String], icon: String, color: Color, type: String, action: @escaping (String) -> Void) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                if items.isEmpty {
                    Text("暂无记录").font(.caption2).foregroundColor(.secondary).padding(.top, 5)
                }
                ForEach(items, id: \.self) { dateStr in
                    Button(action: { action(dateStr) }) {
                        HStack {
                            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color.opacity(0.7))
                            Text(dateStr).font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity).background(Color.black.opacity(0.03)).cornerRadius(8)
                    }
                    .buttonStyle(.plain).contentShape(Rectangle())
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteHistoryItem(dateStr, type: type)
                        } label: {
                            Label("删除记录", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxHeight: 160)
    }
}

struct LabChatBubble: View {
    let msg: ResearchLabView.ChatMessage
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if msg.isUser { Spacer(minLength: 40) }
            
            if !msg.isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(LinearGradient(gradient: Gradient(colors: [.orange, .red]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .padding(.bottom, 2)
            }
            
            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                Text(msg.text)
                    .font(.system(size: 14, weight: .regular))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundColor(msg.isUser ? .white : .primary)
                    .background(
                        ZStack {
                            if msg.isUser {
                                LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                LinearGradient(gradient: Gradient(colors: [Color.purple.opacity(0.12), Color.indigo.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: 600, alignment: msg.isUser ? .trailing : .leading)
            
            if !msg.isUser { Spacer(minLength: 40) }
        }
        .transition(.asymmetric(insertion: .move(edge: msg.isUser ? .trailing : .leading).combined(with: .opacity), removal: .opacity))
    }
}

