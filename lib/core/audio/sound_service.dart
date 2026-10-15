import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

import '../../data/models/config_model.dart';

class SoundService {
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;

  late final AssetSource _uploadSound;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _uploadSound = AssetSource('sounds/upload_complete.wav');

      _isInitialized = true;
    } catch (e) {
      developer.log(
        'Error initializing sound service: $e',
        name: 'SoundService',
      );
    }
  }

  Future<void> playUploadSound(ConfigModel config) async {
    if (!_isInitialized) await initialize();

    if (!config.soundEnabled) return;

    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(config.soundVolume);
      await _audioPlayer.play(_uploadSound);
    } catch (e) {
      developer.log('Error playing upload sound: $e', name: 'SoundService');
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
