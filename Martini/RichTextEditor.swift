import SwiftUI
import UIKit

@MainActor
final class RichTextEditorState: ObservableObject {
    @Published var attributedText: NSAttributedString
    weak var textView: UITextView?
    let baseFont: UIFont
    let baseColor: UIColor
    var toolbarButtons: ToolbarButtons?

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
        guard let textView else { return }
        let selectedRange = textView.selectedRange
        let paragraphRange = (textView.text as NSString).paragraphRange(for: selectedRange)
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let currentStyle = (mutableText.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
        let updatedStyle = currentStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        let isQuoted = isDialogBlockquote(in: paragraphRange, using: mutableText)
            || currentStyle.firstLineHeadIndent > 0
            || currentStyle.headIndent > 0

        if isQuoted {
            updatedStyle.firstLineHeadIndent = 0
            updatedStyle.headIndent = 0
            updatedStyle.paragraphSpacingBefore = 0
            updatedStyle.paragraphSpacing = 0
            mutableText.removeAttribute(dialogBlockquoteAttribute, range: paragraphRange)
            updateFontTrait(in: paragraphRange, text: mutableText, trait: .traitBold, shouldAdd: false)
        } else {
            updatedStyle.firstLineHeadIndent = 0
            updatedStyle.headIndent = 0
            updatedStyle.paragraphSpacingBefore = 4
            updatedStyle.paragraphSpacing = 8
            mutableText.addAttribute(dialogBlockquoteAttribute, value: true, range: paragraphRange)
            updateFontTrait(in: paragraphRange, text: mutableText, trait: .traitBold, shouldAdd: true)
        }

        mutableText.addAttribute(.paragraphStyle, value: updatedStyle, range: paragraphRange)
        applyChanges(mutableText, selectedRange: selectedRange)
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
        let nsString = attributedText.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let traitCollection = textView?.traitCollection ?? UITraitCollection.current
        var htmlParagraphs: [String] = []

        nsString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, range, _, _ in
            let paragraphStyle = self.attributedText.attribute(.paragraphStyle, at: max(range.location, 0), effectiveRange: nil) as? NSParagraphStyle
            let alignmentStyle = self.htmlParagraphAlignmentStyle(paragraphStyle)
            let isBlockQuote = self.isDialogBlockquote(in: range, using: self.attributedText)
                || self.isBlockQuoteParagraph(paragraphStyle)
            let paragraphContent = self.htmlContent(in: range, source: nsString, traitCollection: traitCollection)
            let resolvedContent = paragraphContent.isEmpty ? "<br>" : paragraphContent
            let styleAttribute = alignmentStyle.map { " style=\"\($0)\"" } ?? ""
            let paragraphHTML = "<p\(styleAttribute)>\(resolvedContent)</p>"
            if isBlockQuote {
                let blockquoteStyle = alignmentStyle.map { " style=\"\($0)\"" } ?? ""
                let blockquoteAttributes = " data-type=\"dialog\"\(blockquoteStyle)"
                let blockquoteParagraphHTML = "<p>\(resolvedContent)</p>"
                htmlParagraphs.append("<blockquote\(blockquoteAttributes)>\(blockquoteParagraphHTML)</blockquote>")
            } else {
                htmlParagraphs.append(paragraphHTML)
            }
        }

