import 'dart:developer' as developer;
import 'package:audioplayers/audioplayers.dart';

import '../../data/models/config_model.dart';

// Service for playing sound notifications
class SoundService {
  // Audio player instance
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Whether the service is initialized
  bool _isInitialized = false;
  
  // Sound for upload completed notification
  late final AssetSource _uploadSound;
  
  // Initialize the sound service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load sound assets
      _uploadSound = AssetSource('sounds/upload_complete.wav');
      
      _isInitialized = true;
      developer.log('Sound service initialized', name: 'SoundService');
    } catch (e) {
      developer.log('Error initializing sound service: $e', name: 'SoundService');
    }
  }
  
  // Play a sound for upload completed notification
  Future<void> playUploadSound(ConfigModel config) async {
    if (!_isInitialized) await initialize();
    
    if (!config.soundEnabled) return;
    
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(config.soundVolume);
      await _audioPlayer.play(_uploadSound);
      developer.log('Played upload sound', name: 'SoundService');
    } catch (e) {
      developer.log('Error playing upload sound: $e', name: 'SoundService');
    }
  }
  
  // Dispose resources
  void dispose() {
    _audioPlayer.dispose();
  }
}
