"""Cinder's reminders: Duolingo-style pushes and emails, driven by collector/messages.json.

Runs every 15 minutes (see .github/workflows/update.yml). Each run looks at today's
stats, decides which trigger is due, picks a message and remembers what it sent in
data/state.json, so nothing fires twice and nothing repeats too often.

Triggers (rules live in messages.json → _meta.rules):
  routine          ~30 min before the time you usually start studying
  partial          you started but stopped short of the goal, 2h+ ago
  save_3h/1h/15m   before midnight if the goal isn't met
  goal_done        once the goal is met, if Cinder had been nagging
  milestone        streak hits 3, 7, 14, 30, 100, 365
  broken, lapsed_day2/3/5/7, final   on the mornings after you skip
  comeback         first review after a break
  weekly           Sunday noon, one insight from "stats" plus the weekly email
"""
import json
import os
import random
import smtplib
import sys
from datetime import date, datetime, timedelta
from email.message import EmailMessage
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "collector"))
from analyze import anki_day, now_local  # noqa: E402
from settings import EMAIL_REMINDERS, NAME, SPICE_MAX  # noqa: E402

STATS = ROOT / "docs" / "data" / "stats.json"
STATE = ROOT / "data" / "state.json"
MESSAGES = json.loads((ROOT / "collector" / "messages.json").read_text())
APP_URL = os.environ.get("APP_URL", "")

SAVE_TIMES = [("save_3h", 21, 0), ("save_1h", 23, 0), ("save_15m", 23, 45)]
LAPSE_TRIGGERS = {1: "broken", 2: "lapsed_day2", 3: "lapsed_day3", 5: "lapsed_day5", 7: "lapsed_day7", 8: "final"}
MORNING_HOUR = 9
MAX_ROUTINE_PUSHES = 2  # non-save pushes per day
SYNC_HINT = " (Studied already? Tap sync in Anki so I can see it.)"


# ---------------------------------------------------------------- state

def load_state(day_key):
    try:
        state = json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    state.setdefault("recent", [])          # last message ids, to avoid repeats
    state.setdefault("milestones", [])      # streak values already celebrated
    state.setdefault("lapse_sent", {})      # {last_study_day: [lapse days sent]}
    if state.get("day") != day_key:
        state["due_yesterday"] = state.get("due_today")
        state.update(day=day_key, sent=[], nonsave=0)
    return state


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=1, ensure_ascii=False))


# ---------------------------------------------------------------- sending

def send_push(title, body, badge=1):
    raw = os.environ.get("PUSH_CONFIG")
    if not raw:
        print("PUSH_CONFIG not set, skipping push:", title)
        return
    from pywebpush import WebPushException, webpush
    cfg = json.loads(raw)
    try:
        webpush(
            subscription_info=cfg["subscription"],
            data=json.dumps({"title": title, "body": body, "url": APP_URL, "badge": badge}),
            vapid_private_key=cfg["privateKey"],
            vapid_claims={"sub": "mailto:" + (os.environ.get("GMAIL_USER") or "cinder@example.com")},
            ttl=3600,
        )
        print("push sent:", title)
    except WebPushException as e:
        print("push failed:", e)


def send_email(subject, body):
    if not EMAIL_REMINDERS:
        return
    user, pw = os.environ.get("GMAIL_USER"), os.environ.get("GMAIL_APP_PASSWORD")
    if not user or not pw:
        print("Gmail secrets not set, skipping email:", subject)
        return
    msg = EmailMessage()
    msg["Subject"], msg["From"], msg["To"] = subject, f"Cinder <{user}>", os.environ.get("EMAIL_TO") or user
    msg.set_content(body + (f"\n\nOpen your stats: {APP_URL}" if APP_URL else ""))
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
        s.login(user, pw)
        s.send_message(msg)
    print("email sent:", subject)


# ---------------------------------------------------------------- choosing text

class Vars(dict):
    """Missing variables render as '?' instead of crashing."""
    def __missing__(self, key):
        return "?"


def variables(stats, state, streak_override=None):
    g, n = stats.get("goal") or {}, stats.get("notify") or {}
    done, target = g.get("done", 0), g.get("target", 30)
    left = max(target - done, 0)
    if g.get("due_left"):
        left = min(left, g["due_left"]) or left
    return Vars(
        name=NAME or "you",
        streak=streak_override if streak_override is not None else stats["streak"]["current"],
        due=n.get("due", "?"),
        due_yesterday=state.get("due_yesterday") or n.get("due", "?"),
        done=done, goal=target, left=left,
        deck=n.get("deck") or "your",
        weakest_deck=n.get("weakest_deck") or "?",
        retention=n.get("retention_7d") or "?",
        week_cards=n.get("week_cards", "?"),
        last_week_cards=n.get("last_week_cards", "?"),
        best_day=n.get("best_day", "?"),
        to_best=max(n.get("best_day", 0) - done, 0),
    )


def pick(bucket, state, needs=None):
    options = [(i, m) for i, m in enumerate(MESSAGES[bucket]) if m.get("spice", 1) <= SPICE_MAX]
    if needs:
        options = [(i, m) for i, m in options if needs(m)]
    fresh = [(i, m) for i, m in options if f"{bucket}:{i}" not in state["recent"]] or options
    if not fresh:
        return None
    i, m = random.choice(fresh)
    state["recent"] = (state["recent"] + [f"{bucket}:{i}"])[-5:]
    return m


