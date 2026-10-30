import Foundation

enum AppLaunchMode {
    case production
    case xctest
    case settingsPreview

    init(environment: [String: String], arguments: [String]) {
        if environment["XCTestConfigurationFilePath"] != nil {
            self = .xctest
        } else if arguments.contains("--uitesting") {
            self = .settingsPreview
        } else {
            self = .production
        }
    }
}
