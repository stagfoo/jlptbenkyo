/// Pointing practice at the deck.
///
/// The case the whole module exists for has a name throughout: you know
/// 遊ぶ, you cannot write 遊. The tests are written around that shape
/// because it is the one that would be silently wrong — a ranking that
/// looks plausible but buries the character you actually need under a
/// frequency list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jlptbenkyo/focus.dart';
import 'package:jlptbenkyo/srs.dart';

final DateTime now = DateTime(2026, 4, 1, 9);

KanjiRef kanji(int id, {int level = 3, List<int> words = const []}) =>
    KanjiRef(id: id, literal: 'X$id', level: level, wordIds: words);

/// A card answered and sitting at [interval] days.
CardState held(String id, int interval, {int lapses = 0}) => CardState(
      id: id,
      reps: 3,
      lapses: lapses,
      step: -1,
      intervalDays: interval,
      due: now.add(Duration(days: interval)),
    );

CardState overdue(String id, {int interval = 10}) => CardState(
      id: id,
      reps: 3,
      step: -1,
      intervalDays: interval,
      due: now.subtract(const Duration(days: 2)),
    );

void main() {
  group('the 遊ぶ case', () {
    // You have known the word for a month. The character is untouched.
    final asobu = kanji(1, words: [100, 101]);
    final deck = {
      'word:100': held('word:100', 30),
      'word:101': held('word:101', 25),
    };

    test('it is recognised and named', () {
      final focus = focusFor(asobu, deck, now);
      expect(focus.reason, FocusReason.knowWordNotKanji);
      expect(focus.confidentWords, 2);
      expect(focus.score, greaterThan(0));
    });

    test('it outranks a character nothing in the deck uses', () {
      final unused = kanji(2);
      final ranked = rankForWriting([unused, asobu], deck, now);
      expect(ranked.first.kanji.id, 1);
      expect(ranked.last.reason, FocusReason.notYetNeeded);
    });

    test('it outranks a commoner character you have no words for', () {
      // The whole point: frequency order would put the common one first.
      final common = kanji(2, level: 5, words: [200, 201, 202, 203]);
      final ranked = rankForWriting([common, asobu], deck, now);
      expect(ranked.first.kanji.id, 1);
    });

    test('learning the character resolves it', () {
      final learned = {...deck, 'kanji:1': held('kanji:1', 90)};
      final focus = focusFor(asobu, learned, now);
      expect(focus.reason, isNot(FocusReason.knowWordNotKanji));
      expect(focus.score, lessThan(0.2));
    });

    test('knowing the word only slightly is not the same gap', () {
      // Met the word twice this week: you do not yet "know the word", so
      // this is ordinary new material, not a gap to close.
      final shallow = {
        'word:100': held('word:100', 3),
        'word:101': held('word:101', 2),
      };
      expect(focusFor(asobu, shallow, now).reason, FocusReason.inYourWords);
    });

    test('it names the word you are surest of', () {
      final mixed = {
        'word:100': held('word:100', 4),
        'word:101': held('word:101', 40),
      };
      final focus = focusFor(asobu, mixed, now);
      expect(focus.exampleWordIds.first, 101);
    });
  });

  group('demand from the deck', () {
    test('more of your words using it means more urgency', () {
      final one = kanji(1, words: [100]);
      final several = kanji(2, words: [100, 101, 102, 103]);
      final deck = {
        for (var i = 100; i < 104; i++) 'word:$i': held('word:$i', 5),
      };
      expect(focusFor(several, deck, now).score,
          greaterThan(focusFor(one, deck, now).score));
    });

    test('it levels off rather than running away', () {
      // A linear count would let a handful of very common characters
      // crowd out everything else for weeks.
      final many = kanji(1, words: [for (var i = 0; i < 30; i++) 100 + i]);
      final deck = {
        for (var i = 0; i < 30; i++) 'word:${100 + i}': held('word:${100 + i}', 5),
      };
      expect(focusFor(many, deck, now).score, lessThanOrEqualTo(1.0));
    });

    test('words you have never answered create no demand', () {
      final k = kanji(1, words: [100, 101]);
      expect(focusFor(k, const {}, now).score, 0);
      expect(focusFor(k, const {}, now).reason, FocusReason.notYetNeeded);
    });

    test('suspended words do not count', () {
      final k = kanji(1, words: [100]);
      final deck = {
        'word:100': held('word:100', 30).copyWith(suspended: true),
      };
      expect(focusFor(k, deck, now).startedWords, 0);
    });
  });

  group('weakness', () {
    test('an untouched character is at full weakness', () {
      final k = kanji(1, words: [100]);
      final deck = {'word:100': held('word:100', 10)};
      final fresh = focusFor(k, deck, now);
      final settled =
          focusFor(k, {...deck, 'kanji:1': held('kanji:1', 120)}, now);
      expect(fresh.score, greaterThan(settled.score));
    });

    test('lapses make a character weaker than its interval suggests', () {
      final k = kanji(1, words: [100]);
      final deck = {'word:100': held('word:100', 10)};
      final clean =
          focusFor(k, {...deck, 'kanji:1': held('kanji:1', 20)}, now);
      final lapsing = focusFor(
          k, {...deck, 'kanji:1': held('kanji:1', 20, lapses: 3)}, now);
      expect(lapsing.score, greaterThan(clean.score));
    });

    test('a suspended character is dropped from the ranking entirely', () {
      final k = kanji(1, words: [100]);
      final deck = {
        'word:100': held('word:100', 30),
        'kanji:1': held('kanji:1', 5).copyWith(suspended: true),
      };
      expect(rankForWriting([k], deck, now), isEmpty);
    });
  });

  group('ordering', () {
    test('the gap comes before a merely overdue character', () {
      final gap = kanji(1, words: [100]);
      final due = kanji(2, words: [200]);
      final deck = {
        // You know this word well and cannot write its character.
        'word:100': held('word:100', 30),
        // This one you are only part-way through, so the character being
        // overdue is ordinary review rather than a gap.
        'word:200': held('word:200', 4),
        'kanji:2': overdue('kanji:2'),
      };
      final ranked = rankForWriting([due, gap], deck, now);
      expect(ranked.first.kanji.id, 1);
      expect(ranked.first.reason, FocusReason.knowWordNotKanji);
      expect(ranked[1].reason, FocusReason.dueForReview);
    });

    test('a due character you also know the word for stays a gap', () {
      // Being due does not downgrade it: the reason you cannot write it
      // is still that you learned the word and not the character.
      final k = kanji(1, words: [100]);
      final deck = {
        'word:100': held('word:100', 30),
        'kanji:1': overdue('kanji:1'),
      };
      expect(focusFor(k, deck, now).reason, FocusReason.knowWordNotKanji);
    });

    test('characters nothing uses sink but are not lost', () {
      final all = [kanji(1, words: [100]), kanji(2), kanji(3)];
      final deck = {'word:100': held('word:100', 30)};
      final ranked = rankForWriting(all, deck, now);
      expect(ranked, hasLength(3));
      expect(ranked.first.kanji.id, 1);
    });

    test('deck-only mode drops them instead', () {
      final all = [kanji(1, words: [100]), kanji(2), kanji(3)];
      final deck = {'word:100': held('word:100', 30)};
      final ranked = rankForWriting(all, deck, now, deckOnly: true);
      expect(ranked.map((f) => f.kanji.id), [1]);
    });

    test('an empty deck still gives a usable order', () {
      // A fresh install must not show an empty writing screen.
      final all = [kanji(1), kanji(2, level: 5), kanji(3, level: 4)];
      final ranked = rankForWriting(all, const {}, now);
      expect(ranked, hasLength(3));
      // Easiest first, since nothing else distinguishes them.
      expect(ranked.first.kanji.level, 5);
    });

    test('the widest gap wins when the deck wants two equally', () {
      // The refinement that matters for a real deck. 日 appears in
      // dozens of words you know and you can already write it; 遊 has
      // been sitting inside 遊ぶ since N5 and you cannot. Both score the
      // same on demand, so the gap decides.
      final common = KanjiRef(
          id: 1, literal: '日', level: 5, wordIds: [100],
          easiestWordLevel: 5);                       // gap 0
      final hidden = KanjiRef(
          id: 2, literal: '遊', level: 3, wordIds: [101],
          easiestWordLevel: 5);                       // gap 2
      final deck = {
        'word:100': held('word:100', 30),
        'word:101': held('word:101', 30),
      };
      final ranked = rankForWriting([common, hidden], deck, now);
      expect(ranked.first.kanji.literal, '遊');
    });

    test('a character with no words has no gap rather than a negative', () {
      expect(kanji(1).levelGap, 0);
    });

    test('the order is total, so two runs agree', () {
      final all = [for (var i = 1; i <= 20; i++) kanji(i)];
      final a = rankForWriting(all, const {}, now).map((f) => f.kanji.id);
      final b = rankForWriting(all.reversed.toList(), const {}, now)
          .map((f) => f.kanji.id);
      expect(a, b);
    });
  });

  group('grammar', () {
    GrammarRef g(int id, {List<int> words = const []}) =>
        GrammarRef(id: id, level: 3, wordIds: words);

    test('standing reflects the card, not the content', () {
      expect(standingFor(null, now), GrammarStanding.notStarted);
      expect(standingFor(overdue('grammar:1'), now), GrammarStanding.due);
      expect(standingFor(held('grammar:1', 5), now),
          GrammarStanding.learning);
      expect(standingFor(held('grammar:1', 200), now),
          GrammarStanding.known);
    });

    test('due points come first', () {
      final all = [g(1), g(2), g(3)];
      final deck = {'grammar:2': overdue('grammar:2')};
      expect(rankGrammar(all, deck, now).first.id, 2);
    });

    test('points you can actually read come first within a group', () {
      // A structure shown in words you know is a structure you can see;
      // one shown in words you do not is two problems at once.
      final readable = g(1, words: [100, 101]);
      final opaque = g(2, words: [200, 201]);
      final deck = {
        'word:100': held('word:100', 20),
        'word:101': held('word:101', 20),
      };
      final ranked = rankGrammar([opaque, readable], deck, now);
      expect(ranked.first.id, 1);
      expect(ranked.first.readableWords, 2);
    });

    test('a point with no linked words is handled, not divided by zero', () {
      final ranked = rankGrammar([g(1)], const {}, now);
      expect(ranked.single.score, 0);
    });

    test('an empty list is empty, not a crash', () {
      expect(rankGrammar(const [], const {}, now), isEmpty);
    });
  });
}
