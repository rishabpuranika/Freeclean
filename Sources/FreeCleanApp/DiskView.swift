import Charts
import CleanCore
import SwiftUI

struct DiskView: View {
    @ViewState private var volume = DiskUsage.volume()
    @ViewState private var folders: [ScanItem] = []
    @ViewState private var root = Paths.home
    @ViewState private var loading = false
    @ViewState private var hovered: String?

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo]

    private struct Slice: Identifiable {
        let id: String
        let size: Int64
        let color: Color
    }

    /// Up to six biggest folders; tiny ones are folded into "Other" (Charts traps on near-zero sectors with insets).
    private var slices: [Slice] {
        let total = max(folders.totalSize, 1)
        let big = folders.prefix(6).filter { Double($0.size) / Double(total) >= 0.02 }
        var out = big.enumerated().map { Slice(id: $1.name, size: $1.size, color: Self.palette[$0 % Self.palette.count]) }
        let rest = total - big.totalSize
        if Double(rest) / Double(total) >= 0.02 { out.append(Slice(id: "Other", size: rest, color: .gray)) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(screen: .disk) {
                Button { open(root) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ScrollView {
                VStack(spacing: 16) {
                    if let v = volume { volumeCard(v) }
                    HStack(alignment: .top, spacing: 16) {
                        chartCard.frame(width: 300)
                        folderList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task { if folders.isEmpty { open(root) } }
    }

    private func volumeCard(_ v: VolumeInfo) -> some View {
        let frac = Double(v.used) / Double(max(v.total, 1))
        return HStack(spacing: 18) {
            Image(systemName: "internaldrive.fill").font(.system(size: 34)).foregroundStyle(Screen.disk.gradient)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Macintosh HD").font(.headline)
                    Spacer()
                    Text("\(v.availableImportant.bytes) available").font(.headline).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(frac > 0.9 ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Screen.disk.gradient))
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 12)
                Text("\(v.used.bytes) used of \(v.total.bytes) (\(Int(frac * 100))%)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 18)
    }

    private var chartCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Chart(slices) { s in
                    SectorMark(angle: .value("Size", Double(s.size)), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(s.color.gradient)
                        .opacity(hovered == nil || hovered == s.id ? 1 : 0.35)
                }
                .chartLegend(.hidden)
                .frame(height: 220)
                if !loading { VStack(spacing: 2) {
                    let total = folders.totalSize
                    let focus = slices.first { $0.id == hovered }
                    Text((focus?.size ?? total).bytes).font(.system(.title2, design: .rounded).weight(.bold))
                    Text(focus?.id ?? (root == Paths.home ? "Home" : root.lastPathComponent)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 130) }
            }
            VStack(spacing: 6) {
                ForEach(slices) { s in
                    HStack {
                        Circle().fill(s.color).frame(width: 9, height: 9)
                        Text(s.id).lineLimit(1)
                        Spacer()
                        Text(s.size.bytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                    .onHover { hovered = $0 ? s.id : nil }
                }
            }
        }
        .card()
        .overlay { if loading { ProgressView() } }
    }

    private var folderList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { i, url in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(i == 0 ? "Home" : url.lastPathComponent) { open(url) }
                        .buttonStyle(.plain)
                        .foregroundStyle(i == breadcrumbs.count - 1 ? .primary : .secondary)
                        .fontWeight(i == breadcrumbs.count - 1 ? .semibold : .regular)
                }
                Spacer()
                Text("Double-click to open").font(.caption).foregroundStyle(.tertiary)
            }
            if loading && folders.isEmpty {
                ProgressView("Measuring folders…").frame(maxWidth: .infinity, minHeight: 300)
            } else {
                let maxSize = Double(folders.first?.size ?? 1)
                LazyVStack(spacing: 2) {
                    ForEach(Array(folders.prefix(40).enumerated()), id: \.element.id) { i, f in
                        FolderRow(item: f, fraction: Double(f.size) / maxSize,
                                  color: slices.first { $0.id == f.name }?.color ?? .gray,
                                  open: { open(f.url) })
                    }
                }
            }
        }
        .card()
    }

    private var breadcrumbs: [URL] {
        var out: [URL] = []
        var u = root
        while u.path.hasPrefix(Paths.home.path) {
            out.insert(u, at: 0)
            if u.path == Paths.home.path { break }
            u = u.deletingLastPathComponent()
        }
        return out
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

private struct FolderRow: View {
    let item: ScanItem
    let fraction: Double
    let color: Color
    let open: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            fileIcon(item.url).resizable().frame(width: 22, height: 22)
            Text(item.name).lineLimit(1).frame(width: 190, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(color.gradient).frame(width: max(4, geo.size.width * fraction))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)
            Text(item.size.bytes).monospacedDigit().foregroundStyle(.secondary).frame(width: 76, alignment: .trailing)
            Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).opacity(hovering ? 1 : 0)
                .help("Show in Finder")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: open)
    }
}
