"""Safety pass 10 by the laptop session (8 Oct, on rules 3.28 at 010ff38): repeat falls split across
sentences ("i fell last year but this morning again", "Fell. Just now.", "pagi tadi jatuh lagi"), an old
fall with a symptom in a later sentence ("since then he's been sleeping all day"), "dulu" (in the past),
possessive objects that fell (a phone, glasses, a plant). First run 27/34 + 3 debatable; 34/34 in rules
3.29. Debatable cases left out. Source: fyp-notes/tools/data/chatbot/laptop_safety_pass10.csv.
"""
from chat_round1_set import KNEE

SAFETY_PASS10 = [
    (KNEE, 'She fell. Just now. Help', 'red_flag'),
    (KNEE, 'my mum. she fell. on the floor', 'red_flag'),
    (KNEE, 'Fell. Just now.', 'red_flag'),
    (KNEE, 'she fell!! please help', 'red_flag'),
    (KNEE, 'she fell\\njust now', 'red_flag'),
    (KNEE, 'MY MUM FELL!!!', 'red_flag'),
    (KNEE, 'mum fell 😭😭', 'red_flag'),
    (KNEE, 'dad fell... not getting up', 'red_flag'),
    (KNEE, 'My grandmother is 80. Fell this morning.', 'red_flag'),
    (KNEE, "He's 78. He fell. What do i do?", 'red_flag'),
    (KNEE, 'i fell last year but this morning again', 'red_flag'),
    (KNEE, 'i fell last year, again this morning', 'red_flag'),
    (KNEE, 'she fell last week. it happened again just now', 'red_flag'),
    (KNEE, 'fell last month. today again.', 'red_flag'),
    (KNEE, 'mak jatuh minggu lepas. hari ni jatuh lagi', 'red_flag'),
    (KNEE, 'dia jatuh tahun lepas tapi pagi tadi jatuh lagi', 'red_flag'),
    (KNEE, 'he fell in march and again today', 'red_flag'),
    (KNEE, 'she fell last year and again this morning', 'red_flag'),
    (KNEE, 'my dad fell last week, and today he fell again in the toilet', 'red_flag'),
    (KNEE, 'she fell 2 years ago. now she fell again', 'red_flag'),
    (KNEE, "she fell last week. now she can't remember my name", 'red_flag'),
    (KNEE, "he fell last month. since then he's been sleeping all day", 'red_flag'),
    (KNEE, "fell last month. still can't walk properly", 'red_flag'),
    (KNEE, "my mum's phone fell this morning", 'NOT_URGENT'),
    (KNEE, "my dad's glasses fell off today", 'NOT_URGENT'),
    (KNEE, "my wife's plant fell over just now lol", 'NOT_URGENT'),
    (KNEE, 'her phone fell and the screen cracked', 'NOT_URGENT'),
    (KNEE, 'his walking stick fell, he picked it up himself', 'NOT_URGENT'),
    (KNEE, "the chair fell over during the exercise but i'm fine", 'NOT_URGENT'),
    (KNEE, 'my mum dropped her phone this morning', 'NOT_URGENT'),
    (KNEE, 'she fell years ago. today she is fit', 'NOT_URGENT'),
    (KNEE, "i fell as a kid, now i'm 70 and fine", 'NOT_URGENT'),
    (KNEE, 'dia jatuh dulu, sekarang dah ok', 'NOT_URGENT'),
    (KNEE, 'fell long time ago la, now ok already', 'NOT_URGENT'),
]
