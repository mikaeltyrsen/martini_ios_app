import SwiftUI
import UIKit

@MainActor
final class RichTextEditorState: ObservableObject {
    @Published var attributedText: NSAttributedString
    weak var textView: UITextView?
    let baseFont: UIFont
    let baseColor: UIColor

    init(text: NSAttributedString, baseFont: UIFont = .preferredFont(forTextStyle: .body), baseColor: UIColor = .label) {
        self.attributedText = text
        self.baseFont = baseFont
        self.baseColor = baseColor
    }

    func toggleBold() {
        toggleFontTrait(.traitBold)
    }

    func toggleItalic() {
        toggleFontTrait(.traitItalic)
    }

    func toggleUnderline() {
        toggleAttribute(
            key: .underlineStyle,
            enabledValue: NSUnderlineStyle.single.rawValue
        )
    }

    func toggleStrikethrough() {
        toggleAttribute(
            key: .strikethroughStyle,
            enabledValue: NSUnderlineStyle.single.rawValue
        )
    }

    func applyColor(_ color: UIColor) {
        applyAttribute(.foregroundColor, value: color)
    }

    func applyAlignment(_ alignment: NSTextAlignment) {
        applyParagraphStyle { style in
            style.alignment = alignment
        }
    }

    func toggleBlockQuote() {
        applyParagraphStyle { style in
            let isQuoted = style.firstLineHeadIndent > 0 || style.headIndent > 0
            if isQuoted {
                style.firstLineHeadIndent = 0
                style.headIndent = 0
                style.paragraphSpacingBefore = 0
                style.paragraphSpacing = 0
            } else {
                style.firstLineHeadIndent = 16
                style.headIndent = 16
                style.paragraphSpacingBefore = 4
                style.paragraphSpacing = 8
            }
        }
    }

    func clearFormatting() {
        guard let textView else { return }
        let defaultAttributes = defaultTextAttributes()
        let selectedRange = textView.selectedRange

        if selectedRange.length == 0 {
            textView.typingAttributes = defaultAttributes
            return
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        mutableText.setAttributes(defaultAttributes, range: selectedRange)
        applyChanges(mutableText, selectedRange: selectedRange)
    }

    func htmlRepresentation() -> String? {
        let options: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let data = try? attributedText.data(from: NSRange(location: 0, length: attributedText.length), documentAttributes: options) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange

        if selectedRange.length == 0 {
            let currentFont = (textView.typingAttributes[.font] as? UIFont) ?? baseFont
            textView.typingAttributes[.font] = fontByTogglingTrait(font: currentFont, trait: trait)
            return
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        mutableText.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
            let font = (value as? UIFont) ?? baseFont
            let updatedFont = fontByTogglingTrait(font: font, trait: trait)
            mutableText.addAttribute(.font, value: updatedFont, range: range)
        }

        applyChanges(mutableText, selectedRange: selectedRange)
    }

    private func toggleAttribute(key: NSAttributedString.Key, enabledValue: Int) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange

        if selectedRange.length == 0 {
            var typingAttributes = textView.typingAttributes
            let currentValue = typingAttributes[key] as? Int ?? 0
            typingAttributes[key] = currentValue == 0 ? enabledValue : 0
            textView.typingAttributes = typingAttributes
            return
        }

        let currentValue = textView.attributedText.attribute(key, at: selectedRange.location, effectiveRange: nil) as? Int ?? 0
        let newValue = currentValue == 0 ? enabledValue : 0
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)

        if newValue == 0 {
            mutableText.removeAttribute(key, range: selectedRange)
        } else {
            mutableText.addAttribute(key, value: newValue, range: selectedRange)
        }

        applyChanges(mutableText, selectedRange: selectedRange)
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange

        if selectedRange.length == 0 {
            var typingAttributes = textView.typingAttributes
            typingAttributes[key] = value
            textView.typingAttributes = typingAttributes
            return
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        mutableText.addAttribute(key, value: value, range: selectedRange)
        applyChanges(mutableText, selectedRange: selectedRange)
    }

