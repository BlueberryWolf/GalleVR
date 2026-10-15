import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

/// Polls DNS to detect whether the internet is reachable.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _controller.stream;

  bool _hasConnection = true;
  bool get hasConnection => _hasConnection;

  Timer? _timer;
  bool _isChecking = false;
  bool _monitoring = false;

  void _scheduleNext() {
    _timer?.cancel();
    if (!_monitoring) return;
    _timer = Timer(
      _hasConnection
          ? const Duration(seconds: 60)
          : const Duration(seconds: 10),
      () => _checkConnection().whenComplete(_scheduleNext),
    );
  }

  void startMonitoring() {
    _timer?.cancel();
    _monitoring = true;
    _checkConnection().whenComplete(_scheduleNext);
    developer.log(
      'Connectivity monitoring started',
      name: 'ConnectivityService',
    );
  }

  void stopMonitoring() {
    _monitoring = false;
    _timer?.cancel();
    _timer = null;
    developer.log(
      'Connectivity monitoring stopped',
      name: 'ConnectivityService',
    );
  }

  Future<bool> checkConnectionManually() async {
    return await _checkConnection();
  }

  Future<bool> _checkConnection() async {
    if (_isChecking) return _hasConnection;
    _isChecking = true;

    bool isConnected = false;
    try {
      // Several hosts avoid false negatives when one is blocked or down.
      final hosts = ['vrchat.com', 'google.com', 'cloudflare.com'];

      for (final host in hosts) {
        try {
          final result = await InternetAddress.lookup(
            host,
          ).timeout(const Duration(seconds: 4));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            isConnected = true;
            break;
          }
        } catch (_) {}
      }
    } catch (e) {
      developer.log(
        'Error checking connection: $e',
        name: 'ConnectivityService',
      );
      isConnected = false;
    } finally {
      _isChecking = false;
    }

    if (isConnected != _hasConnection) {
      _hasConnection = isConnected;
      _controller.add(isConnected);
      developer.log(
        'Connectivity status changed: ${isConnected ? "ONLINE" : "OFFLINE"}',
        name: 'ConnectivityService',
      );
    }

    return isConnected;
  }
}
