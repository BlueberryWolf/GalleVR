import 'dart:async';
import 'dart:isolate';

typedef WorkerTask<T, R> = FutureOr<R> Function(T params);

class IsolateWorkerPool {
  static final IsolateWorkerPool _instance = IsolateWorkerPool._internal();
  factory IsolateWorkerPool() => _instance;

  final int _poolSize;
  final List<_WorkerInstance> _workers = [];
  final List<_PendingTask> _taskQueue = [];
  bool _initialized = false;

  IsolateWorkerPool._internal({int poolSize = 4}) : _poolSize = poolSize;

  Future<void> initialize() async {
    if (_initialized) return;

    final spawnFutures = <Future<void>>[];
    for (int i = 0; i < _poolSize; i++) {
      final worker = _WorkerInstance();
      spawnFutures.add(worker.start());
      _workers.add(worker);
    }

    await Future.wait(spawnFutures);

    _initialized = true;
    _processQueue();
  }

  Future<R> execute<T, R>(WorkerTask<T, R> task, T params) {
    final completer = Completer<R>();
    _taskQueue.add(_PendingTask(task, params, completer));
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (!_initialized || _taskQueue.isEmpty) return;

    final availableWorker = _workers.firstWhere((w) => !w.isBusy, orElse: () => _workers[0]);
    if (availableWorker.isBusy) {
      return;
    }

    final task = _taskQueue.removeAt(0);
    availableWorker.runTask(task);
    
    if (_taskQueue.isNotEmpty) {
      Timer.run(_processQueue);
    }
  }

  void dispose() {
    for (var worker in _workers) {
      worker.stop();
    }
    _workers.clear();
    _initialized = false;
  }
}

class _WorkerInstance {
  Isolate? _isolate;
  SendPort? _sendPort;
  bool isBusy = false;
  _PendingTask? _currentTask;

  Future<void> start() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_workerEntry, receivePort.sendPort);

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

    return completer.future;
  }

  void runTask(_PendingTask task) {
    isBusy = true;
    _currentTask = task;
    _sendPort?.send(_WorkerRequest(task.task, task.params));
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
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
