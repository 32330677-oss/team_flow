import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffSupervisorAttendanceScreen extends StatefulWidget {
  const StaffSupervisorAttendanceScreen({super.key});

  @override
  State<StaffSupervisorAttendanceScreen> createState() => _StaffSupervisorAttendanceScreenState();
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

class _StaffSupervisorAttendanceScreenState extends State<StaffSupervisorAttendanceScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);
  static const List<String> _statuses = ['Present', 'Absent', 'Sick', 'Vacation', 'Holiday'];

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  final Set<int> _selectedStaffIds = <int>{};
bool _isSavingSelection = false;
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

  // يوم جمعة؟ (نفس تعريف isFriday بالباك اند: getUTCDay() == 5 لنفس التاريخ)
  bool get _isFridaySelected => _selectedDate.weekday == DateTime.friday;

  TimeOfDay? _parseTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    final match = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);
    if (match == null) return null;
    return TimeOfDay(hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
  }

  Future<void> _loadDay() async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.get(
        '/staff-attendance/supervisor/day',
        queryParameters: {'date': _dateStr},
      );

      final data = (response.data['data'] as List?) ?? [];

      setState(() {
        _rows = data.map((raw) {
          final standard =
              double.tryParse(raw['standard_daily_hours']?.toString() ?? '8') ?? 8;
          final hasRecord = raw['staff_attendance_id'] != null;

          return _StaffRow(
            staffId: raw['staff_id'],
            uniqueId: raw['staff_unique_id']?.toString() ?? '',
            fullName: raw['full_name']?.toString() ?? '',
            position: raw['position']?.toString() ?? '-',
            standardHours: standard,
            status: raw['attendance_status']?.toString() ?? 'Present',
            checkIn: _parseTime(raw['check_in_time']) ?? const TimeOfDay(hour: 8, minute: 0),
            checkOut: _parseTime(raw['check_out_time']) ??
                TimeOfDay(hour: (8 + standard).floor() % 24, minute: 0),
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

  // ------------------------------------------------------------------
  // شيفت ليلي (Overnight): إذا وقت الخروج <= وقت الدخول، اعتبر الخروج
  // باليوم التالي التقويمي. هاد بيطابق مبدأ "Overnight attendance":
  // تاريخ سجل الحضور بيضل تاريخ الدخول، بس وقت الخروج فعليًا باليوم اللي بعده.
  // ------------------------------------------------------------------
  String _fmtDateTimeForRow(TimeOfDay checkIn, TimeOfDay t, {required bool isCheckOut}) {
    final baseDate = DateTime.parse(_dateStr);
    DateTime dt = DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);

    if (isCheckOut) {
      final checkInMinutes = checkIn.hour * 60 + checkIn.minute;
      final checkOutMinutes = t.hour * 60 + t.minute;
      if (checkOutMinutes <= checkInMinutes) {
        dt = dt.add(const Duration(days: 1));
      }
    }

    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return '$d $h:$m:00';
  }

Future<void> _save() => _saveRows(_rows, isFullDay: true);

Future<void> _saveSelected() async {
  if (_selectedStaffIds.isEmpty) {
    _showSnack('Save atleast 1 Employee', Colors.orange);
    return;
  }
  final rows = _rows.where((r) => _selectedStaffIds.contains(r.staffId)).toList();
  await _saveRows(rows, isFullDay: false);
}

Future<void> _saveOne(_StaffRow row) => _saveRows([row], isFullDay: false);

Future<void> _saveRows(List<_StaffRow> rowsToSave, {required bool isFullDay}) async {
  if (rowsToSave.isEmpty) return;

  if (_isBackdated) {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backdated Attendance'),
        content: Text(
          'You are recording attendance for $_dateStr, which is not today. Are you sure you want to continue?',
        ),
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

  final hasPresentEntries = rowsToSave.any((r) => r.status == 'Present');
  bool fridayConfirmed = false;
  if (_isFridaySelected && hasPresentEntries) {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Friday Attendance'),
        content: const Text(
          'Friday is normally a non-working day. Are you sure you want to register attendance for the staff marked Present on this Friday?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    fridayConfirmed = true;
  }

  setState(() {
    if (isFullDay) {
      _isSaving = true;
    } else {
      _isSavingSelection = true;
    }
  });

  try {
    final entries = rowsToSave.map((row) {
      final map = <String, dynamic>{
        'staff_id': row.staffId,
        'attendance_status': row.status,
      };
      if (row.status == 'Present') {
        map['check_in_time'] = _fmtDateTimeForRow(row.checkIn, row.checkIn, isCheckOut: false);
        map['check_out_time'] = _fmtDateTimeForRow(row.checkIn, row.checkOut, isCheckOut: true);
        if (_isFridaySelected) {
          map['friday_confirmed'] = fridayConfirmed;
        }
      }
      return map;
    }).toList();

    final response = await ApiConfig.dio.post(
      '/staff-attendance/supervisor/bulk-set',
      data: {'record_date': _dateStr, 'entries': entries},
    );

    final data = response.data is Map ? response.data as Map : {};
    final results = data['data'] is Map ? data['data'] as Map : {};
    final skipped = (results['skipped'] as List?) ?? [];
    final updatedCount = (results['updated'] as List?)?.length ?? 0;

    if (skipped.isNotEmpty) {
      final needsFriday = skipped.any(
        (s) => s is Map && s['requires_friday_confirmation'] == true,
      );
      _showSnack(
        needsFriday
            ? '$updatedCount saved. Some entries need Friday confirmation — please retry.'
            : '$updatedCount saved, ${skipped.length} skipped.',
        Colors.orange,
      );
    } else {
      _showSnack(
        isFullDay
            ? (data['message']?.toString() ?? 'Saved successfully')
            : '$updatedCount saved successfully.',
        Colors.green.shade700,
      );
    }

    if (!isFullDay) {
      setState(() {
        _selectedStaffIds.removeWhere((id) => rowsToSave.any((r) => r.staffId == id));
      });
    }

    _loadDay();
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to save')
        : 'Failed to save';
    _showSnack(msg, Colors.red);
  } finally {
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isSavingSelection = false;
      });
    }
  }
}

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Widget _timeStepper(TimeOfDay value, ValueChanged<TimeOfDay> onChanged) {
    TimeOfDay addMinutes(int delta) {
      final total = (value.hour * 60 + value.minute + delta) % (24 * 60);
      final normalized = total < 0 ? total + 24 * 60 : total;
      return TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60);
    }

    Widget unitStepper({required String label, required VoidCallback onMinus, required VoidCallback onPlus}) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
            onPressed: onPlus,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          IconButton.filledTonal(
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            onPressed: onMinus,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
          child: Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        unitStepper(
          label: value.minute.toString().padLeft(2, '0'),
          onMinus: () => onChanged(addMinutes(-5)),
          onPlus: () => onChanged(addMinutes(5)),
        ),
      ],
    );
  }
Widget _buildSelectionToolbar() {
  final allIds = _rows.map((r) => r.staffId).toSet();
  final allSelected = _selectedStaffIds.isNotEmpty && _selectedStaffIds.length == allIds.length;

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Checkbox(
          value: allSelected,
          tristate: true,
          onChanged: (v) => setState(() {
            if (v == true) {
              _selectedStaffIds.addAll(allIds);
            } else {
              _selectedStaffIds.clear();
            }
          }),
        ),
        Expanded(
          child: Text(
            _selectedStaffIds.isEmpty
                ? 'Check Employees to save them in one time'
                : '${_selectedStaffIds.length} checked',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton.icon(
          onPressed: (_isSavingSelection || _selectedStaffIds.isEmpty) ? null : _saveSelected,
          icon: _isSavingSelection
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_alt_rounded, size: 16, color: Colors.white),
          label: Text('Save checked records (${_selectedStaffIds.length})', style: const TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Staff Attendance',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDay),
        ],
      ),
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
                          child: Text(
                            DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (_isFridaySelected)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Friday',
                            style: TextStyle(
                              color: Colors.deepPurple.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_isBackdated)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            'Backdated',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        label: const Text('Change'),
                      ),
                    ],
                  ),
                ),

                if (_isFridaySelected)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.deepPurple.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Friday is normally a non-working day. Marking anyone Present will require confirmation on save.',
                            style: TextStyle(fontSize: 11.5, color: Colors.deepPurple.shade700),
                          ),
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
                        itemCount: _rows.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bulk apply Check-in / Check-out to everyone Present:',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('In: '),
                                      _timeStepper(_globalCheckIn, (v) => setState(() => _globalCheckIn = v)),
                                      const SizedBox(width: 20),
                                      const Text('Out: '),
                                      _timeStepper(_globalCheckOut, (v) => setState(() => _globalCheckOut = v)),
                                      const Spacer(),
                                      ElevatedButton(
                                        onPressed: _applyGlobalToAllPresent,
                                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                                        child: const Text('Apply to All', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'If check-out time is earlier than or equal to check-in, it will be treated as the next calendar day (overnight shift).',
                                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (index == 1) {
                            return _buildSelectionToolbar();
                          }

                          final row = _rows[index - 2];
                          final isSelected = _selectedStaffIds.contains(row.staffId);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isSelected ? primaryColor.withOpacity(0.04) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (v) => setState(() {
                                          if (v == true) {
                                            _selectedStaffIds.add(row.staffId);
                                          } else {
                                            _selectedStaffIds.remove(row.staffId);
                                          }
                                        }),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(row.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text(
                                              '${row.uniqueId} • ${row.position}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownButton<String>(
                                        value: row.status,
                                        items: _statuses
                                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                            .toList(),
                                        onChanged: (v) => setState(() => row.status = v ?? row.status),
                                      ),
                                      IconButton(
                                        tooltip: 'Save Now',
                                        icon: const Icon(Icons.save_rounded, size: 20, color: Colors.green),
                                        onPressed: _isSaving ? null : () => _saveOne(row),
                                      ),
                                    ],
                                  ),
                                  if (row.status == 'Present') ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Check-in', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            _timeStepper(row.checkIn, (v) => setState(() => row.checkIn = v)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Check-out', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            _timeStepper(row.checkOut, (v) => setState(() => row.checkOut = v)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if ((row.checkOut.hour * 60 + row.checkOut.minute) <=
                                        (row.checkIn.hour * 60 + row.checkIn.minute))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Icon(Icons.nightlight_round, size: 13, color: Colors.indigo.shade400),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Overnight shift — check-out counted on the next day',
                                              style: TextStyle(fontSize: 10.5, color: Colors.indigo.shade400),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

                // -------------------------------------------------------
                // كان ناقص بالكامل: زر الحفظ! بدونه ما في طريقة ترسل
                // التغييرات للسيرفر.
                // -------------------------------------------------------
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: (_isSaving || _rows.isEmpty) ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_alt_rounded, color: Colors.white),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Attendance',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}