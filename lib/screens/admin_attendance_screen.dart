import 'package:dio/dio.dart';
import '../widgets/payroll_followup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/help_tip.dart';
import '../widgets/app_data_table.dart' show AppDataTableCard, AppColors;
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

// Date -> Site -> records
typedef _SiteGroups = Map<String, List<Map<String, dynamic>>>;

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final Set<int> _selectedIds = <int>{};
  Map<String, _SiteGroups> _grouped = {};
  bool _loading = true;
  bool _working = false;
  // D-12: server-side search / filter.
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = '';      // '' = Submitted + Rejected (server default)
  bool _onlyAnomalies = false;
  Map<String, dynamic> _summary = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _itemById(int id) {
    for (final sites in _grouped.values) {
      for (final list in sites.values) {
        for (final item in list) {
          if ('${item['attendance_id']}' == '$id') return item;
        }
      }
    }
    return null;
  }

  bool _hasOpenAnomaly(Map<String, dynamic>? item) =>
      item != null && item['anomaly_code'] != null && item['anomaly_ack_at'] == null;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final q = _searchController.text.trim();
      final response = await ApiConfig.dio.get('/admin/attendance/pending', queryParameters: {
        if (q.isNotEmpty) 'q': q,
        if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        if (_onlyAnomalies) 'anomaly': '1',
      });
      final raw = response.data is Map ? response.data['data'] : null;
      final summary = response.data is Map && response.data['summary'] is Map
          ? Map<String, dynamic>.from(response.data['summary'])
          : <String, dynamic>{};

      // date -> site -> [records]
      final byDate = <String, _SiteGroups>{};

      if (raw is List) {
        for (final value in raw) {
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          final rawDate = '${item['record_date'] ?? '1970-01-01'}';
          final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
          final siteName = (item['site_name'] ?? 'Unknown Site').toString();

          byDate.putIfAbsent(date, () => <String, List<Map<String, dynamic>>>{});
          byDate[date]!.putIfAbsent(siteName, () => <Map<String, dynamic>>[]);
          byDate[date]![siteName]!.add(item);
        }
      }

      final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
      final ordered = <String, _SiteGroups>{};
      for (final date in sortedDates) {
        final sites = byDate[date]!;
        final sortedSites = sites.keys.toList()..sort();
        final orderedSites = <String, List<Map<String, dynamic>>>{};
        for (final site in sortedSites) {
          orderedSites[site] = sites[site]!;
        }
        ordered[date] = orderedSites;
      }

      if (!mounted) return;
      setState(() {
        _grouped = ordered;
        _summary = summary;
        _selectedIds.clear();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_errorMessage(e, 'Failed to load attendance records.'), false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Failed to load attendance records.', false);
    }
  }

  String _errorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }

  List<int> _idsOf(List<Map<String, dynamic>> items) {
    return items
        .map((item) => int.tryParse('${item['attendance_id']}'))
        .whereType<int>()
        .toList();
  }

  /// D-09: flagged records need an explicit acknowledgement note to be approved.
  Future<String?> _askAnomalyAck(List<Map<String, dynamic>> flagged, {int? total}) async {
    final ctrl = TextEditingController();
    bool checked = false;
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            Icon(Icons.report_problem_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(child: Text('Records need review')),
            const HelpTip(title: 'Long session', message: HelpTexts.longShift),
          ]),
          content: SizedBox(
            width: 500,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (total != null && total > flagged.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${flagged.length} of $total record(s) have abnormal hours. '
                    'Confirming approves all $total.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ...flagged.take(8).map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• ${i['full_name']} — ${i['record_date']}: ${i['anomaly_detail'] ?? i['anomaly_code']}',
                        style: const TextStyle(fontSize: 13)),
                  )),
              if (flagged.length > 8) Text('…and ${flagged.length - 8} more'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: checked,
                onChanged: (v) => setD(() => checked = v == true),
                title: const Text('I checked these times and they are correct'),
              ),
              TextField(
                controller: ctrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Review note (required, min. 5 characters)',
                  errorText: err,
                  border: const OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!checked || ctrl.text.trim().length < 5) {
                  setD(() => err = 'Tick the confirmation and enter a note');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return res;
  }

  String _statusOf(Map<String, dynamic>? item) =>
      '${item?['status'] ?? item?['attendance_status'] ?? 'Submitted'}';

  /// Only Submitted records can be approved / rejected.
  List<int> _submittedOnly(Iterable<int> ids) =>
      ids.where((id) => _statusOf(_itemById(id)) == 'Submitted').toList();

  /// Approve a whole day (or any selection) in one go. Records with abnormal
  /// hours (open anomaly) still go through the review dialog in
  /// _reviewSelected; everything else only needs one confirmation.
  Future<void> _approveMany(List<int> ids, {required String label}) async {
    final submitted = _submittedOnly(ids);
    if (submitted.isEmpty) {
      _showMessage('Nothing waiting for approval in $label.', false);
      return;
    }
    await _reviewSelected(submitted, 'Approved', confirmLabel: label);
  }

  Future<void> _rejectMany(List<int> ids) async {
    final submitted = _submittedOnly(ids);
    if (submitted.isEmpty) {
      _showMessage('Nothing waiting for review in the selection.', false);
      return;
    }
    final note = await _promptForReason(context);
    if (note != null) await _reviewSelected(submitted, 'Rejected', note: note);
  }

  Future<bool> _confirmApprove(int count, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve records'),
        content: Text('Approve $count record(s) for $label?\nNo abnormal hours were found.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Approve $count'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _reviewSelected(List<int> ids, String status, {String? note, String? confirmLabel}) async {
    if (ids.isEmpty || _working) return;

    String? ackNote;
    if (status == 'Approved') {
      final flagged = ids.map(_itemById).where(_hasOpenAnomaly).cast<Map<String, dynamic>>().toList();
      if (flagged.isNotEmpty) {
        // Abnormal hours: the admin must review them before approving.
        ackNote = await _askAnomalyAck(flagged, total: ids.length);
        if (ackNote == null) return;
      } else if (confirmLabel != null && ids.length > 1) {
        if (!await _confirmApprove(ids.length, confirmLabel)) return;
      }
    }

    setState(() => _working = true);

    final succeeded = <int>[];
    final failed = <int>[];
    String? firstError;
    for (final id in ids) {
      try {
        final flagged = _hasOpenAnomaly(_itemById(id));
        await ApiConfig.dio.post('/admin/attendance/review', data: {
          'attendance_id': id,
          'status': status,
          'admin_note': note,
          if (flagged && ackNote != null) 'acknowledge_anomaly': true,
          if (flagged && ackNote != null) 'anomaly_note': ackNote,
        });
        succeeded.add(id);
      } on DioException catch (e) {
        failed.add(id);
        firstError ??= _errorMessage(e, 'Request failed');
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() => _working = false);
    if (failed.isEmpty) {
      _showMessage('${succeeded.length} record(s) processed successfully.', true);
    } else {
      _showMessage('${succeeded.length} succeeded, ${failed.length} failed.${firstError != null ? ' $firstError' : ''}', false);
    }
    await _fetchData();
  }

  /// D-02: Admin correction. Works also inside a finalized payroll period:
  /// the backend logs the correction and, if the record was already paid in a
  /// locked batch, opens a payroll adjustment instead of changing payroll.
  Future<void> _showCorrectionDialog(Map<String, dynamic> item) async {
    final id = item['attendance_id'];
    String full(dynamic v) {
      if (v == null) return '';
      final t = '$v'.replaceFirst('T', ' ');
      return t.length >= 16 ? t.substring(0, 16) : t;
    }
    final inCtrl = TextEditingController(text: full(item['check_in_time']));
    final outCtrl = TextEditingController(text: full(item['check_out_time']));
    final reasonCtrl = TextEditingController();
    final lunchFromCtrl = TextEditingController();
    final lunchToCtrl = TextEditingController();
    bool workedThroughLunch = false;
    final hmRe = RegExp(r'^\d{2}:\d{2}$');
    String status = '${item['attendance_status'] ?? 'Present'}';
    const statuses = ['Present', 'Absent', 'Sick', 'Vacation', 'Holiday'];
    if (!statuses.contains(status)) status = 'Present';
    String? err;
    final dtRe = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Row(children: [
            Expanded(child: Text('Correct attendance — ${item['full_name'] ?? ''}')),
            const HelpTip(title: 'Admin correction', message: HelpTexts.payrollLocked),
          ]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Record date: ${item['record_date']} · ${item['site_name']} (${item['shift_type'] ?? 'Day'})',
                    style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Attendance status', border: OutlineInputBorder()),
                  items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setD(() => status = v ?? status),
                ),
                if (status == 'Present') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: inCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Check-in (YYYY-MM-DD HH:MM)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: outCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Check-out (YYYY-MM-DD HH:MM)',
                        helperText: 'Night shift: check-out may be on the next day',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  // Lunch: empty = the site's lunch of that day (like Submit Day).
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: lunchFromCtrl,
                        enabled: !workedThroughLunch,
                        decoration: const InputDecoration(labelText: 'Lunch from (HH:MM)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lunchToCtrl,
                        enabled: !workedThroughLunch,
                        decoration: const InputDecoration(labelText: 'Lunch to (HH:MM)', border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Leave empty to use the site\'s lunch of that day.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: workedThroughLunch,
                    title: const Text('Worked through lunch (no lunch deducted)'),
                    onChanged: (v) => setD(() => workedThroughLunch = v ?? false),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: 'Reason (required)', errorText: err, border: const OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (reasonCtrl.text.trim().length < 5) {
                  setD(() => err = 'Enter a reason (min. 5 characters)');
                  return;
                }
                if (status == 'Present' &&
                    (!dtRe.hasMatch(inCtrl.text.trim()) ||
                        (outCtrl.text.trim().isNotEmpty && !dtRe.hasMatch(outCtrl.text.trim())))) {
                  setD(() => err = 'Times must look like 2026-10-01 07:30');
                  return;
                }
                final lf = lunchFromCtrl.text.trim();
                final lt = lunchToCtrl.text.trim();
                if (status == 'Present' && !workedThroughLunch && (lf.isNotEmpty || lt.isNotEmpty) &&
                    (!hmRe.hasMatch(lf) || !hmRe.hasMatch(lt))) {
                  setD(() => err = 'Lunch times must look like 12:00 and 13:00');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save correction'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        final r = await ApiConfig.dio.post('/attendance/$id/admin-correction', data: {
          'reason': reasonCtrl.text.trim(),
          'attendance_status': status,
          if (status == 'Present') 'check_in_time': '${inCtrl.text.trim()}:00',
          if (status == 'Present' && outCtrl.text.trim().isNotEmpty) 'check_out_time': '${outCtrl.text.trim()}:00',
          if (status == 'Present' && workedThroughLunch) 'worked_through_lunch': true,
          if (status == 'Present' && !workedThroughLunch && lunchFromCtrl.text.trim().isNotEmpty)
            'lunch_start_time': lunchFromCtrl.text.trim(),
          if (status == 'Present' && !workedThroughLunch && lunchToCtrl.text.trim().isNotEmpty)
            'lunch_end_time': lunchToCtrl.text.trim(),
        });
        final msg = r.data is Map ? (r.data['message'] ?? 'Correction saved').toString() : 'Correction saved';
        // Retro pay: a paid period gets an automatic adjustment; a finalized /
        // open batch gets a hint. Shown in a dialog; otherwise the usual snack.
        final shown = mounted ? await showPayrollFollowUp(context, r.data) : false;
        if (!shown) _showMessage(msg, true);
        await _fetchData();
      } on DioException catch (e) {
        _showMessage(_errorMessage(e, 'Failed to save the correction.'), false);
      }
    }
    inCtrl.dispose();
    outCtrl.dispose();
    reasonCtrl.dispose();
    lunchFromCtrl.dispose();
    lunchToCtrl.dispose();
  }

  /// Admin delete of a record entered on the wrong site/shift. The backend
  /// refuses it inside a payroll batch, for biometric records and for records
  /// with correction history; its message is shown as is.
  Future<void> _showDeleteDialog(Map<String, dynamic> item) async {
    final id = item['attendance_id'];
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Delete attendance — ${item['full_name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record date: ${item['record_date']} · ${item['site_name']} (${item['shift_type'] ?? 'Day'})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'Use this only for a record entered on the wrong site or shift. '
                'After deleting, fix the worker assignment, then enter the day again on the right shift. '
                'This cannot be undone (the record is kept in the audit log).',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: reasonCtrl.text.trim().length < 5 ? null : () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        final r = await ApiConfig.dio.post('/attendance/$id/admin-delete', data: {'reason': reasonCtrl.text.trim()});
        _showMessage(r.data is Map ? (r.data['message'] ?? 'Record deleted').toString() : 'Record deleted', true);
        await _fetchData();
      } on DioException catch (e) {
        _showMessage(_errorMessage(e, 'Failed to delete the record.'), false);
      }
    }
    reasonCtrl.dispose();
  }

  Future<String?> _promptForReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for correction'),
        content: TextField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Management leave: counter-based input (minutes, step 15) instead of a
  // free-text field. Sends decimal hours to the server (minutes / 60),
  // matching the `decimal(4,2)` column and avoiding ambiguous manual entry.
  // ---------------------------------------------------------------------

Future<void> _showManagementLeaveDialog(
  int attendanceId, {
  num currentHours = 0,
  required bool hasCheckIn,
}) async {
  int minutes = ((currentHours * 60) / 15).round() * 15; // snap to nearest 15
  if (minutes < 0) minutes = 0;
  if (minutes > 24 * 60) minutes = 24 * 60;
  final reason = TextEditingController();
  String? reasonError;
 
  String fmt(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
 
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Management leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCheckIn
                  ? 'Use the counter to set the compensated time (steps of 15 minutes).'
                  : 'This worker has no check-in (Absent/Sick/Vacation/Holiday). '
                      'These hours will be counted directly as working hours, '
                      'so a reason is required.',
              style: TextStyle(
                fontSize: 12,
                color: hasCheckIn ? Colors.grey : Colors.orange.shade800,
                fontWeight: hasCheckIn ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: minutes <= 0
                      ? null
                      : () => setDialogState(() => minutes -= 15),
                ),
                Container(
                  width: 110,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    fmt(minutes),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: minutes >= 24 * 60
                      ? null
                      : () => setDialogState(() => minutes += 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLines: 2,
              onChanged: (_) {
                if (reasonError != null) setDialogState(() => reasonError = null);
              },
              decoration: InputDecoration(
                // Mark as required only when there's no check-in.
                labelText: hasCheckIn ? 'Reason (optional)' : 'Reason *',
                border: const OutlineInputBorder(),
                errorText: reasonError,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!hasCheckIn && reason.text.trim().isEmpty) {
                setDialogState(() => reasonError = 'A reason is required for workers with no check-in.');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
 
  final reasonValue = reason.text.trim();
  reason.dispose();
  if (result != true) return;
 
  final hoursValue = minutes / 60.0;
 
  try {
    final response = await ApiConfig.dio.patch('/attendance/$attendanceId/management-leave', data: {
      'hours': hoursValue,
      'reason': reasonValue,
    });
 
    if (!mounted) return;
    _showMessage('Management leave saved (${fmt(minutes)}).', true);
 
    // Server returns a `warning` when the shift is still open (check-in
    // without check-out): the hours were saved but not yet reflected in
    // total_working_hours until checkout happens.
    final warning = response.data is Map ? response.data['warning'] : null;
    if (warning != null && '$warning'.trim().isNotEmpty) {
      // Slight delay so it doesn't collide with the success snackbar above.
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _showMessage('$warning', false);
      });
    }
 
    await _fetchData();
  } on DioException catch (e) {
    if (mounted) _showMessage(_errorMessage(e, 'Failed to save management leave.'), false);
  }
}

  /// D-08 / D-14: effective-dated settings. Changes apply from "Effective from";
  /// a back-dated change needs a reason and is refused inside finalized payroll.
  Future<void> _showSettingsDialog() async {
    Map data = {};
    String today = '';
    try {
      final response = await ApiConfig.dio.get('/admin/attendance/settings/breaks');
      if (response.data is Map && response.data['data'] is Map) data = response.data['data'];
      today = response.data is Map ? '${response.data['business_today'] ?? ''}' : '';
    } catch (_) {
      if (mounted) _showMessage('Failed to load settings.', false);
      return;
    }
    if (!mounted) return;

    bool lunchPaid = '${data['is_lunch_paid']}'.toLowerCase() == 'true';
    final minutesCtrl = TextEditingController(text: '${data['standard_work_minutes'] ?? ''}');
    final otRateCtrl = TextEditingController(text: data['overtime_flat_rate_syp'] == null ? '' : '${data['overtime_flat_rate_syp']}');
    final longShiftCtrl = TextEditingController(text: '${data['long_shift_review_hours'] ?? 16}');
    final reasonCtrl = TextEditingController();
    int weekStart = int.tryParse('${data['attendance_week_start_day'] ?? 6}') ?? 6;
    // Initial values: only fields the Admin actually changed are sent, so an
    // overtime-rate-only change never touches the lunch / standard-hours rules.
    final bool lunchPaidInitial = lunchPaid;
    final int weekStartInitial = weekStart;
    final String minutesInitial = minutesCtrl.text.trim();
    final String otRateInitial = otRateCtrl.text.trim();
    final String longShiftInitial = longShiftCtrl.text.trim();
    final bool gateInitial = '${data['attendance_daily_gate_enabled'] ?? 'true'}'.toLowerCase() != 'false';
    final String gateStartInitial = '${data['attendance_daily_gate_start_date'] ?? ''}';
    bool gateEnabled = gateInitial;
    String gateStart = gateStartInitial;
    DateTime effective = DateTime.tryParse(today) ?? DateTime.now();
    final todayDate = DateTime.tryParse(today) ?? DateTime.now();
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(children: [
            Expanded(child: Text('Attendance & payroll settings')),
            HelpTip(
              title: 'How settings apply',
              message: 'Each change is stored with an "Effective from" date and kept in history. '
                  'Records already Submitted or Approved on/after that date are never recalculated silently. '
                  'A back-dated date needs a reason and cannot fall inside a finalized payroll period.',
            ),
          ]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lunch is paid'),
                    value: lunchPaid,
                    onChanged: (value) => setDialogState(() => lunchPaid = value),
                  ),
                  TextField(
                    controller: minutesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Standard work minutes per day', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Overtime rate (SYP per hour, workers)',
                      helperText: 'Required before worker payroll can be generated',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: longShiftCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Long-session review threshold (hours)',
                      helperText: 'Warning only — never changes the record or the shift',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: weekStart,
                    decoration: const InputDecoration(labelText: 'Attendance week starts on', border: OutlineInputBorder()),
                    items: List.generate(7, (i) => DropdownMenuItem(value: i, child: Text(days[i]))),
                    onChanged: (v) => setDialogState(() => weekStart = v ?? weekStart),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Supervisors submit days in order'),
                    subtitle: const Text('A day cannot be recorded or submitted while an earlier day of the same '
                        'site/shift is still Draft or not recorded. An empty Friday is skipped.'),
                    value: gateEnabled,
                    onChanged: (value) => setDialogState(() => gateEnabled = value),
                  ),
                  if (gateEnabled)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(gateStart.isEmpty ? 'Check the last 60 days' : 'Check days from $gateStart'),
                      subtitle: const Text('Older days are never checked'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (gateStart.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setDialogState(() => gateStart = ''),
                          ),
                        const Icon(Icons.edit_calendar),
                      ]),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.tryParse(gateStart) ?? todayDate,
                          firstDate: DateTime(2024),
                          lastDate: todayDate,
                        );
                        if (d != null) setDialogState(() => gateStart = fmt(d));
                      },
                    ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text('Effective from: ${fmt(effective)}'),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: effective,
                        firstDate: DateTime(2024),
                        lastDate: todayDate,
                      );
                      if (d != null) setDialogState(() => effective = d);
                    },
                  ),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason (required when back-dated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final body = <String, dynamic>{};
                if (lunchPaid != lunchPaidInitial) body['is_lunch_paid'] = lunchPaid;
                if (weekStart != weekStartInitial) body['attendance_week_start_day'] = weekStart;
                if (minutesCtrl.text.trim() != minutesInitial) {
                  final value = int.tryParse(minutesCtrl.text.trim());
                  if (value == null || value <= 0 || value > 1440) {
                    _showMessage('Minutes must be between 1 and 1440.', false);
                    return;
                  }
                  body['standard_work_minutes'] = value;
                }
                if (otRateCtrl.text.trim() != otRateInitial && otRateCtrl.text.trim().isNotEmpty) {
                  final ot = double.tryParse(otRateCtrl.text.trim());
                  if (ot == null || ot <= 0) {
                    _showMessage('Overtime rate must be a positive number.', false);
                    return;
                  }
                  body['overtime_flat_rate_syp'] = ot;
                }
                if (longShiftCtrl.text.trim() != longShiftInitial) {
                  final ls = double.tryParse(longShiftCtrl.text.trim());
                  if (ls == null || ls < 4 || ls > 48) {
                    _showMessage('Long-session threshold must be between 4 and 48 hours.', false);
                    return;
                  }
                  body['long_shift_review_hours'] = ls;
                }
                if (gateEnabled != gateInitial) body['attendance_daily_gate_enabled'] = gateEnabled;
                if (gateStart != gateStartInitial) body['attendance_daily_gate_start_date'] = gateStart;
                if (body.isEmpty) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) _showMessage('Nothing changed.', true);
                  return;
                }
                body['effective_from'] = fmt(effective);
                if (reasonCtrl.text.trim().isNotEmpty) body['reason'] = reasonCtrl.text.trim();
                try {
                  await ApiConfig.dio.put('/admin/attendance/settings/breaks', data: body);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) _showMessage('Settings saved (effective ${fmt(effective)}).', true);
                } on DioException catch (e) {
                  if (mounted) _showMessage(_errorMessage(e, 'Failed to update settings.'), false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    minutesCtrl.dispose();
    otRateCtrl.dispose();
    longShiftCtrl.dispose();
    reasonCtrl.dispose();
  }

  void _showMessage(String message, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: color.withOpacity(.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(.15), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ])),
          ],
        ),
      ),
    );
  }

  String _timeOnly(dynamic value) {
    if (value == null) return '--:--';
    final text = '$value'.replaceFirst('T', ' ');
    return text.length > 16 ? text.substring(11, 16) : text;
  }

  Widget _statusChip(String status) {
    final rejected = status == 'Rejected';
    final color = rejected ? Colors.red : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  // ── Worker attendance table (shared AppDataTableCard) ──────────────────
  static DataColumn _col(String label) => DataColumn(
        label: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label),
        ),
      );

  static final List<DataColumn> _workerColumns = [
    const DataColumn(label: SizedBox(width: 44)),
    _col('Worker'),
    _col('Status'),
    _col('Check in'),
    _col('Check out'),
    _col('Hours'),
    _col('Overtime'),
    _col('Mgmt leave'),
    _col('Notes'),
    _col('Actions'),
  ];

  DataCell _cell(Widget child) => DataCell(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: child,
        ),
      );

  Widget _pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // One table row per attendance record. Same data and same actions the
  // old per-worker card had — only the presentation changed.
  DataRow? _workerRow(Map<String, dynamic> item) {
    final id = int.tryParse('${item['attendance_id']}');
    if (id == null) return null;

    final status = '${item['status'] ?? item['attendance_status'] ?? 'Submitted'}';
    final rejected = status == 'Rejected';
    final selected = _selectedIds.contains(id);

    final overtimeHours = double.tryParse('${item['overtime_hours'] ?? 0}') ?? 0;
    final hasOvertime = overtimeHours > 0;
    final managementHours = double.tryParse('${item['management_leave_hours'] ?? 0}') ?? 0;

    // Notes: anomaly (needs review / reviewed) and admin rejection note.
    final notes = <Widget>[];
    if (item['anomaly_code'] != null) {
      final open = item['anomaly_ack_at'] == null;
      final text = open
          ? 'Needs review: ${item['anomaly_detail'] ?? item['anomaly_code']}'
          : 'Reviewed: ${item['anomaly_ack_note'] ?? ''}';
      notes.add(Tooltip(
        message: text,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.report_problem_rounded, size: 15,
              color: open ? Colors.orange.shade800 : Colors.grey),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ]),
      ));
    }
    if (rejected && item['admin_rejection_notes'] != null) {
      final text = '${item['admin_rejection_notes']}';
      notes.add(Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.red.shade800, fontSize: 12),
        ),
      ));
    }

    return DataRow(
      key: ValueKey('att-$id'),
      selected: selected,
      cells: [
        DataCell(Center(
          child: Checkbox(
            value: selected,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => setState(() => v == true ? _selectedIds.add(id) : _selectedIds.remove(id)),
          ),
        )),
        _cell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            '${item['full_name'] ?? 'Worker'}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        )),
        _cell(_statusChip(status)),
        _cell(Text(_timeOnly(item['check_in_time']))),
        _cell(Text(_timeOnly(item['check_out_time']))),
        _cell(Text('${item['total_working_hours'] ?? '--'}h')),
        _cell(hasOvertime
            ? _pill('${overtimeHours.toStringAsFixed(2)}h', Colors.deepPurple.shade400, icon: Icons.bolt_rounded)
            : Text('—', style: TextStyle(color: Colors.grey.shade500))),
        _cell(managementHours > 0
            ? _pill('${managementHours.toStringAsFixed(2)}h', Colors.teal.shade700)
            : Text('—', style: TextStyle(color: Colors.grey.shade500))),
        _cell(notes.isEmpty
            ? Text('—', style: TextStyle(color: Colors.grey.shade500))
            : SizedBox(
                width: 220,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: notes,
                ),
              )),
        _cell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'Submitted')
              TextButton.icon(
                onPressed: _working ? null : () => _reviewSelected([id], 'Approved'),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            // B6: biometric records can be rejected like manual ones; the
            // supervisor corrects and resubmits them.
            if (status == 'Submitted')
              TextButton.icon(
                onPressed: _working
                    ? null
                    : () async {
                        final note = await _promptForReason(context);
                        if (note != null) {
                          await _reviewSelected([id], 'Rejected', note: note);
                        }
                      },
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reject', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            IconButton(
              tooltip: 'Correct attendance (Admin)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_note_rounded, size: 20, color: Colors.indigo),
              onPressed: () => _showCorrectionDialog(item),
            ),
            if (item['source'] != 'Biometric')
              IconButton(
                tooltip: 'Delete record (wrong site/shift)',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red.shade700),
                onPressed: _working ? null : () => _showDeleteDialog(item),
              ),
            IconButton(
              tooltip: 'Management leave',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_time_rounded, size: 19, color: Colors.teal),
              onPressed: () => _showManagementLeaveDialog(
                id,
                currentHours: managementHours,
                hasCheckIn: item['check_in_time'] != null,
              ),
            ),
          ],
        )),
      ],
    );
  }

