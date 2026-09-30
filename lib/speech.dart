/// Japanese text-to-speech, and recording an attempt at saying it back.
///
/// The thin layer that touches plugins. Everything here can fail on a
/// real device for reasons the app cannot fix — no Japanese voice
/// installed, a microphone another app is holding, permission refused —
/// so every method reports what happened rather than throwing, and the
/// screens are built to stay useful when the answer is no.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Why speech is unavailable, in terms that suggest what to do about it.
enum VoiceProblem {
  /// The device has no Japanese voice data. On most Android devices this
  /// is a one-off download inside the system text-to-speech settings, so
  /// it is worth saying rather than failing silently.
  noJapaneseVoice,

  /// The engine is there but refused to speak.
  engineFailed,
}

class Speech {
  Speech._();
  static final Speech instance = Speech._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  VoiceProblem? problem;

  /// True once a Japanese voice has been found and configured.
  bool get available => _ready && problem == null;

  /// Speaking rate. Slower than the default on purpose — the system
  /// default is tuned for a native speaker skimming a notification, and
  /// at that speed a learner hears one continuous sound.
  double rate = 0.45;

  Future<void> init() async {
    if (_ready) return;
    try {
      final languages = await _tts.getLanguages;
      final hasJapanese = languages is List &&
          languages.any((l) => '$l'.toLowerCase().startsWith('ja'));
      if (!hasJapanese) {
        problem = VoiceProblem.noJapaneseVoice;
        _ready = true;
        return;
      }
      await _tts.setLanguage('ja-JP');
      await _tts.setSpeechRate(rate);
      await _tts.awaitSpeakCompletion(true);
      problem = null;
    } catch (_) {
      problem = VoiceProblem.engineFailed;
    }
    _ready = true;
  }

  Future<void> setRate(double value) async {
    rate = value;
    if (available) {
      try {
        await _tts.setSpeechRate(value);
      } catch (_) {
        // A rate the engine will not accept is not worth a screen; it
        // keeps whatever it had.
      }
    }
  }

  /// Says [text]. Returns false when nothing was spoken, so a caller can
  /// show the reason instead of appearing to do nothing.
  Future<bool> say(String text) async {
    await init();
    if (!available) return false;
    try {
      await _tts.stop();
      await _tts.speak(text);
      return true;
    } catch (_) {
      problem = VoiceProblem.engineFailed;
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping something that is not playing is not an error.
    }
  }
}

/// Recording an attempt, and playing it back.
///
/// Nothing here scores pronunciation. No honest scoring is available on
/// a device, and a number that claimed to would be worse than none — so
/// the app captures the attempt and lets the person listen to it against
/// the reference, which is what self-assessment actually is.
class Recorder {
  Recorder._();
  static final Recorder instance = Recorder._();

  final AudioRecorder _rec = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool get isRecordingSupported => Platform.isAndroid || Platform.isIOS;

  Future<bool> hasPermission() async {
    try {
      return await _rec.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isRecording async {
    try {
      return await _rec.isRecording();
    } catch (_) {
      return false;
    }
  }

  /// Starts recording into the app's own directory and returns the path,
  /// or null if it could not start.
  Future<String?> start(int sentenceId) async {
    if (!await hasPermission()) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/recordings');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final path = '${folder.path}/s${sentenceId}_'
          '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        // AAC in an m4a container: plays back through the same audio
        // stack as everything else, and a minute of speech is tens of
        // kilobytes rather than the megabytes raw PCM would cost on a
        // device that is going to accumulate hundreds of these.
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: path,
      );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Stops and returns the finished file's path, or null.
  Future<String?> stop() async {
    try {
      return await _rec.stop();
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel() async {
    try {
      await _rec.cancel();
    } catch (_) {
      // Nothing to cancel is the normal case on a screen being left.
    }
  }

  Future<bool> play(String path) async {
    if (!File(path).existsSync()) return false;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {
      // As above.
    }
  }

  Future<void> dispose() async {
    await _rec.dispose();
    await _player.dispose();
  }
}