def fire(trigger, stats, state, bucket=None, hint="", streak_override=None, needs=None):
    due = (stats.get("notify") or {}).get("due") or 0

    def sensible(m):
        # "The Backlog: I'm 0 now" makes no sense; skip due-count jokes when little is due.
        if due < 5 and "{due" in m["title"] + m["body"]:
            return False
        return needs(m) if needs else True

    if trigger == "milestone":
        msg = MESSAGES["milestones"][bucket]
    else:
        msg = pick(bucket or trigger, state, sensible) or pick(bucket or trigger, state, needs)
    if not msg:
        return
    v = variables(stats, state, streak_override)
    title, body = msg["title"].format_map(v), msg["body"].format_map(v) + hint
    send_push(title, body, badge=v["left"] or 1)
    email = next((e for e in MESSAGES["email"] if e["trigger"] == trigger), None)
    if email:
        send_email(email["subject"].format_map(v), f"{email['preview'].format_map(v)}\n\n{title}\n{body}")
    state["sent"].append(trigger)
    print(f"[{trigger}] {title} | {body}")


# ---------------------------------------------------------------- main

def decide(stats, state, now):
    today = date.fromisoformat(stats["today"])
    streak, goal, notify = stats["streak"], stats.get("goal") or {}, stats.get("notify") or {}
    sent = state["sent"]
    done = goal.get("done", 0)
    met = goal.get("met", streak["reviewed_today"])
    minutes = now.hour * 60 + now.minute
    last_study = date.fromisoformat(notify["last_study_day"]) if notify.get("last_study_day") else None
    # Cinder only counts skipped days since he started watching, so installing him
    # after a long break starts a fresh nag cycle instead of silence.
    watching_since = date.fromisoformat(state.setdefault("watching_since", stats["today"]))
    adjusted = bool(last_study and last_study < watching_since - timedelta(days=1))
    if adjusted:
        last_study = watching_since - timedelta(days=1)

    # --- studied today --------------------------------------------------------
    if streak["reviewed_today"]:
        if state.get("lapsed") and "comeback" not in sent:
            fire("comeback", stats, state)
            state["lapsed"] = False
        current = streak["current"]
        if str(current) in MESSAGES["milestones"] and current not in state["milestones"]:
            fire("milestone", stats, state, bucket=str(current))
            state["milestones"].append(current)
        if met:
            if any(t.startswith(("save", "partial", "routine")) for t in sent) and "goal_done" not in sent:
                fire("goal_done", stats, state)
            return
        last = datetime.fromisoformat(notify["last_review"]) if notify.get("last_review") else now
        if (now - last >= timedelta(hours=2) and "partial" not in sent
                and state["nonsave"] < MAX_ROUTINE_PUSHES and now.hour < 21):
            fire("partial", stats, state)
            state["nonsave"] += 1

    # --- not studied (yet) ------------------------------------------------------
    else:
        lapse_day = (today - last_study).days - 1 if last_study else 0
        if lapse_day >= 1:
            state["lapsed"] = True
            key = notify["last_study_day"]
            already = state["lapse_sent"].setdefault(key, [])
            trigger = LAPSE_TRIGGERS.get(lapse_day)
            if trigger and lapse_day not in already and now.hour >= MORNING_HOUR:
                override = notify.get("lost_streak") if trigger == "broken" else None
                if trigger != "broken" or ((override or 0) > 1 and not adjusted):
                    fire(trigger, stats, state, streak_override=override)
                already.append(lapse_day)
            if lapse_day > 8:
                return  # silence, apart from the weekly email
        usual = notify.get("usual_start_minute")
        target = (usual - 30) if usual is not None else 18 * 60 + 30
        if (target <= minutes < 21 * 60 and "routine" not in sent
                and state["nonsave"] < MAX_ROUTINE_PUSHES and lapse_day <= 1):
            fire("routine", stats, state, hint=SYNC_HINT if done == 0 else "")
            state["nonsave"] += 1

    # --- rescue pushes before midnight (only while a streak is alive) ------------
    alive = streak["current"] > 0 or streak["reviewed_today"]
    if not met and alive:
        due_now = [t for t, h, m in SAVE_TIMES if minutes >= h * 60 + m and t not in sent]
        if due_now:
            # If runs were missed, send only the latest one and mark the earlier ones done.
            for t in due_now[:-1]:
                sent.append(t)
            fire(due_now[-1], stats, state, hint=SYNC_HINT if done == 0 else "")


def weekly(stats, state, now):
    if now.weekday() == 6 and now.hour >= 12 and state.get("weekly_sent") != stats["today"]:
        n = stats.get("notify") or {}

        def available(m):
            text = m["body"] + m["title"]
            if "{weakest_deck}" in text:
                return bool(n.get("weakest_deck"))
            if "{retention}" in text:
                return (n.get("retention_7d") or 0) < (n.get("retention_prev_7d") or 0)
            if "{to_best}" in text:
                return False  # that one is about a live day, not a weekly recap
            return True

        fire("weekly", stats, state, bucket="stats", needs=available)
        state["weekly_sent"] = stats["today"]


def main():
    stats = json.loads(STATS.read_text())
    now = now_local()
    day_key = anki_day(now).isoformat()
    state = load_state(day_key)

    if os.environ.get("TEST_REMINDER") == "true":
        fire("test", stats, state, bucket="save_1h")
        save_state(state)
        return
    if stats["today"] != day_key:
        print("Stats are not from today, skipping reminders")
        return

    # Between midnight and the 4:00 rollover Anki still counts reviews for "today",
    # but Cinder's deadline has passed: the grace period stays quiet.
    if now.hour >= 4:
        decide(stats, state, now)
        weekly(stats, state, now)
    state["due_today"] = (stats.get("notify") or {}).get("due")
    save_state(state)


if __name__ == "__main__":
    main()
