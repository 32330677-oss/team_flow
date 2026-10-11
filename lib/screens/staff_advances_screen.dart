// lib/screens/staff_advances_screen.dart
//
// Staff salary advances (Admin only). Shown under Staff Payroll -> "Advances"
// so advances never mix with the regular payroll batches.
//
// Flow: pick staff -> financial report (required) -> amount + deduction month(s)
// -> voucher (unique number ADV-YYYY-NNNNNN, print and have it signed).
// Within 72 hours an advance can be cancelled: everything goes back to how it was.
// After that it can only be closed by a payroll deduction, a cash repayment or a
// write-off.

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../widgets/searchable_picker_sheet.dart';
import 'payroll_export_service.dart';

const Color _primary = Color(0xFF1A2A6C);

String _money(dynamic v) {
  final n = (v is num) ? v : (num.tryParse('$v') ?? 0);
  return NumberFormat('#,##0.00').format(n);
}

num _num(dynamic v) => (v is num) ? v : (num.tryParse('$v') ?? 0);

String _errorMessage(Object e, String fallback) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
  }
  return fallback;
}

void _snack(BuildContext context, String message, {Color? color}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
  );
}

Future<void> _downloadPdf(BuildContext context, String path, String fileName) async {
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty file');
    await PayrollExportService.exportBytes(bytes, fileName);
  } catch (e) {
    if (context.mounted) _snack(context, _errorMessage(e, 'Failed to download $fileName.'), color: Colors.red);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      'Active' => (Colors.orange.shade800, 'Active'),
      'Settled' => (Colors.green.shade700, 'Settled'),
      'Cancelled' => (Colors.grey.shade700, 'Cancelled'),
      'WrittenOff' => (Colors.red.shade700, 'Written off'),
      'Scheduled' => (Colors.blue.shade700, 'Scheduled'),
      'Included' => (Colors.indigo, 'In batch'),
      'Deducted' => (Colors.green.shade700, 'Deducted'),
      'Unscheduled' => (Colors.red.shade700, 'Needs a month'),
      'Repaid' => (Colors.teal, 'Repaid (cash)'),
      _ => (Colors.grey, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

// ===========================================================================
// List (embedded in Staff Payroll)
// ===========================================================================
class StaffAdvancesPanel extends StatefulWidget {
  const StaffAdvancesPanel({super.key});

  @override
  State<StaffAdvancesPanel> createState() => _StaffAdvancesPanelState();
}

class _StaffAdvancesPanelState extends State<StaffAdvancesPanel> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _openBalance = {};
  String _status = 'Active';
  String? _month;
  final TextEditingController _search = TextEditingController();

  List<String> get _monthOptions {
    final now = DateTime.now();
    return List.generate(15, (i) {
      final d = DateTime(now.year, now.month - 2 + i, 1);
      return DateFormat('yyyy-MM').format(d);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiConfig.dio.get('/staff-advances', queryParameters: {
        if (_status != 'All') 'status': _status,
        if (_month != null) 'month': _month,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _rows = (r.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _openBalance = Map<String, dynamic>.from(r.data['open_balance_by_currency'] ?? {});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, _errorMessage(e, 'Failed to load advances.'), color: Colors.red);
    }
  }

  Future<void> _newAdvance() async {
    final created = await startNewStaffAdvance(context);
    if (created == true) _load();
  }

  Future<void> _open(Map<String, dynamic> a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StaffAdvanceDetailsScreen(advanceId: a['advance_id'] as int)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined, color: _primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Salary Advances', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _primary)),
                    const SizedBox(height: 2),
                    Text(
                      _openBalance.isEmpty
                          ? 'No open balance'
                          : 'Open balance: ${_openBalance.entries.map((e) => '${_money(e.value)} ${e.key}').join(' · ')}',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ]),
                ),
                FilledButton.icon(
                  onPressed: _newAdvance,
                  style: FilledButton.styleFrom(backgroundColor: _primary),
                  icon: const Icon(Icons.add),
                  label: const Text('New advance'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in const ['Active', 'Settled', 'Cancelled', 'WrittenOff', 'All'])
              ChoiceChip(
                label: Text(s == 'WrittenOff' ? 'Written off' : s),
                selected: _status == s,
                onSelected: (_) {
                  setState(() => _status = s);
                  _load();
                },
              ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                value: _month,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Deduction month', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Any month')),
                  for (final m in _monthOptions)
                    DropdownMenuItem<String?>(value: m, child: Text(DateFormat('MMMM yyyy').format(DateTime.parse('$m-01')))),
                ],
                onChanged: (v) {
                  setState(() => _month = v);
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Search name, ID or voucher',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _load),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No advances')))
          else
            ..._rows.map(_tile),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> a) {
    final installments = (a['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final unscheduled = installments.where((i) => i['status'] == 'Unscheduled').toList();
    final next = installments.firstWhere((i) => i['status'] == 'Scheduled' || i['status'] == 'Included', orElse: () => {});
    final canCancel = a['can_cancel_window'] == true;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(a),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${a['staff_unique_id']} · ${a['voucher_no']} · ${a['created_at']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_money(a['amount'])} ${a['currency']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                _StatusChip('${a['status']}'),
              ]),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 4, children: [
              Text('Balance: ${_money(a['outstanding_balance'])} ${a['currency']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(a['deduction_mode'] == 'Full' ? 'Full deduction' : 'Partial (${installments.length} parts)', style: const TextStyle(fontSize: 12.5)),
              if (next.isNotEmpty)
                Text('Next: ${next['month_label'] ?? '-'} · ${_money(next['amount'])}', style: const TextStyle(fontSize: 12.5)),
              if (canCancel)
                Text('Can be cancelled for ${_countdown(_num(a['cancel_seconds_left']).toInt())}',
                    style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800)),
            ]),
            if (unscheduled.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('${_money(unscheduled.fold<num>(0, (s, i) => s + _num(i['amount'])))} ${a['currency']} needs a new deduction month.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
              ),
          ]),
        ),
      ),
    );
  }
}

