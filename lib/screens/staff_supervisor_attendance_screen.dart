import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffSupervisorAttendanceScreen extends StatefulWidget {
  const StaffSupervisorAttendanceScreen({super.key});

  @override
  State<StaffSupervisorAttendanceScreen> createState() =>
      _StaffSupervisorAttendanceScreenState();
}

class _StaffRow {
  final int staffId;
  final String uniqueId;
  final String fullName;
  final String position;
  final double standardHours;
  String status; // Present / Absent / Sick / Vacation / Holiday
  TimeOfDay checkIn;
  TimeOfDay checkOut;
  bool existing;

  /// Workflow status coming from the server:
  /// null (no record yet) / Submitted / Approved / Rejected
  String? workflowStatus;
  String? rejectionNote;

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
    this.workflowStatus,
    this.rejectionNote,
  });

  /// Once the admin approved a record the supervisor can no longer change it
  /// (the backend rejects it too: "Already approved by Admin; cannot modify.").
  bool get isLocked => workflowStatus == 'Approved';
}

class _StaffSupervisorAttendanceScreenState
    extends State<StaffSupervisorAttendanceScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);
  static const List<String> _statuses = [
    'Present',
    'Absent',
    'Sick',
    'Vacation',
    'Holiday',
  ];

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;

  /// Employees the supervisor checked. Only these are affected by
  /// "Apply to Checked" and by "Submit Checked".
  final Set<int> _selectedStaffIds = <int>{};
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

  // Same definition as the backend isFriday().
  bool get _isFridaySelected => _selectedDate.weekday == DateTime.friday;

  Set<int> get _selectableIds =>
      _rows.where((r) => !r.isLocked).map((r) => r.staffId).toSet();

  int get _checkedCount {
    final selectable = _selectableIds;
    return _selectedStaffIds.where(selectable.contains).length;
  }

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

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------
  // Loading
  //
  // When [justSavedIds] is provided this is a "silent" refresh after a save:
  // no full-screen spinner, and rows the supervisor did NOT just save keep
  // their unsaved on-screen edits (previously a single-row save reloaded the
  // whole list and wiped every other unsaved edit).
  // ------------------------------------------------------------------
  Future<void> _loadDay({Set<int>? justSavedIds}) async {
    final saved = justSavedIds;
    final silent = saved != null;
    if (!silent) setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.get(
        '/staff-attendance/supervisor/day',
        queryParameters: {'date': _dateStr},
      );

      final data = (response.data['data'] as List?) ?? [];
      final oldById = {for (final r in _rows) r.staffId: r};

      final newRows = data.map<_StaffRow>((raw) {
        final standard =
            double.tryParse(raw['standard_daily_hours']?.toString() ?? '8') ?? 8;
        final hasRecord = raw['staff_attendance_id'] != null;
        final note = raw['admin_rejection_notes']?.toString();

        final row = _StaffRow(
          staffId: raw['staff_id'],
          uniqueId: raw['staff_unique_id']?.toString() ?? '',
          fullName: raw['full_name']?.toString() ?? '',
          position: raw['position']?.toString() ?? '-',
          standardHours: standard,
          status: raw['attendance_status']?.toString() ?? 'Present',
          checkIn: _parseTime(raw['check_in_time']) ??
              const TimeOfDay(hour: 8, minute: 0),
          checkOut: _parseTime(raw['check_out_time']) ??
              TimeOfDay(hour: (8 + standard).floor() % 24, minute: 0),
          existing: hasRecord,
          workflowStatus: hasRecord ? raw['status']?.toString() : null,
          rejectionNote: (note != null && note.trim().isNotEmpty) ? note : null,
        );

        // Keep unsaved local edits of rows that were not part of this save.
        if (saved != null && !saved.contains(row.staffId) && !row.isLocked) {
          final old = oldById[row.staffId];
          if (old != null) {
            row.status = old.status;
            row.checkIn = old.checkIn;
            row.checkOut = old.checkOut;
          }
        }
        return row;
      }).toList();

      if (!mounted) return;
      setState(() {
        _rows = newRows;
        // Drop selections of rows that no longer exist or became locked.
        _selectedStaffIds.removeWhere(
          (id) => !newRows.any((r) => r.staffId == id && !r.isLocked),
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
      setState(() {
        _selectedDate = picked;
        _selectedStaffIds.clear();
      });
      _loadDay();
    }
  }

  // ------------------------------------------------------------------
  // Bulk time entry — affects ONLY the checked employees.
  // This is local only: nothing is sent to the server until Submit.
  // ------------------------------------------------------------------
  void _applyGlobalToChecked() {
    if (_selectedStaffIds.isEmpty) {
      _showSnack(
        'Check the employees first, then apply the times.',
        Colors.orange,
      );
      return;
    }

    int applied = 0;
    setState(() {
      for (final row in _rows) {
        if (!_selectedStaffIds.contains(row.staffId)) continue;
        if (row.isLocked || row.status != 'Present') continue;
        row.checkIn = _globalCheckIn;
        row.checkOut = _globalCheckOut;
        applied++;
      }
    });

    if (applied == 0) {
      _showSnack(
        'None of the checked employees is marked Present.',
        Colors.orange,
      );
    } else {
      _showSnack(
        'Times applied to $applied employee(s). Nothing is submitted until you press Submit.',
        Colors.blueGrey,
      );
    }
  }

  // ------------------------------------------------------------------
  // Overnight shift: if check-out <= check-in, check-out is on the next
  // calendar day. The attendance record date stays the check-in date.
  // ------------------------------------------------------------------
  String _fmtDateTimeForRow(
    TimeOfDay checkIn,
    TimeOfDay t, {
    required bool isCheckOut,
  }) {
    final baseDate = DateTime.parse(_dateStr);
    DateTime dt =
        DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);

    if (isCheckOut) {
      final checkInMinutes = checkIn.hour * 60 + checkIn.minute;
      final checkOutMinutes = t.hour * 60 + t.minute;
      if (checkOutMinutes <= checkInMinutes) {
        dt = dt.add(const Duration(days: 1));
      }
    }

    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d =
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return '$d $h:$m:00';
  }

  // ------------------------------------------------------------------
  // Saving. There is NO draft for staff: every save goes straight to the
  // admin as "Submitted". All buttons below use this same method; the only
  // difference between them is WHICH rows are sent.
  // ------------------------------------------------------------------
  Future<void> _saveSelected() async {
    final rows = _rows
        .where((r) => _selectedStaffIds.contains(r.staffId) && !r.isLocked)
        .toList();
    if (rows.isEmpty) {
      _showSnack('Check at least one employee first.', Colors.orange);
      return;
    }
    await _saveRows(rows);
  }

  Future<void> _saveOne(_StaffRow row) => _saveRows([row]);

  Future<void> _saveRows(List<_StaffRow> rowsToSave) async {
    final rows = rowsToSave.where((r) => !r.isLocked).toList();
    if (rows.isEmpty || _isSaving) return;

    // 1) Confirmation for bulk submits and for backdated dates.
    if (rows.length > 1 || _isBackdated) {
      final counts = <String, int>{};
      for (final r in rows) {
        counts[r.status] = (counts[r.status] ?? 0) + 1;
      }
      final summary =
          counts.entries.map((e) => '${e.value} ${e.key}').join('  •  ');

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_isBackdated ? 'Backdated Attendance' : 'Submit for Review'),
          content: Text(
            '${rows.length} employee(s) for $_dateStr\n$summary\n\n'
            '${_isBackdated ? 'This date is not today.\n' : ''}'
            'They will be sent to the admin for approval.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isBackdated ? Colors.orange.shade800 : primaryColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    // 2) Friday confirmation (only when someone is marked Present).
    bool fridayConfirmed = false;
    if (_isFridaySelected && rows.any((r) => r.status == 'Present')) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Friday Attendance'),
          content: const Text(
            'Friday is normally a non-working day. Are you sure you want to register attendance for the staff marked Present on this Friday?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      fridayConfirmed = true;
    }

    setState(() => _isSaving = true);

    try {
      final entries = rows.map((row) {
        final map = <String, dynamic>{
          'staff_id': row.staffId,
          'attendance_status': row.status,
        };
        if (row.status == 'Present') {
          map['check_in_time'] =
              _fmtDateTimeForRow(row.checkIn, row.checkIn, isCheckOut: false);
          map['check_out_time'] =
              _fmtDateTimeForRow(row.checkIn, row.checkOut, isCheckOut: true);
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
      final updatedIds = ((results['updated'] as List?) ?? [])
          .map((e) => int.tryParse('$e'))
          .whereType<int>()
          .toSet();

      if (skipped.isNotEmpty) {
        final first = skipped.first;
        final reason = first is Map ? first['reason'] : null;
        _showSnack(
          '${updatedIds.length} submitted, ${skipped.length} skipped'
          '${reason != null ? ' — $reason' : ''}',
          Colors.orange,
        );
      } else {
        _showSnack(
          '${updatedIds.length} submitted for admin review.',
          Colors.green.shade700,
        );
      }

      if (mounted) {
        // Only the ones that were really saved get un-checked; skipped ones
        // stay checked so the supervisor can see what still needs attention.
        setState(() => _selectedStaffIds.removeAll(updatedIds));
      }
      await _loadDay(justSavedIds: updatedIds);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to save')
          : 'Failed to save';
      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------------------------
  // UI helpers
  // ------------------------------------------------------------------
  Widget _timeStepper(TimeOfDay value, ValueChanged<TimeOfDay> onChanged) {
    TimeOfDay addMinutes(int delta) {
      final total = (value.hour * 60 + value.minute + delta) % (24 * 60);
      final normalized = total < 0 ? total + 24 * 60 : total;
      return TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60);
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
            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
            onPressed: onPlus,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _workflowBadge(_StaffRow row) {
    switch (row.workflowStatus) {
      case 'Approved':
        return _chip('Approved', Colors.green.shade700);
      case 'Submitted':
        return _chip('Submitted', Colors.orange.shade800);
      case 'Rejected':
        return _chip('Rejected', Colors.red.shade700);
      default:
        return _chip('Not recorded', Colors.grey.shade600);
    }
  }

  Widget _buildBulkTimeCard() {
    final checked = _checkedCount;
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
            'Set the same Check-in / Check-out for the CHECKED employees marked Present:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('In: '),
              _timeStepper(
                _globalCheckIn,
                (v) => setState(() => _globalCheckIn = v),
              ),
              const SizedBox(width: 20),
              const Text('Out: '),
              _timeStepper(
                _globalCheckOut,
                (v) => setState(() => _globalCheckOut = v),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: checked == 0 ? null : _applyGlobalToChecked,
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: Text(
                  checked == 0 ? 'Apply to Checked' : 'Apply to Checked ($checked)',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This only changes the times on screen. Nothing reaches the admin until you press Submit at the bottom.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            'If check-out is earlier than or equal to check-in, it is treated as the next calendar day (overnight shift).',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar() {
    final selectableIds = _selectableIds;
    final checked = _checkedCount;
    final allChecked = selectableIds.isNotEmpty && checked == selectableIds.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allChecked ? true : (checked == 0 ? false : null),
            tristate: true,
            onChanged: selectableIds.isEmpty
                ? null
                : (_) => setState(() {
                      if (allChecked) {
                        _selectedStaffIds.clear();
                      } else {
                        _selectedStaffIds
                          ..clear()
                          ..addAll(selectableIds);
                      }
                    }),
          ),
          Expanded(
            child: Text(
              checked == 0
                  ? 'Select all, then uncheck the ones you want to leave untouched'
                  : '$checked of ${selectableIds.length} checked',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (checked > 0)
            TextButton(
              onPressed: () => setState(_selectedStaffIds.clear),
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(_StaffRow row) {
    final locked = row.isLocked;
    final isSelected = !locked && _selectedStaffIds.contains(row.staffId);
    final isOvernight = (row.checkOut.hour * 60 + row.checkOut.minute) <=
        (row.checkIn.hour * 60 + row.checkIn.minute);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: locked
          ? Colors.grey.shade100
          : (isSelected ? primaryColor.withOpacity(0.04) : null),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: locked
                      ? null
                      : (v) => setState(() {
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
                      Text(row.fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${row.uniqueId} • ${row.position}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      _workflowBadge(row),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: row.status,
                  items: _statuses
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: locked
                      ? null
                      : (v) => setState(() => row.status = v ?? row.status),
                ),
                IconButton(
                  tooltip: 'Submit this employee only',
                  icon: Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: locked ? Colors.grey : Colors.green,
                  ),
                  onPressed: (locked || _isSaving) ? null : () => _saveOne(row),
                ),
              ],
            ),
            if (row.workflowStatus == 'Rejected' && row.rejectionNote != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rejected: ${row.rejectionNote}',
                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                ),
              ),
            ],
            if (locked) ...[
              const SizedBox(height: 6),
              Text(
                row.status == 'Present'
                    ? 'Approved by admin — locked (${_fmtTime(row.checkIn)} → ${_fmtTime(row.checkOut)})'
                    : 'Approved by admin — locked (${row.status})',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ] else if (row.status == 'Present') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check-in',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      _timeStepper(
                        row.checkIn,
                        (v) => setState(() => row.checkIn = v),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check-out',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      _timeStepper(
                        row.checkOut,
                        (v) => setState(() => row.checkOut = v),
                      ),
                    ],
                  ),
                ],
              ),
              if (isOvernight)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.nightlight_round,
                          size: 13, color: Colors.indigo.shade400),
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
  }

  @override
  Widget build(BuildContext context) {
    final checked = _checkedCount;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Staff Attendance',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _loadDay()),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.deepPurple.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Friday is normally a non-working day. Marking anyone Present will require confirmation on submit.',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.deepPurple.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('No active staff found'))
                      : RefreshIndicator(
                          onRefresh: () => _loadDay(),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _rows.length + 2,
                            itemBuilder: (context, index) {
                              if (index == 0) return _buildBulkTimeCard();
                              if (index == 1) return _buildSelectionToolbar();
                              return _buildStaffCard(_rows[index - 2]);
                            },
                          ),
                        ),
                ),
                // One single submit button: it sends ONLY the checked employees.
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_isSaving || checked == 0) ? null : _saveSelected,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white),
                        label: Text(
                          _isSaving
                              ? 'Submitting...'
                              : (checked == 0
                                  ? 'Check employees to submit'
                                  : 'Submit Checked ($checked) for Review'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          disabledBackgroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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