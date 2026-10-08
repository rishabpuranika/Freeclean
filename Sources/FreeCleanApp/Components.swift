import AppKit
import CleanCore
import SwiftUI

extension Int64 {
    var bytes: String { Format.bytes(self) }
}

func tilde(_ u: URL) -> String {
    u.path.replacingOccurrences(of: Paths.home.path, with: "~")
}

func reveal(_ u: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([u])
}

/// A checkbox row for a file or folder with size and a reveal button.
struct ItemRow: View {
    let item: ScanItem
    @Binding var selected: Set<URL>
    var showDate = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(item.url) },
                set: { if $0 { selected.insert(item.url) } else { selected.remove(item.url) } }
            ))
            .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(tilde(item.url.deletingLastPathComponent()))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if showDate { Text(Format.date(item.modified)).font(.caption).foregroundStyle(.secondary) }
            Text(item.size.bytes).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Reveal in Finder")
        }
    }
}

/// Bottom bar with selection summary and a confirmed destructive action.
struct CleanBar: View {
    let count: Int
    let size: Int64
    let actionTitle: String
    var confirmMessage = "Selected items will be moved to the Trash. You can restore them from there."
    let busy: Bool
    let action: () -> Void
    @ViewState private var confirming = false

    var body: some View {
        HStack {
            Text("\(count) selected · \(size.bytes)").foregroundStyle(.secondary)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(actionTitle) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0 || busy)
        }
        .padding(12)
        .background(.bar)
        .confirmationDialog("\(actionTitle)? (\(size.bytes))", isPresented: $confirming) {
            Button(actionTitle, role: .destructive, action: action)
        } message: {
            Text(confirmMessage)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 56)).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(buttonTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReportBanner: View {
    let report: TrashReport

    var body: some View {
        HStack {
            Image(systemName: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.failed.isEmpty ? .green : .orange)
            Text("Freed \(report.freed.bytes) (\(report.trashed.count) items)"
                 + (report.failed.isEmpty ? "" : " · \(report.failed.count) failed"))
            Spacer()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .help(report.failed.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
    }
}

/// `@State` resolves to a SwiftUI macro whose plugin only ships with full Xcode.
/// Using the property wrapper through a typealias lets this build with Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
