import SwiftUI

struct ScriptView: View {
    @EnvironmentObject private var authService: AuthService
    let targetDialogId: String?
    let targetFrameId: String?
    @State private var fontScale: CGFloat = UIControlConfig.scriptFontScaleDefault
    @GestureState private var magnifyBy: CGFloat = 1.0

    private let minFontScale: CGFloat = UIControlConfig.scriptFontScaleMin
    private let maxFontScale: CGFloat = UIControlConfig.scriptFontScaleMax
    private let baseFontSize: CGFloat = 16

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(scriptFrames) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            frameDivider(for: entry.frame)
                                .id(entry.frame.id)

                            if entry.blocks.isEmpty {
                                Text("No description provided for this frame.")
                                    .font(.system(size: baseFontSize * effectiveScale))
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(entry.blocks) { block in
                                    scriptBlockView(block)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .gesture(magnificationGesture)
            .safeAreaInset(edge: .bottom) {
                scriptToolbar(proxy: proxy)
            }
            .onAppear {
                scrollToTarget(using: proxy)
            }
            .onChange(of: targetDialogId) { _ in
                scrollToTarget(using: proxy)
            }
        }
    }

    private var effectiveScale: CGFloat {
        let scaled = fontScale * magnifyBy
        return min(max(scaled, minFontScale), maxFontScale)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = fontScale * value
                fontScale = min(max(newScale, minFontScale), maxFontScale)
            }
    }

    private var scriptFrames: [ScriptFrameEntry] {
        let sortedFrames = authService.frames.sorted { lhs, rhs in
            let lhsOrder = Int(lhs.frameOrder ?? "") ?? Int.max
            let rhsOrder = Int(rhs.frameOrder ?? "") ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            let lhsShoot = Int(lhs.frameShootOrder ?? "") ?? Int.max
            let rhsShoot = Int(rhs.frameShootOrder ?? "") ?? Int.max
            return lhsShoot < rhsShoot
        }

        return sortedFrames.map { frame in
            ScriptFrameEntry(
                frame: frame,
                blocks: ScriptParser.blocks(from: frame.description ?? "", frameId: frame.id)
            )
        }
    }

    private var hereFrameId: String? {
        authService.frames.first { $0.statusEnum == .here }?.id
    }

    @ViewBuilder
    private func frameDivider(for frame: Frame) -> some View {
        HStack(spacing: 12) {
            Text(frame.frameNumber > 0 ? "Frame \(frame.frameNumber)" : "Frame")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func scriptBlockView(_ block: ScriptBlock) -> some View {
        let textView = Text(block.text)
            .font(.system(size: baseFontSize * effectiveScale))
            .fontWeight(block.isDialog ? .bold : .regular)
            .foregroundStyle(block.isDialog ? Color.primary : Color.martiniDefaultDescriptionColor)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let dialogId = block.dialogId {
            textView
                .id(dialogId)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Color.martiniDefaultColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            textView
        }
    }

    @ViewBuilder
    private func scriptToolbar(proxy: ScrollViewProxy) -> some View {
        HStack {
            Button {
                scrollToHere(using: proxy)
            } label: {
                Label("Here", systemImage: "location.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.martiniDefaultColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(hereFrameId == nil)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func scrollToTarget(using proxy: ScrollViewProxy) {
        guard targetDialogId != nil || targetFrameId != nil else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                if let targetDialogId {
                    proxy.scrollTo(targetDialogId, anchor: .center)
                } else if let targetFrameId {
                    proxy.scrollTo(targetFrameId, anchor: .top)
                }
            }
        }
    }

    private func scrollToHere(using proxy: ScrollViewProxy) {
        guard let hereFrameId else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(hereFrameId, anchor: .top)
        }
    }
}

struct ScriptFrameEntry: Identifiable {
    let id: String
    let frame: Frame
    let blocks: [ScriptBlock]

    init(frame: Frame, blocks: [ScriptBlock]) {
        id = frame.id
        self.frame = frame
        self.blocks = blocks
    }
}

struct ScriptBlock: Identifiable, Hashable {
    let id: String
    let text: String
    let isDialog: Bool
    let dialogId: String?
}

enum ScriptParser {
    static func blocks(from html: String, frameId: String) -> [ScriptBlock] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let pattern = "(<blockquote[^>]*>(.*?)</blockquote>)|(<([a-zA-Z0-9]+)[^>]*class=\"[^\"]*qr-syntax[^\"]*\"[^>]*>(.*?)</\\4>)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [ScriptBlock(
                id: "\(frameId)-block-0",
                text: scriptTextFromHTML(html),
                isDialog: false,
                dialogId: nil
            )]
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else {
            return [ScriptBlock(
                id: "\(frameId)-block-0",
                text: scriptTextFromHTML(html),
                isDialog: false,
                dialogId: nil
            )]
        }

        var blocks: [ScriptBlock] = []
        var cursorLocation = 0
        var blockIndex = 0
        var dialogIndex = 0

        for match in matches {
            let matchRange = match.range(at: 0)
            if matchRange.location > cursorLocation {
                let beforeRange = NSRange(location: cursorLocation, length: matchRange.location - cursorLocation)
                let beforeHTML = nsHTML.substring(with: beforeRange)
                let beforeText = scriptTextFromHTML(beforeHTML)
                if !beforeText.isEmpty {
                    blocks.append(ScriptBlock(
                        id: "\(frameId)-block-\(blockIndex)",
                        text: beforeText,
                        isDialog: false,
                        dialogId: nil
                    ))
                    blockIndex += 1
                }
            }

            let blockquoteRange = match.range(at: 2)
            let classRange = match.range(at: 5)
            let dialogRange = blockquoteRange.location != NSNotFound ? blockquoteRange : classRange
            guard dialogRange.location != NSNotFound else {
                continue
            }
            let dialogHTML = nsHTML.substring(with: dialogRange)
            let dialogText = scriptTextFromHTML(dialogHTML)
            if !dialogText.isEmpty {
                let dialogId = "\(frameId)-dialog-\(dialogIndex)"
                blocks.append(ScriptBlock(
                    id: "\(frameId)-block-\(blockIndex)",
                    text: dialogText,
                    isDialog: true,
                    dialogId: dialogId
                ))
                blockIndex += 1
                dialogIndex += 1
            }

            cursorLocation = matchRange.location + matchRange.length
        }

        if cursorLocation < nsHTML.length {
            let trailingRange = NSRange(location: cursorLocation, length: nsHTML.length - cursorLocation)
            let trailingHTML = nsHTML.substring(with: trailingRange)
            let trailingText = scriptTextFromHTML(trailingHTML)
            if !trailingText.isEmpty {
                blocks.append(ScriptBlock(
                    id: "\(frameId)-block-\(blockIndex)",
                    text: trailingText,
                    isDialog: false,
                    dialogId: nil
                ))
            }
        }

        return blocks
    }
}

struct ScriptDescriptionPreview: View {
    let blocks: [ScriptBlock]
    let fontSize: CGFloat
    let onDialogTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                if let dialogId = block.dialogId {
                    Button {
                        logDescriptionTap(text: block.text, isDialog: true, dialogId: dialogId)
                        onDialogTap(dialogId)
                    } label: {
                        Text(block.text)
                            .font(.system(size: fontSize))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(block.text)
                        .font(.system(size: fontSize))
                        .foregroundStyle(Color.martiniDefaultDescriptionColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            logDescriptionTap(text: block.text, isDialog: false, dialogId: nil)
                        }
                }
            }
        }
    }

    private func logDescriptionTap(text: String, isDialog: Bool, dialogId: String?) {
        let sanitizedText = text.replacingOccurrences(of: "\n", with: "\\n")
        print("ScriptDescriptionPreview tap: isDialog=\(isDialog) dialogId=\(dialogId ?? "nil") text=\"\(sanitizedText)\"")
    }
}
