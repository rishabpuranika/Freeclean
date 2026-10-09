import AppKit
import Charts
import CleanCore
import Combine
import SwiftUI

struct MemoryStartupView: View {
    enum Tab: String, CaseIterable { case memory = "Memory", startup = "Startup Items" }

    @ViewState private var tab = Tab.memory

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(screen: .memory) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            switch tab {
            case .memory: MemoryPanel()
            case .startup: StartupPanel()
            }
        }
    }
}

private struct Sample: Identifiable {
    let id: Int
    let used: Double
}

struct MemoryPanel: View {
    @ViewState private var memory = SystemInfo.memory()
    @ViewState private var history: [Sample] = []
    @ViewState private var tick = 0
    @ViewState private var processes: [ProcessUsage] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let m = memory {
                    HStack(alignment: .top, spacing: 16) {
                        gaugeCard(m).frame(width: 240)
                        historyCard(m)
                    }
                    breakdownCard(m)
                }
                processCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func pressureColor(_ f: Double) -> Color { f > 0.85 ? .red : f > 0.7 ? .orange : .green }

    private func gaugeCard(_ m: MemoryStats) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 14)
                Circle().trim(from: 0, to: m.usedFraction)
                    .stroke(pressureColor(m.usedFraction).gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: m.usedFraction)
                VStack(spacing: 0) {
                    Text("\(Int(m.usedFraction * 100))%").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("in use").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, 4)
            Text("\(Int64(m.used).bytes) of \(Int64(m.total).bytes)").font(.callout.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func historyCard(_ m: MemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory used").font(.headline)
            Text("Last 2 minutes").font(.caption).foregroundStyle(.secondary)
            Chart(history) { s in
                AreaMark(x: .value("t", s.id), y: .value("GB", s.used))
                    .foregroundStyle(LinearGradient(colors: Screen.memory.colors.map { $0.opacity(0.35) } + [.clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.id), y: .value("GB", s.used))
                    .foregroundStyle(Screen.memory.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...(Double(m.total) / 1e9))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) GB") } }
            } }
            .frame(height: 160)
        }
        .card()
    }

    private func breakdownCard(_ m: MemoryStats) -> some View {
        let parts: [(String, UInt64, Color)] = [
            ("App", m.active, .blue), ("Wired", m.wired, .orange), ("Compressed", m.compressed, .purple),
            ("Cached", m.cached, .teal), ("Free", m.free, .gray.opacity(0.4)),
        ]
        let total = Double(max(m.total, 1))
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { p in
                        Rectangle().fill(p.2.gradient).frame(width: max(0, geo.size.width * Double(p.1) / total - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 18) {
                ForEach(parts, id: \.0) { p in
                    HStack(spacing: 6) {
                        Circle().fill(p.2).frame(width: 9, height: 9)
                        Text(p.0).foregroundStyle(.secondary)
                        Text(Int64(p.1).bytes).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
        .card()
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top processes").font(.headline)
                Spacer()
                Button("Open Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                .buttonStyle(.link)
            }
            let maxRSS = Double(processes.first?.residentBytes ?? 1)
            ForEach(processes.prefix(12)) { p in
                HStack(spacing: 10) {
                    processIcon(p.pid).resizable().frame(width: 20, height: 20)
                    Text(p.name).lineLimit(1).frame(width: 260, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Screen.memory.gradient.opacity(0.75))
                            .frame(width: max(3, geo.size.width * Double(p.residentBytes) / maxRSS))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 6)
                    Text(Int64(p.residentBytes).bytes).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .card()
    }

    private func processIcon(_ pid: Int32) -> Image {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon { return Image(nsImage: icon) }
        return Image(nsImage: NSWorkspace.shared.icon(for: .unixExecutable))
    }

    private func refresh() {
        memory = SystemInfo.memory()
        if let m = memory {
            tick += 1
            history.append(Sample(id: tick, used: Double(m.used) / 1e9))
            if history.count > 60 { history.removeFirst(history.count - 60) }
        }
        Task.detached {
            let p = SystemInfo.topProcesses(limit: 12)
            await MainActor.run { processes = p }
        }
    }
}

struct StartupPanel: View {
    @ViewState private var items = SystemInfo.loginItems()
    @ViewState private var error: String?
    @ViewState private var toDisable: LoginItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            List {
                section("Your agents", items.filter(\.isUserOwned),
                        note: "Background helpers installed for your account. Disabling moves the file to the Trash.")
                section("System-wide", items.filter { !$0.isUserOwned },
                        note: "Installed for all users. Remove these from the app that installed them.")
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            HStack {
                Text("Login items you added yourself are managed in System Settings.").font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .confirmationDialog("Disable \(toDisable?.label ?? "")?", isPresented: Binding(
            get: { toDisable != nil }, set: { if !$0 { toDisable = nil } }
        )) {
            Button("Disable", role: .destructive) {
                if let item = toDisable, case .failure(let e) = SystemInfo.disable(item) { error = e.localizedDescription }
                withAnimation { items = SystemInfo.loginItems() }
                toDisable = nil
            }
        } message: {
            Text("The agent is stopped and its file moved to the Trash. Put it back from the Trash to undo.")
        }
    }

    private func section(_ title: String, _ list: [LoginItem], note: String) -> some View {
        Section {
            ForEach(list) { item in
                HStack(spacing: 10) {
                    agentIcon(item).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label).lineLimit(1)
                        Text(item.program).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if item.runAtLoad {
                        Text("At login").font(.caption2.weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule()).foregroundStyle(.green)
                    }
                    Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Show in Finder")
                    if item.isUserOwned {
                        Button("Disable") { toDisable = item }.controlSize(.small)
                    }
                }
                .padding(.vertical, 3)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) (\(list.count))")
                Text(note).font(.caption).foregroundStyle(.secondary).textCase(nil)
            }
        }
    }

    /// Icon of the app that owns the agent's program, if it lives inside a bundle.
    private func agentIcon(_ item: LoginItem) -> Image {
        if let r = item.program.range(of: ".app/") {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: String(item.program[..<r.lowerBound]) + ".app"))
        }
        return Image(nsImage: NSWorkspace.shared.icon(for: .unixExecutable))
    }
}
