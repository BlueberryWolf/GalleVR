import 'dart:async';

// Class to represent an error event with detailed information
class PhotoErrorEvent {
  // The error type
  final String type;

  // The error message
  final String message;

  // The related photo path, if any
  final String? photoPath;

  // Constructor
  PhotoErrorEvent({
    required this.type,
    required this.message,
    this.photoPath,
  });
}

// Service for broadcasting photo-related events across the app
class PhotoEventService {
  // Singleton instance
  static final PhotoEventService _instance = PhotoEventService._internal();

  // Factory constructor to return the singleton instance
  factory PhotoEventService() {
    return _instance;
  }

  // Private constructor for singleton
  PhotoEventService._internal();

  // Stream controller for photo added events
  final _photoAddedController = StreamController<String>.broadcast();

  // Stream controller for error events
  final _errorController = StreamController<PhotoErrorEvent>.broadcast();

  // Stream of photo added events
  Stream<String> get photoAdded => _photoAddedController.stream;

  // Stream of error events
  Stream<PhotoErrorEvent> get errors => _errorController.stream;

  // Notify that a new photo has been added
  void notifyPhotoAdded(String photoPath) {
    _photoAddedController.add(photoPath);
  }

  // Notify about an error
  void notifyError(String type, String message, {String? photoPath}) {
    _errorController.add(
      PhotoErrorEvent(
        type: type,
        message: message,
        photoPath: photoPath,
      ),
    );
  }

  // Dispose resources
  void dispose() {
    _photoAddedController.close();
    _errorController.close();
  }
}
