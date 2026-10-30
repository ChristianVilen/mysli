import Cocoa

final class SettingsHelpView: NSStackView {
    let reportBug = NSButton(title: "Report a bug…", target: nil, action: nil)
    let sendFeedback = NSButton(title: "Send feedback…", target: nil, action: nil)
    private let openURL: (URL) -> Void

    var controls: [NSView] { [reportBug, sendFeedback] }

    init(openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 16
        SettingsLayout.add(SettingsLayout.page(title: "Help & feedback", subtitle: "Report a problem or suggest a way to improve Ku-Ka."), to: self)
        for button in [reportBug, sendFeedback] {
            button.bezelStyle = .rounded
            button.target = self
        }
        reportBug.action = #selector(reportBugClicked)
        sendFeedback.action = #selector(sendFeedbackClicked)
        SettingsLayout.add(SettingsLayout.group([
            SettingsLayout.row("Something went wrong", detail: "Tell us what happened and what you expected.", control: reportBug),
            SettingsLayout.row("Share an idea", detail: "Suggest a feature or tell us what could work better.", control: sendFeedback)
        ]), to: self)
        SettingsLayout.add(SettingsLayout.label("These buttons open GitHub in your browser. You can review your message before you send it. A GitHub account is required.", size: 12, secondary: true), to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func reportBugClicked() {
        openURL(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=bug")!)
    }

    @objc private func sendFeedbackClicked() {
        openURL(URL(string: "https://github.com/ChristianVilen/ku-ka/issues/new?labels=enhancement")!)
    }
}
