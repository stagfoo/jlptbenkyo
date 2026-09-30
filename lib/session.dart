/// Choosing what to put in front of someone, and in what order.
///
/// Plain Dart: it takes the card states and the ids that exist, and
/// returns a queue. No database, no clock of its own, no widgets — so the
/// rules that decide a study session can be tested directly, which
/// matters because they are the difference between a deck someone keeps
/// up with and one they abandon in week three.
library;

import 'dart:math' as math;

import 'srs.dart';

/// What kind of thing a card is. The id carries it as a prefix so one
/// queue can hold all three and one table can store them.
enum CardKind { word, kanji, grammar }

CardKind? kindOf(String cardId) => switch (cardId.split(':').first) {
      'word' => CardKind.word,
      'kanji' => CardKind.kanji,
      'grammar' => CardKind.grammar,
      _ => null,
    };

int? idOf(String cardId) => int.tryParse(cardId.split(':').last);

/// The knobs someone can actually turn, and why each exists.
class StudySettings {
  const StudySettings({
    this.newPerDay = 15,
    this.maxReviewsPerDay = 120,
    this.easiestLevel = 5,
    this.includeWords = true,
    this.includeKanji = true,
    this.includeGrammar = true,
  });

  /// New cards introduced per day. The single most consequential
  /// setting in the app: the deck is ~4,200 items, and every new card
  /// becomes roughly ten reviews spread over the following months.
  final int newPerDay;

  /// A ceiling on a day's reviews, so a fortnight away does not return
  /// six hundred cards at once — which is the point most people stop.
  /// Overdue cards are not lost, only deferred; the most overdue are
  /// always the ones shown.
  final int maxReviewsPerDay;

  /// The easiest JLPT level to include, as a number: 5 keeps N5, N4 and
  /// N3; 4 drops N5; 3 leaves N3-specific material only.
  ///
  /// Named for what it means rather than for the comparison, because the
  /// numbers run backwards to the names — N5 is the *easiest* level and
  /// the *highest* number. Filtering is `level <= easiestLevel`. Getting
  /// that the wrong way round silently inverts the setting: "N5-N3" then
  /// returns 718 words instead of 3,526, and the app studies the
  /// opposite of what the label says.
  final int easiestLevel;

  final bool includeWords;
  final bool includeKanji;
  final bool includeGrammar;

  bool includes(CardKind kind) => switch (kind) {
        CardKind.word => includeWords,
        CardKind.kanji => includeKanji,
        CardKind.grammar => includeGrammar,
      };

  StudySettings copyWith({
    int? newPerDay,
    int? maxReviewsPerDay,
    int? easiestLevel,
    bool? includeWords,
    bool? includeKanji,
    bool? includeGrammar,
  }) =>
      StudySettings(
        newPerDay: newPerDay ?? this.newPerDay,
        maxReviewsPerDay: maxReviewsPerDay ?? this.maxReviewsPerDay,
        easiestLevel: easiestLevel ?? this.easiestLevel,
        includeWords: includeWords ?? this.includeWords,
        includeKanji: includeKanji ?? this.includeKanji,
        includeGrammar: includeGrammar ?? this.includeGrammar,
      );
}

/// Builds the day's queue.
///
/// [available] is every card id that exists at the chosen level, in the
/// order the content database considers worth learning — commonest
/// first. [states] is what is known about the ones that have been seen.
///
/// New cards are interleaved rather than front-loaded or appended. All
/// the new cards first means the reviews are answered while tired, and
/// all of them last means they are never reached on a day that runs
/// short; spacing them through the queue is the only arrangement where
/// stopping early still costs proportionally.
List<CardState> buildQueue(
  List<String> available,
  Map<String, CardState> states,
  DateTime now, {
  StudySettings settings = const StudySettings(),
  int reviewedToday = 0,
}) {
  final due = <CardState>[];
  final fresh = <CardState>[];

  for (final id in available) {
    final kind = kindOf(id);
    if (kind == null || !settings.includes(kind)) continue;

    final state = states[id] ?? CardState(id: id);
    if (state.suspended) continue;

    if (state.isNew) {
      fresh.add(state);
    } else if (state.isDue(now)) {
      due.add(state);
    }
  }

  due.sort((a, b) => compareForQueue(a, b, now));

  // The review ceiling counts what has already been answered today, so
  // opening the app a second time does not hand out a second full day.
  final reviewRoom = math.max(0, settings.maxReviewsPerDay - reviewedToday);
  final reviews = due.take(reviewRoom).toList();

  // New cards are rationed against the same day's budget. Falling behind
  // on reviews should slow the intake of new material automatically,
  // rather than needing someone to notice and turn it down by hand.
  final newRoom = math.max(
    0,
    math.min(settings.newPerDay, reviewRoom - reviews.length),
  );
  final newCards = fresh.take(newRoom).toList();

  return _interleave(reviews, newCards);
}

