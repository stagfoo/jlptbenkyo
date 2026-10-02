/// Pointing practice at what the deck is actually asking for.
///
/// The ordinary way to study kanji is to walk a list by frequency or by
/// level. That order is wrong for someone who is already learning words,
/// and measurably so: **402 of the 609 kanji here appear in words easier
/// than the character itself**. You meet 遊ぶ as an N5 word and 遊 as an
/// N3 character; 部屋, 本当 and 飛行機 are all N5 words built from N3
/// kanji. A frequency list hands you those characters years after you
/// started saying the words, and in the meantime you know the word, can
/// say it, and cannot write it.
///
/// So the writing exercise is driven by the deck instead. The characters
/// it surfaces first are the ones where **you already know a word that
/// uses them and do not know the character** — the exact gap, rather than
/// the next entry in a list.
///
/// Plain Dart with no Flutter and no clock of its own, so the ranking can
/// be tested against a deck built by hand.
library;

import 'dart:math' as math;

import 'srs.dart';

/// A kanji and the deck words that use it, as the content database knows
/// them. The full record is loaded only for the ones actually shown.
class KanjiRef {
  const KanjiRef({
    required this.id,
    required this.literal,
    required this.level,
    required this.wordIds,
    this.easiestWordLevel,
  });

  final int id;
  final String literal;
  final int level;

  /// Every word in the deck written with this character.
  final List<int> wordIds;

  /// The JLPT level of the easiest word using it, where there is one.
  final int? easiestWordLevel;

  /// How far ahead of its own character the easiest word runs.
  ///
  /// 遊 is an N3 character and 遊ぶ an N5 word, so its gap is 2. This is
  /// the measurable form of the blind spot: a character you have been
  /// reading inside easy words for a year without ever being taught it.
  /// Across this library 402 of 609 characters have a positive gap, which
  /// is why a frequency list is the wrong order for someone who already
  /// knows words.
  int get levelGap =>
      easiestWordLevel == null ? 0 : easiestWordLevel! - level;

  String get cardId => 'kanji:$id';
}

/// Why a character is being put in front of you. Shown on the screen,
/// because "practise this one" is far less useful than "you know 遊ぶ but
/// not this".
enum FocusReason {
  /// You can already use a word written with this character, and cannot
  /// write the character. The gap this whole module exists for.
  knowWordNotKanji,

  /// The character's own card is due or overdue.
  dueForReview,

  /// It turns up in words you have started, but you are not yet
  /// comfortable with either.
  inYourWords,

  /// Nothing in your deck uses it yet. Still learnable, just not urgent.
  notYetNeeded,
}

/// A character, scored and explained.
class KanjiFocus {
  const KanjiFocus({
    required this.kanji,
    required this.score,
    required this.reason,
    required this.exampleWordIds,
    required this.startedWords,
    required this.confidentWords,
  });

  final KanjiRef kanji;

  /// 0..1. Demand from the deck multiplied by how weak your grip is.
  final double score;

  final FocusReason reason;

  /// Words of yours that use it, the best-known first — so the screen can
  /// say *which* word you already know.
  final List<int> exampleWordIds;

  /// How many words using it you have answered at least once.
  final int startedWords;

  /// How many of those you are comfortable with.
  final int confidentWords;
}

/// An interval at which a word has stopped being work. Three weeks is
/// roughly where recall becomes retrieval rather than reconstruction —
/// and it is deliberately well short of the 60 days that counts as
/// mature elsewhere, because the point here is that the *word* is
/// comfortable while the character is not.
const int kConfidentIntervalDays = 21;

/// Where a character stops being urgent. Past this the card is holding on
/// its own and the exercise has better uses for your time.
const int kSettledIntervalDays = 60;

/// How weak your grip on a character is, 0..1.
double _weakness(CardState? state) {
  if (state == null || state.isNew) return 1;
  if (state.suspended) return 0;

  // Lapses matter beyond what the interval says: a character you have
  // forgotten three times and relearned is not as solid as a fresh one
  // sitting at the same interval.
  final lapsePenalty = math.min(0.3, state.lapses * 0.1);
  final settled =
      (state.intervalDays / kSettledIntervalDays).clamp(0.0, 1.0);
  return (1 - settled + lapsePenalty).clamp(0.0, 1.0);
}

/// How much your deck is actually asking you to read this character.
///
/// Logarithmic rather than linear: the fifth word using a character adds
/// far less urgency than the second, and a purely linear count would let
/// a handful of very common characters crowd out everything else for
/// weeks.
double _demand(int startedWords) {
  if (startedWords <= 0) return 0;
  return math.min(1, math.log(1 + startedWords) / math.log(6));
}

