/// The two pure pieces of the writing exercise: turning KanjiVG path data
/// into a polyline, and deciding whether a drawn stroke is the right one.
///
/// Both are worth pinning down here rather than discovering on a tablet.
/// A flattener that silently mishandles a curve produces a model stroke
/// in the wrong place, and every attempt at it then fails for no visible
/// reason — which reads as the app being broken rather than the parser.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jlptbenkyo/writing_screen.dart';

void main() {
  group('flattening stroke paths', () {
    test('a move and a line give their endpoints', () {
      final pts = flattenKanjiPath('M10,20L30,40');
      expect(pts.first, const Offset(10, 20));
      expect(pts.last, const Offset(30, 40));
    });

    test('a cubic is sampled along its length, not just its ends', () {
      final pts = flattenKanjiPath('M0,0C0,50 100,50 100,0', perCurve: 8);
      expect(pts.first, const Offset(0, 0));
      expect(pts.last.dx, closeTo(100, 0.001));
      expect(pts.last.dy, closeTo(0, 0.001));
      expect(pts.length, 9, reason: 'start plus one point per step');
      // The curve bulges downward, so the middle must not sit on the
      // straight line between the endpoints.
      expect(pts[4].dy, greaterThan(10));
    });

    test('relative commands accumulate from the cursor', () {
      final absolute = flattenKanjiPath('M10,10C10,20 20,20 20,10');
      final relative = flattenKanjiPath('M10,10c0,10 10,10 10,0');
      expect(relative.last.dx, closeTo(absolute.last.dx, 0.001));
      expect(relative.last.dy, closeTo(absolute.last.dy, 0.001));
    });

    test('a smooth curve reflects its previous control point', () {
      // The thing this guards: treating the reflected control point as
      // the cursor puts a visible kink at every S command, and KanjiVG
      // uses them throughout.
      final withS = flattenKanjiPath('M0,0C10,10 20,10 30,0S50,-10 60,0');
      final explicit =
          flattenKanjiPath('M0,0C10,10 20,10 30,0C40,-10 50,-10 60,0');
      expect(withS.last.dx, closeTo(explicit.last.dx, 0.001));
      for (var i = 0; i < withS.length; i++) {
        expect(withS[i].dy, closeTo(explicit[i].dy, 0.001));
      }
    });

    test('an unsupported command stops rather than scrambling', () {
      // Returning a short stroke is recoverable; returning a stroke built
      // from misread numbers is a model in the wrong place.
      final pts = flattenKanjiPath('M0,0L10,10A5,5 0 0 1 20,20');
      expect(pts, hasLength(2));
    });

    test('empty data is an empty list, not a crash', () {
      expect(flattenKanjiPath(''), isEmpty);
    });

    test('real KanjiVG data flattens to something sane', () {
      // The first stroke of 一, as KanjiVG actually writes it.
      final pts = flattenKanjiPath(
          'M17.75,52.13c1.62,0.37,4.59,0.44,6.21,0.37c12.79-0.5,50.29-4,'
          '66.15-4.12c2.7-0.02,4.32,0.18,5.67,0.36');
      expect(pts.length, greaterThan(10));
      expect(pts.first.dx, closeTo(17.75, 0.01));
      // A horizontal stroke: it travels far across and barely at all down.
      expect(pts.last.dx - pts.first.dx, greaterThan(50));
      expect((pts.last.dy - pts.first.dy).abs(), lessThan(10));
    });
  });

  group('deciding whether a stroke counts', () {
    final model = sampleLine(const Offset(20, 20), const Offset(80, 20), 20);

    test('tracing it accurately passes', () {
      expect(strokeMatches(model, model), isTrue);
    });

    test('a wobbly but recognisable stroke passes', () {
      // The point of the exercise is stroke order, not penmanship.
      final wobbly = [
        for (var i = 0; i < model.length; i++)
          Offset(model[i].dx, model[i].dy + (i.isEven ? 6 : -6)),
      ];
      expect(strokeMatches(wobbly, model), isTrue);
    });

    test('drawing it backwards fails', () {
      // Direction is half of what stroke order actually encodes, so a
      // right-to-left horizontal must not count.
      expect(strokeMatches(model.reversed.toList(), model), isFalse);
    });

    test('a stroke in the wrong place fails', () {
      final elsewhere =
          sampleLine(const Offset(20, 90), const Offset(80, 90), 20);
      expect(strokeMatches(elsewhere, model), isFalse);
    });

    test('right endpoints but a wandering path fails', () {
      // Starting and ending correctly is not enough — otherwise a loop
      // through the middle of the character would pass.
      final detour = [
        const Offset(20, 20),
        const Offset(50, 95),
        const Offset(80, 20),
      ];
      expect(strokeMatches(detour, model), isFalse);
    });

    test('a stroke that stops half way fails', () {
      final short =
          sampleLine(const Offset(20, 20), const Offset(45, 20), 10);
      expect(strokeMatches(short, model), isFalse);
    });

    test('a degenerate model accepts anything rather than blocking', () {
      // A one-point model stroke cannot be compared against. Refusing
      // every attempt would strand the exercise on that character with
      // no way forward.
      expect(strokeMatches(model, [const Offset(5, 5)]), isTrue);
    });
  });
}
