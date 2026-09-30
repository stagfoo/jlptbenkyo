#!/usr/bin/env python3
"""Builds assets/content.db from open Japanese-language data.

Run:  python3 tool/build_content.py

Everything the app knows is assembled here and shipped as one SQLite file.
The app itself never touches a network — it queries this database in
place, a card at a time, which is also why the content is a database and
not a bundle of JSON: ~3,500 words, ~610 kanji and ~26,000 sentence pairs
held as Dart maps would cost tens of megabytes of heap to answer a
question about one word.

Sources, all redistributable, all credited in the README:

  open-anki-jlpt-decks  MIT       which words belong to which JLPT level
  kanji-data            MIT       kanji levels, strokes, readings, meanings
  jmdict-examples-eng   CC BY-SA  dictionary entries with Tatoeba sentences
  KanjiVG               CC BY-SA  stroke-by-stroke paths, for writing practice
  grammar_n3.json       -         the grammar points, authored in this repo

Downloads are cached in tool/.cache/ so a rebuild is cheap. Delete that
directory to force a refresh.
"""

import csv
import gzip
import io
import json
import os
import re
import sqlite3
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CACHE = os.path.join(HERE, ".cache")
OUT = os.path.join(ROOT, "assets", "content.db")

VOCAB_URL = ("https://raw.githubusercontent.com/jamsinclair/"
             "open-anki-jlpt-decks/main/src/{level}.csv")
KANJI_URL = ("https://raw.githubusercontent.com/davidluzgouveia/"
             "kanji-data/master/kanji-jouyou.json")
JMDICT_RELEASE = ("https://api.github.com/repos/scriptin/"
                  "jmdict-simplified/releases/latest")
KANJIVG_RELEASE = "https://api.github.com/repos/KanjiVG/kanjivg/releases/latest"

# N5 through N3. The levels count down, so "at or above N3" is >= 3.
LEVELS = (5, 4, 3)


def log(msg):
    print(msg, flush=True)


