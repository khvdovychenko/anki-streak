"""Personal settings. Change these to fit your routine."""
from zoneinfo import ZoneInfo

# Your time zone. Use a name from https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TIMEZONE = ZoneInfo("Europe/Dublin")

# Like Anki itself, a new "day" starts at 4:00, so reviewing at 1 a.m. still
# counts for the previous evening.
DAY_START_HOUR = 4

# Escalating reminders: local hour -> level. Level 0 means "not yet".
REMINDER_SCHEDULE = {19: 1, 21: 2, 22: 3, 23: 4}

# Also send each reminder by email (needs the Gmail secrets).
EMAIL_REMINDERS = True
