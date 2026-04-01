import SwiftUI
import Combine

struct PaperMetadata: Codable {
    let category: String?
    let tags: [String]?
    let datasets: [String]?
    let short_comment: String?
    let url: String?
}

struct Paper: Identifiable, Codable {
    var id = UUID()
    let title: String
    let date: String
    let pdfPath: String
    let summaryPath: String
    let timestamp: String
    let priority: String
    var tags: [String]?
    var category: String?
    var datasets: [String]?
    var short_comment: String?
    var type: String?
    var url: String?
}

class DataManager: ObservableObject {
    @Published var papers: [Paper] = []
    @AppStorage("scholar_storage_path") private var storagePath = ""

    init() {}

    func deleteItem(_ paper: Paper) {
        let folderPath = URL(fileURLWithPath: paper.summaryPath).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folderPath)
        loadPapers()
    }

    func deleteDateFolder(date: String) {
        let fm = FileManager.default
        let papersDateDir = URL(fileURLWithPath: storagePath).appendingPathComponent("papers/\(date)")
        let blogsDateDir = URL(fileURLWithPath: storagePath).appendingPathComponent("blogs/\(date)")
        
        try? fm.removeItem(at: papersDateDir)
        try? fm.removeItem(at: blogsDateDir)
        loadPapers()
    }

    func updateSummary(for paper: Paper, newMarkdown: String) {
        try? newMarkdown.write(toFile: paper.summaryPath, atomically: true, encoding: .utf8)
        loadPapers()
    }

    func updateMetadata(for paper: Paper, category: String?, tags: [String], datasets: [String], shortComment: String? = nil) {
        let metadataUrl = URL(fileURLWithPath: paper.summaryPath).deletingLastPathComponent().appendingPathComponent("metadata.json")
        do {
            var json: [String: Any] = [:]
            if let data = try? Data(contentsOf: metadataUrl), let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = existing }
            json["category"] = category ?? "未分类"
            json["tags"] = tags
            json["datasets"] = datasets
            json["short_comment"] = shortComment
            let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
            try newData.write(to: metadataUrl)
            loadPapers()
        } catch { print("❌ 更新失败: \(error)") }
    }

    private func refreshGlobalPools() {
        let catsPoolUrl = URL(fileURLWithPath: storagePath).appendingPathComponent("categories_pool.json")
        let tagsPoolUrl = URL(fileURLWithPath: storagePath).appendingPathComponent("tags_pool.json")
        let activeCategories = Array(Set(papers.compactMap { $0.category }.filter { !$0.isEmpty && $0 != "未分类" })).sorted()
        let activeTags = Array(Set(papers.compactMap { $0.tags }.flatMap { $0 }.filter { !$0.isEmpty })).sorted()
        if let cData = try? JSONEncoder().encode(activeCategories) { try? cData.write(to: catsPoolUrl) }
        if let tData = try? JSONEncoder().encode(activeTags) { try? tData.write(to: tagsPoolUrl) }
    }

    func loadPapers() {
        guard !storagePath.isEmpty else { return }
        var allItems: [Paper] = []
        let fm = FileManager.default
        
        let papersRoot = URL(fileURLWithPath: storagePath).appendingPathComponent("papers")
        if let dateFolders = try? fm.contentsOfDirectory(atPath: papersRoot.path) {
            for dateStr in dateFolders {
                let datePath = papersRoot.appendingPathComponent(dateStr)
                for subType in ["精读论文", "粗读论文", "manual"] {
                    let subPath = datePath.appendingPathComponent(subType)
                    guard let folders = try? fm.contentsOfDirectory(atPath: subPath.path) else { continue }
                    for titleFolder in folders {
                        let folderPath = subPath.appendingPathComponent(titleFolder)
                        let metaPath = folderPath.appendingPathComponent("metadata.json")
                        let summPath = folderPath.appendingPathComponent("summary.md")
                        let pdfP = folderPath.appendingPathComponent("paper.pdf")
                        if fm.fileExists(atPath: summPath.path) {
                            var tags: [String] = [], ds: [String] = [], category: String? = nil, comment: String? = nil
                            if let data = try? Data(contentsOf: metaPath), let meta = try? JSONDecoder().decode(PaperMetadata.self, from: data) {
                                tags = meta.tags ?? []; ds = meta.datasets ?? []; category = meta.category; comment = meta.short_comment
                            }
                            let priorityValue: String
                            if subType == "精读论文" { priorityValue = "high" }
                            else if subType == "manual" { priorityValue = "manual" }
                            else { priorityValue = "low" }
                            
                            allItems.append(Paper(title: titleFolder, date: dateStr, pdfPath: fm.fileExists(atPath: pdfP.path) ? pdfP.path : "", summaryPath: summPath.path, timestamp: dateStr, priority: priorityValue, tags: tags, category: category, datasets: ds, short_comment: comment, type: "paper"))
                        }
                    }
                }
            }
        }
        
        let blogsRoot = URL(fileURLWithPath: storagePath).appendingPathComponent("blogs")
        if let dateFolders = try? fm.contentsOfDirectory(atPath: blogsRoot.path) {
            for dateStr in dateFolders {
                let datePath = blogsRoot.appendingPathComponent(dateStr)
                guard let folders = try? fm.contentsOfDirectory(atPath: datePath.path) else { continue }
                for titleFolder in folders {
                    let folderPath = datePath.appendingPathComponent(titleFolder)
                    let metaPath = folderPath.appendingPathComponent("metadata.json")
                    let summPath = folderPath.appendingPathComponent("summary.md")
                    if fm.fileExists(atPath: summPath.path) {
                        var tags: [String] = [], category: String? = nil, comment: String? = nil, url: String? = nil
                        if let data = try? Data(contentsOf: metaPath), let meta = try? JSONDecoder().decode(PaperMetadata.self, from: data) {
                            tags = meta.tags ?? []; category = meta.category; comment = meta.short_comment; url = meta.url
                        }
                        allItems.append(Paper(title: titleFolder, date: dateStr, pdfPath: "", summaryPath: summPath.path, timestamp: dateStr, priority: "blog", tags: tags, category: category, datasets: [], short_comment: comment, type: "blog", url: url))
                    }
                }
            }
        }
        DispatchQueue.main.async { self.papers = allItems.sorted(by: { $0.date > $1.date }); self.refreshGlobalPools() }
    }
}
