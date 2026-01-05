import SwiftUI
import UIKit

struct FrameDescriptionEditorSheet: View {
    let title: String
    @StateObject private var editorState: RichTextEditorState
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialText: NSAttributedString) {
        self.title = title
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
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
