//
//  MartiniLiveActivityBundle.swift
//  MartiniLiveActivity
//

import WidgetKit
import SwiftUI

@main
struct MartiniLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            MartiniLiveActivityWidget()
        }
    }
}