def fetch(url, name, binary=True):
    """Downloads to the cache, or returns what is already there."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        log(f"  downloading {name}")
        req = urllib.request.Request(
            url, headers={"User-Agent": "jlptbenkyo-build"})
        with urllib.request.urlopen(req, timeout=300) as r, \
                open(path, "wb") as f:
            f.write(r.read())
    with open(path, "rb" if binary else "r") as f:
        return f.read()


def release_asset(api_url, name_contains, cache_name):
    """Finds an asset on a GitHub release by substring and downloads it.

    By substring rather than exact name because these releases carry a
    build timestamp in every filename, so the exact name changes daily
    and a hardcoded one would rot within a week.
    """
    meta = json.loads(fetch(api_url, cache_name + ".release.json"))
    for asset in meta["assets"]:
        if name_contains in asset["name"] and asset["name"].endswith(".zip"):
            return fetch(asset["browser_download_url"],
                         cache_name + ".zip"), meta["tag_name"]
    raise SystemExit(f"no asset matching {name_contains!r} on {api_url}")


# ------------------------------------------------------------------ vocab

def clean_expression(raw):
    """Turns a list entry into the forms it actually stands for.

    The lists use a few notations that are not part of the word: a tilde
    marks where something attaches (`~円`), and a semicolon separates
    spellings that are the same word (`いい; よい`). Left alone, both fail
    to match anything in the dictionary, which is most of the 3% that
    otherwise arrives with no reading, no part of speech and no example
    sentence.
    """
    parts = [p.strip() for p in re.split(r"[;；]", raw)]
    out = []
    for p in parts:
        p = p.replace("～", "").replace("〜", "").replace("~", "").strip()
        if p:
            out.append(p)
    return out


def load_vocab():
    rows = []
    seen = set()
    for level in LEVELS:
        data = fetch(VOCAB_URL.format(level=f"n{level}"),
                     f"vocab-n{level}.csv").decode("utf-8")
        for r in csv.DictReader(io.StringIO(data)):
            expr = r["expression"].strip()
            if not expr:
                continue
            key = (expr, r["reading"].strip())
            # A word listed at more than one level keeps the easiest one:
            # it is introduced there, and re-introducing it later would
            # put the same card in the deck twice.
            if key in seen:
                continue
            seen.add(key)
            rows.append({
                "expression": expr,
                "forms": clean_expression(expr),
                "reading": r["reading"].strip(),
                "meaning": r["meaning"].strip(),
                "level": level,
            })
    return rows


# ------------------------------------------------------------------ kanji

def load_kanji():
    data = json.loads(fetch(KANJI_URL, "kanji-jouyou.json"))
    out = []
    for literal, k in data.items():
        # `jlpt_new` is the post-2010 five-level scale. Kanjidic's own
        # `jlpt` field is the *old* four-level one and disagrees — 語 is
        # N5 on the new scale and 4 on the old, which would quietly put
        # beginner kanji in the wrong deck.
        level = k.get("jlpt_new")
        if level not in LEVELS:
            continue
        out.append({
            "literal": literal,
            "level": level,
            "strokes": k.get("strokes"),
            "grade": k.get("grade"),
            "freq": k.get("freq"),
            "meanings": k.get("meanings") or [],
            "on": k.get("readings_on") or [],
            "kun": k.get("readings_kun") or [],
        })
    return out


# ---------------------------------------------------------------- kanjivg

def load_stroke_paths(wanted):
    """Stroke-order paths per kanji, in drawing order.

    KanjiVG nests strokes inside groups describing radicals and
    components. The nesting is not needed here — what a writing exercise
    wants is the flat sequence of strokes in the order a person draws
    them, which is exactly document order for the `path` elements.
    """
    blob, tag = release_asset(KANJIVG_RELEASE, "-main", "kanjivg")
    log(f"  kanjivg {tag}")
    paths = {}
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        for info in z.infolist():
            name = os.path.basename(info.filename)
            if not name.endswith(".svg") or "-" in name:
                # Variant files (`08a9e-Kaisho.svg`) describe alternate
                # calligraphic styles of a character already covered.
                continue
            try:
                codepoint = int(name[:-4], 16)
            except ValueError:
                continue
            literal = chr(codepoint)
            if literal not in wanted:
                continue
            root = ET.fromstring(z.read(info))
            d = [p.get("d") for p in root.iter()
                 if p.tag.endswith("path") and p.get("d")]
            if d:
                paths[literal] = d
    return paths


# -------------------------------------------------------- jmdict + tatoeba

def load_jmdict():
    blob, tag = release_asset(JMDICT_RELEASE, "jmdict-examples-eng",
                              "jmdict-examples")
    log(f"  jmdict {tag}")
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        name = z.namelist()[0]
        return json.loads(z.read(name)), tag


def index_jmdict(jm):
    """Every surface form to the entries that use it."""
    by_form = {}
    for w in jm["words"]:
        forms = ([k["text"] for k in w["kanji"]]
                 + [k["text"] for k in w["kana"]])
        for f in forms:
            by_form.setdefault(f, []).append(w)
    return by_form


def harvest_sentences(jm):
    """Unique Japanese/English pairs, and which words each was filed under.

    A sentence appears once per dictionary entry that cites it, so the
    same sentence arrives many times over. Keying by the Japanese text
    collapses that, and keeps the set small enough to ship.
    """
    pairs = {}
    cites = {}
    for w in jm["words"]:
        for s in w["sense"]:
            for ex in s.get("examples", []):
                jp = en = None
                for sent in ex.get("sentences", []):
                    if sent["lang"] == "jpn":
                        jp = sent["text"]
                    elif sent["lang"] == "eng":
                        en = sent["text"]
                if jp and en:
                    pairs.setdefault(jp, en)
                    cites.setdefault(jp, set()).add(w["id"])
    return pairs, cites


# -------------------------------------------------------------- checking

# Scripts that have no business being in this data. Authoring these files
# by hand has twice produced a stray Cyrillic or Latin-Extended fragment
# inside a Japanese sentence — invisible at a glance, and it reaches a
# tablet as a sentence that cannot be read or spoken. Latin letters are
# allowed because real Japanese uses them (Mサイズ, QRコード); these
# ranges never appear in it.
FOREIGN = re.compile(
    r"[\u0400-\u04ff\u0370-\u03ff\u0590-\u05ff\u0600-\u06ff"
    r"\u0100-\u024f\u1e00-\u1eff]"
)

# A vocabulary key has to be pure Japanese: it is matched against the word
# table, and anything else can never join.
JAPANESE_ONLY = re.compile(r"^[\u3040-\u30ff\u4e00-\u9fff\u3005\u30fc]+$")


def check_authored(records, label, japanese_fields, vocab_field=None):
    """Fails the build on contaminated authored data.

    Loudly, and before anything is written: a sentence with a Cyrillic
    fragment in it looks fine in a diff and is unreadable on the device.
    """
    problems = []
    for r in records:
        for field in japanese_fields:
            value = r.get(field)
            for text in ([value] if isinstance(value, str) else (value or [])):
                if isinstance(text, dict):
                    text = text.get("jp", "")
                if text and FOREIGN.search(text):
                    problems.append(f"{r.get('id')}.{field}: {text!r}")
        for v in (r.get(vocab_field) or []) if vocab_field else []:
            if not JAPANESE_ONLY.match(v):
                problems.append(f"{r.get('id')}.{vocab_field}: {v!r}")
    if problems:
        raise SystemExit(
            f"!! {label} contains characters that cannot be Japanese:\n  "
            + "\n  ".join(problems)
        )


# ---------------------------------------------------------------- grammar

def load_grammar():
    path = os.path.join(HERE, "grammar.json")
    if not os.path.exists(path):
        log("  !! tool/grammar.json missing — grammar tables will be empty")
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_challenges():
    path = os.path.join(HERE, "challenges.json")
    if not os.path.exists(path):
        log("  !! tool/challenges.json missing — no daily challenges")
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def mine_grammar_examples(points, pairs, limit=6):
    """Finds real sentences that actually use each pattern.

    Attested examples rather than invented ones: every sentence here was
    written by a person and translated by a person, so a grammar point
    is shown doing its job in a sentence that someone meant. Patterns the
    corpus does not cover fall back to the examples authored alongside
    the point, and the build reports how many needed to.
    """
    found = {}
    for p in points:
        hits = []
        for probe in p.get("match", [p["pattern"]]):
            for jp, en in pairs.items():
                if probe in jp:
                    hits.append(jp)
                    if len(hits) >= limit * 3:
                        break
            if len(hits) >= limit * 3:
                break
        # Shortest first: a grammar example wants to show one thing, and
        # a 40-character sentence with three other unknown structures in
        # it does not.
        hits.sort(key=len)
        found[p["id"]] = hits[:limit]
    return found


# ----------------------------------------------------------------- schema

SCHEMA = """
PRAGMA journal_mode = OFF;

