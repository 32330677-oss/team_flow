// lib/screens/dpr/dpr_registers_screen.dart
//
// NCR register and Areas of concern register of a contract (the workbook's
// NCR_Reg and Concern_Reg). The daily report shows them "as of" its date:
// an item closed later is still open on the earlier reports.

import 'package:flutter/material.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import 'dpr_widgets.dart';

class DprRegistersPage extends StatelessWidget {
  const DprRegistersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const DprContractBar(showDate: false),
      Expanded(child: DprSelection(withDate: false, builder: (ctx, cid, _) => _Registers(key: ValueKey(cid), contractId: cid))),
    ]);
  }
}

class _Registers extends StatefulWidget {
  final int contractId;
  const _Registers({super.key, required this.contractId});

  @override
  State<_Registers> createState() => _RegistersState();
}

class _RegistersState extends State<_Registers> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Json>? _ncr;
  List<Json>? _con;
  String? _status; // null = all
  String? _error;
  Json _lists = {};

  bool get canEdit => DprState.can('dpr.registers');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        DprApi.register(widget.contractId, 'ncr', status: _status),
        DprApi.register(widget.contractId, 'concerns', status: _status),
        DprApi.options(),
      ]);
      if (!mounted) return;
      setState(() {
        _ncr = r[0] as List<Json>;
        _con = r[1] as List<Json>;
        _lists = asJson((r[2] as Json)['lists']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<String> _list(String k) => (_lists[k] as List? ?? const []).map((e) => e.toString()).toList();

  Future<void> _edit(String kind, [Json? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RegisterDialog(
        contractId: widget.contractId,
        kind: kind,
        row: row,
        severities: _list('severity'),
        impacts: _list('impact'),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(String kind, Json row) async {
    final id = asInt(row[kind == 'ncr' ? 'ncr_id' : 'concern_id']);
    final label = kind == 'ncr' ? str(row['ncr_no']) : str(row['issue']);
    if (!await dprConfirm(context, 'Delete', 'Delete "$label"? It disappears from every report not issued yet.', ok: 'Delete', danger: true)) return;
    try {
      await DprApi.deleteRegister(widget.contractId, kind, id);
      _load();
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Widget _actions(String kind, Json row) => canEdit
      ? Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Edit / close', icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _edit(kind, row)),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), onPressed: () => _delete(kind, row)),
        ])
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (_ncr == null || _con == null) {
      return _error != null
          ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
          : const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final filter = Wrap(spacing: 8, children: [
      for (final s in [null, 'Open', 'Closed'])
        ChoiceChip(
          label: Text(s ?? 'All'),
          selected: _status == s,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: _status == s ? Colors.white : AppColors.textPrimary),
          onSelected: (_) {
            _status = s;
            _load();
          },
        ),
    ]);
    return Column(children: [
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(text: 'NCR register (${_ncr!.length})'),
            Tab(text: 'Areas of concern (${_con!.length})'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          ListView(padding: const EdgeInsets.all(14), children: [
            AppDataTableCard(
              title: 'Non-conformance reports',
              icon: Icons.report_gmailerrorred_rounded,
              accentColor: AppColors.danger,
              emptyMessage: 'No NCR.',
              trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                filter,
                if (canEdit) ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit('ncr'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New NCR')),
              ]),
              columns: [dprCol('NCR No.'), dprCol('Raised'), dprCol('Raised by'), dprCol('Description'), dprCol('Root cause'), dprCol('Corrective action'),
                dprCol('Responsible'), dprCol('Target'), dprCol('Status'), dprCol('Closed'), dprCol('')],
              rows: _ncr!
                  .map((x) => DataRow(cells: [
                        DataCell(dprCell(str(x['ncr_no']), bold: true)),
                        DataCell(dprCell(fmtDay(x['date_raised']))),
                        DataCell(dprCell(str(x['raised_by']))),
                        DataCell(dprCell(str(x['description']), width: 220)),
                        DataCell(dprCell(str(x['root_cause']), width: 160)),
                        DataCell(dprCell(str(x['corrective_action']), width: 200)),
                        DataCell(dprCell(str(x['responsible']))),
                        DataCell(dprCell(fmtDay(x['target_date']))),
                        DataCell(StatusBadge.fromStatus(str(x['status']) == 'Open' ? 'Pending' : 'Completed')),
                        DataCell(dprCell(fmtDay(x['date_closed']))),
                        DataCell(_actions('ncr', x)),
                      ]))
                  .toList(),
            ),
          ]),
          ListView(padding: const EdgeInsets.all(14), children: [
            AppDataTableCard(
              title: 'Areas of concern / delays / constraints',
              icon: Icons.warning_amber_rounded,
              accentColor: const Color(0xffb45309),
              emptyMessage: 'No concern.',
              trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                filter,
                if (canEdit)
                  ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit('concerns'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New concern')),
              ]),
              columns: [dprCol('Raised'), dprCol('Issue'), dprCol('Impact'), dprCol('Severity'), dprCol('Action required'), dprCol('By whom'),
                dprCol('Target'), dprCol('Status'), dprCol('Closed'), dprCol('')],
              rows: _con!
                  .map((x) => DataRow(cells: [
                        DataCell(dprCell(fmtDay(x['date_raised']))),
                        DataCell(dprCell(str(x['issue']), width: 240)),
                        DataCell(dprCell(str(x['impact']))),
                        DataCell(dprCell(str(x['severity']), bold: true, color: str(x['severity']) == 'High' ? AppColors.danger : null)),
                        DataCell(dprCell(str(x['action_required']), width: 220)),
                        DataCell(dprCell(str(x['by_whom']))),
                        DataCell(dprCell(fmtDay(x['target_date']))),
                        DataCell(StatusBadge.fromStatus(str(x['status']) == 'Open' ? 'Pending' : 'Completed')),
                        DataCell(dprCell(fmtDay(x['date_closed']))),
                        DataCell(_actions('concerns', x)),
                      ]))
                  .toList(),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

class _RegisterDialog extends StatefulWidget {
  final int contractId;
  final String kind; // ncr / concerns
  final Json? row;
  final List<String> severities;
  final List<String> impacts;
  const _RegisterDialog({required this.contractId, required this.kind, required this.row, required this.severities, required this.impacts});

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final Map<String, TextEditingController> _c = {};
  late String _status = str(widget.row?['status']).isEmpty ? 'Open' : str(widget.row?['status']);
  late String? _severity = str(widget.row?['severity']).isEmpty ? null : str(widget.row?['severity']);
  late String? _impact = str(widget.row?['impact']).isEmpty ? null : str(widget.row?['impact']);
  DateTime? _raised;
  DateTime? _target;
  DateTime? _closed;
  bool _busy = false;
  String? _error;

  bool get isNcr => widget.kind == 'ncr';

  @override
  void initState() {
    super.initState();
    final keys = isNcr
        ? ['ncr_no', 'raised_by', 'description', 'root_cause', 'corrective_action', 'responsible']
        : ['issue', 'action_required', 'by_whom'];
    for (final k in keys) {
      _c[k] = TextEditingController(text: str(widget.row?[k]));
    }
    DateTime? d(String k) => str(widget.row?[k]).isEmpty ? null : parseYmd(str(widget.row?[k]));
    _raised = d('date_raised') ?? DprState.date.value;
    _target = d('target_date');
    _closed = d('date_closed');
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  Widget _dateField(String label, DateTime? v, ValueChanged<DateTime?> set, {bool clearable = true}) => InkWell(
        onTap: _busy
            ? null
            : () async {
                final p = await _pick(v);
                if (p != null) setState(() => set(p));
              },
        child: InputDecorator(
          decoration: dprInput(label,
              suffix: clearable && v != null
                  ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => setState(() => set(null)))
                  : const Icon(Icons.event_rounded, size: 18)),
          child: Text(v == null ? '—' : fmtDay(ymd(v))),
        ),
      );

  Future<void> _save() async {
    final body = <String, dynamic>{
      for (final e in _c.entries) e.key: e.value.text.trim(),
      'date_raised': _raised == null ? null : ymd(_raised!),
      'target_date': _target == null ? null : ymd(_target!),
      'status': _status,
      'date_closed': _status == 'Closed' && _closed != null ? ymd(_closed!) : null,
      if (!isNcr) 'severity': _severity,
      if (!isNcr) 'impact': _impact,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idKey = isNcr ? 'ncr_id' : 'concern_id';
      await DprApi.saveRegister(widget.contractId, widget.kind, widget.row == null ? null : asInt(widget.row![idKey]), body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tf(String k, String label, {int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: _c[k], enabled: !_busy, minLines: lines, maxLines: lines + 2, decoration: dprInput(label)),
        );
    return AlertDialog(
      title: Text(widget.row == null ? (isNcr ? 'New NCR' : 'New concern') : (isNcr ? 'NCR ${str(widget.row!['ncr_no'])}' : 'Concern')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (isNcr) ...[
              Row(children: [
                Expanded(child: tf('ncr_no', 'NCR No.')),
                const SizedBox(width: 10),
                Expanded(child: tf('raised_by', 'Raised by')),
              ]),
              tf('description', 'Description', lines: 2),
              tf('root_cause', 'Root cause'),
              tf('corrective_action', 'Corrective action', lines: 2),
              tf('responsible', 'Responsible'),
            ] else ...[
              tf('issue', 'Issue / description', lines: 2),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _impact,
                    decoration: dprInput('Impact'),
                    items: {...widget.impacts, if (_impact != null) _impact!}.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _impact = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _severity,
                    decoration: dprInput('Severity'),
                    items: {...widget.severities, if (_severity != null) _severity!}.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _severity = v),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              tf('action_required', 'Action required', lines: 2),
              tf('by_whom', 'By whom'),
            ],
            Row(children: [
              Expanded(child: _dateField('Date raised', _raised, (v) => _raised = v, clearable: false)),
              const SizedBox(width: 10),
              Expanded(child: _dateField('Target date', _target, (v) => _target = v)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration: dprInput('Status'),
                  items: const [DropdownMenuItem(value: 'Open', child: Text('Open')), DropdownMenuItem(value: 'Closed', child: Text('Closed'))],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                            _status = v ?? 'Open';
                            if (_status == 'Closed') _closed ??= DprState.date.value;
                          }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _status == 'Closed' ? _dateField('Date closed', _closed, (v) => _closed = v, clearable: false) : const SizedBox.shrink()),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