        let html = htmlParagraphs.joined()
        return html.isEmpty ? nil : html
    }

    private func escapeHTML(_ string: String) -> String {
        var escaped = string
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]

        for (target, replacement) in replacements {
            escaped = escaped.replacingOccurrences(of: target, with: replacement)
        }

        return escaped
    }

    private func htmlParagraphAlignmentStyle(_ style: NSParagraphStyle?) -> String? {
        guard let alignment = style?.alignment else { return nil }

        switch alignment {
        case .center:
            return "text-align: center;"
        case .right:
            return "text-align: right;"
        case .justified:
            return "text-align: justify;"
        case .left:
            return "text-align: left;"
        case .natural:
            return nil
        @unknown default:
            return nil
        }
    }

    private func isBlockQuoteParagraph(_ style: NSParagraphStyle?) -> Bool {
        guard let style else { return false }
        return style.firstLineHeadIndent > 0 || style.headIndent > 0
    }

    private func isDialogBlockquote(in range: NSRange, using text: NSAttributedString) -> Bool {
        var isDialog = false
        text.enumerateAttribute(dialogBlockquoteAttribute, in: range, options: []) { value, _, stop in
            if (value as? Bool) == true {
                isDialog = true
                stop.pointee = true
            }
        }
        return isDialog
    }

    private func htmlContent(
        in range: NSRange,
        source: NSString,
        traitCollection: UITraitCollection
    ) -> String {
        var segments: [String] = []

        attributedText.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
            let rawText = source.substring(with: runRange)
            let escapedText = escapeHTML(rawText)
            let styledText = applyHTMLStyles(
                escapedText,
                attributes: attributes,
                traitCollection: traitCollection
            )
            segments.append(styledText)
        }

        return segments.joined()
    }

    private func applyHTMLStyles(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        traitCollection: UITraitCollection
    ) -> String {
        var wrappedText = text

        if let color = attributes[.foregroundColor] as? UIColor,
           let colorString = htmlRGBColorString(from: color, traitCollection: traitCollection),
           !colorsEqual(color, baseColor, traitCollection: traitCollection) {
            wrappedText = "<span style=\"color: \(colorString);\">\(wrappedText)</span>"
        }

        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            wrappedText = "<u>\(wrappedText)</u>"
        }

        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            wrappedText = "<s>\(wrappedText)</s>"
        }

        let font = (attributes[.font] as? UIFont) ?? baseFont
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.traitItalic) {
            wrappedText = "<em>\(wrappedText)</em>"
        }
        if traits.contains(.traitBold) {
            wrappedText = "<strong>\(wrappedText)</strong>"
        }

        return wrappedText
    }

    private func htmlRGBColorString(from color: UIColor, traitCollection: UITraitCollection) -> String? {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let redValue = Int(round(red * 255))
        let greenValue = Int(round(green * 255))
        let blueValue = Int(round(blue * 255))
        return "rgb(\(redValue), \(greenValue), \(blueValue))"
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
        updateToolbarState(from: textView)
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

    private func updateFontTrait(
        in range: NSRange,
        text: NSMutableAttributedString,
        trait: UIFontDescriptor.SymbolicTraits,
        shouldAdd: Bool
    ) {
        text.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? UIFont) ?? baseFont
            let updatedFont = shouldAdd
                ? fontByAddingTrait(font: font, trait: trait)
                : fontByRemovingTrait(font: font, trait: trait)
            text.addAttribute(.font, value: updatedFont, range: subrange)
        }
    }

    private func fontByAddingTrait(font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private func fontByRemovingTrait(font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.remove(trait)
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

    func updateToolbarState(from textView: UITextView) {
        guard let toolbarButtons else { return }

        let attributes = currentAttributes(from: textView)
        let font = (attributes[.font] as? UIFont) ?? baseFont
        let traits = font.fontDescriptor.symbolicTraits
        let isBold = traits.contains(.traitBold)
        let isItalic = traits.contains(.traitItalic)
        let isUnderline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        let isStrikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0

        let paragraphStyle = (attributes[.paragraphStyle] as? NSParagraphStyle)
        let alignment = paragraphStyle?.alignment ?? .natural
        let isCustomAlignment = alignment != .natural && alignment != .left
        let paragraphRange = (textView.text as NSString).paragraphRange(for: textView.selectedRange)
        let isQuote = isDialogBlockquote(in: paragraphRange, using: textView.attributedText)
            || (paragraphStyle?.firstLineHeadIndent ?? 0) > 0
            || (paragraphStyle?.headIndent ?? 0) > 0

        let foregroundColor = (attributes[.foregroundColor] as? UIColor) ?? baseColor
        let isCustomColor = !colorsEqual(foregroundColor, baseColor, traitCollection: textView.traitCollection)

        updateToolbarButton(toolbarButtons.bold, isActive: isBold)
        updateToolbarButton(toolbarButtons.italic, isActive: isItalic)
        updateToolbarButton(toolbarButtons.underline, isActive: isUnderline)
        updateToolbarButton(toolbarButtons.strikethrough, isActive: isStrikethrough)
        updateToolbarButton(toolbarButtons.color, isActive: isCustomColor)
        updateToolbarButton(toolbarButtons.alignment, isActive: isCustomAlignment)
        updateToolbarButton(toolbarButtons.quote, isActive: isQuote)
    }

    private func updateToolbarButton(_ button: UIButton, isActive: Bool) {
        let highlightColor = UIColor(named: "MartiniDefaultColor") ?? UIColor.systemBlue
        button.backgroundColor = isActive ? highlightColor : .clear
        button.tintColor = isActive ? .white : .label
    }

    private func currentAttributes(from textView: UITextView) -> [NSAttributedString.Key: Any] {
        if textView.attributedText.length == 0 {
            return textView.typingAttributes
        }

        let selectedRange = textView.selectedRange
        if selectedRange.length == 0 {
            let location = min(max(selectedRange.location, 0), textView.attributedText.length - 1)
            return textView.attributedText.attributes(at: location, effectiveRange: nil)
        }

        return textView.attributedText.attributes(at: selectedRange.location, effectiveRange: nil)
    }

    private func colorsEqual(_ lhs: UIColor, _ rhs: UIColor, traitCollection: UITraitCollection) -> Bool {
        let lhsResolved = lhs.resolvedColor(with: traitCollection)
        let rhsResolved = rhs.resolvedColor(with: traitCollection)
        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0

        if lhsResolved.getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
           rhsResolved.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha) {
            let epsilon: CGFloat = 0.01
            return abs(lhsRed - rhsRed) < epsilon
                && abs(lhsGreen - rhsGreen) < epsilon
                && abs(lhsBlue - rhsBlue) < epsilon
                && abs(lhsAlpha - rhsAlpha) < epsilon
        }

        return lhsResolved.isEqual(rhsResolved)
    }
}

