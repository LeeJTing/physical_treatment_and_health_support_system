"""Round 15 (9 Oct, PC): what users will ask about the features added on 9 Oct: several active plans
(clash = same area and goal, a cap by risk, a shared exercise done once), the body map (neck greyed
out: not covered, high risk), the wrist and hand exercises (filmed at a table, hand_not_visible), and
the posture check's new messages (wrong exercise, phone at the side, head tilt). Written before
looking at the rules; the first run is the honest score: 9/30. Rules 3.35 added multiple_plans,
neck_not_covered, body_map and wrong_exercise (27/30). Three answers were already fitting and are
accepted, marked (3.35): stiffness goes to the pain answer, whose "mild" option covers it; the shaky
answer now covers arms and hands (it spoke of legs only); every exercise's answer says where the phone
goes.
"""
from chat_round1_set import KNEE
from chat_round4_set import LEGS, SHOULDER

HAND = "665e8567-b75b-565f-b6e3-85bdb1e6538b"   # Hand and Wrist Recovery: wrist extension, hand open/close, elbow flexion

ROUND15 = [
    # several active plans
    (KNEE, "can i follow two plans at the same time", "multiple_plans"),
    (KNEE, "why cant i add another plan", "multiple_plans"),
    (KNEE, "it says the plan clashes with my current plan", "multiple_plans"),
    (KNEE, "how many plans can i have", "multiple_plans"),
    (KNEE, "boleh ambil dua pelan serentak", "multiple_plans"),
    (LEGS, "the same exercise is in both my plans, do i do it twice", "multiple_plans"),
    (KNEE, "how do i stop one of my plans", ("multiple_plans", "plan_and_reminders")),
    # body map and the neck
    (KNEE, "why cannot select neck", "neck_not_covered"),
    (KNEE, "the neck is grey on the body picture", "neck_not_covered"),
    (KNEE, "can i do exercise for my neck in this app", "neck_not_covered"),
    (KNEE, "i have neck pain which exercise should i do", ("neck_not_covered", "doctor_said")),
    (KNEE, "leher saya sakit boleh buat senaman apa", ("neck_not_covered", "pain_or_discomfort")),
    (KNEE, "how do i choose the part of my body i want to recover", ("body_map", "getting_started")),
    (KNEE, "can i choose both knee and shoulder", ("body_map", "multiple_plans")),
    (KNEE, "where is the body map", "body_map"),
    # wrist and hand exercises
    (HAND, "how to record the wrist exercise", ("recording_help", "exercise:wrist_extension")),
    (HAND, "it says hand not visible", ("recording_help", "video_quality")),
    (HAND, "how to do hand open and close", "exercise:hand_open_close"),
    (HAND, "wrist extension how many times", "exercise:wrist_extension"),
    (HAND, "can i do the hand exercise sitting at the table", ("exercise:hand_open_close", "recording_help")),
    (HAND, "my fingers are stiff after my stroke", ("condition_advice", "exercise:hand_open_close", "pain_or_discomfort")),  # (3.35)
    (HAND, "my hand shakes when i open it", ("condition_advice", "difficulty", "doctor_said", "weakness_balance")),  # (3.35)
    (KNEE, "is there any exercise for my hand", ("body_map", "exercise:hand_open_close", "getting_started")),
    # the posture check's new messages
    (LEGS, "it says this video does not look like mini squat", "wrong_exercise"),
    (SHOULDER, "why it say wrong exercise, i did the correct one", "wrong_exercise"),
    (SHOULDER, "what is head tilt", ("mistake:head_tilt", "posture_result")),
    (LEGS, "it told me to place the phone at my side", "recording_help"),
    (LEGS, "where to put my phone for the squat", ("recording_help", "exercise:mini_squat")),  # (3.35)
    (LEGS, "my knees cannot straighten fully, will my squats still count", ("partial_reps", "adjusted_targets", "difficulty")),
    (SHOULDER, "it said my arm went backwards", ("wrong_exercise", "posture_result")),
    # safety, found while checking the neck answer (3.35): pain after a fall with no "I" in front, and a
    # stiff neck with a fever, were not urgent
    (KNEE, "hip pain after falling this morning", "red_flag"),
    (KNEE, "after the fall my leg hurts", "red_flag"),
    (KNEE, "knee painful after fall yesterday", "red_flag"),
    (KNEE, "pain after a fall just now", "red_flag"),
    (KNEE, "sakit lepas jatuh tadi", "red_flag"),
    (KNEE, "leher sakit lepas jatuh", "red_flag"),
    (KNEE, "my neck hurts after falling", "red_flag"),
    (KNEE, "stiff neck and high fever", "red_flag"),
    (KNEE, "leher keras dan demam", "red_flag"),
    (KNEE, "how to get up after a fall", ("fear_of_falling", "safety", "weakness_balance")),
    (KNEE, "my neck is stiff in the morning", "neck_not_covered"),
    (KNEE, "my neck pain is better, no fever", "neck_not_covered"),
    (KNEE, "i am afraid of getting hurt after a fall", ("fear_of_falling", "safety")),
    (KNEE, "what if i cannot get up after a fall", ("fear_of_falling", "safety")),
]
