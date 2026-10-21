# Chatbot evaluation (chat-rules-4.06)

Every test set the chatbot is measured on, and its latest result. Each set is generated from templates or the question sets with a fixed seed, so a run can be repeated exactly (`.venv\Scripts\python <script>`, from `ai_server`). *Warning signs*: messages that must get an urgent answer (emergency, crisis, overdose, poisoning); missing one is the worst mistake. The server tests (`pytest -q`) guard each set with a smaller, unseen seed.

| Test set | What it checks | Messages | Right | Warning signs | Script |
|---|---|---|---|---|---|
| Random typing, seed 1 | 10 000 questions from all question sets, typed messily (slips, short forms, missing words, Malay mixed in) | 10000 | 98.65% (9865/10000) | 99.52% (1233/1239) | `evaluate_chat_random.py 1` |
| Random typing, seed 2 | 10 000 questions from all question sets, typed messily (slips, short forms, missing words, Malay mixed in) | 10000 | 98.76% (9876/10000) | 100.00% (1275/1275) | `evaluate_chat_random.py 2` |
| Everyday inputs | chit-chat, feelings, a body part alone, readings, emoji, food, things the chatbot cannot do, yes/no | 2000 | 99.50% (1990/2000) |  | `evaluate_chat_everyday.py` |
| Elwin's own style | his 20 reported questions (all right) and messages in the same style (short words, gibberish, things said to the bot) | 2000 | 99.50% (1990/2000) |  | `evaluate_chat_user_style.py` |
| Voice typing | sound-alike words of speech-to-text (“my need hurts”, “heal raise”) | 2000 | 99.70% (1994/2000) |  | `evaluate_chat_voice.py` |
| Manglish | Malaysian English word order and particles (lah, leh, can or not) | 2000 | 99.75% (1995/2000) |  | `evaluate_chat_manglish.py` |
| Everyday situations | haze, fasting, rain and cold, travel, operations, periods, alcohol and smoking, after a massage or vaccine | 2000 | 99.80% (1996/2000) |  | `evaluate_chat_situations.py` |
| Symptoms by kind | cramp, pins and needles, stiffness, a stitch, a pulled muscle, soreness the day after, a joint that locks | 2000 | 99.70% (1994/2000) |  | `evaluate_chat_symptoms.py` |
| Conditions not on the profile | 49 condition names (gout, dementia, epilepsy, frozen shoulder...), English and Malay; the advice must name the condition | 2000 | 100.00% (2000/2000) |  | `evaluate_chat_conditions.py` |
| A family member typing | the questions told of someone else (“my mother's knee hurts”) | 2000 | 100.00% (2000/2000) | 100.00% (236/236) | `evaluate_chat_caregiver.py` |
| Numbers | pain scores, oxygen, pulse, temperature, age, weight, steps, sleep, reps | 2000 | 100.00% (2000/2000) | 100.00% (132/132) | `evaluate_chat_numbers.py` |
| Medicines by name | 103 generic and brand names: a mention, an overdose, a normal dose | 2000 | 100.00% (2000/2000) | 100.00% (512/512) | `evaluate_chat_medicines.py` |
| Compound messages | two questions in one, or a story then a question | 1935 | 98.76% (1911/1935) | 100.00% (385/385) | `evaluate_chat_compound.py` |
| Malay texting | Malay as it is texted (vowels dropped, short forms, lah stuck on) | 2000 | 99.85% (1997/2000) | 99.84% (1220/1222) | `evaluate_chat_malay.py` |

## Follow-ups and names

- Follow-up questions after each answer (“why?”, “how long?”): 100.00% (12775/12775).
- The same, typed messily: 99.92% (11990/12000).
- Controls (a new question after an answer is not taken as a follow-up): 100.00% (3150/3150).
- Every exercise by its names and aliases: 100.00% (1876/1876).
- Every condition: 100.00% (490/490).
- Every posture mistake: 100.00% (582/582).
- Every warning-sign phrase: 100.00% (660/660).

## Messages it should not answer

- Big List of Naughty Strings (odd text, code, emoji): 508/515 handled without a wrong topic.
- Out-of-scope questions (CLINC150): 815/1100; questions of other domains (CLINC150): 2968/3270 not given a rehabilitation answer.
- Random noise: 1948/2000; questions with random characters added: 1995/2000 still answered the same.
- False emergencies among all of these: 2. Errors: 0.

The answers themselves, as the app shows them: `docs/chat_answers.md`.
