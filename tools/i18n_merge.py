#!/usr/bin/env python3
"""Merge a patch CSV into i18n/game.csv.

Rows whose key already exists are REPLACED in place (so a reworded string keeps
its position next to its neighbours); new keys are appended in patch order.

Why a tool and not a hand edit: game.csv is 300+ rows of quoted CJK, and the one
failure mode that matters -- a key silently present twice, with the loser winning
depending on import order -- is invisible when you are scrolling. I18nTest
asserts there are no duplicate keys; this makes it impossible to create one.

  python tools/i18n_merge.py <patch.csv>
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "i18n", "game.csv")


def read(path):
    with io.open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: i18n_merge.py <patch.csv>")
    main_rows = read(MAIN)
    patch_rows = read(sys.argv[1])
    header, body = main_rows[0], main_rows[1:]
    if patch_rows and patch_rows[0][0] == "keys":
        patch_rows = patch_rows[1:]

    index = {r[0]: i for i, r in enumerate(body) if r}
    replaced, added = 0, 0
    for r in patch_rows:
        if not r or not r[0].strip():
            continue
        if len(r) != 3:
            sys.exit("patch row is not 3 columns: %r" % (r,))
        if r[0] in index:
            body[index[r[0]]] = r
            replaced += 1
        else:
            index[r[0]] = len(body)
            body.append(r)
            added += 1

    seen = set()
    for r in body:
        if r[0] in seen:
            sys.exit("duplicate key survived the merge: %s" % r[0])
        seen.add(r[0])

    # QUOTE_ALL matches the existing file: every cell is quoted, so a comma or a
    # 、 inside a translated sentence can never shift a column.
    with io.open(MAIN, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL, lineterminator="\n")
        w.writerow(header)
        w.writerows(body)
    print("merged: %d replaced, %d added, %d rows total" % (replaced, added, len(body)))


if __name__ == "__main__":
    main()
