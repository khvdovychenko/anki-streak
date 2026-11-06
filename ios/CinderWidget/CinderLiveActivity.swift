import ActivityKit
import SwiftUI
import WidgetKit

private let flame = Color(red: 1.0, green: 0.48, blue: 0.10)

struct CinderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CinderAttributes.self) { context in
            // Lock Screen
            let s = context.state
            HStack(spacing: 12) {
                Image(CinderLogic.imageName(stage: s.stage, mood: s.mood)).resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.done > 0 ? "\(s.done)/\(s.target) done. Not enough." : "\(s.streak)-day streak at risk")
                        .font(.headline.weight(.heavy))
                    HStack(spacing: 4) {
                        Text("Cinder dies in")
                        Text(timerInterval: Date.now...context.attributes.dayEnd, countsDown: true)
                            .monospacedDigit().foregroundStyle(flame)
                    }
                    .font(.subheadline.weight(.bold))
                    ProgressView(value: min(Double(s.done) / Double(max(s.target, 1)), 1)).tint(flame)
                }
            }
            .padding(14)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.11, green: 0.09, blue: 0.07))
            .widgetURL(URL(string: "cinder://open-anki"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(CinderLogic.imageName(stage: s.stage, mood: s.mood)).resizable().scaledToFit().frame(width: 48)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.attributes.dayEnd, countsDown: true)
                        .monospacedDigit().font(.title3.weight(.heavy)).foregroundStyle(flame).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(s.streak)-day streak · \(s.done)/\(s.target) today · feed me")
                        .font(.caption.weight(.bold))
                }
            } compactLeading: {
                Image(CinderLogic.imageName(stage: s.stage, mood: s.mood)).resizable().scaledToFit()
            } compactTrailing: {
                Text(timerInterval: Date.now...context.attributes.dayEnd, countsDown: true)
                    .monospacedDigit().font(.caption2.weight(.heavy)).foregroundStyle(flame).frame(width: 50)
            } minimal: {
                Image(CinderLogic.imageName(stage: s.stage, mood: s.mood)).resizable().scaledToFit()
            }
            .widgetURL(URL(string: "cinder://open-anki"))
        }
    }
}
