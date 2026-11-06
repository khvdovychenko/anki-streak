"""The workflow wakes up every 15 minutes. This decides, in the user's own time zone,
whether this slot is worth a sync. Keeps AnkiWeb traffic to about a dozen syncs a day:

  - a few daytime checks (fresh stats, morning "you skipped" messages, partial-session nudges)
  - the slot ~30 min before you usually study (routine reminder)
  - the rescue slots before midnight: 21:00, 23:00, 23:45
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "collector"))
from settings import TIMEZONE  # noqa: E402

CHECK_HOURS = {8, 9, 10, 12, 14, 16, 18, 19, 20}
SAVE_SLOTS = [21 * 60, 23 * 60, 23 * 60 + 45]
SLOT = 30  # wide enough to survive GitHub running a scheduled job late

now = datetime.now(TIMEZONE)
minute_of_day = now.hour * 60 + now.minute
in_slot = lambda start: start <= minute_of_day < start + SLOT  # noqa: E731

usual = None
try:
    usual = json.loads((ROOT / "docs/data/stats.json").read_text())["notify"]["usual_start_minute"]
except Exception:
    pass
routine_slot = (usual - 30) if usual is not None else 18 * 60 + 30

run = (
    os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
    or (now.hour in CHECK_HOURS and now.minute < SLOT)
    or in_slot(routine_slot - routine_slot % 15)
    or any(in_slot(s) for s in SAVE_SLOTS)
)

print(f"{now:%H:%M} in {TIMEZONE.key}: {'running' if run else 'skipping'}")
with open(os.environ.get("GITHUB_OUTPUT", os.devnull), "a") as f:
    f.write(f"run={'true' if run else 'false'}\n")
