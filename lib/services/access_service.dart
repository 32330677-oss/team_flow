// lib/services/access_service.dart
//
// Roles & accounts of type 'User' (backend: /api/access).
//   * The Admin creates roles (any name), ticks their permissions and gives
//     one role to each account. Nothing here is hard-coded: the permission
//     list comes from the server (GET /api/access/permissions).
//   * Admin / Supervisor / StaffSupervisor are not managed here.

import 'package:dio/dio.dart';

import '../constants.dart';

class AppPermission {
  final String key;
  final String group;
  final String label;
  final List<String> requires;

  const AppPermission({required this.key, required this.group, required this.label, required this.requires});

  factory AppPermission.fromJson(Map j) => AppPermission(
        key: j['key'].toString(),
        group: (j['group'] ?? 'Other').toString(),
        label: (j['label'] ?? j['key']).toString(),
        requires: ((j['requires'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

class AppRole {
  final int id;
  final String name;
  final String description;
  final bool isActive;
  final int accounts;
  final List<String> permissions;
  final String? updatedAt;

  const AppRole({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.accounts,
    required this.permissions,
    this.updatedAt,
  });

  factory AppRole.fromJson(Map j) => AppRole(
        id: int.parse(j['role_id'].toString()),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        isActive: j['is_active'] == true,
        accounts: int.tryParse('${j['accounts'] ?? 0}') ?? 0,
        permissions: ((j['permissions'] as List?) ?? const []).map((e) => e.toString()).toList(),
        updatedAt: j['updated_at']?.toString(),
      );
}

class AppUserAccount {
  final int id;
  final String fullName;
  final String username;
  final String email;
  final String status;
  final int? roleId;
  final String? roleName;
  final bool roleActive;
  final String? lastLogin;

  const AppUserAccount({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.status,
    required this.roleId,
    required this.roleName,
    required this.roleActive,
    this.lastLogin,
  });

  bool get isActive => status == 'Active';

  factory AppUserAccount.fromJson(Map j) => AppUserAccount(
        id: int.parse(j['user_id'].toString()),
        fullName: (j['full_name'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        roleId: j['role_id'] == null ? null : int.tryParse(j['role_id'].toString()),
        roleName: j['role_name']?.toString(),
        roleActive: j['role_active'] == true,
        lastLogin: j['last_login']?.toString(),
      );
}

class AccessAuditEntry {
  final String action;
  final String targetType;
  final String? targetName;
  final String? actorName;
  final String createdAt;
  final Map details;

  const AccessAuditEntry({
    required this.action,
    required this.targetType,
    required this.targetName,
    required this.actorName,
    required this.createdAt,
    required this.details,
  });

  factory AccessAuditEntry.fromJson(Map j) => AccessAuditEntry(
        action: (j['action'] ?? '').toString(),
        targetType: (j['target_type'] ?? '').toString(),
        targetName: j['target_name']?.toString(),
        actorName: j['actor_name']?.toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        details: j['details'] is Map ? j['details'] as Map : const {},
      );
}

/// What the signed-in account may do (GET /api/access/me).
class MyAccess {
  final String? type;
  final String? roleName;
  final bool roleActive;
  final List<String> permissions;
  final Map<String, String> labels; // permission key -> what it means

  const MyAccess({
    required this.type,
    required this.roleName,
    required this.roleActive,
    required this.permissions,
    this.labels = const {},
  });

  bool has(String key) => permissions.contains(key);

  String labelOf(String key) => labels[key] ?? key;

  factory MyAccess.fromJson(Map j) {
    final role = j['role'];
    return MyAccess(
      type: j['type']?.toString(),
      roleName: role is Map ? role['name']?.toString() : null,
      roleActive: role is Map ? role['is_active'] == true : false,
      permissions: ((j['permissions'] as List?) ?? const []).map((e) => e.toString()).toList(),
      labels: j['labels'] is Map
          ? (j['labels'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
    );
  }
}

/// Error with the server's message, ready to show to the user.
class AccessException implements Exception {
  final String message;
  const AccessException(this.message);
  @override
  String toString() => message;
}

class AccessService {
  static final Dio _dio = ApiConfig.dio;

  static Future<T> _call<T>(Future<Response> Function() req, T Function(dynamic data) parse) async {
    try {
      final res = await req();
      final body = res.data;
      return parse(body is Map ? body['data'] : null);
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map && data['message'] != null ? data['message'].toString() : null;
      if (e.response == null) {
        throw const AccessException('Cannot reach the server. Check your connection and try again.');
      }
      throw AccessException(msg ?? 'Request failed (${e.response?.statusCode}).');
    }
  }

  static List<Map> _list(dynamic d) => ((d as List?) ?? const []).whereType<Map>().toList();

  static Future<MyAccess> me() => _call(() => _dio.get('/access/me'), (d) => MyAccess.fromJson(d as Map));

  static Future<List<AppPermission>> permissions() =>
      _call(() => _dio.get('/access/permissions'), (d) => _list(d).map(AppPermission.fromJson).toList());

  static Future<List<AppRole>> roles() =>
      _call(() => _dio.get('/access/roles'), (d) => _list(d).map(AppRole.fromJson).toList());

  static Future<AppRole> createRole({
    required String name,
    required String description,
    required List<String> permissions,
    required bool isActive,
  }) =>
      _call(
        () => _dio.post('/access/roles', data: {
          'name': name,
          'description': description,
          'permissions': permissions,
          'is_active': isActive,
        }),
        (d) => AppRole.fromJson(d as Map),
      );

  static Future<AppRole> updateRole(int id, Map<String, dynamic> changes) =>
      _call(() => _dio.put('/access/roles/$id', data: changes), (d) => AppRole.fromJson(d as Map));

  static Future<void> deleteRole(int id) => _call(() => _dio.delete('/access/roles/$id'), (_) {});

  static Future<List<AppUserAccount>> users() =>
      _call(() => _dio.get('/access/users'), (d) => _list(d).map(AppUserAccount.fromJson).toList());

  static Future<AppUserAccount> createUser({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required int roleId,
  }) =>
      _call(
        () => _dio.post('/access/users', data: {
          'full_name': fullName,
          'username': username,
          'email': email,
          'password': password,
          'role_id': roleId,
        }),
        (d) => AppUserAccount.fromJson(d as Map),
      );

  static Future<AppUserAccount> updateUser(int id, Map<String, dynamic> changes) =>
      _call(() => _dio.put('/access/users/$id', data: changes), (d) => AppUserAccount.fromJson(d as Map));

  static Future<AppUserAccount> setUserStatus(int id, bool active) => _call(
        () => _dio.patch('/access/users/$id/status', data: {'status': active ? 'Active' : 'Inactive'}),
        (d) => AppUserAccount.fromJson(d as Map),
      );

  static Future<void> resetPassword(int id, String password) =>
      _call(() => _dio.put('/access/users/$id/password', data: {'password': password}), (_) {});

  static Future<List<AccessAuditEntry>> audit({int limit = 200}) => _call(
        () => _dio.get('/access/audit', queryParameters: {'limit': limit}),
        (d) => _list(d).map(AccessAuditEntry.fromJson).toList(),
      );
}