String _countdown(int seconds) {
  if (seconds <= 0) return '0m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

// ===========================================================================
// New advance: staff -> financial report -> form
// ===========================================================================
Future<bool?> startNewStaffAdvance(BuildContext context) async {
  List<Map<String, dynamic>> staff;
  try {
    final r = await ApiConfig.dio.get('/staff');
    staff = (r.data['data'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => s['status'] == 'Active')
        .toList()
      ..sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
  } catch (e) {
    if (context.mounted) _snack(context, _errorMessage(e, 'Failed to load staff.'), color: Colors.red);
    return false;
  }
  if (!context.mounted) return false;
  final picked = await SearchablePickerSheet.show<Map<String, dynamic>>(
    context,
    title: 'Advance for which staff member?',
    items: staff,
    labelBuilder: (s) => '${s['full_name']}',
    subtitleBuilder: (s) => '${s['staff_unique_id'] ?? ''} · ${s['position'] ?? ''}',
  );
  if (picked == null || !context.mounted) return false;
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => StaffFinancialReportScreen(staffId: picked['staff_id'] as int)),
  );
}

class StaffFinancialReportScreen extends StatefulWidget {
  final int staffId;
  const StaffFinancialReportScreen({super.key, required this.staffId});

  @override
  State<StaffFinancialReportScreen> createState() => _StaffFinancialReportScreenState();
}

