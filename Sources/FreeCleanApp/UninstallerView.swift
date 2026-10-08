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
            List(model.filtered, selection: Binding(
                get: { model.current?.url },
                set: { url in Task { await model.select(model.apps.first { $0.url == url }) } }
            )) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading) {
                        Text(app.name)
                        Text(app.version ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(app.url)
            }
            .searchable(text: $model.search, placement: .sidebar, prompt: "Search apps")
            .frame(minWidth: 230, idealWidth: 260, maxWidth: 340)

            VStack(spacing: 0) {
                if let r = model.report { ReportBanner(report: r).padding(8) }
                if let app = model.current {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.title2.bold())
                            Text(app.bundleID ?? "no bundle ID").font(.caption).foregroundStyle(.secondary)
                            if app.isRunning {
                                Label("Running — quit it before uninstalling", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    Divider()
                    if model.loadingPlan {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.plan) { ItemRow(item: $0, selected: $model.selected) }
                        let chosen = model.plan.filter { model.selected.contains($0.url) }
                        CleanBar(count: chosen.count, size: chosen.totalSize, actionTitle: "Uninstall", busy: false) {
                            Task { await model.uninstall() }
                        }
                    }
                } else {
                    Text("Select an app to see it and its leftover files.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420)
        }
        .navigationTitle("Uninstaller")
        .task { if model.apps.isEmpty { await model.load() } }
    }
}
