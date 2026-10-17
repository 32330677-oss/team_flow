// lib/screens/user_shell.dart
//
// Home of an account of type 'User' (users.role = 'User').
// The menu is built from the account's permissions (GET /api/access/me):
// a page is shown only if the role the Admin gave this account has the
// page's permission. No role name is written here, so the Admin can name
// roles freely ("QC Manager", ...) and change them at any time.

import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/access_service.dart';
import '../services/dpr_api.dart';
import '../widgets/app_data_table.dart';
import 'change_password_screen.dart';
import 'dpr/dpr_pages.dart';
import 'dpr/dpr_registers_screen.dart';
import 'dpr/dpr_report_screen.dart';
import 'dpr/dpr_setup_screen.dart';

/// A page of the User area, shown when the account has [permission].
class _UserPage {
  final String id;
  final IconData icon;
  final String label;
  final String? permission; // null: every User account
  final Widget Function(MyAccess access, void Function(String id) open) build;
  const _UserPage(this.id, this.icon, this.label, this.permission, this.build);
}

final List<_UserPage> _pages = [
  _UserPage('user_home', Icons.space_dashboard_rounded, 'Home', null, (a, open) => _HomePage(access: a, open: open)),
  _UserPage('dpr_dashboard', Icons.insights_rounded, 'DPR Dashboard', 'dpr.view',
      (a, open) => DprDashboardPage(onOpenDay: (d) {
            DprState.date.value = parseYmd(d);
            open('dpr_report');
          })),
  _UserPage('dpr_report', Icons.assignment_rounded, 'Daily Progress Report', 'dpr.view', (a, open) => const DprReportPage()),
  _UserPage('dpr_alloc', Icons.grid_view_rounded, 'Resource Allocation', 'dpr.view', (a, open) => const DprAllocPage()),
  _UserPage('dpr_registers', Icons.report_rounded, 'NCR & Concerns', 'dpr.view', (a, open) => const DprRegistersPage()),
  _UserPage('dpr_archive', Icons.inventory_2_rounded, 'Issued Reports', 'dpr.view', (a, open) => const DprArchivePage()),
  _UserPage('dpr_differences', Icons.compare_arrows_rounded, 'Manual vs System', 'dpr.view', (a, open) => const DprDifferencesPage()),
  _UserPage('dpr_setup', Icons.settings_suggest_rounded, 'Contracts Setup', 'dpr.setup', (a, open) => const DprSetupPage()),
];

class UserShell extends StatefulWidget {
  final String userName;
  const UserShell({super.key, required this.userName});

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MyAccess? _access;
  String? _error;
  String _selected = _pages.first.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final a = await AccessService.me();
      if (!mounted) return;
      DprState.permissions = a.permissions.toSet();
      setState(() {
        _access = a;
        if (!_visible(a).any((p) => p.id == _selected)) _selected = _pages.first.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<_UserPage> _visible(MyAccess a) =>
      _pages.where((p) => p.permission == null || a.has(p.permission!)).toList();

  void _select(String id) {
    final s = _scaffoldKey.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
    setState(() => _selected = id);
  }

  void _changePassword() {
    final s = _scaffoldKey.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  void _logout() {
    final s = _scaffoldKey.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dCtx);
              ApiConfig.logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator(color: AppColors.primary)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      OutlinedButton.icon(
                          onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                      const SizedBox(width: 10),
                      TextButton(onPressed: ApiConfig.logout, child: const Text('Log Out')),
                    ]),
                  ]),
                ),
        ),
      );
    }

    final pages = _visible(access);
    final page = pages.firstWhere((p) => p.id == _selected, orElse: () => pages.first);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1000;
      final sidebar = _UserSidebar(
        userName: widget.userName,
        roleName: access.roleName,
        pages: pages,
        selected: page.id,
        onSelect: _select,
        onChangePassword: _changePassword,
        onLogout: _logout,
      );
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.background,
        drawer: wide ? null : Drawer(backgroundColor: AppColors.primary, width: 260, child: sidebar),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: wide
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'Menu',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
          title: Text(page.label, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primary,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
          ],
        ),
        body: Row(children: [
          if (wide) sidebar,
          Expanded(child: KeyedSubtree(key: ValueKey(page.id), child: page.build(access, _select))),
        ]),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Sidebar (same look as the Admin sidebar)
// ---------------------------------------------------------------------------
class _UserSidebar extends StatelessWidget {
  final String userName;
  final String? roleName;
  final List<_UserPage> pages;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const _UserSidebar({
    required this.userName,
    required this.roleName,
    required this.pages,
    required this.selected,
    required this.onSelect,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: AppColors.primary,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 4),
            child: Text('ASIK ENGINEERING CONSTRUCTION',
                maxLines: 2,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(roleName ?? 'User',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              for (final p in pages) _tile(p.icon, p.label, () => onSelect(p.id), selected: p.id == selected),
            ]),
          ),
          Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.12)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          _tile(Icons.lock_reset_rounded, 'Change Password', onChangePassword),
          _tile(Icons.logout_rounded, 'Log Out', onLogout),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 20, color: selected ? AppColors.accent : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------
class _HomePage extends StatelessWidget {
  final MyAccess access;
  final void Function(String id) open;
  const _HomePage({required this.access, required this.open});

  @override
  Widget build(BuildContext context) {
    final pages = _pages.where((p) => p.permission != null && access.has(p.permission!)).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, Color(0xff2a4d8f)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.verified_user_rounded, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(access.roleName ?? 'User',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                pages.isEmpty
                    ? 'Your role has no pages yet. Please contact the administrator.'
                    : 'You have access to ${pages.length} section(s).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: pages
            .map((p) => InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => open(p.id),
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
                        child: Icon(p.icon, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    ]),
                  ),
                ))
            .toList(),
      ),
      const SizedBox(height: 16),
      AppDataTableCard(
        title: 'My Permissions',
        subtitle: 'Given by the administrator through your role',
        icon: Icons.key_rounded,
        emptyMessage: 'No permissions yet.',
        columns: const [DataColumn(label: Text('  Permission'))],
        rows: access.permissions
            .map((k) => DataRow(cells: [
                  DataCell(Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(access.labelOf(k)))),
                ]))
            .toList(),
      ),
    ]);
  }
}
