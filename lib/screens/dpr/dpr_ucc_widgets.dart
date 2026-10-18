// lib/screens/dpr/dpr_ucc_widgets.dart
//
// Pieces of the daily report in the client's form (UCC-IMS-CM-3003A):
//   * UccLayoutEditor: what is printed (sections, tables, columns, titles, empty rows),
//     used for one day (report page) and as the contract default (Setup).
//   * UccFigureDialog: change any figure — this report only / from this day on /
//     counts in the cumulative — with the days and issued reports it changes shown
//     BEFORE saving, the same value in other contracts if wanted, history, and
//     remove everywhere / from a date.

import 'package:flutter/material.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import 'dpr_widgets.dart';

// ---------------------------------------------------------------------------
// Layout editor
// ---------------------------------------------------------------------------
class UccLayoutEditor extends StatelessWidget {
  final List<Json> sections; // schema from the server (dprUccLayout.SECTIONS)
  final Json layout; // effective layout
  final bool enabled;
  final ValueChanged<Json> onChanged;
  const UccLayoutEditor({super.key, required this.sections, required this.layout, required this.onChanged, this.enabled = true});

  Json _part(String k) => asJson(layout[k]);

  void _set(String part, String key, dynamic value) {
    final l = Map<String, dynamic>.from(layout);
    final p = Map<String, dynamic>.from(asJson(l[part]));
    p[key] = value;
    l[part] = p;
    onChanged(l);
  }

  Future<void> _editTitle(BuildContext context, String key, String current) async {
    final ctl = TextEditingController(text: current);
    final r = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Title printed'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: ctl, autofocus: true, decoration: dprInput('Title')),
            const SizedBox(height: 8),
            const Text('{code} = contract code, {area} = area name. Empty = no title.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          ElevatedButton(style: dprPrimaryButton(), onPressed: () => Navigator.pop(dCtx, ctl.text), child: const Text('Use')),
        ],
      ),
    );
    ctl.dispose();
    if (r != null) _set('titles', key, r.trim());
  }

  @override
  Widget build(BuildContext context) {
    final secs = _part('sections');
    final tabs = _part('tables');
    final cols = _part('columns');
    final titles = _part('titles');
    final empty = _part('hide_empty');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in sections) _section(context, s, secs, tabs, cols, titles, empty),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Photos per page', style: TextStyle(fontWeight: FontWeight.w600)),
        DropdownButton<int>(
          value: asInt(layout['photos_per_page']) == 0 ? 1 : asInt(layout['photos_per_page']),
          items: const [1, 2, 4, 6].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
          onChanged: enabled
              ? (v) {
                  final l = Map<String, dynamic>.from(layout);
                  l['photos_per_page'] = v;
                  onChanged(l);
                }
              : null,
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
            value: layout['photo_captions'] != false,
            onChanged: enabled
                ? (v) {
                    final l = Map<String, dynamic>.from(layout);
                    l['photo_captions'] = v;
                    onChanged(l);
                  }
                : null,
          ),
          const Text('Photo captions'),
        ]),
      ]),
    ]);
  }

  Widget _section(BuildContext context, Json s, Json secs, Json tabs, Json cols, Json titles, Json empty) {
    final key = str(s['key']);
    final on = secs[key] != false;
    final tables = asList(s['tables']);
    final title = titles.containsKey(key) ? str(titles[key]) : str(s['title']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      decoration: BoxDecoration(
        color: on ? Colors.white : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Switch(value: on, onChanged: enabled ? (v) => _set('sections', key, v) : null),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(s['label']), style: TextStyle(fontWeight: FontWeight.w700, color: on ? AppColors.textPrimary : AppColors.textSecondary)),
              if (title.isNotEmpty) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
          if (enabled && s.containsKey('title'))
            IconButton(
              tooltip: 'Change the printed title',
              icon: const Icon(Icons.title_rounded, size: 19, color: AppColors.primary),
              onPressed: () => _editTitle(context, key, title),
            ),
        ]),
        if (on)
          for (final t in tables)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Checkbox(
                    value: tabs[str(t['key'])] != false,
                    onChanged: enabled ? (v) => _set('tables', str(t['key']), v == true) : null,
                  ),
                  Text('Table: ${str(t['label'])}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(width: 10),
                  FilterChip(
                    label: const Text('Print empty rows', style: TextStyle(fontSize: 11.5)),
                    selected: empty[str(t['key'])] != true,
                    onSelected: enabled ? (v) => _set('hide_empty', str(t['key']), !v) : null,
                  ),
                ]),
                if (tabs[str(t['key'])] != false)
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final c in (t['columns'] as List? ?? const []))
                        _colChip(context, str(t['key']), c is List && c.isNotEmpty ? str(c[0]) : '', c is List && c.length > 1 ? str(c[1]) : '', cols, titles),
                    ]),
                  ),
              ]),
            ),
      ]),
    );
  }

  Widget _colChip(BuildContext context, String table, String col, String label, Json cols, Json titles) {
    final k = '$table.$col';
    final on = cols[k] != false;
    final tk = 'col.$k';
    final shown = titles.containsKey(tk) ? str(titles[tk]) : label;
    return InputChip(
      label: Text(shown.isEmpty ? col : shown, style: const TextStyle(fontSize: 11.5)),
      selected: on,
      showCheckmark: true,
      onSelected: enabled ? (v) => _set('columns', k, v) : null,
      onDeleted: enabled ? () => _editTitle(context, tk, shown) : null,
      deleteIcon: const Icon(Icons.edit_rounded, size: 14),
      deleteButtonTooltipMessage: 'Rename the column',
    );
  }
}

