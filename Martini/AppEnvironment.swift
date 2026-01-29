import Foundation

enum AppEnvironment {
    static let developerModeKey = "martini_developer_mode"

    static var isDeveloperMode: Bool {
        UserDefaults.standard.bool(forKey: developerModeKey)
    }

    static func setDeveloperMode(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: developerModeKey)
    }

    static var baseScriptsURL: String {
        if isDeveloperMode {
            return "https://dev.staging.trymartini.com/scripts/"
        }

        return "https://trymartini.com/scripts/"
    }

    static var pingURL: URL {
        guard let url = URL(string: baseScriptsURL) else {
            preconditionFailure("Invalid base scripts URL: \(baseScriptsURL)")
        }
        return url
    }

    static func realtimeProjectURL(projectId: String) -> URL? {
        let baseURL = isDeveloperMode
            ? "https://dev.staging.trymartini.com/scripts/sub/project.php"
            : "https://trymartini.com/scripts/sub/project.php"
        return URL(string: "\(baseURL)?projectId=\(projectId)")
    }
}
