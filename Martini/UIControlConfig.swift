import SwiftUI

enum UIControlConfig {
    static let showDescriptionsDefault: Bool = true
    static let showFullDescriptionsDefault: Bool = false
    static let showGridTagsDefault: Bool = false
    static let showDoneCrossesDefault: Bool = true

    static let gridSizeMin: Int = 1
    static let gridSizeMax: Int = 4
    static let gridSizeStep: Int = 1
    static let gridSizeDefault: Int = 1

    static let gridFontSizeMin: Int = 1
    static let gridFontSizeMax: Int = 5
    static let gridFontSizeStep: Int = 1
    static let gridFontSizeDefault: Int = 3

    static let borderThicknessMin: Double = 1
    static let borderThicknessMax: Double = 9
    static let borderThicknessStep: Double = 1
    static let borderThicknessDefault: Double = 5.0

    static let borderRadiusMin: Int = 0
    static let borderRadiusMax: Int = 17
    static let borderRadiusStep: Int = 1
    static let borderRadiusDefault: Int = 9

    static let crossMarkThicknessMin: Double = 1
    static let crossMarkThicknessMax: Double = 9
    static let crossMarkThicknessStep: Double = 1
    static let crossMarkThicknessDefault: Double = 5.0

    static let boardSizingSmallScale: CGFloat = 0.6
    static let boardSizingMediumScale: CGFloat = 0.8
    static let boardSizingFullScale: CGFloat = 1.0
    static let boardSizingDefault: BoardSizingOption = .full

    static let scriptFontScaleMin: CGFloat = 0.8
    static let scriptFontScaleMax: CGFloat = 1.8
    static let scriptFontScaleDefault: CGFloat = 1.0
    static let scriptDialogFontScaleMin: CGFloat = 0.8
    static let scriptDialogFontScaleMax: CGFloat = 1.8
    static let scriptDialogFontScaleDefault: CGFloat = 1.0
    static let scriptDialogFontScaleEnabledDefault: Bool = false

    static let scriptShowBoardDefault: Bool = true
    static let scriptShowFrameDividerDefault: Bool = true
    static let scriptBoardScaleMin: CGFloat = 0.6
    static let scriptBoardScaleMax: CGFloat = 1.6
    static let scriptBoardScaleDefault: CGFloat = 1.0
    static let scriptDeviceScaleStep: CGFloat = 1.25
}
