/// Writing practice: trace a kanji, one stroke at a time.
///
/// KanjiVG gives the strokes in the order a person actually writes them,
/// which is the whole value — stroke order is not decoration, it is what
/// makes handwriting legible and what a dictionary lookup by hand
/// depends on. The exercise is therefore ordered: the next stroke is the
/// only one you can draw, and the guide shows exactly where it starts.
///
/// What it does not do is grade your handwriting. It checks that you
/// drew roughly the right stroke in roughly the right place, in the
/// right order — which is what stroke-order practice is for — and leaves
/// the aesthetics alone.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'content.dart';
import 'theme.dart';

/// KanjiVG draws on a 109-unit square.
const double kKanjiVgSize = 109;

/// How far a drawn stroke may be from the model and still count.
///
/// Generous on purpose, and in KanjiVG units so it scales with the
/// canvas. This is not a handwriting exam: a stroke that is recognisably
/// the right stroke in the right place should pass, because the thing
/// being practised is which stroke comes next, not penmanship.
const double kStrokeTolerance = 22;

class WritingScreen extends StatefulWidget {
  const WritingScreen({super.key, required this.app});

  final AppState app;

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen> {
  List<Kanji> _kanji = const [];
  int _index = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.app.content.kanji(
      minLevel: widget.app.settings.minLevel,
    );
    // Only characters that actually have stroke data. Offering a writing
    // exercise with nothing to trace is worse than not listing it.
    final usable = [for (final k in all) if (k.strokePaths.isNotEmpty) k];
    if (!mounted) return;
    setState(() {
      _kanji = usable;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Writing')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_kanji.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Writing')),
        body: const Center(child: Text('No kanji with stroke data.')),
      );
    }

    final kanji = _kanji[_index];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${_index + 1} / ${_kanji.length}'),
            ),
          ),
        ],
      ),
      body: _TracePad(
        key: ValueKey(kanji.id),
        kanji: kanji,
        onNext: () => setState(
            () => _index = (_index + 1) % _kanji.length),
        onPrevious: () => setState(() =>
            _index = (_index - 1 + _kanji.length) % _kanji.length),
      ),
    );
  }
}

class _TracePad extends StatefulWidget {
  const _TracePad({
    super.key,
    required this.kanji,
    required this.onNext,
    required this.onPrevious,
  });

  final Kanji kanji;
  final VoidCallback onNext, onPrevious;

  @override
  State<_TracePad> createState() => _TracePadState();
}

class _TracePadState extends State<_TracePad> {
  /// Strokes already accepted, in KanjiVG coordinates.
  final List<List<Offset>> _done = [];

  /// The stroke under the finger.
  List<Offset> _current = [];

  bool _showGuide = true;
  bool _lastWasWrong = false;

  /// The model strokes, flattened to point lists once. Parsing the path
  /// data on every frame would be visible on a character with twenty
  /// strokes under a moving finger.
  late final List<List<Offset>> _model = [
    for (final d in widget.kanji.strokePaths) _flatten(d),
  ];

  int get _next => _done.length;
  bool get _complete => _next >= _model.length;

  void _finishStroke() {
    if (_current.length < 2 || _complete) {
      setState(() => _current = []);
      return;
    }

    final ok = _matches(_current, _model[_next]);
    setState(() {
      if (ok) {
        _done.add(_current);
        _lastWasWrong = false;
      } else {
        _lastWasWrong = true;
      }
      _current = [];
    });
  }

  /// Whether a drawn stroke is the model stroke.
  ///
  /// Three checks, all of which have to pass, and all of them deliberately
  /// loose:
  ///
  /// - it starts near where the model starts, which is the half of
  ///   stroke order that direction actually encodes;
  /// - it ends near where the model ends;
  /// - every point along it stays within tolerance of the model line, so
  ///   a stroke that starts and ends right but loops through the middle
  ///   of the character does not pass.
  ///
  /// Comparing shapes any more strictly than this turns a stroke-order
  /// exercise into a handwriting exam, which is not what it is for.
  static bool _matches(List<Offset> drawn, List<Offset> model) {
    if (model.length < 2) return true;

    final start = (drawn.first - model.first).distance;
    final end = (drawn.last - model.last).distance;
    if (start > kStrokeTolerance || end > kStrokeTolerance) return false;

    for (final p in drawn) {
      if (_distanceToPolyline(p, model) > kStrokeTolerance) return false;
    }
    return true;
  }

