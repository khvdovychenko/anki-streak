import Charts
import SwiftUI

private let flame = Color(red: 1.0, green: 0.48, blue: 0.10)
private let card = Color(red: 0.15, green: 0.125, blue: 0.10)
private let good = Color(red: 0.18, green: 0.64, blue: 0.42)
private let bad = Color(red: 0.88, green: 0.28, blue: 0.24)
private let hardC = Color(red: 0.94, green: 0.65, blue: 0.19)
private let easyC = Color(red: 0.24, green: 0.55, blue: 0.99)
private let heat: [Color] = [
    Color(red: 0.20, green: 0.16, blue: 0.12), Color(red: 0.42, green: 0.23, blue: 0.08),
    Color(red: 0.66, green: 0.32, blue: 0.10), flame, Color(red: 1.0, green: 0.69, blue: 0.18),
]

/// Everything the web dashboard shows, drawn natively.
struct DashboardView: View {
    let s: Stats

    var body: some View {
        VStack(spacing: 14) {
            section("Overview") { kpis }
            if !insights.isEmpty { section("What the data says") { insightList } }
            if let h = s.heatmap { section("Your year") { HeatmapView(days: h) } }
            if let w = s.weekly, w.contains(where: { $0.reviews > 0 }) { section("Reviews per week") { weeklyChart(w) } }
            if let h = s.hours, h.contains(where: { $0.reviews > 0 }) { section("When you study") { hoursChart(h) } }
            if let r = s.ratings_30d, r.again + r.hard + r.good + r.easy > 0 { section("Your answers, 30 days") { ratings(r) } }
            if let f = s.forecast { section("Next 2 weeks") { forecast(f) } }
            if let r = s.research { research(r) }
            if let d = s.decks?.filter({ $0.reviews_total > 0 || $0.cards.new + $0.cards.young + $0.cards.mature > 0 }), !d.isEmpty {
                section("Decks") { VStack(spacing: 16) { ForEach(d, id: \.name) { deck($0) } } }
            }
        }
    }

    // MARK: building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0) } ?? "—" }

    // MARK: overview

