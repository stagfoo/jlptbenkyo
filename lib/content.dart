/// Reading the bundled content database.
///
/// `assets/content.db` is built by `tool/build_content.py` and shipped
/// read-only. SQLite cannot open a file inside the APK, so the first
/// launch copies it out to the documents directory — once, and then never
/// again unless the build that produced it changed.
///
/// Everything here returns plain models rather than raw rows, so the
/// screens never see a `Map<String, Object?>` and a schema change breaks
/// in one file instead of nine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// A vocabulary entry.
class Word {
  const Word({
    required this.id,
    required this.expression,
    required this.reading,
    required this.meaning,
    required this.level,
    this.pos,
    this.common = false,
  });

  final int id;
  final String expression;
  final String reading;
  final String meaning;
  final int level;

  /// Dictionary part-of-speech codes, comma separated. Null for the
  /// handful of list entries the dictionary had nothing for.
  final String? pos;

  final bool common;

  /// Whether the written form differs from the reading at all. A word
  /// written only in kana has nothing to test the reading of, so the
  /// review screen asks a different question about it.
  bool get hasKanji => expression != reading;

  String get cardId => 'word:$id';

  static Word fromRow(Map<String, Object?> r) => Word(
        id: r['id']! as int,
        expression: r['expression']! as String,
        reading: r['reading']! as String,
        meaning: r['meaning']! as String,
        level: r['level']! as int,
        pos: r['pos'] as String?,
        common: (r['common'] as int? ?? 0) == 1,
      );
}

/// A kanji, with the strokes needed to write it.
class Kanji {
  const Kanji({
    required this.id,
    required this.literal,
    required this.level,
    required this.strokes,
    required this.meanings,
    required this.onYomi,
    required this.kunYomi,
    required this.strokePaths,
    this.freq,
  });

  final int id;
  final String literal;
  final int level;
  final int strokes;
  final List<String> meanings;
  final List<String> onYomi;
  final List<String> kunYomi;

  /// SVG path data, one entry per stroke, in the order a person writes
  /// them. Empty when KanjiVG had nothing for this character.
  final List<String> strokePaths;

  /// Newspaper frequency rank, where known. Lower is commoner, and it is
  /// what decides which kanji a level introduces first.
  final int? freq;

  String get cardId => 'kanji:$id';

  static Kanji fromRow(Map<String, Object?> r) => Kanji(
        id: r['id']! as int,
        literal: r['literal']! as String,
        level: r['level']! as int,
        strokes: r['strokes'] as int? ?? 0,
        meanings: _strings(r['meanings']),
        onYomi: _strings(r['on_yomi']),
        kunYomi: _strings(r['kun_yomi']),
        strokePaths: _strings(r['strokes_svg']),
        freq: r['freq'] as int?,
      );
}

/// One grammar point.
class GrammarPoint {
  const GrammarPoint({
    required this.id,
    required this.pattern,
    required this.level,
    required this.meaning,
    this.category,
    this.formation,
    this.note,
  });

  final int id;
  final String pattern;
  final int level;
  final String meaning;
  final String? category;
  final String? formation;

  /// The thing worth knowing that the meaning alone does not say — which
  /// near-identical pattern this is confused with, or where it cannot be
  /// used. Null where there is nothing to warn about.
  final String? note;

  String get cardId => 'grammar:$id';

  static GrammarPoint fromRow(Map<String, Object?> r) => GrammarPoint(
        id: r['id']! as int,
        pattern: r['pattern']! as String,
        level: r['level']! as int,
        meaning: r['meaning']! as String,
        category: r['category'] as String?,
        formation: r['formation'] as String?,
        note: r['note'] as String?,
      );
}

/// A Japanese sentence and its English translation, from Tatoeba.
class Sentence {
  const Sentence({
    required this.id,
    required this.jp,
    required this.en,
    required this.chars,
    required this.level,
  });

  final int id;
  final String jp;
  final String en;
  final int chars;

