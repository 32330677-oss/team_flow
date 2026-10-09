// lib/screens/staff_delete_flow.dart
//
// Safe delete of a staff member (recycle bin, 30-day undo).
//
// The server decides everything (GET /staff/:id/deletion-check). This dialog
// only shows what it says and offers the next step:
//   * VOID_REQUIRED        -> "Void batch #N" (reason)            -> re-check
//   * SUPERSEDE_REQUIRED   -> "Put on hold" then "Supersede #N"   -> re-check
//   * PAID_PAYROLL / BIOMETRIC_DATA / UNHANDLED_DEPENDENCY -> explained, no delete
//   * nothing blocking     -> reason + type the full name -> Delete
//
// Returns true when the staff member was moved to the recycle bin.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants.dart';

const Color _kPrimary = Color(0xFF1A2A6C);
const Color _kDanger = Color(0xFFC62828);

Future<bool> showStaffDeleteFlow(BuildContext context, Map<String, dynamic> staff) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StaffDeleteDialog(staff: staff),
  );
  return result == true;
}

String _errorMessage(Object e, String fallback) {
  if (e is DioException && e.response?.data is Map) {
    final data = e.response!.data as Map;
    return (data['message'] ?? fallback).toString();
  }
  return fallback;
}

class _StaffDeleteDialog extends StatefulWidget {
  final Map<String, dynamic> staff;
  const _StaffDeleteDialog({required this.staff});

  @override
  State<_StaffDeleteDialog> createState() => _StaffDeleteDialogState();
}

class _StaffDeleteDialogState extends State<_StaffDeleteDialog> {
  Map<String, dynamic>? _check;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _reason = TextEditingController();
  final _confirmName = TextEditingController();

