import AppKit
import SwiftUI

/// Who made the app and where to find them.
enum Developer {
    static let name = "Kelly Daniel"
    static let website = URL(string: "https://kellydanielo.com")!
    static let appsPage = URL(string: "https://kellydanielo.com/#apps")!
    static let email = "kellyappdev@gmail.com"
    static let mailURL = URL(string: "mailto:\(email)?subject=Notchella")!
}

/// The About block at the bottom of Settings: app identity, the developer, and ways to get in touch.
struct AboutSection: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notchella")
                        .font(.title3.weight(.semibold))
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Free, forever. No accounts, no tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            LabeledContent("Made by") {
                Text(Developer.name)
            }
            Text("I build small, careful apps for the Mac and iPhone. Notchella started as a way to make the notch earn its space. If it made your day a little smoother, I'd love to hear about it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Contact") {
                HStack {
                    Button("Email Me") { NSWorkspace.shared.open(Developer.mailURL) }
                    Button("Copy Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Developer.email, forType: .string)
                    }
                }
            }
            LabeledContent("More from me") {
                HStack {
                    Button("Other Apps") { NSWorkspace.shared.open(Developer.appsPage) }
                    Button("Website") { NSWorkspace.shared.open(Developer.website) }
                }
            }
        } header: {
            Text("About")
        }
    }
}
