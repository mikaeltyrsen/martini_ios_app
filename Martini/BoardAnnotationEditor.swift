import SwiftUI
import PencilKit

struct BoardAnnotationEditor: View {
    let title: String
    let aspectRatio: CGFloat
    let backgroundURL: URL?
    let initialDrawing: PKDrawing
    let onCancel: () -> Void
    let onSave: (PKDrawing) -> Void

    @State private var drawing: PKDrawing

    init(
        title: String,
        aspectRatio: CGFloat,
        backgroundURL: URL?,
        initialDrawing: PKDrawing = PKDrawing(),
        onCancel: @escaping () -> Void,
        onSave: @escaping (PKDrawing) -> Void
    ) {
        self.title = title
        self.aspectRatio = aspectRatio
        self.backgroundURL = backgroundURL
        self.initialDrawing = initialDrawing
        self.onCancel = onCancel
        self.onSave = onSave
        _drawing = State(initialValue: initialDrawing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    ZStack {
                        if let backgroundURL {
                            AsyncImage(url: backgroundURL) { phase in
                                switch phase {
                                case .empty:
                                    Color.black.opacity(0.08)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                case .failure:
                                    Color.black.opacity(0.08)
                                @unknown default:
                                    Color.black.opacity(0.08)
                                }
                            }
                        } else {
                            Color.white
                        }

                        PencilCanvasView(drawing: $drawing, showsToolPicker: true)
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Spacer(minLength: 12)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(drawing)
                    }
                }
            }
        }
    }
}

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var showsToolPicker: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.drawing = drawing
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let currentData = uiView.drawing.dataRepresentation()
        let incomingData = drawing.dataRepresentation()
        if currentData != incomingData {
            uiView.drawing = drawing
        }

        if let window = uiView.window, let toolPicker = PKToolPicker.shared(for: window) {
            toolPicker.setVisible(showsToolPicker, forFirstResponder: uiView)
            if showsToolPicker {
                toolPicker.addObserver(uiView)
                uiView.becomeFirstResponder()
            } else {
                toolPicker.removeObserver(uiView)
                uiView.resignFirstResponder()
            }
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        if let window = uiView.window, let toolPicker = PKToolPicker.shared(for: window) {
            toolPicker.removeObserver(uiView)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
