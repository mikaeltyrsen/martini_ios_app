import SwiftUI

struct MartiniLoader: View {
    var size: CGFloat = 25
    var lineWidth: CGFloat = 3
    var color: Color = .martiniAccentColor

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

//struct MartiniLoader: View {
//    
//    @State var isAnimating: Bool = false
//    let timing: Double
//    
//    let frame: CGSize
//    let primaryColor: Color
//    
//    init(color: Color = .black, size: CGFloat = 25, speed: Double = 0.2) {
//        timing = speed * 4
//        frame = CGSize(width: size, height: size)
//        primaryColor = color
//    }
//
//    var body: some View {
//        Circle()
//            .trim(from: isAnimating ? 0.9 : 0.8, to: 1.0)
//            .stroke(primaryColor,
//                    style: StrokeStyle(lineWidth:
//                        isAnimating ? frame.height / 8 : frame.height / 8,
//                                       lineCap: .round, lineJoin: .round)
//            )
//            .animation(Animation.easeInOut(duration: timing / 2).repeatForever(), value: isAnimating)
//            .rotationEffect(
//                Angle(degrees: isAnimating ? 360 : 0)
//            )
//            .animation(Animation.linear(duration: timing).repeatForever(autoreverses: false), value: isAnimating)
//            .frame(width: frame.width, height: frame.height, alignment: .center)
//            .rotationEffect(Angle(degrees: 360 * 0.15))
//            .onAppear {
//                isAnimating.toggle()
//            }
//    }
//}
