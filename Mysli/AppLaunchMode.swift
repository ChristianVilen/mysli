import Foundation

enum AppLaunchMode {
    case production
    case xctest
    case settingsPreview
    #if DEBUG
    case xcodePreview
    #endif

    init(environment: [String: String], arguments: [String]) {
        if environment["XCTestConfigurationFilePath"] != nil {
            self = .xctest
            return
        }
        #if DEBUG
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self = .xcodePreview
            return
        }
        #endif
        if arguments.contains("--uitesting") {
            self = .settingsPreview
        } else {
            self = .production
        }
    }
}
