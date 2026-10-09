// lib/widgets/admin_shell.dart
//
// Admin layout: the "Live Operations" sidebar on EVERY Admin page.
//   * Wide screens (>= 1000 px): the sidebar is always visible on the left.
//   * Narrow screens: the sidebar opens as a drawer from the menu button in
//     each page's top bar.
//
// How it works: [AdminChrome] wraps the app's ONE navigator (MaterialApp
// `builder`), so every page, dialog and bottom sheet uses the same navigator
// as before. (An earlier version used a second, nested navigator: loading
// dialogs opened on the root navigator were then closed with
// Navigator.pop(context) on the nested one, and stayed on screen forever.)
// The sidebar is shown only after an Admin reaches the Admin home
// ([AdminShell]); the login screen and the supervisor apps never show it.

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

/// Whether the Admin sidebar is shown, and which item is selected.
class AdminChromeState {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  static final ValueNotifier<int> selected = ValueNotifier<int>(0);

  /// Called after the frame (never during a build).
  static void setEnabled(bool value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (enabled.value != value) enabled.value = value;
      if (!value) selected.value = 0;
    });
  }
}

/// Admin home (first page after an Admin logs in): turns the sidebar on and
/// shows Live Operations.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  @override
  void initState() {
    super.initState();
    AdminChromeState.selected.value = 0;
    AdminChromeState.setEnabled(true);
  }

  @override
  Widget build(BuildContext context) => const AnalyticsDashboardScreen();
}

/// Wraps the app navigator (MaterialApp.builder). Shows nothing extra until
/// [AdminChromeState.enabled] is true.
class AdminChrome extends StatefulWidget {
  final Widget child;
  const AdminChrome({super.key, required this.child});

  @override
  State<AdminChrome> createState() => _AdminChromeState();
}

class _AdminChromeState extends State<AdminChrome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  NavigatorState? get _nav => ApiConfig.navigatorKey.currentState;

  void _closeDrawer() {
    final s = _scaffoldKey.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
  }

  void _select(int index) {
    _closeDrawer();
    AdminChromeState.selected.value = index;
    _nav?.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => _shellItems[index].build(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  void _openChangePassword() {
    _closeDrawer();
    _nav?.push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  void _confirmLogout() {
    _closeDrawer();
    final ctx = ApiConfig.navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffb21f1f), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dCtx);
              AdminChromeState.setEnabled(false);
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
    return ValueListenableBuilder<bool>(
      valueListenable: AdminChromeState.enabled,
      builder: (context, enabled, _) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        // Same widget tree in every state: only the sidebar / drawer appear.
        // (The app navigator also keeps its GlobalKey, so it is never rebuilt.)
        final sidebar = ValueListenableBuilder<int>(
          valueListenable: AdminChromeState.selected,
          builder: (_, sel, __) => AdminSidebar(
            selected: sel,
            onSelect: _select,
            onChangePassword: _openChangePassword,
            onLogout: _confirmLogout,
          ),
        );
        return Scaffold(
          key: _scaffoldKey,
          drawer: enabled && !wide ? Drawer(backgroundColor: _kNavy, width: 260, child: sidebar) : null,
          drawerEnableOpenDragGesture: false,
          body: Row(children: [
            if (enabled && wide) sidebar,
            Expanded(
              child: enabled
                  ? AdminShellScope(
                      persistentSidebar: wide,
                      openMenu: () => _scaffoldKey.currentState?.openDrawer(),
                      child: widget.child,
                    )
                  : widget.child,
            ),
          ]),
        );
      }),
    );
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
