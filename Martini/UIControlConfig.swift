import SwiftUI

enum UIControlConfig {
    static let borderThicknessMin: Double = 1
    static let borderThicknessMax: Double = 12
    static let borderThicknessStep: Double = 0.5
    static let borderThicknessDefault: Double = 3.0

    static let borderRadiusMin: Int = 0
    static let borderRadiusMax: Int = 9
    static let borderRadiusStep: Int = 1
    static let borderRadiusDefault: Int = 5

    static let crossMarkThicknessMin: Double = 1
    static let crossMarkThicknessMax: Double = 12
    static let crossMarkThicknessStep: Double = 0.5
    static let crossMarkThicknessDefault: Double = 5.0

    static let boardSizingSmallScale: CGFloat = 0.84
    static let boardSizingMediumScale: CGFloat = 0.92
    static let boardSizingFullScale: CGFloat = 1.0
    static let boardSizingDefault: BoardSizingOption = .full
}
