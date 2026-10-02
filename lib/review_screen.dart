/// The review session.
///
/// One queue holding all three kinds of card, because that is how recall
/// actually gets tested — you do not know in advance whether the next
/// thing you meet in a sentence is a word, a character or a structure,
/// and a deck that groups them lets you answer from context rather than
/// from memory.
///
/// The question side shows as little as possible and the answer side
/// shows everything, including what the item connects to. That asymmetry
/// is the point: a flashcard that shows the answer alongside the question
/// tests nothing, and one that never shows the connections teaches a word
/// in isolation from the language it belongs to.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'content.dart';
import 'session.dart';
import 'speech.dart';
import 'srs.dart';
import 'theme.dart';
import 'writing_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.app, required this.queue});

  final AppState app;
  final List<CardState> queue;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<CardState> _queue = [...widget.queue];
  int _index = 0;
  bool _revealed = false;
  int _answered = 0;

  CardState? get _current => _index < _queue.length ? _queue[_index] : null;

  Future<void> _grade(Grade grade) async {
    final card = _current;
    if (card == null) return;

    final next = await widget.app.answer(card, grade);
    _answered++;

    // A card still in learning comes back in this same session rather
    // than tomorrow — that is what the one- and ten-minute steps are
    // for, and dropping it from the queue would quietly turn the
    // learning steps off.
    setState(() {
      _queue.removeAt(_index);
      if (next.step >= 0) {
        // Far enough back that a handful of other cards come between,
        // near enough that the session does not end before it returns.
        final insertAt = (_index + 6).clamp(0, _queue.length);
        _queue.insert(insertAt, next);
      }
      if (_index >= _queue.length) _index = 0;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = _current;
    if (card == null) return _done(context);

    final total = _queue.length + _answered;
    return Scaffold(
      appBar: AppBar(
        title: Text('$_answered / $total'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : _answered / total,
            minHeight: 4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Suspend this card',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: () async {
              await widget.app.suspend(card);
              setState(() {
                _queue.removeAt(_index);
                if (_index >= _queue.length) _index = 0;
                _revealed = false;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _CardFace(
              app: widget.app,
              card: card,
              revealed: _revealed,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _revealed
                  ? _GradeRow(card: card, onGrade: _grade)
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => setState(() => _revealed = true),
                        child: const Text('Show answer'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _done(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Done')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 64),
            const SizedBox(height: 16),
            Text('$_answered reviewed',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four answers, each labelled with where the card actually lands.
///
/// Showing the resulting interval on the button is what makes the
/// scheduler legible rather than mysterious, and it costs nothing because
/// the scheduler is pure — the preview is the real calculation, not an
/// estimate of it.
class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.card, required this.onGrade});

  final CardState card;
  final void Function(Grade) onGrade;

  @override
  Widget build(BuildContext context) {
    final preview = previewAll(card, DateTime.now());
    const labels = ['Again', 'Hard', 'Good', 'Easy'];

    return Row(
      children: [
        for (var i = 0; i < Grade.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: gradeColour(i),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => onGrade(Grade.values[i]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labels[i]),
                  Text(
                    _when(preview[Grade.values[i]]!),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _when(CardState s) {
    final due = s.due;
    if (due == null) return '';
    final minutes = due.difference(DateTime.now()).inMinutes;
    if (minutes < 60) return '${minutes < 1 ? 1 : minutes}m';
    final days = s.step >= 0 ? 0 : s.intervalDays;
    if (days == 0) return '${(minutes / 60).round()}h';
    if (days < 30) return '${days}d';
    if (days < 365) return '${(days / 30).round()}mo';
    return '${(days / 365).toStringAsFixed(1)}y';
  }
}

/// Loads and lays out whichever kind of card this is.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.app,
    required this.card,
    required this.revealed,
  });

  final AppState app;
  final CardState card;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(card.id);
    final id = idOf(card.id);
    if (kind == null || id == null) {
      // A progress row for a card type this build does not know. Skipped
      // rather than fatal, the same way an unknown field is on the way in.
      return const Center(child: Text('Unknown card'));
    }

    return FutureBuilder<Widget>(
      key: ValueKey('${card.id}:$revealed'),
      future: _build(context, kind, id),
      builder: (context, snap) => snap.data ??
          const Center(child: CircularProgressIndicator()),
    );
  }

  Future<Widget> _build(BuildContext context, CardKind kind, int id) async {
    switch (kind) {
      case CardKind.word:
        final word = await app.content.word(id);
        if (word == null) return const Center(child: Text('Missing word'));
        final sentences = revealed
            ? await app.content.sentencesForWord(id, limit: 2)
            : const <Sentence>[];
        return _WordFace(
            app: app,
            word: word,
            revealed: revealed,
            sentences: sentences);

      case CardKind.kanji:
        final kanji = await app.content.kanjiById(id);
        if (kanji == null) return const Center(child: Text('Missing kanji'));
        final words = revealed
            ? await app.content.wordsWithKanji(id, limit: 6)
            : const <Word>[];
        return _KanjiFace(kanji: kanji, revealed: revealed, words: words);

      case CardKind.grammar:
        final point = await app.content.grammarById(id);
        if (point == null) {
          return const Center(child: Text('Missing grammar point'));
        }
        final sentences = revealed
            ? await app.content.sentencesForGrammar(id, limit: 2)
            : const <Sentence>[];
        return _GrammarFace(
            point: point, revealed: revealed, sentences: sentences);
    }
  }
}

Widget _levelChip(int level) => Chip(
      label: Text(levelName(level)),
      backgroundColor: levelColour(level).withValues(alpha: 0.15),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );

class _WordFace extends StatelessWidget {
  const _WordFace({
    required this.app,
    required this.word,
    required this.revealed,
    required this.sentences,
  });

  final AppState app;
  final Word word;
  final bool revealed;
  final List<Sentence> sentences;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Center(child: _levelChip(word.level)),
        const SizedBox(height: 16),
        Center(
          child: Text(word.expression,
              style: Jp.word, textAlign: TextAlign.center),
        ),
        if (revealed) ...[
          const SizedBox(height: 12),
          // The reading is only worth showing when it differs from the
          // written form. A word written in kana already shows it, and a
          // card that repeats itself looks like a bug.
          if (word.hasKanji)
            Center(
              child: Text(word.reading,
                  style: Jp.reading.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
            ),
          const SizedBox(height: 20),
          Center(
            child: Text(word.meaning,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
          ),
          if (word.pos != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(word.pos!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 12),
          Center(child: _SpeakButton(text: word.expression)),
          // Write the characters in the word you have just read. The
          // commonest gap at this level is knowing a word perfectly well
          // and being unable to write it, and the moment you have just
          // recalled the word is when the character means the most.
          if (word.hasKanji) _WriteTheKanji(app: app, word: word),
          for (final s in sentences) _SentenceTile(sentence: s),
        ],
      ],
    );
  }
}

/// Tappable characters from the word just answered.
class _WriteTheKanji extends StatelessWidget {
  const _WriteTheKanji({required this.app, required this.word});

  final AppState app;
  final Word word;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Kanji>>(
      future: app.content.kanjiInText(word.expression),
      builder: (context, snap) {
        final kanji = snap.data ?? const <Kanji>[];
        // A word written only in kana, or in characters outside the
        // level range, simply shows nothing here.
        if (kanji.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Text('Write it',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                children: [
                  for (final k in kanji)
                    ActionChip(
                      label: Text(k.literal,
                          style: const TextStyle(fontSize: 26)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 10),
                      onPressed: k.strokePaths.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => KanjiTraceScreen(
                                    kanji: k,
                                    context_:
                                        '${word.expression} · ${word.reading}',
                                  ),
                                ),
                              ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanjiFace extends StatelessWidget {
  const _KanjiFace({
    required this.kanji,
    required this.revealed,
    required this.words,
  });

  final Kanji kanji;
  final bool revealed;
  final List<Word> words;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(child: _levelChip(kanji.level)),
        Center(child: Text(kanji.literal, style: Jp.character)),
        if (revealed) ...[
          Center(
            child: Text(kanji.meanings.join(', '),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          if (kanji.onYomi.isNotEmpty)
            _ReadingRow(label: 'on', readings: kanji.onYomi),
          if (kanji.kunYomi.isNotEmpty)
            _ReadingRow(label: 'kun', readings: kanji.kunYomi),
          const SizedBox(height: 8),
          Center(
            child: Text('${kanji.strokes} strokes',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          // Words are what a character is *for*. A kanji card that shows
          // only meanings and readings teaches a symbol nobody uses on
          // its own.
          if (words.isNotEmpty) ...[
            Text('Used in', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final w in words)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(w.expression, style: Jp.reading),
                subtitle: Text('${w.reading} · ${w.meaning}'),
                trailing: _SpeakButton(text: w.expression, dense: true),
              ),
          ],
        ],
      ],
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.label, required this.readings});

  final String label;
  final List<String> readings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(readings.join('、'), style: Jp.reading),
          ),
        ],
      ),
    );
  }
}

class _GrammarFace extends StatelessWidget {
  const _GrammarFace({
    required this.point,
    required this.revealed,
    required this.sentences,
  });

  final GrammarPoint point;
  final bool revealed;
  final List<Sentence> sentences;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Center(child: _levelChip(point.level)),
        const SizedBox(height: 16),
        Center(
          child: Text(point.pattern,
              style: Jp.pattern, textAlign: TextAlign.center),
        ),
        if (revealed) ...[
          const SizedBox(height: 20),
          Text(point.meaning,
              style: Theme.of(context).textTheme.titleMedium),
          if (point.formation != null) ...[
            const SizedBox(height: 12),
            Text('Formation',
                style: Theme.of(context).textTheme.labelLarge),
            Text(point.formation!),
          ],
          if (point.note != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(point.note!)),
                  ],
                ),
              ),
            ),
          ],
          for (final s in sentences) _SentenceTile(sentence: s),
        ],
      ],
    );
  }
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({required this.sentence});

  final Sentence sentence;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sentence.jp, style: Jp.sentence),
            const SizedBox(height: 8),
            Text(sentence.en,
                style: Theme.of(context).textTheme.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: _SpeakButton(text: sentence.jp, dense: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Speaks its text, and says why if it cannot.
///
/// A play button that silently does nothing is the worst outcome here —
/// a device with no Japanese voice installed is common, and it is fixable
/// in the system settings, so it is worth naming rather than hiding.
class _SpeakButton extends StatelessWidget {
  const _SpeakButton({required this.text, this.dense = false});

  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: dense ? VisualDensity.compact : null,
      icon: const Icon(Icons.volume_up_outlined),
      tooltip: 'Say it',
      onPressed: () async {
        final ok = await Speech.instance.say(text);
        if (ok || !context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            Speech.instance.problem == VoiceProblem.noJapaneseVoice
                ? 'No Japanese voice installed. Add one in Android\'s '
                    'text-to-speech settings.'
                : 'The speech engine would not start.',
          ),
        ));
      },
    );
  }
}
