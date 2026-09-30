import 'package:flutter/material.dart';

import 'app_state.dart';
import 'grammar_screen.dart';
import 'notifications.dart';
import 'practice_screens.dart';
import 'review_screen.dart';
import 'session.dart';
import 'settings_screen.dart';
import 'speech.dart';
import 'theme.dart';
import 'writing_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JlptBenkyoApp());
}

class JlptBenkyoApp extends StatelessWidget {
  const JlptBenkyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JLPT Benkyo',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _Boot(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Opens the databases before anything tries to read them.
///
/// The content database is copied out of the APK on first launch, which
/// takes a moment and can fail on a device with no space left — so it
/// happens behind a visible screen that can report the failure, rather
/// than inside a widget build that would simply go blank.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppState? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final app = await AppState.load();
      // Warmed here rather than on the listening screen, so the first tap
      // of a play button does not sit silent while the engine wakes up.
      Speech.instance.init();
      Reminders.instance.init();
      if (mounted) setState(() => _app = app);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text('The content database could not be opened.'),
                const SizedBox(height: 8),
                Text('$_error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    if (_app == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeScreen(app: _app!);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});

  final AppState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.addListener(_onChange);
  }

  @override
  void dispose() {
    app.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final summary = app.summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('JLPT Benkyo'),
        actions: [
          if (app.streak > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.local_fire_department, size: 18),
                  label: Text('${app.streak}'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(app: app),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DueCard(
              summary: summary,
              reviewedToday: app.reviewedToday,
              onStart: _startReview,
            ),
            const SizedBox(height: 24),
            Text('Practice', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Tile(
              icon: Icons.menu_book_outlined,
              title: 'Reading',
              subtitle: 'Graded sentences, tap a word to look it up',
              onTap: () => _push(ReadingScreen(app: app)),
            ),
            _Tile(
              icon: Icons.hearing_outlined,
              title: 'Listening',
              subtitle: 'Hear it first, then check what was said',
              onTap: () => _push(ListeningScreen(app: app)),
            ),
            _Tile(
              icon: Icons.mic_none_outlined,
              title: 'Speaking',
              subtitle: 'Record yourself and compare with the reference',
              onTap: () => _push(SpeakingScreen(app: app)),
            ),
            _Tile(
              icon: Icons.draw_outlined,
              title: 'Writing',
              subtitle: 'Trace kanji stroke by stroke',
              onTap: () => _push(WritingScreen(app: app)),
            ),
            _Tile(
              icon: Icons.rule_outlined,
              title: 'Grammar',
              subtitle: '${app.content.meta['grammar'] ?? '—'} points, '
                  'with real examples',
              onTap: () => _push(GrammarScreen(app: app)),
            ),
            const SizedBox(height: 24),
            Text('Progress', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final kind in CardKind.values)
              _ProgressRow(kind: kind, progress: app.progress(kind)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => app.refresh());
  }

  Future<void> _startReview() async {
    final queue = app.buildSession();
    if (queue.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewScreen(app: app, queue: queue),
    ));
    await app.refresh();
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.summary,
    required this.reviewedToday,
    required this.onStart,
  });

  final SessionSummary summary;
  final int reviewedToday;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.isEmpty)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      reviewedToday > 0
                          ? 'Done for today — $reviewedToday reviewed.'
                          : 'Nothing due right now.',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              )
            else ...[
              Text('Due now', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Count('${summary.learning}', 'learning', gradeColour(1)),
                  _Count('${summary.review}', 'review', gradeColour(2)),
                  _Count('${summary.newCards}', 'new', gradeColour(3)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onStart,
                  child: Text('Study ${summary.total}'),
                ),
              ),
            ],
            if (summary.deferred > 0) ...[
              const SizedBox(height: 12),
              Text(
                // Said out loud rather than hidden. Someone back from a
                // fortnight away should know there is a backlog and that
                // it is being fed to them gradually, not conclude the app
                // lost their deck.
                '${summary.deferred} more are overdue and will come in over '
                'the next few days.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, this.colour);

  final String value, label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w600, color: colour)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.kind, required this.progress});

  final CardKind kind;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      CardKind.word => 'Vocabulary',
      CardKind.kanji => 'Kanji',
      CardKind.grammar => 'Grammar',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${progress.learned} / ${progress.total}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: progress.fraction, minHeight: 8),
          ),
        ],
      ),
    );
  }
}
