import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const Color primaryColor = Color(0xff1a2a6c);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: CustomAppBar(
        title: 'Analytics Dashboard',
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.today_rounded), text: 'Daily'),
            Tab(icon: Icon(Icons.view_week_rounded), text: 'Weekly'),
            Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _DailyTab(),
          _WeeklyTab(),
          _MonthlyTab(),
        ],
      ),
    );
  }
}

// =====================================================================
// Shared small widgets
// =====================================================================

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

Widget _errorBox(String message, VoidCallback onRetry) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 40),
        const SizedBox(height: 10),
        Text(message, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

// =====================================================================
// DAILY TAB
// =====================================================================

class _DailyTab extends StatefulWidget {
  const _DailyTab();

  @override
  State<_DailyTab> createState() => _DailyTabState();
}

class _DailyTabState extends State<_DailyTab> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final response = await ApiConfig.dio.get('/dashboard/daily', queryParameters: {'date': dateStr});
      setState(() {
        _data = response.data;
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to load data') : 'Connection error';
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Connection error';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorBox(_error!, _fetch);
    final totals = _data!['totals'] as Map<String, dynamic>;
    final workflow = _data!['workflow'] as Map<String, dynamic>;
    final sites = (_data!['sites'] as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: Color(0xff1a2a6c), size: 18),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _StatCard(label: 'Total Assigned', value: '${totals['total_assigned']}', icon: Icons.groups_rounded, color: const Color(0xff1a2a6c)),
                _StatCard(label: 'Attendance Rate', value: '${totals['attendance_rate']}%', icon: Icons.percent_rounded, color: Colors.green.shade700),
                _StatCard(label: 'Currently Working', value: '${totals['currently_working']}', icon: Icons.engineering_rounded, color: Colors.blue.shade700),
                _StatCard(label: 'On Break', value: '${totals['on_break']}', icon: Icons.free_breakfast_rounded, color: Colors.orange.shade700),
                _StatCard(label: 'Checked Out', value: '${totals['checked_out']}', icon: Icons.logout_rounded, color: Colors.purple.shade700),
                _StatCard(label: 'Not Checked In', value: '${totals['not_checked_in']}', icon: Icons.person_off_rounded, color: Colors.red.shade700),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Review Queue',
              child: Row(
                children: [
                  _miniChip('Submitted', workflow['Submitted'], Colors.orange),
                  const SizedBox(width: 10),
                  _miniChip('Rejected', workflow['Rejected'], Colors.red),
                  const SizedBox(width: 10),
                  _miniChip('Approved', workflow['Approved'], Colors.green),
                ],
              ),
            ),
            _SectionCard(
              title: 'Per-Site Breakdown',
              child: Column(
                children: sites.map((site) {
                  final rate = (site['attendance_rate'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(site['site_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Text('${site['attendance_rate']}%', style: TextStyle(fontWeight: FontWeight.bold, color: _rateColor(rate))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: rate / 100,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(_rateColor(rate)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          children: [
                            Text('Working: ${site['currently_working']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text('Break: ${site['on_break']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text('Out: ${site['checked_out']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text('Not in: ${site['not_checked_in']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text('Absent: ${site['absent_count']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, dynamic value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Color _rateColor(double rate) {
    if (rate >= 85) return Colors.green.shade700;
    if (rate >= 60) return Colors.orange.shade700;
    return Colors.red.shade700;
  }
}

// =====================================================================
// WEEKLY TAB
// =====================================================================

class _WeeklyTab extends StatefulWidget {
  const _WeeklyTab();

  @override
  State<_WeeklyTab> createState() => _WeeklyTabState();
}

class _WeeklyTabState extends State<_WeeklyTab> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiConfig.dio.get('/dashboard/weekly', queryParameters: {
        'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
        'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
      });
      setState(() {
        _data = response.data;
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to load data') : 'Connection error';
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Connection error';
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorBox(_error!, _fetch);

    final daily = (_data!['daily'] as List).cast<Map<String, dynamic>>();
    final hours = _data!['hours'] as Map<String, dynamic>;
    final review = _data!['review'] as Map<String, dynamic>;
    final topAbsentees = (_data!['top_absentees'] as List).cast<Map<String, dynamic>>();
    final siteComparison = (_data!['site_comparison'] as List).cast<Map<String, dynamic>>();

    final regularHours = (hours['regular_hours'] as num).toDouble();
    final overtimeHours = (hours['overtime_hours'] as num).toDouble();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded, color: Color(0xff1a2a6c), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Daily Attendance Rate (%)',
              child: SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= daily.length) return const SizedBox.shrink();
                            final d = DateTime.parse(daily[idx]['date']);
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(DateFormat('dd/MM').format(d), style: const TextStyle(fontSize: 10)),
                            );
                          },
                          reservedSize: 28,
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: const Color(0xff1a2a6c),
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(show: true, color: const Color(0xff1a2a6c).withOpacity(0.08)),
                        spots: List.generate(daily.length, (i) => FlSpot(i.toDouble(), (daily[i]['attendance_rate'] as num).toDouble())),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _SectionCard(
              title: 'Hours Summary',
              child: Row(
                children: [
                  Expanded(child: _hourBox('Regular Hours', regularHours, Colors.blue.shade700)),
                  const SizedBox(width: 12),
                  Expanded(child: _hourBox('Overtime Hours', overtimeHours, Colors.orange.shade700)),
                ],
              ),
            ),
            _SectionCard(
              title: 'Review & Quality',
              child: Row(
                children: [
                  Expanded(child: _reviewBox('Approved', review['Approved'], Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _reviewBox('Rejected', review['Rejected'], Colors.red)),
                  const SizedBox(width: 10),
                  Expanded(child: _reviewBox('Rejection Rate', '${review['rejection_rate']}%', Colors.deepOrange, isText: true)),
                ],
              ),
            ),
            _SectionCard(
              title: 'Top Absentees This Week',
              child: topAbsentees.isEmpty
                  ? Text('No absences recorded 🎉', style: TextStyle(color: Colors.grey.shade600))
                  : Column(
                      children: topAbsentees.map((w) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(backgroundColor: Color(0xfffdecea), child: Icon(Icons.person_off, color: Colors.red)),
                          title: Text(w['full_name']),
                          trailing: Text('${w['absent_days']} day(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      }).toList(),
                    ),
            ),
            _SectionCard(
              title: 'Site Comparison',
              child: Column(
                children: siteComparison.map((s) {
                  final rate = (s['attendance_rate'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(s['site_name'])),
                        Expanded(
                          flex: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: rate / 100,
                              minHeight: 10,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation(rate >= 75 ? Colors.green.shade700 : Colors.orange.shade700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${s['attendance_rate']}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hourBox(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${value.toStringAsFixed(1)} h', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _reviewBox(String label, dynamic value, Color color, {bool isText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text('$value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// =====================================================================
// MONTHLY TAB
// =====================================================================

class _MonthlyTab extends StatefulWidget {
  const _MonthlyTab();

  @override
  State<_MonthlyTab> createState() => _MonthlyTabState();
}

class _MonthlyTabState extends State<_MonthlyTab> {
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
      final response = await ApiConfig.dio.get('/dashboard/monthly', queryParameters: {'month': monthStr});
      setState(() {
        _data = response.data;
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to load data') : 'Connection error';
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Connection error';
      });
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select any day in the target month',
    );
    if (picked != null) {
      setState(() => _selectedMonth = picked);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorBox(_error!, _fetch);

    final summary = _data!['summary'] as Map<String, dynamic>;
    final calendar = (_data!['calendar'] as List).cast<Map<String, dynamic>>();
    final topAbsentees = (_data!['top_absentees'] as List).cast<Map<String, dynamic>>();
    final turnover = _data!['turnover'] as Map<String, dynamic>;
    final supervisorPerf = (_data!['supervisor_performance'] as List).cast<Map<String, dynamic>>();
    final siteComparison = (_data!['site_comparison'] as List).cast<Map<String, dynamic>>();

    final regularHours = (summary['regular_hours'] as num).toDouble();
    final overtimeHours = (summary['overtime_hours'] as num).toDouble();
    final overtimeShare = (summary['overtime_share'] as num).toDouble();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickMonth,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_view_month_rounded, color: Color(0xff1a2a6c), size: 18),
                    const SizedBox(width: 10),
                    Text(DateFormat('MMMM yyyy').format(_selectedMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _StatCard(label: 'Attendance Rate', value: '${summary['attendance_rate']}%', icon: Icons.percent_rounded, color: Colors.green.shade700),
                _StatCard(label: 'Total Assigned', value: '${summary['total_assigned']}', icon: Icons.groups_rounded, color: const Color(0xff1a2a6c)),
                _StatCard(label: 'Regular Hours', value: '${regularHours.toStringAsFixed(0)} h', icon: Icons.timer_rounded, color: Colors.blue.shade700),
                _StatCard(label: 'Overtime Share', value: '$overtimeShare%', icon: Icons.trending_up_rounded, color: Colors.orange.shade700),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Attendance Trend Through the Month',
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    maxY: 100,
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 25)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 5,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= calendar.length) return const SizedBox.shrink();
                            final d = DateTime.parse(calendar[idx]['date']);
                            return Padding(padding: const EdgeInsets.only(top: 6), child: Text('${d.day}', style: const TextStyle(fontSize: 9)));
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(calendar.length, (i) {
                      final rate = (calendar[i]['attendance_rate'] as num).toDouble();
                      return BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: rate,
                          color: rate >= 75 ? Colors.green.shade600 : (rate >= 50 ? Colors.orange.shade600 : Colors.red.shade600),
                          width: 5,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
            _SectionCard(
              title: 'Workforce Changes',
              child: Row(
                children: [
                  Expanded(child: _turnoverBox('Deactivated Workers', turnover['deactivated_workers'], Icons.person_remove_rounded, Colors.red)),
                  const SizedBox(width: 12),
                  Expanded(child: _turnoverBox('Approved Transfers', turnover['approved_transfers'], Icons.swap_horiz_rounded, Colors.blue)),
                ],
              ),
            ),
            _SectionCard(
              title: 'Top Absentees This Month',
              child: topAbsentees.isEmpty
                  ? Text('No absences recorded 🎉', style: TextStyle(color: Colors.grey.shade600))
                  : Column(
                      children: topAbsentees.map((w) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(backgroundColor: Color(0xfffdecea), child: Icon(Icons.person_off, color: Colors.red)),
                          title: Text(w['full_name']),
                          trailing: Text('${w['absent_days']} day(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      }).toList(),
                    ),
            ),
            _SectionCard(
              title: 'Supervisor Performance',
              child: supervisorPerf.isEmpty
                  ? Text('No records this month', style: TextStyle(color: Colors.grey.shade600))
                  : Column(
                      children: supervisorPerf.map((sup) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(sup['full_name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                              Expanded(child: Text('${sup['total_recorded']} recs', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                              Text('${sup['approval_rate']}%', style: TextStyle(fontWeight: FontWeight.bold, color: (sup['approval_rate'] as num) >= 80 ? Colors.green.shade700 : Colors.orange.shade700)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            _SectionCard(
              title: 'Site Comparison',
              child: Column(
                children: siteComparison.map((s) {
                  final rate = (s['attendance_rate'] as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(s['site_name'])),
                        Expanded(
                          flex: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: rate / 100,
                              minHeight: 10,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation(rate >= 75 ? Colors.green.shade700 : Colors.orange.shade700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${s['attendance_rate']}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _turnoverBox(String label, dynamic value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}