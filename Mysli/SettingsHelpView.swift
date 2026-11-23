import Cocoa

final class SettingsHelpView: NSStackView {
    let reportBug = NSButton(title: "Report a bug…", target: nil, action: nil)
    let sendFeedback = NSButton(title: "Send feedback…", target: nil, action: nil)
    private let openURL: (URL) -> Void
    private(set) var searchDestinations: [SettingsSearchDestination] = []

    var controls: [NSView] { [reportBug, sendFeedback] }

    init(openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
        SettingsLayout.add(SettingsLayout.page(title: "Help", subtitle: "Report a problem or suggest a way to improve Mysli."), to: self)
        for button in [reportBug, sendFeedback] {
            button.bezelStyle = .rounded
            button.target = self
        }
        reportBug.action = #selector(reportBugClicked)
        sendFeedback.action = #selector(sendFeedbackClicked)
        func row(_ title: String, detail: String, button: NSButton) -> NSView {
            let view = SettingsLayout.row(title, detail: detail, control: button)
            searchDestinations.append(.init(item: .init(page: .help, title: title, detail: detail, keywords: [button.title]),
                                            view: view, control: button))
            return view
        }
        SettingsLayout.add(SettingsLayout.group([
            row("Something went wrong", detail: "Tell us what happened and what you expected.", button: reportBug),
            row("Share an idea", detail: "Suggest a feature or tell us what could work better.", button: sendFeedback)
        ]), to: self)
        SettingsLayout.add(SettingsLayout.note("These buttons open GitHub in your browser. You can review your message before you send it. A GitHub account is required."), to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func reportBugClicked() {
        openURL(URL(string: "https://github.com/ChristianVilen/mysli/issues/new?labels=bug")!)
    }

    @objc private func sendFeedbackClicked() {
        openURL(URL(string: "https://github.com/ChristianVilen/mysli/issues/new?labels=enhancement")!)
    }
}
