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
                    ToolbarItemGroup(placement: .keyboard) {
                        Button {
                            editorState.toggleBold()
                        } label: {
                            Image(systemName: "bold")
                        }
                        Button {
                            editorState.toggleItalic()
                        } label: {
                            Image(systemName: "italic")
                        }
                        Button {
                            editorState.toggleUnderline()
                        } label: {
                            Image(systemName: "underline")
                        }
                        Button {
                            editorState.toggleStrikethrough()
                        } label: {
                            Image(systemName: "strikethrough")
                        }
                        Menu {
                            Button("Default") {
                                editorState.applyColor(.label)
                            }
                            Button("Red") {
                                editorState.applyColor(.systemRed)
                            }
                            Button("Orange") {
                                editorState.applyColor(.systemOrange)
                            }
                            Button("Green") {
                                editorState.applyColor(.systemGreen)
                            }
                            Button("Blue") {
                                editorState.applyColor(.systemBlue)
                            }
                        } label: {
                            Image(systemName: "paintpalette")
                        }
                        Menu {
                            Button {
                                editorState.applyAlignment(.left)
                            } label: {
                                Label("Left", systemImage: "text.alignleft")
                            }
                            Button {
                                editorState.applyAlignment(.center)
                            } label: {
                                Label("Center", systemImage: "text.aligncenter")
                            }
                            Button {
                                editorState.applyAlignment(.right)
                            } label: {
                                Label("Right", systemImage: "text.alignright")
                            }
                            Button {
                                editorState.applyAlignment(.justified)
                            } label: {
                                Label("Justified", systemImage: "text.justify")
                            }
                        } label: {
                            Image(systemName: "text.alignleft")
                        }
                        Button {
                            editorState.toggleBlockQuote()
                        } label: {
                            Image(systemName: "text.quote")
                        }
                        Button {
                            editorState.clearFormatting()
                        } label: {
                            Image(systemName: "eraser")
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