    private var kpis: some View {
        let t = s.totals
        let items: [(String, String)] = [
            ((t.reviews ?? 0).formatted(), "reviews in total"),
            ((t.hours ?? 0).formatted(.number.precision(.fractionLength(0))), "hours studied"),
            (pct(t.retention_30d), "retention, 30 days"),
            ("\(t.consistency_90d ?? 0)%", "of the last 90 days studied"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(items, id: \.1) { v, l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(v).font(.system(size: 26, weight: .black, design: .rounded))
                    Text(l).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var insights: [(String, String)] {
        var out: [(String, String)] = []
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        if let hours = s.hours {
            let ok = hours.filter { $0.reviews >= 150 && $0.retention != nil }
            if let best = ok.max(by: { $0.retention! < $1.retention! }), let worst = ok.min(by: { $0.retention! < $1.retention! }),
               best.retention! - worst.retention! >= 2 {
                out.append(("🧠", "You remember best at \(best.hour):00 (\(pct(best.retention))) and worst at \(worst.hour):00 (\(pct(worst.retention)))."))
            }
        }
        if let wd = s.weekdays?.filter({ $0.study_days > 0 }), wd.count >= 5 {
            if let top = wd.max(by: { Double($0.reviews) / Double($0.study_days) < Double($1.reviews) / Double($1.study_days) }) {
                out.append(("📅", "Most productive day: \(days[top.weekday]), \(top.reviews / max(top.study_days, 1)) reviews on average."))
            }
            if let all = s.weekdays, let skip = all.min(by: { $0.study_days < $1.study_days }),
               (all.map(\.study_days).max() ?? 0) - skip.study_days >= 3 {
                out.append(("😴", "The day you skip most: \(days[skip.weekday])."))
            }
        }
        if let f = s.research?.overdue.finding, f.significant {
            out.append(("⏰", "Reviewing \(f.worst_label) late drops your recall from \(pct(f.base)) to \(pct(f.worst))."))
        }
        if let t = s.totals.hours, s.totals.study_days > 0 {
            out.append(("⏱️", "On a study day you spend \(Int(t * 60) / s.totals.study_days) min in Anki and do \(s.totals.avg_reviews_per_study_day ?? 0) reviews."))
        }
        if let f = s.forecast, f.count > 1, f[1].due > 0 { out.append(("📬", "\(f[1].due) reviews are due tomorrow.")) }
        let leeches = s.decks?.reduce(0) { $0 + $1.cards.leeches } ?? 0
        if leeches > 0 { out.append(("🧟", "\(leeches) cards were forgotten 8+ times. Rewrite or split them.")) }
        return out
    }

    private var insightList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(insights.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Text(item.0)
                    Text(item.1).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: charts

    private func weeklyChart(_ w: [Week]) -> some View {
        let maxR = Double(max(w.map(\.reviews).max() ?? 1, 1))
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(w.enumerated()), id: \.offset) { i, wk in
                    BarMark(x: .value("Week", i), y: .value("Reviews", wk.reviews)).foregroundStyle(flame.opacity(0.85))
                }
                ForEach(Array(w.enumerated()), id: \.offset) { i, wk in
                    if let r = wk.retention {
                        LineMark(x: .value("Week", i), y: .value("Retention", r / 100 * maxR))
                            .foregroundStyle(good).interpolationMethod(.monotone)
                        PointMark(x: .value("Week", i), y: .value("Retention", r / 100 * maxR)).foregroundStyle(good).symbolSize(14)
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 150)
            Text("Bars: reviews per week, last 26 weeks. Green line: retention (top = 100%).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hoursChart(_ h: [HourStat]) -> some View {
        let peak = h.max(by: { $0.reviews < $1.reviews })?.hour
        return Chart(h, id: \.hour) { x in
            BarMark(x: .value("Hour", x.hour), y: .value("Reviews", x.reviews))
                .foregroundStyle(x.hour == peak ? flame : heat[2])
        }
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)h") } } }
        .frame(height: 120)
    }

    private func ratings(_ r: Ratings) -> some View {
        let total = Double(max(r.again + r.hard + r.good + r.easy, 1))
        let parts: [(String, Int, Color)] = [("Again", r.again, bad), ("Hard", r.hard, hardC), ("Good", r.good, good), ("Easy", r.easy, easyC)]
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.0) { _, n, c in Rectangle().fill(c).frame(width: g.size.width * Double(n) / total) }
                }
            }
            .frame(height: 18).clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach(parts, id: \.0) { name, n, c in
                    HStack(spacing: 4) {
                        Circle().fill(c).frame(width: 8, height: 8)
                        Text("\(name) \(Int(Double(n) / total * 100))%")
                    }
                }
            }
            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
    }

    private func forecast(_ f: [ForecastDay]) -> some View {
        Chart(Array(f.enumerated()), id: \.offset) { i, d in
            BarMark(x: .value("Day", i), y: .value("Due", d.due))
                .foregroundStyle(i == 0 ? flame : heat[2])
                .annotation(position: .top) { if d.due > 0 { Text("\(d.due)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) } }
        }
        .chartXAxis(.hidden)
        .frame(height: 110)
    }

    // MARK: research

    @ViewBuilder
    private func research(_ r: Research) -> some View {
        section("Research · the cost of a late review") {
            finding(r.overdue.finding.map { f in
                (f.significant,
                 f.significant
                    ? "Review a card \(f.worst_label) late and you recall it \(pct(f.worst)) of the time instead of \(pct(f.base))."
                    : "Even \(f.worst_label) late you recall \(pct(f.worst)) vs \(pct(f.base)) on time. No real cost yet.")
            })
            CIChart(buckets: r.overdue.buckets, color: flame, zeroBase: false)
            note("Share of correct answers by how much later than scheduled you reviewed. Whiskers: 95% confidence interval. Faded: fewer than \(r.min_n) answers.")
        }
        section("Research · session fatigue") {
            finding(r.fatigue.finding.map { f in
                (f.significant,
                 f.significant
                    ? "Accuracy on cards #\(f.worst_label) of a session is \(pct(f.worst)) vs \(pct(f.base)) on the first 25."
                    : "Long sessions don't wear you out: \(pct(f.worst)) on cards #\(f.worst_label), \(pct(f.base)) on the first 25.")
            })
            CIChart(buckets: r.fatigue.buckets, color: flame, zeroBase: false)
            note("A session = reviews without a break longer than 30 minutes.")
        }
        section("Research · does hesitation predict forgetting?") {
            finding(r.hesitation.finding.map { f in
                (f.significant,
                 f.significant
                    ? "Correct answers that took \(f.slow_label) are forgotten \(String(format: "%.1f", f.ratio ?? 0))× as often next time."
                    : "Answer time doesn't predict forgetting yet: \(pct(f.fast)) vs \(pct(f.slow)).")
            })
            CIChart(buckets: r.hesitation.buckets, color: bad, zeroBase: true)
            note("Correct answers only: how often the card was failed at its next review, by answer time.")
        }
        if !r.price.decks.isEmpty {
            section("Research · the price of one card") {
                ForEach(r.price.decks, id: \.deck) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.deck).font(.headline.weight(.heavy))
                        Text(d.median_minutes < 1 ? "\(Int(d.median_minutes * 60)) s" : String(format: "%.1f min", d.median_minutes))
                            .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(flame)
                        Text("\(Int(d.median_reviews)) reviews over \(Int(d.median_days)) days · ≈ \(Int(d.words_per_hour)) cards per hour · n=\(d.n)")
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                note("Median from a card's first showing until its interval first reaches 21 days.")
            }
        }
    }

    @ViewBuilder
    private func finding(_ f: (Bool, String)?) -> some View {
        if let (sig, text) = f {
            Text(sig ? "Statistically significant" : "Within the margin of error")
                .font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 3)
                .background((sig ? good : Color.gray).opacity(0.18), in: Capsule())
                .foregroundStyle(sig ? good : .secondary)
            Text(text).font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Not enough data yet. A finding appears once more reviews come in.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: decks

    private func deck(_ d: Deck) -> some View {
        let c = d.cards
        let parts: [(String, Int, Color)] = [("new", c.new, easyC), ("learning", c.learning, hardC), ("young", c.young, heat[2]), ("mature", c.mature, good), ("suspended", c.suspended, .gray)]
        let total = Double(max(parts.reduce(0) { $0 + $1.1 }, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(d.name).font(.headline.weight(.heavy))
                Spacer()
                Text("\(Int(total)) cards").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                stat(pct(d.retention_30d), "retention")
                stat("\(d.reviews_30d)", "reviews, 30 d")
                stat(d.avg_seconds.map { String(format: "%.1f s", $0) } ?? "—", "per card")
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.0) { _, n, col in Rectangle().fill(col).frame(width: g.size.width * Double(n) / total) }
                }
            }
            .frame(height: 10).clipShape(Capsule())
            Text(parts.filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.title3.weight(.black))
            Text(l).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bars with 95% confidence whiskers, faded when the sample is small.
struct CIChart: View {
    let buckets: [Bucket]
    let color: Color
    let zeroBase: Bool

    var body: some View {
        let vals = buckets.filter { $0.rate != nil }
        let lo = zeroBase ? 0 : max(0, ((vals.compactMap(\.lo).min() ?? 0) - 5).rounded(.down) / 10 * 10)
        let hi = min(100, (vals.compactMap(\.hi).max() ?? 100) + 4)
        Chart(buckets) { b in
            if let r = b.rate {
                BarMark(x: .value("Group", b.label), yStart: .value("Base", lo), yEnd: .value("Rate", r))
                    .foregroundStyle(color.opacity(b.enough ? 0.85 : 0.25))
                    .annotation(position: .top, spacing: 14) {
                        Text("\(Int(r.rounded()))%").font(.system(size: 10, weight: .heavy)).opacity(b.enough ? 1 : 0.4)
                    }
                if let l = b.lo, let h = b.hi {
                    RuleMark(x: .value("Group", b.label), yStart: .value("Low", l), yEnd: .value("High", h))
                        .foregroundStyle(.white.opacity(b.enough ? 0.7 : 0.25)).lineStyle(StrokeStyle(lineWidth: 1.4))
                }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let label = v.as(String.self), let b = buckets.first(where: { $0.label == label }) {
                        VStack(spacing: 1) {
                            Text(label).font(.system(size: 9, weight: .bold))
                            Text("n=\(b.n)").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
        .frame(height: 170)
    }
}

/// GitHub-style calendar of the last year, newest week on the right.
struct HeatmapView: View {
    let days: [HeatDay]

    var body: some View {
        let nonzero = days.map(\.reviews).filter { $0 > 0 }.sorted()
        let q = { (p: Double) -> Int in nonzero.isEmpty ? 1 : nonzero[Int(p * Double(nonzero.count - 1))] }
        let cuts = [q(0.25), q(0.5), q(0.75)]
        let level = { (n: Int) -> Int in n == 0 ? 0 : n <= cuts[0] ? 1 : n <= cuts[1] ? 2 : n <= cuts[2] ? 3 : 4 }
        let lead = leadingBlanks
        let cols = Int(ceil(Double(days.count + lead) / 7))
        let active = days.filter { $0.reviews > 0 }.count
        VStack(alignment: .leading, spacing: 8) {
            Text("\(active) study days in the last year").font(.headline.weight(.heavy))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(0..<cols, id: \.self) { c in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { r in
                                    let i = c * 7 + r - lead
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(i >= 0 && i < days.count ? heat[level(days[i].reviews)] : .clear)
                                        .frame(width: 11, height: 11)
                                }
                            }
                            .id(c)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(cols - 1, anchor: .trailing) }
            }
            HStack(spacing: 4) {
                Text("less")
                ForEach(0..<5, id: \.self) { RoundedRectangle(cornerRadius: 2).fill(heat[$0]).frame(width: 10, height: 10) }
                Text("more")
            }
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
    }

    private var leadingBlanks: Int {
        guard let first = days.first else { return 0 }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: first.date) else { return 0 }
        return (Calendar(identifier: .gregorian).component(.weekday, from: d) + 5) % 7 // Monday = 0
    }
}
