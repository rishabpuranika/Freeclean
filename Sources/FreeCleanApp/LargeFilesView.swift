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
    @ViewState private var sortOrder = [KeyPathComparator(\ScanItem.size, order: .reverse)]

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
                    options.card(padding: 12).padding(24).fixedSize()
                        .disabled(model.scanning)
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
            Table(model.visible.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn("") { item in
                    Toggle("", isOn: Binding(
                        get: { model.selected.contains(item.url) },
                        set: { if $0 { model.selected.insert(item.url) } else { model.selected.remove(item.url) } }
                    ))
                    .labelsHidden().toggleStyle(.checkbox)
                }
                .width(22)
                TableColumn("Name", value: \.name) { item in
                    HStack(spacing: 8) {
                        fileIcon(item.url).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).lineLimit(1)
                            Text(tilde(item.url.deletingLastPathComponent())).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .contextMenu { Button("Show in Finder") { reveal(item.url) } }
                }
                TableColumn("Kind") { item in
                    Text(item.category == "large" ? "Large" : "Unused")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background((item.category == "large" ? Color.orange : Color.purple).opacity(0.16), in: Capsule())
                        .foregroundStyle(item.category == "large" ? Color.orange : Color.purple)
                }
                .width(70)
                TableColumn("Last Used", value: \.modified.orDistantPast) { Text(Format.date($0.modified)).foregroundStyle(.secondary) }
                    .width(110)
                TableColumn("Size", value: \.size) { Text($0.size.bytes).monospacedDigit() }
                    .width(80)
                TableColumn("") { item in
                    Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Show in Finder")
                }
                .width(22)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            let chosen = model.items.filter { model.selected.contains($0.url) }
            CleanBar(screen: .large, count: chosen.count, size: chosen.totalSize, actionTitle: "Move to Trash", busy: false) {
                Task { await model.trash() }
            }
        }
    }
}

extension Optional where Wrapped == Date {
    var orDistantPast: Date { self ?? .distantPast }
}
