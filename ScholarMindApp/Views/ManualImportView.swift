import SwiftUI

struct ManualImportView: View {
    @ObservedObject var dataManager: DataManager
    @Binding var importType: ImportType // 改为 Binding，由父视图控制
    var onStart: (String, String, String, String, Bool, Bool) -> Void
    
    @State private var paperTitle = ""
    @State private var pdfPath = ""
    @State private var webUrl = ""
    @State private var selectedDate = Date()
    @State private var isAutoDate = true
    
    enum ImportType { case file, folder, url }

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)]), startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("导入研究资产").font(.system(size: 32, weight: .black)).padding(.top, 40)
                
                Picker("", selection: $importType) {
                    Text("本地 PDF").tag(ImportType.file)
                    Text("PDF 文件夹").tag(ImportType.folder)
                    Text("网页链接/博客").tag(ImportType.url)
                }.pickerStyle(.segmented).frame(width: 400)

                VStack(spacing: 20) {
                    if importType == .url {
                        inputField(label: "网页链接", icon: "link", text: $webUrl, placeholder: "https://openai.com/blog/...")
                        Text("系统会自动识别：arXiv 将存为论文，其他网页将存为博客。").font(.caption).foregroundColor(.secondary)
                    } else {
                        inputField(label: "显示名称 (可选)", icon: "pencil", text: $paperTitle, placeholder: "不填写则由 AI 自动提取")
                        HStack {
                            Text(pdfPath.isEmpty ? (importType == .file ? "未选择文件" : "未选择文件夹") : pdfPath)
                                .font(.system(size: 12, design: .monospaced)).lineLimit(1).foregroundColor(.secondary)
                            Spacer()
                            Button("选择路径") { selectPath() }.buttonStyle(.bordered)
                        }.padding().background(Color.black.opacity(0.03)).cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("自动识别归档日期 (推荐)", isOn: $isAutoDate).font(.headline)
                        if !isAutoDate {
                            DatePicker("手动指定日期:", selection: $selectedDate, displayedComponents: .date).font(.subheadline)
                        }
                    }.padding(.top, 10)
                }
                .padding(30).background(RoundedRectangle(cornerRadius: 24).fill(Color(NSColor.controlBackgroundColor).opacity(0.6))).frame(width: 550)

                Button(action: startTask) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(importType == .url ? "开始抓取并分析" : "开始 AI 深度导入")
                    }
                    .font(.headline).frame(width: 300).padding().background(Color.blue).foregroundColor(.white).cornerRadius(15)
                }.buttonStyle(.plain).disabled(importType == .url ? webUrl.isEmpty : pdfPath.isEmpty)
                
                Spacer()
            }
        }
    }

    private func inputField(label: String, icon: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon).font(.caption).bold().foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.plain).padding(12).background(Color.black.opacity(0.03)).cornerRadius(10)
        }
    }

    private func selectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = (importType == .file); panel.canChooseDirectories = (importType == .folder)
        if panel.runModal() == .OK { self.pdfPath = panel.url?.path ?? "" }
    }

    private func startTask() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        onStart(paperTitle, pdfPath, webUrl, fmt.string(from: selectedDate), importType == .folder, isAutoDate)
        paperTitle = ""; pdfPath = ""; webUrl = ""
    }
}
