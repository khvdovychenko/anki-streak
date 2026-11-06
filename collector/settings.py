"""Personal settings.

Change them without touching code: on GitHub open Settings → Secrets and
variables → Actions → Variables, and add any of these:

  TIMEZONE         e.g. Europe/Dublin, America/New_York (default Europe/Dublin)
                   Full list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  REMINDER_HOURS   hour Cinder starts looking worried in the app (default 19); reminder
                   timing itself lives in remind.py and messages.json
  EMAIL_REMINDERS  "false" to get push notifications only (default true)
  DAY_START_HOUR   when a new study day starts, like in Anki (default 4)
  DAILY_GOAL       reviews per day before reminders stop (default 30);
                   clearing everything due today also counts as done
  SPICE_MAX        how mean Cinder may get: 1 cheeky, 2 guilt trip, 3 unhinged (default 3)
  NAME             your first name, used in some messages
"""
import os
from zoneinfo import ZoneInfo


def _env(name, default):
    value = os.environ.get(name, "").strip()
    return value or default


TIMEZONE = ZoneInfo(_env("TIMEZONE", "Europe/Dublin"))

# A new "day" starts at 4:00, so reviewing at 1 a.m. still counts for the previous evening.
DAY_START_HOUR = int(_env("DAY_START_HOUR", "4"))

# Escalating reminders: local hour -> level 1..4.
_hours = [int(h) for h in _env("REMINDER_HOURS", "19,21,22,23").split(",")][:4]
REMINDER_SCHEDULE = {h: level for level, h in enumerate(sorted(_hours), start=1)}

# Reminders stop only when today's goal is met: this many reviews,
# or every card due today is done, whichever comes first.
DAILY_GOAL = int(_env("DAILY_GOAL", "30"))

EMAIL_REMINDERS = _env("EMAIL_REMINDERS", "true").lower() != "false"

# 1 = cheeky, 2 = guilt trip, 3 = unhinged (see collector/messages.json)
SPICE_MAX = int(_env("SPICE_MAX", "3"))

NAME = _env("NAME", "")
