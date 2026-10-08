import CleanCore
import SwiftUI

struct DiskView: View {
    @ViewState private var volume = DiskUsage.volume()
    @ViewState private var folders: [ScanItem] = []
    @ViewState private var root = Paths.home
    @ViewState private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let v = volume {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Macintosh HD").font(.headline)
                    ProgressView(value: Double(v.used), total: Double(max(v.total, 1)))
                        .tint(Double(v.used) / Double(max(v.total, 1)) > 0.9 ? .red : .accentColor)
                    Text("\(v.used.bytes) used of \(v.total.bytes) · \(v.availableImportant.bytes) available")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("Largest in \(tilde(root))").font(.headline)
                Spacer()
                if root != Paths.home {
                    Button("Up") { open(root.deletingLastPathComponent()) }
                }
            }
            if loading {
                ProgressView("Measuring folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSize = Double(folders.first?.size ?? 1)
                List(folders) { f in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path)).resizable().frame(width: 18, height: 18)
                        Text(f.name).frame(width: 220, alignment: .leading).lineLimit(1)
                        ProgressView(value: Double(f.size), total: maxSize)
                        Text(f.size.bytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Button { reveal(f.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(f.url) }
                }
                Text("Double-click a folder to drill in.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Disk Usage")
        .toolbar {
            Button { open(root) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
        .task { if folders.isEmpty { open(root) } }
    }

    private func open(_ url: URL) {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return }
        root = url
        loading = true
        volume = DiskUsage.volume()
        Task {
            let r = await Task.detached { await DiskUsage.breakdown(of: url) }.value
            if root == url {
                folders = r
                loading = false
            }
        }
    }
}
