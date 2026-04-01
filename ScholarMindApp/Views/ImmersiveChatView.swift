import SwiftUI
import PDFKit
import Combine

struct ImmersiveChatView: View {
    let paper: Paper
    var onClose: () -> Void
    
    @State private var chatHistory: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var currentProcess: Process?
    
    // --- 核心：可选上下文状态 ---
    @State private var includePDF = true
    @State private var includeSummary = true
    @State private var includeMyNotes = true
    
    @AppStorage("scholar_proxy") private var savedProxy = ""
    @AppStorage("selected_ai_engine") private var selectedEngine = "Gemini"
    @AppStorage("ai_cli_path") private var aiCliPath = ""

    struct ChatMessage: Identifiable, Codable {
        var id = UUID()
        let text: String
        let isUser: Bool
    }
    
    private var historyURL: URL? {
        let summaryURL = URL(fileURLWithPath: paper.summaryPath)
        return summaryURL.deletingLastPathComponent().appendingPathComponent("chat_history.json")
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. 消息展示区
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 25) {
                        ForEach(chatHistory) { msg in
                            ImmersiveChatBubble(message: msg)
                        }
                        
                        if isGenerating {
                            HStack {
                                LabThinkingBubble()
                                Spacer()
                            }
                        }
                        
                        Spacer().frame(height: 1).id("bottomAnchor")
                    }
                    .padding(.top, 30)
                    .padding(.horizontal, 25) 
                }
                .onChange(of: chatHistory.count) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
                    }
                }
                .onChange(of: isGenerating) { newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.1))

            Divider()

            // 2. 底部控制区 (不再悬浮，由 Divider 隔离)
            VStack(spacing: 0) {
                // 资源选择器
                HStack(spacing: 12) {
                    Text("上下文:").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                    contextChip(title: "PDF 原文", icon: "doc.text.fill", isSelected: $includePDF, color: .blue)
                    contextChip(title: "AI 总结", icon: "sparkles", isSelected: $includeSummary, color: .purple)
                    contextChip(title: "我的随笔", icon: "pencil.and.outline", isSelected: $includeMyNotes, color: .orange)
                    
                    Spacer()
                    
                    Button(action: { withAnimation { clearHistory() } }) {
                        Image(systemName: "trash").font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))
                            .padding(6).background(Circle().fill(Color.red.opacity(0.05)))
                    }.buttonStyle(.plain).help("清除对话记录")
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

                // 输入区
                HStack(spacing: 12) {
                    TextField("基于所选资源进行深度探讨...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color.black.opacity(0.03))
                        .cornerRadius(10)
                        .onSubmit { if !inputText.isEmpty && !isGenerating { sendMessage() } }
                    
                    if isGenerating {
                        Button(action: stopChat) { 
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.red)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(inputText.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                .clipShape(Circle())
                        }.buttonStyle(.plain).disabled(inputText.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 5)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            }
        }
        .onAppear {
            if let loaded = loadHistory(), !loaded.isEmpty {
                self.chatHistory = loaded
            } else if chatHistory.isEmpty {
                chatHistory.append(ChatMessage(text: "你好！你可以通过上方的开关选择让我参考哪些内容。你想针对这篇论文聊聊什么？", isUser: false))
            }
        }
    }

    private func saveHistory() {
        guard let url = historyURL else { return }
        if let data = try? JSONEncoder().encode(chatHistory) {
            try? data.write(to: url)
        }
    }

    private func loadHistory() -> [ChatMessage]? {
        guard let url = historyURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode([ChatMessage].self, from: data)
        }
        return nil
    }

    private func clearHistory() {
        chatHistory = [ChatMessage(text: "你好！你可以通过上方的开关选择让我参考哪些内容。你想针对这篇论文聊聊什么？", isUser: false)]
        if let url = historyURL { try? FileManager.default.removeItem(at: url) }
    }

    private func contextChip(title: String, icon: String, isSelected: Binding<Bool>, color: Color) -> some View {
        Button(action: { withAnimation { isSelected.wrappedValue.toggle() } }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected.wrappedValue ? color.opacity(0.15) : Color.gray.opacity(0.05))
            .foregroundColor(isSelected.wrappedValue ? color : .secondary)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected.wrappedValue ? color.opacity(0.3) : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    func sendMessage() {
        let userQuery = inputText
        chatHistory.append(ChatMessage(text: userQuery, isUser: true))
        inputText = ""
        isGenerating = true
        saveHistory()
        
        // --- 动态构建 Prompt 上下文 ---
        var contextInfo = ""
        if includePDF {
            let pdfText = extractPDFText(path: paper.pdfPath)
            contextInfo += "【PDF原文核心内容】:\n\(pdfText.prefix(8000))\n\n"
        }
        if includeSummary {
            let summary = (try? String(contentsOfFile: paper.summaryPath)) ?? ""
            contextInfo += "【AI之前生成的总结】:\n\(summary)\n\n"
        }
        if includeMyNotes, let myNotes = paper.short_comment, !myNotes.isEmpty {
            contextInfo += "【我的科研随笔记录】:\n\(myNotes)\n\n"
        }
        
        let finalPrompt = """
        你是一位顶尖科研导师。
        背景资料：
        \(contextInfo)
        
        用户问题：
        \(userQuery)
        
        请结合上述你被授予权访问的背景资料，给出深度、严谨且具有启发性的回答。如果某些信息在背景中不存在，请如实告知。
        """
        
        // 启动 Python/CLI 进程
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let binName = selectedEngine.lowercased()
            let aiCliUrl = URL(fileURLWithPath: aiCliPath).appendingPathComponent(binName)
            process.executableURL = URL(fileURLWithPath: aiCliUrl.path)
            
            if binName == "codex" {
                process.arguments = ["exec", "--skip-git-repo-check", finalPrompt]
            } else {
                process.arguments = ["-p", finalPrompt]
            }
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(aiCliPath):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(env["PATH"] ?? "")"
            if !savedProxy.isEmpty { 
                env["HTTP_PROXY"] = savedProxy
                env["HTTPS_PROXY"] = savedProxy
                env["ALL_PROXY"] = savedProxy
            }
            process.environment = env
            
            let pipe = Pipe(); process.standardOutput = pipe
            self.currentProcess = process
            
            try? process.run(); process.waitUntilExit()
            
            if let reply = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                DispatchQueue.main.async {
                    withAnimation(.spring()) {
                        chatHistory.append(ChatMessage(text: reply.trimmingCharacters(in: .whitespacesAndNewlines), isUser: false))
                        isGenerating = false
                        saveHistory()
                    }
                }
            } else {
                DispatchQueue.main.async { isGenerating = false }
            }
        }
    }

    private func stopChat() { currentProcess?.terminate(); isGenerating = false }

    private func extractPDFText(path: String) -> String {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return "" }
        var fullText = ""
        for i in 0..<min(document.pageCount, 15) {
            if let pageText = document.page(at: i)?.string { fullText += pageText }
        }
        return fullText
    }
}

// 消息气泡组件
struct ImmersiveChatBubble: View {
    let message: ImmersiveChatView.ChatMessage
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 50) }
            
            if !message.isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(LinearGradient(gradient: Gradient(colors: [.orange, .red]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .padding(.bottom, 2)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(LocalizedStringKey(message.text))
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .foregroundColor(message.isUser ? .white : .primary)
                    .background(
                        ZStack {
                            if message.isUser {
                                LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                LinearGradient(gradient: Gradient(colors: [Color.purple.opacity(0.12), Color.indigo.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: 600, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser { Spacer(minLength: 50) }
        }
        .transition(.asymmetric(insertion: .move(edge: message.isUser ? .trailing : .leading).combined(with: .opacity), removal: .opacity))
    }
}

