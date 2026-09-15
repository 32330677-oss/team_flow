import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:team_flow/constants.dart';
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
  static const Color _sidebarColor = Color(0xff1a2a6c);
  static const Color _sidebarAccent = Color(0xfffdbb2d);

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isDarkMode = true;

  Map<String, dynamic>? _data;
  String _adminName = 'Admin';

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 13));
  DateTime _endDate = DateTime.now();


  Color get _pageBg => _isDarkMode ? DashColors.bg : const Color(0xFFF4F6FB);
  Color get _cardBg => _isDarkMode ? DashColors.card : Colors.white;
  Color get _borderColor =>
      _isDarkMode ? DashColors.cardBorder : const Color(0xFFE2E8F0);
  Color get _mainText =>
      _isDarkMode ? DashColors.textMain : const Color(0xFF172033);
  Color get _mutedText =>
      _isDarkMode ? DashColors.textMuted : const Color(0xFF64748B);
  Color get _gridColor =>
      _isDarkMode ? DashColors.cardBorder : const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    _loadDashboardData();
  }

  Future<void> _loadAdminName() async {
    final name = await ApiConfig.storage.read(key: 'user_name');
    if (mounted && name != null && name.trim().isNotEmpty) {
      setState(() => _adminName = name.split(' ').first);
    }
  }

  String get _startStr => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endStr => DateFormat('yyyy-MM-dd').format(_endDate);

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(
        '/main-dashboard/overview',
        queryParameters: {'start_date': _startStr, 'end_date': _endStr},
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

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: _isDarkMode
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: DashColors.blue,
                    surface: DashColors.card,
                  ),
                  dialogTheme: const DialogThemeData(backgroundColor: DashColors.card),
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
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out', style: TextStyle(color: _mainText)),
        content: Text('Are you sure you want to log out?', style: TextStyle(color: _mutedText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _mutedText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DashColors.red),
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
        destination = const PendingTransfersScreen();
        break;
      case 8:
        destination = const StaffAttendancePayrollHub();
        break;
      case 9:
        destination = const SupervisorManagementScreen();
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => destination)).then((_) {
      if (mounted) {
        setState(() => _selectedIndex = 0);
        _loadDashboardData();
      }
    });
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: _pageBg,
    body: _buildMainContent(showMenuButton: false),
  );
}



  Widget _buildMainContent({bool showMenuButton = false}) {
    return Container(
      color: _pageBg,
      child: Column(
        children: [
         _buildTopBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: DashColors.blue))
                : _data == null
                    ? Center(child: Text('No data', style: TextStyle(color: _mutedText)))
                    : RefreshIndicator(
                        onRefresh: _loadDashboardData,
                        color: DashColors.blue,
                        backgroundColor: _cardBg,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          child: _buildBody(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({bool showMenuButton = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _pageBg,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Builder(
        builder: (context) => Row(
          children: [
          
            Expanded(
              child: Text(
                'Dashboard Overview',
                style: TextStyle(color: _mainText, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: IconButton(
                tooltip: _isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
                icon: Icon(
                  _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: _isDarkMode ? DashColors.orange : DashColors.blue,
                  size: 20,
                ),
                onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
              ),
            ),
            const SizedBox(width: 10),
            const CircleAvatar(radius: 17, backgroundColor: DashColors.blue, child: Icon(Icons.person, color: Colors.white, size: 17)),
            const SizedBox(width: 8),
            Text(_adminName, style: TextStyle(color: _mainText, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BODY — عمود واحد قابل للـ scroll، ما في أي شي محشور
  // ============================================================

  Widget _buildBody() {
    final kpis = (_data!['kpis'] as Map).cast<String, dynamic>();
    final liveSites = ((_data!['live_sites'] as List?) ?? []).cast<Map<String, dynamic>>();
    final attendanceOverview = ((_data!['attendance_overview'] as List?) ?? []).cast<Map<String, dynamic>>();
    final dailyHours = ((_data!['daily_hours_series'] as List?) ?? []).cast<Map<String, dynamic>>();
    final positions = ((_data!['workers_by_position'] as List?) ?? []).cast<Map<String, dynamic>>();
    final topSites = ((_data!['top_sites'] as List?) ?? []).cast<Map<String, dynamic>>();
    final lastPaid = _data!['last_paid_payroll'] as Map<String, dynamic>?;
    final latestBatch = _data!['latest_payroll_batch'] as Map<String, dynamic>?;

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : (hour < 18 ? 'Good Afternoon' : 'Good Evening');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------- Greeting + Date range ----------------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting, $_adminName 👋',
                      style: TextStyle(color: _mainText, fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("Here's a live snapshot of your workforce.",
                      style: TextStyle(color: _mutedText, fontSize: 12.5)),
                ],
              ),
            ),
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: DashColors.blue),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('MMM d').format(_startDate)} — ${DateFormat('MMM d').format(_endDate)}',
                      style: TextStyle(color: _mainText, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _mutedText),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // ---------------- KPI cards ----------------
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 520 ? 2 : 1);
          final cards = [
            _kpiCard(Icons.groups_rounded, DashColors.blue, 'Total Assigned Workers',
                '${kpis['total_workers']}', 'Currently assigned to active sites',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkersScreen()))),
            _kpiCard(Icons.directions_walk_rounded, DashColors.green, 'Working Right Now',
                '${kpis['currently_working_now']}', 'Checked in, not checked out yet'),
            _kpiCard(Icons.event_available_rounded, DashColors.blue, 'Present Today',
                '${kpis['present_today']}', '${kpis['attendance_rate']}% attendance rate'),
            _kpiCard(Icons.beach_access_rounded, DashColors.orange, 'On Leave Today',
                '${kpis['on_leave_today']}', 'Sick / Vacation / Holiday'),
            _kpiCard(Icons.person_off_rounded, DashColors.red, 'Absent Today',
                '${kpis['absent_today']}', 'of assigned workforce'),
            _kpiCard(Icons.pending_actions_rounded, DashColors.orange, 'Pending Reviews',
                '${kpis['pending_reviews']}', '${kpis['rejected_records']} rejected records',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen()))
                    .then((_) => _loadDashboardData())),
          ];
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: cards,
          );
        }),

        const SizedBox(height: 18),

        // ---------------- Live site status ----------------
        _sectionCard(
          title: 'Live Site Status',
          child: _liveSitesList(liveSites),
        ),

        const SizedBox(height: 18),

        // ---------------- Attendance trend ----------------
        _sectionCard(
          title: 'Attendance Trend',
          legend: [
            _legendDot(DashColors.green, 'Present'),
            _legendDot(DashColors.orange, 'On Leave'),
            _legendDot(DashColors.red, 'Absent'),
          ],
          child: SizedBox(height: 220, child: _attendanceBarChart(attendanceOverview)),
        ),

        const SizedBox(height: 18),

        // ---------------- Working hours trend ----------------
        _sectionCard(
          title: 'Working Hours (Regular vs Overtime)',
          legend: [
            _legendDot(DashColors.blue, 'Regular Hours'),
            _legendDot(DashColors.purple, 'Overtime Hours'),
          ],
          child: SizedBox(height: 220, child: _hoursTrendChart(dailyHours)),
        ),

        const SizedBox(height: 18),

        // ---------------- Payroll snapshot ----------------
        _payrollSection(lastPaid, latestBatch),

        const SizedBox(height: 18),

        // ---------------- Position + Top sites ----------------
        _sectionCard(
          title: 'Workers by Position',
          child: _positionDonut(positions),
        ),
        const SizedBox(height: 18),
        _sectionCard(
          title: 'Top Sites by Workforce',
          child: _topSitesList(topSites),
        ),

        const SizedBox(height: 18),

        // ---------------- Quick actions ----------------
        _sectionCard(
          title: 'Quick Actions',
          child: Column(
            children: [
              _quickAction(Icons.person_add_alt_1_rounded, 'Add New Worker', DashColors.green,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkersScreen()))
                      .then((_) => _loadDashboardData())),
              _quickAction(Icons.fact_check_rounded, 'Review Attendance', DashColors.blue,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAttendanceScreen()))
                      .then((_) => _loadDashboardData())),
              _quickAction(Icons.account_balance_wallet_rounded, 'Open Payroll', DashColors.orange,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollScreen()))
                      .then((_) => _loadDashboardData())),
              _quickAction(Icons.swap_horiz_rounded, 'Transfer Requests', DashColors.purple,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingTransfersScreen()))
                      .then((_) => _loadDashboardData())),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION CARD / LEGEND / KPI
  // ============================================================

  Widget _sectionCard({required String title, List<Widget>? legend, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: TextStyle(color: _mainText, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              if (legend != null) Wrap(spacing: 12, children: legend),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: _mutedText, fontSize: 11.5)),
      ],
    );
  }

  Widget _kpiCard(IconData icon, Color color, String title, String value, String subtitle, {VoidCallback? onTap}) {
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: _mutedText, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: _mainText, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: content);
  }

  // ============================================================
  // LIVE SITES LIST
  // ============================================================

  Widget _liveSitesList(List<Map<String, dynamic>> sites) {
    if (sites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text('No active sites with assigned workers yet.', style: TextStyle(color: _mutedText)),
      );
    }
    return Column(
      children: sites.map((s) {
        final assigned = s['assigned_workers'] as int? ?? 0;
        final working = s['currently_working'] as int? ?? 0;
        final checkedIn = s['checked_in_today'] as int? ?? 0;
        final submitted = s['is_submitted'] == true;

        String statusLabel;
        Color statusColor;
        if (checkedIn == 0) {
          statusLabel = 'Not started yet';
          statusColor = _mutedText;
        } else if (submitted) {
          statusLabel = 'Day submitted';
          statusColor = DashColors.blue;
        } else if (working > 0) {
          statusLabel = 'In progress';
          statusColor = DashColors.green;
        } else {
          statusLabel = 'Pending submission';
          statusColor = DashColors.orange;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isDarkMode ? DashColors.bg : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (working > 0 ? DashColors.green : _mutedText).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.location_on_rounded, size: 16, color: working > 0 ? DashColors.green : _mutedText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['site_name']?.toString() ?? 'Site',
                        style: TextStyle(color: _mainText, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Working now: $working / $assigned assigned',
                        style: TextStyle(color: _mutedText, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // ATTENDANCE TREND CHART
  // ============================================================

  Widget _attendanceBarChart(List<Map<String, dynamic>> series) {
    if (series.isEmpty) {
      return Center(child: Text('No data', style: TextStyle(color: _mutedText)));
    }
    final maxVal = series.fold<int>(0, (m, e) {
      final total = (e['present'] as int) + (e['on_leave'] as int) + (e['absent'] as int);
      return total > m ? total : m;
    });

    return BarChart(
      BarChartData(
        maxY: (maxVal + 5).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: _gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, m) => Text('${v.toInt()}', style: TextStyle(color: _mutedText, fontSize: 10)),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (series.length / 6).ceilToDouble().clamp(1, 999),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                final d = DateTime.parse(series[idx]['date']);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('MMM d').format(d), style: TextStyle(color: _mutedText, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(series.length, (i) {
          final present = (series[i]['present'] as int).toDouble();
          final leave = (series[i]['on_leave'] as int).toDouble();
          final absent = (series[i]['absent'] as int).toDouble();
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: present + leave + absent,
                width: series.length > 20 ? 4 : 8,
                borderRadius: BorderRadius.circular(2),
                rodStackItems: [
                  BarChartRodStackItem(0, present, DashColors.green),
                  BarChartRodStackItem(present, present + leave, DashColors.orange),
                  BarChartRodStackItem(present + leave, present + leave + absent, DashColors.red),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  // ============================================================
  // HOURS TREND CHART (Regular vs Overtime, day by day)
  // ============================================================

  Widget _hoursTrendChart(List<Map<String, dynamic>> series) {
    if (series.isEmpty) {
      return Center(child: Text('No data', style: TextStyle(color: _mutedText)));
    }
    double maxVal = 1;
    for (final e in series) {
      final reg = (e['regular_hours'] as num).toDouble();
      final ot = (e['overtime_hours'] as num).toDouble();
      if (reg > maxVal) maxVal = reg;
      if (ot > maxVal) maxVal = ot;
    }

    return BarChart(
      BarChartData(
        maxY: maxVal + (maxVal * 0.25) + 1,
        groupsSpace: 14,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: _gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, m) => Text('${v.toInt()}h', style: TextStyle(color: _mutedText, fontSize: 9)),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (series.length / 6).ceilToDouble().clamp(1, 999),
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                final d = DateTime.parse(series[idx]['date']);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('MMM d').format(d), style: TextStyle(color: _mutedText, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(series.length, (i) {
          final reg = (series[i]['regular_hours'] as num).toDouble();
          final ot = (series[i]['overtime_hours'] as num).toDouble();
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(toY: reg, width: series.length > 10 ? 4 : 7, borderRadius: BorderRadius.circular(2), color: DashColors.blue),
              BarChartRodData(toY: ot, width: series.length > 10 ? 4 : 7, borderRadius: BorderRadius.circular(2), color: DashColors.purple),
            ],
          );
        }),
      ),
    );
  }

  // ============================================================
  // PAYROLL SNAPSHOT
  // ============================================================

  Widget _payrollSection(Map<String, dynamic>? lastPaid, Map<String, dynamic>? latestBatch) {
    String money(dynamic v) {
      final amount = double.tryParse(v?.toString() ?? '0') ?? 0;
      return '${NumberFormat('#,##0', 'en_US').format(amount)} ل.س';
    }

    return _sectionCard(
      title: 'Payroll Snapshot',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastPaid != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: DashColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.check_circle_rounded, color: DashColors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last Paid Payment', style: TextStyle(color: _mutedText, fontSize: 11.5)),
                      Text(money(lastPaid['total_amount']),
                          style: TextStyle(color: _mainText, fontSize: 19, fontWeight: FontWeight.bold)),
                      Text(
                        '${lastPaid['period']} • ${lastPaid['total_workers']} workers'
                        '${lastPaid['paid_date'] != null ? ' • paid ${lastPaid['paid_date']}' : ''}',
                        style: TextStyle(color: _mutedText, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _mutedText, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('No payroll has been marked as paid yet.',
                      style: TextStyle(color: _mutedText, fontSize: 12.5)),
                ),
              ],
            ),
          if (latestBatch != null && latestBatch['status'] != 'Paid') ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.hourglass_bottom_rounded, color: DashColors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Batch #${latestBatch['batch_id']} (${latestBatch['period']}) is ${latestBatch['status']} — '
                    '${money(latestBatch['total_amount'])} for ${latestBatch['total_workers']} workers, not yet paid.',
                    style: TextStyle(color: _mainText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollScreen()))
                  .then((_) => _loadDashboardData()),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Open Payroll'),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // POSITION DONUT
  // ============================================================

  Widget _positionDonut(List<Map<String, dynamic>> positions) {
    if (positions.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Text('No data', style: TextStyle(color: _mutedText)));
    }
    final colors = [DashColors.blue, DashColors.green, DashColors.orange, DashColors.purple, DashColors.red, Colors.tealAccent, Colors.pinkAccent];
    final total = positions.fold<int>(0, (s, e) => s + (e['count'] as int));

    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  sections: List.generate(positions.length, (i) {
                    final count = positions[i]['count'] as int;
                    return PieChartSectionData(
                      value: count.toDouble(),
                      color: colors[i % colors.length],
                      radius: 24,
                      showTitle: false,
                    );
                  }),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: TextStyle(color: _mainText, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Total', style: TextStyle(color: _mutedText, fontSize: 10.5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(positions.length, (i) {
              final count = positions[i]['count'] as int;
              final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${positions[i]['position']}',
                          style: TextStyle(color: _mainText, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                    Text('$count ($pct%)', style: TextStyle(color: _mutedText, fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TOP SITES
  // ============================================================

  Widget _topSitesList(List<Map<String, dynamic>> sites) {
    if (sites.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: Text('No data', style: TextStyle(color: _mutedText)));
    }
    final maxCount = sites.fold<int>(1, (m, e) => (e['worker_count'] as int) > m ? (e['worker_count'] as int) : m);

    return Column(
      children: sites.map((s) {
        final count = s['worker_count'] as int;
        final ratio = count / maxCount;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text('${s['site_name']}', style: TextStyle(color: _mainText, fontSize: 12), overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 10,
                    backgroundColor: _borderColor,
                    valueColor: const AlwaysStoppedAnimation(DashColors.blue),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$count', style: TextStyle(color: _mainText, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // QUICK ACTION
  // ============================================================

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
