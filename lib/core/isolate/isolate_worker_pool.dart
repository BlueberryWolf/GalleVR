import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

typedef WorkerTask<T, R> = FutureOr<R> Function(T params);

class IsolateWorkerPool {
  static final IsolateWorkerPool _instance = IsolateWorkerPool._internal();
  factory IsolateWorkerPool() => _instance;

  static const Duration _idleTimeout = Duration(seconds: 45);

  final int _poolSize;
  final List<_WorkerInstance> _workers = [];
  final List<_PendingTask> _taskQueue = [];
  Timer? _idleTimer;
  bool _disposed = false;

  IsolateWorkerPool._internal()
    : _poolSize = math.max(1, math.min(2, Platform.numberOfProcessors - 1));

  Future<void> initialize() async {
    _disposed = false;
  }

  Future<R> execute<T, R>(WorkerTask<T, R> task, T params) {
    _disposed = false;
    final completer = Completer<R>();
    _taskQueue.add(_PendingTask(task, params, completer));
    _idleTimer?.cancel();
    _idleTimer = null;
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_disposed) return;
    while (_taskQueue.isNotEmpty) {
      _WorkerInstance? worker;
      for (final w in _workers) {
        if (w.isReady && !w.isBusy) {
          worker = w;
          break;
        }
      }
      if (worker == null) {
        final starting = _workers.where((w) => !w.isReady).length;
        if (_workers.length < _poolSize && starting < _taskQueue.length) {
          final w = _WorkerInstance();
          _workers.add(w);
          w.start().then(
            (_) => _processQueue(),
            onError: (Object e) {
              _workers.remove(w);
              if (_workers.isEmpty) {
                for (final t in _taskQueue) {
                  t.completer.completeError(e);
                }
                _taskQueue.clear();
              }
            },
          );
        }
        return;
      }
      worker.runTask(_taskQueue.removeAt(0));
    }
    _scheduleIdleShutdown();
  }

  void _scheduleIdleShutdown() {
    if (_workers.any((w) => w.isBusy || !w.isReady)) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      _idleTimer = null;
      if (_taskQueue.isNotEmpty || _workers.any((w) => w.isBusy)) return;
      for (final w in _workers) {
        w.stop();
      }
      _workers.clear();
    });
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    for (var worker in _workers) {
      worker.stop();
    }
    _workers.clear();
  }
}

class _WorkerInstance {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool isBusy = false;
  _PendingTask? _currentTask;

  bool get isReady => _sendPort != null;

  Future<void> start() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final completer = Completer<void>();
    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else if (message is _WorkerResult) {
        isBusy = false;
        if (message.isError) {
          _currentTask?.completer.completeError(message.error!);
        } else {
          _currentTask?.completer.complete(message.result);
        }
        _currentTask = null;
        IsolateWorkerPool._instance._processQueue();
      }
    });
    try {
      _isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);
    } catch (e) {
      receivePort.close();
      rethrow;
    }
    return completer.future;
  }

  void runTask(_PendingTask task) {
    isBusy = true;
    _currentTask = task;
    _sendPort!.send(_WorkerRequest(task.task, task.params));
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
  }
}

class _PendingTask {
  final Function task;
  final dynamic params;
  final Completer<dynamic> completer;

  _PendingTask(this.task, this.params, this.completer);
}

class _WorkerRequest {
  final Function task;
  final dynamic params;

  _WorkerRequest(this.task, this.params);
}

class _WorkerResult {
  final dynamic result;
  final dynamic error;
  final bool isError;

  _WorkerResult.success(this.result) : error = null, isError = false;
  _WorkerResult.error(this.error) : result = null, isError = true;
}

void _workerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is _WorkerRequest) {
      try {
        final result = await message.task(message.params);
        mainSendPort.send(_WorkerResult.success(result));
      } catch (e) {
        mainSendPort.send(_WorkerResult.error(e.toString()));
      }
    }
  });
}
