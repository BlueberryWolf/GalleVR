import 'package:flutter/foundation.dart';

class ThumbnailProvider extends ChangeNotifier {
  static final ThumbnailProvider _instance = ThumbnailProvider._internal();

  factory ThumbnailProvider() {
    return _instance;
  }

  ThumbnailProvider._internal();

  static const int _maxThumbnails = 64;
  final Map<String, Uint8List> _thumbnails = {};

  void setThumbnail(String filePath, Uint8List thumbnailData) {
    if (_thumbnails.length >= _maxThumbnails) {
      _thumbnails.remove(_thumbnails.keys.first);
    }
    _thumbnails[filePath] = thumbnailData;
  }

  Uint8List? getThumbnail(String filePath) {
    return _thumbnails[filePath];
  }

  bool hasThumbnail(String filePath) {
    return _thumbnails.containsKey(filePath);
  }

  void clearThumbnails() {
    _thumbnails.clear();
  }
}
