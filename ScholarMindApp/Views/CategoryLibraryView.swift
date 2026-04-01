import SwiftUI

struct CategoryLibraryView: View {
    @ObservedObject var dataManager: DataManager
    var onSelectPaper: (Paper) -> Void
    
    @State private var selectedCategory: String? = nil
    @State private var selectedTag: String? = nil
    @State private var selectedDataset: String? = nil
    
    // 动态提取全库资源
    var allCategories: [String] {
        let cats = Array(Set(dataManager.papers.compactMap { $0.category }.filter { !$0.isEmpty && $0 != "未分类" })).sorted()
        return dataManager.papers.contains(where: { $0.category == nil || $0.category == "未分类" }) ? ["📂 待分类"] + cats : cats
    }
    var allTags: [String] { Array(Set(dataManager.papers.compactMap { $0.tags }.flatMap { $0 })).sorted() }
    var allDatasets: [String] { Array(Set(dataManager.papers.compactMap { $0.datasets }.flatMap { $0 })).sorted() }
    
    // 扁平化过滤逻辑：只要满足选中的任意一个条件即可（或逻辑），若都没选则显示全部
    var filteredPapers: [Paper] {
        if selectedCategory == nil && selectedTag == nil && selectedDataset == nil { return dataManager.papers }
        return dataManager.papers.filter { paper in
            let matchCat = selectedCategory != nil && (selectedCategory == "📂 待分类" ? (paper.category == nil || paper.category == "未分类") : paper.category == selectedCategory)
            let matchTag = selectedTag != nil && (paper.tags?.contains(selectedTag!) ?? false)
            let matchDS = selectedDataset != nil && (paper.datasets?.contains(selectedDataset!) ?? false)
            return matchCat || matchTag || matchDS
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("知识图谱").font(.system(size: 28, weight: .black))
                Text("多维穿透：点击任意标签、领域或数据集进行交叉检索").font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(40)

            ScrollView {
                VStack(alignment: .leading, spacing: 35) {
                    // 1. 大类 (紫色)
                    sectionView(title: "研究领域 (Categories)", icon: "square.grid.3x3.fill", items: allCategories, selected: $selectedCategory, color: .purple)
                    // 2. 标签 (蓝色)
                    sectionView(title: "技术关键词 (Tags)", icon: "tag.fill", items: allTags, selected: $selectedTag, color: .blue)
                    // 3. 数据集 (绿色)
                    sectionView(title: "实验数据 (Datasets)", icon: "cylinder.split.1x2.fill", items: allDatasets, selected: $selectedDataset, color: .green)
                    
                    Divider().padding(.vertical, 10)
                    
                    // 4. 结果列表
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass").foregroundColor(.secondary)
                            Text("检索结果 (\(filteredPapers.count))").font(.headline)
                            Spacer()
                            if selectedCategory != nil || selectedTag != nil || selectedDataset != nil {
                                Button("重置全部筛选") { withAnimation { selectedCategory = nil; selectedTag = nil; selectedDataset = nil } }.buttonStyle(.link)
                            }
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(filteredPapers) { paper in
                                PaperCategoryRow(paper: paper).contentShape(Rectangle()).onTapGesture { onSelectPaper(paper) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40).padding(.bottom, 100)
            }
        }
    }

    private func sectionView(title: String, icon: String, items: [String], selected: Binding<String?>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon); Text(title) }.font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
            if items.isEmpty {
                Text("暂无记录").font(.caption).foregroundColor(.secondary).padding(.leading, 5)
            } else {
                FlowLayout(items: items) { item in
                    Button(action: { withAnimation(.spring()) { selected.wrappedValue = (selected.wrappedValue == item ? nil : item) } }) {
                        Text(item).font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected.wrappedValue == item ? color : color.opacity(0.08))
                            .foregroundColor(selected.wrappedValue == item ? .white : color).cornerRadius(15)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FlowLayout<T: Hashable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geo in
                self.generateContent(in: geo)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                self.content(item)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > geo.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == self.items.last {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { d in
                        let result = height
                        if item == self.items.last {
                            height = 0 // last item
                        }
                        return result
                    }
            }
        }.background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geo -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = geo.size.height
            }
            return .clear
        }
    }
}

struct PaperCategoryRow: View {
    let paper: Paper
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack {
                    Text(paper.date).font(.system(size: 11)).foregroundColor(.secondary)
                    if let cat = paper.category {
                        Text("•").foregroundColor(.secondary)
                        Text(cat).font(.system(size: 11)).foregroundColor(.purple)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
}
