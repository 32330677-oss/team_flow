import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffAttendanceAdminScreen extends StatefulWidget {
  const StaffAttendanceAdminScreen({super.key});

  @override
  State<StaffAttendanceAdminScreen> createState() => _StaffAttendanceAdminScreenState();
}

class _StaffRow {
  final int staffId;
  final String uniqueId;
  final String fullName;
  final String position;
  final double standardHours;
  String status;
  double hours;
  bool existing;

  _StaffRow({
    required this.staffId,
    required this.uniqueId,
    required this.fullName,
    required this.position,
    required this.standardHours,
    required this.status,
    required this.hours,
    required this.existing,
  });
}

class _StaffAttendanceAdminScreenState extends State<StaffAttendanceAdminScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);
  static const List<String> _statuses = ['Present', 'Absent', 'Sick', 'Vacation', 'Holiday'];

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  List<_StaffRow> _rows = [];
  double _globalHours = 8;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isBackdated => _dateStr != DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _loadDay() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/staff-attendance/admin/day', queryParameters: {'date': _dateStr});
      final data = (response.data['data'] as List?) ?? [];
      setState(() {
        _rows = data.map((raw) {
          final standard = double.tryParse(raw['standard_daily_hours']?.toString() ?? '8') ?? 8;
          final hasRecord = raw['staff_attendance_id'] != null;
          final regular = double.tryParse(raw['regular_hours']?.toString() ?? '0') ?? 0;
          final overtime = double.tryParse(raw['overtime_hours']?.toString() ?? '0') ?? 0;
          return _StaffRow(
            staffId: raw['staff_id'],
            uniqueId: raw['staff_unique_id']?.toString() ?? '',
            fullName: raw['full_name']?.toString() ?? '',
            position: raw['position']?.toString() ?? '-',
            standardHours: standard,
            status: raw['attendance_status']?.toString() ?? 'Present',
            hours: hasRecord ? (regular + overtime) : standard,
            existing: hasRecord,
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load staff attendance', Colors.red);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      helpText: 'Select attendance date (past dates allowed)',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDay();
    }
  }

  void _applyGlobalToAllPresent() {
    setState(() {
      for (final row in _rows) {
        if (row.status == 'Present') row.hours = _globalHours;
      }
    });
  }

  Future<void> _save() async {
    if (_isBackdated) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backdated Attendance'),
          content: Text('You are recording attendance for $_dateStr, which is not today. Are you sure you want to continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);
    try {
      final entries = _rows.map((row) => {
            'staff_id': row.staffId,
            'attendance_status': row.status,
            'hours': row.status == 'Present' ? row.hours : 0,
          }).toList();

      final response = await ApiConfig.dio.post('/staff-attendance/admin/bulk-set', data: {
        'record_date': _dateStr,
        'entries': entries,
      });

      _showSnack(response.data['message'] ?? 'Saved successfully', Colors.green.shade700);
      _loadDay();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to save') : 'Failed to save';
      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Widget _hourStepper(double value, ValueChanged<double> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: value <= 0 ? null : () => onChanged(((value * 4).round() - 1) / 4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        Container(width: 64, alignment: Alignment.center, child: Text('${value.toStringAsFixed(2)}h', style: const TextStyle(fontWeight: FontWeight.bold))),
        IconButton.filledTonal(
          icon: const Icon(Icons.add, size: 16),
          onPressed: value >= 24 ? null : () => onChanged(((value * 4).round() + 1) / 4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: 'Staff Attendance', actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDay)]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: primaryColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickDate,
                          child: Text(DateFormat('EEEE, dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_isBackdated)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text('Backdated', style: TextStyle(color: Colors.orange.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      TextButton.icon(onPressed: _pickDate, icon: const Icon(Icons.edit_calendar, size: 16), label: const Text('Change')),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Bulk apply hours to everyone Present:', style: TextStyle(fontWeight: FontWeight.w600))),
                      _hourStepper(_globalHours, (v) => setState(() => _globalHours = v)),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _applyGlobalToAllPresent,
                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                        child: const Text('Apply to All', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('No active staff found'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(row.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              Text('${row.uniqueId} • ${row.position}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            ],
                                          ),
                                        ),
                                        DropdownButton<String>(
                                          value: row.status,
                                          items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                          onChanged: (v) => setState(() => row.status = v ?? row.status),
                                        ),
                                      ],
                                    ),
                                    if (row.status == 'Present') ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text('Hours worked: ', style: TextStyle(color: Colors.grey.shade700)),
                                          _hourStepper(row.hours, (v) => setState(() => row.hours = v)),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, color: Colors.white),
                      label: Text(_isSaving ? 'Saving...' : 'Save Attendance for This Day', style: const TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}