struct ToolbarButtons {
    let bold: UIButton
    let italic: UIButton
    let underline: UIButton
    let strikethrough: UIButton
    let color: UIButton
    let alignment: UIButton
    let quote: UIButton
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
        state.updateToolbarState(from: textView)
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
        state.updateToolbarState(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    private func makeAccessoryToolbar() -> UIView {
        let toolbar = UIToolbar()
        toolbar.isTranslucent = false
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.compactAppearance = appearance

        let boldButton = accessoryButton(systemName: "bold") { [weak state] in
            state?.toggleBold()
        }
        let italicButton = accessoryButton(systemName: "italic") { [weak state] in
            state?.toggleItalic()
        }
        let underlineButton = accessoryButton(systemName: "underline") { [weak state] in
            state?.toggleUnderline()
        }
        let strikethroughButton = accessoryButton(systemName: "strikethrough") { [weak state] in
            state?.toggleStrikethrough()
        }
        let colorButton = accessoryMenuButton(
            systemName: "paintpalette",
            menu: makeColorMenu()
        )
        let alignmentButton = accessoryMenuButton(
            systemName: "text.alignleft",
            menu: makeAlignmentMenu()
        )
        let quoteButton = accessoryButton(systemName: "text.quote") { [weak state] in
            state?.toggleBlockQuote()
        }

        state.toolbarButtons = ToolbarButtons(
            bold: boldButton,
            italic: italicButton,
            underline: underlineButton,
            strikethrough: strikethroughButton,
            color: colorButton,
            alignment: alignmentButton,
            quote: quoteButton
        )

        toolbar.items = [
            UIBarButtonItem(customView: boldButton),
            UIBarButtonItem(customView: italicButton),
            UIBarButtonItem(customView: underlineButton),
            UIBarButtonItem(customView: strikethroughButton),
            UIBarButtonItem(customView: colorButton),
            UIBarButtonItem(customView: alignmentButton),
            UIBarButtonItem(customView: quoteButton)
        ]
        toolbar.sizeToFit()
        toolbar.backgroundColor = .clear

        let spacerHeight: CGFloat = 8
        let containerHeight = toolbar.bounds.height + spacerHeight
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: containerHeight))
        container.backgroundColor = .clear
        container.autoresizingMask = [.flexibleWidth]

