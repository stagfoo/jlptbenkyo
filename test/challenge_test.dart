/// Daily challenge selection.
///
/// The rules worth pinning down are the ones a user would notice being
/// wrong: the same challenge for a whole day, a different one tomorrow,
/// and not the same scenario twice in a fortnight.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jlptbenkyo/challenge.dart';
import 'package:jlptbenkyo/srs.dart';

final DateTime day1 = DateTime(2026, 3, 1, 9);
final DateTime day2 = DateTime(2026, 3, 2, 9);

ChallengeRef ref(String id, {int level = 3, List<int> words = const []}) =>
    ChallengeRef(id: id, level: level, wordIds: words);

/// A word part-way through being learned.
CardState learning(int id, {int interval = 5, int lapses = 0}) => CardState(
      id: 'word:$id',
      reps: 2,
      lapses: lapses,
      step: -1,
      intervalDays: interval,
      due: day1,
    );

/// A word long since mastered.
CardState mature(int id) => CardState(
      id: 'word:$id',
      reps: 12,
      step: -1,
      intervalDays: 200,
      due: day1,
    );

void main() {
  group('affinity', () {
    test('words in motion score, mature and unseen ones do not', () {
      final c = ref('a', words: [1, 2, 3, 4]);
      final states = {
        'word:1': learning(1),
        'word:2': learning(2),
        'word:3': mature(3),
        // word:4 has never been seen
      };
      expect(affinity(c, states), closeTo(0.5, 1e-9));
    });

    test('a deck that knows everything scores zero', () {
      final c = ref('a', words: [1, 2]);
      expect(affinity(c, {'word:1': mature(1), 'word:2': mature(2)}), 0);
    });

    test('a fresh deck scores zero — a list is not a task', () {
      expect(affinity(ref('a', words: [1, 2]), const {}), 0);
    });

    test('a challenge with no linked words sits in the middle', () {
      // Neither promoted nor buried: it is still a real task, the app
      // just has nothing to say about how it fits.
      expect(affinity(ref('a'), const {}), 0.5);
    });

    test('suspended words do not count as in motion', () {
      final c = ref('a', words: [1]);
      final states = {
        'word:1': learning(1).copyWith(suspended: true),
      };
      expect(affinity(c, states), 0);
    });
  });

  group('the breakdown shown on the screen', () {
    test('it accounts for every word exactly once', () {
      final c = ref('a', words: [1, 2, 3, 4, 5]);
      final states = {
        'word:1': learning(1),
        'word:2': learning(2),
        'word:3': mature(3),
      };
      final b = breakdown(c, states);
      expect(b.total, 5);
      expect(b.learning, 2);
      expect(b.known, 1);
      expect(b.unseen, 2);
      expect(b.learning + b.known + b.unseen, b.total);
    });
  });

  group('the daily pick', () {
    final library = [for (var i = 0; i < 20; i++) ref('c$i')];

    test('it is the same all day', () {
      final morning = pickDaily(library, const {}, DateTime(2026, 3, 1, 6));
      final evening = pickDaily(library, const {}, DateTime(2026, 3, 1, 23));
      expect(morning!.id, evening!.id);
    });

    test('it changes the next day', () {
      final a = pickDaily(library, const {}, day1);
      final b = pickDaily(library, const {}, day2);
      expect(a!.id, isNot(b!.id));
    });

    test('it does not repeat what was done recently', () {
      final done = [for (var i = 0; i < 10; i++) 'c$i'];
      for (var d = 0; d < 30; d++) {
        final pick = pickDaily(
          library,
          const {},
          day1.add(Duration(days: d)),
          recentlyDone: done,
        );
        expect(done, isNot(contains(pick!.id)));
      }
    });

    test('narrowing the level hides the easier scenarios', () {
      // The numbers run backwards to the names: N5 is level 5 and is the
      // easiest, so "N3 only" (3) must exclude the N5 scenario, not the
      // N3 one. Getting this backwards inverts the whole setting.
      final mixed = [
        ref('n5_easy', level: 5),
        ref('n3_hard', level: 3),
      ];
      for (var d = 0; d < 20; d++) {
        final narrow = pickDaily(mixed, const {},
            day1.add(Duration(days: d)), easiestLevel: 3);
        expect(narrow!.id, 'n3_hard');
      }
      // The default keeps everything.
      final anyLevel = {
        for (var d = 0; d < 20; d++)
          pickDaily(mixed, const {}, day1.add(Duration(days: d)))!.id,
      };
      expect(anyLevel, containsAll(['n5_easy', 'n3_hard']));
    });

    test('challenges matching the deck are favoured', () {
      // Twenty scenarios, one of which is built entirely from words the
      // deck is part-way through. Over a month it should come up far more
      // often than a given irrelevant one.
      final withWords = [
        ref('relevant', words: [1, 2, 3]),
        for (var i = 0; i < 19; i++) ref('other$i', words: [90 + i]),
      ];
      final states = {
        'word:1': learning(1),
        'word:2': learning(2),
        'word:3': learning(3),
      };

      var relevantDays = 0;
      for (var d = 0; d < 30; d++) {
        final pick = pickDaily(
            withWords, states, day1.add(Duration(days: d)));
        if (pick!.id == 'relevant') relevantDays++;
      }
      expect(relevantDays, greaterThan(0),
          reason: 'the best-fitting scenario must actually come up');
    });

    test('it still varies when one challenge fits best', () {
      // Ranking by fit alone would hand you the same scenario every day
      // until the deck moved.
      final withWords = [
        ref('best', words: [1, 2, 3]),
        for (var i = 0; i < 19; i++) ref('other$i'),
      ];
      final states = {
        'word:1': learning(1),
        'word:2': learning(2),
        'word:3': learning(3),
      };
      final picked = {
        for (var d = 0; d < 14; d++)
          pickDaily(withWords, states, day1.add(Duration(days: d)))!.id,
      };
      expect(picked.length, greaterThan(1));
    });

    test('an exhausted library repeats rather than offering nothing', () {
      final small = [ref('a'), ref('b')];
      final pick = pickDaily(small, const {}, day1,
          recentlyDone: const ['a', 'b']);
      expect(pick, isNotNull);
    });

    test('an empty library is null, not a crash', () {
      expect(pickDaily(const [], const {}, day1), isNull);
    });

    test('two devices on the same day agree', () {
      // Ties are broken by id so the ordering is total; otherwise the
      // same date could give different answers depending on map order.
      final shuffled = library.reversed.toList();
      expect(pickDaily(library, const {}, day1)!.id,
          pickDaily(shuffled, const {}, day1)!.id);
    });
  });

  group('words to work in', () {
    test('the challenge own words come first', () {
      final c = ref('a', words: [1, 2]);
      final states = {
        'word:1': learning(1),
        'word:2': learning(2),
        'word:9': learning(9),
      };
      final picked = wordsToPractise(c, states, day1, count: 3);
      expect(picked.take(2), containsAll([1, 2]));
    });

    test('it fills from the rest of the deck when the challenge is thin', () {
      final c = ref('a', words: [1]);
      final states = {
        'word:1': learning(1),
        for (var i = 10; i < 20; i++) 'word:$i': learning(i),
      };
      expect(wordsToPractise(c, states, day1, count: 5), hasLength(5));
    });

    test('the words you keep forgetting come first among the filler', () {
      final c = ref('a');
      final states = {
        'word:10': learning(10, lapses: 0),
        'word:11': learning(11, lapses: 5),
        'word:12': learning(12, lapses: 2),
      };
      expect(wordsToPractise(c, states, day1, count: 3), [11, 12, 10]);
    });

    test('mature and unseen words are never suggested', () {
      final c = ref('a', words: [1, 2]);
      final states = {'word:1': mature(1)};
      expect(wordsToPractise(c, states, day1), isEmpty);
    });

    test('an empty deck gives an empty list rather than throwing', () {
      expect(wordsToPractise(ref('a'), const {}, day1), isEmpty);
    });

    test('a progress row for an unknown card kind is ignored', () {
      final states = {
        'kanji:4': learning(4),
        'radical:7': learning(7),
      };
      expect(wordsToPractise(ref('a'), states, day1), isEmpty);
    });
  });

  group('the challenge streak', () {
    test('consecutive days count', () {
      final done = [
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 3),
      ];
      expect(challengeStreak(done, DateTime(2026, 3, 3, 20)), 3);
    });

    test('today being undone does not break it', () {
      // Otherwise the number reads as zero every morning.
      final done = [DateTime(2026, 3, 1), DateTime(2026, 3, 2)];
      expect(challengeStreak(done, DateTime(2026, 3, 3, 9)), 2);
    });

    test('a missed day does break it', () {
      final done = [DateTime(2026, 3, 1), DateTime(2026, 3, 4)];
      expect(challengeStreak(done, DateTime(2026, 3, 4, 20)), 1);
    });

    test('twice in one day is still one day', () {
      final done = [
        DateTime(2026, 3, 3, 9),
        DateTime(2026, 3, 3, 21),
      ];
      expect(challengeStreak(done, DateTime(2026, 3, 3, 22)), 1);
    });

    test('nothing done is zero', () {
      expect(challengeStreak(const [], day1), 0);
    });
  });
}
