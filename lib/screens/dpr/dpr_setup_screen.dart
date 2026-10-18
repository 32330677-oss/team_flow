// lib/screens/dpr/dpr_setup_screen.dart
//
// One-time setup of each contract (the workbook's Setup sheet), all editable
// later: contract information, VO / EOT log, own trades, own plant,
// subcontractor lines, BOQ (typed or imported from Excel), and which Team Flow /
// Equipment sites and names feed each line. Nothing is fixed in the app: the
// contracts (e.g. 71, 26, 59), their lines and their names are data.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import 'dpr_setup_ucc.dart';
import 'dpr_widgets.dart';

class DprSetupPage extends StatefulWidget {
  const DprSetupPage({super.key});

  @override
  State<DprSetupPage> createState() => _DprSetupPageState();
}

class _DprSetupPageState extends State<DprSetupPage> {
  int _barKey = 0;

  Future<void> _newContract() async {
    final r = await showDialog<Json>(context: context, builder: (_) => const _NewContractDialog());
    if (r == null) return;
    DprState.contractId.value = asInt(r['contract_id']);
    setState(() => _barKey += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      DprContractBar(
        key: ValueKey(_barKey),
        showDate: false,
        actions: [
          if (DprState.can('dpr.setup'))
            ElevatedButton.icon(style: dprPrimaryButton(), onPressed: _newContract, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New contract')),
        ],
      ),
      Expanded(
        child: DprSelection(
          withDate: false,
          builder: (ctx, cid, _) => _Setup(key: ValueKey('$cid|$_barKey'), contractId: cid, onRenamed: () => setState(() => _barKey += 1)),
        ),
      ),
    ]);
  }
}

class _Setup extends StatefulWidget {
  final int contractId;
  final VoidCallback onRenamed;
  const _Setup({super.key, required this.contractId, required this.onRenamed});

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 12, vsync: this);
  Json? _s;
  Json? _src; // source options (Team Flow / equipment names)
  List<Json> _contracts = [];
  String? _error;

  int get cid => widget.contractId;
  bool get canEdit => DprState.can('dpr.setup');

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
      final s = await DprApi.setup(cid);
      final all = await DprApi.contracts();
      if (!mounted) return;
      setState(() {
        _s = s;
        _contracts = all;
        _error = null;
      });
      if (canEdit && _src == null) _loadSources();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSources() async {
    try {
      final ids = (asJson(_s?['contract'])['tf_site_ids'] as List? ?? const []).map((e) => asInt(e)).toList();
      final o = await DprApi.sourceOptions(ids);
      if (mounted) setState(() => _src = o);
    } catch (e) {
      if (mounted) dprSnack(context, 'Names from the systems not loaded: $e', error: true);
    }
  }

  Json get contract => asJson(_s?['contract']);
  List<Json> get lines => asList(_s?['lines']);

  Future<void> _copySetup() async {
    final others = _contracts.where((c) => asInt(c['contract_id']) != cid).toList();
    if (others.isEmpty) return;
    final r = await showDialog<_CopySetupChoice>(context: context, builder: (_) => _CopySetupDialog(contracts: others));
    if (r == null) return;
    try {
      final out = await DprApi.copySetup(cid, r.fromId, r.parts);
      if (mounted) dprSnack(context, 'Copied: ${out.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
      _load();
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_s == null) {
      return _error != null
          ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
          : const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    int count(String k) => lines.where((l) => l['kind'] == k).length;
    return Column(children: [
      Container(
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppColors.primary,
              indicatorColor: AppColors.accent,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: [
                const Tab(text: 'Contract'),
                const Tab(text: 'Sources'),
                Tab(text: 'VO / EOT (${asList(_s?['eot_vo']).length})'),
                Tab(text: 'Staff (${count('staff')})'),
                Tab(text: 'Trades (${count('trade')})'),
                Tab(text: 'Plant (${count('plant')})'),
                Tab(text: 'Tools (${count('tool')})'),
                Tab(text: 'Subcontractors (${count('subcon')})'),
                Tab(text: 'BOQ (${asList(_s?['boq']).where((b) => str(b['row_type']) == 'item' || str(b['row_type']).isEmpty).length})'),
                Tab(text: 'Areas (${asList(_s?['areas']).length})'),
                Tab(text: 'Fixed pages (${asList(_s?['fixed_pages']).length})'),
                const Tab(text: 'Layout'),
              ],
            ),
          ),
          if (canEdit && _contracts.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(onPressed: _copySetup, icon: const Icon(Icons.content_copy_rounded, size: 17), label: const Text('Copy setup from…')),
            ),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          _ContractTab(key: ValueKey('c${contract['updated_at']}'), contract: contract, contracts: _contracts, sections: asList(_s?['sections']),
              ucc: asJson(_s?['ucc']), canEdit: canEdit, onSaved: () {
            _load();
            widget.onRenamed();
          }),
          _SourcesTab(contract: contract, src: _src, canEdit: canEdit, onSaved: () {
            _src = null;
            _load();
          }),
          _EotTab(contractId: cid, rows: asList(_s?['eot_vo']), totals: asJson(_s?['totals']), canEdit: canEdit, onChanged: _load),
          _LinesTab(contractId: cid, kind: 'staff', lines: lines, src: _src, lists: asJson(_s?['lists']), canEdit: canEdit, onChanged: _load),
          _LinesTab(contractId: cid, kind: 'trade', lines: lines, src: _src, lists: asJson(_s?['lists']), canEdit: canEdit, onChanged: _load),
          _LinesTab(contractId: cid, kind: 'plant', lines: lines, src: _src, lists: asJson(_s?['lists']), canEdit: canEdit, onChanged: _load),
          _LinesTab(contractId: cid, kind: 'tool', lines: lines, src: _src, lists: asJson(_s?['lists']), canEdit: canEdit, onChanged: _load),
          _LinesTab(contractId: cid, kind: 'subcon', lines: lines, src: _src, lists: asJson(_s?['lists']), canEdit: canEdit, onChanged: _load),
          _BoqTab(contractId: cid, rows: asList(_s?['boq']), canEdit: canEdit, onChanged: _load),
          DprAreasTab(contractId: cid, areas: asList(_s?['areas']), canEdit: canEdit, onChanged: _load),
          DprFixedPagesTab(contractId: cid, pages: asList(_s?['fixed_pages']), canEdit: canEdit, onChanged: _load),
          DprLayoutTab(contract: contract, ucc: asJson(_s?['ucc']), canEdit: canEdit, onChanged: _load),
        ]),
      ),
    ]);
  }
}

