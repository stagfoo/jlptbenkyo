/// The spaced-repetition scheduler.
///
/// Plain Dart with no Flutter, no plugin and no clock of its own — the
/// time is always passed in. That is what makes the whole of it testable
/// at full speed: a year of reviews runs in a millisecond against a fake
/// `now`, and the cases that actually matter (a card lapsing repeatedly,
/// an interval overflowing, a deck untouched for six months) are the ones
/// you would otherwise have to wait months on a real device to see once.
///
/// The algorithm is SM-2 with learning steps, which is what Anki has
/// converged on and what decades of use has sanded the corners off. It is
/// chosen over FSRS deliberately: FSRS is better, but it earns that by
/// fitting parameters to a review history that does not exist yet on a
/// fresh install, and a worse algorithm you can reason about beats a
/// better one you cannot debug on a tablet.
library;

import 'dart:math' as math;

/// What the reviewer said about a card.
enum Grade {
  /// Did not know it. The card goes back to the start.
  again,

  /// Knew it, but it hurt. Shorter than it would otherwise have been.
  hard,

  /// Knew it. The ordinary answer, and the one the intervals are tuned
  /// around.
  good,

  /// Knew it instantly. Skips ahead.
  easy,
}

/// How long a card waits after each answer while it is still being
/// learned. A card that survives the last step graduates into the
/// interval schedule.
///
/// Two steps rather than Anki's default three: this is a deck someone
/// studies once a day, so a third step ten minutes later only ever lands
/// inside the same sitting and teaches the card nothing it did not
/// already know a minute ago.
const List<Duration> kLearningSteps = [
  Duration(minutes: 1),
  Duration(minutes: 10),
];

/// The first real interval, once a card leaves the learning steps.
const int kGraduatingIntervalDays = 1;

/// Where a card lands if it graduated on [Grade.easy] instead.
const int kEasyIntervalDays = 4;

/// A card's starting ease. 2.5 means "next time, two and a half times as
/// long as last time".
const double kStartingEase = 2.5;

/// Ease can be driven down by failures but never below this. Under about
/// 1.3 the intervals stop growing meaningfully and the card is in front of
/// you every other day forever, which is how people come to hate a deck.
const double kMinimumEase = 1.3;

/// How much a card's ease moves on each answer.
const double kEasePenaltyAgain = -0.20;
const double kEasePenaltyHard = -0.15;
const double kEaseBonusEasy = 0.15;

/// What a failed card's interval is multiplied by, rather than reset to
/// zero. A word you have known for four months and just blanked on is not
/// as new as a word you met this morning, and throwing the whole history
/// away is what makes a single bad session feel like a punishment.
const double kLapseMultiplier = 0.5;

/// Intervals are capped so a card cannot disappear over the horizon. Ten
/// years of not seeing a word is indistinguishable from never seeing it.
const int kMaximumIntervalDays = 365 * 2;

/// A card someone has failed this many times is not being learned, it is
/// being endured. Marking it lets the UI offer to reformulate or suspend
/// it rather than letting it keep surfacing.
const int kLeechThreshold = 8;

/// Everything the scheduler knows about one item.
///
/// Immutable: a review returns a new state rather than mutating this one,
/// so a caller can compute what *would* happen to a card under each of
/// the four answers — which is exactly what the review screen shows on
/// its buttons — without having to undo anything.
class CardState {
  const CardState({
    required this.id,
    this.reps = 0,
    this.lapses = 0,
    this.ease = kStartingEase,
    this.intervalDays = 0,
    this.step = 0,
    this.due,
    this.suspended = false,
  });

  /// `word:123`, `kanji:45`, `grammar:7`. One namespace, so a single
  /// queue can mix them and a single table can store them.
  final String id;

  /// Successful reviews since the card was last learned from scratch.
  final int reps;

  /// How many times this has been forgotten after having been learned.
  final int lapses;

  final double ease;

  /// The current interval in days. Zero while the card is still in the
  /// learning steps, where waits are measured in minutes.
  final int intervalDays;

  /// Position in [kLearningSteps], or -1 once graduated.
  final int step;

  /// When this is next due. Null means it has never been seen.
  final DateTime? due;

  final bool suspended;

  bool get isNew => due == null;
  bool get isLearning => step >= 0 && !isNew;
  bool get isLeech => lapses >= kLeechThreshold;

  bool isDue(DateTime now) =>
      !suspended && (due == null || !due!.isAfter(now));

  CardState copyWith({
    int? reps,
    int? lapses,
    double? ease,
    int? intervalDays,
    int? step,
    DateTime? due,
    bool? suspended,
  }) {
    return CardState(
      id: id,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      ease: ease ?? this.ease,
      intervalDays: intervalDays ?? this.intervalDays,
      step: step ?? this.step,
      due: due ?? this.due,
      suspended: suspended ?? this.suspended,
    );
  }

  @override
  String toString() => 'CardState($id, reps=$reps, lapses=$lapses, '
      'ease=${ease.toStringAsFixed(2)}, ivl=$intervalDays, step=$step)';
}

/// Applies one answer to one card.
///
/// [now] is always supplied rather than read from the system clock, so
/// the scheduler has no hidden input and a test can walk a card through a
/// simulated year without sleeping.
CardState applyReview(CardState card, Grade grade, DateTime now) {
  if (card.step >= 0) return _reviewLearning(card, grade, now);
  return _reviewGraduated(card, grade, now);
}

