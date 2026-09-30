/// Browsing the grammar points.
///
/// A reference, not a drill — the drilling happens in the review queue
/// alongside vocabulary and kanji. This is the screen for when you have
/// met a structure in the wild and want to see it done properly six
/// times, which is the thing a flashcard cannot do.
///
/// Grouped by category rather than listed flat, because N3 grammar comes
/// in families that are only confusing when met one at a time: the four
/// conditionals, the three ways of saying "because", the pair that mean
/// "thanks to" and "because of, damn it".
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'content.dart';
import 'speech.dart';
import 'theme.dart';

class GrammarScreen extends StatefulWidget {
  const GrammarScreen({super.key, required this.app});

  final AppState app;

  @override
  State<GrammarScreen> createState() => _GrammarScreenState();
}

class _GrammarScreenState extends State<GrammarScreen> {
  List<GrammarPoint> _points = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final points =
        await widget.app.content.grammar(
            easiestLevel: widget.app.settings.easiestLevel);
    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
    });
  }

  List<GrammarPoint> get _filtered {
    if (_query.isEmpty) return _points;
    final q = _query.toLowerCase();
    return [
      for (final p in _points)
        if (p.pattern.contains(_query) ||
            p.meaning.toLowerCase().contains(q) ||
            (p.category ?? '').toLowerCase().contains(q))
          p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final points = _filtered;

    // Preserving the order the query gave them, so categories stay in the
    // order the content database considers pedagogically sensible rather
    // than in alphabetical order.
    final grouped = <String, List<GrammarPoint>>{};
    for (final p in points) {
      grouped.putIfAbsent(p.category ?? 'Other', () => []).add(p);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Grammar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search patterns or meanings',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                Expanded(
                  child: points.isEmpty
                      ? const Center(child: Text('Nothing matches.'))
                      : ListView(
                          children: [
                            for (final entry in grouped.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 16, 16, 4),
                                child: Text(
                                  entry.key,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ),
                              for (final p in entry.value)
                                ListTile(
                                  title: Text(p.pattern, style: Jp.reading),
                                  subtitle: Text(
                                    p.meaning,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    levelName(p.level),
                                    style: TextStyle(
                                        color: levelColour(p.level)),
                                  ),
                                  onTap: () =>
                                      Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => GrammarDetailScreen(
                                          app: widget.app, point: p),
                                    ),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class GrammarDetailScreen extends StatelessWidget {
  const GrammarDetailScreen({
    super.key,
    required this.app,
    required this.point,
  });

  final AppState app;
  final GrammarPoint point;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(levelName(point.level))),
      body: FutureBuilder<List<Sentence>>(
        future: app.content.sentencesForGrammar(point.id),
        builder: (context, snap) {
          final sentences = snap.data ?? const <Sentence>[];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(point.pattern, style: Jp.pattern),
              const SizedBox(height: 16),
              Text(point.meaning,
                  style: Theme.of(context).textTheme.titleMedium),
              if (point.formation != null) ...[
                const SizedBox(height: 20),
                Text('Formation',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(point.formation!, style: Jp.reading),
              ],
              if (point.note != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(point.note!)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Examples',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                // Worth saying: these are not invented for the textbook.
                // Every one was written by a person and translated by a
                // person, which is why they read like Japanese rather
                // than like grammar exercises.
                'Real sentences from the Tatoeba corpus.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else
                for (final s in sentences)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.jp, style: Jp.sentence),
                          const SizedBox(height: 6),
                          Text(s.en,
                              style:
                                  Theme.of(context).textTheme.bodyMedium),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.volume_up_outlined),
                              onPressed: () => Speech.instance.say(s.jp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
