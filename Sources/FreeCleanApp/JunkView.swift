import CleanCore
import SwiftUI

@MainActor @Observable
final class JunkModel {
    enum Phase { case idle, scanning, results, cleaning, done }

    var phase = Phase.idle
    var results: [JunkCategory: [ScanItem]] = [:]
    var selected: Set<URL> = []
    var scanningCategory: JunkCategory?
    var report: TrashReport?
    var inspected: JunkCategory?
    let scanner = JunkScanner()

    var allItems: [ScanItem] { JunkCategory.allCases.flatMap { results[$0] ?? [] } }
    var selectedItems: [ScanItem] { allItems.filter { selected.contains($0.url) } }
    var foundTotal: Int64 { allItems.totalSize }

    func items(_ c: JunkCategory) -> [ScanItem] { results[c] ?? [] }
    func selectedSize(_ c: JunkCategory) -> Int64 { items(c).filter { selected.contains($0.url) }.totalSize }

    func scan() async {
        phase = .scanning
        report = nil
        results = [:]
        let s = scanner
        for c in JunkCategory.allCases {
            scanningCategory = c
            let items = await Task.detached { await s.scan(c) }.value
            results[c] = items
        }
        scanningCategory = nil
        selected = Set(JunkCategory.allCases.filter(\.selectedByDefault)
            .flatMap { items($0).filter(\.selectedByDefault).map(\.url) })
        phase = .results
    }

    func clean() async {
        phase = .cleaning
        let items = selectedItems
        let s = scanner
        report = await Task.detached { s.clean(items) }.value
        inspected = nil
        phase = .done
    }

    func setCategory(_ c: JunkCategory, on: Bool) {
        for i in items(c) { if on { selected.insert(i.url) } else { selected.remove(i.url) } }
    }
}

struct JunkView: View {
    @Bindable var model: JunkModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .scanning:
                LandingView(screen: .junk, buttonTitle: "Scan",
                            message: "Find caches, logs, Xcode and developer junk that's safe to remove.\nNothing is touched until you confirm.",
                            busy: model.phase == .scanning,
                            status: model.scanningCategory.map { "Scanning \($0.title)…" }) {
                    Task { await model.scan() }
                }
            case .results, .cleaning:
                results
            case .done:
                SuccessView(screen: .junk, report: model.report ?? TrashReport(), doneTitle: "Scan Again") {
                    Task { await model.scan() }
                }
            }
        }
        .animation(.smooth, value: model.phase)
        .toolbar {
            if model.phase == .results {
                Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan complete").font(.headline).foregroundStyle(.secondary)
                            Text(model.foundTotal.bytes)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(Screen.junk.gradient)
                            Text("of junk found across \(model.allItems.count) items").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                        ForEach(JunkCategory.allCases) { c in
                            CategoryCard(category: c, items: model.items(c), selectedSize: model.selectedSize(c),
                                         isInspected: model.inspected == c,
                                         toggle: { model.setCategory(c, on: $0) },
                                         review: { model.inspected = model.inspected == c ? nil : c })
                        }
                    }
                }
                .padding(24)
            }
            CleanBar(screen: .junk, count: model.selectedItems.count, size: model.selectedItems.totalSize,
                     actionTitle: "Clean",
                     confirmMessage: model.selectedItems.contains { $0.category == JunkCategory.trash.rawValue }
                        ? "Selected items go to the Trash. Items already in the Trash will be deleted permanently."
                        : "Selected items will be moved to the Trash. You can restore them from there.",
                     busy: model.phase == .cleaning) {
                Task { await model.clean() }
            }
        }
        .inspector(isPresented: Binding(get: { model.inspected != nil }, set: { if !$0 { model.inspected = nil } })) {
            if let c = model.inspected {
                CategoryInspector(category: c, items: model.items(c), selected: $model.selected)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
        }
    }
}

struct CategoryCard: View {
    let category: JunkCategory
    let items: [ScanItem]
    let selectedSize: Int64
    let isInspected: Bool
    let toggle: (Bool) -> Void
    let review: () -> Void
    @ViewState private var hovering = false

    private var total: Int64 { items.totalSize }
    private var state: Bool { selectedSize > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                IconTile(category, size: 38)
                Spacer()
                Toggle("", isOn: Binding(get: { state }, set: toggle))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(items.isEmpty)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.headline)
                Text(category.detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(total.bytes).font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(items.isEmpty ? .secondary : .primary)
                if state && selectedSize != total {
                    Text("\(selectedSize.bytes) selected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !items.isEmpty {
                    Button(isInspected ? "Hide" : "Review \(items.count)", action: review)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(category.color.opacity(isInspected ? 0.9 : hovering ? 0.4 : 0), lineWidth: 2)
        )
        .opacity(items.isEmpty ? 0.6 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct CategoryInspector: View {
    let category: JunkCategory
    let items: [ScanItem]
    @Binding var selected: Set<URL>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconTile(category, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.title).font(.headline)
                    Text("\(items.count) items · \(items.totalSize.bytes)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Select All") { items.forEach { selected.insert($0.url) } }
                    Button("Select None") { items.forEach { selected.remove($0.url) } }
                } label: { Image(systemName: "checklist") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(14)
            Divider()
            List(items) { ItemRow(item: $0, selected: $selected) }
                .listStyle(.inset)
        }
    }
}
