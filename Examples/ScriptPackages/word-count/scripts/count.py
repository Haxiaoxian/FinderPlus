"""Prints a per-file breakdown and a one-line total (shown as the FinderPlus notification)."""
import re
import sys

CJK = re.compile(r"[぀-ヿ㐀-䶿一-鿿가-힯]")
WORD = re.compile(r"[A-Za-z0-9_'\-]+")

totals = [0, 0, 0]
for path in sys.argv[1:]:
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    characters = len(text)
    words = len(CJK.findall(text)) + len(WORD.findall(CJK.sub(" ", text)))
    lines = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
    totals = [totals[0] + characters, totals[1] + words, totals[2] + lines]
    print(f"{path}: {characters} chars, {words} words, {lines} lines")

print(f"{len(sys.argv) - 1} file(s): {totals[0]} chars · {totals[1]} words · {totals[2]} lines")