// ======================================================================
// Contract information
// ======================================================================
class _ContractTab extends StatefulWidget {
  final Json contract;
  final List<Json> contracts;
  final List<Json> sections;
  final Json ucc;
  final bool canEdit;
  final VoidCallback onSaved;
  const _ContractTab(
      {super.key, required this.contract, required this.contracts, required this.sections, required this.ucc, required this.canEdit, required this.onSaved});

  @override
  State<_ContractTab> createState() => _ContractTabState();
}

const _contractText = [
  ['code', 'Contract code (tab)'],
  ['title', 'Contract title'],
  ['company_name', 'Company name (report header)'],
  ['project_name', 'Project name'],
  ['project_code', 'Project code'],
  ['agreement_no', 'Agreement / contract No.'],
  ['client', 'Client / employer'],
  ['consultant', 'Consultant / engineer'],
  ['main_contractor', 'Main contractor'],
  ['location', 'Project location'],
  ['currency', 'Currency'],
  ['contract_value', 'Contract value'],
  ['hrs_mp', 'Working hours / day – manpower'],
  ['hrs_pl', 'Working hours / day – plant'],
  ['prepared_by', 'Prepared by (name / title)'],
  ['reviewed_by', 'Reviewed by (name / title)'],
  ['consultant_rep', "Consultant's representative"],
  ['report_prefix', 'Report number prefix'],
];

class _ContractTabState extends State<_ContractTab> {
  final Map<String, TextEditingController> _c = {};
  DateTime? _start;
  DateTime? _finish;
  late bool _active = widget.contract['is_active'] == true;
  late Set<int> _copyFrom = (widget.contract['copy_from_ids'] as List? ?? const []).map((e) => asInt(e)).toSet();
  late Map<String, dynamic> _sections = Map<String, dynamic>.from(asJson(widget.contract['sections']));
  final GlobalKey<DprUccContractCardState> _uccKey = GlobalKey<DprUccContractCardState>();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in _contractText) {
      var v = str(widget.contract[f[0]]);
      if (['contract_value', 'hrs_mp', 'hrs_pl'].contains(f[0]) && v.contains('.')) {
        v = v.replaceFirst(RegExp(r'0+$'), '');
        if (v.endsWith('.')) v = v.substring(0, v.length - 1);
      }
      _c[f[0]] = TextEditingController(text: v);
    }
    _start = str(widget.contract['commencement_date']).isEmpty ? null : parseYmd(str(widget.contract['commencement_date']));
    _finish = str(widget.contract['original_completion']).isEmpty ? null : parseYmd(str(widget.contract['original_completion']));
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, dynamic>{
      for (final e in _c.entries) e.key: e.value.text.trim(),
      'is_active': _active,
      'commencement_date': _start == null ? null : ymd(_start!),
      'original_completion': _finish == null ? null : ymd(_finish!),
      'copy_from_ids': _copyFrom.toList(),
      'sections': _sections,
      ...?_uccKey.currentState?.values(),
    };
    if (str(body['contract_value']).isEmpty) body['contract_value'] = null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.updateContract(asInt(widget.contract['contract_id']), body);
      if (mounted) dprSnack(context, 'Contract saved.');
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _date(String label, DateTime? v, ValueChanged<DateTime> set) => SizedBox(
        width: 260,
        child: InkWell(
          onTap: !widget.canEdit || _busy
              ? null
              : () async {
                  final p = await showDatePicker(context: context, initialDate: v ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
                  if (p != null) setState(() => set(p));
                },
          child: InputDecorator(decoration: dprInput(label, suffix: const Icon(Icons.event_rounded, size: 18)), child: Text(v == null ? '—' : fmtDay(ymd(v)))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final others = widget.contracts.where((c) => asInt(c['contract_id']) != asInt(widget.contract['contract_id'])).toList();
    // a Column (not a lazy list): the cards keep their typed values when scrolled out of sight
    return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DprCard(
        title: 'Contract information',
        subtitle: 'Printed in the report header. Report No. = prefix + day number from the commencement date.',
        icon: Icons.description_rounded,
        actions: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Active'),
            Switch(value: _active, activeThumbColor: AppColors.primary, onChanged: widget.canEdit ? (v) => setState(() => _active = v) : null),
          ]),
        ],
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final f in _contractText)
            SizedBox(
              width: ['project_name', 'title', 'client', 'consultant', 'main_contractor'].contains(f[0]) ? 530 : 260,
              child: TextField(
                controller: _c[f[0]],
                enabled: widget.canEdit && !_busy,
                keyboardType: ['contract_value', 'hrs_mp', 'hrs_pl'].contains(f[0]) ? const TextInputType.numberWithOptions(decimal: true) : null,
                inputFormatters: ['contract_value', 'hrs_mp', 'hrs_pl'].contains(f[0]) ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                decoration: dprInput(f[1]),
              ),
            ),
          _date('Commencement date', _start, (v) => _start = v),
          _date('Original completion date', _finish, (v) => _finish = v),
        ]),
      ),
      DprUccContractCard(
        key: _uccKey,
        contract: widget.contract,
        contracts: widget.contracts,
        ucc: widget.ucc,
        enabled: widget.canEdit && !_busy,
      ),
      if (str(widget.contract['template']) == 'dpr')
      DprCard(
        title: 'Copy day data from',
        subtitle: 'Contracts that work with the same people and machines (e.g. 71 and 26). Their day can be copied into this one with "Copy from…".',
        icon: Icons.content_copy_rounded,
        child: others.isEmpty
            ? const Text('No other contract.', style: TextStyle(color: AppColors.textSecondary))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: others.map((c) {
                  final id = asInt(c['contract_id']);
                  return FilterChip(
                    label: Text('${str(c['code'])} · ${str(c['title'])}'),
                    selected: _copyFrom.contains(id),
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.primary,
                    onSelected: widget.canEdit ? (v) => setState(() => v ? _copyFrom.add(id) : _copyFrom.remove(id)) : null,
                  );
                }).toList(),
              ),
      ),
      if (str(widget.contract['template']) == 'dpr')
      DprCard(
        title: 'Sections printed by default',
        subtitle: 'Each day can still switch a section on or off.',
        icon: Icons.print_rounded,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.sections.map((s) {
            final k = str(s['key']);
            return FilterChip(
              label: Text(str(s['label'])),
              selected: _sections[k] != false,
              selectedColor: AppColors.primary.withValues(alpha: 0.12),
              checkmarkColor: AppColors.primary,
              onSelected: widget.canEdit ? (v) => setState(() => _sections = {..._sections, k: v}) : null,
            );
          }).toList(),
        ),
      ),
      if (_error != null) DprBanner(lines: [_error!], color: AppColors.danger, icon: Icons.error_outline_rounded),
      if (widget.canEdit)
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: dprPrimaryButton(),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save contract'),
          ),
        ),
    ]));
  }
}

