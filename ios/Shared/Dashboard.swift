import Foundation

// Types for the analytics sections of docs/data/stats.json.

struct HeatDay: Codable { var date: String; var reviews: Int; var minutes: Double }
struct Week: Codable { var week: String; var reviews: Int; var minutes: Int; var retention: Double? }
struct HourStat: Codable { var hour: Int; var reviews: Int; var retention: Double? }
struct WeekdayStat: Codable { var weekday: Int; var reviews: Int; var study_days: Int }
struct Ratings: Codable { var again: Int; var hard: Int; var good: Int; var easy: Int }
struct ForecastDay: Codable { var date: String; var due: Int }

struct Deck: Codable {
    struct Cards: Codable { var new: Int; var learning: Int; var young: Int; var mature: Int; var suspended: Int; var leeches: Int }
    var name: String
    var reviews_total: Int
    var reviews_30d: Int
    var retention_30d: Double?
    var avg_seconds: Double?
    var cards: Cards
}

struct Bucket: Codable, Identifiable {
    var label: String
    var n: Int
    var rate: Double?
    var lo: Double?
    var hi: Double?
    var enough: Bool
    var id: String { label }
}

struct DropFinding: Codable {
    var base_label: String; var base: Double
    var worst_label: String; var worst: Double
    var drop_pp: Double; var significant: Bool
}

struct HesitationFinding: Codable {
    var fast_label: String; var slow_label: String
    var fast: Double; var slow: Double
    var ratio: Double?; var significant: Bool
}

struct Research: Codable {
    struct Drop: Codable { var buckets: [Bucket]; var n: Int; var finding: DropFinding? }
    struct Hes: Codable { var buckets: [Bucket]; var n: Int; var finding: HesitationFinding? }
    struct Price: Codable {
        struct DeckPrice: Codable { var deck: String; var n: Int; var median_minutes: Double; var median_reviews: Double; var median_days: Double; var words_per_hour: Double }
        var decks: [DeckPrice]
    }
    var overdue: Drop
    var fatigue: Drop
    var hesitation: Hes
    var price: Price
    var min_n: Int
}
