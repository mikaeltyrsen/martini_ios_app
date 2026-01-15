import SwiftUI

struct ScriptView: View {
    @EnvironmentObject private var authService: AuthService
    let targetDialogId: String?
    let targetFrameId: String?
    @AppStorage("scriptFontScale") private var fontScale: Double = Double(UIControlConfig.scriptFontScaleDefault)
    @AppStorage("scriptDialogFontScale") private var dialogFontScale: Double = Double(UIControlConfig.scriptDialogFontScaleDefault)
    @AppStorage("scriptDialogFontScaleEnabled") private var isDialogFontScaleEnabled: Bool = UIControlConfig.scriptDialogFontScaleEnabledDefault
    @State private var isShowingSettings = false
    @State private var selectedCreativeId: String?
    @AppStorage("scriptShowBoard") private var showBoard: Bool = UIControlConfig.scriptShowBoardDefault
    @AppStorage("scriptShowFrameDivider") private var showFrameDivider: Bool = UIControlConfig.scriptShowFrameDividerDefault
    @AppStorage("scriptBoardScale") private var boardScale: Double = Double(UIControlConfig.scriptBoardScaleDefault)

    private let minFontScale: CGFloat = UIControlConfig.scriptFontScaleMin
    private let maxFontScale: CGFloat = UIControlConfig.scriptFontScaleMax
    private let minDialogFontScale: CGFloat = UIControlConfig.scriptDialogFontScaleMin
    private let maxDialogFontScale: CGFloat = UIControlConfig.scriptDialogFontScaleMax
    private let baseFontSize: CGFloat = 16
    private let baseBoardSize: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            let deviceMultiplier = deviceScaleMultiplier(for: geometry.size)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let creativeTitle = selectedCreativeTitle {
                            Text(creativeTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }

                        ForEach(scriptFrames) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                if showFrameDivider {
                                    frameDivider(for: entry.frame)
                                }

                                HStack(alignment: .top, spacing: 16) {
                                    if showBoard {
                                        boardReference(for: entry.frame, multiplier: deviceMultiplier)
                                    }

                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(entry.blocks) { block in
                                            scriptBlockView(block, multiplier: deviceMultiplier)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .id(entry.frame.id)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .navigationTitle("Script")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            creativeMenuContent
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Select creative")
                    }

                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            scrollToHere(using: proxy)
                        } label: {
                            Image(systemName: "location.fill")
                        }
                        .accessibilityLabel("Scroll to here")
                        .disabled(hereFrameId == nil)

                        Spacer()

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Script settings")
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    ScriptSettingsSheet(
                        fontScale: $fontScale,
                        dialogFontScale: $dialogFontScale,
                        isDialogFontScaleEnabled: $isDialogFontScaleEnabled,
                        showBoard: $showBoard,
                        showFrameDivider: $showFrameDivider,
                        boardScale: $boardScale
                    )
                        .presentationDetents([.medium])
                }
                .onAppear {
                    updateSelectedCreativeIfNeeded()
                    scrollToTarget(using: proxy)
                }
                .onChange(of: targetDialogId) { _ in
                    scrollToTarget(using: proxy)
                }
                .onChange(of: authService.creatives.map(\.id)) { _ in
                    updateSelectedCreativeIfNeeded()
                }
            }
        }
    }

    private var effectiveScale: CGFloat {
        let clamped = min(max(CGFloat(fontScale), minFontScale), maxFontScale)
        return clamped
    }

    private var effectiveDialogScale: CGFloat {
        guard isDialogFontScaleEnabled else {
            return effectiveScale
        }
        let clamped = min(max(CGFloat(dialogFontScale), minDialogFontScale), maxDialogFontScale)
        return clamped
    }

    private var effectiveBoardScale: CGFloat {
        let minScale = UIControlConfig.scriptBoardScaleMin
        let maxScale = UIControlConfig.scriptBoardScaleMax
        return min(max(CGFloat(boardScale), minScale), maxScale)
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

        let filteredFrames = sortedFrames.filter { frame in
            guard let selectedCreativeId else { return true }
            return frame.creativeId == selectedCreativeId
        }

        return filteredFrames.compactMap { frame in
            let blocks = ScriptParser.blocks(from: frame.description ?? "", frameId: frame.id)
            guard !blocks.isEmpty else { return nil }
            return ScriptFrameEntry(
                frame: frame,
                blocks: blocks
            )
        }
    }

    private var hereFrameId: String? {
        authService.frames.first { $0.statusEnum == .here }?.id
    }

    private var selectedCreativeTitle: String? {
        if let selectedCreativeId,
           let creative = authService.creatives.first(where: { $0.id == selectedCreativeId }) {
            return creative.title
        }
        return selectedCreativeId == nil ? "All Creatives" : nil
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
    private func scriptBlockView(_ block: ScriptBlock, multiplier: CGFloat) -> some View {
        let textView = Text(block.text)
            .font(.system(size: baseFontSize * (block.isDialog ? effectiveDialogScale : effectiveScale) * multiplier,
                          design: block.isDialog ? .monospaced : .default))
            .fontWeight(block.isDialog ? .bold : .regular)
            .foregroundStyle(block.isDialog ? Color.primary : Color.martiniDefaultDescriptionColor)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let dialogId = block.dialogId {
            textView
                .id(dialogId)
        } else {
            textView
        }
    }

    @ViewBuilder
    private func boardReference(for frame: Frame, multiplier: CGFloat) -> some View {
        let boardSize = baseBoardSize * effectiveBoardScale * multiplier

        VStack(alignment: .leading, spacing: 6) {
            FrameLayout(
                frame: frame,
                showStatusBadge: false,
                showFrameTimeOverlay: false,
                showTextBlock: false,
                enablesFullScreen: false,
                usePinnedBoardMarkupFallback: true
            )
            .frame(width: boardSize, height: boardSize * 0.7)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: boardSize, alignment: .leading)
    }

    private var creativeMenuContent: some View {
        Group {
            if authService.creatives.isEmpty {
                Text("No creatives available")
            } else {
                ForEach(authService.creatives) { creative in
                    Button {
                        selectedCreativeId = creative.id
                    } label: {
                        if creative.id == selectedCreativeId {
                            Label(creative.title, systemImage: "checkmark")
                        } else {
                            Text(creative.title)
                        }
                    }
                }
            }
        }
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

    private func updateSelectedCreativeIfNeeded() {
        let targetCreativeId = authService.frames.first { $0.id == targetFrameId }?.creativeId
        let fallbackCreativeId = authService.creatives.first?.id
        let preferredCreativeId = targetCreativeId ?? fallbackCreativeId
        guard let preferredCreativeId else { return }
        if selectedCreativeId == nil || !authService.creatives.contains(where: { $0.id == selectedCreativeId }) {
            selectedCreativeId = preferredCreativeId
        }
    }

    private func deviceScaleMultiplier(for size: CGSize) -> CGFloat {
        let step = UIControlConfig.scriptDeviceScaleStep
        guard step > 0 else { return 1 }
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = size.width > size.height
        if isPad {
            return powCGFloat(step, isLandscape ? 3 : 2)
        }
        return isLandscape ? step : 1
    }

    private func powCGFloat(_ base: CGFloat, _ exponent: Int) -> CGFloat {
        CGFloat(pow(Double(base), Double(exponent)))
    }
}

private struct ScriptSettingsSheet: View {
    @Binding var fontScale: Double
    @Binding var dialogFontScale: Double
    @Binding var isDialogFontScaleEnabled: Bool
    @Binding var showBoard: Bool
    @Binding var showFrameDivider: Bool
    @Binding var boardScale: Double

    private let minFontScale: CGFloat = UIControlConfig.scriptFontScaleMin
    private let maxFontScale: CGFloat = UIControlConfig.scriptFontScaleMax
    private let minDialogFontScale: CGFloat = UIControlConfig.scriptDialogFontScaleMin
    private let maxDialogFontScale: CGFloat = UIControlConfig.scriptDialogFontScaleMax
    private let minBoardScale: Double = Double(UIControlConfig.scriptBoardScaleMin)
    private let maxBoardScale: Double = Double(UIControlConfig.scriptBoardScaleMax)

    var body: some View {
        NavigationStack {
            Form {
                Section("Font Size") {
                    HStack {
                        Image(systemName: "textformat.size.smaller")
                        Slider(value: $fontScale, in: Double(minFontScale)...Double(maxFontScale))
                        Image(systemName: "textformat.size.larger")
                    }

                    Toggle("Size dialogs separate", isOn: $isDialogFontScaleEnabled)

                    if isDialogFontScaleEnabled {
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $dialogFontScale, in: Double(minDialogFontScale)...Double(maxDialogFontScale))
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                }

                Section("Board Reference") {
                    Toggle("Show Board", isOn: $showBoard)

                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(showBoard ? .primary : .secondary)
                        Slider(value: $boardScale, in: minBoardScale...maxBoardScale)
                            .disabled(!showBoard)
                        Image(systemName: "photo.fill")
                            .foregroundStyle(showBoard ? .primary : .secondary)
                    }
                }

                Section("Frame Divider") {
                    Toggle("Show Frame Divider", isOn: $showFrameDivider)
                }
            }
            .navigationTitle("Script Settings")
            .navigationBarTitleDisplayMode(.inline)
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
