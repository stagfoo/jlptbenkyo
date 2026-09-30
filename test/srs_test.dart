/// The scheduler, walked through the situations a real deck produces.
///
/// All of it runs against an injected clock, so a card's whole life —
/// learned, forgotten, relearned, forgotten again, eventually a leech —
/// takes a millisecond instead of eight months.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jlptbenkyo/srs.dart';

final DateTime t0 = DateTime.utc(2026, 1, 1, 9, 0);

CardState fresh([String id = 'word:1']) => CardState(id: id);

/// Answers a card repeatedly, advancing the clock to each due date.
/// Returns the state and the day count that elapsed.
(CardState, int) drill(CardState card, List<Grade> grades) {
  var c = card;
  var now = t0;
  for (final g in grades) {
    c = applyReview(c, g, now);
    now = c.due!;
  }
  return (c, now.difference(t0).inDays);
}

void main() {
  group('a new card', () {
    test('starts due immediately and counts as new', () {
      final c = fresh();
      expect(c.isNew, isTrue);
      expect(c.isDue(t0), isTrue);
      expect(c.reps, 0);
    });

    test('good walks it through the learning steps, then graduates', () {
      var c = applyReview(fresh(), Grade.good, t0);
      expect(c.step, 1);
      expect(c.due, t0.add(kLearningSteps[1]));
      expect(c.intervalDays, 0, reason: 'still in minutes, not days');

      c = applyReview(c, Grade.good, c.due!);
      expect(c.step, -1, reason: 'graduated');
      expect(c.intervalDays, kGraduatingIntervalDays);
      expect(c.reps, 1);
    });

    test('again sends it back to the first step, keeping its history', () {
      var c = applyReview(fresh(), Grade.good, t0);
      c = applyReview(c, Grade.again, c.due!);
      expect(c.step, 0);
      expect(c.isNew, isFalse,
          reason: 'having seen it and failed is not the same as never '
              'having seen it');
    });

    test('hard repeats the same step rather than advancing', () {
      var c = applyReview(fresh(), Grade.good, t0);
      final at = c.due!;
      final before = c.step;
      c = applyReview(c, Grade.hard, at);
      expect(c.step, before);
      expect(c.due, at.add(kLearningSteps[before]));
    });

    test('easy skips the remaining steps entirely', () {
      final c = applyReview(fresh(), Grade.easy, t0);
      expect(c.step, -1);
      expect(c.intervalDays, kEasyIntervalDays);
    });
  });

  group('a graduated card', () {
    CardState graduated() {
      var c = applyReview(fresh(), Grade.good, t0);
      return applyReview(c, Grade.good, c.due!);
    }

    test('good multiplies the interval by the ease', () {
      final c = graduated();
      final next = applyReview(c, Grade.good, c.due!);
      expect(next.intervalDays,
          (c.intervalDays * kStartingEase).round().clamp(2, 9999));
      expect(next.ease, kStartingEase, reason: 'good does not move ease');
    });

    test('hard grows slowly and takes ease down', () {
      final c = graduated();
      final next = applyReview(c, Grade.hard, c.due!);
      expect(next.ease, closeTo(kStartingEase + kEasePenaltyHard, 1e-9));
      expect(next.intervalDays, greaterThan(c.intervalDays));
      expect(next.intervalDays,
          lessThan((c.intervalDays * kStartingEase).round() + 1));
    });

    test('easy grows fastest and raises ease', () {
      final c = graduated();
      final good = applyReview(c, Grade.good, c.due!);
      final easy = applyReview(c, Grade.easy, c.due!);
      expect(easy.intervalDays, greaterThan(good.intervalDays));
      expect(easy.ease, closeTo(kStartingEase + kEaseBonusEasy, 1e-9));
    });

    test('an interval always moves by at least a day', () {
      // Rounding can otherwise leave a short card the same distance away
      // after a correct answer, which reads as the answer not counting.
      var c = graduated();
      for (var i = 0; i < 12; i++) {
        final next = applyReview(c, Grade.hard, c.due!);
        expect(next.intervalDays, greaterThan(c.intervalDays),
            reason: 'hard must still move forward, from ${c.intervalDays}');
        c = next;
      }
    });

    test('intervals are capped rather than running to infinity', () {
      var c = graduated();
      for (var i = 0; i < 60; i++) {
        c = applyReview(c, Grade.easy, c.due!);
      }
      expect(c.intervalDays, kMaximumIntervalDays);
    });
  });

  group('forgetting', () {
    test('a lapse halves the interval instead of erasing it', () {
      var (c, _) = drill(fresh(), [Grade.good, Grade.good, Grade.good,
        Grade.good]);
      final before = c.intervalDays;
      expect(before, greaterThan(4));

      final lapsed = applyReview(c, Grade.again, c.due!);
      expect(lapsed.lapses, 1);
      expect(lapsed.step, 0, reason: 'back into learning');
      expect(lapsed.intervalDays, (before * kLapseMultiplier).round());
      expect(lapsed.ease, closeTo(kStartingEase + kEasePenaltyAgain, 1e-9));
    });

    test('a relearned card resumes from the halved interval', () {
      var (c, _) = drill(fresh(), [Grade.good, Grade.good, Grade.good]);
      final before = c.intervalDays;
      var lapsed = applyReview(c, Grade.again, c.due!);
      lapsed = applyReview(lapsed, Grade.good, lapsed.due!);
      lapsed = applyReview(lapsed, Grade.good, lapsed.due!);
      expect(lapsed.intervalDays, greaterThan((before * 0.5).round() - 1),
          reason: 'picks up from where the lapse left it, not from day one');
    });

    test('ease has a floor, however badly it goes', () {
      var c = fresh();
      var now = t0;
      for (var i = 0; i < 40; i++) {
        c = applyReview(c, Grade.good, now);
        now = c.due!;
        c = applyReview(c, Grade.good, now);
        now = c.due!;
        c = applyReview(c, Grade.again, now);
        now = c.due!;
      }
      expect(c.ease, kMinimumEase);
      expect(c.ease, greaterThanOrEqualTo(kMinimumEase));
    });

    test('a card failed enough times is flagged as a leech', () {
      var c = fresh();
      var now = t0;
      while (c.lapses < kLeechThreshold) {
        c = applyReview(c, Grade.good, now);
        now = c.due!;
        c = applyReview(c, Grade.good, now);
        now = c.due!;
        c = applyReview(c, Grade.again, now);
        now = c.due!;
      }
      expect(c.isLeech, isTrue);
      expect(fresh().isLeech, isFalse);
    });
  });

  group('the queue', () {
    test('learning comes before overdue, and new comes last', () {
      final learning = applyReview(fresh('a'), Grade.good, t0);
      var overdue = applyReview(fresh('b'), Grade.good, t0);
      overdue = applyReview(overdue, Grade.good, overdue.due!);
      final brandNew = fresh('c');

      final cards = [brandNew, overdue, learning]
        ..sort((x, y) => compareForQueue(x, y, t0));
      expect(cards.map((c) => c.id), ['a', 'b', 'c']);
    });

    test('the most overdue card comes first', () {
      final now = t0.add(const Duration(days: 30));
      final a = CardState(
          id: 'a', step: -1, intervalDays: 5, reps: 1,
          due: t0.add(const Duration(days: 1)));
      final b = CardState(
          id: 'b', step: -1, intervalDays: 5, reps: 1,
          due: t0.add(const Duration(days: 20)));
      final cards = [b, a]..sort((x, y) => compareForQueue(x, y, now));
      expect(cards.map((c) => c.id), ['a', 'b']);
    });

    test('ordering is stable for cards that tie', () {
      final a = fresh('word:2');
      final b = fresh('word:10');
      final one = [a, b]..sort((x, y) => compareForQueue(x, y, t0));
      final two = [b, a]..sort((x, y) => compareForQueue(x, y, t0));
      expect(one.map((c) => c.id), two.map((c) => c.id));
    });
  });

  group('counting what is due', () {
    test('new cards are rationed, reviews are not', () {
      final cards = [
        for (var i = 0; i < 500; i++) fresh('word:$i'),
      ];
      final counts = countDue(cards, t0, newPerDay: 20);
      expect(counts.newCards, 20,
          reason: 'a day that introduces 500 words produces 500 reviews a '
              'day for a fortnight');
      expect(counts.review, 0);
      expect(counts.total, 20);
    });

    test('a card not yet due is not counted', () {
      var c = applyReview(fresh(), Grade.good, t0);
      c = applyReview(c, Grade.good, c.due!);
      expect(countDue([c], t0).total, 0);
      expect(countDue([c], c.due!).total, 1);
    });

    test('suspended cards are invisible to the queue', () {
      final c = fresh().copyWith(suspended: true);
      expect(countDue([c], t0).total, 0);
      expect(c.isDue(t0), isFalse);
    });

    test('an empty deck reports empty rather than throwing', () {
      expect(countDue(const [], t0).isEmpty, isTrue);
    });
  });

  group('previewing the buttons', () {
    test('every grade produces a distinct, sensible next date', () {
      var c = applyReview(fresh(), Grade.good, t0);
      c = applyReview(c, Grade.good, c.due!);
      final preview = previewAll(c, c.due!);

      expect(preview.keys, Grade.values.toSet());
      final again = preview[Grade.again]!.due!;
      final hard = preview[Grade.hard]!.due!;
      final good = preview[Grade.good]!.due!;
      final easy = preview[Grade.easy]!.due!;
      expect(again.isBefore(hard), isTrue);
      expect(hard.isBefore(good), isTrue);
      expect(good.isBefore(easy), isTrue);
    });

    test('previewing does not change the card', () {
      final c = applyReview(fresh(), Grade.good, t0);
      final before = c.toString();
      previewAll(c, t0);
      expect(c.toString(), before);
    });
  });
}
