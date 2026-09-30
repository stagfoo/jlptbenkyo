/// The one object every screen reads from.
///
/// Holds the two databases, the settings, and the card states — kept in
/// memory because the whole deck is about four thousand small rows and
/// re-reading them on every card flip would make answering feel slower
/// than thinking. Writes go straight to disk; reads come from here.
library;

import 'package:flutter/foundation.dart';

import 'content.dart';
import 'notifications.dart';
import 'review_store.dart';
import 'session.dart';
import 'srs.dart';

class AppState extends ChangeNotifier {
  AppState._(this.content, this.store);

  final ContentDb content;
  final ReviewStore store;

  /// Every card id that exists, in the order the content database
  /// considers worth learning. Rebuilt when the level setting changes.
  List<String> available = const [];

  /// What is known about the cards that have been answered. A card with
  /// no entry here has never been seen.
  Map<String, CardState> states = {};

  StudySettings settings = const StudySettings();

  int reviewedToday = 0;
  int streak = 0;

  /// The daily reminder, as `HH:mm`, or null when it is off.
  String? reminderAt;

  bool loading = true;

  static Future<AppState> load() async {
    final content = await ContentDb.open();
    final store = await ReviewStore.open();
    final app = AppState._(content, store);
    await app.refresh();
    return app;
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();

    settings = StudySettings(
      newPerDay: await store.intSetting('newPerDay', 15),
      maxReviewsPerDay: await store.intSetting('maxReviewsPerDay', 120),
      minLevel: await store.intSetting('minLevel', 5),
      includeWords: await store.intSetting('includeWords', 1) == 1,
      includeKanji: await store.intSetting('includeKanji', 1) == 1,
      includeGrammar: await store.intSetting('includeGrammar', 1) == 1,
    );
    reminderAt = await store.setting('reminderAt');

    await _loadAvailable();
    states = await store.allStates();

    final now = DateTime.now();
    reviewedToday = await store.reviewedToday(now);
    streak = await store.streak(now);

    loading = false;
    notifyListeners();
  }

  Future<void> _loadAvailable() async {
    // Ordered per kind, then concatenated. The queue interleaves new
    // cards itself, so the order within each kind is what matters —
    // commonest words first, commonest kanji first.
    final words = await content.words(minLevel: settings.minLevel);
    final kanji = await content.kanji(minLevel: settings.minLevel);
    final grammar = await content.grammar(minLevel: settings.minLevel);
    available = [
      for (final w in words) w.cardId,
      for (final k in kanji) k.cardId,
      for (final g in grammar) g.cardId,
    ];
  }

  SessionSummary get summary => summarise(
        available,
        states,
        DateTime.now(),
        settings: settings,
        reviewedToday: reviewedToday,
      );

  List<CardState> buildSession() => buildQueue(
        available,
        states,
        DateTime.now(),
        settings: settings,
        reviewedToday: reviewedToday,
      );

  Progress progress(CardKind kind) => progressFor(available, states, kind);

  /// Answers a card: schedules it, writes it, and updates the counters
  /// the home screen shows.
  Future<CardState> answer(CardState card, Grade grade) async {
    final now = DateTime.now();
    final next = applyReview(card, grade, now);
    states[next.id] = next;
    await store.record(next, grade, now);
    reviewedToday++;
    // The streak can only ever start on the first answer of a day, so
    // recomputing it on every card is wasted work — but it is one query
    // against an indexed column, and getting it wrong means the number
    // on the home screen is stale until a restart.
    if (reviewedToday == 1) streak = await store.streak(now);
    notifyListeners();
    return next;
  }

  Future<void> suspend(CardState card) async {
    final next = card.copyWith(suspended: true);
    states[next.id] = next;
    await store.save(next);
    notifyListeners();
  }

  // ---------------------------------------------------------- settings

  Future<void> updateSettings(StudySettings next) async {
    final levelChanged = next.minLevel != settings.minLevel;
    settings = next;
    await store.setSetting('newPerDay', '${next.newPerDay}');
    await store.setSetting('maxReviewsPerDay', '${next.maxReviewsPerDay}');
    await store.setSetting('minLevel', '${next.minLevel}');
    await store.setSetting('includeWords', next.includeWords ? '1' : '0');
    await store.setSetting('includeKanji', next.includeKanji ? '1' : '0');
    await store.setSetting('includeGrammar', next.includeGrammar ? '1' : '0');
    if (levelChanged) await _loadAvailable();
    notifyListeners();
  }

  /// Sets or clears the daily reminder. Returns false when the platform
  /// refused — a denied notification permission, most often — so the
  /// settings screen can say so instead of showing a time that will
  /// never fire.
  Future<bool> setReminder(int? hour, int? minute) async {
    if (hour == null || minute == null) {
      await Reminders.instance.cancel();
      reminderAt = null;
      await store.setSetting('reminderAt', '');
      notifyListeners();
      return true;
    }

    final granted = await Reminders.instance.requestPermission();
    if (!granted) return false;
    final ok = await Reminders.instance.scheduleDaily(hour, minute);
    if (!ok) return false;

    reminderAt = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    await store.setSetting('reminderAt', reminderAt!);
    notifyListeners();
    return true;
  }
}
