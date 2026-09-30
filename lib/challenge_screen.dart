/// Today's challenge: a real thing to try saying, out loud, in Japanese.
///
/// The gap this fills is the one every SRS has. You can answer four
/// thousand cards correctly and still freeze at a café counter, because
/// recognising a word on a card and producing it under time pressure in
/// front of a stranger are different skills, and only one of them is
/// being practised.
///
/// So the screen is arranged as a task, not as a lesson: the goal first,
/// the steps to hit, and the phrases folded away underneath. Looking at
/// the phrases is allowed and expected — but having to open them is the
/// difference between recalling and reading.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'challenge.dart';
import 'content.dart';
import 'speech.dart';
import 'theme.dart';

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  AppState get app => widget.app;

  List<ChallengePhrase> _phrases = const [];
  List<Word> _practise = const [];
  List<GrammarPoint> _grammar = const [];
  bool _loading = true;
  bool _showPhrases = false;

  /// Which steps have been ticked off. Local to the screen and not
  /// persisted: they are a scratchpad for one attempt, and a half-ticked
  /// list restored tomorrow would be noise rather than progress.
  final Set<int> _done = {};

  String? _lastRecording;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    Recorder.instance.cancel();
    Recorder.instance.stopPlayback();
    Speech.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final pick = app.todaysChallenge;
    if (pick == null) {
      setState(() => _loading = false);
      return;
    }
    final phrases = await app.content.challengePhrases(pick.id);
    final grammar = await app.content.challengeGrammar(pick.id);
    final practise = await app.challengeWordsToPractise();
    if (!mounted) return;
    setState(() {
      _phrases = phrases;
      _practise = practise;
      _grammar = grammar;
      _loading = false;
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await Recorder.instance.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _lastRecording = path;
        });
      }
      return;
    }
    // Filed under sentence id 0: this is a whole attempt at a scenario,
    // not a reading of one sentence, so it does not belong to any.
    final path = await Recorder.instance.start(0);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission was refused.'),
        ));
      }
      return;
    }
    if (mounted) {
      setState(() {
        _recording = true;
        _lastRecording = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = app.todaysChallengeDetail;
    final pick = app.todaysChallenge;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Today\'s challenge')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (detail == null || pick == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Today\'s challenge')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No challenges are available at this level setting.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final fit = breakdown(pick, app.states);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s challenge'),
        actions: [
          if (app.challengeStreakDays > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.bolt, size: 18),
                  label: Text('${app.challengeStreakDays}'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Chip(
                label: Text(levelName(detail.level)),
                backgroundColor:
                    levelColour(detail.level).withValues(alpha: 0.15),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              if (detail.category != null)
                Text(detail.category!, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(detail.title, style: theme.textTheme.headlineSmall),
          if (detail.setting != null) ...[
            const SizedBox(height: 4),
            Text(detail.setting!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),

          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Goal',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  Text(detail.goal,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text('Steps', style: theme.textTheme.titleMedium),
          for (var i = 0; i < detail.steps.length; i++)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _done.contains(i),
              onChanged: (on) => setState(() {
                if (on == true) {
                  _done.add(i);
                } else {
                  _done.remove(i);
                }
              }),
              title: Text(detail.steps[i]),
            ),

          const SizedBox(height: 12),
          _WordsToPractise(words: _practise, fit: fit),

          const SizedBox(height: 16),
          // Folded away by default. The phrases are a safety net, and a
          // net you are already standing on is a floor — having to open
          // it is the whole difference between recalling and reading.
          Card(
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Phrases you could use'),
              subtitle: Text('${_phrases.length} · try without them first',
                  style: theme.textTheme.bodySmall),
              initiallyExpanded: _showPhrases,
              onExpansionChanged: (v) => setState(() => _showPhrases = v),
              children: [
                for (final p in _phrases)
                  ListTile(
                    title: Text(p.jp, style: Jp.reading),
                    subtitle: Text(p.en),
                    trailing: IconButton(
                      icon: const Icon(Icons.volume_up_outlined),
                      onPressed: () => Speech.instance.say(p.jp),
                    ),
                  ),
              ],
            ),
          ),

          if (_grammar.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.rule_outlined),
                title: const Text('Grammar this leans on'),
                children: [
                  for (final g in _grammar)
                    ListTile(
                      title: Text(g.pattern, style: Jp.reading),
                      subtitle: Text(g.meaning),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          _RecordRow(
            recording: _recording,
            lastPath: _lastRecording,
            onToggle: _toggleRecording,
            onPlay: () => Recorder.instance.play(_lastRecording!),
          ),

          if (detail.stretch != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.trending_up, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('If that was easy',
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Text(detail.stretch!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          if (app.challengeDoneToday)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Done today'),
              ],
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('I did it'),
              onPressed: () async {
                await app.completeChallenge();
                if (mounted) setState(() {});
              },
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              // Said plainly. Nothing here can tell whether you actually
              // said it out loud, and pretending otherwise would make the
              // streak a lie you tell yourself.
              'Nothing checks this but you.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// The words from the deck to deliberately work into today's attempt.
class _WordsToPractise extends StatelessWidget {
  const _WordsToPractise({required this.words, required this.fit});

  final List<Word> words;
  final WordBreakdown fit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (words.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Once you have some words part-way learned, they will show up '
            'here to work into the attempt.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work these in',
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
            const SizedBox(height: 2),
            Text(
              'Words you are part-way through. Getting one of these into '
              'the conversation is the point.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            for (final w in words)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.expression, style: Jp.reading),
                          Text(
                            w.hasKanji
                                ? '${w.reading} · ${w.meaning}'
                                : w.meaning,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme
                                    .colorScheme.onSecondaryContainer),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.volume_up_outlined),
                      onPressed: () => Speech.instance.say(w.expression),
                    ),
                  ],
                ),
              ),
            if (fit.total > 0)
              Text(
                'This scenario uses ${fit.total} deck words — '
                '${fit.learning} you are learning, ${fit.known} you know, '
                '${fit.unseen} not started.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.recording,
    required this.lastPath,
    required this.onToggle,
    required this.onPlay,
  });

  final bool recording;
  final String? lastPath;
  final VoidCallback onToggle, onPlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          icon: Icon(recording ? Icons.stop : Icons.mic),
          label: Text(recording ? 'Stop' : 'Record your attempt'),
          onPressed: onToggle,
        ),
        const SizedBox(width: 12),
        if (lastPath != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: const Text('Play back'),
            onPressed: onPlay,
          ),
      ],
    );
  }
}
