import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/task.dart';
import 'secure_storage_service.dart';

class BackendError implements Exception {
  final String code;
  final String message;
  final dynamic details;

  const BackendError({required this.code, required this.message, this.details});

  factory BackendError.fromJson(Map<String, dynamic> json) {
    return BackendError(
      code: json['code'] as String? ?? 'SERVER_ERROR',
      message: json['message'] as String? ?? '后台请求失败',
      details: json['details'],
    );
  }

  @override
  String toString() => message;
}

class ConflictInfo {
  final String taskId;
  final Map<String, dynamic> serverVersion;
  final Map<String, dynamic> clientVersion;

  const ConflictInfo({
    required this.taskId,
    required this.serverVersion,
    required this.clientVersion,
  });

  factory ConflictInfo.fromJson(Map<String, dynamic> json) {
    return ConflictInfo(
      taskId: json['taskId'] as String,
      serverVersion: Map<String, dynamic>.from(json['serverVersion'] as Map),
      clientVersion: Map<String, dynamic>.from(json['clientVersion'] as Map),
    );
  }
}

class BackendSession {
  final String token;
  final String userId;
  final String nickname;

  const BackendSession({
    required this.token,
    required this.userId,
    required this.nickname,
  });
}

class BackendTeamMember {
  final String userId;
  final String displayName;
  final String? phoneMasked;
  final String role;
  final bool online;

  const BackendTeamMember({
    required this.userId,
    required this.displayName,
    this.phoneMasked,
    required this.role,
    required this.online,
  });

  factory BackendTeamMember.fromJson(Map<String, dynamic> json) {
    return BackendTeamMember(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      phoneMasked: json['phoneMasked'] as String?,
      role: json['role'] as String,
      online: json['online'] as bool? ?? false,
    );
  }
}

class BackendTaskComment {
  final String id;
  final String clientCommentId;
  final String taskId;
  final String authorUserId;
  final String content;
  final String operationId;
  final String status;
  final DateTime serverCreatedAt;
  final String? authorName;
  final List<String> readByUserIds;

  const BackendTaskComment({
    required this.id,
    required this.clientCommentId,
    required this.taskId,
    required this.authorUserId,
    required this.content,
    required this.operationId,
    required this.status,
    required this.serverCreatedAt,
    this.authorName,
    this.readByUserIds = const [],
  });

