import SwiftUI
import WidgetKit

@main
struct CinderWidgetBundle: WidgetBundle {
    var body: some Widget {
        CinderWidget()
        CinderLiveActivity()
    }
}
