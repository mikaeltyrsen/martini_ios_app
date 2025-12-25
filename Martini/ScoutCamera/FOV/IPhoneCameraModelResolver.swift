import Foundation
import UIKit

struct IPhoneCameraModelResolver {
    static func currentModelName() -> String {
        let model = UIDevice.current.model
        let name = UIDevice.current.name
        if name.lowercased().contains("iphone") {
            return name
        }
        return model
    }
}
