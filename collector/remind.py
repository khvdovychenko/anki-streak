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

# {days} ("12 днів"), {streak} (just the number) and {due} get filled in. Edit freely, it's your app.
MESSAGES = {
    1: [
        ("Картки чекають 🔥", "Стрік {days}. П'ять хвилин, і всі щасливі."),
        ("Маленьке нагадування", "Сьогодні ще жодного повторення. {due} карток чекають на тебе."),
        ("Ти ж не забула?", "Стрік {days} сам себе не продовжить."),
    ],
    2: [
        ("Стрік нервує 😬", "Стрік {days} тримається на чесному слові. Відкрий Анкі."),
        ("Ми помітили", "Сьогодні тиша. Французькі слова вже забувають, як ти виглядаєш."),
        ("Це вже не жарт", "Ще трохи, і стрік {days} згорить. Одна сесія. Зараз."),
    ],
    3: [
        ("Це втручання 🚨", "Твій стрік {days} зникне до ранку. Анкі. Негайно."),
        ("Ти серйозно?", "Netflix почекає. Картки ні. {due} повторень, вперед."),
        ("Остання розмова по-доброму", "Далі буде менш ввічливо. Відкрий Анкі."),
    ],
    4: [
        ("Останній шанс 💀", "До кінця дня лічені години. {days}. Ти справді це віддаси?"),
        ("Схоже, нагадування не працюють", "Ми перестанемо писати... Ні, не перестанемо. Анкі. Зараз."),
        ("Гаразд, ми ображені", "Стрік {days} зараз згорить, і винна будеш ти."),
    ],
}
SAVED = [("Стрік врятовано 🔥", "{days} поспіль. Отак би одразу.")]
LOST = [("Стрік згорів 🪦", "Вчора без повторень, стрік обнулився. Почни новий сьогодні.")]


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
    msg.set_content(body + (f"\n\nВідкрити: {APP_URL}" if APP_URL else ""))
    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as s:
        s.login(user, pw)
        s.send_message(msg)
    print("email sent:", title)


def days_word(n):
    """Ukrainian plural: 1 день, 2 дні, 5 днів."""
    if n % 10 == 1 and n % 100 != 11:
        return f"{n} день"
    if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14):
        return f"{n} дні"
    return f"{n} днів"


def notify(options, stats, email=True):
    title, body = random.choice(options)
    due = next((d["due"] for d in (stats.get("forecast") or [])[:1]), "Твої")
    n = stats["streak"]["current"]
    body = body.format(streak=n, days=days_word(n), due=due)
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

    if streak["reviewed_today"]:
        if state["sent_levels"] and not state["saved_sent"]:
            notify(SAVED, stats, email=False)
            state["saved_sent"] = True
    else:
        level = max((lvl for h, lvl in REMINDER_SCHEDULE.items() if now.hour >= h), default=0)
        if level and level not in state["sent_levels"]:
            notify(MESSAGES[level], stats)
            state["sent_levels"].append(level)

    save_state(state)


if __name__ == "__main__":
    main()
