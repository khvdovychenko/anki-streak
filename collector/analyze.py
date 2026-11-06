"""Turn Anki's review log into analytics for the app.

Outputs (no card text is ever exported, only numbers and deck names):
  docs/data/stats.json   - everything the dashboard shows
  docs/data/reviews.csv  - the cleaned review log, one row per review
"""
import csv
import json
import sqlite3
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "collector"))
from settings import DAILY_GOAL, DAY_START_HOUR, REMINDER_SCHEDULE, TIMEZONE  # noqa: E402
from research import run_all  # noqa: E402

OUT_DIR = ROOT / "docs" / "data"

# revlog.type: 0 learn, 1 review, 2 relearn, 3 filtered/cram, 4 manual, 5 rescheduled
TYPE_NAMES = {0: "learn", 1: "review", 2: "relearn", 3: "filtered", 4: "manual", 5: "rescheduled"}
RATING_NAMES = {1: "again", 2: "hard", 3: "good", 4: "easy"}


def anki_day(ts: datetime):
    """The study day a timestamp belongs to, with Anki's 4 a.m. rollover."""
    return (ts - timedelta(hours=DAY_START_HOUR)).date()


def now_local() -> datetime:
    return datetime.now(TIMEZONE)


def load_deck_names(con):
    names = {}
    try:
        rows = con.execute("select id, name from decks").fetchall()
    except sqlite3.OperationalError:
        # very old schema: decks stored as JSON in col.decks
        raw = con.execute("select decks from col").fetchone()[0]
        rows = [(int(k), v["name"]) for k, v in json.loads(raw).items()]
    for did, name in rows:
        # nested decks are separated by \x1f inside the database
        names[did] = name.replace("\x1f", "::")
    return names


def top_deck(name: str) -> str:
    return name.split("::")[0]


def compute(collection_path: Path, today=None):
    con = sqlite3.connect(f"file:{collection_path}?mode=ro", uri=True)
    deck_names = load_deck_names(con)

    card_deck = {}
    cards = []
    for cid, did, odid, ctype, queue, ivl, due, lapses in con.execute(
        "select id, did, odid, type, queue, ivl, due, lapses from cards"
    ):
        real_did = odid or did  # cards in filtered decks keep their home deck in odid
        deck = top_deck(deck_names.get(real_did, "Unknown"))
        card_deck[cid] = deck
        cards.append((deck, ctype, queue, ivl, due, lapses))

    try:
        days_elapsed_base = con.execute("select crt from col").fetchone()[0]
    except Exception:
        days_elapsed_base = None

    reviews = []
    for rid, cid, ease, ivl, last_ivl, time_ms, rtype in con.execute(
        "select id, cid, ease, ivl, lastIvl, time, type from revlog order by id"
    ):
        if rtype in (4, 5) or ease == 0:
            continue  # manual reschedules are not real study
        ts = datetime.fromtimestamp(rid / 1000, TIMEZONE)
        reviews.append({
            "ts": ts,
            "day": anki_day(ts),
            "deck": card_deck.get(cid, "Deleted cards"),
            "cid": cid,
            "rating": ease,
            "type": rtype,
            "ivl": ivl,
            "last_ivl": last_ivl,
            "secs": min(time_ms, 60000) / 1000,  # Anki caps answer time at 60s
        })
    con.close()

    today = today or anki_day(now_local())
    return build_stats(reviews, cards, today, days_elapsed_base), reviews


