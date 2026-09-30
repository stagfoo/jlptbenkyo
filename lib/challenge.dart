/// Choosing the day's challenge, and connecting it to the deck.
///
/// Plain Dart: it takes a list of challenges, what is known about the
/// cards, and a date, and returns a pick. No database, no clock of its
/// own, no widgets — so the rule that decides what you are asked to do
/// today can be tested directly, including the part that matters most,
/// which is that it does not hand you the same scenario twice in a week.
///
/// The point of the feature is the join: a challenge is worth doing when
/// it is made of words you are actually in the middle of learning, and
/// worth skipping when every word in it is either unknown or long since
/// mastered. That is what [affinity] measures and what the daily pick
/// weights by.
library;

import 'srs.dart';

/// Just enough of a challenge to choose between them. The full record
/// lives in the content database and is loaded only once one is picked.
class ChallengeRef {
  const ChallengeRef({
    required this.id,
    required this.level,
    required this.wordIds,
  });

  final String id;
  final int level;

  /// The deck words this scenario is built from, resolved at build time.
  final List<int> wordIds;
}

/// How much of a challenge is made of words you are part-way through.
///
/// Not "how many do you know" — a scenario where you know every word is
/// no longer practice, and one where you know none of them is a
/// vocabulary list, not a task. What earns a challenge its place is the
/// middle: words that are in the deck and in motion.
///
/// Returns 0..1. A challenge with no linked words scores a flat 0.5 so it
/// is neither promoted nor buried; it is still a real task, the app just
/// has nothing to say about how it fits.
double affinity(ChallengeRef challenge, Map<String, CardState> states) {
  if (challenge.wordIds.isEmpty) return 0.5;

  var inMotion = 0;
  for (final id in challenge.wordIds) {
    final state = states['word:$id'];
    if (state == null || state.isNew || state.suspended) continue;
    // Mature cards have stopped teaching anything. Two months is the
    // point where a word is part of the furniture rather than something
    // you are still reaching for.
    if (state.intervalDays > 60) continue;
    inMotion++;
  }
  return inMotion / challenge.wordIds.length;
}

/// How many of a challenge's words are in each state, for the screen to
/// show rather than just score with.
class WordBreakdown {
  const WordBreakdown({
    required this.total,
    required this.learning,
    required this.known,
    required this.unseen,
  });

  final int total;

  /// Started and still on a short interval — the ones this is practice for.
  final int learning;

  /// Graduated and on a long interval.
  final int known;

  /// Never answered, or not in the deck at the current level setting.
  final int unseen;
}

WordBreakdown breakdown(
  ChallengeRef challenge,
  Map<String, CardState> states,
) {
  var learning = 0, known = 0, unseen = 0;
  for (final id in challenge.wordIds) {
    final state = states['word:$id'];
    if (state == null || state.isNew) {
      unseen++;
    } else if (state.intervalDays > 60) {
      known++;
    } else {
      learning++;
    }
  }
  return WordBreakdown(
    total: challenge.wordIds.length,
    learning: learning,
    known: known,
    unseen: unseen,
  );
}

/// How many of the most recent challenges are held back from being picked
/// again. Roughly a fortnight at one a day, which is long enough that a
/// repeat feels like a callback rather than the app running out.
const int kRecentMemory = 14;

/// How wide the field is before the day's date decides.
///
/// Picking strictly the best-fitting challenge would hand you the same
/// one every day until your deck moved. Picking purely at random would
/// ignore the deck entirely. Ranking by fit and then letting the date
/// choose within the top band gives both: relevant, and different
/// tomorrow.
const int kDailyBand = 8;

/// The day's challenge. Deterministic: the same date and the same deck
/// always give the same answer, so opening the app twice does not change
/// what you were asked to do.
ChallengeRef? pickDaily(
  List<ChallengeRef> all,
  Map<String, CardState> states,
  DateTime day, {
  List<String> recentlyDone = const [],
  int easiestLevel = 5,
}) {
  final recent = recentlyDone.take(kRecentMemory).toSet();

  var eligible = [
    for (final c in all)
      if (c.level <= easiestLevel && !recent.contains(c.id)) c,
  ];

  // Everything having been done recently is not a reason to offer
  // nothing — it means the memory is longer than the library, so it is
  // dropped rather than the day being empty.
  if (eligible.isEmpty) {
    eligible = [for (final c in all) if (c.level <= easiestLevel) c];
  }
  if (eligible.isEmpty) return null;

  final scored = [
    for (final c in eligible) (c, affinity(c, states)),
  ]..sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      // Ties broken by id, so the ordering is stable and the same day
      // cannot give different answers on two devices.
      return byScore != 0 ? byScore : a.$1.id.compareTo(b.$1.id);
    });

  final band = scored.take(kDailyBand).toList();
  return band[_daySeed(day) % band.length].$1;
}

/// A stable number for a calendar day. Deliberately not a hash of the
/// whole `DateTime` — that would change every millisecond and the
/// challenge would move while you were looking at it.
int _daySeed(DateTime day) {
  final ordinal = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(2000))
      .inDays;
  // A cheap scramble, so consecutive days do not walk the list in order.
  final x = ordinal * 2654435761;
  return (x ^ (x >> 16)).abs();
}

/// Words from the deck to deliberately work into today's attempt.
///
/// The direct answer to "ways to practise the words I'm learning": the
/// challenge supplies a situation, and these supply the words that are
/// currently costing you something to recall. Challenge words come first
/// where they qualify, because using them in the scenario they belong to
/// is the easiest win; the rest is filled from whatever else is in
/// motion, so the list is never empty on a scenario the deck does not
/// happen to cover.
List<int> wordsToPractise(
  ChallengeRef challenge,
  Map<String, CardState> states,
  DateTime now, {
  int count = 5,
}) {
  bool inMotion(CardState s) =>
      !s.isNew && !s.suspended && s.intervalDays <= 60;

  final fromChallenge = <int>[
    for (final id in challenge.wordIds)
      if (states['word:$id'] case final s?) if (inMotion(s)) id,
  ];

  if (fromChallenge.length >= count) {
    return fromChallenge.take(count).toList();
  }

  // Filled from the rest of the deck, hardest first — a word you have
  // lapsed on repeatedly is the one worth forcing into a sentence today.
  final rest = <(int, CardState)>[];
  for (final entry in states.entries) {
    if (!entry.key.startsWith('word:')) continue;
    final id = int.tryParse(entry.key.substring(5));
    if (id == null || fromChallenge.contains(id)) continue;
    if (!inMotion(entry.value)) continue;
    rest.add((id, entry.value));
  }
  rest.sort((a, b) {
    final byLapses = b.$2.lapses.compareTo(a.$2.lapses);
    if (byLapses != 0) return byLapses;
    final byEase = a.$2.ease.compareTo(b.$2.ease);
    return byEase != 0 ? byEase : a.$1.compareTo(b.$1);
  });

  return [
    ...fromChallenge,
    for (final r in rest.take(count - fromChallenge.length)) r.$1,
  ];
}

/// Consecutive days up to today on which a challenge was completed.
///
/// Today not having been done yet does not break the streak — it is only
/// broken by a day that has already ended with nothing in it. Counting
/// otherwise means the number reads as zero every morning.
int challengeStreak(List<DateTime> completions, DateTime now) {
  if (completions.isEmpty) return 0;

  final days = {
    for (final c in completions) DateTime(c.year, c.month, c.day),
  };

  var streak = 0;
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