  factory BackendTaskComment.fromJson(Map<String, dynamic> json) {
    return BackendTaskComment(
      id: json['id'] as String,
      clientCommentId:
          json['clientCommentId'] as String? ?? json['id'] as String,
      taskId: json['taskId'] as String,
      authorUserId: json['authorUserId'] as String,
      content: json['content'] as String,
      operationId: json['operationId'] as String? ?? json['id'] as String,
      status: json['status'] as String,
      serverCreatedAt: DateTime.parse(json['serverCreatedAt'] as String),
      authorName: json['authorName'] as String?,
      readByUserIds:
          (json['readByUserIds'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}

class StatusChangeLog {
  final String id;
  final String taskId;
  final String? distributionId;
  final String changedByUserId;
  final String previousStatus;
  final String newStatus;
  final String source;
  final DateTime createdAt;
  final String? changedByName;

  const StatusChangeLog({
    required this.id,
    required this.taskId,
    this.distributionId,
    required this.changedByUserId,
    required this.previousStatus,
    required this.newStatus,
    required this.source,
    required this.createdAt,
    this.changedByName,
  });

  factory StatusChangeLog.fromJson(Map<String, dynamic> json) {
    return StatusChangeLog(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      distributionId: json['distributionId'] as String?,
      changedByUserId: json['changedByUserId'] as String,
      previousStatus: json['previousStatus'] as String,
      newStatus: json['newStatus'] as String,
      source: json['source'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      changedByName: json['changedByName'] as String?,
    );
  }
}

class BackendDistribution {
  final String id;
  final String senderUserId;
  final String recipientUserId;
  final String? sourceTaskId;
  final String? recipientTaskId;
  final String? teamId;
  final String status;
  final String? remark;
  final int commentCount;
  final String? lastCommentSummary;
  final String? recipientName;
  final String? senderName;
  final String? recipientTaskStatus;
  final int unreadCommentCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BackendDistribution({
    required this.id,
    required this.senderUserId,
    required this.recipientUserId,
    this.sourceTaskId,
    this.recipientTaskId,
    this.teamId,
    required this.status,
    this.remark,
    required this.commentCount,
    this.lastCommentSummary,
    this.recipientName,
    this.senderName,
    this.recipientTaskStatus,
    this.unreadCommentCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory BackendDistribution.fromJson(Map<String, dynamic> json) {
    return BackendDistribution(
      id: json['id'] as String,
      senderUserId: json['senderUserId'] as String,
      recipientUserId: json['recipientUserId'] as String,
      sourceTaskId: json['sourceTaskId'] as String?,
      recipientTaskId: json['recipientTaskId'] as String?,
      teamId: json['teamId'] as String?,
      status: json['status'] as String,
      remark: json['remark'] as String?,
      commentCount: json['commentCount'] as int? ?? 0,
      lastCommentSummary: json['lastCommentSummary'] as String?,
      recipientName: json['recipientName'] as String?,
      senderName: json['senderName'] as String?,
      recipientTaskStatus: json['recipientTaskStatus'] as String?,
      unreadCommentCount: json['unreadCommentCount'] as int? ?? 0,
      createdAt: _parseDateStatic(json['createdAt']),
      updatedAt: _parseDateStatic(json['updatedAt']),
    );
  }

  static DateTime? _parseDateStatic(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}

/// pullTasks 返回结果：包含任务、评论和已删除任务 ID
class PullResult {
  final List<Task> tasks;
  final List<String> deletedTaskIds;
  final List<BackendTaskComment> comments;
  PullResult(
      {this.tasks = const [],
      this.deletedTaskIds = const [],
      this.comments = const []});
}

class BackendApiService {
  BackendApiService._();

  static final BackendApiService instance = BackendApiService._();

  static const _appKey = 'smart-task-app-2025';
  static const _tokenKey = 'backend.token';
  static const _userIdKey = 'backend.userId';
  static const _nicknameKey = 'backend.nickname';
  static const _baseUrlKey = 'backend.baseUrl';
  static const _accountKey = 'backend.account';
  static const _passwordKey = 'backend.password';
  static const _lastSyncAtKey = 'backend.lastSyncAt';
  static const _deviceIdKey = 'backend.deviceId';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String? _token;
  String? _userId;
  String? _nickname;
  String? _baseUrl;
  String? _account;
  String? _password;
  String? _deviceId;
  Timer? _heartbeatTimer;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  String? get userId => _userId;
  String? get nickname => _nickname;
  String? get account => _account;
  String? get password => _password;
  String? get deviceId => _deviceId;
  String get baseUrl => _baseUrl ?? defaultBaseUrl;

  String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:4100/api';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:4100/api';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://localhost:4100/api';
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = await SecureStorageService.instance.readBackendToken();
    _userId = prefs.getString(_userIdKey);
    _nickname = prefs.getString(_nicknameKey);
    _baseUrl = prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
    _account = prefs.getString(_accountKey);
    _password = await SecureStorageService.instance.readPassword();
    if (prefs.containsKey(_passwordKey)) {
      await prefs.remove(_passwordKey);
    }
    _deviceId = prefs.getString(_deviceIdKey);

    // Restore heartbeat if already logged in
    if (isLoggedIn && _deviceId != null) {
      _autoBindDevice();
      _startHeartbeat();
    }
  }

  Future<void> setBaseUrl(String value) async {
    final normalized =
        value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    _baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized);
  }

  Future<BackendSession> login({
    required String account,
    required String password,
    String? baseUrl,
    bool rememberPassword = true,
  }) async {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      await setBaseUrl(baseUrl);
    }

    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '${this.baseUrl}/auth/login',
        data: {'account': account, 'password': password},
        options: Options(headers: {'X-App-Key': _appKey}),
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('登录响应为空');
    final user = data['user'] as Map<String, dynamic>?;
    if (user == null) throw Exception('登录响应缺少用户信息');
    final token = data['token'] as String?;
    if (token == null) throw Exception('登录响应缺少令牌');
    final session = BackendSession(
      token: token,
      userId: user['id'] as String,
      nickname: user['nickname'] as String,
    );

    _token = session.token;
    _userId = session.userId;
    _nickname = session.nickname;
    _account = account;
    _password = rememberPassword ? password : null;

    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.instance.writeBackendToken(session.token);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_nicknameKey, session.nickname);
    await prefs.setString(_accountKey, account);
    await prefs.remove(_passwordKey);

    if (rememberPassword) {
      await SecureStorageService.instance.writePassword(password);
    } else {
      await SecureStorageService.instance.deletePassword();
    }

    // Auto bind device and start heartbeat
    await _autoBindDevice();
    _startHeartbeat();

    return session;
  }

  Future<BackendSession> register({
    required String nickname,
    required String password,
    required String inviteCode,
    String? phone,
    String? email,
    String? baseUrl,
  }) async {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      await setBaseUrl(baseUrl);
    }

    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '${this.baseUrl}/auth/register',
        data: _withoutNulls({
          'nickname': nickname,
          'password': password,
          'inviteCode': inviteCode,
          'phone': phone,
          'email': email,
        }),
        options: Options(headers: {'X-App-Key': _appKey}),
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('注册响应为空');
    final user = data['user'] as Map<String, dynamic>?;
    if (user == null) throw Exception('注册响应缺少用户信息');
    final token = data['token'] as String?;
    if (token == null) throw Exception('注册响应缺少令牌');

    final session = BackendSession(
      token: token,
      userId: user['id'] as String,
      nickname: user['nickname'] as String,
    );

    _token = session.token;
    _userId = session.userId;
    _nickname = session.nickname;

    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.instance.writeBackendToken(session.token);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_nicknameKey, session.nickname);
    await prefs.setString(_accountKey, nickname);
    await prefs.remove(_passwordKey);

    // Auto bind device and start heartbeat
    await _autoBindDevice();
    _startHeartbeat();

    return session;
  }

  Future<void> logout() async {
    _stopHeartbeat();
    _token = null;
    _userId = null;
    _nickname = null;
    _password = null;
    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.instance.deleteBackendToken();
    await prefs.remove(_userIdKey);
    await prefs.remove(_nicknameKey);
    await prefs.remove(_passwordKey);
    await SecureStorageService.instance.deletePassword();
  }

  Future<void> bindDevice({
    required String deviceName,
    required String platform,
    String? deviceId,
  }) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/devices/bind',
        data: _withoutNulls({
          'deviceId': deviceId,
          'deviceName': deviceName.trim().isEmpty ? 'APP设备' : deviceName,
          'platform': platform.trim().isEmpty ? 'unknown' : platform,
        }),
        options: _authOptions(),
      ),
    );
  }

  Future<void> _autoBindDevice() async {
    if (!isLoggedIn || _deviceId == null) return;
    try {
      await _request(
        () => _dio.post<Map<String, dynamic>>(
          '$baseUrl/devices/bind',
          data: _withoutNulls({
            'deviceId': _deviceId,
            'deviceName': 'Flutter APP',
            'platform': defaultTargetPlatform.name,
          }),
          options: _authOptions(),
        ),
      );
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!isLoggedIn || _deviceId == null) return;
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!isLoggedIn || _deviceId == null) return;
    try {
      await _request(
        () => _dio.post<Map<String, dynamic>>(
          '$baseUrl/devices/heartbeat',
          data: {'deviceId': _deviceId},
          options: _authOptions(),
        ),
      );
    } catch (_) {}
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 获取我加入的团队列表
  Future<List<Map<String, dynamic>>> getMyTeams() async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/teams/mine',
        options: _authOptions(),
      ),
    );
    final list = response.data?['teams'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createTeam({required String name}) async {
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/teams',
        data: {'name': name},
        options: _authOptions(),
      ),
    );
    return (response.data?['team'] ?? <String, dynamic>{})
        as Map<String, dynamic>;
  }

  Future<List<BackendTeamMember>> getTeamMembers(String teamId) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/teams/$teamId/members',
        options: _authOptions(),
      ),
    );
    final list = response.data?['members'] as List? ?? [];
    return list
        .map((json) => BackendTeamMember.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<BackendDistribution> distributeTask({
    required String sourceTaskId,
    required String recipientUserId,
    required String teamId,
    String? remark,
  }) async {
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/distributions',
        data: _withoutNulls({
          'sourceTaskId': sourceTaskId,
          'recipientUserId': recipientUserId,
          'teamId': teamId,
          'remark': remark,
        }),
        options: _authOptions(),
      ),
    );
    return BackendDistribution.fromJson(
      (response.data?['distribution'] ?? <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  Future<List<ConflictInfo>> pushTask(Task task, {bool deleted = false}) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/tasks/sync/push',
        data: {
          'tasks': [
            taskToBackendJson(
              task,
              deletedAt: deleted ? DateTime.now().toIso8601String() : null,
            ),
          ],
        },
        options: _authOptions(),
      ),
    );
    return _parseConflicts(response.data);
  }

  /// 批量推送任务到服务端
  Future<List<ConflictInfo>> pushTasks(List<Task> tasks,
      {List<String>? deletedIds}) async {
    if (!isLoggedIn ||
        (tasks.isEmpty && (deletedIds == null || deletedIds.isEmpty)))
      return [];
    final items = <Map<String, dynamic>>[];
    for (final task in tasks) {
      items.add(taskToBackendJson(task));
    }
    if (deletedIds != null) {
      final now = DateTime.now().toIso8601String();
      for (final id in deletedIds) {
        items.add({'id': id, 'deletedAt': now, 'updatedAt': now, 'version': 1});
      }
    }
    final allConflicts = <ConflictInfo>[];
    const batchSize = 50;
    for (var i = 0; i < items.length; i += batchSize) {
      final batch = items.sublist(
          i, i + batchSize > items.length ? items.length : i + batchSize);
      final response = await _request(
        () => _dio.post<Map<String, dynamic>>(
          '$baseUrl/tasks/sync/push',
          data: {'tasks': batch},
          options: _authOptions(),
        ),
      );
      allConflicts.addAll(_parseConflicts(response.data));
    }
    return allConflicts;
  }

  /// 推送原始任务数据（用于重试队列）
  Future<void> pushRawTasks(List<Map<String, dynamic>> rawTasks) async {
    if (!isLoggedIn || rawTasks.isEmpty) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/tasks/sync/push',
        data: {'tasks': rawTasks},
        options: _authOptions(),
      ),
    );
  }

  /// 强制推送（覆盖服务器版本）
  Future<void> forcePushTasks(List<Map<String, dynamic>> rawTasks) async {
    if (!isLoggedIn || rawTasks.isEmpty) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/tasks/sync/push',
        data: {'force': true, 'tasks': rawTasks},
        options: _authOptions(),
      ),
    );
  }

  /// 获取单个任务
  Future<Map<String, dynamic>?> fetchTask(String taskId) async {
    if (!isLoggedIn) return null;
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/tasks/$taskId',
        options: _authOptions(),
      ),
    );
    return response.data?['task'] as Map<String, dynamic>?;
  }

  /// 拉取远端任务（后端同时返回 comments，一并返回以减少请求）
  Future<PullResult> pullTasks(
      {DateTime? since, List<Task>? localTasks}) async {
    if (!isLoggedIn) return PullResult();
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/tasks/sync/pull',
        queryParameters: {
          if (since != null) 'since': since.toIso8601String(),
        },
        options: _authOptions(),
      ),
    );
    final tasksJson = response.data?['tasks'] as List? ?? [];
    final commentsJson = response.data?['comments'] as List? ?? [];

    final activeTasks = <Task>[];
    final deletedIds = <String>[];
    for (final json in tasksJson) {
      if (json is! Map<String, dynamic>) continue;
      final jsonMap = json;
      if (jsonMap['deleted'] == true) {
        final id = jsonMap['id'];
        if (id is String) deletedIds.add(id);
        continue;
      }
      final localMatch =
          localTasks?.where((t) => t.id == jsonMap['id']).firstOrNull;
      activeTasks.add(taskFromBackendJson(jsonMap, localTask: localMatch));
    }

    final comments = commentsJson
        .whereType<Map<String, dynamic>>()
        .map((json) => BackendTaskComment.fromJson(json))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncAtKey, DateTime.now().toIso8601String());

    return PullResult(
        tasks: activeTasks, deletedTaskIds: deletedIds, comments: comments);
  }

  Future<DateTime?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastSyncAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<List<BackendDistribution>> getDistributions() async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/distributions',
        options: _authOptions(),
      ),
    );
    final list = response.data?['distributions'] as List? ?? [];
    return list
        .map((json) =>
            BackendDistribution.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<BackendDistribution>> getDistributionsForTask(
      String taskId) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/distributions/by-task/$taskId',
        options: _authOptions(),
      ),
    );
    final list = response.data?['distributions'] as List? ?? [];
    return list
        .map((json) =>
            BackendDistribution.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<BackendTaskComment>> getRecipientComments(
      String distributionId) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/distributions/$distributionId/recipient-comments',
        options: _authOptions(),
      ),
    );
    final list = response.data?['comments'] as List? ?? [];
    return list
        .map(
            (json) => BackendTaskComment.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<StatusChangeLog>> getStatusChangeLogs(
      String distributionId) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/distributions/$distributionId/status-logs',
        options: _authOptions(),
      ),
    );
    final list = response.data?['logs'] as List? ?? [];
    return list
        .map((json) => StatusChangeLog.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// 确认收到分发任务
  Future<void> ackDistribution(String distributionId,
      {required String status}) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/distributions/$distributionId/ack',
        data: {'status': status},
        options: _authOptions(),
      ),
    );
  }

  Future<void> markCommentsRead(String distributionId) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/distributions/$distributionId/mark-comments-read',
        options: _authOptions(),
      ),
    );
  }

  Future<BackendTaskComment> addComment({
    required String taskId,
    required String content,
    String? clientCommentId,
    String? operationId,
    String? sourceDeviceId,
  }) async {
    final response = await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/tasks/$taskId/comments',
        data: _withoutNulls({
          'content': content,
          'clientCommentId': clientCommentId ?? const Uuid().v4(),
          'operationId': operationId ?? const Uuid().v4(),
          'sourceDeviceId': sourceDeviceId,
        }),
        options: _authOptions(),
      ),
    );
    return BackendTaskComment.fromJson(
      (response.data?['comment'] ?? <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  /// 编辑评论（仅作者本人）
  Future<BackendTaskComment> editComment({
    required String taskId,
    required String commentId,
    required String content,
  }) async {
    if (!isLoggedIn) throw Exception('未登录');
    final response = await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '$baseUrl/tasks/$taskId/comments/$commentId',
        data: {'content': content},
        options: _authOptions(),
      ),
    );
    return BackendTaskComment.fromJson(
      (response.data?['comment'] ?? <String, dynamic>{})
          as Map<String, dynamic>,
    );
  }

  /// 删除评论（仅作者本人）
  Future<void> deleteComment({
    required String taskId,
    required String commentId,
  }) async {
    if (!isLoggedIn) throw Exception('未登录');
    await _request(
      () => _dio.delete<Map<String, dynamic>>(
        '$baseUrl/tasks/$taskId/comments/$commentId',
        options: _authOptions(),
      ),
    );
  }

  Future<List<BackendTaskComment>> pullComments({DateTime? since}) async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/comments/sync/pull',
        queryParameters: {
          if (since != null) 'since': since.toIso8601String(),
        },
        options: _authOptions(),
      ),
    );
    final list = response.data?['comments'] as List? ?? [];
    return list
        .map(
            (json) => BackendTaskComment.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// 批量推送评论到服务端
  Future<void> pushCommentsBatch(List<Map<String, String>> comments) async {
    if (!isLoggedIn || comments.isEmpty) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/comments/sync/push',
        data: {'comments': comments},
        options: _authOptions(),
      ),
    );
  }

  // ---- Notifications ----

  Future<List<Map<String, dynamic>>> getNotifications() async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/notifications',
        options: _authOptions(),
      ),
    );
    final list = response.data?['notifications'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadNotificationCount() async {
    if (!isLoggedIn) return 0;
    try {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '$baseUrl/notifications/unread-count',
          options: _authOptions(),
        ),
      );
      return response.data?['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/notifications/$notificationId/read',
        options: _authOptions(),
      ),
    );
  }

  Future<void> markAllNotificationsRead() async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.post<Map<String, dynamic>>(
        '$baseUrl/notifications/read-all',
        options: _authOptions(),
      ),
    );
  }

  // ---- Activity ----

  Future<List<Map<String, dynamic>>> getActivityFeed() async {
    if (!isLoggedIn) return [];
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '$baseUrl/activity',
        options: _authOptions(),
      ),
    );
    final list = response.data?['activities'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ---- Reports ----

  Future<Map<String, dynamic>?> getReportSummary({
    String period = 'weekly',
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    if (!isLoggedIn) return null;
    try {
      final response = await _request(
        () => _dio.get<Map<String, dynamic>>(
          '$baseUrl/reports/summary',
          queryParameters: {
            'period': period,
            if (periodStart != null)
              'periodStart': periodStart.toUtc().toIso8601String(),
            if (periodEnd != null)
              'periodEnd': periodEnd.toUtc().toIso8601String(),
          },
          options: _authOptions(),
        ),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  // ---- Batch Operations ----

  Future<void> batchUpdateTasks({
    required List<String> taskIds,
    String? status,
    List<String>? tagIds,
    String? priority,
  }) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.patch<Map<String, dynamic>>(
        '$baseUrl/tasks/batch',
        data: _withoutNulls({
          'taskIds': taskIds,
          'status': status,
          'tagIds': tagIds,
          'priority': priority,
        }),
        options: _authOptions(),
      ),
    );
  }

  Future<void> batchDeleteTasks(List<String> taskIds) async {
    if (!isLoggedIn) return;
    await _request(
      () => _dio.delete<Map<String, dynamic>>(
        '$baseUrl/tasks/batch',
        data: {'taskIds': taskIds},
        options: _authOptions(),
      ),
    );
  }

  // ---- Export ----

  Future<String?> exportTasksCsv() async {
    if (!isLoggedIn) return null;
    try {
      final response = await _request(
        () => _dio.get<String>(
          '$baseUrl/admin/tasks/export',
          options: _authOptions().copyWith(
            responseType: ResponseType.plain,
          ),
        ),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  List<ConflictInfo> _parseConflicts(Map<String, dynamic>? data) {
    final raw = data?['conflicts'] as List?;
    if (raw == null || raw.isEmpty) return [];
    return raw
        .map((e) => ConflictInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Options _authOptions() {
    return Options(headers: {
      'Authorization': 'Bearer $_token',
      'X-App-Key': _appKey,
    });
  }

  Map<String, dynamic> taskToBackendJson(Task task, {String? deletedAt}) {
    // ★ 分发任务只推送 status 相关字段，避免跨用户内容覆盖
    final isDistribution = task.sourceType == 'team_distribution';
    if (isDistribution && deletedAt == null) {
      return _withoutNulls({
        'id': task.id,
        'status': _statusToBackend(task.status),
        'completedAt': task.completedAt?.toIso8601String(),
        'sourceType': task.sourceType,
        'sourceTaskId': task.sourceTaskId,
        'sourceDistributionId': task.sourceDistributionId,
        'teamId': task.teamId,
        'version': task.version ?? 1,
        'updatedAt': task.updatedAt.toIso8601String(),
      });
    }
    final payload = _withoutNulls({
      'id': task.id,
      'title': task.title,
      'content': task.content,
      'status': _statusToBackend(task.status),
      'priority': _priorityToBackend(task.priority),
      'startTime': task.startTime?.toIso8601String(),
      'dueTime': task.dueTime?.toIso8601String(),
      'completedAt': task.completedAt?.toIso8601String(),
      'reminderTime': task.reminderMinutes == null
          ? null
          : task.dueTime
              ?.subtract(Duration(minutes: task.reminderMinutes!))
              .toIso8601String(),
      'assignee': task.assignee,
      'parentId': task.parentId,
      'isRecurring': task.isRecurring,
      'recurringRule': task.recurringRule,
      'tagIds': task.tagIds.isNotEmpty ? task.tagIds : null,
      'attachmentPaths':
          task.attachmentPaths.isNotEmpty ? task.attachmentPaths : null,
      'reminderMinutes': task.reminderMinutes,
      'reminderDismissed': task.reminderDismissed,
      'reminderVoiceEnabled': task.reminderVoiceEnabled,
      'reminderVoiceType': task.reminderVoiceType,
      'reminderVoiceStyle': task.reminderVoiceStyle,
      'reminderVoiceSpeed': task.reminderVoiceSpeed,
      'reminderCustomVoicePath': task.reminderCustomVoicePath,
      'sourceType': task.sourceType,
      'sourceTaskId': task.sourceTaskId,
      'sourceDistributionId': task.sourceDistributionId,
      'teamId': task.teamId,
      'ownerUserId': task.ownerUserId,
      'version': task.version ?? 1,
      'sortOrder': task.sortOrder,
      'assigneeUserId': task.assigneeUserId,
      'updatedAt': task.updatedAt.toIso8601String(),
      'deletedAt': deletedAt,
    });
    // archivedAt 必须保留显式 null，恢复归档时服务端才能清除此字段。
    payload['archivedAt'] = task.archivedAt?.toIso8601String();
    return payload;
  }

  Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) {
    return Map.fromEntries(
      value.entries.where((entry) => entry.value != null),
    );
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() action,
      {bool allowRelogin = true}) async {
    try {
      return await action();
    } on DioException catch (e) {
      // 401 token 过期：尝试用保存的凭据静默重登后重放一次
      if (allowRelogin &&
          e.response?.statusCode == 401 &&
          _account != null &&
          _password != null) {
        try {
          await _silentRelogin();
          return _request(action, allowRelogin: false);
        } catch (_) {
          // 重登失败，落到下方错误处理
        }
      }
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['code'] != null) {
        throw BackendError.fromJson(data);
      }
      if (data is Map && data['message'] != null) {
        throw BackendError(
            code: 'SERVER_ERROR', message: data['message'] as String);
      }
      if (data is String && data.isNotEmpty) {
        throw BackendError(code: 'SERVER_ERROR', message: data);
      }
      throw BackendError(code: 'SERVER_ERROR', message: e.message ?? '后台请求失败');
    }
  }

  /// 静默重登：用保存的账号密码刷新 token（直接 _dio.post，不经 _request 以避免 401 递归）
  Future<void> _silentRelogin() async {
    if (_account == null || _password == null) throw Exception('无保存凭据');
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/auth/login',
      data: {'account': _account, 'password': _password},
      options: Options(headers: {'X-App-Key': _appKey}),
    );
    final data = response.data;
    final token = data?['token'] as String?;
    final user = data?['user'] as Map<String, dynamic>?;
    if (token == null || user == null) throw Exception('重登响应异常');
    _token = token;
    _userId = user['id'] as String;
    _nickname = user['nickname'] as String;
    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.instance.writeBackendToken(token);
    await prefs.setString(_userIdKey, _userId!);
    await prefs.setString(_nicknameKey, _nickname!);
  }

  /// Helper: get nullable value from json, fall back to localTask only if key is absent or value is null
  T? _jsonOrLocal<T>(
      Map<String, dynamic> json, String key, T? Function()? localGetter) {
    if (json.containsKey(key) && json[key] != null) {
      final v = json[key];
      // Coerce numeric types: double → int when T is int
      if (T == int && v is num) return v.toInt() as T?;
      return v as T?;
    }
    return localGetter?.call();
  }

  bool _parseBool(dynamic v, {bool defaultValue = false, bool? localFallback}) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v == null && localFallback != null) return localFallback;
    return defaultValue;
  }

  DateTime? _parseDateField(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      final parsed = DateTime.tryParse(v);
      // 后端可能返回 UTC 时间（带 Z 后缀），转换为本地时间，
      // 否则与本地 DateTime.now() 混用会导致排序/逾期判断偏移时区差。
      if (parsed != null && parsed.isUtc) return parsed.toLocal();
      return parsed;
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  Task taskFromBackendJson(Map<String, dynamic> json, {Task? localTask}) {
    // ★ 分发任务的 status-only 响应：缺少 title 表示后端只返回了状态字段
    // 保留本地所有内容字段，只更新 status / completedAt / version / updatedAt
    final isStatusOnly = !json.containsKey('title') && localTask != null;
    if (isStatusOnly) {
      return localTask.copyWith(
        status: json.containsKey('status')
            ? _statusFromBackend(json['status'] as String?)
            : null,
        completedAt: json.containsKey('completedAt')
            ? _parseDateField(json['completedAt'])
            : localTask.completedAt,
        version: json.containsKey('version')
            ? (json['version'] as num?)?.toInt()
            : localTask.version,
        updatedAt: json.containsKey('updatedAt')
            ? _parseDateField(json['updatedAt']) ?? localTask.updatedAt
            : localTask.updatedAt,
      );
    }
    final sourceType = json.containsKey('sourceType')
        ? (json['sourceType'] as String?)
        : (localTask?.sourceType);
    final task = Task(
      id: json['id'] as String,
      title: json['title'] as String,
      content: _jsonOrLocal(json, 'content', () => localTask?.content),
      status: _statusFromBackend(json['status'] as String?),
      priority: _priorityFromBackend(json['priority'] as String?),
      startTime: json.containsKey('startTime')
          ? _parseDateField(json['startTime'])
          : localTask?.startTime,
      dueTime: json.containsKey('dueTime')
          ? _parseDateField(json['dueTime'])
          : localTask?.dueTime,
      completedAt: json.containsKey('completedAt')
          ? _parseDateField(json['completedAt'])
          : localTask?.completedAt,
      archivedAt: json.containsKey('archivedAt')
          ? _parseDateField(json['archivedAt'])
          : localTask?.archivedAt,
      assignee: _jsonOrLocal(json, 'assignee', () => localTask?.assignee),
      parentId: _jsonOrLocal(json, 'parentId', () => localTask?.parentId),
      isRecurring: json.containsKey('isRecurring')
          ? _parseBool(json['isRecurring'],
              localFallback: localTask?.isRecurring)
          : (localTask?.isRecurring ?? false),
      recurringRule:
          _jsonOrLocal(json, 'recurringRule', () => localTask?.recurringRule),
      tagIds: json.containsKey('tagIds')
          ? _parseStringList(json['tagIds']) ?? []
          : (localTask?.tagIds ?? []),
      attachmentPaths: json.containsKey('attachmentPaths')
          ? _parseStringList(json['attachmentPaths']) ?? []
          : (localTask?.attachmentPaths ?? []),
      reminderMinutes: _jsonOrLocal(
          json, 'reminderMinutes', () => localTask?.reminderMinutes),
      reminderDismissed: json.containsKey('reminderDismissed')
          ? _parseBool(json['reminderDismissed'],
              localFallback: localTask?.reminderDismissed)
          : (localTask?.reminderDismissed ?? false),
      reminderVoiceEnabled: json.containsKey('reminderVoiceEnabled')
          ? _parseBool(json['reminderVoiceEnabled'],
              defaultValue: true,
              localFallback: localTask?.reminderVoiceEnabled)
          : (localTask?.reminderVoiceEnabled ?? true),
      reminderVoiceType: _jsonOrLocal(
          json, 'reminderVoiceType', () => localTask?.reminderVoiceType),
      reminderVoiceStyle: _jsonOrLocal(
          json, 'reminderVoiceStyle', () => localTask?.reminderVoiceStyle),
      reminderVoiceSpeed: _jsonOrLocal(
          json, 'reminderVoiceSpeed', () => localTask?.reminderVoiceSpeed),
      reminderCustomVoicePath: _jsonOrLocal(json, 'reminderCustomVoicePath',
          () => localTask?.reminderCustomVoicePath),
      sourceType: sourceType,
      sourceTaskId:
          _jsonOrLocal(json, 'sourceTaskId', () => localTask?.sourceTaskId),
      sourceDistributionId: _jsonOrLocal(
          json, 'sourceDistributionId', () => localTask?.sourceDistributionId),
      teamId: _jsonOrLocal(json, 'teamId', () => localTask?.teamId),
      ownerUserId:
          _jsonOrLocal(json, 'ownerUserId', () => localTask?.ownerUserId),
      version: _jsonOrLocal(json, 'version', () => localTask?.version),
      sortOrder: _jsonOrLocal(json, 'sortOrder', () => localTask?.sortOrder),
      assigneeUserId:
          _jsonOrLocal(json, 'assigneeUserId', () => localTask?.assigneeUserId),
      createdAt: json.containsKey('createdAt')
          ? (_parseDate(json['createdAt']) ??
              localTask?.createdAt ??
              DateTime.now())
          : (localTask?.createdAt ?? DateTime.now()),
      updatedAt: _parseDate(json['updatedAt']) ??
          localTask?.updatedAt ??
          DateTime.now(),
    );

    return task;
  }

  TaskStatus _statusFromBackend(String? value) {
    switch (value) {
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'pending':
      default:
        return TaskStatus.pending;
    }
  }

  String _statusToBackend(TaskStatus status) {
    switch (status) {
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
      case TaskStatus.pending:
        return 'pending';
    }
  }

  TaskPriority _priorityFromBackend(String? value) {
    switch (value) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'medium':
      default:
        return TaskPriority.medium;
    }
  }

  String _priorityToBackend(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'low';
      case TaskPriority.medium:
        return 'medium';
      case TaskPriority.high:
        return 'high';
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  List<String>? _parseStringList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    return null;
  }
}
