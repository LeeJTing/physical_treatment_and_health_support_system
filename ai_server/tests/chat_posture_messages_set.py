"""Questions about the posture check's new messages (8 Oct, rules 3.16): possible-fall alert,
targets adjusted to the health profile, partial repetitions, dark video / small figure, balance tip.
Probed first: 0/7 had a fitting answer (none, posture_result, plan_exercises, profile_help,
equipment); four topics were added for them.
"""
from chat_round1_set import KNEE

POSTURE_MESSAGES = [
    (KNEE, "why are my targets adjusted", "adjusted_targets"),
    (KNEE, "it says my video is quite dark", "video_quality"),
    (KNEE, "the app said i may have fallen", ("fall_alert", "red_flag")),
    (KNEE, "it says partial repetitions", "partial_reps"),
    (KNEE, "what does targets adjusted to my health profile mean", "adjusted_targets"),
    (KNEE, "it told me to hold on to a chair because i swayed", ("weakness_balance", "safety")),
    (KNEE, "why does it say move the phone closer", ("video_quality", "recording_help")),
]
