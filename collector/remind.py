"""Duolingo-style escalating reminders: push notifications + email.

Runs every evening hour. Reads docs/data/stats.json, decides whether you
have studied today, and if not, sends the next (meaner) message.
Remembers what it already sent in data/state.json so nothing repeats.
"""
import json
import os
import random
import smtplib
import sys
from email.message import EmailMessage
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "collector"))
from analyze import anki_day, now_local  # noqa: E402
from settings import EMAIL_REMINDERS, REMINDER_SCHEDULE  # noqa: E402

STATS = ROOT / "docs" / "data" / "stats.json"
STATE = ROOT / "data" / "state.json"
APP_URL = os.environ.get("APP_URL", "")

# The voice is the streak flame itself: needy, dramatic, passive-aggressive.
# {days} ("12-day"), {streak} (just the number), {due}, {done}, {goal} and {left}
# get filled in. Edit freely, it's your app.
MESSAGES = {
    1: [
        ("Hi, it's your streak 🔥", "Just checking you're alive. You haven't opened Anki today. No pressure. Some pressure."),
        ("{due} cards are waiting", "They've been sitting there all day. Patiently. Unlike some people."),
        ("Did you forget about me?", "{days} streak. I'd hate for something to happen to it."),
        ("Friendly reminder 🙂", "This is the nice version. You won't like the next ones."),
    ],
    2: [
        ("I see you on Instagram 👀", "Plenty of time for that. Zero time for your {due} cards. Interesting."),
        ("Your streak is shaking", "{days} of work, hanging by a thread. One session. That's all I'm asking."),
        ("Your vocabulary is fading", "Every hour you wait, a word quietly packs its bags and leaves."),
        ("Remember when you cared?", "You built a {days} streak. Past you would be so disappointed right now."),
    ],
    3: [
        ("This is an intervention 🚨", "We're all worried. Your {days} streak is dying and you're just letting it happen."),
        ("I'm not angry. I'm disappointed.", "You promised yourself you'd be fluent. Was that a lie?"),
        ("Netflix will still be there", "Your {days} streak won't. {due} cards. Now."),
        ("Do you even want this?", "Because right now it really doesn't look like it."),
    ],
    4: [
        ("Last chance 💀", "Your {days} streak dies at midnight. I'll remember who let it happen."),
        ("These reminders don't seem to work", "So I'll stop sending them. ...Just kidding. I'll never stop. Open Anki."),
        ("Fine. Let it burn. 🔥", "{days} of work. Gone. Because you couldn't spare five minutes."),
        ("I'll just tell everyone", "That you gave up on a {days} streak tonight. Unless you open Anki."),
    ],
}
# Started, but the goal isn't met yet.
PARTIAL = {
    1: [
        ("That's it? {done}?", "You opened Anki, did {done} cards and left. Bold strategy. {left} to go."),
        ("Warm-up done. Now study.", "{done} reviews is not a session. It's a cameo. {left} left."),
    ],
    2: [
        ("Your cards saw you leave", "{done} out of {goal}. They're asking if they did something wrong."),
        ("Half-effort detected 🔍", "{done} reviews and done for the day? Your goal says {goal}."),
    ],
    3: [
        ("Quitting at {done}?", "Your goal is {goal}. Doing {done} and calling it a day is how fluency dies."),
        ("We need to talk", "About the {left} cards you abandoned tonight."),
    ],
    4: [
        ("Day's ending. You're at {done}.", "{done} of {goal}. Future you will open Anki tomorrow and suffer for this."),
        ("Disappointing, honestly", "You started. You stopped. {left} cards are still waiting. Finish it."),
    ],
}
SYNC_HINT = " (Already studied? Tap sync in Anki, I can't see it otherwise.)"
SAVED = [
    ("Fine. You did it. 🔥", "{days} streak and goal done. Was that so hard? Same time tomorrow."),
    ("Streak saved 🔥", "See? Wasn't so hard. I'll be watching tomorrow too."),
]
LOST = [
    ("Your streak is gone 🪦", "Yesterday you didn't study. The streak is dead. Start a new one today, and don't do that again."),
    ("Well. That happened.", "Your streak reset to zero. I'm not saying it's your fault. It's your fault. Day 1 starts now."),
]


