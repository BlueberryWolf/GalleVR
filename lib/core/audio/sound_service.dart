import 'dart:async';
import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

import '../../data/models/config_model.dart';

class SoundService {
  static final AssetSource _uploadSound = AssetSource(
    'sounds/upload_complete.wav',
  );
  static const Duration _idleReleaseDelay = Duration(seconds: 10);

  AudioPlayer? _audioPlayer;
  Timer? _idleTimer;

  Future<void> initialize() async {}

  Future<void> playUploadSound(ConfigModel config) async {
    if (!config.soundEnabled) return;

    _idleTimer?.cancel();
    _idleTimer = null;

    try {
      final player = _audioPlayer ??= AudioPlayer();
      await player.stop();
      await player.setVolume(config.soundVolume);
      await player.play(_uploadSound);

      _idleTimer = Timer(_idleReleaseDelay, () {
        releasePlayer();
      });
    } catch (e) {
      developer.log('Error playing upload sound: $e', name: 'SoundService');
    }
  }

  Future<void> releasePlayer() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final player = _audioPlayer;
    if (player == null) return;
    _audioPlayer = null;
    try {
      await player.dispose();
    } catch (e) {
      developer.log('Error releasing audio player: $e', name: 'SoundService');
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final player = _audioPlayer;
    _audioPlayer = null;
    player?.dispose();
  }
}
