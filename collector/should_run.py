"""The workflow wakes up every hour. This decides whether this hour is worth
a sync in the user's own time zone: a few times in the day for fresh stats,
and every hour of the reminder window. Keeps AnkiWeb traffic to ~10 syncs a day.
"""
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from settings import REMINDER_SCHEDULE, TIMEZONE  # noqa: E402

STATS_HOURS = {8, 12, 16}

hour = datetime.now(TIMEZONE).hour
first, last = min(REMINDER_SCHEDULE), max(REMINDER_SCHEDULE)
run = hour in STATS_HOURS or first <= hour <= last or os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"

print(f"Local hour {hour} in {TIMEZONE.key}: {'running' if run else 'skipping'}")
with open(os.environ.get("GITHUB_OUTPUT", os.devnull), "a") as f:
    f.write(f"run={'true' if run else 'false'}\n")
