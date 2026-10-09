// lib/screens/staff_approved_records_screen.dart
//
// Staff attendance AFTER review (Approved). Until now an approved record left
// the review list and could not be changed from the app. Here the Admin can:
//   * Mark paid / unpaid  (Sick / Vacation / Holiday) while the month is open;
//   * Correct             any record, also in a finalized or paid month
//                         (reason required; original kept; a paid month gets
//                         an automatic payroll adjustment for the next batch).
// Each row shows which payroll batch covers its date.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/payroll_followup_dialog.dart';

const Color _kPrimary = Color(0xFF1A2A6C);

class StaffApprovedRecordsScreen extends StatefulWidget {
  const StaffApprovedRecordsScreen({super.key});

  @override
  State<StaffApprovedRecordsScreen> createState() => _StaffApprovedRecordsScreenState();
}

class _StaffApprovedRecordsScreenState extends State<StaffApprovedRecordsScreen> {
  late DateTime _month;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _staff = [];
  int? _staffId;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _loadStaff();
    _load();
  }

  String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  String _err(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) return '${(e.response!.data as Map)['message'] ?? fallback}';
    return fallback;
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _loadStaff() async {
    try {
      final r = await ApiConfig.dio.get('/staff');
      final list = (r.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      list.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
      if (mounted) setState(() => _staff = list);
    } catch (_) {/* the filter is optional */}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiConfig.dio.get('/staff-attendance/admin/records', queryParameters: {
        'start_date': _d(_month),
        'end_date': _d(_monthEnd),
        if (_staffId != null) 'staff_id': _staffId,
      });
      _rows = (r.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      _snack(_err(e, 'Failed to load records'), ok: false);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  Future<String?> _askReason(String title, String message) async {
    final ctrl = TextEditingController();
    String? err;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: 'Reason (required)', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < 5) { setD(() => err = 'Min. 5 characters'); return; }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return r;
  }

  // ---------------------------------------------------------------- actions
  Future<void> _markPaid(Map<String, dynamic> r, bool paid) async {
    final reason = await _askReason(paid ? 'Mark as paid' : 'Mark as unpaid',
        '${r['full_name']} — ${r['attendance_status']} on ${r['record_date']}.');
    if (reason == null) return;
    try {
      final res = await ApiConfig.dio.post('/staff-attendance/admin/${r['staff_attendance_id']}/paid', data: {'is_paid': paid ? 1 : 0, 'reason': reason});
      _snack('${res.data['message'] ?? 'Saved'}');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed'), ok: false);
    }
  }

  Future<void> _correct(Map<String, dynamic> r) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StaffCorrectionDialog(record: r),
    );
    if (result == null) return;
    try {
      final res = await ApiConfig.dio.post('/staff-attendance/admin/${r['staff_attendance_id']}/correction', data: result);
      if (!mounted) return;
      final shown = await showPayrollFollowUp(context, res.data);
      if (!shown) _snack('${res.data['message'] ?? 'Correction saved'}');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed to save the correction'), ok: false);
    }
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows.where((r) => '${r['full_name']} ${r['staff_unique_id']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Approved Staff Records',
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
              Text('${_months[_month.month - 1]} ${_month.year}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next month'),
            ]),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                value: _staffId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Staff member', isDense: true, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All staff')),
                  for (final s in _staff)
                    DropdownMenuItem<int?>(value: int.tryParse('${s['staff_id']}'), child: Text('${s['full_name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) { setState(() => _staffId = v); _load(); },
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text('No approved records in this month', style: TextStyle(color: Colors.grey.shade600)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tile(rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _payrollChip(Map payroll) {
    final state = '${payroll['state']}';
    final id = payroll['batch_id'];
    late Color c;
    late String label;
    switch (state) {
      case 'Paid':
        c = Colors.green.shade700; label = 'Paid · batch #$id';
        break;
      case 'Finalized':
        c = Colors.indigo; label = 'Finalized · batch #$id';
        break;
      case 'Generated':
        c = Colors.orange.shade800; label = 'In batch #$id (not finalized)';
        break;
      default:
        c = Colors.blueGrey; label = 'No payroll yet';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final status = '${r['attendance_status']}';
    final payroll = r['payroll'] is Map ? r['payroll'] as Map : const {'state': 'None'};
    final lockedMonth = payroll['state'] == 'Paid' || payroll['state'] == 'Finalized';
    final isLeave = ['Sick', 'Vacation', 'Holiday'].contains(status);
    final paid = '${r['is_paid']}' == '1';
    final mgmt = '${r['is_management_paid_absence']}' == '1';
    String detail;
    if (status == 'Present') {
      final inT = '${r['check_in_time'] ?? ''}';
      final outT = '${r['check_out_time'] ?? ''}';
      detail = '${inT.length >= 16 ? inT.substring(11, 16) : '-'} → ${outT.length >= 16 ? outT.substring(11, 16) : '-'} · '
          '${r['regular_hours']} h${(num.tryParse('${r['overtime_hours']}') ?? 0) > 0 ? ' + ${r['overtime_hours']} OT' : ''}';
    } else if (status == 'Absent') {
      detail = mgmt ? 'Absent · paid by management' : 'Absent · unpaid';
    } else {
      detail = '$status · ${paid ? 'paid' : 'unpaid'}';
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${r['record_date']} · $detail', style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
              ]),
            ),
            _payrollChip(payroll),
          ]),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
            if (isLeave && !lockedMonth)
              TextButton.icon(
                onPressed: () => _markPaid(r, !paid),
                icon: Icon(paid ? Icons.money_off : Icons.attach_money, size: 18),
                label: Text(paid ? 'Mark unpaid' : 'Mark paid'),
              ),
            OutlinedButton.icon(
              onPressed: () => _correct(r),
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(lockedMonth ? 'Correct (payroll ${payroll['state'] == 'Paid' ? 'paid' : 'finalized'})' : 'Correct'),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- dialog
class _StaffCorrectionDialog extends StatefulWidget {
  final Map<String, dynamic> record;
  const _StaffCorrectionDialog({required this.record});

  @override
  State<_StaffCorrectionDialog> createState() => _StaffCorrectionDialogState();
}

class _StaffCorrectionDialogState extends State<_StaffCorrectionDialog> {
  static const _statuses = ['Present', 'Absent', 'Sick', 'Vacation', 'Holiday'];
  late String _status;
  late final TextEditingController _in;
  late final TextEditingController _out;
  final _reason = TextEditingController();
  bool _completeDay = false;
  late bool _isPaid;
  late bool _mgmtPaid;
  String? _err;
  final _dt = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$');

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _status = _statuses.contains(r['attendance_status']) ? '${r['attendance_status']}' : 'Present';
    final date = '${r['record_date']}';
    _in = TextEditingController(text: r['check_in_time'] != null ? '${r['check_in_time']}' : '$date 08:00');
    _out = TextEditingController(text: r['check_out_time'] != null ? '${r['check_out_time']}' : '$date 16:00');
    _isPaid = '${r['is_paid']}' == '1';
    _mgmtPaid = '${r['is_management_paid_absence']}' == '1';
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_reason.text.trim().length < 5) { setState(() => _err = 'Enter a reason (min. 5 characters).'); return; }
    if (_status == 'Present' && (!_dt.hasMatch(_in.text.trim()) || !_dt.hasMatch(_out.text.trim()))) {
      setState(() => _err = 'Times must look like 2026-08-03 08:00');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'reason': _reason.text.trim(),
      'attendance_status': _status,
      if (_status == 'Present') 'check_in_time': '${_in.text.trim()}:00',
      if (_status == 'Present') 'check_out_time': '${_out.text.trim()}:00',
      if (_status == 'Present' && _completeDay) 'complete_day': true,
      if (['Sick', 'Vacation', 'Holiday'].contains(_status)) 'is_paid': _isPaid ? 1 : 0,
      if (_status == 'Absent') 'is_management_paid_absence': _mgmtPaid ? 1 : 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final payroll = r['payroll'] is Map ? r['payroll'] as Map : const {};
    String? note;
    if (payroll['state'] == 'Paid') {
      note = 'This month is PAID (batch #${payroll['batch_id']}). The paid batch will not change: the pay difference is computed automatically and added to the next payroll batch.';
    } else if (payroll['state'] == 'Finalized') {
      note = 'This month is FINALIZED (batch #${payroll['batch_id']}). After saving, supersede that batch to include the correction.';
    } else if (payroll['state'] == 'Generated') {
      note = 'Batch #${payroll['batch_id']} covers this date (not finalized). After saving, void it and generate the month again.';
    }
    return AlertDialog(
      title: Text('Correct — ${r['full_name']}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${r['record_date']}', style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w700)),
            if (note != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(note, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 12),
            if (_status == 'Present') ...[
              TextField(controller: _in, decoration: const InputDecoration(labelText: 'Check-in (YYYY-MM-DD HH:MM)', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: _out, decoration: const InputDecoration(labelText: 'Check-out (YYYY-MM-DD HH:MM)', border: OutlineInputBorder(), isDense: true)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _completeDay,
                onChanged: (v) => setState(() => _completeDay = v ?? false),
                title: const Text('Complete the day (management decision)'),
                subtitle: const Text('Pay the missing hours up to the standard day. The real times are kept.'),
              ),
            ],
            if (['Sick', 'Vacation', 'Holiday'].contains(_status))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPaid,
                onChanged: (v) => setState(() => _isPaid = v),
                title: Text('Paid $_status'),
              ),
            if (_status == 'Absent')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _mgmtPaid,
                onChanged: (v) => setState(() => _mgmtPaid = v),
                title: const Text('Paid by management'),
                subtitle: const Text('The absent day is paid as a full day.'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
            ),
            if (_err != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_err!, style: TextStyle(color: Colors.red.shade700)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save correction')),
      ],
    );
  }
}
