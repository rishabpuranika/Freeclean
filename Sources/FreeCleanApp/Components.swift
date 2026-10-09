import AppKit
import CleanCore
import SwiftUI

/// `@State` resolves to a SwiftUI macro whose plugin only ships with full Xcode.
/// Using the property wrapper through a typealias lets this build with Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Int64 {
    var bytes: String { Format.bytes(self) }
}

func tilde(_ u: URL) -> String {
    u.path.replacingOccurrences(of: Paths.home.path, with: "~")
}

func reveal(_ u: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([u])
}

func fileIcon(_ u: URL) -> Image {
    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path))
}

/// A checkbox row for a file or folder with size and a reveal button.
struct ItemRow: View {
    let item: ScanItem
    @Binding var selected: Set<URL>
    var showDate = false
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(item.url) },
                set: { if $0 { selected.insert(item.url) } else { selected.remove(item.url) } }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            fileIcon(item.url).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(tilde(item.url.deletingLastPathComponent()))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if showDate { Text(Format.date(item.modified)).font(.caption).foregroundStyle(.secondary) }
            Button { reveal(item.url) } label: { Image(systemName: "arrow.right.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Show in Finder")
                .opacity(hovering ? 1 : 0)
            Text(item.size.bytes).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { Button("Show in Finder") { reveal(item.url) } }
    }
}

/// Bottom bar with selection summary and a confirmed destructive action.
struct CleanBar: View {
    let screen: Screen
    let count: Int
    let size: Int64
    let actionTitle: String
    var confirmMessage = "Selected items will be moved to the Trash. You can restore them from there."
    let busy: Bool
    let action: () -> Void
    @ViewState private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(size.bytes).font(.title3.weight(.semibold)).monospacedDigit()
                Text("\(count) item\(count == 1 ? "" : "s") selected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(actionTitle) { confirming = true }
                .buttonStyle(GradientButtonStyle(gradient: screen.gradient))
                .disabled(count == 0 || busy)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .confirmationDialog("\(actionTitle) \(size.bytes)?", isPresented: $confirming) {
            Button(actionTitle, role: .destructive, action: action)
        } message: {
            Text(confirmMessage)
        }
    }
}

/// Landing view shown before a screen's first scan.
struct LandingView: View {
    let screen: Screen
    let buttonTitle: String
    let message: String
    var busy = false
    var status: String?
    let action: () -> Void

    var body: some View {
        ZStack {
            GlowBackground(screen: screen)
            VStack(spacing: 22) {
                HeroButton(screen: screen, title: buttonTitle, busy: busy, action: action)
                Text(busy ? (status ?? "Scanning…") : message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .contentTransition(.opacity)
                    .animation(.default, value: status)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReportBanner: View {
    let report: TrashReport
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(report.failed.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text("Freed \(report.freed.bytes)").font(.headline)
                Text("\(report.trashed.count) item(s) moved to the Trash"
                     + (report.failed.isEmpty ? "" : " · \(report.failed.count) failed"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .card(padding: 12)
        .help(report.failed.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
    }
}
