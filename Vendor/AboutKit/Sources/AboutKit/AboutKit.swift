// Stand-in for the private AboutKit: only the API UUyc-companion calls. The About window is a plain alert and the
// debug labels do nothing.
import AppKit

public struct OpenSourceCredit {
    public let name, url, author, license, usage: String
    public init(name: String, url: String, author: String, license: String, usage: String) {
        self.name = name; self.url = url; self.author = author; self.license = license; self.usage = usage
    }
}

public struct AboutApp {
    public let name, summary, repository, disclaimer: String
    public let credits: [OpenSourceCredit]
    public init(name: String, summary: String, repository: String, credits: [OpenSourceCredit], disclaimer: String) {
        self.name = name; self.summary = summary; self.repository = repository
        self.credits = credits; self.disclaimer = disclaimer
    }
}

public final class AboutWindowController {
    private let app: AboutApp
    public init(app: AboutApp) { self.app = app }

    public func show() {
        let alert = NSAlert()
        alert.messageText = app.name
        alert.informativeText = "\(app.summary)\n\n\(app.repository)\n\n\(app.disclaimer)"
        alert.runModal()
    }

    public func render(to url: URL) {}
}

public enum DebugLabels {
    public static var fileURL: URL?
    public static var windowPrefix: ((NSWindow) -> String?)?
    public static func start() {}
    public static func decorate(_ menu: NSMenu) {}
}
