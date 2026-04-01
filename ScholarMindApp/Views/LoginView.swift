import SwiftUI

struct LoginView: View {
    @AppStorage("scholar_cookie") private var savedCookie = ""
    @AppStorage("scholar_proxy") private var savedProxy = ""
    @AppStorage("use_system_proxy") private var useSystemProxy = false
    @AppStorage("scholar_storage_path") private var storagePath = ""
    @AppStorage("selected_ai_engine") private var selectedEngine = "Gemini"
    
    // 同步策略
    @AppStorage("max_daily_papers") private var maxDailyPapers = 15
    @AppStorage("high_score_threshold") private var highScoreThreshold = 0.8
    @AppStorage("min_likes_threshold") private var minLikesThreshold = 2
    @AppStorage("max_low_score_samples") private var maxLowScoreSamples = 2
    
    // 环境路径配置
    @AppStorage("python_path") private var pythonPath = ""
    @AppStorage("ai_cli_path") private var aiCliPath = ""
    
    @State private var isPermissionGranted: Bool = false
    
    private var isConfigComplete: Bool {
        !storagePath.isEmpty && !pythonPath.isEmpty && !aiCliPath.isEmpty
    }
    
    let engines = ["Gemini", "Claude", "Codex"]
    
    var body: some View {
        ZStack {
            // 背景渐变点缀
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // 0. 警告横幅
                    if !isConfigComplete {
                        HStack(spacing: 15) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("环境配置不完整").font(.headline)
                                Text("必须设置资产存储路径、Python 路径和 AI CLI 路径才能开始使用。").font(.caption)
                            }
                            Spacer()
                        }
                        .padding(20).background(Color.red).foregroundColor(.white).cornerRadius(16).padding(.top, 20)
                    }

                    // 1. 头部
                    VStack(spacing: 12) {
                        Image(systemName: "gearshape.fill").font(.system(size: 48)).foregroundColor(.gray.opacity(0.8))
                        Text("系统配置").font(.system(size: 32, weight: .black))
                        Text("在这里调优您的智能助手与学术资产环境").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, isConfigComplete ? 60 : 10)
                    