def load_state(today_key):
    try:
        state = json.loads(STATE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    if state.get("day") != today_key:
        state = {"day": today_key, "sent_levels": [], "saved_sent": False,
                 "lost_sent_for": state.get("lost_sent_for")}
    return state


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=1))


def send_push(title, body):
    raw = os.environ.get("PUSH_CONFIG")
    if not raw:
        print("PUSH_CONFIG not set, skipping push")
        return
    from pywebpush import WebPushException, webpush
    cfg = json.loads(raw)
    try:
        webpush(
            subscription_info=cfg["subscription"],
            data=json.dumps({"title": title, "body": body, "url": APP_URL}),
            vapid_private_key=cfg["privateKey"],
            vapid_claims={"sub": "mailto:" + (os.environ.get("GMAIL_USER") or "anki-streak@example.com")},
            ttl=3600,
        )
        print("push sent:", title)
    except WebPushException as e:
        print("push failed:", e)


def send_email(title, body):
    if not EMAIL_REMINDERS:
        return
    user, pw = os.environ.get("GMAIL_USER"), os.environ.get("GMAIL_APP_PASSWORD")
    if not user or not pw:
        print("Gmail secrets not set, skipping email")
        return
    msg = EmailMessage()
    msg["Subject"], msg["From"], msg["To"] = title, f"Anki Streak <{user}>", os.environ.get("EMAIL_TO") or user
    msg.set_content(body + (f"\n\nOpen your stats: {APP_URL}" if APP_URL else ""))
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
        s.login(user, pw)
        s.send_message(msg)
    print("email sent:", title)


def days_word(n):
    """Used before 'streak': '1-day', '12-day'."""
    return f"{n}-day"


def notify(options, stats, email=True, hint=""):
    title, body = random.choice(options)
    due = next((d["due"] for d in (stats.get("forecast") or [])[:1]), "Your")
    n = stats["streak"]["current"]
    g = stats.get("goal") or {"target": 0, "done": 0}
    left = max(g["target"] - g["done"], 0)
    if g.get("due_left") is not None:
        left = min(left, g["due_left"]) or left
    fmt = dict(streak=n, days=days_word(n), due=due, done=g["done"], goal=g["target"], left=left)
    title, body = title.format(**fmt), body.format(**fmt)
    body += hint
    send_push(title, body)
    if email:
        send_email(title, body)


def main():
    stats = json.loads(STATS.read_text())
    now = now_local()
    today_key = anki_day(now).isoformat()
    state = load_state(today_key)

    if os.environ.get("TEST_REMINDER") == "true":
        notify(MESSAGES[2], stats)
        return

    if stats["today"] != today_key:
        print("Stats are not from today, skipping reminders")
        return

    streak = stats["streak"]
    # Morning: yesterday was missed and an earlier streak existed.
    if (streak.get("lost_yesterday") and not streak["reviewed_today"]
            and now.hour < 12 and state.get("lost_sent_for") != today_key):
        notify(LOST, stats, email=False)
        state["lost_sent_for"] = today_key

    goal_met = (stats.get("goal") or {}).get("met", streak["reviewed_today"])
    if goal_met:
        if state["sent_levels"] and not state["saved_sent"]:
            notify(SAVED, stats, email=False)
            state["saved_sent"] = True
    else:
        level = max((lvl for h, lvl in REMINDER_SCHEDULE.items() if now.hour >= h), default=0)
        if level and level not in state["sent_levels"]:
            if streak["reviewed_today"]:
                notify(PARTIAL[level], stats)
            else:
                notify(MESSAGES[level], stats, hint=SYNC_HINT)
            state["sent_levels"].append(level)

    save_state(state)


if __name__ == "__main__":
    main()
