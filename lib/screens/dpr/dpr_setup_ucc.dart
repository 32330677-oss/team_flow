// lib/screens/dpr/dpr_setup_ucc.dart
//
// Setup of the client's form (UCC-IMS-CM-3003A) for a contract:
//   * DprUccContractCard  form texts, system start date, attendance counting,
//                         automatic rows, "same as" another contract per section,
//                         choice lists
//   * DprAreasTab         areas / bridges with their own pages
//   * DprFixedPagesTab    cover, maps, sections printed every day
//   * DprLayoutTab        what is printed by default (each day can change it)
// Nothing here is fixed in the app: every text is a default the QC can change.

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import 'dpr_ucc_widgets.dart';
import 'dpr_widgets.dart';

// ---------------------------------------------------------------------------
// Contract: the client's form
// ---------------------------------------------------------------------------
class DprUccContractCard extends StatefulWidget {
  final Json contract;
  final List<Json> contracts;
  final Json ucc;
  final bool enabled;
  const DprUccContractCard({super.key, required this.contract, required this.contracts, required this.ucc, required this.enabled});

  @override
  State<DprUccContractCard> createState() => DprUccContractCardState();
}

const _formFields = [
  ('report_title', 'Report title ({code} = contract code)', 420.0),
  ('project_ref', 'Project Ref.', 260.0),
  ('contract_ref', 'Contract (signed contract ref.)', 260.0),
  ('project_manager', 'Project Manager', 260.0),
  ('doc_ref', 'Document Reference', 260.0),
  ('rev_no', 'Rev. No.', 120.0),
  ('rev_date', 'Rev. Date (YYYY-MM-DD)', 180.0),
  ('system_title', 'Header line 1', 260.0),
  ('department', 'Header line 2', 260.0),
  ('form_title', 'Header line 3', 260.0),
  ('footer_note', 'Footer note (optional)', 530.0),
];
const _linkLabels = {
  'weather': 'Weather',
  'manpower': 'Manpower (staff | tradesmen)',
  'plant': 'Plant | tools',
  'materials': 'Delivered materials',
  'wir': 'WIR register',
  'notes': 'General remarks',
};
const _modeLabels = {
  'recorded': 'Any attendance record (draft, submitted, approved)',
  'checked_in': 'Present only with a check-in time',
  'approved': 'Approved records only',
};
const _listLabels = {
  'weather_conditions': 'Weather choices',
  'humidity_levels': 'Humidity choices',
  'wir_status': 'WIR status choices',
  'units': 'Units',
};

class DprUccContractCardState extends State<DprUccContractCard> {
  late final Map<String, TextEditingController> _form = {
    for (final f in _formFields) f.$1: TextEditingController(text: str(asJson(widget.contract['form'])[f.$1])),
  };
  late final Map<String, TextEditingController> _lists = {
    for (final k in _listLabels.keys)
      k: TextEditingController(text: (asJson(widget.contract['lists'])[k] as List? ?? const []).map((e) => e.toString()).join(', ')),
  };
  late String _template = str(widget.contract['template']).isEmpty ? 'ucc' : str(widget.contract['template']);
  late String _mode = str(widget.contract['count_mode']).isEmpty ? 'recorded' : str(widget.contract['count_mode']);
  late bool _auto = widget.contract['auto_rows'] != false;
  late DateTime? _sysStart = str(widget.contract['system_start_date']).isEmpty ? null : parseYmd(str(widget.contract['system_start_date']));
  late final Map<String, int?> _links = {
    for (final k in _linkLabels.keys)
      k: asJson(widget.contract['section_links'])[k] == null ? null : asInt(asJson(widget.contract['section_links'])[k]),
  };

  /// What this card adds to the contract's save.
  Json values() => {
        'template': _template,
        'form': {for (final e in _form.entries) e.key: e.value.text.trim()},
        'system_start_date': _sysStart == null ? null : ymd(_sysStart!),
        'count_mode': _mode,
        'auto_rows': _auto,
        'section_links': {for (final e in _links.entries) if (e.value != null) e.key: e.value},
        'lists': {
          for (final e in _lists.entries) e.key: e.value.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
        },
      };

