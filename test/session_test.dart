/// Queue building — the rules that decide whether a deck stays usable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jlptbenkyo/session.dart';
import 'package:jlptbenkyo/srs.dart';

final DateTime t0 = DateTime.utc(2026, 1, 1, 9, 0);

List<String> ids(String kind, int n) =>
    [for (var i = 1; i <= n; i++) '$kind:$i'];

CardState dueCard(String id, {int daysOverdue = 1}) => CardState(
      id: id,
      reps: 3,
      step: -1,
      intervalDays: 10,
      due: t0.subtract(Duration(days: daysOverdue)),
    );

void main() {
  group('card ids', () {
    test('kind and number round-trip', () {
      expect(kindOf('word:12'), CardKind.word);
      expect(kindOf('kanji:3'), CardKind.kanji);
      expect(kindOf('grammar:99'), CardKind.grammar);
      expect(idOf('word:12'), 12);
    });

    test('an unknown prefix is null rather than a crash', () {
      // A progress row written by a future build with a card type this
      // one has never heard of must be skipped, not fatal.
      expect(kindOf('radical:4'), isNull);
      expect(idOf('word:notanumber'), isNull);
    });
  });

  group('the daily queue', () {
    test('a fresh deck hands out exactly the new-card ration', () {
      final q = buildQueue(ids('word', 500), {}, t0,
          settings: const StudySettings(newPerDay: 15));
      expect(q, hasLength(15));
      expect(q.every((c) => c.isNew), isTrue);
    });

    test('new cards come in the order the content offers them', () {
      // The content database orders by commonness, so taking the first n
      // is what puts 私 before 作法.
      final q = buildQueue(ids('word', 50), {}, t0,
          settings: const StudySettings(newPerDay: 3));
      expect(q.map((c) => c.id), ['word:1', 'word:2', 'word:3']);
    });

    test('due reviews come before new material', () {
      final available = ids('word', 20);
      final states = {for (final id in available.take(5)) id: dueCard(id)};
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(newPerDay: 5));
      expect(q.first.isNew, isFalse);
    });

    test('new cards are spread through the session, not bolted on', () {
      final available = ids('word', 40);
      final states = {for (final id in available.take(20)) id: dueCard(id)};
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(newPerDay: 4));

      final positions = <int>[];
      for (var i = 0; i < q.length; i++) {
        if (q[i].isNew) positions.add(i);
      }
      expect(positions, hasLength(4));
      // All four bunched at either end would mean the interleave is not
      // working: stopping half way should cost roughly half of each.
      expect(positions.first, lessThan(q.length ~/ 2));
      expect(positions.last, greaterThan(q.length ~/ 2));
    });

    test('the review ceiling caps a backlog instead of dumping it', () {
      final available = ids('word', 600);
      final states = {
        for (var i = 0; i < 600; i++)
          available[i]: dueCard(available[i], daysOverdue: 1 + i % 30),
      };
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(maxReviewsPerDay: 120, newPerDay: 0));
      expect(q, hasLength(120));
    });

    test('the most overdue cards are the ones that survive the cap', () {
      final available = ids('word', 10);
      final states = {
        for (var i = 0; i < 10; i++)
          available[i]: dueCard(available[i], daysOverdue: i + 1),
      };
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(maxReviewsPerDay: 3, newPerDay: 0));
      expect(q.map((c) => c.id), ['word:10', 'word:9', 'word:8']);
    });

    test('what was already answered today counts against the ceiling', () {
      final available = ids('word', 200);
      final states = {for (final id in available) id: dueCard(id)};
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(maxReviewsPerDay: 100, newPerDay: 0),
          reviewedToday: 60);
      expect(q, hasLength(40),
          reason: 'reopening the app must not hand out a second full day');
    });

    test('falling behind on reviews throttles new cards by itself', () {
      final available = [...ids('word', 200), ...ids('kanji', 50)];
      final states = {
        for (final id in ids('word', 200)) id: dueCard(id),
      };
      final q = buildQueue(available, states, t0,
          settings: const StudySettings(maxReviewsPerDay: 100, newPerDay: 20));
      expect(q.where((c) => c.isNew), isEmpty,
          reason: 'a full review day should leave no room for new material');
    });

    test('suspended cards never appear', () {
      final available = ids('word', 5);
      final states = {
        for (final id in available)
          id: CardState(id: id, suspended: true),
      };
      expect(buildQueue(available, states, t0), isEmpty);
    });

    test('a card not yet due is not in the queue', () {
      final available = ids('word', 3);
      final states = {
        for (final id in available)
          id: CardState(
              id: id, reps: 2, step: -1, intervalDays: 5,
              due: t0.add(const Duration(days: 5))),
      };
      expect(buildQueue(available, states, t0), isEmpty);
    });
  });

  group('choosing what to study', () {
    test('turning a kind off removes it from the queue entirely', () {
      final available = [...ids('word', 10), ...ids('kanji', 10)];
      final q = buildQueue(available, {}, t0,
          settings: const StudySettings(
              includeKanji: false, newPerDay: 20));
      expect(q.every((c) => kindOf(c.id) == CardKind.word), isTrue);
    });

    test('an unknown card kind is skipped, not fatal', () {
      final q = buildQueue(['word:1', 'radical:9'], {}, t0);
      expect(q.map((c) => c.id), ['word:1']);
    });

    test('everything off is an empty session, not a crash', () {
      final q = buildQueue(ids('word', 10), {}, t0,
          settings: const StudySettings(
              includeWords: false,
              includeKanji: false,
              includeGrammar: false));
      expect(q, isEmpty);
    });
  });

  group('the summary shown before committing', () {
    test('it agrees with the queue it describes', () {
      final available = [...ids('word', 60), ...ids('kanji', 20)];
      final states = {for (final id in ids('word', 30)) id: dueCard(id)};
      const settings = StudySettings(newPerDay: 10, maxReviewsPerDay: 100);

      final q = buildQueue(available, states, t0, settings: settings);
      final s = summarise(available, states, t0, settings: settings);
      expect(s.total, q.length);
    });

    test('a backlog is reported as deferred rather than hidden', () {
      final available = ids('word', 400);
      final states = {for (final id in available) id: dueCard(id)};
      final s = summarise(available, states, t0,
          settings: const StudySettings(maxReviewsPerDay: 120, newPerDay: 0));
      expect(s.review + s.learning, 120);
      expect(s.deferred, 280);
    });

    test('nothing due is empty, and says so', () {
      final s = summarise(const [], const {}, t0);
      expect(s.isEmpty, isTrue);
      expect(s.deferred, 0);
    });
  });

  group('progress', () {
    test('learned counts graduated cards, not cards merely seen', () {
      final available = ids('word', 4);
      final states = {
        'word:1': CardState(id: 'word:1', step: 0, due: t0, reps: 0),
        'word:2': CardState(
            id: 'word:2', step: -1, reps: 4, intervalDays: 12, due: t0),
        'word:3': CardState(id: 'word:3'),
      };
      final p = progressFor(available, states, CardKind.word);
      expect(p.total, 4);
      expect(p.seen, 2, reason: 'word:3 is unstarted, word:4 has no row');
      expect(p.learned, 1);
      expect(p.fraction, closeTo(0.25, 1e-9));
    });

    test('an empty deck reports zero rather than dividing by it', () {
      final p = progressFor(const [], const {}, CardKind.kanji);
      expect(p.fraction, 0);
    });
  });
}
