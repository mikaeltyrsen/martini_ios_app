import SwiftUI
import UIKit

struct FrameDescriptionEditorSheet: View {
    let title: String
    let onSave: (String) async throws -> Void
    let onError: (Error) -> Void
    @StateObject private var editorState: RichTextEditorState
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
        _editorState = StateObject(wrappedValue: RichTextEditorState(text: initialText))
    }

    var body: some View {
        NavigationStack {
            RichTextEditorView(state: editorState, becomeFirstResponder: true)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            Task {
                                do {
                                    let description = editorState.htmlRepresentation() ?? editorState.attributedText.string
                                    try await onSave(description)
                                    dismiss()
                                } catch {
                                    onError(error)
                                }
                            }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