  @override
  void dispose() {
    for (final c in [..._form.values, ..._lists.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final others = widget.contracts.where((c) => asInt(c['contract_id']) != asInt(widget.contract['contract_id'])).toList();
    final en = widget.enabled;
    return DprCard(
      title: 'Report form & how figures are read',
      subtitle: 'One day page for both designs: the PDF / Excel asks "Client\'s form" or "Our design". Saved with "Save contract".',
      icon: Icons.assignment_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Client\'s form (UCC)'), selected: _template == 'ucc', onSelected: en ? (_) => setState(() => _template = 'ucc') : null),
          // the old workbook (its own day page) stays for contracts already on it; "our design" is chosen when printing
          if (str(widget.contract['template']) == 'dpr')
            ChoiceChip(label: const Text('DPR workbook (old)'), selected: _template == 'dpr', onSelected: en ? (_) => setState(() => _template = 'dpr') : null),
        ]),
        const SizedBox(height: 12),
        if (_template == 'ucc') ...[
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final f in _formFields)
              SizedBox(width: f.$3, child: TextField(controller: _form[f.$1], enabled: en, decoration: dprInput(f.$2))),
          ]),
          const Divider(height: 28),
        ],
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 300,
            child: InkWell(
              onTap: !en
                  ? null
                  : () async {
                      final p = await showDatePicker(context: context, initialDate: _sysStart ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2100));
                      if (p != null) setState(() => _sysStart = p);
                    },
              child: InputDecorator(
                decoration: dprInput('System start date (before: opening balances)',
                    suffix: _sysStart == null
                        ? const Icon(Icons.event_rounded, size: 18)
                        : IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: en ? () => setState(() => _sysStart = null) : null)),
                child: Text(_sysStart == null ? 'Commencement date' : fmtDay(ymd(_sysStart!))),
              ),
            ),
          ),
          SizedBox(
            width: 380,
            child: DropdownButtonFormField<String>(
              initialValue: _mode,
              isExpanded: true,
              decoration: dprInput('Attendance counted'),
              items: _modeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: en ? (v) => setState(() => _mode = v ?? _mode) : null,
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: _auto, onChanged: en ? (v) => setState(() => _auto = v) : null),
            const Text('Positions / types without a row get an automatic row'),
          ]),
        ]),
        const Divider(height: 28),
        const Text('Same as another contract (e.g. 26 = 71 for weather and manpower)', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('A section that follows another contract shows that contract\'s figures and is changed there. Empty = own figures.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in _linkLabels.keys)
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: _links[k],
                isExpanded: true,
                decoration: dprInput(_linkLabels[k]!),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Own figures')),
                  ...others.map((c) => DropdownMenuItem<int?>(value: asInt(c['contract_id']), child: Text('Same as ${str(c['code'])}'))),
                ],
                onChanged: en ? (v) => setState(() => _links[k] = v) : null,
              ),
            ),
        ]),
        const Divider(height: 28),
        const Text('Choice lists (comma separated)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in _listLabels.entries)
            SizedBox(width: 400, child: TextField(controller: _lists[e.key], enabled: en, decoration: dprInput(e.value))),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Areas / bridges
// ---------------------------------------------------------------------------
class DprAreasTab extends StatelessWidget {
  final int contractId;
  final List<Json> areas;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const DprAreasTab({super.key, required this.contractId, required this.areas, required this.canEdit, required this.onChanged});

  Future<void> _edit(BuildContext context, [Json? a]) async {
    final ctl = TextEditingController(text: str(a?['name']));
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(a == null ? 'New area' : 'Rename area'),
        content: SizedBox(width: 380, child: TextField(controller: ctl, autofocus: true, decoration: dprInput('Name (e.g. BRIDGE - 08)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          ElevatedButton(style: dprPrimaryButton(), onPressed: () => Navigator.pop(dCtx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await DprApi.saveArea(contractId, a == null ? null : asInt(a['area_id']), {
        'name': name,
        if (a != null) 'sort_order': a['sort_order'],
        if (a != null) 'is_active': a['is_active'],
      });
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _set(BuildContext context, Json a, Json change) async {
    try {
      await DprApi.saveArea(contractId, asInt(a['area_id']), {'name': a['name'], 'sort_order': a['sort_order'], 'is_active': a['is_active'], ...change});
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  /// Swaps the order of two areas.
  Future<void> _swap(BuildContext context, Json a, Json b) async {
    try {
      await DprApi.saveArea(contractId, asInt(a['area_id']), {'name': a['name'], 'is_active': a['is_active'], 'sort_order': asInt(b['sort_order'])});
      await DprApi.saveArea(contractId, asInt(b['area_id']), {'name': b['name'], 'is_active': b['is_active'], 'sort_order': asInt(a['sort_order'])});
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      AppDataTableCard(
        title: 'Areas / bridges',
        subtitle: 'Each area with activities or photos on a day gets its own page: activity, chainage, plant & tradesmen (No., W-HRS), output, photos.',
        icon: Icons.account_tree_rounded,
        emptyMessage: 'No area. Add one (e.g. BRIDGE - 08) if the report has pages per bridge / zone.',
        trailing: canEdit
            ? ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _edit(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add area'))
            : null,
        columns: [dprCol('#'), dprCol('Name'), dprCol('Active'), dprCol('')],
        rows: areas.asMap().entries.map((e) {
          final a = e.value;
          return DataRow(cells: [
            DataCell(dprCell('${e.key + 1}')),
            DataCell(dprCell(str(a['name']), bold: true, width: 260)),
            DataCell(Switch(value: a['is_active'] == true, onChanged: canEdit ? (v) => _set(context, a, {'is_active': v}) : null)),
            DataCell(canEdit
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Up',
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        onPressed: e.key == 0 ? null : () => _swap(context, areas[e.key - 1], a)),
                    IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _edit(context, a)),
                  ])
                : const SizedBox.shrink()),
          ]);
        }).toList(),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Fixed pages (cover, maps, sections)
// ---------------------------------------------------------------------------
class DprFixedPagesTab extends StatelessWidget {
  final int contractId;
  final List<Json> pages;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const DprFixedPagesTab({super.key, required this.contractId, required this.pages, required this.canEdit, required this.onChanged});

  Future<void> _add(BuildContext context) async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Pictures', extensions: ['jpg', 'jpeg', 'png'])]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    final ctl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Title of the page (optional)'),
        content: SizedBox(width: 380, child: TextField(controller: ctl, decoration: dprInput('e.g. Project location map'))),
        actions: [ElevatedButton(style: dprPrimaryButton(), onPressed: () => Navigator.pop(dCtx, ctl.text.trim()), child: const Text('Add'))],
      ),
    );
    ctl.dispose();
    try {
      await DprApi.addFixedPage(contractId, bytes, f.name, title ?? '');
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _set(BuildContext context, Json p, Json change) async {
    try {
      await DprApi.updateFixedPage(contractId, asInt(p['page_id']), change);
      await onChanged();
    } catch (e) {
      if (context.mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      DprCard(
        title: 'Fixed pages',
        subtitle: 'Printed at the start of every report (the first one under the project information). JPG or PNG; turn a PDF page into a picture first.',
        icon: Icons.map_rounded,
        actions: [
          if (canEdit) ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _add(context), icon: const Icon(Icons.add_photo_alternate_rounded, size: 18), label: const Text('Add page')),
        ],
        child: pages.isEmpty
            ? const Text('No fixed page.', style: TextStyle(color: AppColors.textSecondary))
            : Wrap(spacing: 12, runSpacing: 12, children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    width: 220,
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(height: 130, child: _PageThumb(contractId: contractId, pageId: asInt(pages[i]['page_id']))),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${i + 1}. ${str(pages[i]['title']).isEmpty ? 'Page' : str(pages[i]['title'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Row(children: [
                            Switch(value: pages[i]['is_active'] == true, onChanged: canEdit ? (v) => _set(context, pages[i], {'is_active': v}) : null),
                            Text(pages[i]['is_active'] == true ? 'Printed' : 'Not printed', style: const TextStyle(fontSize: 12)),
                            const Spacer(),
                            if (canEdit && i > 0)
                              IconButton(
                                  tooltip: 'Earlier',
                                  icon: const Icon(Icons.arrow_back_rounded, size: 17),
                                  onPressed: () async {
                                    await DprApi.updateFixedPage(contractId, asInt(pages[i]['page_id']), {'sort_order': asInt(pages[i - 1]['sort_order'])});
                                    if (!context.mounted) return;
                                    await _set(context, pages[i - 1], {'sort_order': asInt(pages[i]['sort_order'])});
                                  }),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _PageThumb extends StatefulWidget {
  final int contractId;
  final int pageId;
  const _PageThumb({required this.contractId, required this.pageId});

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  Uint8List? _b;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    DprApi.fixedPageBytes(widget.contractId, widget.pageId).then((b) {
      if (mounted) setState(() => _b = b);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: _b != null
          ? Image.memory(_b!, fit: BoxFit.cover)
          : Center(
              child: _failed
                  ? const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary)
                  : const CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
    );
  }
}

// ---------------------------------------------------------------------------
// Default layout
// ---------------------------------------------------------------------------
class DprLayoutTab extends StatefulWidget {
  final Json contract;
  final Json ucc;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const DprLayoutTab({super.key, required this.contract, required this.ucc, required this.canEdit, required this.onChanged});

  @override
  State<DprLayoutTab> createState() => _DprLayoutTabState();
}

class _DprLayoutTabState extends State<DprLayoutTab> {
  late Json _layout = asJson(widget.ucc['layout']);
  bool _dirty = false;
  bool _busy = false;

  Future<void> _save({bool reset = false}) async {
    setState(() => _busy = true);
    try {
      await DprApi.updateContract(asInt(widget.contract['contract_id']), {'layout': reset ? null : _layout});
      if (mounted) dprSnack(context, reset ? 'Back to the client\'s form.' : 'Default layout saved.');
      _dirty = false;
      await widget.onChanged();
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      DprCard(
        title: 'What is printed – contract default',
        subtitle: 'Sections, tables, columns and titles of every report of this contract. Each day can still change it on the report page.',
        icon: Icons.print_rounded,
        actions: [
          if (widget.canEdit)
            TextButton.icon(
              onPressed: _busy ? null : () => _save(reset: true),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Client\'s form'),
            ),
          if (widget.canEdit)
            ElevatedButton.icon(
              style: dprPrimaryButton(),
              onPressed: _busy || !_dirty ? null : () => _save(),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
        ],
        child: UccLayoutEditor(
          sections: asList(widget.ucc['sections']),
          layout: _layout,
          enabled: widget.canEdit && !_busy,
          onChanged: (l) => setState(() {
            _layout = l;
            _dirty = true;
          }),
        ),
      ),
    ]);
  }
}
