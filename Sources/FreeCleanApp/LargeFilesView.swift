import CleanCore
import SwiftUI

@MainActor @Observable
final class LargeFilesModel {
    var items: [ScanItem] = []
    var selected: Set<URL> = []
    var scanning = false
    var scanned = false
    var progress = 0
    var minSizeMB = 100.0
    var olderThanDays = 365
    var includeOld = true
    var includeHidden = false
    var filter = Filter.all
    var report: TrashReport?

    enum Filter: String, CaseIterable { case all = "All", large = "Large", old = "Old" }

    var visible: [ScanItem] {
        switch filter {
        case .all: items
        case .large: items.filter { $0.category == "large" }
        case .old: items.filter { $0.category == "old" }
        }
    }

    func scan() async {
        scanning = true
        report = nil
        progress = 0
        var scanner = LargeFileScanner(minSize: Int64(minSizeMB * 1_000_000),
                                       olderThanDays: includeOld ? olderThanDays : nil)
        scanner.includeHidden = includeHidden
        let found = await Task.detached { [scanner] in
            scanner.scan { n in Task { @MainActor in self.progress = n } }
        }.value
        items = found
        selected = []
        scanning = false
        scanned = true
    }

    func trash() async {
        let chosen = items.filter { selected.contains($0.url) }
        report = await Task.detached { Trash.move(chosen) }.value
        let gone = Set(report?.trashed ?? [])
        items.removeAll { gone.contains($0.url) }
        selected.subtract(gone)
    }
}

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    enum SortKey { case name, kind, date, size }
    @ViewState private var sortKey = SortKey.size
    @ViewState private var ascending = false

    private var sorted: [ScanItem] {
        let items = model.visible.sorted { a, b in
            switch sortKey {
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .kind: a.category < b.category
            case .date: a.modified.orDistantPast < b.modified.orDistantPast
            case .size: a.size < b.size
            }
        }
        return ascending ? items : items.reversed()
    }

    private func sortHeader(_ title: String, _ key: SortKey) -> some View {
        Button {
            withAnimation(.snappy) {
                if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key == .name }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sortKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(sortKey == key ? 0.9 : 0.5))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        Group {
            if !model.scanned || model.scanning {
                ZStack(alignment: .bottom) {
                    LandingView(screen: .large, buttonTitle: "Scan",
                                message: "Look through your home folder for big files and things you haven't opened in a long time.",
                                busy: model.scanning,
                                status: "Checked \(model.progress.formatted()) files…") {
                        Task { await model.scan() }
                    }
                    options.padding(.horizontal, 18).padding(.vertical, 10).glassCapsule()
                        .padding(28).fixedSize()
                        .disabled(model.scanning)
                        .appear(delay: 0.25)
                }
            } else {
                results
            }
        }
        .animation(.smooth, value: model.scanning)
    }

    private var options: some View {
        HStack(spacing: 14) {
            Picker("Larger than", selection: $model.minSizeMB) {
                ForEach([50.0, 100, 250, 500, 1000, 5000], id: \.self) { Text(Int64($0 * 1_000_000).bytes).tag($0) }
            }
            .fixedSize()
            Divider().frame(height: 18)
            Toggle("Unused for", isOn: $model.includeOld)
            Picker("", selection: $model.olderThanDays) {
                Text("6 months").tag(180); Text("1 year").tag(365); Text("2 years").tag(730)
            }
            .labelsHidden().fixedSize().disabled(!model.includeOld)
            Divider().frame(height: 18)
            Toggle("Hidden folders", isOn: $model.includeHidden)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            PageHeader(screen: .large, subtitle: "\(model.items.count) files · \(model.items.totalSize.bytes)") {
                HStack(spacing: 10) {
                    Picker("", selection: $model.filter) {
                        ForEach(LargeFilesModel.Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Menu {
                        options
                        Divider()
                        Button("Scan Again") { Task { await model.scan() } }
                    } label: { Label("Options", systemImage: "slider.horizontal.3") }
                    .fixedSize()
                }
            }
            if let r = model.report {
                ReportBanner(report: r) { model.report = nil }.padding(.horizontal, 24).padding(.bottom, 10)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 18, height: 1)
                    sortHeader("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader("Kind", .kind).frame(width: 70, alignment: .leading)
                    sortHeader("Last Used", .date).frame(width: 110, alignment: .leading)
                    sortHeader("Size", .size).frame(width: 84, alignment: .trailing)
                    Color.clear.frame(width: 22, height: 1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                Divider().opacity(0.4)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { i, item in
                            FileRow(item: item, selected: $model.selected)
                                .appear(delay: min(0.025 * Double(i), 0.5))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.never)
            }
            .glass(cornerRadius: 20)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .appear(delay: 0.1)
            .overlay(alignment: .bottom) {
                let chosen = model.items.filter { model.selected.contains($0.url) }
                CleanBar(screen: .large, count: chosen.count, size: chosen.totalSize, actionTitle: "Move to Trash", busy: false) {
                    Task { await model.trash() }
                }
                .padding(.bottom, 14)
            }
        }
    }
}

extension Optional where Wrapped == Date {
    var orDistantPast: Date { self ?? .distantPast }
}

private struct FileRow: View {
    let item: ScanItem
    @Binding var selected: Set<URL>
    @ViewState private var hovering = false

    private var isOn: Bool { selected.contains(item.url) }
    private var isLarge: Bool { item.category == "large" }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in withAnimation(.snappy) { if on { selected.insert(item.url) } else { selected.remove(item.url) } } }
            ))
            .labelsHidden().toggleStyle(.checkbox).frame(width: 18)
            HStack(spacing: 10) {
                fileIcon(item.url).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Text(tilde(item.url.deletingLastPathComponent())).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(isLarge ? "Large" : "Unused")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .fontWeight(.bold)
                .background((isLarge ? Color.orange : Color.purple).opacity(0.18), in: Capsule())
                .foregroundStyle(isLarge ? Color.orange : Color.purple)
                .frame(width: 70, alignment: .leading)
            Text(Format.date(item.modified)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(item.size.bytes).monospacedDigit().fontWeight(.medium).frame(width: 84, alignment: .trailing)
            Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.primary.opacity(hovering ? 0.75 : 0.3))
                .help("Show in Finder").frame(width: 22)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? Screen.large.colors[1].opacity(0.22) : .primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { if isOn { selected.remove(item.url) } else { selected.insert(item.url) } } }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .contextMenu { Button("Show in Finder") { reveal(item.url) } }
    }
}
