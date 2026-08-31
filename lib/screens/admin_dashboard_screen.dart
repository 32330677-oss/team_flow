import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'analytics_dashboard_screen.dart';
import 'login_screen.dart';
import 'project_management_screen.dart';
import 'worker_assignment_screen.dart';
import 'hr_management_screen.dart';
import 'attendance_payroll_hub.dart';
import 'workers_screen.dart';
import 'supervisor_management_screen.dart';
import 'pending_transfers_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // ---------- Design tokens ----------
  static const Color primaryColor = Color(0xff1a2a6c);
  static const Color accentColor = Color(0xfffdbb2d);
  static const Color dangerColor = Color(0xffb21f1f);
  static const Color bgColor = Color(0xfff4f6fb);
  static const Color activeColor = Color(0xff2e7d32);
  static const Color inactiveColor = Color(0xff9e9e9e);
  static const Color warningColor = Color(0xffed6c02);

  // ---------- State ----------
  int _selectedIndex = 0;
  bool _isLoading = true;

  int _totalWorkers = 0;
  int _activeWorkers = 0;
  int _totalSupervisors = 0;
  int _activeSupervisors = 0;
  int _pendingReviews = 0;
  List<dynamic> _recentPending = [];

  // تم إضافة عنصر Transfer Requests إلى القائمة الجانبية
  final List<_SidebarItem> _items = const [
    _SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _SidebarItem(icon: Icons.insights_rounded, label: 'Analytics'),
    _SidebarItem(icon: Icons.business_rounded, label: 'Projects'),
    _SidebarItem(icon: Icons.alt_route_rounded, label: 'Worker Distribution'),
    _SidebarItem(icon: Icons.people_alt_rounded, label: 'HR Management'),
    _SidebarItem(icon: Icons.fact_check_rounded, label: 'Attendance & Payroll'),
    _SidebarItem(icon: Icons.swap_horiz_rounded, label: 'Transfer Requests'), // <-- العنصر الجديد
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // ---------- Data fetching (uses existing backend endpoints only) ----------
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/workers'),
        ApiConfig.dio.get('/users/supervisors'),
        ApiConfig.dio.get('/admin/attendance/pending'),
      ]);

      final workers = (results[0].data['data'] as List?) ?? [];
      final supervisors = (results[1].data['data'] as List?) ?? [];
      final pending = (results[2].data['data'] as List?) ?? [];

      if (!mounted) return;
      setState(() {
        _totalWorkers = workers.length;
        _activeWorkers = workers.where((w) => w['status'] == 'Active').length;
        _totalSupervisors = supervisors.length;
        _activeSupervisors =
            supervisors.where((s) => s['status'] == 'Active').length;
        _pendingReviews = pending.length;
        _recentPending = pending.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load dashboard data. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------- Auth / Logout (unchanged logic) ----------
  Future<void> _handleLogout(BuildContext context) async {
    await ApiConfig.storage.delete(key: 'jwt_token');
    await ApiConfig.storage.delete(key: 'user_role');
    await ApiConfig.storage.delete(key: 'user_id');
    await ApiConfig.storage.delete(key: 'user_name');

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: dangerColor),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout(context);
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ---------- Sidebar navigation ----------
   void _onSelectItem(int index) {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    setState(() => _selectedIndex = index);

    Widget destination;
    switch (index) {
      case 1:
        destination = const AnalyticsDashboardScreen();
        break;
      case 2:
        destination = const ProjectManagementScreen();
        break;
      case 3:
        destination = const WorkerAssignmentScreen();
        break;
      case 4:
        destination = const HRManagementScreen();
        break;
      case 5:
        destination = const AttendancePayrollHub();
        break;
      case 6:
        destination = const PendingTransfersScreen();
        break;
      default:
        return;
    }

    _navigateAndRefresh(destination);
  }

  void _navigateAndRefresh(Widget destination) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    ).then((_) {
      if (mounted) {
        setState(() => _selectedIndex = 0);
        _loadDashboardData();
      }
    });
  }

  // ---------- Layout ----------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Row(
              children: [
                _buildSidebar(isPermanent: true),
                Expanded(child: _buildMainContent()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
          drawer: Drawer(
            child: _buildSidebar(isPermanent: false),
          ),
          body: _buildMainContent(showMenuButton: true),
        );
      },
    );
  }

  Widget _buildSidebar({required bool isPermanent}) {
    return Container(
      width: 260,
      color: primaryColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.group_work_rounded, color: Colors.white, size: 30),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'TEAM FLOW',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Admin Panel',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ),
            const SizedBox(height: 30),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == index;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Material(
                  color: isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (!isPermanent) Navigator.pop(context);
                      _onSelectItem(index);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: isSelected ? accentColor : Colors.white70,
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              item.label,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (!isPermanent) Navigator.pop(context);
                    _confirmLogout(context);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: Colors.white70, size: 22),
                        SizedBox(width: 14),
                        Text('Log Out', style: TextStyle(color: Colors.white70, fontSize: 14.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent({bool showMenuButton = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(showMenuButton: showMenuButton),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadDashboardData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: _buildOverview(),
                  ),
                ),
        ),
      ],
    );
  }

  // ---------- Top bar ----------
  Widget _buildTopBar({bool showMenuButton = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Builder(
        builder: (context) => Row(
          children: [
            if (showMenuButton)
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: primaryColor),
                onPressed: () => Scaffold.of(context).openDrawer(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            if (showMenuButton) const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Dashboard Overview',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: primaryColor),
              tooltip: 'Refresh',
              onPressed: _loadDashboardData,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 14),
            const CircleAvatar(
              radius: 18,
              backgroundColor: primaryColor,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Overview content ----------
  Widget _buildOverview() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back, Admin 👋',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              'A quick snapshot of your team status today.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),

            // 1) Workers breakdown card
            _buildBreakdownCard(
              title: 'Workers',
              subtitle: 'Total workforce on record',
              icon: Icons.engineering_rounded,
              iconColor: primaryColor,
              total: _totalWorkers,
              breakdown: [
                _BreakdownItem('Active', _activeWorkers, activeColor),
                _BreakdownItem('Inactive', _totalWorkers - _activeWorkers, inactiveColor),
              ],
              onTap: () => _navigateAndRefresh(const WorkersScreen()),
            ),
            const SizedBox(height: 16),

            // 2) Supervisors breakdown card
            _buildBreakdownCard(
              title: 'Supervisors',
              subtitle: 'Field supervisors managing sites',
              icon: Icons.manage_accounts_rounded,
              iconColor: dangerColor,
              total: _totalSupervisors,
              breakdown: [
                _BreakdownItem('Active', _activeSupervisors, activeColor),
                _BreakdownItem('Inactive', _totalSupervisors - _activeSupervisors, inactiveColor),
              ],
              onTap: () => _navigateAndRefresh(const SupervisorManagementScreen()),
            ),
            const SizedBox(height: 16),

            // 3) Pending Reviews — alert style card
            _buildAlertCard(
              title: 'Pending Reviews',
              subtitle: _pendingReviews == 0
                  ? 'No attendance records waiting for review'
                  : 'Attendance records awaiting your approval',
              icon: Icons.pending_actions_rounded,
              count: _pendingReviews,
              onTap: () => _onSelectItem(4),
            ),

            const SizedBox(height: 28),
            _buildRecentPendingSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required int total,
    required List<_BreakdownItem> breakdown,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: primaryColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        total.toString(),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                children: breakdown
                    .map((b) => Expanded(child: _buildBreakdownBadge(b)))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownBadge(_BreakdownItem item) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.count.toString(),
                maxLines: 1,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: item.color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required int count,
    required VoidCallback onTap,
  }) {
    final bool hasPending = count > 0;
    final Color color = hasPending ? warningColor : activeColor;

    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
                          ),
                        ),
                        if (hasPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    count.toString(),
                    maxLines: 1,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentPendingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Pending Attendance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: primaryColor),
                ),
              ),
              TextButton(
                onPressed: () => _onSelectItem(4),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_recentPending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No pending records right now 🎉',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ..._recentPending.map((item) {
              final status = item['status']?.toString() ?? '';
              final isRejected = status == 'Rejected';
              final statusColor = isRejected ? Colors.red : Colors.orange;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: statusColor.withOpacity(0.1),
                      child: Icon(
                        isRejected ? Icons.close_rounded : Icons.hourglass_bottom_rounded,
                        color: statusColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['full_name']?.toString() ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Text(
                            item['site_name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isRejected ? Colors.red.shade700 : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  const _SidebarItem({required this.icon, required this.label});
}

class _BreakdownItem {
  final String label;
  final int count;
  final Color color;
  _BreakdownItem(this.label, this.count, this.color);
}