// ======================================================================
// Sources: which Team Flow / equipment sites are read
// ======================================================================
class _SourcesTab extends StatefulWidget {
  final Json contract;
  final Json? src;
  final bool canEdit;
  final VoidCallback onSaved;
  const _SourcesTab({required this.contract, required this.src, required this.canEdit, required this.onSaved});

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  late Set<int> _tf = (widget.contract['tf_site_ids'] as List? ?? const []).map((e) => asInt(e)).toSet();
  late Set<int> _eq = (widget.contract['eq_site_ids'] as List? ?? const []).map((e) => asInt(e)).toSet();
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await DprApi.updateContract(asInt(widget.contract['contract_id']), {'tf_site_ids': _tf.toList(), 'eq_site_ids': _eq.toList()});
      if (mounted) dprSnack(context, 'Sources saved.');
      widget.onSaved();
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.src;
    if (!widget.canEdit) {
      return const DprMessage(icon: Icons.lock_outline_rounded, text: 'Only an account with the Setup permission can see and change the sources.');
    }
    if (src == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final tfSites = asList(src['tf_sites']);
    final eqSites = asList(src['eq_sites']);
    return ListView(padding: const EdgeInsets.all(14), children: [
      const DprBanner(
        lines: ['The report READS these sites only. People on site come from the attendance of the Team Flow sites; '
            'machines on site from the equipment system. Nothing is written to either system.'],
        color: AppColors.primary,
        icon: Icons.info_outline_rounded,
      ),
      DprCard(
        title: 'Team Flow sites (manpower)',
        icon: Icons.location_city_rounded,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tfSites.map((s) {
            final id = asInt(s['site_id']);
            return FilterChip(
              label: Text('${str(s['site_name'])}${str(s['status']) == 'Active' ? '' : ' (${str(s['status'])})'}'),
              tooltip: [str(s['project_name']), str(s['contract_name'])].where((x) => x.isNotEmpty).join(' · '),
              selected: _tf.contains(id),
              selectedColor: AppColors.primary.withValues(alpha: 0.12),
              checkmarkColor: AppColors.primary,
              onSelected: (v) => setState(() => v ? _tf.add(id) : _tf.remove(id)),
            );
          }).toList(),
        ),
      ),
      DprCard(
        title: 'Equipment system sites (plant)',
        icon: Icons.precision_manufacturing_rounded,
        child: src['equipment_connected'] != true
            ? Text(str(src['equipment_error']).isEmpty ? 'The equipment system is not connected.' : str(src['equipment_error']),
                style: const TextStyle(color: AppColors.danger))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: eqSites.map((s) {
                  final id = asInt(s['site_id']);
                  return FilterChip(
                    label: Text('${str(s['site_code'])} · ${str(s['site_name'])}'),
                    selected: _eq.contains(id),
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.primary,
                    onSelected: (v) => setState(() => v ? _eq.add(id) : _eq.remove(id)),
                  );
                }).toList(),
              ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(style: dprPrimaryButton(), onPressed: _busy ? null : _save, icon: const Icon(Icons.save_rounded), label: const Text('Save sources')),
      ),
    ]);
  }
}

// ======================================================================
// VO / EOT
// ======================================================================
class _EotTab extends StatelessWidget {
  final int contractId;
  final List<Json> rows;
  final Json totals;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const _EotTab({required this.contractId, required this.rows, required this.totals, required this.canEdit, required this.onChanged});

