import Combine
import CleanCore
import SwiftUI

struct MemoryStartupView: View {
    @ViewState private var memory = SystemInfo.memory()
    @ViewState private var processes: [ProcessUsage] = []
    @ViewState private var loginItems = SystemInfo.loginItems()
    @ViewState private var error: String?
    @ViewState private var toDisable: LoginItem?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Memory").font(.title3.bold())
                if let m = memory {
                    Gauge(value: m.usedFraction) {
                        Text("Used")
                    } currentValueLabel: {
                        Text("\(Int64(m.used).bytes) of \(Int64(m.total).bytes)")
                    }
                    .tint(m.usedFraction > 0.85 ? .red : m.usedFraction > 0.7 ? .orange : .green)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        row("App memory", m.active)
                        row("Wired", m.wired)
                        row("Compressed", m.compressed)
                        row("Cached files", m.cached)
                        row("Free", m.free)
                    }
                    .font(.callout)
                }
                Text("Top processes").font(.headline).padding(.top, 8)
                Table(processes) {
                    TableColumn("Process", value: \.name)
                    TableColumn("PID") { Text(String($0.pid)).monospacedDigit() }.width(60)
                    TableColumn("Memory") { Text(Int64($0.residentBytes).bytes).monospacedDigit() }.width(90)
                }
                Text("Quit heavy apps from the Dock or Activity Monitor to free memory.").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 340)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Launch Agents & Startup").font(.title3.bold())
                    Spacer()
                    Button { loginItems = SystemInfo.loginItems() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                List(loginItems) { item in
                    HStack {
                        Circle().fill(item.runAtLoad ? .green : .gray.opacity(0.4)).frame(width: 8, height: 8)
                            .help(item.runAtLoad ? "Runs at login" : "Runs on demand")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).lineLimit(1)
                            Text(item.program).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(item.isUserOwned ? "User" : "System").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Button { reveal(item.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                        if item.isUserOwned {
                            Button("Disable") { toDisable = item }.controlSize(.small)
                        }
                    }
                }
                Text("Login items added in System Settings › General › Login Items are managed there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 420)
        }
        .navigationTitle("Memory & Startup")
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .confirmationDialog("Disable \(toDisable?.label ?? "")?", isPresented: Binding(
            get: { toDisable != nil }, set: { if !$0 { toDisable = nil } }
        )) {
            Button("Disable", role: .destructive) {
                if let item = toDisable, case .failure(let e) = SystemInfo.disable(item) { error = e.localizedDescription }
                loginItems = SystemInfo.loginItems()
                toDisable = nil
            }
        } message: {
            Text("The agent is unloaded and its plist moved to the Trash. Restore it from the Trash to undo.")
        }
    }

    private func row(_ label: String, _ v: UInt64) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(Int64(v).bytes).monospacedDigit()
        }
    }

    private func refresh() {
        memory = SystemInfo.memory()
        Task.detached {
            let p = SystemInfo.topProcesses(limit: 20)
            await MainActor.run { processes = p }
        }
    }
}
