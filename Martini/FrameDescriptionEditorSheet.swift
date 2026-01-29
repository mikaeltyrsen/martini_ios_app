import SwiftUI
import UIKit

struct FrameDescriptionEditorSheet: View {
    let title: String
    let onSave: (String) async throws -> Void
    let onError: (Error) -> Void
    private let initialPlainText: String
    @StateObject private var editorState: RichTextEditorState
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialText: NSAttributedString,
        onSave: @escaping (String) async throws -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.onError = onError
        self.initialPlainText = initialText.string
        _editorState = StateObject(wrappedValue: RichTextEditorState(text: initialText))
    }

    var body: some View {
        NavigationStack {
            RichTextEditorView(state: editorState, becomeFirstResponder: true)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                do {
                                    isSaving = true
                                    defer { isSaving = false }
                                    let description = editorState.htmlRepresentation() ?? editorState.attributedText.string
                                    try await onSave(description)
                                    dismiss()
                                } catch {
                                    onError(error)
                                }
                            }
                        } label: {
                            if isSaving {
                                MartiniLoader()
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                        .accessibilityLabel(isSaving ? "Saving" : "Save")
                        .disabled(isSaving)
                        .tint(hasChanges ? .martiniAccentColor : .primary)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var hasChanges: Bool {
        editorState.attributedText.string != initialPlainText
    }
}
