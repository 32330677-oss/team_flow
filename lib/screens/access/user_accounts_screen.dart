// lib/screens/access/user_accounts_screen.dart
//
// Admin: accounts of type 'User'. Each account has one role (made in
// "Roles & Permissions"); the role decides what the account sees.
// Admin / Supervisor / Staff Supervisor accounts are not listed or changed here.

import 'package:flutter/material.dart';

import '../../services/access_service.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/custom_app_bar.dart';
import 'access_widgets.dart';

class UserAccountsScreen extends StatefulWidget {
  const UserAccountsScreen({super.key});

  @override
  State<UserAccountsScreen> createState() => _UserAccountsScreenState();
}

class _UserAccountsScreenState extends State<UserAccountsScreen> {
  bool _loading = true;
  String? _error;
  List<AppUserAccount> _users = [];
  List<AppRole> _roles = [];
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([AccessService.users(), AccessService.roles()]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AppUserAccount>;
        _roles = results[1] as List<AppRole>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  List<AppUserAccount> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users
        .where((u) =>
            u.fullName.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            (u.roleName ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _openEditor([AppUserAccount? user]) async {
    if (user == null && !_roles.any((r) => r.isActive)) {
      _snack('Create an active role first (Roles & Permissions).', error: true);
      return;
    }
    final saved = await showDialog<AppUserAccount>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountEditorDialog(user: user, roles: _roles),
    );
    if (saved == null) return;
    _snack(user == null ? 'Account "${saved.username}" created.' : 'Account "${saved.username}" saved.');
    _load();
  }

  Future<void> _resetPassword(AppUserAccount u) async {
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordDialog(user: u),
    );
    if (done == true) _snack('Password changed for "${u.username}".');
  }

  Future<void> _toggleStatus(AppUserAccount u) async {
    final activate = !u.isActive;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(activate ? 'Activate Account' : 'Deactivate Account'),
        content: Text(activate
            ? '"${u.fullName}" will be able to sign in again.'
            : '"${u.fullName}" will not be able to sign in. Nothing is deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? AppColors.primary : AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AccessService.setUserStatus(u.id, activate);
      if (!mounted) return;
      _snack(activate ? 'Account activated.' : 'Account deactivated.');
      _load();
    } catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    }
  }

