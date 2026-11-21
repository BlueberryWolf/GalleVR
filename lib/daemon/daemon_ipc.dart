import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'daemon_paths.dart';

class DaemonInfo {
  final int pid;
  final int port;
  final String token;

  const DaemonInfo({
    required this.pid,
    required this.port,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'port': port,
    'token': token,
  };

  static DaemonInfo? fromJson(Map<String, dynamic> map) {
    final pid = map['pid'];
    final port = map['port'];
    final token = map['token'];
    if (pid is int && port is int && token is String && token.isNotEmpty) {
      return DaemonInfo(pid: pid, port: port, token: token);
    }
    return null;
  }

  static DaemonInfo? readFromDisk() {
    try {
      final file = File(DaemonPaths.getDaemonInfoPath());
      if (!file.existsSync()) return null;
      final decoded = json.decode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return DaemonInfo.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static void writeToDisk(DaemonInfo info) {
    try {
      final filePath = DaemonPaths.getDaemonInfoPath();
      final tmp = File('$filePath.tmp');
      tmp.writeAsStringSync(json.encode(info.toJson()), flush: true);
      tmp.renameSync(filePath);
    } catch (_) {}
  }

  static void removeFromDisk() {
    try {
      final file = File(DaemonPaths.getDaemonInfoPath());
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

String generateDaemonToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class DaemonIpcServer {
  ServerSocket? _server;
  final String _token;
  final Set<Socket> _authedClients = {};
  final Future<Map<String, dynamic>> Function(
    String cmd,
    Map<String, dynamic> msg,
  )
  _onCommand;

  DaemonIpcServer({
    required String token,
    required Future<Map<String, dynamic>> Function(
      String cmd,
      Map<String, dynamic> msg,
    )
    onCommand,
  }) : _token = token,
       _onCommand = onCommand;

  int get port => _server?.port ?? 0;
  bool get hasConnectedClients => _authedClients.isNotEmpty;

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleClient, onError: (_) {});
    return _server!.port;
  }

  void _handleClient(Socket socket) {
    var authed = false;
    final lineStream = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter());

    lineStream.listen(
      (line) async {
        if (line.trim().isEmpty) return;
        Map<String, dynamic> msg;
        try {
          final decoded = json.decode(line);
          if (decoded is! Map<String, dynamic>) return;
          msg = decoded;
        } catch (_) {
          return;
        }

        final id = msg['id'];
        final cmd = msg['cmd'] as String?;
        if (cmd == null) return;

        if (!authed) {
          if (cmd == 'auth' && msg['token'] == _token) {
            authed = true;
            _authedClients.add(socket);
            final resp = await _onCommand('getStatus', msg);
            _sendRaw(socket, {'id': id, 'ok': true, ...resp});
          } else {
            _sendRaw(socket, {'id': id, 'ok': false, 'error': 'unauthorized'});
            unawaited(socket.close());
          }
          return;
        }

        try {
          final resp = await _onCommand(cmd, msg);
          _sendRaw(socket, {'id': id, 'ok': true, ...resp});
        } catch (e) {
          _sendRaw(socket, {'id': id, 'ok': false, 'error': e.toString()});
        }
      },
      onDone: () {
        _authedClients.remove(socket);
        socket.destroy();
      },
      onError: (_) {
        _authedClients.remove(socket);
        socket.destroy();
      },
    );
  }

  void broadcastEvent(String event, [Map<String, dynamic>? payload]) {
    if (_authedClients.isEmpty) return;
    final data = <String, dynamic>{
      'event': event,
      if (payload != null) ...payload,
    };
    final line = '${json.encode(data)}\n';
    final dead = <Socket>[];
    for (final client in _authedClients) {
      try {
        client.write(line);
      } catch (_) {
        dead.add(client);
      }
    }
    for (final d in dead) {
      _authedClients.remove(d);
      d.destroy();
    }
  }

  void _sendRaw(Socket socket, Map<String, dynamic> payload) {
    try {
      socket.write('${json.encode(payload)}\n');
    } catch (_) {}
  }

  Future<void> stop() async {
    for (final client in List<Socket>.from(_authedClients)) {
      try {
        client.destroy();
      } catch (_) {}
    }
    _authedClients.clear();
    await _server?.close();
    _server = null;
  }
}

class DaemonClient {
  static final DaemonClient _instance = DaemonClient._internal();
  factory DaemonClient() => _instance;
  DaemonClient._internal();

  Socket? _socket;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  bool _isWatching = false;
  List<Map<String, dynamic>> _initialHistory = const [];

  bool get isConnected => _isConnected;
  bool get isWatching => _isWatching;
  List<Map<String, dynamic>> get initialHistory => _initialHistory;
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isDaemonAvailable {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    return File(DaemonPaths.getDaemonExePath()).existsSync();
  }

  Future<bool> ensureConnected({bool startIfMissing = true}) async {
    if (_isConnected && _socket != null) return true;
    if (!Platform.isWindows && !Platform.isLinux) return false;

    if (await _tryConnectExisting()) {
      return true;
    }

    if (!startIfMissing || !isDaemonAvailable) {
      return false;
    }

    try {
      final daemonExe = DaemonPaths.getDaemonExePath();
      developer.log(
        'Starting background daemon: $daemonExe',
        name: 'DaemonClient',
      );
      await Process.start(
        daemonExe,
        const <String>[],
        mode: ProcessStartMode.detached,
      );

      for (int attempt = 0; attempt < 25; attempt++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (await _tryConnectExisting()) {
          return true;
        }
      }
    } catch (e) {
      developer.log('Failed to start daemon: $e', name: 'DaemonClient');
    }

    return false;
  }

  Future<bool> _tryConnectExisting() async {
    final info = DaemonInfo.readFromDisk();
    if (info == null) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        info.port,
        timeout: const Duration(milliseconds: 500),
      );
      _socket = socket;
      _pending.clear();

      utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onDone: _handleDisconnect,
            onError: (_) => _handleDisconnect(),
          );

      final authResp = await sendCommand(
        'auth',
        {'token': info.token},
        const Duration(seconds: 2),
      );

      if (authResp?['ok'] == true) {
        _isConnected = true;
        _isWatching = authResp?['watching'] == true;
        final hist = authResp?['history'];
        if (hist is List) {
          _initialHistory = hist.whereType<Map<String, dynamic>>().toList();
        }
        developer.log(
          'Connected to gallevr_daemon (pid=${info.pid}, port=${info.port})',
          name: 'DaemonClient',
        );
        return true;
      }

      disconnect();
      return false;
    } catch (_) {
      socket?.destroy();
      if (_socket == socket) {
        _socket = null;
      }
      return false;
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = json.decode(line);
      if (decoded is! Map<String, dynamic>) return;

      final id = decoded['id'];
      if (id is int && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(decoded);
        return;
      }

      final event = decoded['event'] as String?;
      if (event != null) {
        if (event == 'watcherState') {
          _isWatching = decoded['watching'] == true;
        }
        _eventController.add(decoded);
      }
    } catch (_) {}
  }

  void _handleDisconnect() {
    _isConnected = false;
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete({'ok': false, 'error': 'disconnected'});
      }
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>?> sendCommand(
    String cmd, [
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 3),
  ]) async {
    final socket = _socket;
    if (socket == null) return null;

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final payload = <String, dynamic>{
      'id': id,
      'cmd': cmd,
      if (args != null) ...args,
    };

    try {
      socket.write('${json.encode(payload)}\n');
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pending.remove(id);
      return null;
    }
  }

  Future<void> reloadConfig() async {
    if (!_isConnected) return;
    final resp = await sendCommand('reloadConfig');
    if (resp?['ok'] == true && resp?['watching'] is bool) {
      _isWatching = resp!['watching'] as bool;
    }
  }

  Future<void> showTrayBalloon(String title, String body) async {
    if (!_isConnected) return;
    await sendCommand('showTrayBalloon', {'title': title, 'body': body});
  }

  Future<void> shutdownDaemon() async {
    if (!_isConnected) return;
    await sendCommand(
      'shutdown',
      null,
      const Duration(milliseconds: 500),
    );
    disconnect();
  }

  void disconnect() {
    _isConnected = false;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete({'ok': false, 'error': 'closed'});
      }
    }
    _pending.clear();
  }
}
