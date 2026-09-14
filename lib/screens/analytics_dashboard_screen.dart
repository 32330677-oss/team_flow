import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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
import 'staff_attendance_payroll_hub.dart';
import 'payroll_screen.dart';
import 'admin_attendance_screen.dart';

class DashColors {
  static const Color bg = Color(0xFF0B1120);
  static const Color sidebar = Color(0xFF0A1428);
  static const Color card = Color(0xFF111C33);
  static const Color cardBorder = Color(0xFF1E2A45);
  static const Color textMain = Color(0xFFE6EAF2);
  static const Color textMuted = Color(0xFF8A95AC);

  static const Color blue = Color(0xFF3B82F6);
  static const Color green = Color(0xFF10B981);
  static const Color orange = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
  static const Color purple = Color(0xFF8B5CF6);
}

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends State<AnalyticsDashboardScreen> {
  // ============================================================
  // SIDEBAR COLORS
  // These NEVER change when Light/Dark mode is toggled.
  // ============================================================

  static const Color _sidebarColor = Color(0xff1a2a6c);
  static const Color _sidebarAccent = Color(0xfffdbb2d);

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isDarkMode = true;

  Map<String, dynamic>? _data;
  String _adminName = 'Admin';

  DateTime _startDate =
      DateTime.now().subtract(const Duration(days: 29));
  DateTime _endDate = DateTime.now();

  final List<_SidebarItem> _items = const [
    _SidebarItem(
      icon: Icons.dashboard_rounded,
      label: 'Dashboard',
    ),
    _SidebarItem(
      icon: Icons.people_alt_rounded,
      label: 'Workers',
    ),
    _SidebarItem(
      icon: Icons.fact_check_rounded,
      label: 'Attendance',
    ),
    _SidebarItem(
      icon: Icons.payments_rounded,
      label: 'Payroll',
    ),
    _SidebarItem(
      icon: Icons.business_rounded,
      label: 'Sites & Projects',
    ),
    _SidebarItem(
      icon: Icons.alt_route_rounded,
      label: 'Worker Distribution',
    ),
    _SidebarItem(
      icon: Icons.groups_2_rounded,
      label: 'HR Management',
    ),
    _SidebarItem(
      icon: Icons.insights_rounded,
      label: 'Reports',
    ),
    _SidebarItem(
      icon: Icons.swap_horiz_rounded,
      label: 'Transfer Requests',
    ),
    _SidebarItem(
      icon: Icons.badge_rounded,
      label: 'Staff Attendance & Payroll',
    ),
    _SidebarItem(
      icon: Icons.admin_panel_settings_rounded,
      label: 'Users & Roles',
    ),
  ];

  // ============================================================
  // CONTENT THEME
  // Only the main dashboard changes.
  // Sidebar stays dark.
  // ============================================================

  Color get _pageBg =>
      _isDarkMode ? DashColors.bg : const Color(0xFFF4F6FB);

  Color get _cardBg =>
      _isDarkMode ? DashColors.card : Colors.white;

  Color get _borderColor =>
      _isDarkMode
          ? DashColors.cardBorder
          : const Color(0xFFE2E8F0);

  Color get _mainText =>
      _isDarkMode
          ? DashColors.textMain
          : const Color(0xFF172033);

  Color get _mutedText =>
      _isDarkMode
          ? DashColors.textMuted
          : const Color(0xFF64748B);

  Color get _gridColor =>
      _isDarkMode
          ? DashColors.cardBorder
          : const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    _loadDashboardData();
  }

  // ============================================================
  // DATA
  // ============================================================

  Future<void> _loadAdminName() async {
    final name = await ApiConfig.storage.read(key: 'user_name');

    if (mounted && name != null && name.trim().isNotEmpty) {
      setState(() {
        _adminName = name.split(' ').first;
      });
    }
  }

  String get _startStr =>
      DateFormat('yyyy-MM-dd').format(_startDate);

  String get _endStr =>
      DateFormat('yyyy-MM-dd').format(_endDate);

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.get(
        '/main-dashboard/overview',
        queryParameters: {
          'start_date': _startStr,
          'end_date': _endStr,
        },
      );

      if (!mounted) return;

      setState(() {
        _data = response.data['data'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load dashboard data.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // DATE RANGE
  // ============================================================

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
      builder: (context, child) {
        return Theme(
          data: _isDarkMode
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: DashColors.blue,
                    surface: DashColors.card,
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: DashColors.card,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: DashColors.blue,
                    surface: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });

      _loadDashboardData();
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _handleLogout(BuildContext context) async {
    await ApiConfig.storage.delete(key: 'jwt_token');
    await ApiConfig.storage.delete(key: 'user_role');
    await ApiConfig.storage.delete(key: 'user_id');
    await ApiConfig.storage.delete(key: 'user_name');

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false,
      );
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Log Out',
          style: TextStyle(
            color: _mainText,
          ),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _mutedText,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DashColors.red,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout(context);
            },
            child: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SIDEBAR NAVIGATION
  // ============================================================

  void _onSelectItem(int index) {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      return;
    }

    setState(() => _selectedIndex = index);

    Widget destination;

    switch (index) {
      case 1:
        destination = const WorkersScreen();
        break;

      case 2:
        destination = const AdminAttendanceScreen();
        break;

      case 3:
        destination = const PayrollScreen();
        break;

      case 4:
        destination = const ProjectManagementScreen();
        break;

      case 5:
        destination = const WorkerAssignmentScreen();
        break;

      case 6:
        destination = const HRManagementScreen();
        break;

      case 7:
        destination = const AnalyticsDashboardScreen();
        break;

      case 8:
        destination = const PendingTransfersScreen();
        break;

      case 9:
        destination = const StaffAttendancePayrollHub();
        break;

      case 10:
        destination = const SupervisorManagementScreen();
        break;

      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => destination,
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _selectedIndex = 0);
        _loadDashboardData();
      }
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return Scaffold(
          backgroundColor: _pageBg,

          drawer: isWide
              ? null
              : Drawer(
                  child: _buildSidebar(),
                ),

          body: Row(
            children: [
              if (isWide) _buildSidebar(),

              Expanded(
                child: _buildMainContent(
                  showMenuButton: !isWide,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // SIDEBAR
  // FIXED DARK - NEVER CHANGES WITH THEME
  // ============================================================

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: _sidebarColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.group_work_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
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
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
            ),

            const SizedBox(height: 30),

            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final isSelected = _selectedIndex == index;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Material(
                      color: isSelected
                          ? Colors.white.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (Scaffold.of(context).hasDrawer) {
                            Navigator.pop(context);
                          }

                          _onSelectItem(index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                color: isSelected
                                    ? _sidebarAccent
                                    : Colors.white70,
                                size: 22,
                              ),

                              const SizedBox(width: 14),

                              Expanded(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
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
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (Scaffold.of(context).hasDrawer) {
                      Navigator.pop(context);
                    }

                    _confirmLogout(context);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        SizedBox(width: 14),
                        Text(
                          'Log Out',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14.5,
                          ),
                        ),
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

  // ============================================================
  // MAIN CONTENT
  // ============================================================

  Widget _buildMainContent({
    bool showMenuButton = false,
  }) {
    return Container(
      color: _pageBg,
      child: Column(
        children: [
          _buildTopBar(
            showMenuButton: showMenuButton,
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: DashColors.blue,
                    ),
                  )
                : _data == null
                    ? Center(
                        child: Text(
                          'No data',
                          style: TextStyle(
                            color: _mutedText,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDashboardData,
                        color: DashColors.blue,
                        backgroundColor: _cardBg,
                        child: SingleChildScrollView(
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: _buildBody(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _buildTopBar({
    bool showMenuButton = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: _pageBg,
        border: Border(
          bottom: BorderSide(
            color: _borderColor,
          ),
        ),
      ),
      child: Builder(
        builder: (context) => Row(
          children: [
            if (showMenuButton)
              IconButton(
                icon: Icon(
                  Icons.menu_rounded,
                  color: _mainText,
                ),
                onPressed: () =>
                    Scaffold.of(context).openDrawer(),
              ),

            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: _mutedText,
                      size: 20,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: TextField(
                        style: TextStyle(
                          color: _mainText,
                          fontSize: 13.5,
                        ),
                        decoration:
                            InputDecoration.collapsed(
                          hintText:
                              'Search for workers, sites, or IDs...',
                          hintStyle: TextStyle(
                            color: _mutedText.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ====================================================
            // LIGHT / DARK TOGGLE
            // ====================================================

            Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _borderColor,
                ),
              ),
              child: IconButton(
                tooltip: _isDarkMode
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                icon: Icon(
                  _isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: _isDarkMode
                      ? DashColors.orange
                      : DashColors.blue,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isDarkMode = !_isDarkMode;
                  });
                },
              ),
            ),

            const SizedBox(width: 8),

            Stack(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: _mainText.withOpacity(0.8),
                  ),
                  onPressed: () {},
                ),

                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: DashColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),

            const CircleAvatar(
              radius: 18,
              backgroundColor: DashColors.blue,
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),

            const SizedBox(width: 10),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _adminName,
                  style: TextStyle(
                    color: _mainText,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Admin',
                  style: TextStyle(
                    color: _mutedText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 4),

            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _mutedText,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody() {
    final kpis =
        _data!['kpis'] as Map<String, dynamic>;

    final attendanceOverview =
        (_data!['attendance_overview'] as List)
            .cast<Map<String, dynamic>>();

    final hours =
        _data!['hours_overview'] as Map<String, dynamic>;

    final positions =
        (_data!['workers_by_position'] as List)
            .cast<Map<String, dynamic>>();

    final topSites =
        (_data!['top_sites'] as List)
            .cast<Map<String, dynamic>>();

    final recentAttendance =
        (_data!['recent_attendance'] as List)
            .cast<Map<String, dynamic>>();

    final recentActivity =
        (_data!['recent_activity'] as List)
            .cast<Map<String, dynamic>>();

    final payroll =
        _data!['payroll_summary']
            as Map<String, dynamic>?;

    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good Morning'
        : (hour < 18
            ? 'Good Afternoon'
            : 'Good Evening');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ==================================================
              // GREETING + DATE
              // ==================================================

              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting, $_adminName 👋',
                          style: TextStyle(
                            color: _mainText,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          "Here's what's happening with your workforce.",
                          style: TextStyle(
                            color: _mutedText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  InkWell(
                    onTap: _pickDateRange,
                    borderRadius:
                        BorderRadius.circular(10),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                          color: _borderColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: DashColors.blue,
                          ),

                          const SizedBox(width: 8),

                          Text(
                            '${DateFormat('MMM d, yyyy').format(_startDate)} — ${DateFormat('MMM d, yyyy').format(_endDate)}',
                            style: TextStyle(
                              color: _mainText,
                              fontSize: 12.5,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),

                          const SizedBox(width: 6),

                          Icon(
                            Icons
                                .keyboard_arrow_down_rounded,
                            size: 16,
                            color: _mutedText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ==================================================
              // KPI CARDS
              // ==================================================

              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 800
                      ? 4
                      : (c.maxWidth > 500 ? 2 : 1);

                  final cards = [
                    _kpiCard(
                      Icons.groups_rounded,
                      DashColors.blue,
                      'Total Workers',
                      '${kpis['total_workers']}',
                      'Active workforce',
                    ),

                    _kpiCard(
                      Icons.event_available_rounded,
                      DashColors.green,
                      'Present Today',
                      '${kpis['present_today']}',
                      '${kpis['attendance_rate']}% attendance rate',
                    ),

                    _kpiCard(
                      Icons.beach_access_rounded,
                      DashColors.orange,
                      'On Leave Today',
                      '${kpis['on_leave_today']}',
                      'Sick / Vacation / Holiday',
                    ),

                    _kpiCard(
                      Icons.person_off_rounded,
                      DashColors.red,
                      'Absent Today',
                      '${kpis['absent_today']}',
                      'of total workforce',
                    ),
                  ];

                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 2.1,
                    children: cards,
                  );
                },
              ),

              const SizedBox(height: 20),

              // ==================================================
              // ATTENDANCE + HOURS
              // ==================================================

              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 780;

                  final attendanceChart = _sectionCard(
                    title: 'Attendance Overview',
                    legend: [
                      _legendDot(
                        DashColors.green,
                        'Present',
                      ),
                      _legendDot(
                        DashColors.orange,
                        'On Leave',
                      ),
                      _legendDot(
                        DashColors.red,
                        'Absent',
                      ),
                    ],
                    child: SizedBox(
                      height: 230,
                      child: _attendanceBarChart(
                        attendanceOverview,
                      ),
                    ),
                  );

                  final hoursChart = _sectionCard(
                    title: 'Hours Overview',
                    legend: [
                      _legendDot(
                        DashColors.blue,
                        'Regular Hours',
                      ),
                      _legendDot(
                        DashColors.purple,
                        'Overtime Hours',
                      ),
                    ],
                    child: SizedBox(
                      height: 230,
                      child: _hoursBarChart(
                        (hours['regular_hours'] as num)
                            .toDouble(),
                        (hours['overtime_hours'] as num)
                            .toDouble(),
                      ),
                    ),
                  );

                  return wide
                      ? Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: attendanceChart,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: hoursChart,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            attendanceChart,
                            const SizedBox(height: 16),
                            hoursChart,
                          ],
                        );
                },
              ),

              const SizedBox(height: 16),

              // ==================================================
              // POSITION + SITES
              // ==================================================

              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 780;

                  final donut = _sectionCard(
                    title: 'Workers by Position',
                    child: _positionDonut(
                      positions,
                    ),
                  );

                  final sites = _sectionCard(
                    title: 'Top Sites by Workforce',
                    child: _topSitesList(
                      topSites,
                    ),
                  );

                  return wide
                      ? Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: donut,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: sites,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            donut,
                            const SizedBox(height: 16),
                            sites,
                          ],
                        );
                },
              ),

              const SizedBox(height: 16),

              // ==================================================
              // RECENT ATTENDANCE
              // ==================================================

              _sectionCard(
                title: 'Recent Attendance Records',
                child: _recentAttendanceTable(
                  recentAttendance,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // ========================================================
        // RIGHT COLUMN
        // ========================================================

        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // ==================================================
              // QUICK ACTIONS
              // ==================================================

              _sectionCard(
                title: 'Quick Actions',
                child: Column(
                  children: [
                    _quickAction(
                      Icons.person_add_alt_1_rounded,
                      'Add New Worker',
                      DashColors.green,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const WorkersScreen(),
                        ),
                      ).then(
                        (_) => _loadDashboardData(),
                      ),
                    ),

                    _quickAction(
                      Icons.fact_check_rounded,
                      'Mark Attendance',
                      DashColors.blue,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AdminAttendanceScreen(),
                        ),
                      ).then(
                        (_) => _loadDashboardData(),
                      ),
                    ),

                    _quickAction(
                      Icons.account_balance_wallet_rounded,
                      'Generate Payroll',
                      DashColors.orange,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const PayrollScreen(),
                        ),
                      ).then(
                        (_) => _loadDashboardData(),
                      ),
                    ),

                    _quickAction(
                      Icons.bar_chart_rounded,
                      'View Reports',
                      DashColors.purple,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AnalyticsDashboardScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // RECENT ACTIVITY
              // ==================================================

              _sectionCard(
                title: 'Recent Activity',
                child: Column(
                  children: recentActivity
                      .map(
                        (a) => _activityTile(a),
                      )
                      .toList(),
                ),
              ),

              const SizedBox(height: 16),

              if (payroll != null)
                _payrollSummaryCard(payroll),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION CARD
  // ============================================================

  Widget _sectionCard({
    required String title,
    List<Widget>? legend,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _mainText,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),

              if (legend != null)
                Wrap(
                  spacing: 12,
                  children: legend,
                ),
            ],
          ),

          const SizedBox(height: 14),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // LEGEND
  // ============================================================

  Widget _legendDot(
    Color color,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 5),

        Text(
          label,
          style: TextStyle(
            color: _mutedText,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // KPI CARD
  // ============================================================

  Widget _kpiCard(
    IconData icon,
    Color color,
    String title,
    String value,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _mutedText,
                    fontSize: 11.5,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  value,
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                Text(
                  subtitle,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ATTENDANCE BAR CHART
  // ============================================================

  Widget _attendanceBarChart(
    List<Map<String, dynamic>> series,
  ) {
    if (series.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    final maxVal = series.fold<int>(
      0,
      (m, e) => [
        m,
        (e['present'] as int) +
            (e['on_leave'] as int) +
            (e['absent'] as int),
      ].reduce(
        (a, b) => a > b ? a : b,
      ),
    );

    return BarChart(
      BarChartData(
        maxY: (maxVal + 5).toDouble(),

        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(
            color: _gridColor,
            strokeWidth: 1,
          ),
        ),

        borderData: FlBorderData(
          show: false,
        ),

        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, m) =>
                  Text(
                '${v.toInt()}',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 10,
                ),
              ),
            ),
          ),

          rightTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),

          topTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (series.length / 6)
                  .ceilToDouble()
                  .clamp(1, 999),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();

                if (idx < 0 ||
                    idx >= series.length) {
                  return const SizedBox.shrink();
                }

                final d = DateTime.parse(
                  series[idx]['date'],
                );

                return Padding(
                  padding:
                      const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(d),
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 9,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        barGroups: List.generate(
          series.length,
          (i) {
            final present =
                (series[i]['present'] as int)
                    .toDouble();

            final leave =
                (series[i]['on_leave'] as int)
                    .toDouble();

            final absent =
                (series[i]['absent'] as int)
                    .toDouble();

            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: present + leave + absent,
                  width: series.length > 20
                      ? 4
                      : 8,
                  borderRadius:
                      BorderRadius.circular(2),
                  rodStackItems: [
                    BarChartRodStackItem(
                      0,
                      present,
                      DashColors.green,
                    ),
                    BarChartRodStackItem(
                      present,
                      present + leave,
                      DashColors.orange,
                    ),
                    BarChartRodStackItem(
                      present + leave,
                      present + leave + absent,
                      DashColors.red,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // HOURS BAR CHART
  // ============================================================

  Widget _hoursBarChart(
    double regular,
    double overtime,
  ) {
    final maxVal =
        (regular + overtime).clamp(
      10,
      double.infinity,
    );

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,

        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(
            color: _gridColor,
            strokeWidth: 1,
          ),
        ),

        borderData: FlBorderData(
          show: false,
        ),

        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, m) =>
                  Text(
                '${v.toInt()}',
                style: TextStyle(
                  color: _mutedText,
                  fontSize: 10,
                ),
              ),
            ),
          ),

          rightTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),

          topTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
            ),
          ),

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, m) {
                const labels = [
                  'Regular',
                  'Overtime',
                ];

                final i = v.toInt();

                if (i < 0 ||
                    i >= labels.length) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding:
                      const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: regular,
                width: 40,
                borderRadius:
                    BorderRadius.circular(6),
                color: DashColors.blue,
              ),
            ],
          ),

          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: overtime,
                width: 40,
                borderRadius:
                    BorderRadius.circular(6),
                color: DashColors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // POSITION DONUT
  // ============================================================

  Widget _positionDonut(
    List<Map<String, dynamic>> positions,
  ) {
    if (positions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    final colors = [
      DashColors.blue,
      DashColors.green,
      DashColors.orange,
      DashColors.purple,
      DashColors.red,
      Colors.tealAccent,
      Colors.pinkAccent,
    ];

    final total = positions.fold<int>(
      0,
      (s, e) => s + (e['count'] as int),
    );

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections:
                      List.generate(
                    positions.length,
                    (i) {
                      final count =
                          positions[i]['count']
                              as int;

                      return PieChartSectionData(
                        value: count.toDouble(),
                        color:
                            colors[i % colors.length],
                        radius: 26,
                        showTitle: false,
                      );
                    },
                  ),
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: TextStyle(
                      color: _mainText,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    'Total',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: List.generate(
              positions.length,
              (i) {
                final count =
                    positions[i]['count'] as int;

                final pct = total > 0
                    ? (count / total * 100)
                        .toStringAsFixed(1)
                    : '0.0';

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: Text(
                          '${positions[i]['position']}',
                          style: TextStyle(
                            color: _mainText,
                            fontSize: 12,
                          ),
                          overflow:
                              TextOverflow.ellipsis,
                        ),
                      ),

                      Text(
                        '$count ($pct%)',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TOP SITES
  // ============================================================

  Widget _topSitesList(
    List<Map<String, dynamic>> sites,
  ) {
    if (sites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No data',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    final maxCount = sites.fold<int>(
      1,
      (m, e) =>
          (e['worker_count'] as int) > m
              ? (e['worker_count'] as int)
              : m,
    );

    return Column(
      children: sites.map((s) {
        final count =
            s['worker_count'] as int;

        final ratio =
            count / maxCount;

        return Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 7,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  '${s['site_name']}',
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 12,
                  ),
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ),

              Expanded(
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 10,
                    backgroundColor: _borderColor,
                    valueColor:
                        const AlwaysStoppedAnimation(
                      DashColors.blue,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Text(
                '$count',
                style: TextStyle(
                  color: _mainText,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // RECENT ATTENDANCE TABLE
  // ============================================================

  Widget _recentAttendanceTable(
    List<Map<String, dynamic>> records,
  ) {
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No records',
          style: TextStyle(
            color: _mutedText,
          ),
        ),
      );
    }

    String timeOnly(dynamic v) {
      if (v == null) return '-';

      final s =
          '$v'.replaceFirst('T', ' ');

      return s.length >= 16
          ? s.substring(11, 16)
          : s;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor:
            WidgetStateProperty.all(
          _isDarkMode
              ? DashColors.bg
              : const Color(0xFFF8FAFC),
        ),

        dataRowColor:
            WidgetStateProperty.all(
          _cardBg,
        ),

        columnSpacing: 22,

        headingTextStyle: TextStyle(
          color: _mutedText,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
        ),

        dataTextStyle: TextStyle(
          color: _mainText,
          fontSize: 12.5,
        ),

        columns: const [
          DataColumn(
            label: Text('Date'),
          ),
          DataColumn(
            label: Text('Worker'),
          ),
          DataColumn(
            label: Text('Position'),
          ),
          DataColumn(
            label: Text('Check In'),
          ),
          DataColumn(
            label: Text('Check Out'),
          ),
          DataColumn(
            label: Text('Hours'),
          ),
          DataColumn(
            label: Text('Status'),
          ),
        ],

        rows: records.map((r) {
          final status =
              r['status'] as String;

          final color = status == 'Present'
              ? DashColors.green
              : (status == 'Absent'
                  ? DashColors.red
                  : DashColors.orange);

          return DataRow(
            cells: [
              DataCell(
                Text(r['date'] ?? ''),
              ),

              DataCell(
                Text(r['full_name'] ?? ''),
              ),

              DataCell(
                Text(r['position'] ?? '-'),
              ),

              DataCell(
                Text(
                  timeOnly(r['check_in']),
                ),
              ),

              DataCell(
                Text(
                  timeOnly(r['check_out']),
                ),
              ),

              DataCell(
                Text(
                  r['total_hours'] != null
                      ? '${r['total_hours']}h'
                      : '-',
                ),
              ),

              DataCell(
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        color.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // QUICK ACTION
  // ============================================================

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 10),
      child: Material(
        color: color.withOpacity(0.15),
        borderRadius:
            BorderRadius.circular(10),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 18,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ACTIVITY
  // ============================================================

  Widget _activityTile(
    Map<String, dynamic> activity,
  ) {
    final action =
        (activity['action_type'] ?? '')
            .toString();

    IconData icon =
        Icons.info_outline_rounded;

    Color color = DashColors.blue;

    if (action.contains('APPROVED')) {
      icon =
          Icons.check_circle_outline_rounded;
      color = DashColors.green;
    } else if (action.contains('REJECTED')) {
      icon = Icons.cancel_outlined;
      color = DashColors.red;
    } else if (action.contains('PAYROLL') ||
        action.contains('FINALIZ')) {
      icon = Icons.payments_outlined;
      color = DashColors.orange;
    } else if (action.contains('CREATED') ||
        action.contains('WORKER')) {
      icon =
          Icons.person_add_alt_outlined;
      color = DashColors.purple;
    }

    String timeAgo = '';

    final ts = activity['timestamp'];

    if (ts != null) {
      final dt = DateTime.tryParse(
        '$ts'.replaceFirst(' ', 'T'),
      );

      if (dt != null) {
        final diff =
            DateTime.now().difference(dt);

        if (diff.inMinutes < 60) {
          timeAgo =
              '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo =
              '${diff.inHours}h ago';
        } else {
          timeAgo =
              DateFormat('MMM d').format(dt);
        }
      }
    }

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius:
                  BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 15,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  action.replaceAll(
                    '_',
                    ' ',
                  ),
                  style: TextStyle(
                    color: _mainText,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                Text(
                  '${activity['table_name'] ?? ''} • ${activity['user_name'] ?? 'System'}',
                  style: TextStyle(
                    color: _mutedText,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),

          Text(
            timeAgo,
            style: TextStyle(
              color: _mutedText,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PAYROLL SUMMARY
  // ============================================================

  Widget _payrollSummaryCard(
    Map<String, dynamic> payroll,
  ) {
    String money(dynamic v) =>
        '\$${(double.tryParse('$v') ?? 0).toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            DashColors.blue,
            Color(0xFF1E3A8A),
          ],
        ),
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Payroll Summary',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),

          Text(
            'Batch #${payroll['batch_id']} • ${payroll['period']}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 12),

          _payrollRow(
            'Total Net Salary',
            money(
              payroll['total_net_salary'],
            ),
          ),

          _payrollRow(
            'Total Deductions',
            money(
              payroll['total_deductions'],
            ),
          ),

          _payrollRow(
            'Total OT Paid',
            money(
              payroll['total_overtime_paid'],
            ),
          ),

          _payrollRow(
            'Total Employees',
            '${payroll['total_employees']}',
          ),
        ],
      ),
    );
  }

  Widget _payrollRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 1),

          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),

          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// SIDEBAR ITEM
// ================================================================

class _SidebarItem {
  final IconData icon;
  final String label;

  const _SidebarItem({
    required this.icon,
    required this.label,
  });
}