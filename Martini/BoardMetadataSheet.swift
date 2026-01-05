import SwiftUI

struct BoardMetadataItem: Identifiable {
    let id = UUID()
    let boardName: String
    let metadata: JSONValue
    let assetURL: URL?
    let assetIsVideo: Bool
}

struct BoardMetadataSheet: View {
    let item: BoardMetadataItem
    @Environment(\.dismiss) private var dismiss
    @State private var showFrameLines: Bool

    init(item: BoardMetadataItem) {
        self.item = item
        let hasFrameLines = ScoutCameraMetadataParser.parse(item.metadata)?.frameLines.isEmpty == false
        _showFrameLines = State(initialValue: hasFrameLines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let scoutMetadata = ScoutCameraMetadataParser.parse(item.metadata) {
                    scoutMetadataView(scoutMetadata)
                } else {
                    ScrollView {
                        Text(formattedMetadata)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("\(item.boardName) Metadata")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func scoutMetadataView(_ metadata: ScoutCameraMetadata) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                scoutImageView(metadata)

                VStack(alignment: .leading, spacing: 12) {
                    metadataRow(title: "Camera", value: metadata.cameraName)
                    metadataRow(title: "Camera Mode", value: metadata.cameraMode)
                    metadataRow(title: "Lens", value: metadata.lensName)
                    metadataRow(title: "Focal Length", value: metadata.focalLength)

                    if !metadata.frameLines.isEmpty {
                        Button {
                            showFrameLines.toggle()
                        } label: {
                            HStack {
                                Text("Frame Lines")
                                Spacer()
                                Text(showFrameLines ? "On" : "Off")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func scoutImageView(_ metadata: ScoutCameraMetadata) -> some View {
        if let url = item.assetURL {
            if item.assetIsVideo {
                CachedVideoPlayerView(url: url)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .overlay {
                                if showFrameLines {
                                    FrameLineOverlayView(configurations: metadata.frameLines)
                                }
                            }
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.secondary.opacity(0.12))
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.secondary.opacity(0.12))
                            .overlay(
                                Text("Unable to load image.")
                                    .foregroundStyle(.secondary)
                            )
                            .frame(maxWidth: .infinity, minHeight: 200)
                    @unknown default:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.secondary.opacity(0.12))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .overlay(
                    Text("Preview unavailable.")
                        .foregroundStyle(.secondary)
                )
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private var formattedMetadata: String {
        let object = item.metadata.anyValue
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: object)
    }
}

private struct ScoutCameraMetadata {
    let cameraName: String
    let cameraMode: String
    let lensName: String
    let focalLength: String
    let frameLines: [FrameLineConfiguration]
}

private enum ScoutCameraMetadataParser {
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
