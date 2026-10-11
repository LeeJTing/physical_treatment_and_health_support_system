"""Round 17 (9 Oct, PC): reminders that come late or not at all, after the alarm and notification changes
(afd2dc9: exact alarms only where the phone allows them, otherwise up to an hour late; 41d2ac8: "Turn on
notifications" on the Reminders page). Written before changing the rules; first run 0/10 (every one went
to the general reminders answer, which says neither). Rules 3.46 added reminder_late_or_off: 10/10;
"i couldnt exercise on time" / "is it too late to exercise" stay best_time.
"""
from chat_round1_set import KNEE

ROUND17 = [
    (KNEE, "why did my reminder come late", "reminder_late_or_off"),
    (KNEE, "the reminder came one hour late", "reminder_late_or_off"),
    (KNEE, "reminder not on time", "reminder_late_or_off"),
    (KNEE, "my notification came late", "reminder_late_or_off"),
    (KNEE, "why is my reminder delayed", "reminder_late_or_off"),
    (KNEE, "notifications are turned off what do i do", "reminder_late_or_off"),
    (KNEE, "how do i turn on notifications", "reminder_late_or_off"),
    (KNEE, "it says my reminders cannot ring", "reminder_late_or_off"),
    (KNEE, "i pressed dont allow by mistake", "reminder_late_or_off"),
    (KNEE, "peringatan lambat", "reminder_late_or_off"),
]
