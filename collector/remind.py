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

# {days} ("12-day"), {streak} (just the number) and {due} get filled in. Edit freely, it's your app.
MESSAGES = {
    1: [
        ("Your cards miss you 🔥", "{days} streak. Five minutes and everyone's happy."),
        ("Friendly reminder", "Not a single review today. {due} cards are waiting for you."),
        ("You didn't forget, right?", "Your {days} streak won't extend itself."),
    ],
    2: [
        ("Your streak is nervous 😬", "Your {days} streak is hanging by a thread. Open Anki."),
        ("We noticed", "It's quiet today. Your vocabulary is starting to forget what you look like."),
        ("This isn't a joke anymore", "A little longer and your {days} streak is gone. One session. Now."),
    ],
    3: [
        ("This is an intervention 🚨", "Your {days} streak disappears by morning. Anki. Now."),
        ("Seriously?", "Netflix can wait. Your cards can't. {due} reviews, go."),
        ("Last polite message", "It gets less polite from here. Open Anki."),
    ],
    4: [
        ("Last chance 💀", "Only a few hours left today. A {days} streak. Are you really giving it up?"),
        ("These reminders don't seem to work", "We'll stop messaging you... Just kidding. Anki. Now."),
        ("Fine. We're hurt.", "Your {days} streak is about to burn, and it's on you."),
    ],
}
# Started, but the goal isn't met yet. {done}, {goal} and {left} get filled in.
PARTIAL = {
    1: [("Nice start, not done", "{done} of {goal} reviews. Keep going, you're almost warmed up."),
        ("That's it?", "{done} reviews and you left? {left} more to go.")],
    2: [("We saw that 👀", "{done} reviews is a warm-up, not a session. {left} to go."),
        ("Half-hearted", "Your cards noticed you stopped at {done}. Finish the job.")],
    3: [("Seriously, {done}?", "Your goal is {goal}. Two minutes of effort doesn't count."),
        ("Come back", "{left} reviews between you and a clean conscience.")],
    4: [("Last call 💀", "Day's almost over and you're stuck at {done} of {goal}."),
        ("We expected more", "{done} reviews. Your future self is disappointed. {left} to go.")],
}
SYNC_HINT = " Already studied? Tap sync in Anki so we can see it."
SAVED = [("Goal done 🔥", "{days} streak and today's goal is in the bag. Was that so hard?")]
LOST = [("Your streak is gone 🪦", "No reviews yesterday, so the streak reset. Start a new one today.")]


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