CardState _reviewLearning(CardState card, Grade grade, DateTime now) {
  switch (grade) {
    case Grade.again:
      // Back to the first step. Not to "new" — the card keeps its
      // history, because having seen it once and failed is different from
      // never having seen it.
      return card.copyWith(
        step: 0,
        due: now.add(kLearningSteps.first),
      );

    case Grade.easy:
      // Straight out of learning, however many steps were left. Someone
      // who answers a brand-new card instantly already knew it, and
      // marching it through the steps anyway wastes both of you.
      // A relearning card keeps the interval its lapse left it with, if
      // that is already longer. Graduating flat to the beginner's
      // interval would silently undo [kLapseMultiplier] and send a word
      // you have known for months back to square one after all.
      final ivl = math.max(card.intervalDays, kEasyIntervalDays);
      return card.copyWith(
        step: -1,
        reps: card.reps + 1,
        intervalDays: ivl,
        due: _atDays(now, ivl),
      );

    case Grade.hard:
      // Sit on the same step rather than advancing. Repeating the step is
      // the whole point of hard on a card that is not learned yet.
      return card.copyWith(due: now.add(kLearningSteps[card.step]));

    case Grade.good:
      final next = card.step + 1;
      if (next < kLearningSteps.length) {
        return card.copyWith(step: next, due: now.add(kLearningSteps[next]));
      }
      final ivl = math.max(card.intervalDays, kGraduatingIntervalDays);
      return card.copyWith(
        step: -1,
        reps: card.reps + 1,
        intervalDays: ivl,
        due: _atDays(now, ivl),
      );
  }
}

CardState _reviewGraduated(CardState card, Grade grade, DateTime now) {
  if (grade == Grade.again) {
    // A lapse. The card drops back into learning and its interval is
    // halved rather than erased — see [kLapseMultiplier].
    final ivl = math.max(1, (card.intervalDays * kLapseMultiplier).round());
    return card.copyWith(
      step: 0,
      lapses: card.lapses + 1,
      reps: 0,
      ease: _clampEase(card.ease + kEasePenaltyAgain),
      intervalDays: ivl,
      due: now.add(kLearningSteps.first),
    );
  }

  final ease = _clampEase(card.ease +
      switch (grade) {
        Grade.hard => kEasePenaltyHard,
        Grade.easy => kEaseBonusEasy,
        _ => 0.0,
      });

  // The previous interval, or one day for a card graduating out of a
  // lapse with nothing sensible behind it.
  final previous = math.max(1, card.intervalDays);

  final grown = switch (grade) {
    // Hard grows, but slowly. A flat 1.2 rather than the ease, so a card
    // that is consistently hard stops being shown every day without ever
    // being promoted as if it were known.
    Grade.hard => previous * 1.2,
    Grade.good => previous * ease,
    Grade.easy => previous * ease * 1.3,
    Grade.again => previous.toDouble(),
  };

  // Each grade must land at least a day beyond the one below it.
  //
  // Without this the three answers collapse into the same number at short
  // intervals: a one-day card graded good gives 1 × 2.5 → 3 days, and
  // graded easy gives 1 × 2.65 × 1.3 → 3 days as well, so pressing the
  // button that means "this was trivial" changes nothing. Once intervals
  // are longer the multipliers separate them on their own and these
  // floors never bind.
  final floor = previous +
      switch (grade) {
        Grade.hard => 1,
        Grade.good => 2,
        Grade.easy => 3,
        Grade.again => 0,
      };

  final ivl = math.min(
    kMaximumIntervalDays,
    math.max(floor, grown.round()),
  );

  return card.copyWith(
    reps: card.reps + 1,
    ease: ease,
    intervalDays: ivl,
    due: _atDays(now, ivl),
  );
}

double _clampEase(double e) => e < kMinimumEase ? kMinimumEase : e;

/// Due dates land at the same time of day the review happened, which
/// keeps a daily habit anchored to when the person actually studies
/// rather than to midnight.
DateTime _atDays(DateTime now, int days) => now.add(Duration(days: days));

/// What each button would do to this card, for the review screen to show.
///
/// Showing the next interval on the button is the one piece of feedback
/// that makes a scheduler feel like it is doing something rather than
/// guessing, and it costs nothing because the scheduler is pure.
Map<Grade, CardState> previewAll(CardState card, DateTime now) => {
      for (final g in Grade.values) g: applyReview(card, g, now),
    };

/// Orders a due queue.
///
/// Learning cards first, then overdue ones by how overdue they are, then
/// new ones. Learning first because they are minutes from being forgotten
/// again; most-overdue next because that is where forgetting is actually
/// happening; new last because introducing a new word while you are
/// behind on old ones is how a backlog becomes unrecoverable.
int compareForQueue(CardState a, CardState b, DateTime now) {
  int rank(CardState c) => c.isNew ? 2 : (c.isLearning ? 0 : 1);
  final ra = rank(a), rb = rank(b);
  if (ra != rb) return ra.compareTo(rb);
  if (ra == 2) return a.id.compareTo(b.id);
  final da = a.due!, db = b.due!;
  final c = da.compareTo(db);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// How many cards are waiting, split the way the UI reports it.
class DueCounts {
  const DueCounts(this.learning, this.review, this.newCards);

  final int learning, review, newCards;

  int get total => learning + review + newCards;
  bool get isEmpty => total == 0;
}

DueCounts countDue(
  Iterable<CardState> cards,
  DateTime now, {
  int newPerDay = 20,
}) {
  var learning = 0, review = 0, fresh = 0;
  for (final c in cards) {
    if (c.suspended) continue;
    if (c.isNew) {
      fresh++;
    } else if (c.isDue(now)) {
      if (c.isLearning) {
        learning++;
      } else {
        review++;
      }
    }
  }
  // New cards are rationed. The whole deck is three and a half thousand
  // words, and a day that introduces two hundred of them produces two
  // hundred reviews a day for the next fortnight — which is how a study
  // habit dies in week three.
  return DueCounts(learning, review, math.min(fresh, newPerDay));
}