class _StaffFinancialReportScreenState extends State<StaffFinancialReportScreen> {
  Map<String, dynamic>? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final r = await ApiConfig.dio.post('/staff-advances/financial-report', data: {'staff_id': widget.staffId});
      if (mounted) setState(() => _report = Map<String, dynamic>.from(r.data['data']));
    } catch (e) {
      if (mounted) setState(() => _error = _errorMessage(e, 'Failed to build the financial report.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Financial report'),
        actions: [
          if (r != null)
            IconButton(
              tooltip: 'Export PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _downloadPdf(context, '/staff-advances/financial-report/${r['report_id']}.pdf',
                  'financial_report_${r['staff']['staff_unique_id']}_${r['report_id']}.pdf'),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : _body(r),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: r['can_create'] == true
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue to advance'),
                        onPressed: () async {
                          final created = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => NewStaffAdvanceScreen(report: r)),
                          );
                          if (created == true && mounted) Navigator.pop(context, true);
                        },
                      )
                    : Text((r['blockers'] as List? ?? []).join('\n'),
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: _primary)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _kv(String k, String v, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color, fontSize: 13)),
        ]),
      );

  Widget _body(Map<String, dynamic> r) {
    final cur = '${r['currency']}';
    final s = Map<String, dynamic>.from(r['staff']);
    final m = Map<String, dynamic>.from(r['current_month']);
    final pending = Map<String, dynamic>.from(r['attendance_pending']);
    final history = (r['payroll_history'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final open = Map<String, dynamic>.from(r['open_advances']);
    final adv = (r['advance_history'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final adj = Map<String, dynamic>.from(r['pending_adjustments']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('${s['full_name']} · ${s['staff_unique_id']}', [
        _kv('Position / site', '${s['position'] ?? '-'} · ${s['site_name'] ?? '-'}'),
        _kv('Status', '${s['status']}'),
        _kv('Hire date', '${s['hire_date'] ?? '-'}'),
        _kv('Monthly salary', '${_money(s['monthly_salary'])} $cur', bold: true),
        _kv('Report', '#${r['report_id']} · valid until ${r['valid_until']}'),
      ]),
      _section('Expected salary · ${m['label']} (to ${m['to']})', [
        if (m['available'] == true) ...[
          _kv('Prorated base', '${_money(m['prorated_base_salary'])} $cur'),
          _kv('Deduction (absence / shortage)', '${_money(m['salary_deduction'])} $cur', color: Colors.red.shade700),
          _kv('Expected net to date', '${_money(m['net_salary'])} $cur', bold: true, color: Colors.green.shade800),
          _kv('Present · paid leave · unpaid absence', '${m['present_days']} · ${m['paid_leave_days']} · ${m['unpaid_absence_days']}'),
          _kv('Shortage hours', '${m['shortage_hours']}'),
        ] else
          Text('${m['note'] ?? 'Not available.'}', style: TextStyle(color: Colors.grey.shade700)),
        _kv('Draft / submitted / rejected days', '${pending['draft']} / ${pending['submitted']} / ${pending['rejected']}'),
      ]),
      _section('Open advances · balance ${_money(open['balance'])} $cur', [
        if (adv.isEmpty) Text('No advances.', style: TextStyle(color: Colors.grey.shade700)),
        for (final a in adv)
          _kv('${a['voucher_no']} · ${a['created_at']}', '${_money(a['outstanding_balance'])} / ${_money(a['amount'])} · ${a['status']}'),
        if ((adj['items'] as List? ?? []).isNotEmpty)
          _kv('Pending payroll adjustments', '${_money(adj['total'])} $cur', color: _num(adj['total']) < 0 ? Colors.red.shade700 : null),
      ]),
      _section('Payroll history (last 6)', [
        if (history.isEmpty) Text('No payroll yet.', style: TextStyle(color: Colors.grey.shade700)),
        for (final p in history)
          _kv('#${p['batch_id']} · ${p['start_date']} → ${p['end_date']} · ${p['status'] == 'Paid' ? 'Paid' : (p['is_finalized'] == true ? 'Finalized' : 'Generated')}',
              '${_money(p['net_salary'])} $cur${_num(p['advance_deduction_amount']) > 0 ? ' (advance −${_money(p['advance_deduction_amount'])})' : ''}'),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Create form
// ---------------------------------------------------------------------------
class _ScheduleRow {
  String? month;
  final TextEditingController amount = TextEditingController();
  _ScheduleRow({this.month});
}

class NewStaffAdvanceScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  const NewStaffAdvanceScreen({super.key, required this.report});

  @override
  State<NewStaffAdvanceScreen> createState() => _NewStaffAdvanceScreenState();
}

class _NewStaffAdvanceScreenState extends State<NewStaffAdvanceScreen> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'Cash';
  bool _partial = false;
  bool _saving = false;
  final List<_ScheduleRow> _rows = [];
  // One key per form: a double tap never creates two advances.
  final String _idempotencyKey =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  List<Map<String, dynamic>> get _months =>
      (widget.report['months'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  String get _cur => '${widget.report['currency']}';

  @override
  void initState() {
    super.initState();
    final first = _months.firstWhere((m) => m['selectable'] == true, orElse: () => {});
    _rows.add(_ScheduleRow(month: first['month'] as String?));
  }

  @override
  void dispose() {
    for (final c in [_amount, _reason, _reference]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  num get _total => num.tryParse(_amount.text.trim()) ?? 0;
  num get _scheduled => _partial ? _rows.fold<num>(0, (s, r) => s + (num.tryParse(r.amount.text.trim()) ?? 0)) : _total;

  Map<String, dynamic>? _monthState(String? m) =>
      m == null ? null : _months.firstWhere((x) => x['month'] == m, orElse: () => <String, dynamic>{});

  Future<void> _submit() async {
    final total = _total;
    if (total <= 0) return _snack(context, 'Enter the advance amount.', color: Colors.orange);
    if (_reason.text.trim().length < 5) return _snack(context, 'Enter a reason (at least 5 characters).', color: Colors.orange);
    final schedule = _partial
        ? _rows.map((r) => {'month': r.month, 'amount': num.tryParse(r.amount.text.trim()) ?? 0}).toList()
        : [
            {'month': _rows.first.month, 'amount': total}
          ];
    if (schedule.any((s) => s['month'] == null)) return _snack(context, 'Choose the deduction month.', color: Colors.orange);
    if ((_scheduled * 100).round() != (total * 100).round()) {
      return _snack(context, 'The monthly amounts must add up to ${_money(total)} $_cur.', color: Colors.orange);
    }
    final staff = widget.report['staff'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create advance?'),
        content: Text('${_money(total)} $_cur to ${staff['full_name']}.\n'
            '${schedule.map((s) => '• ${DateFormat('MMMM yyyy').format(DateTime.parse('${s['month']}-01'))}: ${_money(s['amount'])}').join('\n')}\n\n'
            'A voucher number is assigned now. You can cancel it within 72 hours.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final r = await ApiConfig.dio.post('/staff-advances', data: {
        'staff_id': staff['staff_id'],
        'amount': total,
        'schedule': schedule,
        'reason': _reason.text.trim(),
        'payment_method': _method,
        if (_reference.text.trim().isNotEmpty) 'payment_reference': _reference.text.trim(),
        'financial_report_id': widget.report['report_id'],
        'idempotency_key': _idempotencyKey,
      });
      if (!mounted) return;
      final a = Map<String, dynamic>.from(r.data['data']);
      final warnings = (r.data['warnings'] as List? ?? []).map((w) => '${w['message']}').toList();
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle, color: Colors.green.shade700, size: 40),
          title: Text(a['voucher_no']),
          content: Text('Advance created: ${_money(a['amount'])} $_cur.\nPrint the voucher and have it signed.'
              '${warnings.isEmpty ? '' : '\n\n${warnings.join('\n\n')}'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton.icon(
              icon: const Icon(Icons.print),
              label: const Text('Print voucher'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadPdf(context, '/staff-advances/${a['advance_id']}/voucher.pdf', '${a['voucher_no']}.pdf');
              },
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(context, _errorMessage(e, 'Failed to create the advance.'), color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _monthPicker(_ScheduleRow row, {String label = 'Deduction month'}) {
    final used = _rows.where((r) => r != row).map((r) => r.month).toSet();
    final st = _monthState(row.month);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        value: row.month,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        items: [
          for (final m in _months)
            DropdownMenuItem<String>(
              value: m['month'] as String,
              enabled: m['selectable'] == true && !used.contains(m['month']),
              child: Text(
                '${m['label']}${m['paid'] == true ? ' · Paid' : (m['warning'] != null ? ' · batch exists' : '')}',
                style: TextStyle(
                  color: (m['selectable'] == true && !used.contains(m['month'])) ? null : Colors.grey,
                ),
              ),
            ),
        ],
        onChanged: (v) => setState(() => row.month = v),
      ),
      if (st != null && st['warning'] != null && st['paid'] != true)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${st['warning']}', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.report['staff'];
    final remaining = _total - _scheduled;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('New advance · ${staff['full_name']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Advance amount ($_cur)', border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.event), label: Text('Full (one month)')),
                  ButtonSegment(value: true, icon: Icon(Icons.view_week_outlined), label: Text('Partial (several months)')),
                ],
                selected: {_partial},
                onSelectionChanged: (s) => setState(() {
                  _partial = s.first;
                  if (!_partial && _rows.length > 1) {
                    for (final r in _rows.skip(1)) {
                      r.amount.dispose();
                    }
                    _rows.removeRange(1, _rows.length);
                  }
                }),
              ),
              const SizedBox(height: 12),
              if (!_partial)
                _monthPicker(_rows.first)
              else ...[
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _monthPicker(_rows[i], label: 'Month ${i + 1}')),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i].amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: 'Amount', border: const OutlineInputBorder(), isDense: true, suffixText: _cur),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _rows.length <= 1
                            ? null
                            : () => setState(() {
                                  _rows[i].amount.dispose();
                                  _rows.removeAt(i);
                                }),
                      ),
                    ]),
                  ),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add month'),
                    onPressed: () => setState(() {
                      final used = _rows.map((r) => r.month).toSet();
                      final next = _months.firstWhere((m) => m['selectable'] == true && !used.contains(m['month']), orElse: () => {});
                      _rows.add(_ScheduleRow(month: next['month'] as String?));
                    }),
                  ),
                  const Spacer(),
                  Text(
                    remaining == 0 ? 'Fully scheduled' : 'Left to schedule: ${_money(remaining)} $_cur',
                    style: TextStyle(fontWeight: FontWeight.w600, color: remaining == 0 ? Colors.green.shade700 : Colors.red.shade700),
                  ),
                ]),
              ],
              const SizedBox(height: 4),
              Text('Months that already have a Paid staff batch cannot be chosen.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _method,
                decoration: const InputDecoration(labelText: 'Payment method', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'BankTransfer', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'Cash'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Payment reference (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder())),
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _primary, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.receipt_long),
            label: const Text('Create advance & voucher'),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Details: voucher, schedule, history, actions
