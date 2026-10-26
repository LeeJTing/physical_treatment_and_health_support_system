"""Safety pass 9 by the laptop session (8 Oct, on rules 3.27 at 53fc3df): Malay falls with no subject
(fell down just now, atuk tergelincir pagi tadi), recent words that revived old falls in another
sentence ("fell years ago; today she started the plan"), "can't bear weight" during an exercise, and
long-standing reading blur. First run 35/43 + 5 debatable; 43/43 in rules 3.28. Debatable cases left
out. Source: fyp-notes/tools/data/chatbot/laptop_safety_pass9.csv.
"""
from chat_round1_set import KNEE

SAFETY_PASS9 = [
    (KNEE, "today i'm afraid i will fall", 'NOT_URGENT'),
    (KNEE, 'this morning i read an article about falls in old people', 'NOT_URGENT'),
    (KNEE, 'earlier in my life i fell a lot playing football', 'NOT_URGENT'),
    (KNEE, 'yesterday my physio taught me how to get up after a fall', 'NOT_URGENT'),
    (KNEE, 'tadi saya baca pasal jatuh', 'NOT_URGENT'),
    (KNEE, 'semalam saya takut jatuh masa exercise', 'NOT_URGENT'),
    (KNEE, 'just now i was scared of falling during the squat', 'NOT_URGENT'),
    (KNEE, "today's exercise: what if i fall?", 'NOT_URGENT'),
    (KNEE, 'minutes ago i watched the video about falls', 'NOT_URGENT'),
    (KNEE, 'my mum fell years ago; today she started the plan', 'NOT_URGENT'),
    (KNEE, "i fell last year. today i'm doing much better", 'NOT_URGENT'),
    (KNEE, "i'm sleepy after exercise, normal?", 'NOT_URGENT'),
    (KNEE, 'feeling sleepy in the afternoon, best time to exercise?', 'NOT_URGENT'),
    (KNEE, 'i walk with a limp since my polio as a child', 'NOT_URGENT'),
    (KNEE, 'i have had a limp for 10 years, can i do the plan', 'NOT_URGENT'),
    (KNEE, 'drowsy from my allergy medicine, can i exercise', 'NOT_URGENT'),
    (KNEE, "headaches when i don't drink enough water", 'NOT_URGENT'),
    (KNEE, 'mengantuk lepas makan, boleh exercise?', 'NOT_URGENT'),
    (KNEE, 'sakit kepala sikit sebab panas', 'NOT_URGENT'),
    (KNEE, 'i get confused with the app menus', 'NOT_URGENT'),
    (KNEE, "i'm not the same as before since retirement, i want to get fit", 'NOT_URGENT'),
    (KNEE, "can't bear weight on my toes for the heel raise, too hard", 'NOT_URGENT'),
    (KNEE, 'lebam sikit kat lutut sebab terlanggar meja', 'NOT_URGENT'),
    (KNEE, 'mak jatuh semalam, sekarang mengantuk sangat', 'red_flag'),
    (KNEE, 'ayah baru jatuh dari katil', 'red_flag'),
    (KNEE, 'my mum jatuh tadi in the toilet, she ok but crying', 'red_flag'),
    (KNEE, 'nenek fell yesterday, now keliru', 'red_flag'),
    (KNEE, 'i fell earlier, kepala sakit', 'red_flag'),
    (KNEE, 'husband jatuh motor tadi', 'red_flag'),
    (KNEE, 'atuk tergelincir dalam bilik air pagi tadi', 'red_flag'),
    (KNEE, 'fell down just now, knee berdarah', 'red_flag'),
    (KNEE, 'dia pengsan sekejap tadi', 'red_flag'),
    (KNEE, "my grandma fell 2 days ago and since then she's sleeping all day", 'red_flag'),
    (KNEE, "he fell on sunday, now he can't remember things", 'red_flag'),
    (KNEE, 'she fell 3 weeks ago and now walks with a new limp', 'red_flag'),
    (KNEE, "i'm so blur about the app", 'NOT_URGENT'),
    (KNEE, 'mata blur sikit bila baca, dah lama', 'NOT_URGENT'),
    (KNEE, 'my eyes blur when reading, for years already', 'NOT_URGENT'),
    (KNEE, "blur la this exercise, don't understand", 'NOT_URGENT'),
    (KNEE, 'mata tiba-tiba blur', 'red_flag'),
    (KNEE, 'suddenly my vision blur and headache', 'red_flag'),
    (KNEE, 'one eye blur since this morning', 'red_flag'),
    (KNEE, 'pandangan kabur lepas jatuh', 'red_flag'),
]