/// Spreads [newCards] evenly through [reviews].
List<CardState> _interleave(List<CardState> reviews, List<CardState> newCards) {
  if (newCards.isEmpty) return reviews;
  if (reviews.isEmpty) return newCards;

  final out = <CardState>[];
  final gap = reviews.length / newCards.length;
  var nextNew = 0;
  for (var i = 0; i < reviews.length; i++) {
    out.add(reviews[i]);
    while (nextNew < newCards.length && (nextNew + 1) * gap <= i + 1) {
      out.add(newCards[nextNew++]);
    }
  }
  out.addAll(newCards.sublist(nextNew));
  return out;
}

/// What the home screen reports before anyone commits to a session.
class SessionSummary {
  const SessionSummary({
    required this.learning,
    required this.review,
    required this.newCards,
    required this.deferred,
  });

  final int learning, review, newCards;

  /// Cards that are due but will not be shown today because of the
  /// review ceiling. Reported rather than hidden: someone coming back
  /// from a fortnight away should be told there is a backlog and that it
  /// is being fed to them gradually, not left to conclude the app forgot
  /// their deck.
  final int deferred;

  int get total => learning + review + newCards;
  bool get isEmpty => total == 0;
}

SessionSummary summarise(
  List<String> available,
  Map<String, CardState> states,
  DateTime now, {
  StudySettings settings = const StudySettings(),
  int reviewedToday = 0,
}) {
  var learning = 0, review = 0, fresh = 0;
  for (final id in available) {
    final kind = kindOf(id);
    if (kind == null || !settings.includes(kind)) continue;
    final state = states[id] ?? CardState(id: id);
    if (state.suspended) continue;
    if (state.isNew) {
      fresh++;
    } else if (state.isDue(now)) {
      if (state.isLearning) {
        learning++;
      } else {
        review++;
      }
    }
  }

  final dueTotal = learning + review;
  final room = math.max(0, settings.maxReviewsPerDay - reviewedToday);
  final shown = math.min(dueTotal, room);
  final newShown =
      math.max(0, math.min(settings.newPerDay, room - shown)).clamp(0, fresh);

  // Learning cards are never deferred — they are minutes from being
  // forgotten, and holding them back to respect a daily ceiling would
  // undo the work that just went into them.
  final shownLearning = math.min(learning, shown);
  return SessionSummary(
    learning: shownLearning,
    review: shown - shownLearning,
    newCards: newShown,
    deferred: dueTotal - shown,
  );
}

/// How far through the deck someone is, per kind.
class Progress {
  const Progress({
    required this.total,
    required this.seen,
    required this.learned,
  });

  final int total;

  /// Cards that have been answered at least once.
  final int seen;

  /// Cards that have graduated out of the learning steps and are on a
  /// real interval — the honest measure of "known", as distinct from
  /// "met once this morning".
  final int learned;

  double get fraction => total == 0 ? 0 : learned / total;
}

Progress progressFor(
  List<String> available,
  Map<String, CardState> states,
  CardKind kind,
) {
  var total = 0, seen = 0, learned = 0;
  for (final id in available) {
    if (kindOf(id) != kind) continue;
    total++;
    final s = states[id];
    if (s == null || s.isNew) continue;
    seen++;
    if (s.step < 0) learned++;
  }
  return Progress(total: total, seen: seen, learned: learned);
}