  void _openAudit() {
    showDialog<void>(context: context, builder: (_) => const _AuditDialog());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'User Accounts',
        actions: [
          IconButton(tooltip: 'Activity log', icon: const Icon(Icons.history_rounded), onPressed: _openAudit),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? AccessErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const AccessInfoBanner(
                        text: 'Accounts of type "User". What each account can open is decided by its role '
                            '(Roles & Permissions). A deactivated account or an inactive role cannot sign in.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: accessInput('Search by name, username, email or role').copyWith(
                          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppDataTableCard(
                        title: 'Accounts',
                        subtitle: '${_users.where((u) => u.isActive).length} active of ${_users.length}',
                        icon: Icons.person_pin_rounded,
                        emptyMessage: _users.isEmpty
                            ? 'No accounts yet. Create the first one with "New Account".'
                            : 'No account matches your search.',
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                          label: const Text('New Account'),
                        ),
                        columns: const [
                          DataColumn(label: Text('  Name')),
                          DataColumn(label: Text('  Email')),
                          DataColumn(label: Text('  Role')),
                          DataColumn(label: Text('  Status')),
                          DataColumn(label: Text('  Last Sign-in')),
                          DataColumn(label: Text('  Actions')),
                        ],
                        rows: rows.map(_row).toList(),
                      ),
                    ],
                  ),
                ),
    );
  }

  DataRow _row(AppUserAccount u) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
    final Widget role;
    if (u.roleName == null) {
      role = StatusBadge(label: 'No role', color: Colors.orange.shade800);
    } else if (!u.roleActive) {
      role = Tooltip(
        message: 'This role is inactive: the account cannot sign in.',
        child: StatusBadge(label: '${u.roleName} (inactive)', color: Colors.orange.shade800),
      );
    } else {
      role = StatusBadge(label: u.roleName!, color: AppColors.primary);
    }
    return DataRow(cells: [
      DataCell(pad(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('@${u.username}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ))),
      DataCell(pad(Text(u.email.isEmpty ? '-' : u.email))),
      DataCell(pad(role)),
      DataCell(pad(StatusBadge.fromStatus(u.status))),
      DataCell(pad(Text(u.lastLogin ?? 'Never', style: const TextStyle(color: AppColors.textSecondary)))),
      DataCell(pad(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_rounded, size: 19, color: AppColors.primary),
          onPressed: () => _openEditor(u),
        ),
        IconButton(
          tooltip: 'Reset password',
          icon: const Icon(Icons.key_rounded, size: 19, color: AppColors.primary),
          onPressed: () => _resetPassword(u),
        ),
        IconButton(
          tooltip: u.isActive ? 'Deactivate' : 'Activate',
          icon: Icon(u.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
              size: 19, color: u.isActive ? AppColors.danger : Colors.green.shade700),
          onPressed: () => _toggleStatus(u),
        ),
      ]))),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Create / edit account
// ---------------------------------------------------------------------------
class _AccountEditorDialog extends StatefulWidget {
  final AppUserAccount? user;
  final List<AppRole> roles;
  const _AccountEditorDialog({required this.user, required this.roles});

  @override
  State<_AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<_AccountEditorDialog> {
  late final TextEditingController _fullName = TextEditingController(text: widget.user?.fullName ?? '');
  late final TextEditingController _username = TextEditingController(text: widget.user?.username ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.user?.email ?? '');
  final TextEditingController _password = TextEditingController();
  late int? _roleId = widget.user?.roleId;
  bool _hidePassword = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.user != null;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Active roles, plus the account's current role even if it is inactive
  // (so the dropdown shows it; saving it unchanged is allowed).
  List<AppRole> get _choices =>
      widget.roles.where((r) => r.isActive || r.id == widget.user?.roleId).toList();

  Future<void> _save() async {
    final fullName = _fullName.text.trim();
    final username = _username.text.trim();
    if (fullName.length < 3) {
      setState(() => _error = 'Enter the full name (at least 3 characters).');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9._@-]{3,50}$').hasMatch(username)) {
      setState(() => _error = 'Username: 3–50 characters, letters, digits and . _ @ - only.');
      return;
    }
    if (!_editing && _password.text.length < 8) {
      setState(() => _error = 'The password must be at least 8 characters.');
      return;
    }
    if (_roleId == null) {
      setState(() => _error = 'Choose a role.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final AppUserAccount saved = _editing
          ? await AccessService.updateUser(widget.user!.id, {
              'full_name': fullName,
              'username': username,
              'email': _email.text.trim(),
              if (_roleId != widget.user!.roleId) 'role_id': _roleId,
            })
          : await AccessService.createUser(
              fullName: fullName,
              username: username,
              email: _email.text.trim(),
              password: _password.text,
              roleId: _roleId!,
            );
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(_editing ? 'Edit Account' : 'New Account',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 4),
            TextField(controller: _fullName, enabled: !_saving, decoration: accessInput('Full name')),
            const SizedBox(height: 12),
            TextField(controller: _username, enabled: !_saving, decoration: accessInput('Username (used to sign in)')),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              decoration: accessInput('Email (optional, can also be used to sign in)'),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_saving,
                obscureText: _hidePassword,
                decoration: accessInput('Password (at least 8 characters)').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: choices.any((r) => r.id == _roleId) ? _roleId : null,
              isExpanded: true,
              decoration: accessInput('Role'),
              items: choices
                  .map((r) => DropdownMenuItem<int>(
                        value: r.id,
                        child: Text(r.isActive ? r.name : '${r.name} (inactive)', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _roleId = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reset password
// ---------------------------------------------------------------------------
class _ResetPasswordDialog extends StatefulWidget {
  final AppUserAccount user;
  const _ResetPasswordDialog({required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  bool _hide = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'The password must be at least 8 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AccessService.resetPassword(widget.user.id, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Reset Password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('New password for ${widget.user.fullName} (@${widget.user.username}).',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_saving,
            obscureText: _hide,
            decoration: accessInput('New password (at least 8 characters)').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: const Text('Change Password'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity log (roles and accounts)
// ---------------------------------------------------------------------------
class _AuditDialog extends StatefulWidget {
  const _AuditDialog();

  @override
  State<_AuditDialog> createState() => _AuditDialogState();
}

class _AuditDialogState extends State<_AuditDialog> {
  late final Future<List<AccessAuditEntry>> _future = AccessService.audit();

  static const Map<String, String> _actions = {
    'role.create': 'Role created',
    'role.update': 'Role changed',
    'role.delete': 'Role deleted',
    'user.create': 'Account created',
    'user.update': 'Account changed',
    'user.status': 'Account status changed',
    'user.password': 'Password reset',
  };

  String _target(AccessAuditEntry e) {
    final name = e.targetName ?? e.details['name']?.toString() ?? e.details['username']?.toString();
    return name ?? '(deleted)';
  }

  String _summary(AccessAuditEntry e) {
    final d = e.details;
    if (e.action == 'user.status') return '${d['from']} → ${d['to']}';
    if (e.action == 'user.password') return 'Password changed by the Admin';
    if (e.action == 'user.create') return 'Username: ${_short(d['username'])}';
    final parts = <String>[];
    d.forEach((k, v) {
      if (v is Map && v.containsKey('to')) {
        parts.add('$k: ${_short(v['from'])} → ${_short(v['to'])}');
      }
    });
    if (parts.isNotEmpty) return parts.join('  •  ');
    if (d['permissions'] is List) return '${(d['permissions'] as List).length} permission(s)';
    return '';
  }

  String _short(dynamic v) {
    if (v == null || v == '') return '—';
    if (v is List) return v.isEmpty ? 'none' : v.join(', ');
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<List<AccessAuditEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 200, child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
              }
              if (snap.hasError) {
                return SizedBox(
                    height: 200, child: AccessErrorView(message: '${snap.error}', onRetry: () => Navigator.pop(context)));
              }
              final list = snap.data ?? const <AccessAuditEntry>[];
              Widget pad(Widget c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c);
              return SingleChildScrollView(
                child: AppDataTableCard(
                  title: 'Activity Log',
                  subtitle: 'Changes to roles and accounts (latest first)',
                  icon: Icons.history_rounded,
                  emptyMessage: 'No changes yet.',
                  trailing: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  columns: const [
                    DataColumn(label: Text('  Date')),
                    DataColumn(label: Text('  By')),
                    DataColumn(label: Text('  Action')),
                    DataColumn(label: Text('  On')),
                    DataColumn(label: Text('  Details')),
                  ],
                  rows: list
                      .map((e) => DataRow(cells: [
                            DataCell(pad(Text(e.createdAt))),
                            DataCell(pad(Text(e.actorName ?? '-'))),
                            DataCell(pad(Text(_actions[e.action] ?? e.action))),
                            DataCell(pad(Text('${e.targetType}: ${_target(e)}'))),
                            DataCell(pad(SizedBox(
                              width: 360,
                              child: Tooltip(
                                message: _summary(e),
                                child: Text(_summary(e), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                            ))),
                          ]))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
