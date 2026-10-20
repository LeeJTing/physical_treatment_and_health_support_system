"""How every chatbot answer is set out (3.68, Elwin 21 Oct: "make sure the responses are clear, neat and easy
to see: 1), 2), 3) line by line instead of everything combined together").

    The first sentence is the direct answer, on its own line.
    Each further point is numbered 1), 2), 3) on a line of its own.
    An answer of one or two short sentences stays as it is.

The app shows the text as written, line breaks included (chat_view.dart, Text). layout() is applied to the
rules' answers when rules.json is built (build_rules.py) and to the answers put together at reply time.
"""
import re

# A sentence ends at . ! ? followed by a space and a capital, a digit, a quote or a bracket - but not inside
# quotes ("how do I do the heel raise?", "...") and not after a short form ("e.g. Paracetamol").
_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9\"(])")
_SHORT_FORMS = ("e.g.", "i.e.", "Dr.", "No.", "vs.", "approx.", "St.")
SHORT_ANSWER = 220          # one or two sentences up to this many characters stay on one line


def sentences(text: str) -> list[str]:
    """The sentences of [text], never split inside double quotes or after a short form."""
    out, start = [], 0
    for m in _END.finditer(text):
        before = text[start:m.start()]
        if before.count('"') % 2 or before.rstrip().endswith(_SHORT_FORMS):
            continue
        out.append(text[start:m.start()].strip())
        start = m.end()
    out.append(text[start:].strip())
    return [s for s in out if s]


# Lines that speak to the person rather than make a point ("Choose an option below.", "Which describes your
# pain best?", "For example: ..."): on a line of their own, not numbered.
_PROMPT = re.compile(r"^(?:Tap |Choose |Pick |You can also (?:pick|tap|choose|try|ask)|For example|Which |What |Is |"
                     r"Are |Do |Does |Would )|\?$")


def layout(text: str) -> str:
    """[text] set out as a lead line and numbered points; text already on lines is left as written."""
    if not text or "\n" in text:
        return text
    if re.search(r"(?:^|\s)1[.)]\s", text) and re.search(r"\s2[.)]\s", text):
        # Already numbered in one paragraph ("Here is how to start: 1) ... 2) ...", "1. Heel Raise; 2. ..."):
        # each number starts a line, the numbers kept.
        lines = re.split(r"[;,]?\s+(?=\d{1,2}[.)]\s)", text)
        tail = sentences(lines[-1])
        if len(tail) > 1 and not re.match(r"\d", tail[-1]):
            lines[-1:] = [" ".join(tail[:-1]), tail[-1]]          # a closing sentence after the last point
        return "\n".join(s.strip() for s in lines if s.strip())
    parts = sentences(text)
    if len(parts) <= 2 and len(text) <= SHORT_ANSWER:
        return text
    lines, k = [parts[0]], 0
    numbered = sum(1 for p in parts[1:] if not _PROMPT.search(p)) >= 2
    for p in parts[1:]:
        if numbered and not _PROMPT.search(p):
            k += 1
            lines.append(f"{k}) {p}")
        else:
            lines.append(p)
    return "\n".join(lines)


def points(lead: str, items: list[str], tail: str = "") -> str:
    """A lead line, numbered items and an optional last line (hand-set answers)."""
    lines = [lead] + [f"{k}) {p}" for k, p in enumerate(items, 1)]
    return "\n".join(lines + ([tail] if tail else []))
