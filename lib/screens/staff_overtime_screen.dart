// lib/screens/staff_overtime_screen.dart
//
// عرض read-only لسجل الساعات الإضافية الشهري (Monthly Overtime Ledger)
// المحسوب تلقائيًا عند توليد دفعة Payroll (StaffPayrollController).
// النظام القديم لمنح تعويض يدوي يوم-بيوم أصبح ملغى واستُبدل بهذا المبدأ
// الشهري التلقائي بالكامل.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffOvertimeScreen extends StatefulWidget {
  final Map<String, dynamic> staff;

  const StaffOvertimeScreen({super.key, required this.staff});

  @override
  State<StaffOvertimeScreen> createState() => _StaffOvertimeScreenState();
}

class _StaffOvertimeScreenState extends State<StaffOvertimeScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;
  Map<String, dynamic>? _ledger;
  String? _infoMessage;

  int get _staffId => widget.staff['staff_id'] as int;
  String get _monthStr => DateFormat('yyyy-MM').format(_selectedMonth);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _infoMessage = null;
    });
    try {
      final response = await ApiConfig.dio.get(
        '/staff-overtime/monthly-ledger',
        queryParameters: {'staff_id': _staffId, 'month': _monthStr},
      );
      setState(() {
        _ledger = response.data['data'];
        _infoMessage = _ledger == null ? response.data['message']?.toString() : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load the monthly overtime ledger', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickMonth() async {
    int selectedYear = _selectedMonth.year;
    int selectedMonth = _selectedMonth.month;

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Month'),
        content: StatefulBuilder(
          builder: (context, setStateDialog) => SizedBox(
            width: 300,
            height: 150,
            child: Column(
              children: [
                DropdownButton<int>(
                  value: selectedYear,
                  isExpanded: true,
                  items: List.generate(8, (i) => 2023 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => selectedYear = v);
                  },
                ),
                const SizedBox(height: 15),
                DropdownButton<int>(
                  value: selectedMonth,
                  isExpanded: true,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text(_monthName(m))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => selectedMonth = v);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, DateTime(selectedYear, selectedMonth, 1)),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => _selectedMonth = result);
      _load();
    }
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  Widget _statBox(String label, double value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('${value.toStringAsFixed(2)}h',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = _ledger;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: '${widget.staff['full_name'] ?? 'Staff'} — Monthly Overtime'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  InkWell(
                    onTap: _pickMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_view_month_rounded, color: primaryColor, size: 18),
                          const SizedBox(width: 10),
                          Text(DateFormat('MMMM yyyy').format(_selectedMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This ledger is calculated automatically when a payroll batch is generated for this month. It is read-only.',
                            style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (ledger == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.hourglass_empty, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _infoMessage ?? 'No data for this month yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        _statBox('Required Hours', _num(ledger['required_hours']), primaryColor),
                        _statBox('Actual Regular', _num(ledger['actual_regular_hours']), Colors.green.shade700),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _statBox('OT Earned', _num(ledger['ot_earned_hours']), Colors.blue.shade700),
                        _statBox('OT Used', _num(ledger['ot_used_hours']), Colors.orange.shade800),
                        _statBox('OT Remaining', _num(ledger['ot_remaining_hours']), Colors.teal.shade700),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _statBox('Shortage', _num(ledger['shortage_hours']), Colors.red.shade700),
                        _statBox('Uncovered Shortage', _num(ledger['uncovered_shortage_hours']), Colors.red.shade900),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Payroll Impact', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Hourly Rate'),
                              Text('${ledger['hourly_rate_snapshot']}'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Salary Deduction'),
                              Text(
                                '-${ledger['salary_deduction_amount']}',
                                style: TextStyle(
                                  color: _num(ledger['salary_deduction_amount']) > 0 ? Colors.red : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Batch Status'),
                              Text('${ledger['batch_status'] ?? '-'}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}