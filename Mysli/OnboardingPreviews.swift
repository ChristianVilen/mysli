#if DEBUG
import AppKit
import SwiftUI

#Preview("Onboarding · Full flow", traits: .fixedLayout(width: 760, height: 700)) {
    onboardingPreview(startingAt: .welcome)
}

#Preview("Onboarding · Choose tools", traits: .fixedLayout(width: 760, height: 700)) {
    onboardingPreview(startingAt: .tools)
}

#Preview("Onboarding · Allow access", traits: .fixedLayout(width: 760, height: 700)) {
    onboardingPreview(startingAt: .permissions)
}

@MainActor
func onboardingPreview(startingAt step: Onboarding.Step) -> NSViewController {
    let defaults = AppKitPreview.defaults()
    let settings = Settings(defaults: defaults, loginItem: PreviewLoginItem())
    let model = Onboarding(settings: settings, defaults: defaults)
    let tools = SettingsPreviews.tools(for: settings)
    model.onApplyChoices = { tools.apply($0) }

    if step != .welcome {
        model.advance()
        model.setCalendarReminders(true)
    }
    if step == .permissions {
        model.setTool(.dictation, enabled: true)
        model.advance()
    }

    return SettingsPreviews.controller(settings: settings, tools: tools, onboarding: model).makePreview()
}
#endif
