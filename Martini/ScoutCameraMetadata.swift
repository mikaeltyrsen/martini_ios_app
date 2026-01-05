struct ScoutCameraMetadata {
    let cameraName: String
    let cameraMode: String
    let lensName: String
    let focalLength: String
    let frameLines: [FrameLineConfiguration]
}

enum ScoutCameraMetadataParser {
    static func parse(_ metadata: JSONValue) -> ScoutCameraMetadata? {
        guard let root = metadata.objectValue,
              let scoutArray = root["scout_camera"]?.arrayValue,
              let scoutEntry = scoutArray.first?.objectValue else {
            return nil
        }
        let capture = scoutEntry["capture"]?.arrayValue?.first?.objectValue
        let camera = scoutEntry["camera"]?.arrayValue?.first?.objectValue
        let lens = scoutEntry["lens"]?.arrayValue?.first?.objectValue

        let cameraName = [camera?["brand"]?.stringValue, camera?["model"]?.stringValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let modeName = camera?["mode"]?.objectValue?["name"]?.stringValue
        let cameraMode = modeName?.isEmpty == false ? modeName ?? "Unknown" : "Unknown"

        let lensName = [lens?["brand"]?.stringValue, lens?["series"]?.stringValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let focalLength = formattedFocalLength(
            capture?["active_focal_length_mm"]?.doubleValue
                ?? capture?["focal_length_mm"]?.doubleValue
        )

        let frameLines = parseFrameLines(from: capture)

        return ScoutCameraMetadata(
            cameraName: cameraName.isEmpty ? "Unknown" : cameraName,
            cameraMode: cameraMode,
            lensName: lensName.isEmpty ? "Unknown" : lensName,
            focalLength: focalLength,
            frameLines: frameLines
        )
    }

    private static func formattedFocalLength(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        let formatted: String
        if abs(value.rounded() - value) < 0.1 {
            formatted = "\(Int(value.rounded()))"
        } else {
            formatted = String(format: "%.1f", value)
        }
        return "\(formatted)mm"
    }

    private static func parseFrameLines(from capture: [String: JSONValue]?) -> [FrameLineConfiguration] {
        guard let entries = capture?["framelines"]?.arrayValue else { return [] }
        return entries.compactMap { entry in
            guard let object = entry.objectValue else { return nil }
            guard let label = object["label"]?.stringValue,
                  let option = FrameLineOption(rawValue: label) else {
                return nil
            }
            let color = FrameLineColor(rawValue: object["color"]?.stringValue ?? "") ?? .white
            let design = FrameLineDesign(rawValue: object["design"]?.stringValue ?? "") ?? .solid
            let opacity = object["opacity"]?.doubleValue ?? 0.8
            let thickness = object["thickness"]?.doubleValue ?? 2
            return FrameLineConfiguration(
                option: option,
                color: color,
                opacity: opacity,
                design: design,
                thickness: thickness
            )
        }
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case let .number(value):
            return value
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }
}
