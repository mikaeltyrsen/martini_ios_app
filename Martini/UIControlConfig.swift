import SwiftUI

enum UIControlConfig {
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
}
