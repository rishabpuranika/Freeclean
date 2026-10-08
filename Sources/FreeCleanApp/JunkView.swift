import CleanCore
import SwiftUI

@MainActor @Observable
final class JunkModel {
    var results: [JunkCategory: [ScanItem]] = [:]
    var selected: Set<URL> = []
    var scanning = false
    var cleaning = false
    var scanned = false
    var report: TrashReport?
    let scanner = JunkScanner()

    var allItems: [ScanItem] { JunkCategory.allCases.flatMap { results[$0] ?? [] } }
    var selectedItems: [ScanItem] { allItems.filter { selected.contains($0.url) } }

    func scan() async {
        scanning = true
        report = nil
        let s = scanner
        let r = await Task.detached { await s.scanAll() }.value
        results = r
        selected = Set(JunkCategory.allCases.filter(\.selectedByDefault)
            .flatMap { (r[$0] ?? []).filter(\.selectedByDefault).map(\.url) })
        scanning = false
        scanned = true
    }

    func clean() async {
        cleaning = true
        let items = selectedItems
        let s = scanner
        let r = await Task.detached { s.clean(items) }.value
        cleaning = false
        await scan()
        report = r
    }
}

struct JunkView: View {
    @Bindable var model: JunkModel

    var body: some View {
        Group {
            if !model.scanned && !model.scanning {
                EmptyState(icon: "sparkles", title: "Smart Scan",
                           subtitle: "Find caches, logs, Xcode and developer junk you can safely remove. Nothing is deleted until you confirm, and everything goes to the Trash.",
                           buttonTitle: "Scan") { Task { await model.scan() } }
            } else if model.scanning && model.results.isEmpty {
                ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    List {
                        if let r = model.report { ReportBanner(report: r).listRowSeparator(.hidden) }
                        ForEach(JunkCategory.allCases) { c in
                            CategorySection(category: c, items: model.results[c] ?? [], selected: $model.selected)
                        }
                    }
                    CleanBar(count: model.selectedItems.count, size: model.selectedItems.totalSize,
                             actionTitle: "Clean",
                             confirmMessage: model.selectedItems.contains { $0.category == JunkCategory.trash.rawValue }
                                ? "Selected items go to the Trash. Items already in the Trash will be deleted permanently."
                                : "Selected items will be moved to the Trash. You can restore them from there.",
                             busy: model.cleaning || model.scanning) {
                        Task { await model.clean() }
                    }
                }
            }
        }
        .navigationTitle("Smart Scan")
        .toolbar {
            Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .disabled(model.scanning)
        }
    }
}

struct CategorySection: View {
    let category: JunkCategory
    let items: [ScanItem]
    @Binding var selected: Set<URL>
    @ViewState private var expanded = false

    private var allOn: Bool { !items.isEmpty && items.allSatisfy { selected.contains($0.url) } }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(items) { ItemRow(item: $0, selected: $selected) }
            } label: {
                HStack {
                    Toggle("", isOn: Binding(get: { allOn }, set: { on in
                        for i in items { if on { selected.insert(i.url) } else { selected.remove(i.url) } }
                    }))
                    .labelsHidden()
                    .disabled(items.isEmpty)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title).font(.headline)
                        Text(category.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(items.totalSize.bytes).font(.headline).monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
    }
}
