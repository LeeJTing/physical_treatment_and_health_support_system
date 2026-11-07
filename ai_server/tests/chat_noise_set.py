"""Random characters (Elwin, 20 Oct: "keep on testing and improving the chatbot ... for random
characters"). Two kinds of message, generated, never hand-picked:

  noise   nothing to answer: keyboard mashing, random letters or digits, emoji or punctuation only,
          symbols, links, code, a very long line, another script, words in random order. The chatbot
          must not invent a topic, must never give an emergency answer, and must not fail.
  noisy   a question with a known answer with random characters around or inside it ("how often@@##",
          "knee pain 😢😢", "pain!!!!!!!!!!", "h o w  o f t e n"). The answer must stay the same.

evaluate_chat_noise.py runs them; tests/test_chat_noise.py guards a sample.
"""
import random
import string

KEY_ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
EMOJI = ["😀", "😂", "🙏", "👍", "❤️", "🔥", "😅", "🤔", "💪", "😴", "🎉", "🙂", "👀", "✨", "🌧️", "🍜"]
SYMBOLS = "!@#$%^&*()_+-=[]{};:'\",.<>/?\\|`~"
OTHER_SCRIPTS = ["你好吗", "谢谢你", "今天天气很好", "நன்றி", "வணக்கம்", "مرحبا", "привет", "こんにちは", "안녕하세요",
                 "สวัสดี", "Γειά σου", "नमस्ते"]
WORDS = ["table", "blue", "running", "apple", "window", "seven", "river", "music", "paper", "garden", "laptop",
         "yellow", "cloud", "train", "bottle", "dance", "pencil", "orange", "mountain", "coffee", "kitten",
         "rocket", "piano", "sunday", "carpet", "silver", "banana", "ticket", "jungle", "violin"]
CODE = ["<script>alert(1)</script>", "'; DROP TABLE users; --", "SELECT * FROM account", "{\"a\": 1}",
        "console.log('hi')", "print('hello world')", "../../etc/passwd", "${jndi:ldap://x}", "<b>bold</b>",
        "rm -rf /", "1=1 OR 1=1", "<img src=x onerror=alert(1)>"]
LINKS = ["https://example.com", "www.google.com", "http://bit.ly/abc123", "someone@example.com", "+60 12-345 6789",
         "0123456789", "#hashtag", "@someone", "C:\\Users\\file.txt"]


def keyboard_mash(rng: random.Random) -> str:
    row = rng.choice(KEY_ROWS)
    start = rng.randrange(len(row) - 3)
    run = row[start:start + rng.randint(3, len(row) - start)]
    return "".join(rng.choice([c, c, c.upper()]) for c in run) * rng.randint(1, 2)


def random_letters(rng: random.Random) -> str:
    n = rng.choice([1, 1, 2, 3, 4, 5, 6, 8, 12, 20])
    return "".join(rng.choice(string.ascii_lowercase) for _ in range(n))


def random_words_of_letters(rng: random.Random) -> str:
    return " ".join(random_letters(rng) for _ in range(rng.randint(2, 6)))


def noise(rng: random.Random) -> tuple[str, str]:
    """(kind, text) with nothing to answer."""
    kind = rng.choice(["mash", "letters", "letter_words", "digits", "emoji", "punctuation", "symbols", "mixed",
                       "repeat", "link", "code", "long", "script", "word_salad", "whitespace", "alnum"])
    if kind == "mash":
        t = keyboard_mash(rng)
    elif kind == "letters":
        t = random_letters(rng)
    elif kind == "letter_words":
        t = random_words_of_letters(rng)
    elif kind == "digits":
        t = "".join(rng.choice(string.digits) for _ in range(rng.randint(1, 15)))
    elif kind == "emoji":
        t = "".join(rng.choice(EMOJI) for _ in range(rng.randint(1, 6)))
    elif kind == "punctuation":
        t = "".join(rng.choice("?!.,;:") for _ in range(rng.randint(1, 10)))
    elif kind == "symbols":
        t = "".join(rng.choice(SYMBOLS) for _ in range(rng.randint(1, 15)))
    elif kind == "mixed":
        t = "".join(rng.choice(string.ascii_letters + string.digits + SYMBOLS) for _ in range(rng.randint(3, 25)))
    elif kind == "repeat":
        t = rng.choice("abcxyzhm?!.") * rng.randint(3, 40)
    elif kind == "link":
        t = rng.choice(LINKS)
    elif kind == "code":
        t = rng.choice(CODE)
    elif kind == "long":
        t = " ".join(rng.choice(WORDS + [random_letters(rng)]) for _ in range(rng.randint(150, 600)))
    elif kind == "script":
        t = rng.choice(OTHER_SCRIPTS) * rng.randint(1, 2)
    elif kind == "word_salad":
        t = " ".join(rng.sample(WORDS, rng.randint(2, 6)))
    elif kind == "whitespace":
        t = rng.choice([" ", "   ", "\n", "\t", " \n \t "])
    else:
        t = "".join(rng.choice(string.ascii_lowercase + string.digits) for _ in range(rng.randint(4, 12)))
    return kind, t


def add_noise(question: str, rng: random.Random) -> tuple[str, str]:
    """(how, text): the question with random characters around or inside it."""
    how = rng.choice(["symbols_after", "symbols_before", "emoji_after", "emoji_before", "repeat_end",
                      "spaced_letters", "double_spaces", "newlines", "dots_between", "junk_word_after",
                      "caps_random", "zero_width"])
    q = question
    if how == "symbols_after":
        return how, q + "".join(rng.choice(SYMBOLS) for _ in range(rng.randint(1, 6)))
    if how == "symbols_before":
        return how, "".join(rng.choice(SYMBOLS) for _ in range(rng.randint(1, 4))) + " " + q
    if how == "emoji_after":
        return how, q + " " + "".join(rng.choice(EMOJI) for _ in range(rng.randint(1, 3)))
    if how == "emoji_before":
        return how, rng.choice(EMOJI) + " " + q
    if how == "repeat_end":
        return how, q + rng.choice("?!.") * rng.randint(3, 12)
    if how == "spaced_letters" and len(q) <= 14:
        return how, " ".join(q.replace(" ", "  "))
    if how == "double_spaces":
        return how, "  ".join(q.split())
    if how == "newlines":
        return how, q.replace(" ", "\n", 1)
    if how == "dots_between":
        return how, "...".join(q.split())
    if how == "junk_word_after":
        return how, q + " " + random_letters(rng)
    if how == "caps_random":
        return how, "".join(c.upper() if rng.random() < 0.3 else c for c in q)
    return "zero_width", q.replace(" ", " \u200b", 1)
