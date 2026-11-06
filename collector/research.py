"""Questions Anki's own statistics don't answer.

Every result carries its sample size and a 95% Wilson confidence interval,
and a finding is only reported when the sample is big enough to mean something.

1. Cost of a late review: recall vs how overdue the card was.
2. Session fatigue: recall vs position of the card within one sitting.
3. Hesitation: do slow-but-correct answers get forgotten more often next time?
4. Price of a word: minutes and reviews until a card first reaches 21-day maturity.
"""
import math
from collections import defaultdict
from statistics import median

SESSION_GAP_MIN = 30   # a pause longer than this starts a new session
MIN_N = 40             # minimum answers per bucket to report it
MATURE_DAYS = 21


def wilson(k, n, z=1.96):
    """95% confidence interval for a proportion, in percent."""
    if n == 0:
        return None, None, None
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return round(100 * p, 1), round(100 * (centre - half), 1), round(100 * (centre + half), 1)


def bucketize(rows, edges, labels, key, outcome):
    """rows -> [{label, n, rate, lo, hi}] using half-open [edge_i, edge_i+1)."""
    counts = [[0, 0] for _ in labels]
    for r in rows:
        v = key(r)
        for i in range(len(labels)):
            if edges[i] <= v < edges[i + 1]:
                counts[i][0] += outcome(r)
                counts[i][1] += 1
                break
    out = []
    for label, (k, n) in zip(labels, counts):
        rate, lo, hi = wilson(k, n)
        out.append({"label": label, "n": n, "rate": rate, "lo": lo, "hi": hi, "enough": n >= MIN_N})
    return out


def by_card(reviews):
    cards = defaultdict(list)
    for r in reviews:
        cards[r["cid"]].append(r)
    return cards


def overdue_cost(reviews):
    """Recall on review cards, by actual gap / scheduled interval."""
    rows = []
    for seq in by_card(reviews).values():
        for prev, cur in zip(seq, seq[1:]):
            if cur["type"] != 1 or cur["last_ivl"] < 1:
                continue
            elapsed = (cur["ts"] - prev["ts"]).total_seconds() / 86400
            rows.append({"ratio": elapsed / cur["last_ivl"], "ok": cur["rating"] > 1})
    edges = [0, 1.15, 1.5, 2, 3, float("inf")]
    labels = ["вчасно", "×1,15–1,5", "×1,5–2", "×2–3", "×3+"]
    buckets = bucketize(rows, edges, labels, lambda r: r["ratio"], lambda r: r["ok"])
    return {"buckets": buckets, "n": len(rows), "finding": _drop_finding(buckets, "late")}


def session_fatigue(reviews):
    """Recall on review cards, by the card's position in the session."""
    rows, pos, last_ts = [], 0, None
    for r in reviews:  # reviews are sorted by time
        if last_ts is None or (r["ts"] - last_ts).total_seconds() > SESSION_GAP_MIN * 60:
            pos = 0
        pos += 1
        last_ts = r["ts"]
        if r["type"] == 1:
            rows.append({"pos": pos, "ok": r["rating"] > 1})
    edges = [1, 26, 51, 101, 151, float("inf")]
    labels = ["1–25", "26–50", "51–100", "101–150", "150+"]
    buckets = bucketize(rows, edges, labels, lambda r: r["pos"], lambda r: r["ok"])
    return {"buckets": buckets, "n": len(rows), "finding": _drop_finding(buckets, "fatigue")}


def hesitation(reviews):
    """For correct answers, how often is the NEXT review of that card a fail?"""
    rows = []
    for seq in by_card(reviews).values():
        for cur, nxt in zip(seq, seq[1:]):
            if cur["type"] == 1 and cur["rating"] > 1 and nxt["type"] == 1:
                rows.append({"secs": cur["secs"], "fail": nxt["rating"] == 1})
    edges = [0, 4, 8, 15, float("inf")]
    labels = ["<4 с", "4–8 с", "8–15 с", "15+ с"]
    buckets = bucketize(rows, edges, labels, lambda r: r["secs"], lambda r: r["fail"])
    ok = [b for b in buckets if b["enough"]]
    finding = None
    if len(ok) >= 2 and ok[0]["rate"] and ok[-1]["rate"] is not None:
        fast, slow = ok[0], ok[-1]
        separated = slow["lo"] > fast["hi"]  # intervals don't overlap
        finding = {
            "fast_label": fast["label"], "slow_label": slow["label"],
            "fast": fast["rate"], "slow": slow["rate"],
            "ratio": round(slow["rate"] / fast["rate"], 1) if fast["rate"] else None,
            "significant": separated,
        }
    return {"buckets": buckets, "n": len(rows), "finding": finding}


def price_of_a_word(reviews):
    """Minutes and reviews spent on each card until it first reached maturity."""
    per_deck = defaultdict(list)
    for seq in by_card(reviews).values():
        if seq[0]["type"] != 0:
            continue  # card was learned before the log starts, cost unknown
        secs = 0
        for i, r in enumerate(seq, 1):
            secs += r["secs"]
            if r["ivl"] >= MATURE_DAYS:
                per_deck[seq[0]["deck"]].append({"min": secs / 60, "reviews": i,
                                                 "days": (r["ts"] - seq[0]["ts"]).days})
                break
    decks = []
    for deck, rows in per_deck.items():
        if len(rows) < 20:
            continue
        decks.append({
            "deck": deck, "n": len(rows),
            "median_minutes": round(median(r["min"] for r in rows), 1),
            "median_reviews": median(r["reviews"] for r in rows),
            "median_days": median(r["days"] for r in rows),
            "words_per_hour": round(60 / (sum(r["min"] for r in rows) / len(rows)), 1),
        })
    decks.sort(key=lambda d: -d["n"])
    return {"decks": decks}


def _drop_finding(buckets, kind):
    ok = [b for b in buckets if b["enough"]]
    if len(ok) < 2:
        return None
    first, worst = ok[0], min(ok[1:], key=lambda b: b["rate"])
    return {
        "base_label": first["label"], "base": first["rate"],
        "worst_label": worst["label"], "worst": worst["rate"],
        "drop_pp": round(first["rate"] - worst["rate"], 1),
        "significant": worst["hi"] < first["lo"],
    }


def run_all(reviews):
    return {
        "overdue": overdue_cost(reviews),
        "fatigue": session_fatigue(reviews),
        "hesitation": hesitation(reviews),
        "price": price_of_a_word(reviews),
        "min_n": MIN_N,
    }
