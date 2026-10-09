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

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(model.apps.count) apps", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(12)
                List(model.filtered, selection: Binding(
                    get: { model.current?.url },
                    set: { url in Task { await model.select(model.apps.first { $0.url == url }) } }
                )) { app in
                    HStack(spacing: 10) {
                        fileIcon(app.url).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(app.version.map { "Version \($0)" } ?? " ").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(app.url)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)

            detail.frame(minWidth: 460, maxWidth: .infinity)
        }
        .task { if model.apps.isEmpty { await model.load() } }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.current {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    fileIcon(app.url).resizable().frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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
                .background(GlowBackground(screen: .uninstaller).clipped())
                if let r = model.report {
                    ReportBanner(report: r) { model.report = nil }.padding(.horizontal, 20).padding(.bottom, 10)
                }
                if model.loadingPlan {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Application") {
                            ForEach(model.plan.filter { $0.category == "app" }) { ItemRow(item: $0, selected: $model.selected) }
                        }
                        let leftovers = model.plan.filter { $0.category == "leftover" }
                        Section("Leftover files (\(leftovers.count))") {
                            if leftovers.isEmpty {
                                Text("No leftover files found").foregroundStyle(.secondary)
                            }
                            ForEach(leftovers) { ItemRow(item: $0, selected: $model.selected) }
                        }
                    }
                    .listStyle(.inset)
                    let chosen = model.plan.filter { model.selected.contains($0.url) }
                    CleanBar(screen: .uninstaller, count: chosen.count, size: chosen.totalSize, actionTitle: "Uninstall",
                             confirmMessage: "\(app.name) and the selected files will be moved to the Trash.", busy: false) {
                        Task { await model.uninstall() }
                    }
                }
            }
        } else {
            ZStack {
                GlowBackground(screen: .uninstaller)
                VStack(spacing: 14) {
                    IconTile(.uninstaller, size: 84)
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