// ---------------------------------------------------------------------------
// One figure: change it, see what it changes, its history
// ---------------------------------------------------------------------------
/// kind: 'count' (people / machines of the day), 'curr' (BOQ quantity of the day),
/// 'cum' (BOQ cumulative), 'display' (any other printed figure).
class UccFigureDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final String figureKey;
  final String label;
  final Json cell; // { v, s, m, e }
  final String kind;
  final bool sourced; // read from a system (needs the permission dpr.override + a reason)
  final List<Json> otherContracts;
  const UccFigureDialog({
    super.key,
    required this.contractId,
    required this.date,
    required this.figureKey,
    required this.label,
    required this.cell,
    required this.kind,
    required this.sourced,
    this.otherContracts = const [],
  });

  @override
  State<UccFigureDialog> createState() => _UccFigureDialogState();
}

class _UccFigureDialogState extends State<UccFigureDialog> {
  late final TextEditingController _value = TextEditingController(text: str(widget.cell['v']));
  final TextEditingController _reason = TextEditingController();
  late String _scope = _scopes.first.$1;
  DateTime? _toDate;
  final Set<int> _applyTo = {};
  Json? _impact;
  List<Json> _history = [];
  String? _error;
  bool _busy = false;

  bool get _canWrite => widget.sourced ? DprState.can('dpr.override') : DprState.can('dpr.edit');

