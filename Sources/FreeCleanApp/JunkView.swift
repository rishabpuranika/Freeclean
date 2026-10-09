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

    var progress: Double? {
        guard phase == .scanning else { return nil }
        return Double(results.count) / Double(JunkCategory.allCases.count)
    }

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
        ZStack {
            switch model.phase {
            case .idle, .scanning:
                VStack(spacing: 0) {
                    LandingView(screen: .junk, buttonTitle: "Scan",
                                message: "Find caches, logs, Xcode and developer junk that's safe to remove. Nothing is touched until you confirm.",
                                busy: model.phase == .scanning,
                                status: model.scanningCategory.map { "Scanning \($0.title)…" },
                                progress: model.progress) {
                        Task { await model.scan() }
                    }
                    if model.phase == .scanning {
                        ScanChecklist(model: model)
                            .padding(.bottom, 36)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            case .results, .cleaning:
                results.transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .done:
                SuccessView(screen: .junk, report: model.report ?? TrashReport(), doneTitle: "Scan Again") {
                    Task { await model.scan() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: model.phase)
    }

    private var results: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Scan complete", systemImage: "checkmark.seal.fill")
                            .font(.headline.weight(.bold)).foregroundStyle(.white.opacity(0.92))
                            .symbolRenderingMode(.multicolor)
                        CountUpBytes(target: model.foundTotal)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .shadow(color: Screen.junk.colors[0].opacity(0.6), radius: 20)
                        Text("of junk found across \(model.allItems.count) items").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topTrailing) {
                        Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise").fontWeight(.semibold).foregroundStyle(.white) }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassCapsule()
                    }
                    .appear()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(Array(JunkCategory.allCases.enumerated()), id: \.element) { i, c in
                            CategoryCard(category: c, items: model.items(c), selectedSize: model.selectedSize(c),
                                         isInspected: model.inspected == c,
                                         toggle: { on in withAnimation(.snappy) { model.setCategory(c, on: on) } },
                                         review: { withAnimation(.smooth) { model.inspected = model.inspected == c ? nil : c } })
                                .appear(delay: 0.12 + Double(i) * 0.06)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
            .scrollContentBackground(.hidden)
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
                    .background(.black.opacity(0.18))
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
        }
    }
}

/// Live list of categories ticking off as the scan progresses.
struct ScanChecklist: View {
    let model: JunkModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(JunkCategory.allCases) { c in
                let done = model.results[c] != nil
                let active = model.scanningCategory == c
                HStack(spacing: 7) {
                    ZStack {
                        if done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else if active {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: c.icon).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.title).font(.caption.weight(.semibold))
                        Text(done ? (model.results[c] ?? []).totalSize.bytes : active ? "Scanning…" : "Waiting")
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .glassCapsule(tint: active ? c.color.opacity(0.35) : nil)
                .opacity(done || active ? 1 : 0.6)
                .scaleEffect(active ? 1.05 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: active)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
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
                IconTile(category, size: 40)
                    .symbolEffect(.bounce, value: hovering)
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
                CountUpBytes(target: total).font(.system(.title2, design: .rounded).weight(.bold))
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
        .card(padding: 18, tint: state ? category.color.opacity(0.18) : nil)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(category.color.opacity(isInspected ? 0.9 : hovering ? 0.45 : 0), lineWidth: 1.5)
        )
        .opacity(items.isEmpty ? 0.8 : 1)
        .scaleEffect(hovering && !items.isEmpty ? 1.015 : 1)
        .shadow(color: category.color.opacity(hovering ? 0.35 : 0), radius: 18, y: 6)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hovering)
        .animation(.smooth, value: state)
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
            List(items) { ItemRow(item: $0, selected: $selected).listRowBackground(Color.clear) }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
        }
    }
}
