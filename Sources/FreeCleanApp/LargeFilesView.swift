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
    var report: TrashReport?

    func scan() async {
        scanning = true
        report = nil
        progress = 0
        var scanner = LargeFileScanner(minSize: Int64(minSizeMB * 1_000_000),
                                       olderThanDays: includeOld ? olderThanDays : nil)
        scanner.includeHidden = includeHidden
        let found = await Task.detached {
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
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Min size")
                Picker("", selection: $model.minSizeMB) {
                    ForEach([50.0, 100, 250, 500, 1000, 5000], id: \.self) { Text(Int64($0 * 1_000_000).bytes).tag($0) }
                }
                .labelsHidden().frame(width: 100)
                Toggle("Include files unused for", isOn: $model.includeOld)
                Picker("", selection: $model.olderThanDays) {
                    Text("6 months").tag(180); Text("1 year").tag(365); Text("2 years").tag(730)
                }
                .labelsHidden().frame(width: 110).disabled(!model.includeOld)
                Toggle("Hidden folders", isOn: $model.includeHidden)
                Spacer()
                Button(model.scanned ? "Rescan" : "Scan Home Folder") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent).disabled(model.scanning)
            }
            .padding(12)
            Divider()
            if model.scanning {
                ProgressView("Scanning… \(model.progress) files checked").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.scanned {
                EmptyState(icon: "doc.on.doc", title: "Large & Old Files",
                           subtitle: "Find big files and things you haven't opened in ages across your home folder (excluding ~/Library, .git and node_modules).",
                           buttonTitle: "Scan") { Task { await model.scan() } }
            } else {
                if let r = model.report { ReportBanner(report: r).padding(8) }
                Table(model.items.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("") { item in
                        Toggle("", isOn: Binding(
                            get: { model.selected.contains(item.url) },
                            set: { if $0 { model.selected.insert(item.url) } else { model.selected.remove(item.url) } }
                        )).labelsHidden()
                    }
                    .width(24)
                    TableColumn("Name", value: \.name) { item in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 16, height: 16)
                            Text(item.name).lineLimit(1)
                        }
                        .contextMenu { Button("Reveal in Finder") { reveal(item.url) } }
                    }
                    TableColumn("Location") { item in
                        Text(tilde(item.url.deletingLastPathComponent())).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Last used", value: \.modified.orDistantPast) { Text(Format.date($0.modified)) }
                        .width(110)
                    TableColumn("Size", value: \.size) { Text($0.size.bytes).monospacedDigit() }
                        .width(90)
                    TableColumn("") { item in
                        Button { reveal(item.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                    }
                    .width(24)
                }
                let chosen = model.items.filter { model.selected.contains($0.url) }
                CleanBar(count: chosen.count, size: chosen.totalSize, actionTitle: "Move to Trash", busy: false) {
                    Task { await model.trash() }
                }
            }
        }
        .navigationTitle("Large & Old Files")
    }
}

extension Optional where Wrapped == Date {
    var orDistantPast: Date { self ?? .distantPast }
}