  List<(String, String, String)> get _scopes {
    switch (widget.kind) {
      case 'curr':
        return const [
          ('day', 'This report only', 'Printed on this day; the cumulative of the next days does not change.'),
          ('chain', 'Counts in the cumulative', 'Replaces the quantity of this day; the cumulative of every later day changes.'),
        ];
      case 'cum':
        return const [
          ('day', 'This report only', 'Printed on this day only; later days keep their own cumulative.'),
          ('forward', 'From this day on', 'The cumulative becomes this value on this day; later days add their own quantities to it.'),
        ];
      default:
        return const [
          ('day', 'This report only', 'Only this day changes.'),
          ('forward', 'From this day on', 'The same value every following day, until you change it or stop it.'),
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _preview();
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Json get _body => {
        'key': widget.figureKey,
        'value': _value.text.trim(),
        'scope': _scope,
        if (_toDate != null) 'to_date': ymd(_toDate!),
        'reason': _reason.text.trim(),
        'apply_to': _applyTo.toList(),
      };

  Future<void> _loadHistory() async {
    if (widget.figureKey.startsWith('auto:')) return;
    try {
      final h = await DprApi.manualHistory(widget.contractId, widget.date, widget.figureKey);
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  Future<void> _preview() async {
    try {
      final r = await DprApi.previewManual(widget.contractId, widget.date, _body);
      if (mounted) setState(() => _impact = r);
    } catch (_) {
      if (mounted) setState(() => _impact = null);
    }
  }

  Future<void> _save() async {
    if (_value.text.trim().isEmpty) {
      setState(() => _error = 'Enter the value.');
      return;
    }
    if (widget.sourced && _reason.text.trim().length < 3 && !widget.figureKey.startsWith('tot:')) {
      setState(() => _error = 'Write the reason of the change (this figure comes from the system).');
      return;
    }
    final issued = asList(_impact?['issued']);
    if (issued.isNotEmpty) {
      final ok = await dprConfirm(
        context,
        'Issued reports will change',
        'This change reaches ${issued.length} issued report(s): ${issued.map((x) => '${str(x['code'])} ${fmtDay(x['report_date'])}').join(', ')}.\n\n'
            'They stay frozen as issued and are marked "Changed since issue": issue a revision for each to print the new figures.',
        ok: 'Save anyway',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.setManual(widget.contractId, widget.date, _body);
      if (mounted) Navigator.pop(context, true);
    } on DprException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _revert(String mode) async {
    final from = mode == 'from';
    final ok = await dprConfirm(
      context,
      from ? 'Stop from this day' : 'Remove everywhere',
      from
          ? 'The manual value stops the day before ${fmtDay(widget.date)}: earlier days keep it, this day and the next ones use the system / computed value again.'
          : 'The manual value is removed from every day it was used, as if it was never typed. It stays in the history.',
      ok: from ? 'Stop' : 'Remove',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await DprApi.revertManual(widget.contractId, widget.date, {
        'key': widget.figureKey,
        'mode': mode,
        'from_date': widget.date,
        'apply_to': _applyTo.toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } on DprException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  String _source(Json c) {
    switch (str(c['m'])) {
      case 'manual':
        return 'Manual value';
      case 'system':
        return 'From the system';
      case 'computed':
        return 'Calculated';
      case 'adjusted':
        return 'Cumulative adjusted from ${fmtDay(asJson(c['e'])['from_date'])}';
      case 'typed':
        return 'Typed by the QC';
      default:
        return 'Empty';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cell;
    final e = asJson(c['e']);
    final active = str(c['m']) == 'manual' && e.isNotEmpty;
    final impact = _impact;
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('In the report: ${str(c['v']).isEmpty ? '—' : fmtQty(c['v'])}  ·  ${_source(c)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (c['s'] != null && str(c['m']) != 'system')
                  Text('System / calculated value: ${fmtQty(c['s'])}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                if (active)
                  Text(
                      '${str(e['scope']) == 'forward' ? 'From ${fmtDay(e['from_date'])} on${str(e['to_date']).isEmpty ? '' : ' to ${fmtDay(e['to_date'])}'}' : (str(e['scope']) == 'chain' ? 'Counts in the cumulative' : 'This report only')}'
                      ' · ${str(e['by'])} ${str(e['at'])}${str(e['reason']).isEmpty ? '' : ' — ${str(e['reason'])}'}',
                      style: const TextStyle(fontSize: 12, color: Color(0xffb45309))),
                const SizedBox(height: 4),
                const Text('The systems are never changed: a manual value only replaces the figure in the report.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(height: 12),
            if (_canWrite) ...[
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: dprInput('New value'),
              ),
              const SizedBox(height: 10),
              for (final s in _scopes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_scope == s.$1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: _scope == s.$1 ? AppColors.primary : AppColors.textSecondary),
                  title: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.$3, style: const TextStyle(fontSize: 11.5)),
                  onTap: () {
                    setState(() => _scope = s.$1);
                    _preview();
                  },
                ),
              if (_scope == 'forward' && widget.kind != 'cum')
                Row(children: [
                  const Text('Last day (optional): '),
                  TextButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(_toDate == null ? 'No end' : fmtDay(ymd(_toDate!))),
                    onPressed: () async {
                      final start = parseYmd(widget.date);
                      final p = await showDatePicker(context: context, initialDate: _toDate ?? start, firstDate: start, lastDate: DateTime(2100));
                      setState(() => _toDate = p);
                      _preview();
                    },
                  ),
                  if (_toDate != null)
                    IconButton(
                        tooltip: 'No end',
                        onPressed: () {
                          setState(() => _toDate = null);
                          _preview();
                        },
                        icon: const Icon(Icons.clear_rounded, size: 16)),
                ]),
              TextField(controller: _reason, decoration: dprInput(widget.sourced ? 'Reason (required)' : 'Reason (optional)')),
              if (widget.otherContracts.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Also put this value in:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                Wrap(spacing: 6, children: [
                  for (final o in widget.otherContracts)
                    FilterChip(
                      label: Text('${str(o['code'])} · ${str(o['title'])}', style: const TextStyle(fontSize: 12)),
                      selected: _applyTo.contains(asInt(o['contract_id'])),
                      onSelected: (v) {
                        setState(() => v ? _applyTo.add(asInt(o['contract_id'])) : _applyTo.remove(asInt(o['contract_id'])));
                        _preview();
                      },
                    ),
                ]),
                const Text('Unticked contracts are not changed.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
              if (impact != null) ...[
                const SizedBox(height: 10),
                DprBanner(
                  color: asList(impact['issued']).isEmpty ? AppColors.primary : const Color(0xffb45309),
                  icon: Icons.info_outline_rounded,
                  lines: [
                    'Changes ${asInt(impact['days'])} day(s): ${fmtDay(impact['from'])}${str(impact['to']) == str(impact['from']) ? '' : ' to ${fmtDay(impact['to'])}'}.',
                    if (asList(impact['issued']).isNotEmpty)
                      'Issued reports reached: ${asList(impact['issued']).map((x) => '${str(x['code'])} ${fmtDay(x['report_date'])} Rev.${str(x['revision'])}').join(', ')} — they will need a revision.',
                    for (final l in asList(impact['later_values'])) 'From ${fmtDay(l['from_date'])} another manual value (${fmtQty(l['value'])}) still applies.',
                  ],
                ),
              ],
            ] else
              const DprBanner(
                lines: ['Your role cannot change this figure.'],
                color: AppColors.textSecondary,
                icon: Icons.lock_outline_rounded,
              ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('History of this figure', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final h in _history)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(h['active'] == true ? Icons.radio_button_checked_rounded : Icons.history_rounded,
                        size: 16, color: h['active'] == true ? const Color(0xffb45309) : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${fmtQty(h['value'])} · ${str(h['scope']) == 'forward' ? 'from ${fmtDay(h['from_date'])}${str(h['to_date']).isEmpty ? '' : ' to ${fmtDay(h['to_date'])}'}' : '${str(h['scope']) == 'chain' ? 'in cumulative' : 'only'} ${fmtDay(h['from_date'])}'}'
                        ' · ${str(h['created_by'])} ${str(h['created_at'])}${str(h['reason']).isEmpty ? '' : ' · ${str(h['reason'])}'}'
                        '${h['active'] == true ? '' : ' · ${str(h['revert_note'])} ${str(h['reverted_at'])}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        if (_canWrite && active && str(e['scope']) == 'forward' && str(e['from_date']).compareTo(widget.date) < 0)
          TextButton.icon(
              onPressed: _busy ? null : () => _revert('from'), icon: const Icon(Icons.stop_circle_outlined), label: const Text('Stop from this day')),
        if (_canWrite && active)
          TextButton.icon(
              onPressed: _busy ? null : () => _revert('all'),
              icon: const Icon(Icons.undo_rounded),
              label: Text(widget.sourced ? 'Back to the system value' : 'Remove everywhere')),
        if (_canWrite) ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
