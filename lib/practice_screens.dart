/// Reading, listening and speaking.
///
/// All three draw on the same 26,000 sentence pairs, graded by the
/// hardest kanji each one contains — so "readable" means readable with
/// what you are actually studying, not readable in the abstract. They
/// share a screen file because they share that pool and the difficulty
/// control over it; the exercises themselves are genuinely different.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'content.dart';
import 'speech.dart';
import 'theme.dart';

/// The difficulty control every practice screen carries.
///
/// A slider rather than a level picker: the useful setting sits between
/// the named levels — "N4 and easier, nothing too long" is a real place
/// to study and is not any single JLPT grade.
class _Difficulty extends StatelessWidget {
  const _Difficulty({
    required this.minLevel,
    required this.maxChars,
    required this.onChanged,
  });

  final int minLevel;
  final int maxChars;
  final void Function(int minLevel, int maxChars) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Level')),
              Expanded(
                child: Slider(
                  value: minLevel.toDouble(),
                  min: 3,
                  max: 5,
                  divisions: 2,
                  label: '${levelName(minLevel)} and easier',
                  onChanged: (v) => onChanged(v.round(), maxChars),
                ),
              ),
              SizedBox(width: 44, child: Text(levelName(minLevel))),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Length')),
              Expanded(
                child: Slider(
                  value: maxChars.toDouble(),
                  min: 10,
                  max: 80,
                  onChanged: (v) => onChanged(minLevel, v.round()),
                ),
              ),
              SizedBox(width: 44, child: Text('$maxChars')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared loading of a graded batch, so the three screens cannot drift
/// apart in what "N4, short" means.
mixin _SentencePool<T extends StatefulWidget> on State<T> {
  AppState get app;

  List<Sentence> sentences = const [];
  int index = 0;
  int minLevel = 4;
  int maxChars = 40;
  int _batch = 0;
  bool loading = true;

  Future<void> loadBatch({bool next = false}) async {
    setState(() => loading = true);
    if (next) _batch++;
    final rows = await app.content.practiceSentences(
      minLevel: minLevel,
      maxChars: maxChars,
      limit: 30,
      seed: _batch,
    );
    if (!mounted) return;
    setState(() {
      sentences = rows;
      index = 0;
      loading = false;
    });
  }

  void setDifficulty(int level, int chars) {
    setState(() {
      minLevel = level;
      maxChars = chars;
    });
    loadBatch();
  }

  Sentence? get current =>
      index < sentences.length ? sentences[index] : null;

  void advance() {
    if (index + 1 < sentences.length) {
      setState(() => index++);
    } else {
      loadBatch(next: true);
    }
  }
}

// ---------------------------------------------------------------- reading

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with _SentencePool<ReadingScreen> {
  @override
  AppState get app => widget.app;

  bool _showTranslation = false;

  @override
  void initState() {
    super.initState();
    loadBatch();
  }

  @override
  Widget build(BuildContext context) {
    final sentence = current;
    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: Column(
        children: [
          _Difficulty(
            minLevel: minLevel,
            maxChars: maxChars,
            onChanged: setDifficulty,
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : sentence == null
                    ? const _Empty()
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 16),
                          // Read it first, then check. Showing the
                          // translation alongside turns reading practice
                          // into reading English.
                          SelectableText(sentence.jp, style: Jp.sentence),
                          const SizedBox(height: 24),
                          if (_showTranslation)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(sentence.en,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              icon: const Icon(Icons.translate),
                              label: const Text('Show translation'),
                              onPressed: () =>
                                  setState(() => _showTranslation = true),
                            ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _SpeakIcon(text: sentence.jp),
                              const Spacer(),
                              Text(levelName(sentence.level),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                            ],
                          ),
                        ],
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: sentence == null
                      ? null
                      : () {
                          setState(() => _showTranslation = false);
                          advance();
                        },
                  child: const Text('Next'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- listening

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key, required this.app});

  final AppState app;

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen>
    with _SentencePool<ListeningScreen> {
  @override
  AppState get app => widget.app;

  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    loadBatch();
  }

  @override
  void dispose() {
    Speech.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentence = current;
    final voice = Speech.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Listening')),
      body: Column(
        children: [
          if (!voice.available && voice.problem != null)
            _VoiceWarning(problem: voice.problem!),
          _Difficulty(
            minLevel: minLevel,
            maxChars: maxChars,
            onChanged: setDifficulty,
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : sentence == null
                    ? const _Empty()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Spacer(),
                            IconButton.filled(
                              iconSize: 64,
                              padding: const EdgeInsets.all(24),
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () =>
                                  Speech.instance.say(sentence.jp),
                            ),
                            const SizedBox(height: 12),
                            // The speed control matters more here than
                            // anywhere else: at a native rate a learner
                            // hears one continuous sound, and the point
                            // of the exercise is to pick words out of it.
                            Row(
                              children: [
                                const Icon(Icons.speed, size: 18),
                                Expanded(
                                  child: Slider(
                                    value: Speech.instance.rate,
                                    min: 0.2,
                                    max: 0.9,
                                    onChanged: (v) => setState(
                                        () => Speech.instance.setRate(v)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (_revealed) ...[
                              Text(sentence.jp, style: Jp.sentence),
                              const SizedBox(height: 16),
                              Text(sentence.en,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                            ] else
                              OutlinedButton.icon(
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Show what was said'),
                                onPressed: () =>
                                    setState(() => _revealed = true),
                              ),
                            const Spacer(),
                          ],
                        ),
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: sentence == null
                      ? null
                      : () {
                          setState(() => _revealed = false);
                          advance();
                        },
                  child: const Text('Next'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- speaking

class SpeakingScreen extends StatefulWidget {
  const SpeakingScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SpeakingScreen> createState() => _SpeakingScreenState();
}

class _SpeakingScreenState extends State<SpeakingScreen>
    with _SentencePool<SpeakingScreen> {
  @override
  AppState get app => widget.app;

  bool _recording = false;
  String? _lastPath;
  bool _micDenied = false;

  @override
  void initState() {
    super.initState();
    loadBatch();
  }

  @override
  void dispose() {
    Recorder.instance.cancel();
    Recorder.instance.stopPlayback();
    Speech.instance.stop();
    super.dispose();
  }

  Future<void> _toggleRecording(Sentence sentence) async {
    if (_recording) {
      final path = await Recorder.instance.stop();
      if (path != null) {
        await app.store.addRecording(sentence.id, path, DateTime.now());
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _lastPath = path;
        });
      }
      return;
    }

    final path = await Recorder.instance.start(sentence.id);
    if (path == null) {
      if (mounted) setState(() => _micDenied = true);
      return;
    }
    if (mounted) {
      setState(() {
        _recording = true;
        _micDenied = false;
        _lastPath = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentence = current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaking'),
        actions: [
          IconButton(
            tooltip: 'Past recordings',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RecordingsScreen(app: app),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          _Difficulty(
            minLevel: minLevel,
            maxChars: maxChars,
            onChanged: setDifficulty,
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : sentence == null
                    ? const _Empty()
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(sentence.jp, style: Jp.sentence),
                          const SizedBox(height: 8),
                          Text(sentence.en,
                              style:
                                  Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.volume_up_outlined),
                                label: const Text('Reference'),
                                onPressed: () =>
                                    Speech.instance.say(sentence.jp),
                              ),
                              const SizedBox(width: 12),
                              if (_lastPath != null)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.replay),
                                  label: const Text('Your take'),
                                  onPressed: () =>
                                      Recorder.instance.play(_lastPath!),
                                ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Center(
                            child: IconButton.filled(
                              iconSize: 56,
                              padding: const EdgeInsets.all(22),
                              style: IconButton.styleFrom(
                                backgroundColor: _recording
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                              icon: Icon(_recording ? Icons.stop : Icons.mic),
                              onPressed: () => _toggleRecording(sentence),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              _recording
                                  ? 'Recording — tap to stop'
                                  : 'Tap to record your attempt',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (_micDenied) ...[
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mic_off_outlined),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Microphone permission was refused. '
                                        'Everything else here still works.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                // Said plainly rather than implied by the
                                // absence of a score. Nothing on a device
                                // can judge a Japanese accent honestly,
                                // and a number that claimed to would be
                                // worse than none.
                                'Nothing here scores your pronunciation — '
                                'no app can do that honestly. Listen to '
                                'the reference, listen to yourself, and '
                                'judge the gap.',
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: sentence == null || _recording
                      ? null
                      : () {
                          setState(() => _lastPath = null);
                          advance();
                        },
                  child: const Text('Next'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything recorded so far, newest first.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<({int id, int sentenceId, String path, DateTime at})> _items = const [];
  final Map<int, Sentence> _sentences = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.app.store.recordings();
    // Looked up one at a time rather than joined: progress and content
    // are separate databases on separate connections, so there is no
    // join to do — and a few dozen indexed lookups cost nothing.
    for (final r in items) {
      if (_sentences.containsKey(r.sentenceId)) continue;
      final s = await widget.app.content.sentenceById(r.sentenceId);
      if (s != null) _sentences[r.sentenceId] = s;
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your recordings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Nothing recorded yet.'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final r = _items[i];
                    return ListTile(
                      leading: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => Recorder.instance.play(r.path),
                      ),
                      title: Text(
                        _sentences[r.sentenceId]?.jp ??
                            'Sentence ${r.sentenceId}',
                        style: Jp.reading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${r.at.year}-${r.at.month.toString().padLeft(2, '0')}'
                        '-${r.at.day.toString().padLeft(2, '0')} '
                        '${r.at.hour.toString().padLeft(2, '0')}:'
                        '${r.at.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await widget.app.store
                              .deleteRecording(r.id, r.path);
                          _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

// ----------------------------------------------------------------- shared

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No sentences match that setting. Try a longer length or an '
            'easier level.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _VoiceWarning extends StatelessWidget {
  const _VoiceWarning({required this.problem});

  final VoiceProblem problem;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(
        problem == VoiceProblem.noJapaneseVoice
            ? 'No Japanese voice is installed. Add one in Android\'s '
                'text-to-speech settings, then reopen this screen.'
            : 'The speech engine would not start on this device.',
        style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _SpeakIcon extends StatelessWidget {
  const _SpeakIcon({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.volume_up_outlined),
      onPressed: () => Speech.instance.say(text),
    );
  }
}