/// Scores one character against the deck.
KanjiFocus focusFor(
  KanjiRef kanji,
  Map<String, CardState> states,
  DateTime now,
) {
  final started = <(int, int)>[]; // (wordId, interval)
  var confident = 0;

  for (final wordId in kanji.wordIds) {
    final state = states['word:$wordId'];
    if (state == null || state.isNew || state.suspended) continue;
    started.add((wordId, state.intervalDays));
    if (state.intervalDays >= kConfidentIntervalDays) confident++;
  }

  // Best-known first, so the screen names the word you are surest of.
  started.sort((a, b) => b.$2.compareTo(a.$2));

  final kanjiState = states[kanji.cardId];
  final weakness = _weakness(kanjiState);
  final demand = _demand(started.length);

  final reason = switch ((confident, kanjiState, started.length)) {
    // The headline case, and it only counts when the character really is
    // weak: knowing both the word and the character is not a gap.
    (> 0, final s, _) when _weakness(s) >= 0.7 =>
      FocusReason.knowWordNotKanji,
    (_, final s?, _) when !s.isNew && !s.suspended && s.isDue(now) =>
      FocusReason.dueForReview,
    (_, _, > 0) => FocusReason.inYourWords,
    _ => FocusReason.notYetNeeded,
  };

  return KanjiFocus(
    kanji: kanji,
    score: demand * weakness,
    reason: reason,
    exampleWordIds: [for (final s in started.take(4)) s.$1],
    startedWords: started.length,
    confidentWords: confident,
  );
}

/// Orders every character by how much the deck needs it.
///
/// Suspended characters are dropped outright. Everything else is kept and
/// ranked, including characters nothing in your deck uses yet — they sink
/// to the bottom rather than disappearing, so the exercise never runs out
/// and a deliberate trawl through unfamiliar characters is still possible.
List<KanjiFocus> rankForWriting(
  List<KanjiRef> all,
  Map<String, CardState> states,
  DateTime now, {
  bool deckOnly = false,
}) {
  final out = <KanjiFocus>[];
  for (final kanji in all) {
    final state = states[kanji.cardId];
    if (state != null && state.suspended) continue;
    final focus = focusFor(kanji, states, now);
    if (deckOnly && focus.startedWords == 0) continue;
    out.add(focus);
  }

  out.sort((a, b) {
    // Reason leads, so "you know the word but not the character" stays at
    // the top even when a long-overdue character scores higher
    // arithmetically. That ordering is the feature.
    final byReason = a.reason.index.compareTo(b.reason.index);
    if (byReason != 0) return byReason;
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;

    // Then the widest gap. Among characters the deck wants equally, the
    // one hiding inside words far easier than itself is the real blind
    // spot: 日 appears in twenty words you know and you can already write
    // it, whereas 遊 has been sitting inside 遊ぶ since N5 unwritten.
    final byGap = b.kanji.levelGap.compareTo(a.kanji.levelGap);
    if (byGap != 0) return byGap;

    // Then the easier character, and finally by id so the order is total
    // and cannot differ between runs.
    final byLevel = b.kanji.level.compareTo(a.kanji.level);
    return byLevel != 0 ? byLevel : a.kanji.id.compareTo(b.kanji.id);
  });

  return out;
}

// ---------------------------------------------------------------- grammar

/// A grammar point, with the deck words its examples are built from.
class GrammarRef {
  const GrammarRef({
    required this.id,
    required this.level,
    required this.wordIds,
  });

  final int id;
  final int level;

  /// Words appearing in this point's example sentences that are also in
  /// the deck. What makes one grammar point more readable than another
  /// right now.
  final List<int> wordIds;

  String get cardId => 'grammar:$id';
}

/// Where a grammar point sits relative to your study, for the list to
/// show at a glance.
enum GrammarStanding {
  /// Its card is due now.
  due,

  /// Started, and still on a short interval.
  learning,

  /// Started and holding.
  known,

  /// Never studied.
  notStarted,
}

class GrammarFocus {
  const GrammarFocus({
    required this.id,
    required this.standing,
    required this.readableWords,
    required this.score,
  });

  final int id;
  final GrammarStanding standing;

  /// How many words in its examples you have already started. A point
  /// whose examples you can mostly read teaches the structure; one built
  /// from unknown words teaches vocabulary badly.
  final int readableWords;

  final double score;
}

GrammarStanding standingFor(CardState? state, DateTime now) {
  if (state == null || state.isNew) return GrammarStanding.notStarted;
  if (state.isDue(now)) return GrammarStanding.due;
  return state.intervalDays >= kSettledIntervalDays
      ? GrammarStanding.known
      : GrammarStanding.learning;
}

/// Orders grammar points around what you are studying.
///
/// Due points first — they are the ones the scheduler says you are about
/// to forget. Within each group, the points whose examples you can
/// actually read come first: a structure demonstrated in words you know
/// is a structure you can see, and one demonstrated in words you do not
/// is two problems at once.
List<GrammarFocus> rankGrammar(
  List<GrammarRef> all,
  Map<String, CardState> states,
  DateTime now,
) {
  final out = [
    for (final g in all)
      () {
        final state = states[g.cardId];
        var readable = 0;
        for (final wordId in g.wordIds) {
          final w = states['word:$wordId'];
          if (w != null && !w.isNew && !w.suspended) readable++;
        }
        return GrammarFocus(
          id: g.id,
          standing: standingFor(state, now),
          readableWords: readable,
          score: g.wordIds.isEmpty ? 0 : readable / g.wordIds.length,
        );
      }(),
  ];

  out.sort((a, b) {
    final byStanding = a.standing.index.compareTo(b.standing.index);
    if (byStanding != 0) return byStanding;
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.id.compareTo(b.id);
  });

  return out;
}