        toolbar.frame = CGRect(x: 0, y: 0, width: container.bounds.width, height: toolbar.bounds.height)
        toolbar.autoresizingMask = [.flexibleWidth]
        container.addSubview(toolbar)

        let spacer = UIView(frame: CGRect(x: 0, y: toolbar.bounds.height, width: container.bounds.width, height: spacerHeight))
        spacer.backgroundColor = .clear
        spacer.autoresizingMask = [.flexibleWidth]
        container.addSubview(spacer)

        return container
    }

    private func accessoryButton(systemName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        return button
    }

    private func accessoryMenuButton(systemName: String, menu: UIMenu) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = .init(top: 6, left: 6, bottom: 6, right: 6)
        button.showsMenuAsPrimaryAction = true
        button.menu = menu
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        return button
    }

    private func makeColorMenu() -> UIMenu {
        let defaultIcon = UIImage(systemName: "circle.slash")
        let redIcon = coloredMenuIcon(color: .systemRed)
        let orangeIcon = coloredMenuIcon(color: .systemOrange)
        let greenIcon = coloredMenuIcon(color: .systemGreen)
        let blueIcon = coloredMenuIcon(color: .systemBlue)
        let pinkColor = UIColor(named: "MartiniPink") ?? .systemPink
        let purpleColor = UIColor(named: "MartiniPurple") ?? .systemPurple
        let pinkIcon = coloredMenuIcon(color: pinkColor)
        let purpleIcon = coloredMenuIcon(color: purpleColor)

        return UIMenu(children: [
            UIAction(title: "Default", image: defaultIcon) { [weak state] _ in
                guard let state else { return }
                state.applyColor(state.baseColor)
            },
            UIAction(title: "Red", image: redIcon) { [weak state] _ in
                state?.applyColor(.systemRed)
            },
            UIAction(title: "Orange", image: orangeIcon) { [weak state] _ in
                state?.applyColor(.systemOrange)
            },
            UIAction(title: "Green", image: greenIcon) { [weak state] _ in
                state?.applyColor(.systemGreen)
            },
            UIAction(title: "Blue", image: blueIcon) { [weak state] _ in
                state?.applyColor(.systemBlue)
            },
            UIAction(title: "Purple", image: purpleIcon) { [weak state] _ in
                state?.applyColor(purpleColor)
            },
            UIAction(title: "Pink", image: pinkIcon) { [weak state] _ in
                state?.applyColor(pinkColor)
            }
        ])
    }

    private func makeAlignmentMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Left", image: UIImage(systemName: "text.alignleft")) { [weak state] _ in
                state?.applyAlignment(.left)
            },
            UIAction(title: "Center", image: UIImage(systemName: "text.aligncenter")) { [weak state] _ in
                state?.applyAlignment(.center)
            },
            UIAction(title: "Right", image: UIImage(systemName: "text.alignright")) { [weak state] _ in
                state?.applyAlignment(.right)
            },
            UIAction(title: "Justified", image: UIImage(systemName: "text.justify")) { [weak state] _ in
                state?.applyAlignment(.justified)
            }
        ])
    }

    private func coloredMenuIcon(color: UIColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let state: RichTextEditorState

        init(state: RichTextEditorState) {
            self.state = state
        }

        func textViewDidChange(_ textView: UITextView) {
            state.attributedText = textView.attributedText
            state.updateToolbarState(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            state.updateToolbarState(from: textView)
        }
    }
}
