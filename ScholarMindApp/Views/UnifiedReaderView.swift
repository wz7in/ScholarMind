import SwiftUI
import WebKit

struct UnifiedReaderView: View {
    let paper: Paper
    var onClose: () -> Void
    
    @State private var summary: String = ""
    @State private var currentCategory: String? = nil
    @State private var currentTags: [String] = []
    @State private var currentDatasets: [String] = []
    @State private var shortComment: String = ""
    
    @State private var detailMode: DetailMode = .summary
    @State private var isShowingCommentEditor = false
    @State private var isShowingSummaryEditor = false 
    @State private var originalSummary = "" // 用于取消编辑时回滚
    @State private var editingType: EditType? = nil
    @State private var newTagInput = ""
    
    @EnvironmentObject var dataManager: DataManager
    
    enum DetailMode { case summary, chat }
    enum EditType { case category, tag, dataset }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                topNavDock
                HSplitView {
                    leftContentPanel
                    VStack(spacing: 0) {
                        researchNoteCard.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
                        Divider().padding(.horizontal, 20)
                        if detailMode == .summary {
                            summaryWithToolbar
                        } else {
                            ImmersiveChatView(paper: paper, onClose: onClose).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(minWidth: 350, maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                }
            }
        }
        .onAppear {
            if let content = try? String(contentsOfFile: paper.summaryPath, encoding: .utf8) { 
                self.summary = content 
                self.originalSummary = content
            }
            self.currentCategory = (paper.category == "未分类" || paper.category == nil) ? nil : paper.category
            self.currentTags = paper.tags ?? []
            self.currentDatasets = paper.datasets ?? []
            self.shortComment = paper.short_comment ?? ""
        }
    }

    private var summaryWithToolbar: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if isShowingSummaryEditor {
                    Button("取消") { withAnimation { isShowingSummaryEditor = false; summary = originalSummary } }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("保存修改") { 
                        withAnimation {
                            dataManager.updateSummary(for: paper, newMarkdown: summary)
                            originalSummary = summary
                            isShowingSummaryEditor = false
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button(action: { withAnimation { isShowingSummaryEditor = true } }) {
                        HStack(spacing: 4) { Image(systemName: "pencil.and.outline"); Text("编辑总结") }
                            .font(.system(size: 11, weight: .bold))
                    }.buttonStyle(.bordered).controlSize(.small).padding(.trailing, 10)
                }
            }.padding(.top, 10)

            if isShowingSummaryEditor {
                TextEditor(text: $summary)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(20)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12).padding(10)
            } else {
                MarkdownWebView(markdown: summary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var topNavDock: some View {
        HStack(spacing: 15) {
            Button(action: onClose) { HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("退出").font(.system(size: 13, weight: .bold)) }.foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(Color.gray.opacity(0.1))) }.buttonStyle(.plain)
            Spacer()
            Picker("", selection: $detailMode) { Label("深度解析", systemImage: "doc.text.magnifyingglass").tag(DetailMode.summary); Label("研讨对话", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill").tag(DetailMode.chat) }.pickerStyle(.segmented).frame(width: 220)
            Spacer()
            HStack(spacing: 10) {
                tagGroup(items: currentCategory != nil ? [currentCategory!] : [], color: .purple, type: .category)
                tagGroup(items: currentTags, color: .blue, type: .tag)
                tagGroup(items: currentDatasets, color: .green, type: .dataset)
                if let type = editingType { TextField("添加...", text: $newTagInput, onCommit: commitAdd).textFieldStyle(.plain).frame(width: 80).font(.system(size: 10, weight: .bold)).padding(6).background(typeColor(type).opacity(0.15)).cornerRadius(6) }
            }.padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.gray.opacity(0.05)))
        }.padding(.horizontal, 25).padding(.vertical, 12).background(.ultraThinMaterial).overlay(VStack { Spacer(); Divider() })
    }

    private var researchNoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) { Image(systemName: "lightbulb.fill").font(.system(size: 12)); Text("我的研究随笔").font(.system(size: 12, weight: .black)) }.foregroundColor(.orange)
                Spacer()
                if isShowingCommentEditor {
                    Button("取消") { withAnimation { isShowingCommentEditor = false; shortComment = paper.short_comment ?? "" } }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)
                    Button("保存") { withAnimation { isShowingCommentEditor = false; saveChanges() } }.buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundColor(.blue)
                } else {
                    Button(action: { withAnimation { isShowingCommentEditor = true } }) { Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundColor(.blue) }.buttonStyle(.plain)
                }
            }
            if isShowingCommentEditor {
                TextEditor(text: $shortComment)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                    .transition(.opacity)
            } else {
                Text(shortComment.isEmpty ? "记录下你此刻的第一研究灵感..." : shortComment)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(shortComment.isEmpty ? .secondary : .primary)
                    .lineLimit(isShowingCommentEditor ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(15).background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private var leftContentPanel: some View {
        if paper.type == "blog", let urlStr = paper.url, let url = URL(string: urlStr) { WebView(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) } 
        else if !paper.pdfPath.isEmpty { PDFKitView(url: URL(fileURLWithPath: paper.pdfPath)).frame(maxWidth: .infinity, maxHeight: .infinity) } 
        else { VStack { Image(systemName: "doc.append.fill").font(.system(size: 64)).foregroundColor(.gray.opacity(0.2)); Text("无法加载原文").foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    }

    private func tagGroup(items: [String], color: Color, type: EditType) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in HStack(spacing: 4) { Text(item).font(.system(size: 10, weight: .bold)); if editingType == type { Button(action: { removeItem(item, type: type) }) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }.buttonStyle(.plain) } }.padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.1)).foregroundColor(color).cornerRadius(6) }
            Button(action: { withAnimation { if editingType == type && !newTagInput.isEmpty { commitAdd() } else { editingType = (editingType == type ? nil : type); newTagInput = "" } } }) { Image(systemName: editingType == type ? "checkmark.circle.fill" : (type == .category ? "square.grid.3x3.fill" : (type == .tag ? "tag.fill" : "cylinder.split.1x2.fill"))).font(.system(size: 12)).foregroundColor(color) }.buttonStyle(.plain)
        }
    }

    private func typeColor(_ type: EditType) -> Color { switch type { case .category: return .purple; case .tag: return .blue; case .dataset: return .green } }
    private func commitAdd() {
        let val = newTagInput.trimmingCharacters(in: .whitespaces)
        guard !val.isEmpty, let type = editingType else { editingType = nil; return }
        withAnimation {
            switch type { case .category: currentCategory = val; case .tag: if !currentTags.contains(val) { currentTags.append(val) }; case .dataset: if !currentDatasets.contains(val) { currentDatasets.append(val) } }
            saveChanges(); newTagInput = ""; editingType = nil
        }
    }
    private func removeItem(_ item: String, type: EditType) { withAnimation { switch type { case .category: currentCategory = nil; case .tag: currentTags.removeAll { $0 == item }; case .dataset: currentDatasets.removeAll { $0 == item } }; saveChanges() } }
    private func saveChanges() { dataManager.updateMetadata(for: paper, category: currentCategory, tags: currentTags, datasets: currentDatasets, shortComment: shortComment) }
}