Widget _siteSection(String date, String siteName, List<Map<String, dynamic>> items) {
  final ids = _idsOf(items);
  final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);

  final shiftGroups = <String, List<Map<String, dynamic>>>{};

  for (final item in items) {
    final shift = item['shift_type'] == 'Night' ? 'Night' : 'Day';
    shiftGroups.putIfAbsent(shift, () => []).add(item);
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: true,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selectedIds.addAll(ids);
                } else {
                  _selectedIds.removeAll(ids);
                }
              }),
            ),
            Icon(
              Icons.location_on,
              size: 15,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                siteName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${items.length}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        ...shiftGroups.entries.map((entry) {
          final shiftType = entry.key;
          final shiftItems = entry.value;

          final shiftIds = _idsOf(shiftItems);
          final shiftSelected =
              shiftIds.isNotEmpty && shiftIds.every(_selectedIds.contains);
          final shiftSome =
              !shiftSelected && shiftIds.any(_selectedIds.contains);

          final selected = shiftIds
              .where(_selectedIds.contains)
              .toList();

          final overtimeCount = shiftItems.where(
            (i) => (double.tryParse('${i['overtime_hours'] ?? 0}') ?? 0) > 0,
          ).length;

          final isNight = shiftType == 'Night';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selected.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: _working
                            ? null
                            : () => _reviewSelected(selected, 'Approved'),
                        icon: const Icon(Icons.check, size: 15),
                        label: Text(
                          'Approve ${selected.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _working
                            ? null
                            : () async {
                                final note = await _promptForReason(context);
                                if (note != null) {
                                  await _reviewSelected(selected, 'Rejected', note: note);
                                }
                              },
                        icon: const Icon(Icons.close, size: 15),
                        label: Text(
                          'Reject ${selected.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                AppDataTableCard(
                  title: '$shiftType shift',
                  subtitle: '${shiftItems.length} record(s)',
                  icon: isNight ? Icons.nightlight_outlined : Icons.wb_sunny_outlined,
                  accentColor: AppColors.primary,
                  padding: const EdgeInsets.all(12),
                  emptyMessage: 'No records for this shift.',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (overtimeCount > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$overtimeCount OT',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.deepPurple.shade400,
                            ),
                          ),
                        ),
                      Text('Select all', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Checkbox(
                        value: shiftSelected ? true : (shiftSome ? null : false),
                        tristate: true,
                        visualDensity: VisualDensity.compact,
                        onChanged: shiftIds.isEmpty
                            ? null
                            : (_) => setState(() {
                                  if (shiftSelected) {
                                    _selectedIds.removeAll(shiftIds);
                                  } else {
                                    _selectedIds.addAll(shiftIds);
                                  }
                                }),
                      ),
                    ],
                  ),
                  columns: _workerColumns,
                  rows: shiftItems
                      .map(_workerRow)
                      .whereType<DataRow>()
                      .toList(),
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

  Widget _filterBar() {
    const filters = [
      ('', 'Pending + Rejected'),
      ('Submitted', 'Submitted'),
      ('Rejected', 'Rejected'),
      ('Approved', 'Approved'),
      ('Draft', 'Draft'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _fetchData(),
            decoration: InputDecoration(
              hintText: 'Search worker name or ID, then press Enter',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _fetchData();
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
        const HelpTip(title: 'Attendance workflow', message: HelpTexts.workflow),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in filters)
          ChoiceChip(
            label: Text(f.$2),
            selected: _statusFilter == f.$1,
            onSelected: (_) {
              setState(() => _statusFilter = f.$1);
              _fetchData();
            },
          ),
        FilterChip(
          avatar: const Icon(Icons.report_problem_rounded, size: 16),
          label: const Text('Needs review only'),
          selected: _onlyAnomalies,
          onSelected: (v) {
            setState(() => _onlyAnomalies = v);
            _fetchData();
          },
        ),
      ]),
    ]);
  }

  Widget _dateSection(String date, _SiteGroups sites) {
    final allItemsForDate = sites.values.expand((v) => v).toList();
    final ids = _idsOf(allItemsForDate);
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    final pendingIds = _submittedOnly(ids);
    final flaggedCount = pendingIds.map(_itemById).where(_hasOpenAnomaly).length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        title: Row(children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) => setState(() {
              if (value == true) {
                _selectedIds.addAll(ids);
              } else {
                _selectedIds.removeAll(ids);
              }
            }),
          ),
          Expanded(child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          Text('${allItemsForDate.length} records • ${sites.length} sites', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ]),
        subtitle: pendingIds.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 48, top: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton.icon(
                      onPressed: _working ? null : () => _approveMany(pendingIds, label: date),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: Text('Approve day (${pendingIds.length})', style: const TextStyle(fontSize: 12.5)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                    if (flaggedCount > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.report_problem_rounded, size: 15, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text('$flaggedCount with abnormal hours',
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                      ]),
                  ]),
                ),
              ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: sites.entries.map((e) => _siteSection(date, e.key, e.value)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown whenever something is selected (record, shift, site or a whole
  /// day), so a selection made with the date / site checkbox can be acted on.
  Widget? _selectionBar() {
    if (_selectedIds.isEmpty) return null;
    final ids = _selectedIds.toList();
    final pending = _submittedOnly(ids).length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text('${ids.length} selected · $pending waiting',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () => setState(_selectedIds.clear),
                child: const Text('Clear'),
              ),
              FilledButton.icon(
                onPressed: pending == 0 ? null : _rejectSelectedBar,
                icon: const Icon(Icons.close, size: 16),
                label: Text('Reject $pending'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              ),
              FilledButton.icon(
                onPressed: pending == 0 ? null : () => _approveMany(ids, label: 'the selection'),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: Text('Approve $pending'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _rejectSelectedBar() => _rejectMany(_selectedIds.toList());

  @override
  Widget build(BuildContext context) {
    final allItems = _grouped.values.expand((sites) => sites.values.expand((v) => v)).toList();
    final pending = _summary['submitted'] ?? allItems.where((i) => '${i['status']}' == 'Submitted').length;
    final rejected = _summary['rejected'] ?? allItems.where((i) => '${i['status']}' == 'Rejected').length;
    final anomaliesOpen = _summary['anomalies_open'] ?? allItems.where(_hasOpenAnomaly).length;
    final overtimeTotal = allItems.where((i) => (double.tryParse('${i['overtime_hours'] ?? 0}') ?? 0) > 0).length;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Admin Attendance Review',
        actions: [
          IconButton(onPressed: _showSettingsDialog, icon: const Icon(Icons.tune), tooltip: 'Settings'),
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                      children: [
                        _filterBar(),
                        const SizedBox(height: 12),
                        if (_grouped.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 80),
                            child: Center(child: Text('No attendance records match these filters.')),
                          ),
                        LayoutBuilder(builder: (context, constraints) {
                          final cards = [
                            _summaryCard('Submitted', '$pending', Icons.pending_actions, Colors.orange),
                            _summaryCard('Rejected', '$rejected', Icons.warning_amber, Colors.red),
                            _summaryCard('With Overtime', '$overtimeTotal', Icons.bolt_rounded, Colors.deepPurple),
                            _summaryCard('Needs review', '$anomaliesOpen', Icons.report_problem_rounded, Colors.deepOrange),
                          ];
                          return constraints.maxWidth < 650
                              ? Column(children: cards.map((card) => Padding(padding: const EdgeInsets.only(bottom: 8), child: card)).toList())
                              : Row(children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 10),
                                    Expanded(child: cards[i]),
                                  ],
                                ]);
                        }),
                        const SizedBox(height: 10),
                        ..._grouped.entries.map((entry) => _dateSection(entry.key, entry.value)),
                      ],
                    ),
            ),
      bottomNavigationBar: _working
          ? const LinearProgressIndicator(minHeight: 3)
          : _selectionBar(),
    );
  }
}