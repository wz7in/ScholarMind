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
    @AppStorage("siliconflow_api_key") private var siliconflowApiKey = ""
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

        let prompt = "Context: Paper '\(paper.title)'. Question: \(userMsg)"
        if selectedEngine.lowercased() == "deepseek" {
            requestDeepSeekReply(prompt: prompt) { result in
                DispatchQueue.main.async {
                    isSending = false
                    switch result {
                    case .success(let reply):
                        history.append((reply.trimmingCharacters(in: .whitespacesAndNewlines), false))
                    case .failure(let error):
                        history.append(("❌ DeepSeek 请求失败: \(error.localizedDescription)", false))
                    }
                }
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let binName = selectedEngine.lowercased()
            let aiCliUrl = URL(fileURLWithPath: aiCliPath).appendingPathComponent(binName)
            process.executableURL = URL(fileURLWithPath: aiCliUrl.path)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(aiCliPath):/usr/local/bin:\(env["PATH"] ?? "")"
            process.environment = env
            
            if binName == "codex" {
                process.arguments = ["exec", "--skip-git-repo-check", prompt]
            } else {
                process.arguments = ["-p", prompt]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            if let response = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                DispatchQueue.main.async { isSending = false; history.append((response.trimmingCharacters(in: .whitespacesAndNewlines), false)) }
            }
        }
    }

    private func requestDeepSeekReply(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let envKey = ProcessInfo.processInfo.environment["SILICONFLOW_API_KEY"] ?? ProcessInfo.processInfo.environment["AI_API_KEY"]
        let apiKey = (envKey?.isEmpty == false ? envKey : nil) ?? siliconflowApiKey
        guard !apiKey.isEmpty else {
            let err = NSError(domain: "DeepSeek", code: 401, userInfo: [NSLocalizedDescriptionKey: "缺少 API Key，请设置 SILICONFLOW_API_KEY 或 AI_API_KEY。"])
            completion(.failure(err))
            return
        }

        guard let url = URL(string: "https://api.siliconflow.cn/v1/chat/completions") else {
            completion(.failure(NSError(domain: "DeepSeek", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求地址"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": "Pro/deepseek-ai/DeepSeek-V3.2",
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "DeepSeek", code: -1, userInfo: [NSLocalizedDescriptionKey: "未收到有效响应"])))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let msg = extractServerError(from: data) ?? "HTTP \(httpResponse.statusCode)"
                completion(.failure(NSError(domain: "DeepSeek", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any] else {
                completion(.failure(NSError(domain: "DeepSeek", code: -1, userInfo: [NSLocalizedDescriptionKey: "返回格式异常"])))
                return
            }

            let content = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let reasoning = (message["reasoning_content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = content.isEmpty ? reasoning : content
            if finalText.isEmpty {
                completion(.failure(NSError(domain: "DeepSeek", code: -1, userInfo: [NSLocalizedDescriptionKey: "返回内容为空"])))
                return
            }
            completion(.success(finalText))
        }.resume()
    }

    private func extractServerError(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = json["message"] as? String, let extra = json["data"] as? String, !extra.isEmpty {
            return "\(message): \(extra)"
        }
        return json["message"] as? String
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