  Future<void> _edit(BuildContext context, [Json? row]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _EotDialog(contractId: contractId, row: row));
    if (saved == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      AppDataTableCard(
        title: 'Variation orders & extensions of time',
        subtitle: 'Approved EOT: ${str(totals['approved_eot_days'])} days · approved VO: ${fmtQty(totals['approved_vo'])}',
        icon: Icons.event_repeat_rounded,
        emptyMessage: 'No VO / EOT.',
        trailing: canEdit
            ? ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add'))
            : null,
        columns: [dprCol('Description'), dprCol('Ref No.'), dprCol('Type'), dprCol('Days'), dprCol('Value'), dprCol('Approval'), dprCol('Status'), dprCol('')],
        rows: rows
            .map((r) => DataRow(cells: [
                  DataCell(dprCell(str(r['description']), width: 260, bold: true)),
                  DataCell(dprCell(str(r['ref_no']))),
                  DataCell(dprCell(str(r['type']))),
                  DataCell(dprCell(str(r['days_granted']))),
                  DataCell(dprCell(fmtQty(r['value']))),
                  DataCell(dprCell(fmtDay(r['approval_date']))),
                  DataCell(StatusBadge.fromStatus(str(r['status']))),
                  DataCell(canEdit
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _edit(context, r)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                            onPressed: () async {
                              if (await dprConfirm(context, 'Delete', 'Delete "${str(r['description'])}"?', ok: 'Delete', danger: true)) {
                                try {
                                  await DprApi.deleteEotVo(contractId, asInt(r['eot_vo_id']));
                                  await onChanged();
                                } catch (e) {
                                  if (context.mounted) dprSnack(context, e.toString(), error: true);
                                }
                              }
                            },
                          ),
                        ])
                      : const SizedBox.shrink()),
                ]))
            .toList(),
      ),
    ]);
  }
}

class _EotDialog extends StatefulWidget {
  final int contractId;
  final Json? row;
  const _EotDialog({required this.contractId, required this.row});

  @override
  State<_EotDialog> createState() => _EotDialogState();
}

class _EotDialogState extends State<_EotDialog> {
  late final TextEditingController _desc = TextEditingController(text: str(widget.row?['description']));
  late final TextEditingController _ref = TextEditingController(text: str(widget.row?['ref_no']));
  late final TextEditingController _days = TextEditingController(text: str(widget.row?['days_granted']));
  late final TextEditingController _value = TextEditingController(text: str(widget.row?['value']));
  late String _type = str(widget.row?['type']).isEmpty ? 'EOT' : str(widget.row?['type']);
  late String _status = str(widget.row?['status']).isEmpty ? 'Pending' : str(widget.row?['status']);
  late DateTime? _date = str(widget.row?['approval_date']).isEmpty ? null : parseYmd(str(widget.row?['approval_date']));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _desc.dispose();
    _ref.dispose();
    _days.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.saveEotVo(widget.contractId, widget.row == null ? null : asInt(widget.row!['eot_vo_id']), {
        'description': _desc.text.trim(),
        'ref_no': _ref.text.trim(),
        'type': _type,
        'days_granted': _days.text.trim().isEmpty ? 0 : _days.text.trim(),
        'value': _value.text.trim().isEmpty ? '0' : _value.text.trim(),
        'approval_date': _date == null ? null : ymd(_date!),
        'status': _status,
        'sort_order': widget.row?['sort_order'] ?? 0,
      });
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
    return AlertDialog(
      title: Text(widget.row == null ? 'New VO / EOT' : 'Edit VO / EOT'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _desc, decoration: dprInput('Description')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _ref, decoration: dprInput('Ref No.'))),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _type,
                decoration: dprInput('Type'),
                items: const [DropdownMenuItem(value: 'EOT', child: Text('EOT')), DropdownMenuItem(value: 'VO', child: Text('VO'))],
                onChanged: (v) => setState(() => _type = v ?? 'EOT'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: dprInput('Days granted'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                decoration: dprInput('Value'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final p = await showDatePicker(context: context, initialDate: _date ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
                  if (p != null) setState(() => _date = p);
                },
                child: InputDecorator(decoration: dprInput('Approval date'), child: Text(_date == null ? '—' : fmtDay(ymd(_date!)))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: dprInput('Status'),
                items: const ['Approved', 'Pending', 'Rejected'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _status = v ?? 'Pending'),
              ),
            ),
          ]),
          if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: AppColors.danger))],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ======================================================================
// Resource lines (trades / plant / subcontractors)
// ======================================================================
class _LinesTab extends StatelessWidget {
  final int contractId;
  final String kind;
  final List<Json> lines;
  final Json? src;
  final Json lists;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const _LinesTab({required this.contractId, required this.kind, required this.lines, required this.src, required this.lists, required this.canEdit, required this.onChanged});

  String get title => const {
        'staff': 'Staff – positions',
        'trade': 'Tradesmen – trades',
        'plant': 'Plant & equipment',
        'tool': 'Tools',
        'subcon': 'Subcontractor resource lines',
      }[kind]!;
  String get nameLabel => const {'staff': 'Position', 'trade': 'Trade', 'plant': 'Equipment', 'tool': 'Tool', 'subcon': 'Resource'}[kind]!;

