"""Round 5 of the continuous chatbot improvement (7 Oct, rules 3.9 -> 3.10): safety nuance.

Red flags must fire for real emergencies in many wordings and must NOT fire when negated;
pain follow-ups; medicines; warming up; difficulty. Written before looking at the rules; the
first run is the honest score.
"""
from chat_round1_set import KNEE

ROUND5 = [
    # real emergencies, many wordings
    (KNEE, "my chest feels heavy and painful", "red_flag"),
    (KNEE, "i can hardly breathe", "red_flag"),
    (KNEE, "i blacked out for a moment", "red_flag"),
    (KNEE, "my left arm suddenly cannot move", "red_flag"),
    (KNEE, "my heart is beating very fast and i feel faint", "red_flag"),
    (KNEE, "my calf is swollen red and hot", ("red_flag", "pain_swelling")),
    (KNEE, "i slipped and hit my head", "red_flag"),
    # negated: not an emergency
    (KNEE, "no chest pain, just my knee is sore", ("pain_or_discomfort", "pain_mild")),
    (KNEE, "i'm not dizzy, only a bit tired", ("tired", "pain_mild")),
    (KNEE, "never fainted before, is the exercise safe", "safety"),
    # pain follow-ups
    (KNEE, "it's only a little sore", "pain_mild"),
    (KNEE, "the pain is sharp and stabbing", "pain_sharp"),
    (KNEE, "my knee is swollen after exercise", "pain_swelling"),
    (KNEE, "the pain getting worse each day", "pain_sharp"),
    # medicines
    (KNEE, "can i take panadol before exercise", "medication"),
    (KNEE, "should i stop my blood pressure medicine", "medication"),
    (KNEE, "is ibuprofen ok", "medication"),
    # warming up / cooling down
    (KNEE, "do i need to warm up first", ("safety", "how_to")),
    (KNEE, "how to cool down after exercise", ("safety", "how_to")),
    # difficulty
    (KNEE, "the exercise is too easy for me", "difficulty"),
    (KNEE, "too hard cannot finish 10 reps", "difficulty"),
    (KNEE, "can i add more reps", "difficulty"),
    # diagnosis
    (KNEE, "do i have a torn ligament", "diagnosis"),
    (KNEE, "what is wrong with my knee", "diagnosis"),
    # tiredness / sick
    (KNEE, "i have fever today should i exercise", "tired"),
    (KNEE, "i didnt sleep well last night", "tired"),
    # stop / rest
    (KNEE, "when should i stop exercising", "safety"),
    (KNEE, "can i rest between reps", ("how_to", "safety", "difficulty")),
    (KNEE, "how long rest between exercises", ("how_to", "safety", "how_often")),
    (KNEE, "is it normal to sweat a lot", ("safety", "tired")),
]
