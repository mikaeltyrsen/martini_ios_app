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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rawMetadataLines.indices, id: \.self) { index in
                        Text(rawMetadataLines[index])
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .padding()
                .textSelection(.enabled)
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

    private var rawMetadataLines: [String] {
        RawMetadataFormatter.lines(for: item.metadata)
    }
}

private enum RawMetadataFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.decimalSeparator = "."
        return formatter
    }()

    static func lines(for value: JSONValue) -> [String] {
        render(value, indent: 0, key: nil, isListItem: false)
    }

    private static func render(
        _ value: JSONValue,
        indent: Int,
        key: String?,
        isListItem: Bool
    ) -> [String] {
        let indentString = String(repeating: "    ", count: indent)

        switch value {
        case .object(let object):
            let entries = object.sorted { $0.key < $1.key }
            guard !entries.isEmpty else {
                return singleLine("{}", indentString: indentString, key: key, isListItem: isListItem)
            }

            if let key {
                var lines = ["\(indentString)\(key):"]
                lines.append(contentsOf: entries.flatMap {
                    render($0.value, indent: indent + 1, key: $0.key, isListItem: false)
                })
                return lines
            }

            if isListItem {
                var lines = ["\(indentString)-"]
                lines.append(contentsOf: entries.flatMap {
                    render($0.value, indent: indent + 1, key: $0.key, isListItem: false)
                })
                return lines
            }

            return entries.flatMap {
                render($0.value, indent: indent, key: $0.key, isListItem: false)
            }
        case .array(let array):
            guard !array.isEmpty else {
                return singleLine("[]", indentString: indentString, key: key, isListItem: isListItem)
            }

            if let key {
                var lines = ["\(indentString)\(key):"]
                lines.append(contentsOf: array.flatMap {
                    render($0, indent: indent + 1, key: nil, isListItem: true)
                })
                return lines
            }

            if isListItem {
                var lines = ["\(indentString)-"]
                lines.append(contentsOf: array.flatMap {
                    render($0, indent: indent + 1, key: nil, isListItem: true)
                })
                return lines
            }

            return array.flatMap {
                render($0, indent: indent, key: nil, isListItem: true)
            }
        default:
            let valueString = primitiveString(for: value)
            return singleLine(valueString, indentString: indentString, key: key, isListItem: isListItem)
        }
    }

    private static func singleLine(
        _ value: String,
        indentString: String,
        key: String?,
        isListItem: Bool
    ) -> [String] {
        if let key {
            return ["\(indentString)\(key): \(value)"]
        }
        if isListItem {
            return ["\(indentString)- \(value)"]
        }
        return ["\(indentString)\(value)"]
    }

    private static func primitiveString(for value: JSONValue) -> String {
        switch value {
        case .string(let string):
            return string.isEmpty ? "\"\"" : string
        case .number(let number):
            return numberFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return ""
        }
    }
}