  int get _staffId => int.parse(widget.staff['staff_id'].toString());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _confirmName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiConfig.dio.get('/staff/$_staffId/deletion-check');
      setState(() => _check = Map<String, dynamic>.from(res.data['data']));
    } catch (e) {
      setState(() => _error = _errorMessage(e, 'Could not check this staff member.'));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _askReason(String title, String message, String confirm) async {
    final controller = TextEditingController();
    String? err;
    final reason = await showDialog<String>(
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
                controller: controller,
                maxLines: 2,
                decoration: InputDecoration(labelText: 'Reason (min. 5 characters)', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().length < 5) { setD(() => err = 'Please enter a clear reason'); return; }
                Navigator.pop(ctx, controller.text.trim());
              },
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _run(Future<Response> Function() call, String okMessage) async {
    setState(() { _busy = true; _error = null; });
    try {
      await call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMessage), behavior: SnackBarBehavior.floating));
      }
      await _load();
    } catch (e) {
      setState(() => _error = _errorMessage(e, 'The action failed.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _voidBatch(int batchId) async {
    final reason = await _askReason('Void batch #$batchId',
        'The batch stays in the history as Voided. After the delete, generate this period again from Staff Payroll.', 'Void');
    if (reason == null) return;
    await _run(() => ApiConfig.dio.patch('/staff-payroll/batch/$batchId/void', data: {'reason': reason}), 'Batch #$batchId voided');
  }

  Future<void> _hold() async {
    final reason = await _askReason('Put on hold',
        'This staff member will be left out of any NEW payroll (generate, supersede, preview). You can release the hold at any time.', 'Put on hold');
    if (reason == null) return;
    await _run(() => ApiConfig.dio.post('/staff/$_staffId/deletion-hold', data: {'reason': reason}), 'On hold');
  }

  Future<void> _releaseHold() async {
    final reason = await _askReason('Release hold', 'The staff member will be included in payroll again.', 'Release');
    if (reason == null) return;
    await _run(() => ApiConfig.dio.delete('/staff/$_staffId/deletion-hold', data: {'reason': reason}), 'Hold released');
  }

  Future<void> _supersede(int batchId) async {
    final reason = await _askReason('Correct (supersede) batch #$batchId',
        'A new version of this period is generated without this staff member. Batch #$batchId is kept as Superseded. '
            'The new version must be finalized again.', 'Supersede');
    if (reason == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ApiConfig.dio.post('/staff-payroll/batch/$batchId/new-version', data: {'reason': reason});
      await _load();
    } on DioException catch (e) {
      final data = e.response?.data is Map ? e.response!.data as Map : const {};
      if (data['code'] == 'PENDING_ATTENDANCE' && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unreviewed attendance in this period'),
            content: Text('${data['message'] ?? 'Some attendance in this period is not approved yet.'}\n\nContinue anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
            ],
          ),
        );
        if (go == true) {
          try {
            await ApiConfig.dio.post('/staff-payroll/batch/$batchId/new-version', data: {'reason': reason, 'acknowledge_pending': true});
            await _load();
          } catch (e2) {
            setState(() => _error = _errorMessage(e2, 'Supersede failed.'));
          }
        }
      } else {
        setState(() => _error = _errorMessage(e, 'Supersede failed.'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final name = (_check?['name'] ?? '').toString();
    if (_reason.text.trim().length < 5) { setState(() => _error = 'Enter a reason (at least 5 characters).'); return; }
    if (_confirmName.text.trim() != name.trim()) { setState(() => _error = 'Type the full name exactly as shown to confirm.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await ApiConfig.dio.delete('/staff/$_staffId', data: {'reason': _reason.text.trim(), 'confirm_name': _confirmName.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res.data['message'] ?? 'Moved to the recycle bin.').toString()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() { _error = _errorMessage(e, 'Delete failed.'); _busy = false; });
      await _load();
    }
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final name = (_check?['name'] ?? widget.staff['full_name'] ?? '').toString();
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: const BoxDecoration(
          color: _kDanger,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Row(children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text('Delete $name', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
          IconButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ]),
      ),
      content: SizedBox(
        width: 540,
        child: _loading && _check == null
            ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(child: _body()),
      ),
      actions: _actions(),
    );
  }

  Widget _body() {
    final c = _check;
    final children = <Widget>[];
    if (_error != null) {
      children.add(_banner(_error!, Colors.red.shade50, Colors.red.shade800, Icons.error_outline));
    }
    if (c == null) return Column(children: children);

    final blockers = (c['blockers'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final hold = c['hold'];
    final days = c['retention_days'] ?? 30;

    if (hold != null) {
      children.add(_banner('On hold since ${hold['created_at']}: excluded from new payroll. Reason: ${hold['reason']}',
          Colors.amber.shade50, Colors.brown.shade800, Icons.pause_circle_outline,
          trailing: TextButton(onPressed: _busy ? null : _releaseHold, child: const Text('Release'))));
    }

    if (blockers.isEmpty) {
      children.add(_banner(
          'Everything about this person (attendance, payroll lines, assignments, history) moves to the Recycle Bin. '
          'It disappears from every screen and report, and can be restored for $days days. After that it is deleted for good.',
          Colors.blue.shade50, _kPrimary, Icons.info_outline));
      children.add(const SizedBox(height: 8));
      children.add(_counts(Map<String, dynamic>.from(c['row_counts'] ?? {})));
      children.add(const SizedBox(height: 14));
      children.add(TextField(
        controller: _reason,
        enabled: !_busy,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
      ));
      children.add(const SizedBox(height: 12));
      children.add(Text.rich(TextSpan(children: [
        const TextSpan(text: 'To confirm, type the full name: '),
        TextSpan(text: (c['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
      ])));
      children.add(const SizedBox(height: 6));
      children.add(TextField(
        controller: _confirmName,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
      ));
    } else {
      children.add(const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Before this person can be deleted:', style: TextStyle(fontWeight: FontWeight.w700)),
      ));
      for (final b in blockers) {
        children.add(_blockerTile(b));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _blockerTile(Map<String, dynamic> b) {
    final code = b['code']?.toString() ?? '';
    final batchId = b['batch_id'] is int ? b['batch_id'] as int : int.tryParse('${b['batch_id']}');
    final hard = code == 'PAID_PAYROLL' || code == 'BIOMETRIC_DATA' || code == 'UNHANDLED_DEPENDENCY';
    Widget? action;
    if (b['action'] == 'void' && batchId != null) {
      action = OutlinedButton(onPressed: _busy ? null : () => _voidBatch(batchId), child: Text('Void #$batchId'));
    } else if (b['action'] == 'hold') {
      action = OutlinedButton(onPressed: _busy ? null : _hold, child: const Text('Put on hold'));
    } else if (b['action'] == 'supersede' && batchId != null) {
      action = OutlinedButton(onPressed: _busy ? null : () => _supersede(batchId), child: Text('Supersede #$batchId'));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hard ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hard ? Colors.red.shade200 : Colors.orange.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(hard ? Icons.block : Icons.pending_actions, color: hard ? _kDanger : Colors.orange.shade800, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text((b['message'] ?? code).toString(), style: const TextStyle(fontSize: 13.5))),
        if (action != null) ...[const SizedBox(width: 8), action],
      ]),
    );
  }

  Widget _counts(Map<String, dynamic> counts) {
    const labels = {
      'staff_attendance': 'Attendance days',
      'staff_payroll': 'Payroll lines (voided / superseded batches)',
      'staff_monthly_overtime_ledger': 'Overtime ledger months',
      'staff_overtime_compensations': 'Overtime compensations',
      'attendance_corrections_log': 'Attendance corrections',
      'staff_site_assignments': 'Site assignments',
      'staff_supervisor_assignments': 'Supervisor assignments',
      'staff_compensation_history': 'Salary history',
      'staff_status_history': 'Status history',
    };
    final rows = labels.entries.where((e) => (counts[e.key] ?? 0) is num && (counts[e.key] ?? 0) > 0).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final e in rows) Chip(label: Text('${e.value}: ${counts[e.key]}'), visualDensity: VisualDensity.compact)],
    );
  }

  Widget _banner(String text, Color bg, Color fg, IconData icon, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13.5))),
          if (trailing != null) trailing,
        ]),
      );

  List<Widget> _actions() {
    final c = _check;
    final canDelete = c != null && c['can_delete'] == true;
    final nameOk = c != null && _confirmName.text.trim() == (c['name'] ?? '').toString().trim();
    return [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Close')),
      if (canDelete)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _kDanger, foregroundColor: Colors.white),
          onPressed: _busy || !nameOk ? null : _delete,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_outline),
          label: const Text('Move to Recycle Bin'),
        ),
    ];
  }
}
