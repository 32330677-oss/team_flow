// lib/screens/staff_overtime_screen.dart
//
// Month-scoped overtime compensation for a single staff member.
// Shows Gross / Used / Remaining OT for the selected month, lists Present
// days still carrying an uncompensated shortfall, lets Admin grant
// compensation against one of them (bounded by both the day's remaining
// shortfall and the month's remaining OT balance), and shows/reverses
// grant history. Never touches stored regular_hours/overtime_hours.

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
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
  bool _isSubmitting = false;

  Map<String, dynamic>? _balance;
  List<dynamic> _shortfallDays = [];
  List<dynamic> _history = [];

  int get _staffId => widget.staff['staff_id'] as int;
  String get _monthStr => DateFormat('yyyy-MM').format(_selectedMonth);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/staff-overtime/balance', queryParameters: {'staff_id': _staffId, 'month': _monthStr}),
        ApiConfig.dio.get('/staff-overtime/shortfall-days', queryParameters: {'staff_id': _staffId, 'month': _monthStr}),
        ApiConfig.dio.get('/staff-overtime/history', queryParameters: {'staff_id': _staffId, 'month': _monthStr}),
      ]);
      setState(() {
        _balance = results[0].data['data'];
        _shortfallDays = results[1].data['data'] ?? [];
        _history = results[2].data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load overtime data', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
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
      _loadAll();
    }
  }

  Future<void> _openGrantDialog(Map day) async {
    final remainingShortfall = (day['remaining_shortfall_hours'] as num).toDouble();
    final remainingOt = (_balance?['remainingOtHours'] as num? ?? 0).toDouble();
    final maxHours = remainingShortfall < remainingOt ? remainingShortfall : remainingOt;

    if (maxHours <= 0) {
      _showSnack('No overtime available to compensate this day.', Colors.orange);
      return;
    }

    double hoursToUse = maxHours;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Compensate ${(day['record_date'] ?? '').toString().split('T')[0]}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Day shortfall remaining: ${remainingShortfall.toStringAsFixed(2)}h', style: const TextStyle(fontSize: 13)),
                Text('Month OT remaining: ${remainingOt.toStringAsFixed(2)}h', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                Text('Hours to apply (max ${maxHours.toStringAsFixed(2)}h):', style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: hoursToUse,
                  min: 0.25,
                  max: maxHours,
                  divisions: (maxHours / 0.25).floor().clamp(1, 400),
                  label: hoursToUse.toStringAsFixed(2),
                  onChanged: (v) => setDialogState(() => hoursToUse = v),
                ),
                Text('${hoursToUse.toStringAsFixed(2)}h', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  _showSnack('A reason is required.', Colors.orange);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await ApiConfig.dio.post('/staff-overtime/grant', data: {
        'staff_attendance_id': day['staff_attendance_id'],
        'hours_to_use': hoursToUse,
        'reason': reasonController.text.trim(),
      });
      if (!mounted) return;
      _showSnack('Overtime compensation granted', Colors.green.shade700);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to grant compensation') : 'Failed to grant compensation';
      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reverse(int compensationId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse Compensation'),
        content: const Text('This will return the used hours to this month\'s OT balance. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiConfig.dio.post('/staff-overtime/$compensationId/reverse');
      if (!mounted) return;
      _showSnack('Compensation reversed', Colors.blue);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to reverse') : 'Failed to reverse';
      _showSnack(msg, Colors.red);
    }
  }

  Widget _balanceCard() {
    final gross = (_balance?['grossOtHours'] as num? ?? 0).toDouble();
    final used = (_balance?['usedOtHours'] as num? ?? 0).toDouble();
    final remaining = (_balance?['remainingOtHours'] as num? ?? 0).toDouble();

    Widget stat(String label, double value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text('${value.toStringAsFixed(2)}h', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat('Gross OT', gross, Colors.blue.shade700),
        const SizedBox(width: 8),
        stat('Used OT', used, Colors.orange.shade800),
        const SizedBox(width: 8),
        stat('Remaining', remaining, Colors.green.shade700),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: '${widget.staff['full_name'] ?? 'Staff'} — Overtime'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
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
                  const SizedBox(height: 16),
                  _balanceCard(),
                  const SizedBox(height: 24),
                  const Text('Days With Uncompensated Shortfall', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  if (_shortfallDays.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No uncompensated shortfall days this month.', style: TextStyle(color: Colors.grey.shade600)),
                    )
                  else
                    ..._shortfallDays.map((day) {
                      final date = (day['record_date'] ?? '').toString().split('T')[0];
                      final shortfall = (day['shortfall_hours'] as num).toDouble();
                      final used = (day['used_hours'] as num).toDouble();
                      final remaining = (day['remaining_shortfall_hours'] as num).toDouble();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xfffdecea), child: Icon(Icons.hourglass_bottom, color: Colors.red)),
                          title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Shortfall: ${shortfall.toStringAsFixed(2)}h • Compensated: ${used.toStringAsFixed(2)}h • Remaining: ${remaining.toStringAsFixed(2)}h'),
                          trailing: ElevatedButton(
                            onPressed: _isSubmitting ? null : () => _openGrantDialog(day),
                            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                            child: const Text('Compensate', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  const Text('Grant History (this month)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No compensations granted this month yet.', style: TextStyle(color: Colors.grey.shade600)),
                    )
                  else
                    ..._history.map((h) {
                      final reversed = h['reversed_at'] != null;
                      final date = (h['target_record_date'] ?? '').toString().split('T')[0];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(reversed ? Icons.undo : Icons.check_circle, color: reversed ? Colors.grey : Colors.green),
                          title: Text('$date — ${h['hours_used']}h', style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null)),
                          subtitle: Text('${h['reason'] ?? ''}\nBy ${h['created_by_name'] ?? ''}${reversed ? ' • Reversed by ${h['reversed_by_name'] ?? ''}' : ''}'),
                          isThreeLine: true,
                          trailing: reversed
                              ? null
                              : TextButton(
                                  onPressed: () => _reverse(h['compensation_id']),
                                  child: const Text('Reverse', style: TextStyle(color: Colors.red)),
                                ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}