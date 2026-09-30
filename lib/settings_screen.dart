/// Settings, statistics and where the content came from.
///
/// The two numbers at the top are the only ones that decide whether this
/// deck stays usable, so they are the first thing here and they say what
/// they cost rather than just what they are.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'session.dart';
import 'speech.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get app => widget.app;

  late StudySettings _draft = app.settings;
  List<int> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final counts = await app.store.dailyCounts(30, DateTime.now());
    if (mounted) setState(() => _history = counts);
  }

  Future<void> _apply(StudySettings next) async {
    setState(() => _draft = next);
    await app.updateSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final meta = app.content.meta;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Heading('Daily load'),
          // Continuous, not stepped. The right number is found by living
          // with it for a week and nudging — and a stepped control always
          // stops just past the value you were heading for.
          _NumberSlider(
            label: 'New cards per day',
            value: _draft.newPerDay.toDouble(),
            min: 0,
            max: 60,
            help: 'Every new card becomes roughly ten reviews spread over '
                'the following months. This is the setting that decides '
                'whether the deck stays manageable.',
            onChanged: (v) => _apply(_draft.copyWith(newPerDay: v.round())),
          ),
          _NumberSlider(
            label: 'Review ceiling',
            value: _draft.maxReviewsPerDay.toDouble(),
            min: 20,
            max: 400,
            help: 'A cap on a day\'s reviews, so a fortnight away does not '
                'come back as six hundred cards at once. Nothing is lost — '
                'the most overdue come first and the rest follow.',
            onChanged: (v) =>
                _apply(_draft.copyWith(maxReviewsPerDay: v.round())),
          ),

          const SizedBox(height: 16),
          _Heading('What to study'),
          _LevelPicker(
            value: _draft.minLevel,
            onChanged: (v) => _apply(_draft.copyWith(minLevel: v)),
          ),
          SwitchListTile(
            title: const Text('Vocabulary'),
            subtitle: Text('${meta['words'] ?? '—'} words'),
            value: _draft.includeWords,
            onChanged: (v) => _apply(_draft.copyWith(includeWords: v)),
          ),
          SwitchListTile(
            title: const Text('Kanji'),
            subtitle: Text('${meta['kanji'] ?? '—'} characters'),
            value: _draft.includeKanji,
            onChanged: (v) => _apply(_draft.copyWith(includeKanji: v)),
          ),
          SwitchListTile(
            title: const Text('Grammar'),
            subtitle: Text('${meta['grammar'] ?? '—'} points'),
            value: _draft.includeGrammar,
            onChanged: (v) => _apply(_draft.copyWith(includeGrammar: v)),
          ),

          const SizedBox(height: 16),
          _Heading('Reminder'),
          _ReminderTile(app: app),

          const SizedBox(height: 16),
          _Heading('Speech'),
          _SpeechRate(),

          const SizedBox(height: 16),
          _Heading('Last 30 days'),
          _HistoryChart(counts: _history),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Streak: ${app.streak} day${app.streak == 1 ? '' : 's'} · '
              '${app.reviewedToday} reviewed today',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),

          const SizedBox(height: 24),
          _Heading('Where this comes from'),
          const _Attribution(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Dictionary ${meta['jmdict'] ?? 'unknown'} · '
              '${meta['sentences'] ?? '—'} sentence pairs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );
}

class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.help,
    required this.onChanged,
  });

  final String label, help;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${value.round()}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Text(help, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Levels included'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5, label: Text('N5–N3')),
              ButtonSegment(value: 4, label: Text('N4–N3')),
              ButtonSegment(value: 3, label: Text('N3 only')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const SizedBox(height: 6),
          Text(
            'Narrowing this hides earlier material rather than deleting '
            'anything — progress on it is kept.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatefulWidget {
  const _ReminderTile({required this.app});

  final AppState app;

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  @override
  Widget build(BuildContext context) {
    final at = widget.app.reminderAt;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Daily reminder'),
          subtitle: Text(at == null
              ? 'Off'
              : 'Every day at $at'),
          value: at != null,
          onChanged: (on) async {
            if (!on) {
              await widget.app.setReminder(null, null);
              return;
            }
            await _pick();
          },
        ),
        if (at != null)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Change the time'),
            onTap: _pick,
          ),
      ],
    );
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 20, minute: 0),
      helpText: 'Remind me at',
    );
    if (picked == null) return;

    final ok = await widget.app.setReminder(picked.hour, picked.minute);
    if (ok || !mounted) return;
    // Said explicitly. A reminder that silently never fires because the
    // permission was refused is worse than one that was never set.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
        'Android refused the notification permission, so the reminder '
        'cannot be set. Allow notifications for this app in system '
        'settings and try again.',
      ),
    ));
    setState(() {});
  }
}

class _SpeechRate extends StatefulWidget {
  @override
  State<_SpeechRate> createState() => _SpeechRateState();
}

class _SpeechRateState extends State<_SpeechRate> {
  @override
  Widget build(BuildContext context) {
    final voice = Speech.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Speaking rate'),
            Text(voice.rate.toStringAsFixed(2)),
          ],
        ),
        Slider(
          value: voice.rate,
          min: 0.2,
          max: 0.9,
          onChanged: (v) => setState(() => voice.setRate(v)),
        ),
        if (voice.problem == VoiceProblem.noJapaneseVoice)
          Text(
            'No Japanese voice is installed on this device. Add one in '
            'Android\'s text-to-speech settings.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton.icon(
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('Test'),
          onPressed: () => Speech.instance.say('日本語の練習をしましょう。'),
        ),
      ],
    );
  }
}

/// Thirty days of review counts.
///
/// A plain bar chart rather than a streak flame or a badge: the useful
/// question is "am I keeping up", and the shape of the last month answers
/// it in a way a single number cannot.
class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const SizedBox(height: 80);
    }
    final peak = counts.fold(1, (a, b) => a > b ? a : b);
    final colour = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final c in counts)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  // A day with nothing still draws a sliver, so the gaps
                  // are visible as gaps rather than as the chart ending.
                  height: c == 0 ? 2 : 4 + 72 * c / peak,
                  decoration: BoxDecoration(
                    color: c == 0
                        ? Theme.of(context).colorScheme.outlineVariant
                        : colour,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Word lists from open-anki-jlpt-decks (MIT).', style: style),
        Text('Kanji levels and readings from kanji-data (MIT).',
            style: style),
        Text(
          'Dictionary entries and example sentences from JMdict and the '
          'Tatoeba corpus, via jmdict-simplified — © the Electronic '
          'Dictionary Research and Development Group, CC BY-SA 4.0.',
          style: style,
        ),
        Text(
          'Stroke order from KanjiVG, © Ulrich Apel, CC BY-SA 3.0.',
          style: style,
        ),
        const SizedBox(height: 8),
        Text(
          'Grammar explanations are written for this app. Their example '
          'sentences are drawn from the same corpus.',
          style: style,
        ),
      ],
    );
  }
}
