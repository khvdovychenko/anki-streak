import SwiftUI
import WidgetKit

private let flame = Color(red: 1.0, green: 0.48, blue: 0.10)
private let bg = Color(red: 0.11, green: 0.09, blue: 0.07)
private let card = Color(red: 0.15, green: 0.125, blue: 0.10)

struct ContentView: View {
    @State private var stats: Stats?
    @State private var error: String?
    @State private var showStats = false
    @State private var activityRunning = LiveActivityManager.isRunning
    @AppStorage("autoCountdown") private var autoCountdown = true
    @Environment(\.scenePhase) private var phase
    @State private var hop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let s = stats {
                    hero(s)
                    evolution(s)
                    controls
                } else if let error {
                    Text(error).foregroundStyle(.secondary).padding(.top, 80).multilineTextAlignment(.center)
                } else {
                    ProgressView().padding(.top, 120)
                }
            }
            .padding(16)
        }
        .background(bg.ignoresSafeArea())
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: phase) { _, p in if p == .active { Task { await load() } } }
        .sheet(isPresented: $showStats) {
            WebView(url: Config.siteURL).ignoresSafeArea()
        }
    }

    // MARK: sections

    private func hero(_ s: Stats) -> some View {
        let mood = CinderLogic.mood(s)
        let stage = CinderLogic.displayedStage(s, mood: mood)
        let fresh = s.isFromToday()
        let done = fresh ? s.goalDone : 0
        let progress = s.goalMet && fresh ? 1 : min(Double(done) / Double(max(s.goalTarget, 1)), 1)
        return VStack(spacing: 6) {
            CinderImage(stage: stage, mood: mood)
                .frame(width: 200, height: 200)
                .offset(y: hop ? -10 : 0)
                .onAppear {
                    guard mood == .lit else { return }
                    withAnimation(.interpolatingSpring(stiffness: 220, damping: 8)) { hop = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(.spring) { hop = false } }
                }
            Text("CINDER · \(CinderLogic.stages[stage].name.uppercased())")
                .font(.caption.weight(.heavy)).tracking(1.5).foregroundStyle(.secondary)
            Text("\(s.streak.current)")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(mood == .lit ? flame : .primary)
            Text("day streak").font(.headline.weight(.heavy))
            Text(CinderLogic.line(for: mood))
                .font(.subheadline.weight(.bold)).foregroundStyle(.secondary).padding(.top, 2)

            if mood != .lit {
                HStack(spacing: 4) {
                    Text(mood == .dead ? "New streak window closes in" : "Cinder dies in")
                    Text(timerInterval: Date.now...CinderLogic.dayEnd(dayStartHour: s.dayStartHour), countsDown: true)
                        .monospacedDigit().foregroundStyle(flame)
                }
                .font(.subheadline.weight(.heavy)).padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today's goal")
                    Spacer()
                    Text("\(done) / \(s.goalTarget)")
                }
                .font(.footnote.weight(.heavy)).foregroundStyle(.secondary)
                ProgressView(value: progress).tint(flame)
            }
            .padding(.top, 12)

            Button {
                UIApplication.shared.open(Config.ankiURL)
            } label: {
                Text(mood == .lit ? "Review a bit more" : "Open Anki")
                    .font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent).tint(flame).padding(.top, 10)

            Text("Studied already? Tap sync in Anki, then pull down here to refresh.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func evolution(_ s: Stats) -> some View {
        let mood = CinderLogic.mood(s)
        let stage = CinderLogic.displayedStage(s, mood: mood)
        let next = stage + 1 < CinderLogic.stages.count ? CinderLogic.stages[stage + 1] : nil
        return VStack(alignment: .leading, spacing: 10) {
            Text("Evolution").font(.headline.weight(.heavy))
            if let next {
                let days = next.from - s.streak.current
                Text("\(days) more day\(days == 1 ? "" : "s") to evolve into \(next.name).")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Final form. Keep the volcano erupting.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(0..<CinderLogic.stages.count, id: \.self) { i in
                    VStack(spacing: 2) {
                        CinderImage(stage: i, mood: i == 0 ? .dead : .lit)
                            .frame(width: 48, height: 48)
                            .saturation(i > stage ? 0 : 1)
                            .opacity(i > stage ? 0.35 : 1)
                        Text(CinderLogic.stages[i].name).font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(i == stage ? flame : .secondary)
                        Text("\(CinderLogic.stages[i].from)d").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $autoCountdown) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock Screen countdown").font(.subheadline.weight(.bold))
                    Text("Starts when you open Cinder and the goal isn't done.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(flame)
            .onChange(of: autoCountdown) { _, on in
                Task {
                    if on, let stats { await LiveActivityManager.sync(with: stats, autoStart: true) }
                    else { await LiveActivityManager.endAll() }
                    activityRunning = LiveActivityManager.isRunning
                }
            }
            .padding(.vertical, 12)
            Divider()
            Button { showStats = true } label: {
                HStack {
                    Text("Full analytics & research").font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                }
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 18)
        .background(card, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: data

    private func load() async {
        do {
            let s = try await Stats.fetch()
            stats = s
            error = nil
            await LiveActivityManager.sync(with: s, autoStart: autoCountdown)
            activityRunning = LiveActivityManager.isRunning
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if stats == nil {
                self.error = "Couldn't load your stats.\nCheck that the GitHub workflow has run and Config.siteURL is right."
            }
        }
    }
}

struct CinderImage: View {
    let stage: Int
    let mood: Mood
    @State private var flicker = false

    var body: some View {
        Image(CinderLogic.imageName(stage: stage, mood: mood))
            .resizable()
            .scaledToFit()
            .scaleEffect(x: 1, y: flicker ? 1.015 : 0.99, anchor: .bottom)
            .animation(mood == .dead ? nil : .easeInOut(duration: mood == .dying ? 0.5 : 1.1).repeatForever(), value: flicker)
            .onAppear { flicker = true }
    }
}
