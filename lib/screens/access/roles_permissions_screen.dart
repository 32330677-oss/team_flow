// lib/screens/access/roles_permissions_screen.dart
//
// Admin: roles for accounts of type 'User'.
// The Admin names each role (and can rename it any time) and ticks what it
// may do. The list of permissions comes from the server; nothing about a
// specific role (e.g. "QC Manager") is written in the app.

import 'package:flutter/material.dart';

import '../../services/access_service.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/custom_app_bar.dart';
import 'access_widgets.dart';

class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({super.key});

  @override
  State<RolesPermissionsScreen> createState() => _RolesPermissionsScreenState();
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  bool _loading = true;
  String? _error;
  List<AppRole> _roles = [];
  List<AppPermission> _permissions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([AccessService.permissions(), AccessService.roles()]);
      if (!mounted) return;
      setState(() {
        _permissions = results[0] as List<AppPermission>;
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

  String _labelOf(String key) {
    for (final p in _permissions) {
      if (p.key == key) return p.label;
    }
    return key;
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

  Future<void> _openEditor([AppRole? role]) async {
    final saved = await showDialog<AppRole>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoleEditorDialog(role: role, permissions: _permissions),
    );
    if (saved == null) return;
    _snack(role == null ? 'Role "${saved.name}" created.' : 'Role "${saved.name}" saved.');
    _load();
  }

  Future<void> _delete(AppRole role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete the role "${role.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AccessService.deleteRole(role.id);
      if (!mounted) return;
      _snack('Role "${role.name}" deleted.');
      _load();
    } catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Roles & Permissions',
        actions: [
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
                        text: 'Roles are for accounts of type "User". Name a role, tick what it may do, '
                            'then give it to accounts in "User Accounts". Admin, Supervisor and Staff '
                            'Supervisor accounts are not affected.',
                      ),
                      const SizedBox(height: 14),
                      AppDataTableCard(
                        title: 'Roles',
                        subtitle: '${_roles.length} role(s)',
                        icon: Icons.admin_panel_settings_rounded,
                        emptyMessage: 'No roles yet. Create the first one with "New Role".',
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New Role'),
                        ),
                        columns: const [
                          DataColumn(label: Text('  Role')),
                          DataColumn(label: Text('  Permissions')),
                          DataColumn(label: Text('  Accounts')),
                          DataColumn(label: Text('  Status')),
                          DataColumn(label: Text('  Last Change')),
                          DataColumn(label: Text('  Actions')),
                        ],
                        rows: _roles.map(_row).toList(),
                      ),
                    ],
                  ),
                ),
    );
  }

  DataRow _row(AppRole r) {
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
    return DataRow(cells: [
      DataCell(pad(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (r.description.isNotEmpty)
            SizedBox(
              width: 240,
              child: Text(r.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ),
        ],
      ))),
      DataCell(pad(Tooltip(
        message: r.permissions.isEmpty ? 'No permissions' : r.permissions.map(_labelOf).join('\n'),
        child: Text(
          r.permissions.isEmpty ? 'None' : '${r.permissions.length} of ${_permissions.length}',
          style: TextStyle(color: r.permissions.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
        ),
      ))),
      DataCell(pad(Text('${r.accounts}'))),
      DataCell(pad(StatusBadge.fromStatus(r.isActive ? 'Active' : 'Inactive'))),
      DataCell(pad(Text(r.updatedAt ?? '-', style: const TextStyle(color: AppColors.textSecondary)))),
      DataCell(pad(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_rounded, size: 19, color: AppColors.primary),
          onPressed: () => _openEditor(r),
        ),
        IconButton(
          tooltip: r.accounts > 0 ? 'Used by ${r.accounts} account(s): deactivate it instead' : 'Delete',
          icon: Icon(Icons.delete_outline_rounded,
              size: 19, color: r.accounts > 0 ? AppColors.border : AppColors.danger),
          onPressed: r.accounts > 0 ? null : () => _delete(r),
        ),
      ]))),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Create / edit dialog
// ---------------------------------------------------------------------------
class _RoleEditorDialog extends StatefulWidget {
  final AppRole? role;
  final List<AppPermission> permissions;
  const _RoleEditorDialog({required this.role, required this.permissions});

  @override
  State<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<_RoleEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.role?.name ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.role?.description ?? '');
  late bool _active = widget.role?.isActive ?? true;
  late final Set<String> _selected = {...?widget.role?.permissions};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  AppPermission? _find(String key) {
    for (final p in widget.permissions) {
      if (p.key == key) return p;
    }
    return null;
  }

  // Ticking a permission also ticks what it needs; unticking one also
  // unticks what depends on it. (The server applies the same rule.)
  void _toggle(String key, bool on) {
    setState(() {
      if (on) {
        void add(String k) {
          if (!_selected.add(k)) return;
          for (final r in _find(k)?.requires ?? const <String>[]) {
            add(r);
          }
        }

        add(key);
      } else {
        void remove(String k) {
          if (!_selected.remove(k)) return;
          for (final p in widget.permissions) {
            if (p.requires.contains(k)) remove(p.key);
          }
        }

        remove(key);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter a role name (at least 2 characters).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final perms = _selected.toList()..sort();
      final AppRole saved = widget.role == null
          ? await AccessService.createRole(
              name: name, description: _description.text.trim(), permissions: perms, isActive: _active)
          : await AccessService.updateRole(widget.role!.id, {
              'name': name,
              'description': _description.text.trim(),
              'permissions': perms,
              'is_active': _active,
            });
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
    final groups = <String, List<AppPermission>>{};
    for (final p in widget.permissions) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }
    final editing = widget.role != null;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
      title: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(editing ? 'Edit Role' : 'New Role',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                enabled: !_saving,
                decoration: accessInput('Role name', hint: 'e.g. QC Manager'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !_saving,
                maxLines: 2,
                decoration: accessInput('Description (optional)'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
                title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Accounts with an inactive role cannot sign in.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                value: _active,
                onChanged: _saving ? null : (v) => setState(() => _active = v),
              ),
              const Divider(color: AppColors.border),
              const SizedBox(height: 4),
              const Text('Permissions',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              if (widget.permissions.isEmpty)
                const Text('No permissions are available yet.', style: TextStyle(color: AppColors.textSecondary)),
              for (final entry in groups.entries) ...[
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(entry.key,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
                for (final p in entry.value)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
                    value: _selected.contains(p.key),
                    onChanged: _saving ? null : (v) => _toggle(p.key, v ?? false),
                    title: Text(p.label, style: const TextStyle(fontSize: 13.5)),
                    subtitle: p.requires.isEmpty
                        ? null
                        : Text('Also needs: ${p.requires.map((k) => _find(k)?.label ?? k).join(', ')}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
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
              : Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