    private func applyParagraphStyle(_ update: (NSMutableParagraphStyle) -> Void) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange
        let paragraphRange: NSRange

        if selectedRange.length == 0 {
            paragraphRange = (textView.text as NSString).paragraphRange(for: selectedRange)
        } else {
            paragraphRange = (textView.text as NSString).paragraphRange(for: selectedRange)
        }

        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let currentStyle = (mutableText.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
        let updatedStyle = currentStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        update(updatedStyle)

        mutableText.addAttribute(.paragraphStyle, value: updatedStyle, range: paragraphRange)
        applyChanges(mutableText, selectedRange: selectedRange)
    }

    private func applyChanges(_ text: NSAttributedString, selectedRange: NSRange) {
        guard let textView else { return }
        textView.attributedText = text
        textView.selectedRange = selectedRange
        attributedText = text
    }

    private func fontByTogglingTrait(font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }

        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            return font
        }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private func defaultTextAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural

        return [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}

struct RichTextEditorView: UIViewRepresentable {
    @ObservedObject var state: RichTextEditorState
    var becomeFirstResponder: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = .init(top: 12, left: 8, bottom: 12, right: 8)
        textView.adjustsFontForContentSizeCategory = true
        textView.attributedText = state.attributedText
        textView.typingAttributes = [
            .font: state.baseFont,
            .foregroundColor: state.baseColor
        ]
        textView.inputAccessoryView = makeAccessoryToolbar()
        state.textView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if !uiView.attributedText.isEqual(to: state.attributedText) {
            uiView.attributedText = state.attributedText
        }

        if becomeFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }

        state.textView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    private func makeAccessoryToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.items = [
            accessoryButton(systemName: "bold") { state.toggleBold() },
            accessoryButton(systemName: "italic") { state.toggleItalic() },
            accessoryButton(systemName: "underline") { state.toggleUnderline() },
            accessoryButton(systemName: "strikethrough") { state.toggleStrikethrough() },
            UIBarButtonItem(
                image: UIImage(systemName: "paintpalette"),
                primaryAction: nil,
                menu: UIMenu(children: [
                    UIAction(title: "Default") { _ in
                        state.applyColor(.label)
                    },
                    UIAction(title: "Red") { _ in
                        state.applyColor(.systemRed)
                    },
                    UIAction(title: "Orange") { _ in
                        state.applyColor(.systemOrange)
                    },
                    UIAction(title: "Green") { _ in
                        state.applyColor(.systemGreen)
                    },
                    UIAction(title: "Blue") { _ in
                        state.applyColor(.systemBlue)
                    }
                ])
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "text.alignleft"),
                primaryAction: nil,
                menu: UIMenu(children: [
                    UIAction(title: "Left", image: UIImage(systemName: "text.alignleft")) { _ in
                        state.applyAlignment(.left)
                    },
                    UIAction(title: "Center", image: UIImage(systemName: "text.aligncenter")) { _ in
                        state.applyAlignment(.center)
                    },
                    UIAction(title: "Right", image: UIImage(systemName: "text.alignright")) { _ in
                        state.applyAlignment(.right)
                    },
                    UIAction(title: "Justified", image: UIImage(systemName: "text.justify")) { _ in
                        state.applyAlignment(.justified)
                    }
                ])
            ),
            accessoryButton(systemName: "text.quote") { state.toggleBlockQuote() },
            accessoryButton(systemName: "eraser") { state.clearFormatting() }
        ]
        toolbar.sizeToFit()
        return toolbar
    }

    private func accessoryButton(systemName: String, action: @escaping () -> Void) -> UIBarButtonItem {
        let action = UIAction { _ in
            action()
        }
        return UIBarButtonItem(image: UIImage(systemName: systemName), primaryAction: action)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let state: RichTextEditorState

        init(state: RichTextEditorState) {
            self.state = state
        }

        func textViewDidChange(_ textView: UITextView) {
            state.attributedText = textView.attributedText
        }
    }
}
