# JLPT Benkyo

Everything needed to study for JLPT N3, on an Android device, offline.

Vocabulary, kanji and grammar in one spaced-repetition queue; reading,
listening, speaking and writing practice over the same corpus; a daily
real-world challenge chosen to fit what you're currently learning; a
daily reminder. **The app never talks to a network.** All of it — 3,526
words, 612 kanji, 145 grammar points, 52 challenge scenarios and 26,269
example sentences — ships inside the APK as a 4.9 MB SQLite file.

Covers **N5 through N3 cumulatively**, not just the N3-specific delta.
The scheduler surfaces earlier material you have forgotten rather than
assuming it is solid, and the level can be narrowed to N4–N3 or N3-only
in settings without losing progress on what it hides.

Named `jlptbenkyo` rather than `n3benkyo` on purpose: the applicationId
*is* the app's identity to Android and to Obtainium, so renaming it later
means removing the Obtainium entry and losing app storage. The content
pipeline already handles every level, and the N2/N1 word lists sit in the
same source.

## What it does

| | |
| --- | --- |
| **Review** | One SRS queue mixing words, kanji and grammar |
| **Reading** | Graded sentences, translation hidden until asked for |
| **Listening** | Device Japanese TTS, with a speed control |
| **Speaking** | Record an attempt, play it against the reference |
| **Writing** | Trace kanji stroke by stroke, in the right order |
| **Grammar** | 145 points with real attested examples |
| **Daily challenge** | A real-world task to attempt out loud, chosen to fit your deck |

## The content

Assembled by `tool/build_content.py` from open data and shipped as
`assets/content.db`. Nothing is fetched at runtime.

