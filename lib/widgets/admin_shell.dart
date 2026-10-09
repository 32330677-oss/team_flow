// lib/widgets/admin_shell.dart
//
// Admin layout: the "Live Operations" sidebar on EVERY Admin page.
//   * Wide screens (>= 1000 px): the sidebar is always visible on the left.
//   * Narrow screens: the sidebar opens as a drawer from the menu button in
//     each page's top bar.
// All Admin pages (and the pages they open) live in a nested Navigator next to
// the sidebar, so the sidebar stays while moving between and inside pages.
// Dialogs still open over the whole window. Logout uses the root navigator.

import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';

import '../screens/admin_attendance_screen.dart';
import '../screens/analytics_dashboard_screen.dart';
import '../screens/biometric_import_screen.dart';
import '../screens/biometric_processing_screen.dart';
import '../screens/change_password_screen.dart';
import '../screens/device_id_mapping_screen.dart';
import '../screens/hr_management_screen.dart';
import '../screens/payroll_screen.dart';
import '../screens/pending_transfers_screen.dart';
import '../screens/project_management_screen.dart';
import '../screens/staff_attendance_payroll_hub.dart';
import '../screens/supervisor_management_screen.dart';
import '../screens/worker_assignment_screen.dart';
import '../screens/workers_screen.dart';
import 'admin_shell_scope.dart';

const Color _kNavy = Color(0xff1a2a6c);
const Color _kAccent = Color(0xfffdbb2d);

class _ShellItem {
  final IconData icon;
  final String label;
  final Widget Function() build;
  const _ShellItem(this.icon, this.label, this.build);
}

final List<_ShellItem> _shellItems = [
  _ShellItem(Icons.monitor_heart_rounded, 'Live Operations', () => const AnalyticsDashboardScreen()),
  _ShellItem(Icons.engineering_rounded, 'Workers', () => const WorkersScreen()),
  _ShellItem(Icons.fact_check_rounded, 'Attendance Review', () => const AdminAttendanceScreen()),
  _ShellItem(Icons.payments_rounded, 'Payroll', () => const PayrollScreen()),
  _ShellItem(Icons.business_rounded, 'Projects', () => const ProjectManagementScreen()),
  _ShellItem(Icons.alt_route_rounded, 'Worker Distribution', () => const WorkerAssignmentScreen()),
  _ShellItem(Icons.people_alt_rounded, 'HR Management', () => const HRManagementScreen()),
  _ShellItem(Icons.swap_horiz_rounded, 'Transfer Requests', () => const PendingTransfersScreen()),
  _ShellItem(Icons.badge_rounded, 'Staff Attendance & Payroll', () => const StaffAttendancePayrollHub()),
  _ShellItem(Icons.manage_accounts_rounded, 'Supervisors Management', () => const SupervisorManagementScreen()),
  _ShellItem(Icons.fingerprint_rounded, 'Biometric Processing', () => const BiometricProcessingScreen()),
  _ShellItem(Icons.upload_file_rounded, 'Biometric Import', () => const BiometricImportScreen()),
  _ShellItem(Icons.link_rounded, 'Device ID Mapping', () => const DeviceIdMappingScreen()),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selected = 0;

  Route<void> _instantRoute(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  void _select(int index) {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    setState(() => _selected = index);
    _navKey.currentState?.pushAndRemoveUntil(_instantRoute(_shellItems[index].build()), (route) => false);
  }

  void _openChangePassword() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    _navKey.currentState?.push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  void _confirmLogout() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffb21f1f), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              ApiConfig.logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  Widget _content(bool wide) {
    return AdminShellScope(
      persistentSidebar: wide,
      openMenu: () => _scaffoldKey.currentState?.openDrawer(),
      child: NavigatorPopHandler(
        onPop: () => _navKey.currentState?.maybePop(),
        child: Navigator(
          key: _navKey,
          onGenerateRoute: (_) => _instantRoute(_shellItems[_selected].build()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final sidebar = AdminSidebar(
        selected: _selected,
        onSelect: _select,
        onChangePassword: _openChangePassword,
        onLogout: _confirmLogout,
      );
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF4F6FB),
        drawer: wide ? null : Drawer(backgroundColor: _kNavy, width: 260, child: sidebar),
        body: wide ? Row(children: [sidebar, Expanded(child: _content(true))]) : _content(false),
      );
    });
  }
}

/// The navy sidebar of the Live Operations page, shared by every Admin page.
class AdminSidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const AdminSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: _kNavy,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Text('ASIK ENGINEERING CONSTRUCTION',
                  maxLines: 2,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.8)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('Admin Panel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < _shellItems.length; i++)
                    _tile(_shellItems[i].icon, _shellItems[i].label, () => onSelect(i), selected: i == selected),
                ],
              ),
            ),
            _tile(Icons.lock_reset_rounded, 'Change Password', onChangePassword),
            _tile(Icons.logout_rounded, 'Log Out', onLogout),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback? onTap, {bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Icon(icon, size: 20, color: selected ? _kAccent : Colors.white70),
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