  static double _distanceToPolyline(Offset p, List<Offset> line) {
    var best = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      final d = _distanceToSegment(p, line[i], line[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  /// Flattens SVG path data into a polyline.
  ///
  /// KanjiVG uses only moves and cubic curves, so this handles `M`, `m`,
  /// `C`, `c`, `S` and `s` and nothing else — deliberately, because
  /// silently accepting a command it cannot draw would produce a stroke
  /// that fails every comparison for no visible reason.
  static List<Offset> _flatten(String d, {int perCurve = 12}) {
    final out = <Offset>[];
    // Any letter counts as a command, not just the ones handled below.
    // Matching only the known ones lets an unsupported command fall
    // through as if it were not there, and its numbers are then eaten by
    // whichever command was still active — producing a stroke built from
    // misread coordinates rather than a short one.
    final tokens = RegExp(r'[A-Za-z]|-?\d*\.?\d+')
        .allMatches(d)
        .map((m) => m.group(0)!)
        .toList();

    var i = 0;
    var cursor = Offset.zero;
    var lastControl = Offset.zero;
    String? command;

    // Truncated path data must end the stroke, not throw. These files
    // are third-party and one malformed character should cost that
    // character, not the screen.
    var ranOut = false;
    double num_() {
      if (i >= tokens.length) {
        ranOut = true;
        return 0;
      }
      return double.parse(tokens[i++]);
    }

    while (i < tokens.length) {
      final t = tokens[i];
      if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
        command = t;
        i++;
      }
      if (command == null) break;

      switch (command) {
        case 'M':
        case 'm':
          final x = num_(), y = num_();
          if (ranOut) return out;
          cursor = command == 'M' ? Offset(x, y) : cursor + Offset(x, y);
          lastControl = cursor;
          out.add(cursor);
          // A repeated coordinate pair after a move is an implicit
          // lineto in SVG, so the command degrades rather than repeating
          // the move.
          command = command == 'M' ? 'L' : 'l';

        case 'L':
        case 'l':
          final x = num_(), y = num_();
          if (ranOut) return out;
          cursor = command == 'L' ? Offset(x, y) : cursor + Offset(x, y);
          lastControl = cursor;
          out.add(cursor);

        case 'C':
        case 'c':
          final rel = command == 'c';
          final c1 = _pt(num_(), num_(), cursor, rel);
          final c2 = _pt(num_(), num_(), cursor, rel);
          final end = _pt(num_(), num_(), cursor, rel);
          if (ranOut) return out;
          _cubic(out, cursor, c1, c2, end, perCurve);
          lastControl = c2;
          cursor = end;

        case 'S':
        case 's':
          final rel = command == 's';
          // The reflected control point — what makes a smooth curve
          // smooth. Treating it as the cursor instead puts a visible
          // kink in every stroke that uses one.
          final c1 = cursor * 2 - lastControl;
          final c2 = _pt(num_(), num_(), cursor, rel);
          final end = _pt(num_(), num_(), cursor, rel);
          if (ranOut) return out;
          _cubic(out, cursor, c1, c2, end, perCurve);
          lastControl = c2;
          cursor = end;

        case 'Z':
        case 'z':
          if (out.isNotEmpty) out.add(out.first);

        default:
          // An unknown command means the rest of this path cannot be
          // trusted. Stopping returns a short stroke rather than a
          // scrambled one.
          return out;
      }
    }
    return out;
  }

  static Offset _pt(double x, double y, Offset cursor, bool relative) =>
      relative ? cursor + Offset(x, y) : Offset(x, y);

  static void _cubic(List<Offset> out, Offset p0, Offset p1, Offset p2,
      Offset p3, int steps) {
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final u = 1 - t;
      out.add(Offset(
        u * u * u * p0.dx +
            3 * u * u * t * p1.dx +
            3 * u * t * t * p2.dx +
            t * t * t * p3.dx,
        u * u * u * p0.dy +
            3 * u * u * t * p1.dy +
            3 * u * t * t * p2.dy +
            t * t * t * p3.dy,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kanji = widget.kanji;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kanji.meanings.take(3).join(', '),
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${kanji.strokes} strokes · '
                      '${levelName(kanji.level)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _showGuide ? 'Hide the guide' : 'Show the guide',
                icon: Icon(_showGuide
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _showGuide = !_showGuide),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  final scale = side / kKanjiVgSize;

                  Offset toModel(Offset local) => local / scale;

                  return GestureDetector(
                    onPanStart: (d) => setState(() {
                      _current = [toModel(d.localPosition)];
                      _lastWasWrong = false;
                    }),
                    onPanUpdate: (d) =>
                        setState(() => _current.add(toModel(d.localPosition))),
                    onPanEnd: (_) => _finishStroke(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: CustomPaint(
                        size: Size.square(side),
                        painter: _KanjiPainter(
                          model: _model,
                          done: _done,
                          current: _current,
                          nextIndex: _next,
                          showGuide: _showGuide,
                          scale: scale,
                          colours: Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _complete
                ? 'Complete — ${_model.length} strokes.'
                : _lastWasWrong
                    ? 'Not that one. The next stroke starts at the green dot.'
                    : 'Stroke ${_next + 1} of ${_model.length}',
            style: TextStyle(
              color: _lastWasWrong
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: widget.onPrevious,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear'),
                    onPressed: () => setState(() {
                      _done.clear();
                      _current = [];
                      _lastWasWrong = false;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.onNext,
                    child: const Text('Next kanji'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KanjiPainter extends CustomPainter {
  _KanjiPainter({
    required this.model,
    required this.done,
    required this.current,
    required this.nextIndex,
    required this.showGuide,
    required this.scale,
    required this.colours,
  });

  final List<List<Offset>> model;
  final List<List<Offset>> done;
  final List<Offset> current;
  final int nextIndex;
  final bool showGuide;
  final double scale;
  final ColorScheme colours;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    // Quarter guides. Kanji are built on a square and the proportions are
    // most of what makes one legible, so the grid is doing real work
    // rather than decorating.
    final grid = Paint()
      ..color = colours.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 0.5 / scale;
    const half = kKanjiVgSize / 2;
    canvas.drawLine(const Offset(half, 0),
        const Offset(half, kKanjiVgSize), grid);
    canvas.drawLine(const Offset(0, half),
        const Offset(kKanjiVgSize, half), grid);

    if (showGuide) {
      final faint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colours.outlineVariant.withValues(alpha: 0.55);
      for (var i = nextIndex; i < model.length; i++) {
        _drawPolyline(canvas, model[i], faint);
      }
    }

    final written = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colours.onSurface;
    for (final stroke in done) {
      _drawPolyline(canvas, stroke, written);
    }

    if (current.isNotEmpty) {
      _drawPolyline(
        canvas,
        current,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = colours.primary,
      );
    }

    // Where the next stroke begins. The single most useful thing on the
    // screen: stroke order is mostly a question of which end you start
    // from, and a guide that shows the shape without showing the start
    // teaches the wrong half of it.
    if (!showGuide || nextIndex >= model.length) {
      canvas.restore();
      return;
    }
    final start = model[nextIndex].first;
    canvas.drawCircle(start, 3.5, Paint()..color = const Color(0xFF43A047));

    canvas.restore();
  }

  void _drawPolyline(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      if (points.length == 1) {
        canvas.drawCircle(points.first, paint.strokeWidth / 2,
            Paint()..color = paint.color);
      }
      return;
    }
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_KanjiPainter old) =>
      old.done.length != done.length ||
      old.current.length != current.length ||
      old.showGuide != showGuide ||
      old.nextIndex != nextIndex ||
      old.scale != scale;
}

/// Exposed for tests: the SVG flattener and the stroke comparison are the
/// two pieces here worth pinning down, and both are pure.
List<Offset> flattenKanjiPath(String d, {int perCurve = 12}) =>
    _TracePadState._flatten(d, perCurve: perCurve);

bool strokeMatches(List<Offset> drawn, List<Offset> model) =>
    _TracePadState._matches(drawn, model);

/// A straight line between two points, sampled — what a test needs to
/// stand in for a finger drawing a stroke.
List<Offset> sampleLine(Offset a, Offset b, int steps) => [
      for (var i = 0; i <= steps; i++)
        Offset(
          a.dx + (b.dx - a.dx) * i / steps,
          a.dy + (b.dy - a.dy) * i / steps,
        ),
    ];
