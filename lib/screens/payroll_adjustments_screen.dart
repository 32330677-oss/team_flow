// lib/screens/payroll_adjustments_screen.dart
//
// Payroll adjustments (retro pay) for workers and staff.
//   * Differences on PAID periods (from attendance corrections) are listed
//     here with their status: Awaiting confirmation (deductions) -> Pending ->
//     Included in batch #N -> Applied (paid) / Cancelled.
//   * "+ Manual adjustment": an amount decided by management, with a reason.
//   * "Open corrections": corrections on paid periods that have no amount yet
//     (made before this feature, or the amount could not be computed).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

const Color _kPrimary = Color(0xFF1A2A6C);

class PayrollAdjustmentsScreen extends StatefulWidget {
  final String? initialType; // 'Worker' | 'Staff' | null (all)
  const PayrollAdjustmentsScreen({super.key, this.initialType});

  @override
  State<PayrollAdjustmentsScreen> createState() => _PayrollAdjustmentsScreenState();
}

class _PayrollAdjustmentsScreenState extends State<PayrollAdjustmentsScreen> {
  static const _statusFilters = <String?, String>{
    null: 'All',
    'AwaitingConfirmation': 'To confirm',
    'Pending': 'Pending',
    'Included': 'In a batch',
    'Applied': 'Paid',
    'Cancelled': 'Cancelled',
  };
  String? _type;
  String? _status;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _openCorrections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _load();
  }

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiConfig.dio.get('/payroll-adjustments', queryParameters: {
        if (_type != null) 'person_type': _type,
        if (_status != null) 'status': _status,
      });
      _items = (res.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      final oc = await ApiConfig.dio.get('/payroll-adjustments/open-corrections');
      _openCorrections = (oc.data['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .where((c) => _type == null || (_type == 'Worker') == (c['record_table'] == 'attendance'))
          .toList();
    } catch (e) {
      _snack(_err(e, 'Failed to load payroll adjustments'), ok: false);
    }
    if (mounted) setState(() => _loading = false);
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
            width: 420,
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
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

  Future<void> _confirm(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm deduction'),
        content: Text('${a['full_name']}: ${a['amount']} ${a['currency']} will be deducted from the next payroll batch.\n\n${a['reason'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiConfig.dio.patch('/payroll-adjustments/${a['adjustment_id']}/confirm');
      _snack('${r.data['message'] ?? 'Confirmed'}');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed'), ok: false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> a) async {
    final reason = await _askReason('Cancel adjustment', '${a['full_name']}: ${a['amount']} ${a['currency']}. It will not be paid or deducted.');
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.patch('/payroll-adjustments/${a['adjustment_id']}/cancel', data: {'reason': reason});
      _snack('${r.data['message'] ?? 'Cancelled'}');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed'), ok: false);
    }
  }

  Future<void> _compute(Map<String, dynamic> c) async {
    try {
      final r = await ApiConfig.dio.post('/payroll-adjustments/open-corrections/${c['correction_id']}/compute');
      _snack('${r.data['message'] ?? 'Done'}');
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed to compute'), ok: false);
    }
  }

  Future<void> _addManual() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ManualAdjustmentDialog(initialType: _type ?? 'Worker'),
    );
    if (created == true) {
      _snack('Adjustment recorded');
      _load();
    }
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Payroll Adjustments',
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addManual,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Manual adjustment'),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(value: 'Worker', label: Text('Workers')),
                ButtonSegment(value: 'Staff', label: Text('Staff')),
              ],
              selected: {_type},
              onSelectionChanged: (s) { setState(() => _type = s.first); _load(); },
            ),
            for (final e in _statusFilters.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _status == e.key,
                onSelected: (_) { setState(() => _status = e.key); _load(); },
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      if (_openCorrections.isNotEmpty) ...[
                        _sectionTitle('Corrections without an amount (${_openCorrections.length})',
                            'Corrections on finalized / paid periods that have no payroll adjustment yet.'),
                        for (final c in _openCorrections) _openCorrectionTile(c),
                        const SizedBox(height: 12),
                      ],
                      _sectionTitle('Adjustments (${_items.length})',
                          'Added to (or deducted from) the next payroll batch of each person. Paid batches are never changed.'),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text('No adjustments', style: TextStyle(color: Colors.grey.shade600))),
                        ),
                      for (final a in _items) _tile(a),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _kPrimary)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      );

  Widget _statusChip(String status, dynamic batchId) {
    final map = <String, (Color, String)>{
      'AwaitingConfirmation': (Colors.orange.shade800, 'To confirm'),
      'Pending': (Colors.blue.shade700, 'Pending · next batch'),
      'Included': (Colors.indigo, 'In batch #$batchId'),
      'Applied': (Colors.green.shade700, 'Paid · batch #$batchId'),
      'Cancelled': (Colors.grey.shade600, 'Cancelled'),
    };
    final (color, label) = map[status] ?? (Colors.grey, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11.5)),
    );
  }

  Widget _tile(Map<String, dynamic> a) {
    final amount = num.tryParse('${a['amount']}') ?? 0;
    final status = '${a['status']}';
    final origin = a['source'] == 'Correction'
        ? 'Correction of ${a['origin_date']} (paid batch #${a['origin_batch_id']}): ${a['before_amount']} → ${a['after_amount']}'
        : 'Manual';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['full_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${a['person_type']} · ${a['person_code'] ?? ''} · #${a['adjustment_id']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${amount > 0 ? '+' : ''}${amount.toStringAsFixed(2)} ${a['currency']}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: amount >= 0 ? Colors.green.shade800 : Colors.red.shade700)),
              const SizedBox(height: 4),
              _statusChip(status, a['included_batch_id']),
            ]),
          ]),
          const SizedBox(height: 6),
          Text(origin, style: const TextStyle(fontSize: 12.5)),
          Text('Reason: ${a['reason'] ?? ''}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
          Text('By ${a['created_by'] ?? '-'} · ${a['created_at'] ?? ''}'
              '${status == 'Cancelled' ? ' · cancelled by ${a['cancelled_by'] ?? '-'}: ${a['cancel_reason'] ?? ''}' : ''}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          if (status == 'AwaitingConfirmation' || status == 'Pending')
            Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
              TextButton(onPressed: () => _cancel(a), child: const Text('Cancel', style: TextStyle(color: Colors.red))),
              if (status == 'AwaitingConfirmation')
                FilledButton(onPressed: () => _confirm(a), child: const Text('Confirm deduction')),
            ]),
        ]),
      ),
    );
  }

  Widget _openCorrectionTile(Map<String, dynamic> c) {
    final paid = c['batch_status'] == 'Paid';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.amber.shade200)),
      child: ListTile(
        title: Text('${c['full_name'] ?? '-'} · ${c['record_date']}'),
        subtitle: Text('${c['record_table'] == 'attendance' ? 'Worker' : 'Staff'} · batch #${c['locked_batch_id']} (${c['batch_status']})\n${c['reason'] ?? ''}'),
        isThreeLine: true,
        trailing: paid
            ? FilledButton(onPressed: () => _compute(c), child: const Text('Compute'))
            : const Tooltip(
                message: 'The batch is finalized but not paid: supersede it, or mark it paid to create the adjustment.',
                child: Icon(Icons.info_outline),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- manual
class _ManualAdjustmentDialog extends StatefulWidget {
  final String initialType;
  const _ManualAdjustmentDialog({required this.initialType});

  @override
  State<_ManualAdjustmentDialog> createState() => _ManualAdjustmentDialogState();
}

class _ManualAdjustmentDialogState extends State<_ManualAdjustmentDialog> {
  late String _type;
  List<Map<String, dynamic>> _people = [];
  int? _personId;
  bool _deduction = false;
  bool _busy = false;
  bool _loadingPeople = true;
  String? _err;
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _loadPeople();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    setState(() { _loadingPeople = true; _personId = null; });
    try {
      final r = await ApiConfig.dio.get(_type == 'Worker' ? '/workers' : '/staff');
      final list = (r.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      list.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
      _people = list;
    } catch (_) {
      _people = [];
    }
    if (mounted) setState(() => _loadingPeople = false);
  }

  Future<void> _submit() async {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_personId == null) { setState(() => _err = 'Choose a person.'); return; }
    if (value == null || value <= 0) { setState(() => _err = 'Enter a positive amount.'); return; }
    if (_reason.text.trim().length < 5) { setState(() => _err = 'Enter a reason (min. 5 characters).'); return; }
    setState(() { _busy = true; _err = null; });
    try {
      await ApiConfig.dio.post('/payroll-adjustments', data: {
        'person_type': _type,
        'person_id': _personId,
        'amount': _deduction ? -value : value,
        'reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _err = e is DioException && e.response?.data is Map ? '${(e.response!.data as Map)['message']}' : 'Failed to save.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final idKey = _type == 'Worker' ? 'worker_id' : 'staff_id';
    final codeKey = _type == 'Worker' ? 'worker_unique_id' : 'staff_unique_id';
    return AlertDialog(
      title: const Text('Manual payroll adjustment'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Worker', label: Text('Worker')),
                ButtonSegment(value: 'Staff', label: Text('Staff')),
              ],
              selected: {_type},
              onSelectionChanged: _busy ? null : (s) { setState(() => _type = s.first); _loadPeople(); },
            ),
            const SizedBox(height: 12),
            _loadingPeople
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int>(
                    value: _personId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Person', border: OutlineInputBorder(), isDense: true),
                    items: [
                      for (final p in _people)
                        DropdownMenuItem<int>(
                          value: int.tryParse('${p[idKey]}'),
                          child: Text('${p['full_name']} (${p[codeKey] ?? ''})', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _personId = v),
                  ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Pay more'), icon: Icon(Icons.add)),
                ButtonSegment(value: true, label: Text('Deduct'), icon: Icon(Icons.remove)),
              ],
              selected: {_deduction},
              onSelectionChanged: (s) => setState(() => _deduction = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${_type == 'Worker' ? 'SYP' : 'USD'})',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
            ),
            if (_deduction)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('A deduction must be confirmed in the list before it is taken from the next payroll.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!, style: TextStyle(color: Colors.red.shade700)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Save')),
      ],
    );
  }
}