// ===========================================================================
class StaffAdvanceDetailsScreen extends StatefulWidget {
  final int advanceId;
  const StaffAdvanceDetailsScreen({super.key, required this.advanceId});

  @override
  State<StaffAdvanceDetailsScreen> createState() => _StaffAdvanceDetailsScreenState();
}

class _StaffAdvanceDetailsScreenState extends State<StaffAdvanceDetailsScreen> {
  Map<String, dynamic>? _a;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiConfig.dio.get('/staff-advances/${widget.advanceId}');
      if (mounted) setState(() => _a = Map<String, dynamic>.from(r.data['data']));
    } catch (e) {
      if (mounted) _snack(context, _errorMessage(e, 'Failed to load the advance.'), color: Colors.red);
    }
  }

  Future<String?> _askReason(String title, String message, String action, {Color? color}) async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(controller: c, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    );
    c.dispose();
    return res;
  }

  Future<void> _run(Future<Response> Function() call, String fallback) async {
    setState(() => _busy = true);
    try {
      final r = await call();
      if (!mounted) return;
      _snack(context, '${r.data['message'] ?? 'Done.'}', color: Colors.green.shade700);
      await _load();
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Not possible'),
            content: Text(_errorMessage(e, fallback)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _askReason(
      'Cancel ${_a!['voucher_no']}?',
      'Everything goes back to how it was before this advance. A deduction already in a Generated (not finalized) '
          'staff batch is removed from that batch. The voucher number stays reserved and the record is kept as Cancelled.',
      'Cancel advance',
      color: Colors.red,
    );
    if (reason == null || reason.isEmpty) return;
    await _run(() => ApiConfig.dio.post('/staff-advances/${widget.advanceId}/cancel', data: {'reason': reason}), 'Failed to cancel.');
  }

  Future<void> _writeOff() async {
    final reason = await _askReason('Write off ${_a!['voucher_no']}?',
        'The open balance (${_money(_a!['outstanding_balance'])} ${_a!['currency']}) will not be recovered.', 'Write off',
        color: Colors.red);
    if (reason == null || reason.isEmpty) return;
    await _run(() => ApiConfig.dio.post('/staff-advances/${widget.advanceId}/write-off', data: {'reason': reason}), 'Failed to write off.');
  }

  Future<void> _repay() async {
    final amount = TextEditingController();
    final reason = TextEditingController(text: 'Cash repayment');
    String method = 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Record a repayment'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount (${_a!['currency']})', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(value: 'BankTransfer', child: Text('Bank transfer')),
                DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
              ],
              onChanged: (v) => setD(() => method = v ?? 'Cash'),
            ),
            const SizedBox(height: 10),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & receipt')),
          ],
        ),
      ),
    );
    final value = num.tryParse(amount.text.trim()) ?? 0;
    final note = reason.text.trim();
    amount.dispose();
    reason.dispose();
    if (ok != true || value <= 0) return;
    setState(() => _busy = true);
    try {
      final r = await ApiConfig.dio.post('/staff-advances/${widget.advanceId}/repay',
          data: {'amount': value, 'reason': note, 'payment_method': method});
      if (!mounted) return;
      _snack(context, '${r.data['message']}', color: Colors.green.shade700);
      await _load();
      if (mounted) {
        await _downloadPdf(context, '/staff-advances/${widget.advanceId}/repayments/${r.data['entry_id']}/receipt.pdf', '${r.data['receipt_no']}.pdf');
      }
    } catch (e) {
      if (mounted) _snack(context, _errorMessage(e, 'Failed to record the repayment.'), color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reschedule() async {
    final a = _a!;
    final editable = (a['installments'] as List).map((e) => Map<String, dynamic>.from(e))
        .where((i) => i['status'] == 'Scheduled' || i['status'] == 'Unscheduled').toList();
    final total = editable.fold<num>(0, (s, i) => s + _num(i['amount']));
    List<Map<String, dynamic>> months;
    try {
      final r = await ApiConfig.dio.get('/staff-advances/months');
      months = (r.data['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (mounted) _snack(context, _errorMessage(e, 'Failed to load months.'), color: Colors.red);
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _RescheduleScreen(advance: a, months: months, total: total, current: editable),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _uploadReceipt() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Signed voucher', extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf']),
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _run(
      () => ApiConfig.dio.post('/staff-advances/${widget.advanceId}/signed-receipt',
          data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: file.name)})),
      'Failed to upload.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) {
      return Scaffold(appBar: AppBar(title: const Text('Advance')), body: const Center(child: CircularProgressIndicator()));
    }
    final cur = '${a['currency']}';
    final active = a['status'] == 'Active';
    final canCancel = a['can_cancel_window'] == true;
    final installments = (a['installments'] as List).map((e) => Map<String, dynamic>.from(e))
        .where((i) => i['status'] != 'Replaced').toList();
    final ledger = (a['ledger'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    final hasEditable = installments.any((i) => i['status'] == 'Scheduled' || i['status'] == 'Unscheduled');
    final hasIncluded = installments.any((i) => i['status'] == 'Included');
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('${a['voucher_no']}')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['full_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${a['staff_unique_id']} · ${a['position'] ?? ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    ]),
                  ),
                  _StatusChip('${a['status']}'),
                ]),
                const Divider(height: 22),
                Row(children: [
                  Expanded(child: _stat('Amount', '${_money(a['amount'])} $cur')),
                  Expanded(child: _stat('Balance', '${_money(a['outstanding_balance'])} $cur', color: active ? Colors.orange.shade900 : Colors.green.shade800)),
                ]),
                const SizedBox(height: 8),
                Text('Created ${a['created_at']} by ${a['created_by']} · ${a['payment_method']}'
                    '${a['payment_reference'] != null ? ' (${a['payment_reference']})' : ''}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                Text('Reason: ${a['reason']}', style: const TextStyle(fontSize: 12.5)),
                if (a['status'] == 'Cancelled')
                  Text('Cancelled ${a['cancelled_at']} by ${a['cancelled_by'] ?? '-'}: ${a['cancel_reason'] ?? ''}',
                      style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
                if (a['status'] == 'WrittenOff')
                  Text('Written off ${a['written_off_at']}: ${a['write_off_reason'] ?? ''}', style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
                if (canCancel)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Can be cancelled until ${a['cancel_deadline']} (${_countdown(_num(a['cancel_seconds_left']).toInt())} left).',
                        style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900)),
                  ),
              ]),
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: Text(_num(a['voucher_print_count']) > 0 ? 'Print voucher (copy)' : 'Print voucher'),
              onPressed: () async {
                await _downloadPdf(context, '/staff-advances/${a['advance_id']}/voucher.pdf', '${a['voucher_no']}.pdf');
                _load();
              },
            ),
            OutlinedButton.icon(
              icon: Icon(a['has_signed_receipt'] == true ? Icons.verified_outlined : Icons.upload_file),
              label: Text(a['has_signed_receipt'] == true ? 'Replace signed voucher' : 'Upload signed voucher'),
              onPressed: _uploadReceipt,
            ),
            if (active && canCancel)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                icon: const Icon(Icons.undo),
                label: const Text('Cancel advance'),
                onPressed: _cancel,
              ),
            if (active && hasEditable)
              OutlinedButton.icon(icon: const Icon(Icons.edit_calendar_outlined), label: const Text('Change months'), onPressed: _reschedule),
            if (active && hasEditable)
              OutlinedButton.icon(icon: const Icon(Icons.payments_outlined), label: const Text('Cash repayment'), onPressed: _repay),
            if (active && !hasIncluded)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                icon: const Icon(Icons.block),
                label: const Text('Write off'),
                onPressed: _writeOff,
              ),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Deduction schedule', style: TextStyle(fontWeight: FontWeight.bold, color: _primary)),
                const SizedBox(height: 6),
                for (final i in installments)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(i['month_label'] ?? 'No month yet'),
                    subtitle: i['included_batch_id'] != null ? Text('Staff batch #${i['included_batch_id']}') : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${_money(i['amount'])} $cur', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      _StatusChip('${i['status']}'),
                    ]),
                  ),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('History', style: TextStyle(fontWeight: FontWeight.bold, color: _primary)),
                const SizedBox(height: 6),
                for (final l in ledger)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${l['entry_type']}${l['receipt_no'] != null ? ' · ${l['receipt_no']}' : ''}'),
                    subtitle: Text('${l['created_at']} · ${l['created_by']}${l['note'] != null ? ' · ${l['note']}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${_num(l['amount']) > 0 ? '+' : ''}${_money(l['amount'])}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: _num(l['amount']) > 0 ? Colors.orange.shade900 : Colors.green.shade800)),
                      if (l['entry_type'] == 'CashRepayment')
                        IconButton(
                          tooltip: 'Receipt PDF',
                          icon: const Icon(Icons.receipt_outlined, size: 20),
                          onPressed: () => _downloadPdf(context,
                              '/staff-advances/${a['advance_id']}/repayments/${l['entry_id']}/receipt.pdf', '${l['receipt_no']}.pdf'),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      ]);
}