CREATE TABLE word (
  id         INTEGER PRIMARY KEY,
  expression TEXT NOT NULL,
  reading    TEXT NOT NULL,
  meaning    TEXT NOT NULL,
  level      INTEGER NOT NULL,
  pos        TEXT,
  common     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX word_level ON word(level);
CREATE INDEX word_expression ON word(expression);

CREATE TABLE kanji (
  id        INTEGER PRIMARY KEY,
  literal   TEXT NOT NULL UNIQUE,
  level     INTEGER NOT NULL,
  strokes   INTEGER,
  grade     INTEGER,
  freq      INTEGER,
  meanings  TEXT NOT NULL,
  on_yomi   TEXT NOT NULL,
  kun_yomi  TEXT NOT NULL,
  strokes_svg TEXT
);
CREATE INDEX kanji_level ON kanji(level);

CREATE TABLE grammar (
  id        INTEGER PRIMARY KEY,
  -- The authored id from grammar.json. Stable across rebuilds, which the
  -- integer id is not, so anything referring to a grammar point by name
  -- keeps working when a point is inserted in the middle.
  slug      TEXT NOT NULL UNIQUE,
  pattern   TEXT NOT NULL,
  level     INTEGER NOT NULL,
  category  TEXT,
  meaning   TEXT NOT NULL,
  formation TEXT,
  note      TEXT
);
CREATE INDEX grammar_level ON grammar(level);

CREATE TABLE sentence (
  id      INTEGER PRIMARY KEY,
  jp      TEXT NOT NULL,
  en      TEXT NOT NULL,
  chars   INTEGER NOT NULL,
  -- The hardest JLPT level any of its kanji belongs to, or 0 when every
  -- kanji in it is beyond N3. This is what grades reading practice:
  -- a sentence is only as easy as its hardest character.
  level   INTEGER NOT NULL
);
CREATE INDEX sentence_level ON sentence(level, chars);

CREATE TABLE word_sentence (
  word_id     INTEGER NOT NULL,
  sentence_id INTEGER NOT NULL
);
CREATE INDEX word_sentence_word ON word_sentence(word_id);

CREATE TABLE grammar_sentence (
  grammar_id  INTEGER NOT NULL,
  sentence_id INTEGER NOT NULL
);
CREATE INDEX grammar_sentence_grammar ON grammar_sentence(grammar_id);

CREATE TABLE kanji_word (
  kanji_id INTEGER NOT NULL,
  word_id  INTEGER NOT NULL
);
CREATE INDEX kanji_word_kanji ON kanji_word(kanji_id);

-- Daily challenges: a real-world task to attempt out loud.
CREATE TABLE challenge (
  id       TEXT PRIMARY KEY,
  ord      INTEGER NOT NULL,
  level    INTEGER NOT NULL,
  category TEXT,
  title    TEXT NOT NULL,
  setting  TEXT,
  goal     TEXT NOT NULL,
  steps    TEXT NOT NULL,
  stretch  TEXT
);
CREATE INDEX challenge_level ON challenge(level);

CREATE TABLE challenge_phrase (
  challenge_id TEXT NOT NULL,
  ord          INTEGER NOT NULL,
  jp           TEXT NOT NULL,
  en           TEXT NOT NULL
);
CREATE INDEX challenge_phrase_c ON challenge_phrase(challenge_id, ord);

-- Resolved to real word rows at build time. This is what lets the app say
-- how much of a challenge is made of words already in the deck.
CREATE TABLE challenge_word (
  challenge_id TEXT NOT NULL,
  word_id      INTEGER NOT NULL
);
CREATE INDEX challenge_word_c ON challenge_word(challenge_id);

CREATE TABLE challenge_grammar (
  challenge_id TEXT NOT NULL,
  grammar_id   INTEGER NOT NULL
);
CREATE INDEX challenge_grammar_c ON challenge_grammar(challenge_id);

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""


def main():
    log("==> sources")
    vocab = load_vocab()
    log(f"  vocab      {len(vocab)} rows")
    kanji = load_kanji()
    log(f"  kanji      {len(kanji)} characters")
    jm, jmdict_tag = load_jmdict()
    by_form = index_jmdict(jm)
    pairs, cites = harvest_sentences(jm)
    log(f"  sentences  {len(pairs)} unique pairs")
    stroke_paths = load_stroke_paths({k["literal"] for k in kanji})
    log(f"  strokes    {len(stroke_paths)} of {len(kanji)} kanji")
    grammar = load_grammar()
    check_authored(grammar, "tool/grammar.json",
                   ["pattern", "formation", "note", "examples"])
    log(f"  grammar    {len(grammar)} points")
    challenges = load_challenges()
    check_authored(challenges, "tool/challenges.json",
                   ["phrases", "stretch"], vocab_field="vocab")
    log(f"  challenges {len(challenges)} scenarios")

    log("==> enriching vocabulary from the dictionary")
    jm_id_to_word = {}
    matched = 0
    for i, v in enumerate(vocab, start=1):
        v["id"] = i
        entries = []
        for form in v["forms"]:
            entries.extend(by_form.get(form, []))
        if not entries:
            entries = by_form.get(v["reading"], [])
        if entries:
            matched += 1
            best = entries[0]
            v["pos"] = ",".join(sorted({p for s in best["sense"]
                                        for p in s["partOfSpeech"]}))
            v["common"] = int(any(k.get("common")
                                  for k in best["kanji"] + best["kana"]))
            for e in entries:
                jm_id_to_word.setdefault(e["id"], []).append(i)
        else:
            v["pos"] = None
            v["common"] = 0
    log(f"  matched    {matched}/{len(vocab)} ({matched / len(vocab):.1%})")

    kanji_levels = {k["literal"]: k["level"] for k in kanji}

    def sentence_level(jp):
        """The hardest level among the kanji in a sentence.

        Kana-only sentences count as N5: there is nothing in them to
        fail on. A sentence containing a kanji outside N5-N3 is marked 0
        and sorts to the end — it is not ungraded, it is above the grade.
        """
        seen = [kanji_levels.get(c) for c in jp
                if "一" <= c <= "鿿"]
        if not seen:
            return 5
        if any(s is None for s in seen):
            return 0
        return min(seen)

    log("==> writing the database")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript(SCHEMA)

    db.executemany(
        "INSERT INTO word (id,expression,reading,meaning,level,pos,common)"
        " VALUES (?,?,?,?,?,?,?)",
        [(v["id"], v["expression"], v["reading"], v["meaning"],
          v["level"], v["pos"], v["common"]) for v in vocab])

    kanji_ids = {}
    kanji_rows = []
    for i, k in enumerate(sorted(kanji, key=lambda x: (-x["level"],
                                                       x["freq"] or 9999)),
                          start=1):
        kanji_ids[k["literal"]] = i
        kanji_rows.append((
            i, k["literal"], k["level"], k["strokes"], k["grade"], k["freq"],
            json.dumps(k["meanings"], ensure_ascii=False),
            json.dumps(k["on"], ensure_ascii=False),
            json.dumps(k["kun"], ensure_ascii=False),
            json.dumps(stroke_paths.get(k["literal"]), ensure_ascii=False)
            if k["literal"] in stroke_paths else None,
        ))
    db.executemany(
        "INSERT INTO kanji (id,literal,level,strokes,grade,freq,meanings,"
        "on_yomi,kun_yomi,strokes_svg) VALUES (?,?,?,?,?,?,?,?,?,?)",
        kanji_rows)

    sentence_ids = {}
    sentence_rows = []
    for i, (jp, en) in enumerate(sorted(pairs.items()), start=1):
        sentence_ids[jp] = i
        sentence_rows.append((i, jp, en, len(jp), sentence_level(jp)))
    db.executemany(
        "INSERT INTO sentence (id,jp,en,chars,level) VALUES (?,?,?,?,?)",
        sentence_rows)

    links = []
    for jp, entry_ids in cites.items():
        sid = sentence_ids[jp]
        for eid in entry_ids:
            for wid in jm_id_to_word.get(eid, ()):
                links.append((wid, sid))
    db.executemany(
        "INSERT INTO word_sentence (word_id,sentence_id) VALUES (?,?)",
        sorted(set(links)))

    kw = []
    for v in vocab:
        for ch in v["expression"]:
            if ch in kanji_ids:
                kw.append((kanji_ids[ch], v["id"]))
    db.executemany(
        "INSERT INTO kanji_word (kanji_id,word_id) VALUES (?,?)",
        sorted(set(kw)))

    if grammar:
        mined = mine_grammar_examples(grammar, pairs)
        grows, gsent = [], []
        fallbacks = 0
        for i, g in enumerate(grammar, start=1):
            grows.append((i, g["id"], g["pattern"], g["level"],
                          g.get("category"), g["meaning"], g.get("formation"),
                          g.get("note")))
            hits = mined.get(g["id"], [])
            if not hits:
                fallbacks += 1
                # Authored examples are appended to the sentence table so
                # every screen reads sentences from one place, rather than
                # some coming from the corpus and some from a second
                # column nothing else knows about.
                for ex in g.get("examples", []):
                    sid = len(sentence_rows) + 1
                    sentence_rows.append(
                        (sid, ex["jp"], ex["en"], len(ex["jp"]),
                         sentence_level(ex["jp"])))
                    db.execute(
                        "INSERT INTO sentence (id,jp,en,chars,level)"
                        " VALUES (?,?,?,?,?)",
                        sentence_rows[-1])
                    gsent.append((i, sid))
            else:
                for jp in hits:
                    gsent.append((i, sentence_ids[jp]))
        db.executemany(
            "INSERT INTO grammar (id,slug,pattern,level,category,meaning,"
            "formation,note) VALUES (?,?,?,?,?,?,?,?)", grows)
        db.executemany(
            "INSERT INTO grammar_sentence (grammar_id,sentence_id)"
            " VALUES (?,?)", sorted(set(gsent)))
        log(f"  grammar    {len(grammar) - fallbacks}/{len(grammar)} points "
            f"have attested examples; {fallbacks} fall back to authored ones")

    if challenges:
        # Vocabulary is resolved to real word rows here rather than matched
        # by string in the app. That is what lets a challenge say how much
        # of itself is already in the deck — and doing it at build time
        # means a word that does not exist is reported now, to the person
        # who can fix it, instead of silently showing as "not learned".
        by_expression = {}
        for v in vocab:
            by_expression.setdefault(v["expression"], v["id"])
            for form in v["forms"]:
                by_expression.setdefault(form, v["id"])
        by_reading = {}
        for v in vocab:
            by_reading.setdefault(v["reading"], v["id"])

        def resolve_word(surface):
            """Finds the deck word a challenge means.

            Direct spelling first, then reading, then through the
            dictionary's own list of surface forms — which is what knows
            that 終わる and 終る are one word. The word lists pick one
            spelling and it is not always the one a person would write,
            so matching on the literal string alone drops real links.
            """
            wid = by_expression.get(surface) or by_reading.get(surface)
            if wid:
                return wid
            for entry in by_form.get(surface, ()):  # noqa: F821
                for candidate in jm_id_to_word.get(entry["id"], ()):
                    return candidate
            return None

        grammar_ids = {g["id"]: i for i, g in enumerate(grammar, start=1)}

        crows, prows, cwords, cgrammar = [], [], [], []
        unmatched_vocab, unknown_grammar = [], []

        for n, c in enumerate(challenges):
            crows.append((
                c["id"], n, c["level"], c.get("category"), c["title"],
                c.get("setting"), c["goal"],
                json.dumps(c.get("steps") or [], ensure_ascii=False),
                c.get("stretch"),
            ))
            for j, ph in enumerate(c["phrases"]):
                prows.append((c["id"], j, ph["jp"], ph["en"]))
            for word in c.get("vocab") or []:
                wid = resolve_word(word)
                if wid:
                    cwords.append((c["id"], wid))
                else:
                    unmatched_vocab.append(f"{c['id']}:{word}")
            for slug in c.get("grammar") or []:
                gid = grammar_ids.get(slug)
                if gid:
                    cgrammar.append((c["id"], gid))
                else:
                    unknown_grammar.append(f"{c['id']}:{slug}")

        db.executemany(
            "INSERT INTO challenge (id,ord,level,category,title,setting,"
            "goal,steps,stretch) VALUES (?,?,?,?,?,?,?,?,?)", crows)
        db.executemany(
            "INSERT INTO challenge_phrase (challenge_id,ord,jp,en)"
            " VALUES (?,?,?,?)", prows)
        db.executemany(
            "INSERT INTO challenge_word (challenge_id,word_id)"
            " VALUES (?,?)", sorted(set(cwords)))
        db.executemany(
            "INSERT INTO challenge_grammar (challenge_id,grammar_id)"
            " VALUES (?,?)", sorted(set(cgrammar)))

        total_vocab = len(cwords) + len(unmatched_vocab)
        log(f"  challenge vocab {len(cwords)}/{total_vocab} matched a word")
        if unmatched_vocab:
            log("    unmatched: " + ", ".join(unmatched_vocab[:10]))
        if unknown_grammar:
            # A typo in a grammar slug is silent otherwise: the challenge
            # just shows no grammar and nobody notices for months.
            raise SystemExit(
                "!! challenges reference grammar points that do not exist: "
                + ", ".join(unknown_grammar))

    db.executemany(
        "INSERT INTO meta (key,value) VALUES (?,?)",
        [("schema", "1"),
         ("jmdict", jmdict_tag),
         ("levels", ",".join(str(l) for l in LEVELS)),
         ("words", str(len(vocab))),
         ("kanji", str(len(kanji_rows))),
         ("sentences", str(len(sentence_rows))),
         ("grammar", str(len(grammar))),
         ("challenges", str(len(challenges)))])

    db.commit()
    db.execute("VACUUM")
    db.close()

    size = os.path.getsize(OUT) / 1e6
    log(f"==> {OUT}  {size:.1f} MB")
    if size > 60:
        log("  !! that is large for a bundled asset; consider trimming "
            "sentences")
    return 0


if __name__ == "__main__":
    sys.exit(main())