  /// The JLPT level of the hardest kanji in it: 5 is easiest, 3 is N3,
  /// and 0 means it contains a kanji beyond N3 — above the grade, not
  /// ungraded.
  final int level;

  bool get isAboveGrade => level == 0;

  static Sentence fromRow(Map<String, Object?> r) => Sentence(
        id: r['id']! as int,
        jp: r['jp']! as String,
        en: r['en']! as String,
        chars: r['chars']! as int,
        level: r['level']! as int,
      );
}

/// A real-world task to attempt out loud.
class Challenge {
  const Challenge({
    required this.id,
    required this.level,
    required this.title,
    required this.goal,
    required this.steps,
    this.category,
    this.setting,
    this.stretch,
  });

  final String id;
  final int level;
  final String title;

  /// What counts as having done it. Deliberately concrete — "order a hot
  /// coffee, say the size, say it's to take away" is something you can
  /// tell whether you managed; "practise ordering" is not.
  final String goal;

  /// The beats to hit, in order. Not a script: the phrases below are one
  /// way to say each, and the point is to get through the steps somehow.
  final List<String> steps;

  final String? category;
  final String? setting;

  /// A harder version for when the plain one stops being work.
  final String? stretch;

  static Challenge fromRow(Map<String, Object?> r) => Challenge(
        id: r['id']! as String,
        level: r['level']! as int,
        title: r['title']! as String,
        goal: r['goal']! as String,
        steps: _strings(r['steps']),
        category: r['category'] as String?,
        setting: r['setting'] as String?,
        stretch: r['stretch'] as String?,
      );
}

class ChallengePhrase {
  const ChallengePhrase(this.jp, this.en);
  final String jp, en;
}

List<String> _strings(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return [for (final v in decoded) '$v'];
}

/// The bundled content, opened once and kept.
class ContentDb {
  ContentDb._(this._db, this.meta);

  final Database _db;

  /// What the build recorded about itself — dictionary version, counts,
  /// schema. Shown on the about screen, and what decides whether the copy
  /// on disk is stale.
  final Map<String, String> meta;

  static ContentDb? _open;

  static Future<ContentDb> open() async {
    if (_open != null) return _open!;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/content.db';
    final bundled = await rootBundle.load('assets/content.db');

    // Copied on first run, and again whenever the asset's size changes —
    // which it does on every rebuild of the content. Comparing sizes is
    // cheap and wrong only if a rebuild lands on exactly the same byte
    // count, so the build's own version string is checked below as well.
    final file = File(path);
    final needsCopy = !file.existsSync() ||
        file.lengthSync() != bundled.lengthInBytes;
    if (needsCopy) {
      await file.writeAsBytes(
        bundled.buffer.asUint8List(
          bundled.offsetInBytes,
          bundled.lengthInBytes,
        ),
        flush: true,
      );
    }

    final db = await openDatabase(path, readOnly: true);
    final meta = {
      for (final r in await db.query('meta'))
        r['key']! as String: r['value']! as String,
    };
    return _open = ContentDb._(db, meta);
  }

  // ------------------------------------------------------------ counts

  Future<int> count(String table, {int? maxLevel}) async {
    final rows = await _db.rawQuery(
      'SELECT count(*) n FROM $table'
      '${maxLevel == null ? '' : ' WHERE level >= ?'}',
      maxLevel == null ? null : [maxLevel],
    );
    return rows.first['n']! as int;
  }

  // ------------------------------------------------------------- words

  /// Words for a level range, commonest first.
  ///
  /// Ordered by the dictionary's own "common" flag and then by level, so
  /// the first words introduced are the ones actually worth knowing
  /// first — a list ordered by id introduces 作法 before 私.
  Future<List<Word>> words({int easiestLevel = 5, int? limit}) async {
    final rows = await _db.query(
      'word',
      // `<=` not `>=`: the numbers run backwards to the names, so the
      // easiest level included is the highest number.
      where: 'level <= ?',
      whereArgs: [easiestLevel],
      orderBy: 'level DESC, common DESC, id ASC',
      limit: limit,
    );
    return [for (final r in rows) Word.fromRow(r)];
  }