def build_stats(reviews, cards, today, crt):
    per_day = Counter(r["day"] for r in reviews)
    secs_per_day = defaultdict(float)
    for r in reviews:
        secs_per_day[r["day"]] += r["secs"]

    study_days = sorted(per_day)

    # --- streaks ---------------------------------------------------------
    def streak_ending(day):
        n = 0
        while per_day.get(day):
            n += 1
            day -= timedelta(days=1)
        return n

    reviewed_today = per_day.get(today, 0) > 0
    current = streak_ending(today) if reviewed_today else streak_ending(today - timedelta(days=1))
    longest, run, prev = 0, 0, None
    for d in study_days:
        run = run + 1 if prev and d - prev == timedelta(days=1) else 1
        longest = max(longest, run)
        prev = d

    # --- heatmap: last 365 days -------------------------------------------
    start = today - timedelta(days=364)
    heatmap = [
        {"date": (start + timedelta(days=i)).isoformat(),
         "reviews": per_day.get(start + timedelta(days=i), 0),
         "minutes": round(secs_per_day.get(start + timedelta(days=i), 0) / 60, 1)}
        for i in range(365)
    ]

    # --- retention: share of "review" answers that were not "again" --------
    def retention(rows):
        rev = [r for r in rows if r["type"] == 1]
        if not rev:
            return None
        return round(100 * sum(r["rating"] > 1 for r in rev) / len(rev), 1)

    def mature_retention(rows):
        rev = [r for r in rows if r["type"] == 1 and r["last_ivl"] >= 21]
        if len(rev) < 5:
            return None
        return round(100 * sum(r["rating"] > 1 for r in rev) / len(rev), 1)

    # --- per deck -------------------------------------------------------------
    by_deck = defaultdict(list)
    for r in reviews:
        by_deck[r["deck"]].append(r)

    card_states = defaultdict(lambda: {"new": 0, "learning": 0, "young": 0, "mature": 0, "suspended": 0, "leeches": 0})
    for deck, ctype, queue, ivl, due, lapses in cards:
        s = card_states[deck]
        if queue == -1:
            s["suspended"] += 1
        elif ctype == 0:
            s["new"] += 1
        elif ctype in (1, 3):
            s["learning"] += 1
        elif ivl >= 21:
            s["mature"] += 1
        else:
            s["young"] += 1
        if lapses >= 8:
            s["leeches"] += 1

    decks = []
    for deck in sorted(set(by_deck) | set(card_states)):
        rows = by_deck.get(deck, [])
        last30 = [r for r in rows if r["day"] > today - timedelta(days=30)]
        decks.append({
            "name": deck,
            "reviews_total": len(rows),
            "reviews_30d": len(last30),
            "retention_30d": retention(last30),
            "mature_retention_30d": mature_retention(last30),
            "avg_seconds": round(sum(r["secs"] for r in rows) / len(rows), 1) if rows else None,
            "cards": card_states[deck],
        })
    decks.sort(key=lambda d: -d["reviews_30d"])

    # --- when do you study best ----------------------------------------------
    hours = []
    for h in range(24):
        rows = [r for r in reviews if r["ts"].hour == h]
        hours.append({"hour": h, "reviews": len(rows), "retention": retention(rows)})
    weekdays = []
    for wd in range(7):
        days_with = [d for d in study_days if d.weekday() == wd]
        weekdays.append({
            "weekday": wd,
            "reviews": sum(per_day[d] for d in days_with),
            "study_days": len(days_with),
        })

    # --- weekly trend (last 26 weeks) ---------------------------------------
    week0 = today - timedelta(days=today.weekday())
    weekly = []
    for i in range(25, -1, -1):
        ws = week0 - timedelta(weeks=i)
        rows = [r for r in reviews if ws <= r["day"] < ws + timedelta(days=7)]
        weekly.append({
            "week": ws.isoformat(),
            "reviews": len(rows),
            "minutes": round(sum(r["secs"] for r in rows) / 60),
            "retention": retention(rows),
            "new_cards": sum(r["type"] == 0 and r["last_ivl"] == 0 for r in rows),
        })

    # --- ratings mix (last 30 days) ------------------------------------------
    last30 = [r for r in reviews if r["day"] > today - timedelta(days=30)]
    ratings = {RATING_NAMES[k]: sum(r["rating"] == k for r in last30) for k in RATING_NAMES}

    # --- forecast: review cards due in the next 14 days -------------------------
    forecast = None
    deck_due = Counter()
    if crt:
        crt_day = datetime.fromtimestamp(crt, TIMEZONE)
        today_index = (today - anki_day(crt_day)).days
        due_counts = Counter()
        for deck, ctype, queue, ivl, due, lapses in cards:
            if queue in (2, 3):  # review / day-learning queue, due = day index
                offset = max(due - today_index, 0)
                if offset < 14:
                    due_counts[offset] += 1
                if offset == 0:
                    deck_due[deck] += 1
        forecast = [{"date": (today + timedelta(days=i)).isoformat(), "due": due_counts.get(i, 0)} for i in range(14)]

    # --- daily goal ------------------------------------------------------------
    done_today = per_day.get(today, 0)
    due_left = forecast[0]["due"] if forecast else None
    goal = {
        "target": DAILY_GOAL,
        "done": done_today,
        "due_left": due_left,
        "met": done_today >= DAILY_GOAL or (done_today > 0 and due_left == 0),
        "cleared_queue": done_today > 0 and due_left == 0,
    }

    # --- what the reminders need ---------------------------------------------------
    last7 = [r for r in reviews if r["day"] > today - timedelta(days=7)]
    prev7 = [r for r in reviews if today - timedelta(days=14) < r["day"] <= today - timedelta(days=7)]
    weak = [(retention([r for r in last7 if r["deck"] == d]), d)
            for d in {r["deck"] for r in last7}
            if sum(r["type"] == 1 for r in last7 if r["deck"] == d) >= 20]
    weak = [w for w in weak if w[0] is not None]
    # When does a study day usually start? Median first-review time over the last 14 study days,
    # in minutes after midnight (times before the 4:00 rollover count as late evening).
    firsts = []
    for d in study_days[-14:]:
        first = min(r["ts"] for r in reviews if r["day"] == d)
        minutes = first.hour * 60 + first.minute
        firsts.append(minutes + 1440 if first.hour < DAY_START_HOUR else minutes)
    firsts.sort()
    last_study = study_days[-1] if study_days else None
    notify = {
        "due": forecast[0]["due"] if forecast else None,
        "deck": deck_due.most_common(1)[0][0] if deck_due else None,
        "weakest_deck": min(weak)[1] if weak else None,
        "retention_7d": retention(last7),
        "retention_prev_7d": retention(prev7),
        "week_cards": len(last7),
        "last_week_cards": len(prev7),
        "best_day": max(per_day.values()) if per_day else 0,
        "last_study_day": last_study.isoformat() if last_study else None,
        "last_review": reviews[-1]["ts"].isoformat(timespec="minutes") if reviews else None,
        "lost_streak": streak_ending(last_study) if last_study else 0,
        "usual_start_minute": firsts[len(firsts) // 2] % 1440 if firsts else None,
    }

    total_secs = sum(r["secs"] for r in reviews)
    return {
        "notify": notify,
        "goal": goal,
        "settings": {"reminder_hours": sorted(REMINDER_SCHEDULE), "timezone": TIMEZONE.key, "day_start_hour": DAY_START_HOUR},
        "generated_at": now_local().isoformat(timespec="minutes"),
        "today": today.isoformat(),
        "streak": {
            "current": current,
            "longest": longest,
            "reviewed_today": reviewed_today,
            "at_risk": not reviewed_today and current > 0,
            # the streak broke yesterday (studied two days ago, not yesterday)
            "lost_yesterday": not per_day.get(today - timedelta(days=1))
                              and bool(per_day.get(today - timedelta(days=2))),
        },
        "today_stats": {
            "reviews": per_day.get(today, 0),
            "minutes": round(secs_per_day.get(today, 0) / 60, 1),
        },
        "totals": {
            "reviews": len(reviews),
            "hours": round(total_secs / 3600, 1),
            "study_days": len(study_days),
            "first_day": study_days[0].isoformat() if study_days else None,
            "avg_reviews_per_study_day": round(len(reviews) / len(study_days)) if study_days else 0,
            "consistency_90d": round(100 * sum(per_day.get(today - timedelta(days=i), 0) > 0 for i in range(90)) / 90),
            "retention_30d": retention(last30),
        },
        "ratings_30d": ratings,
        "decks": decks,
        "hours": hours,
        "weekdays": weekdays,
        "weekly": weekly,
        "heatmap": heatmap,
        "forecast": forecast,
        "research": run_all(reviews),
    }


def write_outputs(stats, reviews):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1))
    with open(OUT_DIR / "reviews.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["timestamp", "study_day", "deck", "card_id", "rating", "rating_name",
                    "review_type", "interval_days", "previous_interval_days", "answer_seconds"])
        for r in reviews:
            w.writerow([r["ts"].isoformat(timespec="seconds"), r["day"].isoformat(), r["deck"],
                        r["cid"], r["rating"], RATING_NAMES.get(r["rating"], ""),
                        TYPE_NAMES.get(r["type"], r["type"]), r["ivl"], r["last_ivl"], r["secs"]])


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "data" / "anki" / "collection.anki2"
    stats, reviews = compute(path)
    write_outputs(stats, reviews)
    s = stats["streak"]
    print(f"{len(reviews)} reviews | streak {s['current']} | today {stats['today_stats']['reviews']}")