  Future<void> _loadDefaults(BuildContext context) async {
    if (!await dprConfirm(context, 'The client\'s rows', 'Add the rows of the client\'s form that this contract does not have yet? '
        'Rows whose name is a position / equipment type of the systems are counted from them; the others are typed.')) {
      return;
    }
    try {
      final r = await DprApi.loadDefaultLines(contractId, [kind]);
      if (context.mounted) dprSnack(context, '${str(r[kind])} row(s) added.');
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(BuildContext context, [Json? line]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LineDialog(contractId: contractId, kind: kind, line: line, src: src, lists: lists),
    );
    if (saved == true) await onChanged();
  }

  Future<void> _move(BuildContext context, List<Json> mine, int i, int d) async {
    final j = i + d;
    if (j < 0 || j >= mine.length) return;
    final ids = mine.map((l) => asInt(l['line_id'])).toList();
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    try {
      await DprApi.reorderLines(contractId, kind, ids);
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  String _mapText(Json m) {
    final tf = (m['tf'] as List? ?? const []).map((e) => e.toString()).toList();
    final sp = (m['sp'] as List? ?? const []).map((e) => e.toString()).toList();
    final eq = asList(m['eq']).map((e) => str(e['vendor']).isEmpty ? str(e['type']) : '${str(e['type'])} (${str(e['vendor'])})').toList();
    final parts = <String>[
      if (tf.isNotEmpty) 'Team Flow: ${tf.join(', ')}',
      if (sp.isNotEmpty) 'Staff list: ${sp.join(', ')}',
      if (eq.isNotEmpty) 'Equipment: ${eq.join(', ')}',
    ];
    return parts.isEmpty ? 'Typed every day' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final mine = lines.where((l) => l['kind'] == kind).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      AppDataTableCard(
        title: title,
        subtitle: 'The order here is the order in the report. A line with a source is counted from the systems; without a source it is typed every day.',
        icon: kind == 'trade' || kind == 'staff'
            ? Icons.engineering_rounded
            : (kind == 'plant' || kind == 'tool' ? Icons.precision_manufacturing_rounded : Icons.handshake_rounded),
        emptyMessage: kind == 'subcon' ? 'No line yet.' : 'No row yet. Add rows, or load the rows of the client\'s form.',
        trailing: canEdit
            ? Wrap(spacing: 8, children: [
                if (kind != 'subcon')
                  OutlinedButton.icon(
                      onPressed: () => _loadDefaults(context), icon: const Icon(Icons.playlist_add_rounded, size: 18), label: const Text('Client\'s rows')),
                ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add row')),
              ])
            : null,
        columns: [
          dprCol('#'),
          if (kind == 'subcon') dprCol('Subcontractor'),
          dprCol(nameLabel),
          dprCol(kind == 'trade' || kind == 'staff' ? 'Category' : (kind == 'plant' || kind == 'tool' ? 'Ownership' : 'Type')),
          dprCol('Counted from'),
          dprCol('Opening days'),
          dprCol('Active'),
          dprCol(''),
        ],
        rows: mine.asMap().entries.map((e) {
          final l = e.value;
          return DataRow(cells: [
            DataCell(dprCell('${e.key + 1}')),
            if (kind == 'subcon') DataCell(dprCell(str(l['subcontractor']), bold: true, width: 160)),
            DataCell(dprCell(str(l['name']), bold: true, width: 170)),
            DataCell(dprCell(kind == 'trade' || kind == 'staff' ? str(l['category']) : (kind == 'plant' || kind == 'tool' ? str(l['ownership']) : str(l['res_type'])))),
            DataCell(dprCell(_mapText(asJson(l['source_map'])), width: 280, color: AppColors.textSecondary)),
            DataCell(dprCell(fmtQty(l['opening_days']))),
            DataCell(Switch(
              value: l['is_active'] == true,
              activeThumbColor: AppColors.primary,
              onChanged: canEdit
                  ? (v) async {
                      try {
                        await DprApi.setLineActive(contractId, asInt(l['line_id']), v);
                        await onChanged();
                      } catch (err) {
                        if (context.mounted) dprSnack(context, err.toString(), error: true);
                      }
                    }
                  : null,
            )),
            DataCell(canEdit
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Up', icon: const Icon(Icons.arrow_upward_rounded, size: 17), onPressed: () => _move(context, mine, e.key, -1)),
                    IconButton(tooltip: 'Down', icon: const Icon(Icons.arrow_downward_rounded, size: 17), onPressed: () => _move(context, mine, e.key, 1)),
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _edit(context, l)),
                  ])
                : const SizedBox.shrink()),
          ]);
        }).toList(),
      ),
    ]);
  }
}

class _LineDialog extends StatefulWidget {
  final int contractId;
  final String kind;
  final Json? line;
  final Json? src;
  final Json lists;
  const _LineDialog({required this.contractId, required this.kind, required this.line, required this.src, required this.lists});

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final TextEditingController _name = TextEditingController(text: str(widget.line?['name']));
  late final TextEditingController _sub = TextEditingController(text: str(widget.line?['subcontractor']));
  late final TextEditingController _scope = TextEditingController(text: str(widget.line?['scope']));
  late final TextEditingController _cat = TextEditingController(text: str(widget.line?['category']));
  late final TextEditingController _opening = TextEditingController(text: _trim(str(widget.line?['opening_days'])));
  late String _ownership = str(widget.line?['ownership']).isEmpty ? 'Own' : str(widget.line?['ownership']);
  late String _resType = str(widget.line?['res_type']).isEmpty ? 'Manpower' : str(widget.line?['res_type']);
  late final List<String> _tf = (asJson(widget.line?['source_map'])['tf'] as List? ?? const []).map((e) => e.toString()).toList();
  late final List<String> _sp = (asJson(widget.line?['source_map'])['sp'] as List? ?? const []).map((e) => e.toString()).toList();
  late final List<Json> _eq = asList(asJson(widget.line?['source_map'])['eq']);
  final TextEditingController _tfOther = TextEditingController();
  String? _eqType;
  String? _eqVendor;
  bool _busy = false;
  String? _error;

