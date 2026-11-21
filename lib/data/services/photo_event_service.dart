import 'dart:async';

class PhotoErrorEvent {
  final String type;

  final String message;

  final String? photoPath;

  final DateTime timestamp;

  PhotoErrorEvent({
    required this.type,
    required this.message,
    this.photoPath,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class PhotoEventService {
  static final PhotoEventService _instance = PhotoEventService._internal();

  factory PhotoEventService() {
    return _instance;
  }

  PhotoEventService._internal();

  final List<PhotoErrorEvent> _history = [];

  List<PhotoErrorEvent> get history => List.unmodifiable(_history);

  void clearHistory() => _history.clear();

  void seedHistory(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return;
    _history.clear();
    for (final entry in entries.take(100)) {
      final type = entry['type'] as String? ?? 'info';
      final message = entry['message'] as String? ?? '';
      final photoPath = entry['photoPath'] as String?;
      final ts = entry['timestamp'];
      _history.add(
        PhotoErrorEvent(
          type: type,
          message: message,
          photoPath: photoPath,
          timestamp:
              ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
        ),
      );
    }
  }

  final _photoAddedController = StreamController<String>.broadcast();

  final _errorController = StreamController<PhotoErrorEvent>.broadcast();

  final _photoUploadedController = StreamController<String>.broadcast();

  Stream<String> get photoAdded => _photoAddedController.stream;

  Stream<String> get photoUploaded => _photoUploadedController.stream;

  Stream<PhotoErrorEvent> get errors => _errorController.stream;

  void notifyPhotoAdded(String photoPath) {
    _photoAddedController.add(photoPath);
  }

  void notifyError(String type, String message, {String? photoPath}) {
    final event = PhotoErrorEvent(
      type: type,
      message: message,
      photoPath: photoPath,
    );

    _history.insert(0, event);
    if (_history.length > 100) {
      _history.removeLast();
    }

    _errorController.add(event);
  }

  void notifyPhotoUploaded(String photoPath) {
    _photoUploadedController.add(photoPath);
  }

  void dispose() {
    _photoAddedController.close();
    _photoUploadedController.close();
    _errorController.close();
  }
}
