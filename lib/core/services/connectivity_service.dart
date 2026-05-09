import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

/// Service to monitor internet connectivity status across platforms
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

  /// Starts monitoring internet connection periodically
  void startMonitoring() {
    _timer?.cancel();
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConnection();
    });
    developer.log('Connectivity monitoring started', name: 'ConnectivityService');
  }

  /// Stops monitoring internet connection
  void stopMonitoring() {
    _timer?.cancel();
    developer.log('Connectivity monitoring stopped', name: 'ConnectivityService');
  }

  /// Force a manual check of the connection
  Future<bool> checkConnectionManually() async {
    return await _checkConnection();
  }

  Future<bool> _checkConnection() async {
    if (_isChecking) return _hasConnection;
    _isChecking = true;

    bool isConnected = false;
    try {
      // Perform DNS lookups for multiple robust hosts to avoid false negatives.
      final hosts = ['vrchat.com', 'google.com', 'cloudflare.com'];
      
      for (final host in hosts) {
        try {
          final result = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 4));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            isConnected = true;
            break;
          }
        } catch (_) {
          // Continue to next host if this one fails
        }
      }
    } catch (e) {
      developer.log('Error checking connection: $e', name: 'ConnectivityService');
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
