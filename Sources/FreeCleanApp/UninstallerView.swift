import CleanCore
import SwiftUI

@MainActor @Observable
final class UninstallerModel {
    var apps: [InstalledApp] = []
    var current: InstalledApp?
    var plan: [ScanItem] = []
    var selected: Set<URL> = []
    var loadingPlan = false
    var search = ""
    var report: TrashReport?
    let uninstaller = AppUninstaller()

    var filtered: [InstalledApp] {
        search.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    func load() async {
        let u = uninstaller
        apps = await Task.detached { u.listApps() }.value
    }

    func select(_ app: InstalledApp?) async {
        current = app
        plan = []
        report = nil
        guard let app else { return }
        loadingPlan = true
        let u = uninstaller
        let p = await Task.detached { await u.plan(for: app) }.value
        guard current == app else { return }
        plan = p
        selected = Set(p.map(\.url))
        loadingPlan = false
    }

    func uninstall() async {
        let items = plan.filter { selected.contains($0.url) }
        let u = uninstaller
        let r = await Task.detached { u.uninstall(items) }.value
        await load()
        if let c = current, !FileManager.default.fileExists(atPath: c.url.path) {
            current = nil
            plan = []
        } else {
            await select(current)
        }
        report = r
    }
}

struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(model.apps.count) apps", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .glassCapsule()
                .padding(12)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filtered) { app in
                            AppRow(app: app, selected: model.current?.url == app.url, namespace: highlight) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                    Task { await model.select(app) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
            }
            .glass(cornerRadius: 20)
            .frame(width: 270)
            .padding(.leading, 18)
            .padding(.vertical, 14)

            detail.frame(minWidth: 0, maxWidth: .infinity)
        }
        .task { if model.apps.isEmpty { await model.load() } }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.current {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    fileIcon(app.url).resizable().frame(width: 104, height: 104)
                        .shadow(color: Screen.uninstaller.colors[0].opacity(0.5), radius: 24, y: 8)
                        .id(app.url)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    Text(app.name).font(.title.weight(.bold))
                    HStack(spacing: 8) {
                        if let v = app.version { Text("Version \(v)") }
                        if let b = app.bundleID { Text("·"); Text(b) }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    if app.isRunning {
                        Label("\(app.name) is running. Quit it before uninstalling.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 28).padding(.bottom, 18)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.url)
                if let r = model.report {
                    ReportBanner(report: r) { model.report = nil }.padding(.horizontal, 20).padding(.bottom, 10)
                }
                if model.loadingPlan {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            GroupHeader(title: "Application")
                            ForEach(model.plan.filter { $0.category == "app" }) { ItemRow(item: $0, selected: $model.selected) }
                            let leftovers = model.plan.filter { $0.category == "leftover" }
                            GroupHeader(title: "Leftover files (\(leftovers.count))").padding(.top, 10)
                            if leftovers.isEmpty {
                                Text("No leftover files found").foregroundStyle(.secondary).padding(.vertical, 4)
                            }
                            ForEach(Array(leftovers.enumerated()), id: \.element.id) { i, item in
                                ItemRow(item: item, selected: $model.selected).appear(delay: 0.04 * Double(i))
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 80)
                    }
                    .scrollIndicators(.never)
                    .glass(cornerRadius: 20)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    let chosen = model.plan.filter { model.selected.contains($0.url) }
                    CleanBar(screen: .uninstaller, count: chosen.count, size: chosen.totalSize, actionTitle: "Uninstall",
                             confirmMessage: "\(app.name) and the selected files will be moved to the Trash.", busy: false) {
                        Task { await model.uninstall() }
                    }
                    .padding(.bottom, 14)
                    }
                }
            }
        } else {
            ZStack {
                VStack(spacing: 14) {
                    IconTile(.uninstaller, size: 96)
                        .shadow(color: Screen.uninstaller.colors[0].opacity(0.6), radius: 30)
                        .appear()
                    Text("Uninstaller").font(.title.weight(.bold))
                    Text("Pick an app on the left to see it with all of its\nsupport files, caches and preferences.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if let r = model.report {
                        ReportBanner(report: r) { model.report = nil }.frame(maxWidth: 360).padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                fileIcon(app.url).resizable().frame(width: 32, height: 32)
                    .scaleEffect(hovering ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                    Text(app.version.map { "Version \($0)" } ?? " ").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: Screen.uninstaller.colors.map { $0.opacity(0.35) },
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18)))
                        .matchedGeometryEffect(id: "app-selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

/// Small uppercase-style group title used inside glass panels (replaces List section headers,
/// whose pinned backgrounds are opaque).
struct GroupHeader: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            if let note { Text(note).font(.caption).foregroundStyle(.white.opacity(0.5)) }
        }
        .padding(.bottom, 4)
    }
}
