"""Safety pass 13 by the PC session (9 Oct, on rules 3.35 at 02455ee): a generated probe of fall
messages, 8 people x 10 fall phrasings x 7 times x 11 injuries (6,160 sentences), missed 160: a trip or
a Malay slip ("tergelincir") told without a time word ("dad tripped on the stairs and cannot stand up",
"grandma tergelincir kaki sakit"), and a fall told without a person ("fell, hip hurts", "jatuh, kepala
sakit", "a fall and now hip pain"; 21 of 350). Fixed in rules 3.36: a fall word with an injury word
close by is urgent, except in questions about preventing or fearing falls, and the Malay words for
slipping, tripping, rolling off and collapsing are read. NOT_URGENT: must not be an emergency answer.
"""
from chat_round1_set import KNEE

SAFETY_PASS13 = [
    # missed before 3.36
    (KNEE, "dad tripped on the stairs and cannot stand up", "red_flag"),
    (KNEE, "my mother tripped on the stairs and her hip hurts", "red_flag"),
    (KNEE, "grandma tergelincir kaki sakit", "red_flag"),
    (KNEE, "mak saya tergelincir tak boleh bangun", "red_flag"),
    (KNEE, "atuk tersandung, lutut bengkak", "red_flag"),
    (KNEE, "fell, hip hurts", "red_flag"),
    (KNEE, "jatuh, kepala sakit", "red_flag"),
    (KNEE, "a fall and now hip pain", "red_flag"),
    (KNEE, "ayah rebah di bilik air, tak boleh bangun", "red_flag"),
    (KNEE, "my husband slipped in the kitchen and the wrist looks bent", "red_flag"),
    (KNEE, "fell off the chair during the exercise, my back is very painful", "red_flag"),
    # already urgent, kept
    (KNEE, "i fell just now and my knee is swollen", "red_flag"),
    (KNEE, "my mother fell this morning and is confused", "red_flag"),
    # not emergencies
    (KNEE, "what if i fall and hurt myself", "NOT_URGENT"),
    (KNEE, "how do i prevent falls, my knees hurt sometimes", "NOT_URGENT"),
    (KNEE, "i am scared of falling because my knee is weak", "NOT_URGENT"),
    (KNEE, "my pain fell from 6 to 3 this week", "NOT_URGENT"),
    (KNEE, "knee hurts a little in the fall prevention class", "NOT_URGENT"),
    (KNEE, "i fell asleep and my neck is a bit sore", "NOT_URGENT"),
    (KNEE, "the phone fell while recording", "NOT_URGENT"),
    (KNEE, "my score fell, is the pain normal", "NOT_URGENT"),
    (KNEE, "my mother is afraid she will fall and hurt her hip", "NOT_URGENT"),
]