class _RescheduleScreen extends StatefulWidget {
  final Map<String, dynamic> advance;
  final List<Map<String, dynamic>> months;
  final num total;
  final List<Map<String, dynamic>> current;
  const _RescheduleScreen({required this.advance, required this.months, required this.total, required this.current});

  @override
  State<_RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<_RescheduleScreen> {
  final List<_ScheduleRow> _rows = [];
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final i in widget.current) {
      final m = i['deduction_month'] as String?;
      final ok = widget.months.any((x) => x['month'] == m && x['selectable'] == true);
      final row = _ScheduleRow(month: ok ? m : null)..amount.text = _num(i['amount']).toString();
      if (_rows.any((r) => r.month != null && r.month == row.month)) row.month = null;
      _rows.add(row);
    }
    if (_rows.isEmpty) _rows.add(_ScheduleRow());
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  num get _scheduled => _rows.fold<num>(0, (s, r) => s + (num.tryParse(r.amount.text.trim()) ?? 0));

  Future<void> _save() async {
    if (_rows.any((r) => r.month == null)) return _snack(context, 'Choose a month for every row.', color: Colors.orange);
    if ((_scheduled * 100).round() != (widget.total * 100).round()) {
      return _snack(context, 'The amounts must add up to ${_money(widget.total)}.', color: Colors.orange);
    }
    if (_reason.text.trim().length < 5) return _snack(context, 'Enter a reason (at least 5 characters).', color: Colors.orange);
    setState(() => _saving = true);
    try {
      await ApiConfig.dio.put('/staff-advances/${widget.advance['advance_id']}/schedule', data: {
        'schedule': _rows.map((r) => {'month': r.month, 'amount': num.tryParse(r.amount.text.trim()) ?? 0}).toList(),
        'reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(context, _errorMessage(e, 'Failed to update the schedule.'), color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.total - _scheduled;
    return Scaffold(
      appBar: AppBar(title: Text('Change months · ${widget.advance['voucher_no']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Amount to schedule: ${_money(widget.total)} ${widget.advance['currency']} (what is not in a batch yet).',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _rows[i].month,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Month ${i + 1}', border: const OutlineInputBorder(), isDense: true),
                  items: [
                    for (final m in widget.months)
                      DropdownMenuItem<String>(
                        value: m['month'] as String,
                        enabled: m['selectable'] == true && !_rows.any((r) => r != _rows[i] && r.month == m['month']),
                        child: Text('${m['label']}${m['paid'] == true ? ' · Paid' : ''}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _rows[i].month = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rows[i].amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _rows.length <= 1
                    ? null
                    : () => setState(() {
                          _rows[i].amount.dispose();
                          _rows.removeAt(i);
                        }),
              ),
            ]),
          ),
        Row(children: [
          TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add month'), onPressed: () => setState(() => _rows.add(_ScheduleRow()))),
          const Spacer(),
          Text(remaining == 0 ? 'Fully scheduled' : 'Left: ${_money(remaining)}',
              style: TextStyle(color: remaining == 0 ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder())),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _primary, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _save,
            child: const Text('Save schedule'),
          ),
        ),
      ),
    );
  }
}
