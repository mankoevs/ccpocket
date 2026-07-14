import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../utils/platform_helper.dart';
import 'bridge_service.dart';

class VoiceInputService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  bool _isAvailable = false;
  bool _isRecording = false;

  bool get isAvailable => _isAvailable;
  bool get isRecording => _isRecording;

  Future<bool> initialize() async {
    if (kIsWeb || isDesktopPlatform) {
      _isAvailable = false;
      return false;
    }
    _isAvailable = await _recorder.hasPermission();
    return _isAvailable;
  }

  Future<void> startRecording() async {
    if (!_isAvailable || _isRecording) return;
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/ccpocket_voice_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _recordingPath = path;
    _isRecording = true;
  }

  Future<String> stopAndTranscribe({
    required BridgeService bridge,
    String localeId = 'ru-RU',
  }) async {
    if (!_isRecording) return '';
    _isRecording = false;
    final path = await _recorder.stop() ?? _recordingPath;
    _recordingPath = null;
    if (path == null) throw StateError('Audio recording was not created');

    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      return await bridge.transcribeAudio(bytes, localeId: localeId);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {
    unawaited(_recorder.dispose());
    _isRecording = false;
  }
}
