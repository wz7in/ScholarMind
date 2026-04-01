import SwiftUI
import PDFKit

struct PaperDetailView: View {
    let paper: Paper
    var onBack: () -> Void
    @State private var chatHistory: [(String, Bool)] = []
    @State private var chatInput = ""
    @State private var summaryText = "正在加载总结..."
    @State private var rightPanelMode: RightPanelMode = .summary
    @State private var isEditing = false
    @State private var editableSummary = ""

    enum RightPanelMode {
        case summary, chat
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            topBar
            Divider()

            // Main Content: Left PDF, Right Side Panel
            HSplitView {
                // Left: PDF 原文
                pdfSection
                    .frame(minWidth: 400, maxWidth: .infinity)
                
                // Right: 动态切换面板 (Summary vs Chat)
                rightPanelSection
                    .frame(minWidth: 350, maxWidth: 550)
            }
        }
        .onAppear { loadInitialContent() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                HStack { Image(systemName: "chevron.left"); Text("返回") }
            }
            .buttonStyle(.plain).padding(.horizontal)
            
            Spacer()
            Text(paper.title).font(.headline).lineLimit(1).frame(maxWidth: 400)
            Spacer()
            
            // 面板切换开关
            Picker("", selection: $rightPanelMode) {
                Text("AI 总结").tag(RightPanelMode.summary)
                Text("对话助手").tag(RightPanelMode.chat)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .padding(.horizontal)
        }
        .frame(height: 44)
        .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
    }

    private var pdfSection: some View {
        Group {
            if !paper.pdfPath.isEmpty && FileManager.default.fileExists(atPath: paper.pdfPath) {
                PDFKitView(url: URL(fileURLWithPath: paper.pdfPath))
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 64)).foregroundColor(.secondary)
                    Text("PDF 文件未找到").foregroundColor(.secondary)
                }
            }
        }
    }

    private var rightPanelSection: some View {
        VStack(spacing: 0) {
            if rightPanelMode == .summary {
                // 总结视图
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("AI 深度分析", systemImage: "sparkles")
                            .font(.headline).foregroundColor(.purple)
                        Spacer()
                        
                        if isEditing {
                            Button("取消") { isEditing = false; editableSummary = summaryText }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("保存") { saveSummary() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        } else {
                            Button("编辑") { isEditing = true; editableSummary = summaryText }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    
                    Divider()

                    if isEditing {
                        TextEditor(text: $editableSummary)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(15)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.1))
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                if paper.priority == "high" {
                                    Text("精读建议").font(.caption2).padding(4).background(Color.yellow.opacity(0.2)).cornerRadius(4)
                                }
                                
                                // 关键修改：使用 LocalizedStringKey 激活原生 Markdown 支持
                                Text(LocalizedStringKey(summaryText))
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                            .padding()
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            } else {
                // 对话视图
                ChatPanel(paper: paper, history: $chatHistory, input: $chatInput)
            }
        }
    }

    private func saveSummary() {
        guard !paper.summaryPath.isEmpty else { return }
        try? editableSummary.write(to: URL(fileURLWithPath: paper.summaryPath), atomically: true, encoding: .utf8)
        summaryText = editableSummary
        isEditing = false
    }

    private func loadInitialContent() {
        if !paper.summaryPath.isEmpty && FileManager.default.fileExists(atPath: paper.summaryPath) {
            if let data = try? String(contentsOfFile: paper.summaryPath, encoding: .utf8) {
                self.summaryText = data
                if chatHistory.isEmpty {
                    chatHistory.append(("你好！我已经阅读了这篇论文，你想深入了解它的哪个部分？", false))
                }
            }
        } else {
            self.summaryText = "暂无总结内容。"
        }
    }
}

// --- 辅助视图 ---

struct ChatPanel: View {
    let paper: Paper
    @Binding var history: [(String, Bool)]
    @Binding var input: String
    @State private var isSending = false
    @AppStorage("ai_cli_path") private var aiCliPath = ""
    @AppStorage("selected_ai_engine") private var selectedEngine = "Gemini"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<history.count, id: \.self) { i in
                            ChatBubble(message: history[i].0, isUser: history[i].1).id(i)
                        }
                    }
                    .padding()
                }
                .onChange(of: history.count) { _ in
                    withAnimation { proxy.scrollTo(history.count - 1, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                TextField("基于内容提问...", text: $input).textFieldStyle(.plain).onSubmit { sendMessage() }
                if isSending { ProgressView().controlSize(.small) }
                else { Button(action: sendMessage) { Image(systemName: "paperplane.fill") }.disabled(input.isEmpty) }
            }
            .padding().background(Color(NSColor.controlBackgroundColor))
        }
    }

    func sendMessage() {
        let userMsg = input
        history.append((userMsg, true))
        input = ""
        isSending = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let aiCliUrl = URL(fileURLWithPath: aiCliPath).appendingPathComponent(selectedEngine.lowercased())
            process.executableURL = URL(fileURLWithPath: aiCliUrl.path)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(aiCliPath):/usr/local/bin:\(env["PATH"] ?? "")"
            process.environment = env
            let prompt = "Context: Paper '\(paper.title)'. Question: \(userMsg)"
            process.arguments = ["-p", prompt]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            if let response = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                DispatchQueue.main.async { isSending = false; history.append((response.trimmingCharacters(in: .whitespacesAndNewlines), false)) }
            }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView(); pdfView.document = PDFDocument(url: url); pdfView.autoScales = true
        return pdfView
    }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct ChatBubble: View {
    let message: String; let isUser: Bool
    var body: some View {
        HStack {
            if isUser { Spacer() }
            // 对话也支持简单的 Markdown 渲染
            Text(LocalizedStringKey(message)).padding(10).background(isUser ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2)).cornerRadius(12).foregroundColor(isUser ? .white : .primary).textSelection(.enabled)
            if !isUser { Spacer() }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material; let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material; view.blendingMode = blendingMode; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