                    // 2. 设置卡片组
                    VStack(spacing: 25) {
                        // 存储路径卡片
                        settingCard(title: "资产存储中心", subtitle: "管理您的论文、总结与 Idea 存放路径", icon: "folder.badge.gearshape", color: .blue) {
                            VStack(alignment: .leading, spacing: 12) {
                                if storagePath.isEmpty {
                                    Text("⚠️ 尚未选择存储目录，软件将无法保存任何论文或报告")
                                        .font(.caption).foregroundColor(.red).bold().padding(.bottom, 5)
                                }
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(storagePath.isEmpty ? "点击右侧按钮选择路径..." : storagePath)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(storagePath.isEmpty ? .red : .primary)
                                            .lineLimit(1)
                                        
                                        if !storagePath.isEmpty {
                                            HStack(spacing: 6) {
                                                Circle().fill(isPermissionGranted ? Color.green : Color.red).frame(width: 8, height: 8)
                                                Text(isPermissionGranted ? "目录权限：已授权" : "目录权限：未授权/受限").font(.system(size: 10)).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Button(storagePath.isEmpty ? "选取目录" : "更改目录") { selectFolder() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                }
                                .padding(15).background(storagePath.isEmpty ? Color.red.opacity(0.05) : Color.gray.opacity(0.05)).cornerRadius(12)
                            }
                        }
                        
                        // AI 引擎卡片
                        settingCard(title: "智能引擎切换", subtitle: "选择用于深度分析与 Idea 生成的核心模型", icon: "brain.head.profile", color: .purple) {
                            Picker("", selection: $selectedEngine) {
                                ForEach(engines, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 5)
                        }
                        
                        // 路径配置卡片
                        settingCard(title: "核心组件路径", subtitle: "配置本地 Python 与 AI CLI 的执行路径", icon: "terminal.fill", color: .gray) {
                            VStack(spacing: 15) {
                                VStack(alignment: .trailing, spacing: 5) {
                                    inputField(label: "Python 解释器路径", icon: "command", text: $pythonPath, placeholder: "例如: /usr/local/bin/python3", isError: pythonPath.isEmpty)
                                    Button("一键自动检测 Python") { 
                                        let paths = ["/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
                                        for p in paths { if FileManager.default.fileExists(atPath: p) { pythonPath = p; break } }
                                    }.buttonStyle(.link).font(.caption)
                                }

                                VStack(alignment: .trailing, spacing: 5) {
                                    inputField(label: "AI CLI 所在目录 (gemini/claude 等)", icon: "folder.fill", text: $aiCliPath, placeholder: "例如: /usr/local/bin", isError: aiCliPath.isEmpty)
                                    Button("尝试自动探测 CLI 目录") {
                                        let paths = ["/usr/local/bin", "/opt/homebrew/bin"]
                                        for p in paths { if FileManager.default.fileExists(atPath: p + "/gemini") { aiCliPath = p; break } }
                                    }.buttonStyle(.link).font(.caption)
                                }
                            }
                        }

                        // 同步策略卡片
                        settingCard(title: "同步策略控制", subtitle: "精细化配置每日论文的筛选与采样逻辑", icon: "slider.horizontal.3", color: .orange) {
                            VStack(spacing: 18) {
                                strategyStepper(label: "每日处理上限", value: $maxDailyPapers, range: 1...50, unit: "篇", icon: "doc.text.fill")

                                Divider().opacity(0.5)

                                VStack(alignment: .leading, spacing: 12) {
                                    Label("高分论文定义", systemImage: "star.bubble.fill").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                                    HStack(spacing: 20) {
                                        VStack(alignment: .leading) {
                                            Text("最低评分: \(String(format: "%.1f", highScoreThreshold))").font(.caption2).foregroundColor(.secondary)
                                            Slider(value: $highScoreThreshold, in: 0...1, step: 0.1).tint(.orange)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("最小点赞: \(minLikesThreshold)").font(.caption2).foregroundColor(.secondary)
                                            Stepper("", value: $minLikesThreshold, in: 0...10).labelsHidden()
                                        }
                                    }
                                }

                                Divider().opacity(0.5)

                                strategyStepper(label: "低分论文采样数", value: $maxLowScoreSamples, range: 0...10, unit: "篇", icon: "dice.fill")
                            }
                            .padding(5)
                        }

                        // 网络设置卡片
                        settingCard(title: "网络与同步", subtitle: "配置代理服务器以确保模型连接稳定", icon: "network", color: .cyan) {
                            VStack(spacing: 15) {
                                inputField(label: "手动 HTTP 代理地址", icon: "link", text: $savedProxy, placeholder: "http://127.0.0.1:7890")
                                inputField(label: "Scholar Inbox 会话 Cookie", icon: "key.fill", text: $savedCookie, placeholder: "session=...", isSecure: true)
                            }
                        }
                    }
                    .frame(maxWidth: 650)
                    
                    // 3. 危险操作区
                    VStack(alignment: .leading, spacing: 20) {
                        Text("危险操作").font(.headline).foregroundColor(.red)
                        Button(action: { resetToFactory() }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("重置所有配置并清理本地缓存")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Text("注意：此操作将抹除所有本地设置（路径、Cookie、代理等），但不会删除您存储在硬盘上的论文文件。").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(30)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.red.opacity(0.02)))
                    .frame(maxWidth: 650)
                    .padding(.top, 40)
                    
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear { verifyPermission() }
    }

    private func resetToFactory() {
        let alert = NSAlert()
        alert.messageText = "确定要重置所有配置吗？"
        alert.informativeText = "此操作不可撤销。App 将恢复到初始未配置状态。"
        alert.addButton(withTitle: "确定重置")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .critical
        
        if alert.runModal() == .alertFirstButtonReturn {
            // 清理 AppStorage
            let domain = Bundle.main.bundleIdentifier!
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
            
            // 提示重启
            let finalAlert = NSAlert()
            finalAlert.messageText = "已重置成功"
            finalAlert.informativeText = "请手动重启 App 以应用更改。"
            finalAlert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func settingCard<Content: View>(title: String, subtitle: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundColor(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).bold()
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            content()
        }
        .padding(25)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(NSColor.controlBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.02), radius: 10, y: 5)
    }
    
    private func inputField(label: String, icon: String, text: Binding<String>, placeholder: String, isSecure: Bool = false, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundColor(isError ? .red : .secondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(isError ? Color.red.opacity(0.1) : Color.black.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isError ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(isError ? Color.red.opacity(0.1) : Color.black.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isError ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1))
            }
        }
    }

    private func strategyStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
            Spacer()
            HStack(spacing: 12) {
                Text("\(value.wrappedValue) \(unit)").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                Stepper("", value: value, in: range).labelsHidden()
            }
        }
    }

    private func verifyPermission() {
        guard !storagePath.isEmpty else { isPermissionGranted = false; return }
        isPermissionGranted = FileManager.default.isWritableFile(atPath: storagePath)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "请选择您的论文存储目录以授予访问权限"
        panel.prompt = "授权并选择"
        
        // 如果已有路径，默认打开该路径
        if !storagePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: storagePath)
        }
        
        if panel.runModal() == .OK {
            self.storagePath = panel.url?.path ?? ""
            verifyPermission()
        }
    }
}