  static String _trim(String s) {
    if (!s.contains('.')) return s == '0' ? '' : s;
    var t = s.replaceFirst(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    return t == '0' ? '' : t;
  }

  @override
  void dispose() {
    _name.dispose();
    _sub.dispose();
    _scope.dispose();
    _cat.dispose();
    _opening.dispose();
    _tfOther.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, dynamic>{
      'kind': widget.kind,
      'name': _name.text.trim(),
      'sort_order': widget.line?['sort_order'],
      'opening_days': _opening.text.trim().isEmpty ? '0' : _opening.text.trim(),
      'source_map': {'tf': _tf, 'sp': _sp, 'eq': _eq},
      'is_active': widget.line == null ? true : widget.line!['is_active'] == true,
      if (widget.kind == 'trade' || widget.kind == 'staff') 'category': _cat.text.trim(),
      if (widget.kind == 'plant' || widget.kind == 'tool') 'ownership': _ownership,
      if (widget.kind == 'subcon') 'subcontractor': _sub.text.trim(),
      if (widget.kind == 'subcon') 'res_type': _resType,
      if (widget.kind == 'subcon') 'scope': _scope.text.trim(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.saveLine(widget.contractId, widget.line == null ? null : asInt(widget.line!['line_id']), body);
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
    final src = widget.src;
    final positions = asList(src?['tf_positions']);
    final types = asList(src?['eq_types']).map((t) => str(t['type_name'])).toList();
    final vendors = asList(src?['eq_vendors']).map((v) => str(v['vendor_name'])).toList();
    final cats = (widget.lists['categories'] as List? ?? const []).map((e) => e.toString()).toList();
    final usesTf = widget.kind == 'trade' || (widget.kind == 'subcon' && _resType == 'Manpower');
    final usesSp = widget.kind == 'staff';
    final usesEq = widget.kind == 'plant' || widget.kind == 'tool' || (widget.kind == 'subcon' && _resType == 'Plant');
    final staffPos = asList(src?['sp_positions']);
    return AlertDialog(
      title: Text(widget.line == null ? 'New line' : 'Edit line'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.kind == 'subcon') ...[
              TextField(controller: _sub, enabled: !_busy, decoration: dprInput('Subcontractor')),
              const SizedBox(height: 10),
            ],
            TextField(
                controller: _name,
                enabled: !_busy,
                decoration: dprInput(const {
                  'staff': 'Position (as printed)',
                  'trade': 'Trade / designation',
                  'plant': 'Equipment',
                  'tool': 'Tool',
                  'subcon': 'Resource',
                }[widget.kind]!)),
            const SizedBox(height: 10),
            if (widget.kind == 'trade') ...[
              TextField(controller: _cat, enabled: !_busy, decoration: dprInput('Category (Staff, Supervision, Skilled…)')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: cats
                    .map((c) => ActionChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          onPressed: _busy ? null : () => setState(() => _cat.text = c),
                        ))
                    .toList(),
              ),
            ],
            if (widget.kind == 'plant' || widget.kind == 'tool')
              DropdownButtonFormField<String>(
                value: _ownership,
                decoration: dprInput('Ownership'),
                items: const [DropdownMenuItem(value: 'Own', child: Text('Own')), DropdownMenuItem(value: 'Hired', child: Text('Hired'))],
                onChanged: _busy ? null : (v) => setState(() => _ownership = v ?? 'Own'),
              ),
            if (widget.kind == 'subcon')
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _resType,
                    decoration: dprInput('Type'),
                    items: const [DropdownMenuItem(value: 'Manpower', child: Text('Manpower')), DropdownMenuItem(value: 'Plant', child: Text('Plant'))],
                    onChanged: _busy ? null : (v) => setState(() => _resType = v ?? 'Manpower'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _scope, enabled: !_busy, decoration: dprInput('Scope / package'))),
              ]),
            const SizedBox(height: 10),
            TextField(
              controller: _opening,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: dprInput('Opening man/equipment-days (before the system, optional)'),
            ),
            const Divider(height: 26),
            const Text('Counted from the systems (leave empty to type the number every day)',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 4),
            if (src == null)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary)),
            if (usesTf) ...[
              const SizedBox(height: 6),
              const Text('Team Flow positions (people on site with these positions):', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...positions.map((p) {
                  final n = str(p['name']);
                  final on = _tf.any((x) => x.toLowerCase() == n.toLowerCase());
                  return FilterChip(
                    label: Text('$n (${asInt(p['workers']) + asInt(p['staff'])})'),
                    selected: on,
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.primary,
                    onSelected: _busy
                        ? null
                        : (v) => setState(() {
                              if (v) {
                                _tf.add(n);
                              } else {
                                _tf.removeWhere((x) => x.toLowerCase() == n.toLowerCase());
                              }
                            }),
                  );
                }),
                ..._tf.where((t) => !positions.any((p) => str(p['name']).toLowerCase() == t.toLowerCase())).map((t) => InputChip(
                      label: Text(t),
                      onDeleted: _busy ? null : () => setState(() => _tf.remove(t)),
                    )),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextField(controller: _tfOther, decoration: dprInput('Other position name'))),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    final t = _tfOther.text.trim();
                    if (t.isNotEmpty && !_tf.any((x) => x.toLowerCase() == t.toLowerCase())) setState(() => _tf.add(t));
                    _tfOther.clear();
                  },
                  child: const Text('Add'),
                ),
              ]),
            ],
            if (usesSp) ...[
              const SizedBox(height: 6),
              const Text('Staff positions (the number of staff with these positions; counts only, no names):', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...staffPos.map((p) {
                  final n = str(p['name']);
                  final on = _sp.any((x) => x.toLowerCase() == n.toLowerCase());
                  return FilterChip(
                    label: Text('$n (${asInt(p['staff'])})'),
                    selected: on,
                    selectedColor: AppColors.primary.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.primary,
                    onSelected: _busy
                        ? null
                        : (v) => setState(() {
                              if (v) {
                                _sp.add(n);
                              } else {
                                _sp.removeWhere((x) => x.toLowerCase() == n.toLowerCase());
                              }
                            }),
                  );
                }),
                ..._sp.where((t) => !staffPos.any((p) => str(p['name']).toLowerCase() == t.toLowerCase())).map((t) => InputChip(
                      label: Text(t),
                      onDeleted: _busy ? null : () => setState(() => _sp.remove(t)),
                    )),
              ]),
              const SizedBox(height: 4),
              const Text('Several positions on one row are added together (e.g. SURVEY ENGINEER + CHIEF SURVEY ENGINEER).',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ],
            if (usesEq) ...[
              const SizedBox(height: 10),
              const Text('Equipment types (machines on site: Working + Standby + Breakdown). Vendor optional:', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _eq
                    .map((e) => InputChip(
                          label: Text(str(e['vendor']).isEmpty ? str(e['type']) : '${str(e['type'])} – ${str(e['vendor'])}'),
                          onDeleted: _busy ? null : () => setState(() => _eq.remove(e)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _eqType,
                    isExpanded: true,
                    decoration: dprInput('Type'),
                    items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _eqType = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _eqVendor,
                    isExpanded: true,
                    decoration: dprInput('Vendor (any)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Any vendor')),
                      ...vendors.map((v) => DropdownMenuItem<String?>(value: v, child: Text(v))),
                    ],
                    onChanged: (v) => setState(() => _eqVendor = v),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _eqType == null
                      ? null
                      : () => setState(() {
                            _eq.add({'type': _eqType, 'vendor': _eqVendor});
                            _eqType = null;
                            _eqVendor = null;
                          }),
                  child: const Text('Add'),
                ),
              ]),
            ],
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))],
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

