import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_queue_item.dart';
import 'backend_api_service.dart';

class SyncQueueService {
  SyncQueueService._();
  static final SyncQueueService instance = SyncQueueService._();

  static const _key = 'sync.queue.items';
  static const _maxQueueSize = 50;
  static const _maxRetries = 10;

  List<SyncQueueItem> _items = [];
  List<SyncQueueItem> get items => List.unmodifiable(_items);
  int get count => _items.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _items = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      _items = list
          .map((e) => SyncQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? error,
    String? errorCode,
  }) async {
    if (_items.length >= _maxQueueSize) {
      _items.removeAt(0);
    }
    final item = SyncQueueItem(
      id: const Uuid().v4(),
      type: type,
      payload: payload,
      error: error,
      errorCode: errorCode,
      createdAt: DateTime.now(),
    );
    _items.add(item);
    await _save();
  }

  Future<void> dequeue(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _save();
  }

  Future<void> clear() async {
    _items = [];
    await _save();
  }

  Future<void> removeByTaskId(String taskId) async {
    _items.removeWhere((item) {
      final payload = item.payload;
      if (payload is Map) return payload['id'] == taskId;
      return false;
    });
    await _save();
  }

  /// Retry all pending items. Returns number of items successfully retried.
  Future<int> retryAll() async {
    final backend = BackendApiService.instance;
    int succeeded = 0;
    final toRetry = List<SyncQueueItem>.from(_items);

    for (final item in toRetry) {
      try {
        await _retryItem(backend, item);
        _items.removeWhere((i) => i.id == item.id);
        succeeded++;
      } on BackendError catch (e) {
        if (_isPermanentError(e.code)) {
          _items.removeWhere((i) => i.id == item.id);
        } else {
          final idx = _items.indexWhere((i) => i.id == item.id);
          if (idx >= 0) {
            _items[idx] = item.copyWith(
              error: e.message,
              errorCode: e.code,
              retryCount: item.retryCount + 1,
              lastRetryAt: DateTime.now(),
            );
          }
        }
      } catch (e) {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx >= 0) {
          if (item.retryCount + 1 >= _maxRetries) {
            _items.removeAt(idx);
          } else {
            _items[idx] = item.copyWith(
              error: e.toString(),
              retryCount: item.retryCount + 1,
              lastRetryAt: DateTime.now(),
            );
          }
        }
      }
    }

    await _save();
    return succeeded;
  }

  Future<void> _retryItem(BackendApiService backend, SyncQueueItem item) async {
    switch (item.type) {
      case 'task_push':
        final payload = Map<String, dynamic>.from(item.payload);
        payload['updatedAt'] = DateTime.now().toIso8601String();
        await backend.pushRawTasks([payload]);
        break;
      case 'task_delete':
        final id = item.payload['id'] as String;
        await backend.pushRawTasks([
          {
            'id': id,
            'deletedAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ]);
        break;
      case 'comment_push':
        await backend.pushCommentsBatch([Map<String, String>.from(item.payload)]);
        break;
      case 'distribution_ack':
        await backend.ackDistribution(
          item.payload['distributionId'] as String,
          status: item.payload['status'] as String,
        );
        break;
    }
  }

  bool _isPermanentError(String code) {
    return code == 'AUTH_EXPIRED' ||
        code == 'AUTH_REQUIRED' ||
        code == 'FORBIDDEN' ||
        code == 'INVALID_APP_KEY';
  }
}
