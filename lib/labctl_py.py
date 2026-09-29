#!/usr/bin/env python3
"""Progress tracking and flashcard quizzes for labctl (stdlib only).

Progress lives in .labctl/progress.json (git-ignored), e.g.:
  {"labs": {"t1-02": {"started": "...", "verified": "...", "breakfix_fixed": "..."}},
   "quiz": {"02-kubernetes-core": {"<card id>": {"right": 2, "wrong": 1}}}}
"""
import hashlib
import json
import os
import random
import re
import sys
import textwrap
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, ".labctl", "progress.json")
QUIZ_DIR = os.path.join(ROOT, "quizzes")


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"labs": {}, "quiz": {}}


def save(data):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, STATE)  # atomic: a crash never leaves half a file


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def cmd_mark(lab, event):
    data = load()
    data.setdefault("labs", {}).setdefault(lab, {})[event] = now()
    save(data)


def cmd_status(lab):
    """Print a one-word status for `labctl list`."""
    ev = load().get("labs", {}).get(lab, {})
    if "verified" in ev and "breakfix_fixed" in ev:
        print("done")
    elif "verified" in ev:
        print("verified")
    elif "started" in ev:
        print("started")
    else:
        print("-")


def cmd_show(labs_tsv):
    """labs_tsv: lines of 'id<TAB>title' supplied by labctl."""
    data = load()
    labs = [line.split("\t", 1) for line in labs_tsv.strip().splitlines() if line]
    done = 0
    print(f"{'LAB':<7} {'TITLE':<44} {'STARTED':<8} {'VERIFIED':<9} BREAK/FIX")
    for lab_id, title in labs:
        ev = data.get("labs", {}).get(lab_id, {})
        s = "yes" if "started" in ev else "-"
        v = ev.get("verified", "-")[:10]
        b = ev.get("breakfix_fixed", "-")[:10]
        done += "verified" in ev and "breakfix_fixed" in ev
        print(f"{lab_id:<7} {title[:44]:<44} {s:<8} {v:<9} {b}")
    print(f"\n{done}/{len(labs)} labs fully complete (verified + break/fix).")
    quiz = data.get("quiz", {})
    if quiz:
        print("\nQuiz scores (cards answered right at least once / seen):")
        for mod, cards in sorted(quiz.items()):
            right = sum(1 for c in cards.values() if c.get("right", 0) > 0)
            print(f"  {mod:<32} {right}/{len(cards)}")


# ---------------- quizzes ----------------
CARD_RE = re.compile(r"^### Q:\s*", re.M)


def parse_quiz(path):
    """Cards are '### Q: question' ... '**A:** answer' blocks in Markdown."""
    with open(path) as f:
        text = f.read()
    cards = []
    for chunk in CARD_RE.split(text)[1:]:
        if "**A:**" not in chunk:
            continue
        q, a = chunk.split("**A:**", 1)
        q, a = q.strip(), a.strip()
        cid = hashlib.sha1(q.encode()).hexdigest()[:10]
        cards.append({"id": cid, "q": q, "a": a})
    return cards


def quiz_files():
    return sorted(f[:-3] for f in os.listdir(QUIZ_DIR) if f.endswith(".md") and f != "README.md")


def resolve_module(name):
    mods = quiz_files()
    matches = [m for m in mods if m == name or m.startswith(name)]
    if len(matches) != 1:
        print("Available quizzes:\n  " + "\n  ".join(mods))
        if name:
            print(f"\n'{name}' matched {len(matches)} quizzes; be more specific.")
        sys.exit(1)
    return matches[0]


def wrap(s):
    return "\n".join(textwrap.fill(p, 88) if not p.startswith(("    ", "```", "|", "-")) else p
                     for p in s.splitlines())


def cmd_quiz(name, missed_only=False):
    mod = resolve_module(name)
    cards = parse_quiz(os.path.join(QUIZ_DIR, mod + ".md"))
    data = load()
    scores = data.setdefault("quiz", {}).setdefault(mod, {})
    if missed_only:
        cards = [c for c in cards if scores.get(c["id"], {}).get("wrong", 0) >
                 scores.get(c["id"], {}).get("right", 0)]
        if not cards:
            print("No missed cards - nice. Run without --missed for the full deck.")
            return
    random.shuffle(cards)
    print(f"Quiz: {mod} ({len(cards)} cards). Think of your answer, press Enter to reveal,")
    print("then grade yourself: y = got it, n = missed it, q = quit.\n")
    right = seen = 0
    for i, c in enumerate(cards, 1):
        print(f"--- Card {i}/{len(cards)} ---")
        print(wrap(c["q"]))
        try:
            input("\n[Enter to reveal] ")
        except EOFError:
            break
        print("\n" + wrap(c["a"]) + "\n")
        try:
            g = input("Did you get it? [y/n/q] ").strip().lower()
        except EOFError:
            break
        if g == "q":
            break
        s = scores.setdefault(c["id"], {"right": 0, "wrong": 0})
        if g == "y":
            s["right"] += 1
            right += 1
        else:
            s["wrong"] += 1
        seen += 1
        save(data)
        print()
    if seen:
        print(f"Score this round: {right}/{seen}. Review misses with: ./labctl quiz {mod} --missed")


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd, args = argv[0], argv[1:]
    if cmd == "mark":
        cmd_mark(args[0], args[1])
    elif cmd == "status":
        cmd_status(args[0])
    elif cmd == "show":
        cmd_show(sys.stdin.read())
    elif cmd == "quiz":
        missed = "--missed" in args
        rest = [a for a in args if a != "--missed"]
        cmd_quiz(rest[0] if rest else "", missed)
    elif cmd == "quiz-count":
        for m in quiz_files():
            print(f"{m}\t{len(parse_quiz(os.path.join(QUIZ_DIR, m + '.md')))}")
    else:
        print(f"unknown command {cmd}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