// ======================================================================
// BOQ
// ======================================================================
class _BoqTab extends StatelessWidget {
  final int contractId;
  final List<Json> rows;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const _BoqTab({required this.contractId, required this.rows, required this.canEdit, required this.onChanged});

  Future<void> _edit(BuildContext context, [Json? row]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _BoqDialog(contractId: contractId, row: row));
    if (saved == true) await onChanged();
  }

  Future<void> _import(BuildContext context) async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Excel', extensions: ['xlsx'])]);
    if (f == null) return;
    try {
      final bytes = await f.readAsBytes();
      final r = await DprApi.importBoq(contractId, bytes, f.name);
      if (context.mounted) {
        dprSnack(context, 'BOQ imported: ${str(r['added'])} added, ${str(r['updated'])} updated, ${str(r['headings'])} heading / text rows.');
      }
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _move(BuildContext context, int i, int d) async {
    final j = i + d;
    if (j < 0 || j >= rows.length) return;
    final ids = rows.map((r) => asInt(r['boq_id'])).toList();
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    try {
      await DprApi.reorderBoq(contractId, ids);
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(BuildContext context, Json r) async {
    if (!await dprConfirm(context, 'Delete BOQ row', 'Delete "${str(r['description'])}"? (An item used in activities cannot be deleted: switch it off.)',
        ok: 'Delete', danger: true)) {
      return;
    }
    try {
      await DprApi.deleteBoq(contractId, asInt(r['boq_id']));
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      AppDataTableCard(
        title: 'Bill of quantities',
        subtitle: '${rows.where((r) => str(r['row_type']) == 'item').length} items · headings and text rows print as in the client\'s form. '
            'Excel columns: Row type, Group, Item No., Cost Code, Description, Unit, Quantity, Budget, Rate, Done before.',
        icon: Icons.list_alt_rounded,
        emptyMessage: 'No BOQ row. Add them one by one or import an Excel file.',
        trailing: canEdit
            ? Wrap(spacing: 8, children: [
                OutlinedButton.icon(onPressed: () => _import(context), icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Import Excel')),
                ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add item')),
              ])
            : null,
        columns: [dprCol('Group'), dprCol('Item No.'), dprCol('Description'), dprCol('Unit'), dprCol('Contract Qty'), dprCol('Budget'), dprCol('Rate'),
          dprCol('Done before'), dprCol('Remarks'), dprCol('Active'), dprCol('')],
        rows: rows.asMap().entries.map((en) {
          final r = en.value;
          final heading = str(r['row_type']) == 'section';
          final text = str(r['row_type']) == 'text';
          return DataRow(
                color: WidgetStateProperty.all(heading ? const Color(0xffe2efda) : (text ? AppColors.background : null)),
                cells: [
                  DataCell(dprCell(str(r['group_name']).isEmpty ? '—' : str(r['group_name']), color: AppColors.textSecondary)),
                  DataCell(dprCell(heading || text ? (heading ? 'Heading' : 'Text') : str(r['item_no']), bold: !text)),
                  DataCell(dprCell(str(r['description']), width: 300, bold: heading)),
                  DataCell(dprCell(str(r['unit']))),
                  DataCell(dprCell(fmtQty(r['contract_qty']))),
                  DataCell(dprCell(fmtQty(r['budget']))),
                  DataCell(dprCell(fmtQty(r['rate']))),
                  DataCell(dprCell(fmtQty(r['opening_qty'], dash: true))),
                  DataCell(dprCell(str(r['remarks']), width: 160)),
                  DataCell(Icon(r['is_active'] == true ? Icons.check_circle_rounded : Icons.cancel_outlined,
                      size: 18, color: r['is_active'] == true ? const Color(0xff047857) : AppColors.textSecondary)),
                  DataCell(canEdit
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Up', icon: const Icon(Icons.arrow_upward_rounded, size: 17), onPressed: () => _move(context, en.key, -1)),
                          IconButton(tooltip: 'Down', icon: const Icon(Icons.arrow_downward_rounded, size: 17), onPressed: () => _move(context, en.key, 1)),
                          IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _edit(context, r)),
                          IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), onPressed: () => _delete(context, r)),
                        ])
                      : const SizedBox.shrink()),
                ]);
        }).toList(),
      ),
    ]);
  }
}

class _BoqDialog extends StatefulWidget {
  final int contractId;
  final Json? row;
  const _BoqDialog({required this.contractId, required this.row});

  @override
  State<_BoqDialog> createState() => _BoqDialogState();
}