| Source | Licence | Gives |
| --- | --- | --- |
| [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks) | MIT | which words belong to which JLPT level |
| [kanji-data](https://github.com/davidluzgouveia/kanji-data) | MIT | kanji levels, strokes, readings, meanings |
| [jmdict-simplified](https://github.com/scriptin/jmdict-simplified) | CC BY-SA 4.0 | dictionary entries and Tatoeba example sentences |
| [KanjiVG](https://github.com/KanjiVG/kanjivg) | CC BY-SA 3.0 | stroke-by-stroke paths |
| `tool/grammar.json` | — | the grammar points, authored in this repo |
| `tool/challenges.json` | — | the daily challenge scenarios, authored in this repo |

JMdict is © the Electronic Dictionary Research and Development Group;
KanjiVG is © Ulrich Apel. Both are share-alike, and the derived database
carries that.

The build **fails loudly on contaminated authored data**. Writing
`grammar.json` and `challenges.json` by hand twice produced a stray
Cyrillic or Latin-Extended fragment inside a Japanese sentence — invisible
in a diff, and it reaches the device as a line that cannot be read or
spoken. `check_authored` rejects those script ranges outright, and holds
vocabulary keys to Japanese-only, since anything else can never join
against the word table.

**The JLPT has published no official word or kanji list since 2010.**
Every "N3 vocabulary list" in existence is a community reconstruction,
including this one. It is close, not authoritative.

### Why the levels come from two different places

Kanjidic carries a `jlpt` field and it is the **old four-level scale**.
語 is N5 on the current scale and 4 on the old one, so using it would
quietly file beginner kanji in the wrong deck. `kanji-data`'s `jlpt_new`
is the post-2010 five-level scale, and that is what this uses.

### Matching the word lists to the dictionary

The lists use notations that are not part of the word — a tilde marking
where something attaches (`~円`), a semicolon separating spellings of one
word (`いい; よい`). Stripping those lifts the dictionary match rate from
97.3% to **99.5%**, and that is most of the difference between a card
with a reading, a part of speech and an example sentence and a card with
only a gloss.

**97% of words have at least one example sentence** and 609 of 612 kanji
appear in at least one word, so a card can nearly always show the thing
in use rather than in isolation.

### Grading sentences

A sentence is only as easy as its hardest character, so each is tagged
with the JLPT level of the hardest kanji in it. A sentence containing a
character beyond N3 is marked `0` — **above** the grade, not ungraded —
and is excluded from practice by default. Around 9,000 of the 26,269 sit
inside N5–N3.

### Grammar examples are mined, not invented

Each point carries `match` probes, and the build searches the corpus for
sentences that actually use the pattern, shortest first. All 145 points
found real examples; none fell back to the authored ones. Every example
was therefore written by a person and translated by a person, which is
why they read like Japanese rather than like grammar exercises.

Shortest first because an example is there to show one thing — a
forty-character sentence with three other unknown structures in it
demonstrates nothing about the pattern you are looking at.

## Daily challenges

Order a coffee. Give someone directions. Explain what you can't eat. Turn
down an invitation without a fight. 52 scenarios across 13 categories,
graded N5 to N3, each with a concrete goal, the steps to hit, real
phrases, and a harder version for when the plain one stops being work.

This exists because of the gap every SRS has: you can answer four
thousand cards correctly and still freeze at a café counter. Recognising
a word on a card and producing it under time pressure in front of a
stranger are different skills, and a flashcard only trains one of them.

**The day's challenge is chosen to fit your deck.** Each scenario's
vocabulary is resolved to real word rows at build time (200 of 201
links), so the app can score how much of a scenario is made of words you
are *currently part-way through* — not words you don't know yet, and not
words you mastered two months ago. A scenario where you know everything
is no longer practice; one where you know nothing is a vocabulary list,
not a task. What earns a challenge its place is the middle.

The pick is deterministic per day and ranked by that fit, then chosen by
the date from the top eight. Ranking alone would hand you the same
scenario every day until your deck moved; picking at random would ignore
the deck entirely. Anything done in the last fortnight is held back.

**"Work these in"** is the direct answer to practising what you're
learning: five words currently in motion, the scenario's own first, then
filled from the rest of the deck hardest-first — a word you have lapsed
on repeatedly is the one worth forcing into a sentence today.

The phrases are folded away by default. A safety net you are already
standing on is a floor, and having to open it is the difference between
recalling and reading. Nothing checks whether you actually said it out
loud, and the screen says so.

## The scheduler

`lib/srs.dart` — SM-2 with learning steps. Plain Dart with no clock of
its own: the time is always passed in, so a card's whole life (learned,
forgotten, relearned, eventually a leech) is tested in a millisecond
instead of eight months.

FSRS is a better algorithm and is deliberately not used: it earns that by
fitting parameters to a review history that does not exist on a fresh
install, and a worse algorithm you can reason about beats a better one
you cannot debug on a tablet.

Two things the tests caught immediately:

- **Grades collapsed at short intervals.** A one-day card graded *good*
  gives 1 × 2.5 → 3 days, and graded *easy* gives 1 × 2.65 × 1.3 → 3 days
  as well — so the button meaning "this was trivial" changed nothing.
  Each grade now lands at least a day beyond the one below it. At longer
  intervals the multipliers separate them and these floors never bind.
- **Graduating out of a lapse threw away the halved interval.** A lapse
  halves the interval rather than erasing it, deliberately — a word known
  for four months that you just blanked on is not as new as one you met
  this morning. Graduating flat to the beginner's interval silently undid
  that.

Intervals are capped at two years (ten years of not seeing a word is
indistinguishable from never seeing it), ease has a floor of 1.3 (below
that a card is in front of you every other day forever), and a card
failed eight times is flagged as a leech rather than left to keep
surfacing.

### The level filter ran backwards

Worth recording because it was invisible and shipped in the first commit.
The JLPT numbers run backwards to the names — N5 is the *easiest* level
and the *highest* number — and the deck-scope query used `level >= x`.
So the setting labelled "N5–N3" returned 718 words (N5 only) instead of
3,526, and "N3 only" returned everything. The default was the inverted
one, so the app studied the opposite of what it said.

The scope filter is now `level <= easiestLevel`, and the parameter is
named for what it means rather than for the comparison. The sentence
grader keeps `>=` because there it really is a difficulty ceiling —
the same numbers, the opposite question. A test pins both directions.

## Keeping a deck usable

The two settings that decide whether this survives week three:

- **New cards per day.** Every new card becomes roughly ten reviews
  spread over the following months. The deck is ~4,200 items; a day that
  introduces two hundred produces two hundred reviews a day for a
  fortnight.
- **A review ceiling**, so a fortnight away does not return six hundred
  cards at once. Nothing is lost — the most overdue come first and the
  rest follow, and the home screen says how many are waiting rather than
  hiding them.

New cards are **interleaved** through the queue, not front-loaded or
appended. All of them first means reviews get answered while tired; all
of them last means they are never reached on a day that runs short.
Spacing them is the only arrangement where stopping early costs
proportionally. Falling behind on reviews also throttles new cards
automatically, rather than needing you to notice and turn it down.

Both are **continuous sliders**. The right number is found by living with
it for a week and nudging, and a stepped control always stops just past
the value you were heading for.

## Writing practice

KanjiVG gives strokes in the order a person actually writes them, which
is the whole value — stroke order is what makes handwriting legible and
what a lookup by hand depends on. The next stroke is the only one you can
draw, and a green dot marks where it starts, because stroke order is
mostly a question of which end you begin from.

The comparison is deliberately loose: the stroke must start near the
right place, end near the right place, and stay near the model line in
between. Anything stricter turns a stroke-order exercise into a
handwriting exam.

`flattenKanjiPath` handles `M`, `L`, `C`, `S` and their relative forms —
everything KanjiVG uses — and **any letter counts as a command**, not
just the handled ones. Matching only known commands let an unsupported
one fall through as if absent, and its numbers were then eaten by
whichever command was still active, producing a model stroke built from
misread coordinates that every attempt would fail against for no visible
reason.

## Speaking

Nothing here scores pronunciation, and the app says so on the screen. No
honest scoring is available on a device, and a number that claimed to
would be worse than none. It records the attempt, plays the TTS
reference, and lets you judge the gap — which is what self-assessment
actually is.

## Reminders

Local notifications, not push: there is no server, and a study reminder
depends on what is due on *this* device. Scheduled **inexactly** on
purpose — an exact alarm needs a special permission on Android 14+, is
refused by default, and buys nothing for a reminder that is no worse for
arriving a few minutes late.

The device's own timezone is resolved from its current offset. Without
that everything schedules in UTC, and "remind me at eight" arrives in the
middle of the night — silently wrong rather than visibly broken.

## Layout

The parts worth being sure about are plain Dart with no Flutter or plugin
imports, so they test with no device attached.

| File | Does |
| --- | --- |
| `lib/srs.dart` | The scheduler: intervals, ease, lapses, leeches |
| `lib/session.dart` | Queue building, rationing, interleaving, progress |
| `lib/content.dart` | Reading the bundled database |
| `lib/review_store.dart` | Progress, logs, settings, recordings |
| `lib/app_state.dart` | The one object every screen reads from |
| `lib/writing_screen.dart` | Stroke tracing; its parser and comparison are pure and tested |
| `lib/speech.dart`, `lib/notifications.dart` | The thin layer that touches plugins |
| `lib/challenge.dart` | Picking the day's challenge and matching it to the deck |
| `tool/build_content.py` | Everything above, assembled from open data |

**Progress lives in a separate database from the content**, and that
separation is the point: `content.db` is replaced wholesale whenever the
word lists are rebuilt, and progress has to survive that. Reviews are
keyed by a string card id (`word:123`), so a rebuild that renumbers
nothing keeps every review, and one that drops a word loses that word's
history and nothing else.

## Building

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Rebuilding the content (needs network; caches downloads in `tool/.cache/`):

```sh
python3 tool/build_content.py
```

`flutter analyze` and `flutter test` never touch Gradle, so a broken
release config sits invisible until someone actually builds one — worth
doing after any change to the Android side, not just before shipping.

### Two Android things that are load-bearing

**Core library desugaring is required.** `flutter_local_notifications`
bundles a desugared `java.time`, and without
`isCoreLibraryDesugaringEnabled` the build fails at `checkAarMetadata`
before a line of app code compiles.

**`flutter_tts` warns on every build** that it applies the Kotlin Gradle
Plugin and that *future* versions of Flutter will refuse to build it. It
works on Flutter 3.47.0. It is on borrowed time — see
[dlutton/flutter_tts#646](https://github.com/dlutton/flutter_tts/issues/646).
If a Flutter upgrade breaks the build, that is the first thing to check.

`android/app/debug.keystore` is committed on purpose (debug-only, never
used for release signing) so local and CI builds share one signing
identity and can install over each other. Flutter's default
`android/.gitignore` has a blanket `**/*.keystore`, so the negation below
it is what actually lets the file be tracked.

Verify the signing identity rather than assuming it — and note that
`keytool -printcert -jarfile` only understands legacy v1 JAR signing and
will wrongly call a modern APK unsigned:

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
keytool -list -v -keystore android/app/debug.keystore -storepass android -alias androiddebugkey
```

## Releasing

Publish only ever through `scripts/release.sh`, never by hand: it bumps
the version, commits everything, pushes, and verifies with `aapt2` that
the APK it is about to upload actually carries the new version. Releasing
a stale artefact ships the previous version under a new tag, Android sees
an unchanged versionCode and declines the install, and the release
quietly contains none of its own changes.

Releases are shaped to Obtainium's defaults: the tag is exactly the
version (`0.1.1`, not `v0.1.1-abc123`), every release bumps both version
and build number, and there is one APK asset per release.

CI is `workflow_dispatch` only, so it does not burn Actions minutes on
every push. Run it by hand when you want a build from a clean machine.

## What it deliberately doesn't do

- **Network, accounts, sync, ads.** The app never makes a request.
- **Score your pronunciation.** Nothing can do that honestly on a device.
- **Claim to be the official JLPT syllabus.** There isn't one.
- **Generate exam-style reading passages.** There is no freely licensed
  corpus of them, so reading practice uses real sentences instead.
