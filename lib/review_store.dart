/// Where progress lives.
///
/// A separate database from the content, and that separation is the whole
/// point: `content.db` is replaced wholesale every time the art of the
/// word lists is rebuilt, and progress must survive that. Keying reviews
/// by a string card id rather than by a row pointer means a rebuilt
/// content database that renumbers nothing keeps every review intact, and
/// one that drops a word loses that word's history and nothing else.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'srs.dart';

/// One answered card, kept for the statistics and for rebuilding a day's
/// work if something goes wrong mid-session.
class ReviewLog {
  const ReviewLog({
    required this.cardId,
    required this.grade,
    required this.at,
    required this.intervalDays,
  });

  final String cardId;
  final Grade grade;
  final DateTime at;
  final int intervalDays;
}

class ReviewStore {
  ReviewStore._(this._db);

  final Database _db;
  static ReviewStore? _open;

  static Future<ReviewStore> open() async {
    if (_open != null) return _open!;
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${dir.path}/progress.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE card (
            id            TEXT PRIMARY KEY,
            reps          INTEGER NOT NULL,
            lapses        INTEGER NOT NULL,
            ease          REAL    NOT NULL,
            interval_days INTEGER NOT NULL,
            step          INTEGER NOT NULL,
            due           INTEGER,
            suspended     INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX card_due ON card(due)');
        await db.execute('''
          CREATE TABLE log (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            card_id       TEXT    NOT NULL,
            grade         INTEGER NOT NULL,
            at            INTEGER NOT NULL,
            interval_days INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX log_at ON log(at)');
        await db.execute('''
          CREATE TABLE setting (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE challenge_done (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            challenge_id TEXT    NOT NULL,
            at           INTEGER NOT NULL,
            note         TEXT
          )
        ''');
        await db.execute('CREATE INDEX challenge_done_at ON challenge_done(at)');
        await db.execute('''
          CREATE TABLE recording (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            sentence_id INTEGER NOT NULL,
            path       TEXT    NOT NULL,
            at         INTEGER NOT NULL
          )
        ''');
      },
    );
    return _open = ReviewStore._(db);
  }

  // ------------------------------------------------------------- cards

  /// Every card that has ever been answered. A card with no row here has
  /// never been seen, and is reconstructed as a new one rather than
  /// stored up front — writing 4,200 rows on first launch to say "none of
  /// these have been studied" is work for no information.
  Future<Map<String, CardState>> allStates() async {
    final rows = await _db.query('card');
    return {
      for (final r in rows) r['id']! as String: _fromRow(r),
    };
  }

  Future<CardState> state(String cardId) async {
    final rows =
        await _db.query('card', where: 'id = ?', whereArgs: [cardId]);
    return rows.isEmpty ? CardState(id: cardId) : _fromRow(rows.first);
  }

  Future<void> save(CardState card) async {
    await _db.insert(
      'card',
      {
        'id': card.id,
        'reps': card.reps,
        'lapses': card.lapses,
        'ease': card.ease,
        'interval_days': card.intervalDays,
        'step': card.step,
        'due': card.due?.millisecondsSinceEpoch,
        'suspended': card.suspended ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Records an answer and the state it produced, in one transaction.
  ///
  /// Together, because a log entry without the matching card state would
  /// make the statistics disagree with the deck, and the card state
  /// without the log would lose the day from the history.
  Future<void> record(CardState after, Grade grade, DateTime at) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'card',
        {
          'id': after.id,
          'reps': after.reps,
          'lapses': after.lapses,
          'ease': after.ease,
          'interval_days': after.intervalDays,
          'step': after.step,
          'due': after.due?.millisecondsSinceEpoch,
          'suspended': after.suspended ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('log', {
        'card_id': after.id,
        'grade': grade.index,
        'at': at.millisecondsSinceEpoch,
        'interval_days': after.intervalDays,
      });
    });
  }

  static CardState _fromRow(Map<String, Object?> r) {
    final due = r['due'] as int?;
    return CardState(
      id: r['id']! as String,
      reps: r['reps']! as int,
      lapses: r['lapses']! as int,
      ease: (r['ease']! as num).toDouble(),
      intervalDays: r['interval_days']! as int,
      step: r['step']! as int,
      due: due == null ? null : DateTime.fromMillisecondsSinceEpoch(due),
      suspended: (r['suspended'] as int? ?? 0) == 1,
    );
  }

  // -------------------------------------------------------- statistics

  /// How many cards were answered on each of the last [days] days, newest
  /// last. The streak and the chart on the home screen both read this.
  Future<List<int>> dailyCounts(int days, DateTime now) async {
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final rows = await _db.rawQuery(
      'SELECT at FROM log WHERE at >= ?',
      [start.millisecondsSinceEpoch],
    );
    final counts = List<int>.filled(days, 0);
    for (final r in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(r['at']! as int);
      final day = DateTime(at.year, at.month, at.day).difference(start).inDays;
      if (day >= 0 && day < days) counts[day]++;
    }
    return counts;
  }

  /// Consecutive days up to today with at least one review.
  ///
  /// Today not having been studied yet does not break the streak — it is
  /// only broken by a day that has already ended with nothing in it.
  /// Counting otherwise means the streak reads as zero every morning.
  Future<int> streak(DateTime now) async {
    final counts = await dailyCounts(365, now);
    var streak = 0;
    for (var i = counts.length - 1; i >= 0; i--) {
      if (counts[i] > 0) {
        streak++;
      } else if (i != counts.length - 1) {
        break;
      }
    }
    return streak;
  }

  Future<int> reviewedToday(DateTime now) async {
    final counts = await dailyCounts(1, now);
    return counts.first;
  }

  // ---------------------------------------------------------- settings

  Future<String?> setting(String key) async {
    final rows =
        await _db.query('setting', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('setting', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> intSetting(String key, int fallback) async =>
      int.tryParse(await setting(key) ?? '') ?? fallback;

  // -------------------------------------------------------- challenges

  /// Marks today's challenge done.
  ///
  /// Appends rather than replaces: doing the same scenario again months
  /// later is a second attempt, not a correction of the first, and the
  /// history is what stops it being offered again next week.
  Future<void> completeChallenge(String id, DateTime at,
      {String? note}) async {
    await _db.insert('challenge_done', {
      'challenge_id': id,
      'at': at.millisecondsSinceEpoch,
      'note': note,
    });
  }

  /// The ids most recently completed, newest first.
  Future<List<String>> recentChallenges({int limit = 30}) async {
    final rows = await _db.query('challenge_done',
        columns: ['challenge_id'], orderBy: 'at DESC', limit: limit);
    return [for (final r in rows) r['challenge_id']! as String];
  }

  Future<List<DateTime>> challengeCompletions({int limit = 400}) async {
    final rows = await _db.query('challenge_done',
        columns: ['at'], orderBy: 'at DESC', limit: limit);
    return [
      for (final r in rows)
        DateTime.fromMillisecondsSinceEpoch(r['at']! as int),
    ];
  }

  /// Whether a given challenge was completed today.
  Future<bool> didChallengeToday(String id, DateTime now) async {
    final start = DateTime(now.year, now.month, now.day);
    final rows = await _db.rawQuery(
      'SELECT 1 FROM challenge_done WHERE challenge_id = ? AND at >= ?'
      ' LIMIT 1',
      [id, start.millisecondsSinceEpoch],
    );
    return rows.isNotEmpty;
  }

  // -------------------------------------------------------- recordings

  /// A speaking attempt, kept so it can be played back later.
  ///
  /// Nothing here scores pronunciation. Nothing available on a device
  /// honestly can, and a number that claims to would be worse than no
  /// number — so the app keeps the recording and lets the person judge,
  /// which is what "self check" actually means.
  Future<void> addRecording(int sentenceId, String path, DateTime at) async {
    await _db.insert('recording', {
      'sentence_id': sentenceId,
      'path': path,
      'at': at.millisecondsSinceEpoch,
    });
  }

  Future<List<({int id, int sentenceId, String path, DateTime at})>>
      recordings({int limit = 100}) async {
    final rows = await _db.query('recording',
        orderBy: 'at DESC', limit: limit);
    return [
      for (final r in rows)
        (
          id: r['id']! as int,
          sentenceId: r['sentence_id']! as int,
          path: r['path']! as String,
          at: DateTime.fromMillisecondsSinceEpoch(r['at']! as int),
        ),
    ];
  }

  /// Removes the row and the audio file together. A row pointing at a
  /// file that is gone shows up as a recording that plays silence, which
  /// is more confusing than one that is simply not listed.
  Future<void> deleteRecording(int id, String path) async {
    await _db.delete('recording', where: 'id = ?', whereArgs: [id]);
    final f = File(path);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {
        // A file the OS will not let go of is not worth failing over;
        // the row is gone either way.
      }
    }
  }
}
