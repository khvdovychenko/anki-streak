import Foundation
import ActivityKit

/// Where the GitHub workflow publishes the stats. Set this to your own Pages URL.
enum Config {
    static let siteURL = URL(string: "https://khvdovychenko.github.io/anki-streak/")!
    static var statsURL: URL { siteURL.appendingPathComponent("data/stats.json") }
    static let ankiURL = URL(string: "anki://")!
    /// Until the real site is set, the app and widget show bundled demo data.
    static var isDemo: Bool { siteURL.absoluteString.contains("YOUR-GITHUB-NAME") }
}

// MARK: - The subset of docs/data/stats.json the app needs

struct Stats: Codable {
    struct Streak: Codable {
        var current: Int
        var longest: Int
        var reviewed_today: Bool
        var at_risk: Bool
    }
    struct Today: Codable {
        var reviews: Int
        var minutes: Double
    }
    struct Goal: Codable {
        var target: Int
        var done: Int
        var due_left: Int?
        var met: Bool
    }
    struct Totals: Codable {
        var study_days: Int
    }
    struct Settings: Codable {
        var reminder_hours: [Int]
        var day_start_hour: Int?
    }

    var today: String
    var generated_at: String
    var streak: Streak
    var today_stats: Today
    var goal: Goal?
    var totals: Totals
    var settings: Settings?

    static func fetch() async throws -> Stats {
        if Config.isDemo { return demo() }
        var request = URLRequest(url: Config.statsURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Stats.self, from: data)
    }

    /// Bundled sample data, dated today, used before the GitHub site exists.
    static func demo(scenario: DemoScenario = .partial) -> Stats {
        let url = Bundle.main.url(forResource: "demo-stats", withExtension: "json")!
        var s = try! JSONDecoder().decode(Stats.self, from: Data(contentsOf: url))
        s.today = CinderLogic.studyDayString(dayStartHour: s.dayStartHour)
        s.generated_at = ISO8601DateFormatter().string(from: .now)
        switch scenario {
        case .lit:
            s.streak.current = 34; s.streak.reviewed_today = true
            s.goal?.done = 42; s.goal?.met = true; s.today_stats.reviews = 42
        case .partial:
            break
        case .atRisk:
            s.streak.reviewed_today = false; s.streak.at_risk = true
            s.goal?.done = 0; s.today_stats.reviews = 0
        case .dead:
            s.streak.current = 0; s.streak.reviewed_today = false
            s.goal?.done = 0; s.today_stats.reviews = 0
        case .volcano:
            s.streak.current = 400; s.streak.longest = 400; s.streak.reviewed_today = true
            s.goal?.done = 55; s.goal?.met = true; s.today_stats.reviews = 55
        }
        return s
    }

    /// Is the snapshot from the current study day? If not, today's progress is unknown (0).
    func isFromToday(now: Date = .now) -> Bool {
        today == CinderLogic.studyDayString(now: now, dayStartHour: dayStartHour)
    }

    var dayStartHour: Int { settings?.day_start_hour ?? 4 }
    var firstReminderHour: Int { settings?.reminder_hours.first ?? 19 }

    var goalMet: Bool { goal?.met ?? streak.reviewed_today }
    var goalTarget: Int { goal?.target ?? 30 }
    var goalDone: Int { goal?.done ?? today_stats.reviews }
    var goalLeft: Int {
        let left = max(goalTarget - goalDone, 0)
        if let due = goal?.due_left, due > 0 { return min(left, due) }
        return left
    }
}

enum DemoScenario: String, CaseIterable, Identifiable {
    case lit = "Goal done", partial = "Half done", atRisk = "At risk", dead = "Dead", volcano = "Volcano"
    var id: String { rawValue }
}

// MARK: - Cinder's stage and mood, mirroring docs/cinder.js

enum Mood: String, Codable {
    case lit, partial, fading, dying, dead, new
}

enum CinderLogic {
    static let stages: [(name: String, from: Int)] = [
        ("Ash", 0), ("Spark", 1), ("Smoulder", 7), ("Blaze", 30), ("Inferno", 100), ("Volcano", 365),
    ]

    static func stage(for streak: Int) -> Int {
        stages.lastIndex { streak >= $0.from } ?? 0
    }

    static func mood(_ s: Stats, now: Date = .now) -> Mood {
        let fresh = s.isFromToday(now: now)
        if fresh && s.streak.reviewed_today { return s.goalMet ? .lit : .partial }
        // Snapshot from yesterday: the streak is alive only if yesterday counted.
        let streak = fresh ? s.streak.current : (s.streak.reviewed_today ? s.streak.current : 0)
        if streak > 0 {
            let hour = Calendar.current.component(.hour, from: now)
            return hour >= s.firstReminderHour || hour < s.dayStartHour ? .dying : .fading
        }
        return s.totals.study_days > 0 ? .dead : .new
    }

    static func displayedStage(_ s: Stats, mood: Mood) -> Int {
        mood == .dead ? 0 : max(1, stage(for: s.streak.current))
    }

    /// Asset name, e.g. "cinder-3-lit". "new" uses the calm "partial" face.
    static func imageName(stage: Int, mood: Mood) -> String {
        if stage == 0 || mood == .dead { return "cinder-0-dead" }
        return "cinder-\(stage)-\(mood == .new ? "partial" : mood.rawValue)"
    }

    /// Cinder's deadline: midnight. Like Anki, reviews until dayStartHour (4:00) still count,
    /// so between midnight and 4:00 the countdown shows that quiet grace period instead.
    static func dayEnd(now: Date = .now, dayStartHour: Int = 4) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        if hour < dayStartHour {
            return cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: now)!
        }
        return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!)
    }

    static func studyDayString(now: Date = .now, dayStartHour: Int = 4) -> String {
        let shifted = now.addingTimeInterval(TimeInterval(-dayStartHour * 3600))
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: shifted)
    }

    static func line(for mood: Mood) -> String {
        switch mood {
        case .lit: return "Fed and smug. See you tomorrow."
        case .partial: return "Still hungry. That wasn't a meal."
        case .fading: return "Getting cold over here."
        case .dying: return "Fading fast. Feed me."
        case .dead: return "Burnt out. One review brings me back."
        case .new: return "Hi. Feed me reviews and I grow."
        }
    }
}

// MARK: - Live Activity

struct CinderAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var streak: Int
        var done: Int
        var target: Int
        var mood: Mood
        var stage: Int
    }
    var dayEnd: Date
}
