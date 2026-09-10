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
  TimeOfDay checkIn;
  TimeOfDay checkOut;
  bool existing;

  _StaffRow({
    required this.staffId,
    required this.uniqueId,
    required this.fullName,
    required this.position,
    required this.standardHours,
    required this.status,
    required this.checkIn,
    required this.checkOut,
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

  TimeOfDay _globalCheckIn = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _globalCheckOut = const TimeOfDay(hour: 16, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  bool get _isBackdated =>
      _dateStr != DateFormat('yyyy-MM-dd').format(DateTime.now());

  TimeOfDay? _parseTime(dynamic value) {
    if (value == null) return null;

    final s = value.toString();
    final match = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);

    if (match == null) return null;

    return TimeOfDay(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
    );
  }

  Future<void> _loadDay() async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.get(
        '/staff-attendance/admin/day',
        queryParameters: {'date': _dateStr},
      );

      final data = (response.data['data'] as List?) ?? [];

      setState(() {
        _rows = data.map((raw) {
          final standard =
              double.tryParse(
                raw['standard_daily_hours']?.toString() ?? '8',
              ) ??
              8;

          final hasRecord = raw['staff_attendance_id'] != null;

          return _StaffRow(
            staffId: raw['staff_id'],
            uniqueId: raw['staff_unique_id']?.toString() ?? '',
            fullName: raw['full_name']?.toString() ?? '',
            position: raw['position']?.toString() ?? '-',
            standardHours: standard,
            status: raw['attendance_status']?.toString() ?? 'Present',
            checkIn:
                _parseTime(raw['check_in_time']) ??
                const TimeOfDay(hour: 8, minute: 0),
            checkOut:
                _parseTime(raw['check_out_time']) ??
                TimeOfDay(
                  hour: (8 + standard).floor() % 24,
                  minute: 0,
                ),
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
        if (row.status == 'Present') {
          row.checkIn = _globalCheckIn;
          row.checkOut = _globalCheckOut;
        }
      }
    });
  }

  String _fmtTimeForDate(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');

    return '$_dateStr $h:$m:00';
  }

  Future<void> _save() async {
    if (_isBackdated) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backdated Attendance'),
          content: Text(
            'You are recording attendance for $_dateStr, which is not today. Are you sure you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Continue',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final entries = _rows
          .map(
            (row) => {
              'staff_id': row.staffId,
              'attendance_status': row.status,
              if (row.status == 'Present')
                'check_in_time': _fmtTimeForDate(row.checkIn),
              if (row.status == 'Present')
                'check_out_time': _fmtTimeForDate(row.checkOut),
            },
          )
          .toList();

      final response = await ApiConfig.dio.post(
        '/staff-attendance/admin/bulk-set',
        data: {
          'record_date': _dateStr,
          'entries': entries,
        },
      );

      _showSnack(
        response.data['message'] ?? 'Saved successfully',
        Colors.green.shade700,
      );

      _loadDay();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to save')
          : 'Failed to save';

      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _timeStepper(
    TimeOfDay value,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    TimeOfDay addMinutes(int delta) {
      final total =
          (value.hour * 60 + value.minute + delta) % (24 * 60);

      final normalized = total < 0 ? total + 24 * 60 : total;

      return TimeOfDay(
        hour: normalized ~/ 60,
        minute: normalized % 60,
      );
    }

    Widget unitStepper({
      required String label,
      required VoidCallback onMinus,
      required VoidCallback onPlus,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            icon: const Icon(
              Icons.keyboard_arrow_up,
              size: 16,
            ),
            onPressed: onPlus,
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            padding: EdgeInsets.zero,
          ),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
            ),
            onPressed: onMinus,
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        unitStepper(
          label: value.hour.toString().padLeft(2, '0'),
          onMinus: () => onChanged(addMinutes(-60)),
          onPlus: () => onChanged(addMinutes(60)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            ':',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        unitStepper(
          label: value.minute.toString().padLeft(2, '0'),
          onMinus: () => onChanged(addMinutes(-5)),
          onPlus: () => onChanged(addMinutes(5)),
        ),
      ],
    );
  }


@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: CustomAppBar(
      title: 'Staff Attendance',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadDay,
        ),
      ],
    ),
    body: _isLoading
        ? const Center(
            child: CircularProgressIndicator(),
          )
        : Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: primaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Text(
                          DateFormat(
                            'EEEE, dd MMM yyyy',
                          ).format(_selectedDate),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (_isBackdated)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Backdated',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(
                        Icons.edit_calendar,
                        size: 16,
                      ),
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Expanded(
                child: _rows.isEmpty
                    ? const Center(
                        child: Text('No active staff found'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _rows.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bulk apply Check-in / Check-out to everyone Present:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('In: '),
                                      _timeStepper(
                                        _globalCheckIn,
                                        (v) => setState(
                                          () => _globalCheckIn = v,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      const Text('Out: '),
                                      _timeStepper(
                                        _globalCheckOut,
                                        (v) => setState(
                                          () => _globalCheckOut = v,
                                        ),
                                      ),
                                      const Spacer(),
                                      ElevatedButton(
                                        onPressed: _applyGlobalToAllPresent,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                        ),
                                        child: const Text(
                                          'Apply to All',
                                          style: TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }

                          final row = _rows[index - 1];

                          return Card(
                            margin: const EdgeInsets.only(
                              bottom: 8,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row.fullName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              '${row.uniqueId} • ${row.position}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownButton<String>(
                                        value: row.status,
                                        items: _statuses
                                            .map(
                                              (s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(s),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => row.status =
                                              v ?? row.status,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (row.status == 'Present') ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Check-in',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            _timeStepper(
                                              row.checkIn,
                                              (v) => setState(
                                                () => row.checkIn = v,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Check-out',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            _timeStepper(
                                              row.checkOut,
                                              (v) => setState(
                                                () => row.checkOut = v,
                                              ),
                                            ),
                                          ],
                                        ),
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
            ],
          ),
  );
}
}