  Future<Word?> word(int id) async {
    final rows = await _db.query('word', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Word.fromRow(rows.first);
  }

  /// Other words that share a kanji with this one. What turns a flashcard
  /// into something connected to the rest of the language.
  Future<List<Word>> wordsSharingKanji(int wordId, {int limit = 8}) async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT w.* FROM word w
      JOIN kanji_word kw ON kw.word_id = w.id
      WHERE kw.kanji_id IN (SELECT kanji_id FROM kanji_word WHERE word_id = ?)
        AND w.id != ?
      ORDER BY w.common DESC, w.level DESC
      LIMIT ?
    ''', [wordId, wordId, limit]);
    return [for (final r in rows) Word.fromRow(r)];
  }

  // ------------------------------------------------------------- kanji

  Future<List<Kanji>> kanji({int easiestLevel = 5, int? limit}) async {
    final rows = await _db.query(
      'kanji',
      // `<=` not `>=`: the numbers run backwards to the names, so the
      // easiest level included is the highest number.
      where: 'level <= ?',
      whereArgs: [easiestLevel],
      orderBy: 'level DESC, COALESCE(freq, 9999) ASC',
      limit: limit,
    );
    return [for (final r in rows) Kanji.fromRow(r)];
  }

  Future<Kanji?> kanjiById(int id) async {
    final rows = await _db.query('kanji', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Kanji.fromRow(rows.first);
  }

  /// Words that use this kanji — how you show what a character is *for*.
  Future<List<Word>> wordsWithKanji(int kanjiId, {int limit = 10}) async {
    final rows = await _db.rawQuery('''
      SELECT w.* FROM word w
      JOIN kanji_word kw ON kw.word_id = w.id
      WHERE kw.kanji_id = ?
      ORDER BY w.common DESC, w.level DESC
      LIMIT ?
    ''', [kanjiId, limit]);
    return [for (final r in rows) Word.fromRow(r)];
  }

  // ----------------------------------------------------------- grammar

  Future<List<GrammarPoint>> grammar({int easiestLevel = 5}) async {
    final rows = await _db.query(
      'grammar',
      // `<=` not `>=`: the numbers run backwards to the names, so the
      // easiest level included is the highest number.
      where: 'level <= ?',
      whereArgs: [easiestLevel],
      orderBy: 'level DESC, category ASC, id ASC',
    );
    return [for (final r in rows) GrammarPoint.fromRow(r)];
  }

  Future<GrammarPoint?> grammarById(int id) async {
    final rows = await _db.query('grammar', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : GrammarPoint.fromRow(rows.first);
  }

  // --------------------------------------------------------- sentences

  /// Example sentences for a word, shortest first.
  ///
  /// Shortest first because an example is there to show one thing. A
  /// forty-character sentence with three other unknown structures in it
  /// demonstrates nothing about the word you are looking at.
  Future<List<Sentence>> sentencesForWord(int wordId, {int limit = 4}) async {
    final rows = await _db.rawQuery('''
      SELECT s.* FROM sentence s
      JOIN word_sentence ws ON ws.sentence_id = s.id
      WHERE ws.word_id = ?
      ORDER BY s.chars ASC
      LIMIT ?
    ''', [wordId, limit]);
    return [for (final r in rows) Sentence.fromRow(r)];
  }

  Future<List<Sentence>> sentencesForGrammar(int grammarId,
      {int limit = 6}) async {
    final rows = await _db.rawQuery('''
      SELECT s.* FROM sentence s
      JOIN grammar_sentence gs ON gs.sentence_id = s.id
      WHERE gs.grammar_id = ?
      ORDER BY s.chars ASC
      LIMIT ?
    ''', [grammarId, limit]);
    return [for (final r in rows) Sentence.fromRow(r)];
  }

  /// The kanji inside a written word, in the order they appear.
  ///
  /// Kana and punctuation simply do not match a row, so 遊ぶ returns one
  /// character and ひらがな returns none — no filtering needed beyond the
  /// lookup itself.
  Future<List<Kanji>> kanjiInText(String text) async {
    final seen = <String>[];
    for (final ch in text.split('')) {
      if (!seen.contains(ch)) seen.add(ch);
    }
    if (seen.isEmpty) return const [];
    final marks = List.filled(seen.length, '?').join(',');
    final rows = await _db
        .rawQuery('SELECT * FROM kanji WHERE literal IN ($marks)', seen);
    final byLiteral = {
      for (final r in rows) r['literal']! as String: Kanji.fromRow(r),
    };
    return [for (final ch in seen) ?byLiteral[ch]];
  }

  // ------------------------------------------------------------- focus

  /// Every kanji with the deck words written with it.
  ///
  /// Loaded whole because the writing ranking has to score all of them
  /// against the deck at once — one query and one join beats six hundred
  /// round trips, and the result is a few thousand integers.
  ///
  /// [withStrokesOnly] drops characters KanjiVG had no paths for, since
  /// offering a tracing exercise with nothing to trace is worse than
  /// leaving the character out.
  Future<
      List<
          ({
            int id,
            String literal,
            int level,
            int? easiestWordLevel,
            List<int> wordIds
          })>> kanjiWithWords({
    int easiestLevel = 5,
    bool withStrokesOnly = true,
  }) async {
    final rows = await _db.query(
      'kanji',
      columns: ['id', 'literal', 'level'],
      where: 'level <= ?'
          '${withStrokesOnly ? ' AND strokes_svg IS NOT NULL' : ''}',
      whereArgs: [easiestLevel],
    );
    // The easiest word is computed here rather than in Dart because the
    // level is on the word row, and pulling 3,500 of those across to take
    // a maximum would be wasteful.
    final links = await _db.rawQuery('''
      SELECT kw.kanji_id kid, kw.word_id wid, w.level wlevel
      FROM kanji_word kw JOIN word w ON w.id = kw.word_id
    ''');
    final byKanji = <int, List<int>>{};
    final easiest = <int, int>{};
    for (final l in links) {
      final kid = l['kid']! as int;
      byKanji.putIfAbsent(kid, () => []).add(l['wid']! as int);
      final level = l['wlevel']! as int;
      // Levels count down, so the easiest word is the highest number.
      if (level > (easiest[kid] ?? 0)) easiest[kid] = level;
    }
    return [
      for (final r in rows)
        (
          id: r['id']! as int,
          literal: r['literal']! as String,
          level: r['level']! as int,
          easiestWordLevel: easiest[r['id']],
          wordIds: byKanji[r['id']] ?? const <int>[],
        ),
    ];
  }

  /// Every grammar point with the deck words its examples are built from.
  ///
  /// Two hops — grammar to sentence, sentence to word — done in SQL
  /// rather than in Dart, because the middle table is 26,000 rows and
  /// pulling it across to join by hand would be the slowest thing in the
  /// app.
  Future<List<({int id, int level, List<int> wordIds})>> grammarWithWords({
    int easiestLevel = 5,
  }) async {
    final rows = await _db.query('grammar',
        columns: ['id', 'level'],
        where: 'level <= ?',
        whereArgs: [easiestLevel]);
    final links = await _db.rawQuery('''
      SELECT DISTINCT gs.grammar_id gid, ws.word_id wid
      FROM grammar_sentence gs
      JOIN word_sentence ws ON ws.sentence_id = gs.sentence_id
    ''');
    final byGrammar = <int, List<int>>{};
    for (final l in links) {
      byGrammar
          .putIfAbsent(l['gid']! as int, () => [])
          .add(l['wid']! as int);
    }
    return [
      for (final r in rows)
        (
          id: r['id']! as int,
          level: r['level']! as int,
          wordIds: byGrammar[r['id']] ?? const <int>[],
        ),
    ];
  }

  // -------------------------------------------------------- challenges

  /// Every challenge, with the deck words each is built from.
  ///
  /// Loaded whole because the daily pick has to score all of them against
  /// the deck, and there are fifty — cheaper as one query than as fifty.
  Future<List<({Challenge challenge, List<int> wordIds})>>
      challenges() async {
    final rows = await _db.query('challenge', orderBy: 'ord ASC');
    final links = await _db.query('challenge_word');
    final byChallenge = <String, List<int>>{};
    for (final l in links) {
      byChallenge
          .putIfAbsent(l['challenge_id']! as String, () => [])
          .add(l['word_id']! as int);
    }
    return [
      for (final r in rows)
        (
          challenge: Challenge.fromRow(r),
          wordIds: byChallenge[r['id']] ?? const [],
        ),
    ];
  }

  Future<Challenge?> challengeById(String id) async {
    final rows =
        await _db.query('challenge', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Challenge.fromRow(rows.first);
  }

  Future<List<ChallengePhrase>> challengePhrases(String id) async {
    final rows = await _db.query('challenge_phrase',
        where: 'challenge_id = ?', whereArgs: [id], orderBy: 'ord ASC');
    return [
      for (final r in rows)
        ChallengePhrase(r['jp']! as String, r['en']! as String),
    ];
  }

  Future<List<Word>> challengeWords(String id) async {
    final rows = await _db.rawQuery('''
      SELECT w.* FROM word w
      JOIN challenge_word cw ON cw.word_id = w.id
      WHERE cw.challenge_id = ?
      ORDER BY w.level DESC, w.id ASC
    ''', [id]);
    return [for (final r in rows) Word.fromRow(r)];
  }

  Future<List<GrammarPoint>> challengeGrammar(String id) async {
    final rows = await _db.rawQuery('''
      SELECT g.* FROM grammar g
      JOIN challenge_grammar cg ON cg.grammar_id = g.id
      WHERE cg.challenge_id = ?
      ORDER BY g.level DESC
    ''', [id]);
    return [for (final r in rows) GrammarPoint.fromRow(r)];
  }

  /// Words by id, for the "work these in" list.
  Future<List<Word>> wordsByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final marks = List.filled(ids.length, '?').join(',');
    final rows =
        await _db.rawQuery('SELECT * FROM word WHERE id IN ($marks)', ids);
    final byId = {for (final r in rows) r['id']! as int: Word.fromRow(r)};
    // Returned in the order asked for: the caller ranked them, and a
    // SQL IN clause does not preserve that.
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  Future<Sentence?> sentenceById(int id) async {
    final rows = await _db.query('sentence', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Sentence.fromRow(rows.first);
  }

  /// Sentences graded for reading, listening and speaking practice.
  ///
  /// [hardestLevel] is a difficulty ceiling, and is the opposite
  /// comparison to the deck scope above: asking for 4 gets sentences
  /// whose every character is N5 or N4, and asking for 3 allows N3 too.
  /// Sentences above N3 are excluded unless [includeAboveGrade], because
  /// a reading exercise full of characters you have not met is not
  /// practice, it is a lookup session.
  Future<List<Sentence>> practiceSentences({
    int hardestLevel = 3,
    int maxChars = 60,
    int limit = 40,
    bool includeAboveGrade = false,
    int seed = 0,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT * FROM sentence
      WHERE chars <= ?
        AND (level >= ? ${includeAboveGrade ? 'OR level = 0' : ''})
      ORDER BY (id * 2654435761) % 1000003, id
      LIMIT ? OFFSET ?
    ''', [maxChars, hardestLevel, limit, seed * limit]);
    return [for (final r in rows) Sentence.fromRow(r)];
  }
}
