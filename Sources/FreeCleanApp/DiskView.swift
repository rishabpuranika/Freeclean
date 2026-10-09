import Charts
import CleanCore
import SwiftUI

struct DiskView: View {
    @ViewState private var volume = DiskUsage.volume()
    @ViewState private var folders: [ScanItem] = []
    @ViewState private var root = Paths.home
    @ViewState private var loading = false
    @ViewState private var hovered: String?
    @ViewState private var revealed = false

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo]

    private struct Slice: Identifiable {
        let id: String
        let size: Int64
        let color: Color
    }

    /// Up to six biggest folders; tiny ones are folded into "Other" (Charts traps on near-zero sectors with insets).
    private var slices: [Slice] {
        guard !folders.isEmpty else { return [] }
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
                    if let v = volume { volumeCard(v).appear(delay: 0.05) }
                    HStack(alignment: .top, spacing: 16) {
                        chartCard.frame(width: 300).appear(delay: 0.12)
                        folderList.appear(delay: 0.18)
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
                .shadow(color: Screen.disk.colors[0].opacity(0.5), radius: 8)
                Text("\(v.used.bytes) used of \(v.total.bytes) (\(Int(frac * 100))%)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 18)
    }

    private var chartCard: some View {
        VStack(spacing: 12) {
            ZStack {
                // Empty track in the donut's exact footprint, so the first load has a shape to fill.
                if slices.isEmpty {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 42)
                        .frame(width: 178, height: 178)
                }
                Chart(slices) { s in
                    SectorMark(angle: .value("Size", Double(s.size)), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(s.color.gradient)
                        .opacity(hovered == nil || hovered == s.id ? 1 : 0.35)
                }
                .chartLegend(.hidden)
                .frame(height: 220)
                .rotationEffect(.degrees(revealed ? 0 : -90))
                .scaleEffect(revealed ? 1 : 0.8)
                .opacity(revealed ? (loading ? 0.3 : 1) : 0)
                .animation(.easeInOut(duration: 0.3), value: loading)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                if loading {
                    DonutLoader()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else { VStack(spacing: 2) {
                    let total = folders.totalSize
                    let focus = slices.first { $0.id == hovered }
                    Text((focus?.size ?? total).bytes).font(.system(.title2, design: .rounded).weight(.bold))
                    Text(focus?.id ?? (root == Paths.home ? "Home" : root.lastPathComponent)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 130)
                .transition(.opacity) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: loading)
            VStack(spacing: 6) {
                if slices.isEmpty {
                    ForEach(0..<4, id: \.self) { i in SkeletonRow(nameWidth: [90, 70, 110, 60][i], icon: .dot) }
                }
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
                VStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { i in
                        SkeletonRow(nameWidth: [120, 90, 150, 80, 110, 130, 70, 100, 140, 85][i], icon: .square)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                }
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
                // Swap data without animation (Swift Charts traps animating sectors in), then reveal the view.
                revealed = false
                folders = r
                loading = false
                withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { revealed = true }
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

/// Loading state shown inside the donut hole: a spinning arc in the Disk Usage colors and a label.
private struct DonutLoader: View {
    @ViewState private var spinning = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: [Screen.disk.colors[1].opacity(0), Screen.disk.colors[0]],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(108)),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            }
            .frame(width: 36, height: 36)
            Text("Measuring…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .onAppear { spinning = true }
    }
}

/// Placeholder row shaped like real data, pulsing gently while sizes are measured.
private struct SkeletonRow: View {
    enum Icon { case dot, square }
    let nameWidth: CGFloat
    let icon: Icon
    @ViewState private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            switch icon {
            case .dot: Circle().frame(width: 9, height: 9)
            case .square: RoundedRectangle(cornerRadius: 5, style: .continuous).frame(width: 22, height: 22)
            }
            Capsule().frame(width: nameWidth, height: 10)
            Spacer()
            Capsule().frame(width: 56, height: 10)
        }
        .foregroundStyle(.white.opacity(pulse ? 0.16 : 0.07))
        .frame(height: icon == .square ? 26 : 18)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
