import SwiftUI
import WidgetKit

private let flame = Color(red: 1.0, green: 0.48, blue: 0.10)
private let bg = Color(red: 0.11, green: 0.09, blue: 0.07)

struct CinderEntry: TimelineEntry {
    let date: Date
    let stats: Stats?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CinderEntry { CinderEntry(date: .now, stats: nil) }

    func getSnapshot(in context: Context, completion: @escaping (CinderEntry) -> Void) {
        Task { completion(CinderEntry(date: .now, stats: try? await Stats.fetch())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CinderEntry>) -> Void) {
        Task {
            let stats = try? await Stats.fetch()
            let now = Date.now
            var entries = [CinderEntry(date: now, stats: stats)]
            // Extra entries so Cinder's mood changes at reminder hours even without a refetch.
            let cal = Calendar.current
            for hour in stats?.settings?.reminder_hours ?? [19, 21, 22, 23] {
                if let d = cal.date(bySettingHour: hour, minute: 0, second: 5, of: now), d > now {
                    entries.append(CinderEntry(date: d, stats: stats))
                }
            }
            // Ask for a fresh fetch in 30 minutes; iOS decides the exact time.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }
}

struct CinderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CinderEntry

    var body: some View {
        if let s = entry.stats {
            let mood = CinderLogic.mood(s, now: entry.date)
            let stage = CinderLogic.displayedStage(s, mood: mood)
            let dayEnd = CinderLogic.dayEnd(now: entry.date, dayStartHour: s.dayStartHour)
            let done = s.isFromToday(now: entry.date) ? s.goalDone : 0
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        Image(systemName: mood == .lit ? "flame.fill" : mood == .dead ? "smoke" : "flame")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(s.streak.current)").font(.system(size: 20, weight: .black, design: .rounded))
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("🔥 \(s.streak.current)-day streak").font(.headline.weight(.heavy))
                    if mood == .lit {
                        Text("Goal done. Cinder is smug.").font(.caption)
                    } else {
                        HStack(spacing: 3) {
                            Text("Dies in")
                            Text(timerInterval: entry.date...dayEnd, countsDown: true).monospacedDigit()
                        }.font(.caption.weight(.semibold))
                        Text("\(done)/\(s.goalTarget) today").font(.caption2)
                    }
                }
            case .accessoryInline:
                Text(mood == .lit ? "🔥 \(s.streak.current) · goal done" : "🔥 \(s.streak.current) · \(done)/\(s.goalTarget) · feed Cinder")
            case .systemMedium:
                HStack(spacing: 12) {
                    Image(CinderLogic.imageName(stage: stage, mood: mood)).resizable().scaledToFit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(s.streak.current)").font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(mood == .lit ? flame : .white)
                        Text("day streak · \(CinderLogic.stages[stage].name)").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                        Text(CinderLogic.line(for: mood)).font(.caption.weight(.bold)).foregroundStyle(.white)
                        if mood != .lit {
                            HStack(spacing: 3) {
                                Text("Dies in")
                                Text(timerInterval: entry.date...dayEnd, countsDown: true).monospacedDigit().foregroundStyle(flame)
                            }.font(.caption.weight(.heavy))
                        }
                        ProgressView(value: mood == .lit ? 1 : min(Double(done) / Double(max(s.goalTarget, 1)), 1)).tint(flame)
                    }
                }
                .foregroundStyle(.white)
            default:
                VStack(spacing: 0) {
                    Image(CinderLogic.imageName(stage: stage, mood: mood)).resizable().scaledToFit()
                    Text("\(s.streak.current)").font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(mood == .lit ? flame : .white)
                    if mood == .lit {
                        Text("goal done").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                    } else {
                        Text(timerInterval: entry.date...dayEnd, countsDown: true)
                            .font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(flame)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        } else {
            VStack(spacing: 4) {
                Image("cinder-1-partial").resizable().scaledToFit()
                Text("Open Cinder").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            }
        }
    }
}

struct CinderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CinderWidget", provider: Provider()) { entry in
            CinderWidgetView(entry: entry)
                .containerBackground(bg, for: .widget)
                .widgetURL(URL(string: "cinder://open-anki"))
        }
        .configurationDisplayName("Cinder")
        .description("Your streak, Cinder's mood and the countdown to midnight.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
