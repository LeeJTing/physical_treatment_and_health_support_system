"""Writes common_words.txt: the 20 000 most common English words and the 15 000 most common Malay words
(wordfreq 3.1, open data). The chatbot never "corrects" a real word ("acting" is not a slip of
"aching"; "price" not of "pain"); only unknown words are respelled (engine.respell, 3.55).

    .venv\Scripts\python -m pip install wordfreq      (only to rebuild the list)
    .venv\Scripts\python app\chat\build_wordlist.py
"""
from pathlib import Path

from wordfreq import top_n_list

OUT = Path(__file__).with_name("common_words.txt")


def main():
    words = sorted({w for w in top_n_list("en", 20_000) + top_n_list("ms", 15_000)
                    if w.isalpha() and w.isascii()})
    OUT.write_text("\n".join(words) + "\n", encoding="utf-8")
    print(f"{len(words)} words -> {OUT}")


if __name__ == "__main__":
    main()