class _BoqDialogState extends State<_BoqDialog> {
  static String _t(String s) {
    if (!s.contains('.')) return s;
    var t = s.replaceFirst(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    return t;
  }

  late final Map<String, TextEditingController> _c = {
    'item_no': TextEditingController(text: str(widget.row?['item_no'])),
    'description': TextEditingController(text: str(widget.row?['description'])),
    'unit': TextEditingController(text: str(widget.row?['unit'])),
    'contract_qty': TextEditingController(text: _t(str(widget.row?['contract_qty']))),
    'rate': TextEditingController(text: _t(str(widget.row?['rate']))),
    'budget': TextEditingController(text: _t(str(widget.row?['budget']))),
    'group_name': TextEditingController(text: str(widget.row?['group_name'])),
    'cost_code': TextEditingController(text: str(widget.row?['cost_code'])),
    'opening_qty': TextEditingController(text: _t(str(widget.row?['opening_qty'])) == '0' ? '' : _t(str(widget.row?['opening_qty']))),
    'remarks': TextEditingController(text: str(widget.row?['remarks'])),
  };
  late bool _active = widget.row == null || widget.row!['is_active'] == true;
  late String _type = str(widget.row?['row_type']).isEmpty ? 'item' : str(widget.row?['row_type']);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.saveBoq(widget.contractId, widget.row == null ? null : asInt(widget.row!['boq_id']), {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'row_type': _type,
        'sort_order': widget.row?['sort_order'] ?? 0,
        'is_active': _active,
      });
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
    TextField numField(String k, String label) => TextField(
          controller: _c[k],
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: dprInput(label),
        );
    return AlertDialog(
      title: Text(widget.row == null ? 'New BOQ row' : 'Edit BOQ row'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, children: [
              for (final t in const [('item', 'Item (quantities)'), ('section', 'Heading'), ('text', 'Text / scope')])
                ChoiceChip(label: Text(t.$2), selected: _type == t.$1, onSelected: _busy ? null : (_) => setState(() => _type = t.$1)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              if (_type == 'item') ...[
                Expanded(child: TextField(controller: _c['item_no'], enabled: !_busy, decoration: dprInput('Item No. / Task code'))),
                const SizedBox(width: 10),
              ],
              Expanded(child: TextField(controller: _c['cost_code'], enabled: !_busy, decoration: dprInput('Cost code'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _c['unit'], enabled: !_busy, decoration: dprInput('Unit'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _c['group_name'], enabled: !_busy, decoration: dprInput('Group (empty = main BOQ, e.g. ADDITIONAL WORKS)')),
            const SizedBox(height: 10),
            TextField(controller: _c['description'], enabled: !_busy, minLines: 2, maxLines: 4, decoration: dprInput('Description')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: numField('contract_qty', _type == 'item' ? 'Contract Qty' : 'Quantity shown (optional)')),
              if (_type == 'item') ...[
                const SizedBox(width: 10),
                Expanded(child: numField('budget', 'Budget (optional)')),
                const SizedBox(width: 10),
                Expanded(child: numField('rate', 'Rate (optional)')),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              if (_type == 'item') ...[
                Expanded(child: numField('opening_qty', 'Done before the system (optional)')),
                const SizedBox(width: 10),
              ],
              Expanded(child: TextField(controller: _c['remarks'], enabled: !_busy, decoration: dprInput('Remarks'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active (can be chosen for new activities)'),
              value: _active,
              activeThumbColor: AppColors.primary,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
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

// ======================================================================
// New contract / copy setup
// ======================================================================
class _NewContractDialog extends StatefulWidget {
  const _NewContractDialog();

  @override
  State<_NewContractDialog> createState() => _NewContractDialogState();
}

class _NewContractDialogState extends State<_NewContractDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _title = TextEditingController();
  DateTime? _start;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await DprApi.createContract({
        'code': _code.text.trim(),
        'title': _title.text.trim(),
        if (_start != null) 'commencement_date': ymd(_start!),
      });
      if (mounted) Navigator.pop(context, r);
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
    return AlertDialog(
      title: const Text('New contract'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Each contract has its own report, numbering, data and archive.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: _code, decoration: dprInput('Code shown on the tab (e.g. 71)')),
          const SizedBox(height: 10),
          TextField(controller: _title, decoration: dprInput('Title (e.g. T2 above ground)')),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
              if (p != null) setState(() => _start = p);
            },
            child: InputDecorator(decoration: dprInput('Commencement date'), child: Text(_start == null ? '—' : fmtDay(ymd(_start!)))),
          ),
          if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: AppColors.danger))],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Create')),
      ],
    );
  }
}

class _CopySetupChoice {
  final int fromId;
  final List<String> parts;
  const _CopySetupChoice(this.fromId, this.parts);
}

class _CopySetupDialog extends StatefulWidget {
  final List<Json> contracts;
  const _CopySetupDialog({required this.contracts});

  @override
  State<_CopySetupDialog> createState() => _CopySetupDialogState();
}

class _CopySetupDialogState extends State<_CopySetupDialog> {
  late int _from = asInt(widget.contracts.first['contract_id']);
  final Set<String> _parts = {'lines', 'boq'};
  static const _labels = {
    'info': 'Contract information (overwrites the current one)',
    'eot_vo': 'VO / EOT log (only if empty here)',
    'lines': 'Trades, plant and subcontractor lines with their sources (only if empty here)',
    'boq': 'BOQ (only if empty here)',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy setup from another contract'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('A COPY is made: afterwards the two contracts are independent.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _from,
            decoration: dprInput('Copy from'),
            items: widget.contracts.map((c) => DropdownMenuItem(value: asInt(c['contract_id']), child: Text('${str(c['code'])} · ${str(c['title'])}'))).toList(),
            onChanged: (v) => setState(() => _from = v ?? _from),
          ),
          ..._labels.entries.map((e) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
                value: _parts.contains(e.key),
                title: Text(e.value, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => v == true ? _parts.add(e.key) : _parts.remove(e.key)),
              )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: dprPrimaryButton(),
          onPressed: _parts.isEmpty ? null : () => Navigator.pop(context, _CopySetupChoice(_from, _parts.toList())),
          child: const Text('Copy'),
        ),
      ],
    );
  }
}
