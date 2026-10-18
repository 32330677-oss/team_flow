// lib/screens/dpr/dpr_ucc_report.dart
//
// The daily report of one contract in the CLIENT'S FORM (UCC-IMS-CM-3003A).
//   * Every figure comes from the systems (Team Flow attendance, the staff list,
//     the equipment system) — READ ONLY — and the QC can change ANY of them:
//     this report only / from this day on / counts in the cumulative, with the
//     days and issued reports it changes shown before saving.
//   * What is printed (sections, tables, columns, titles, empty rows) can be
//     chosen for this day; the contract default is in Setup.
//   * A section can be the same as another contract (71 <-> 26): Setup.
//   * Left: what is filled in. Right (wide) / second tab: the PDF as printed.
// Only counts of people are shown: never names, salaries or anything personal.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import '../payroll_export_service.dart';
import 'dpr_report_screen.dart';
import 'dpr_ucc_widgets.dart';
import 'dpr_widgets.dart';

const _dayText = ['weather_remarks', 'remarks'];
const _dayDec = ['temp_max', 'temp_min'];

class UccDayEditor extends StatefulWidget {
  final int contractId;
  final String date;
  const UccDayEditor({super.key, required this.contractId, required this.date});

  @override
  State<UccDayEditor> createState() => _UccDayEditorState();
}

class _UccDayEditorState extends State<UccDayEditor> with SingleTickerProviderStateMixin {
  Json? _b;
  String? _error;
  int _version = 0;
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, dynamic> _dirty = {};
  final Set<int> _applyDayTo = {};
  Timer? _saveTimer;
  Timer? _pdfTimer;
  bool _saving = false;
  bool _saveFailed = false;
  String _saveState = '';
  Uint8List? _pdf;
  bool _pdfLoading = false;
  String? _pdfError;
  int _pdfSeq = 0;
  Json? _sitesToday;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  int get cid => widget.contractId;
  String get date => widget.date;
  bool get canEdit => DprState.can('dpr.edit');
  Json get model => asJson(_b?['model']);
  Json get day => asJson(_b?['day']);
  Json get links => asJson(model['links']);
  Json get layout => asJson(model['layout']);
  List<Json> get others => asList(_b?['other_contracts']);
  Json get lists => asJson(_b?['lists']);

  @override
  void initState() {
    super.initState();
    for (final k in [..._dayText, ..._dayDec]) {
      _ctl[k] = TextEditingController();
    }
    _load(first: true);
    _loadSites();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _pdfTimer?.cancel();
    if (_dirty.isNotEmpty) {
      DprApi.patchDayTo(cid, date, _version, Map<String, dynamic>.from(_dirty), _applyDayTo.toList()).catchError((_) => <String, dynamic>{});
    }
    for (final c in _ctl.values) {
      c.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false, bool refresh = false}) async {
    try {
      final b = await DprApi.day(cid, date, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _b = b;
        _error = null;
        if (first || refresh || _dirty.isEmpty) _version = asInt(b['version']);
        if (first || refresh) {
          for (final k in _ctl.keys) {
            _ctl[k]!.text = str(asJson(b['day'])[k]);
          }
        }
      });
      _schedulePdf(immediate: first);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSites() async {
    try {
      final r = await DprApi.teamFlowToday(date, contractId: cid);
      if (mounted) setState(() => _sitesToday = r);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- autosave of the day fields
  void _changed(String key, dynamic value) {
    if (!canEdit) return;
    _dirty[key] = value;
    setState(() => _saveState = 'Changes not saved yet…');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _save);
  }

  Future<void> _save() async {
    if (_saving || _dirty.isEmpty) return;
    final fields = Map<String, dynamic>.from(_dirty);
    _dirty.clear();
    setState(() {
      _saving = true;
      _saveState = 'Saving…';
    });
    try {
      final r = await DprApi.patchDayTo(cid, date, _version, fields, _applyDayTo.toList());
      _version = asInt(r['version']);
      if (!mounted) return;
      final applied = (r['applied_to'] as List? ?? const []).map((e) => e.toString()).toList();
      setState(() {
        _saving = false;
        _saveFailed = false;
        _saveState = 'Saved ✓ ${TimeOfDay.now().format(context)}${applied.isEmpty ? '' : ' (also in ${applied.join(', ')})'}';
      });
      await _load();
    } on DprException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
      if (e.status == 409) {
        setState(() => _saveState = 'Someone else saved this day: latest version loaded.');
        dprSnack(context, e.message, error: true);
        await _load(refresh: true);
      } else {
        setState(() => _saveState = 'Not saved: ${e.message}');
        dprSnack(context, e.message, error: true);
      }
    }
    if (_dirty.isNotEmpty && mounted && !_saveFailed) _save();
  }

  // ---------------------------------------------------------------- preview
  void _schedulePdf({bool immediate = false}) {
    _pdfTimer?.cancel();
    _pdfTimer = Timer(Duration(milliseconds: immediate ? 10 : 1200), _loadPdf);
  }

  Future<void> _loadPdf() async {
    if (!mounted) return;
    setState(() {
      _pdfLoading = true;
      _pdfError = null;
    });
    try {
      final bytes = await DprApi.draftPdf(cid, date);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _pdfSeq += 1;
        _pdfLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _pdfLoading = false;
          _pdfError = e.toString();
        });
      }
    }
  }

  Future<void> _afterChange() async {
    await _load();
    _schedulePdf();
  }

  Future<void> _run(Future<void> Function() fn, {String? done}) async {
    try {
      await fn();
      if (done != null && mounted) dprSnack(context, done);
      await _afterChange();
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _download(String format) async {
    try {
      final bytes = format == 'pdf' ? await DprApi.draftPdf(cid, date) : await DprApi.draftXlsx(cid, date);
      final code = str(asJson(_b?['contract'])['code']);
      await PayrollExportService.exportBytes(bytes, 'Daily_Report_${code}_${date}_DRAFT.$format');
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _issue({bool revise = false}) async {
    final res = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DprIssuePage(contractId: cid, date: date, revise: revise, model: model),
    ));
    if (res == true) {
      if (mounted) dprSnack(context, revise ? 'New revision issued.' : 'Report issued.');
      await _afterChange();
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    if (_b == null) {
      if (_error != null) {
        return DprMessage(
          icon: Icons.error_outline_rounded,
          color: AppColors.danger,
          text: _error!,
          action: OutlinedButton.icon(onPressed: () => _load(first: true), icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1150;
      final form = _form();
      final preview = _preview();
      return Column(children: [
        _statusBar(),
        Expanded(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 11, child: form),
                  Container(width: 1, color: AppColors.border),
                  Expanded(flex: 9, child: preview),
                ])
              : Column(children: [
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabs,
                      labelColor: AppColors.primary,
                      indicatorColor: AppColors.accent,
                      unselectedLabelColor: AppColors.textSecondary,
                      tabs: const [Tab(icon: Icon(Icons.edit_note_rounded), text: 'Fill in'), Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'Preview')],
                      onTap: (i) {
                        if (i == 1 && _pdf == null && !_pdfLoading) _loadPdf();
                      },
                    ),
                  ),
                  Expanded(child: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [form, preview])),
                ]),
        ),
      ]);
    });
  }

  Widget _chip(String t, Color c, IconData i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _statusBar() {
    final h = asJson(model['header']);
    final reports = asList(_b?['reports']);
    final issued = reports.where((r) => r['status'] == 'Issued').toList();
    final missing = asList(model['missing']);
    final changed = _b?['changed_since_issue'] == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(str(h['report_title']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
        Text('${str(h['day_name'])} · ${fmtDay(h['report_date'])} · day ${str(h['day_no'])}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        if (issued.isNotEmpty)
          _chip('Issued Rev.${str(issued.first['revision'])} · ${str(issued.first['issued_at'])}', const Color(0xff047857), Icons.verified_rounded)
        else
          _chip('Draft', AppColors.textSecondary, Icons.edit_note_rounded),
        if (changed) _chip('Changed since issue – revise to reissue', const Color(0xffb45309), Icons.history_toggle_off_rounded),
        if (missing.isNotEmpty) _chip('${missing.length} missing', const Color(0xffb45309), Icons.rule_rounded),
        if (_saveState.isNotEmpty) Text(_saveState, style: TextStyle(fontSize: 12, color: _saveFailed ? AppColors.danger : AppColors.textSecondary)),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: () => _download('pdf'), icon: const Icon(Icons.picture_as_pdf_rounded, size: 17), label: const Text('PDF')),
        OutlinedButton.icon(onPressed: () => _download('xlsx'), icon: const Icon(Icons.grid_on_rounded, size: 17), label: const Text('Excel')),
        IconButton(
            tooltip: 'Reload figures from the systems',
            onPressed: () {
              _load(refresh: true);
              _loadSites();
            },
            icon: const Icon(Icons.refresh_rounded)),
        if (issued.isEmpty && DprState.can('dpr.issue'))
          ElevatedButton.icon(style: dprAccentButton(), onPressed: () => _issue(), icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Issue report')),
        if (issued.isNotEmpty && DprState.can('dpr.revise'))
          ElevatedButton.icon(
              style: dprPrimaryButton(), onPressed: () => _issue(revise: true), icon: const Icon(Icons.restart_alt_rounded, size: 17), label: const Text('Revise')),
      ]),
    );
  }

  Widget _preview() {
    if (_pdf == null) {
      if (_pdfError != null) {
        return DprMessage(
            icon: Icons.picture_as_pdf_outlined, color: AppColors.danger, text: _pdfError!, action: OutlinedButton(onPressed: _loadPdf, child: const Text('Try again')));
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final bytes = _pdf!;
    return Stack(children: [
      Container(
        color: const Color(0xffe5e7eb),
        child: PdfPreview(
          key: ValueKey(_pdfSeq),
          build: (format) async => bytes,
          useActions: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          maxPageWidth: 820,
          pdfFileName: 'preview.pdf',
          loadingWidget: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      ),
      if (_pdfLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3, color: AppColors.accent)),
    ]);
  }

  // ---------------------------------------------------------------- the form
  Widget _form() {
    final warnings = (model['warnings'] as List? ?? const []).map((e) => e.toString()).toList();
    final missing = asList(model['missing']).map((x) => str(x['label'])).toList();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          if (!canEdit) const DprBanner(lines: ['Read only: your account can view this report but not change it.'], color: AppColors.primary, icon: Icons.visibility_rounded),
          DprBanner(lines: warnings),
          if (missing.isNotEmpty) DprBanner(lines: ['Not filled in yet: ${missing.join(', ')}.'], color: AppColors.textSecondary, icon: Icons.rule_rounded),
          _headerCard(),
          _sitesCard(),
          _weatherCard(),
          _manpowerCard(),
          _plantCard(),
          _boqCard(),
          _activitiesCard(),
          _materialsCard(),
          _wirCard(),
          _notesCard(),
          _photosCard(),
          _layoutCard(),
        ],
      ),
    );
  }

  /// Small "Printed / Hidden" switch of a section (writes the layout of the day).
  Widget _printSwitch(String section) {
    final on = asJson(layout['sections'])[section] != false;
    return Tooltip(
      message: on ? 'Printed — tap to leave out of this day\'s report' : 'Not printed — tap to print',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: canEdit ? () => _setLayout('sections', section, !on) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.print_rounded : Icons.print_disabled_rounded, size: 18, color: on ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(on ? 'Printed' : 'Hidden', style: TextStyle(fontSize: 11.5, color: on ? AppColors.primary : AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  void _setLayout(String part, String key, dynamic value) {
    final l = Map<String, dynamic>.from(layout);
    final p = Map<String, dynamic>.from(asJson(l[part]));
    p[key] = value;
    l[part] = p;
    setState(() => _b!['model'] = {...model, 'layout': l});
    _changed('layout', l);
  }

  Widget _linkBanner(String section) {
    final l = asJson(links[section]);
    if (l.isEmpty) return const SizedBox.shrink();
    return DprBanner(
      lines: ['Same as contract ${str(l['code'])} (Setup → Same as): change it in ${str(l['code'])}.'],
      color: AppColors.primary,
      icon: Icons.link_rounded,
    );
  }

  Widget _headerCard() {
    final h = asJson(model['header']);
    Widget kv(String k, String v) => SizedBox(
          width: 250,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(v.isEmpty ? '—' : v, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return DprCard(
      title: str(h['report_title']),
      subtitle: 'From Setup — change it there',
      icon: Icons.apartment_rounded,
      actions: [_printSwitch('project')],
      child: Wrap(children: [
        kv('Project Ref.', str(h['project_ref'])),
        kv('Contract', str(h['contract_ref'])),
        kv('Project Name', str(h['project_name'])),
        kv('Project Location', str(h['project_location'])),
        kv('Client', str(h['client'])),
        kv('Consultant', str(h['consultant'])),
        kv('Project Manager', str(h['project_manager'])),
        kv('Commencement Date', fmtDay(h['commencement_date'])),
        kv('Completion Date', fmtDay(h['completion_date'])),
        kv('Document', '${str(h['doc_ref'])} · Rev. ${str(h['rev_no'])}'),
      ]),
    );
  }

  /// Workers of the day on every Team Flow site (counts only) — to check the figures.
  Widget _sitesCard() {
    final sites = asList(_sitesToday?['sites']);
    return DprCard(
      title: 'Team Flow today – workers per site',
      subtitle: 'From the attendance of each site (counts only). Assigned = on the site that day.',
      icon: Icons.location_city_rounded,
      actions: [IconButton(tooltip: 'Refresh', onPressed: _loadSites, icon: const Icon(Icons.refresh_rounded, size: 18))],
      child: sites.isEmpty
          ? const Text('No attendance data.', style: TextStyle(color: AppColors.textSecondary))
          : AppDataTableCard(
              title: 'Sites',
              icon: Icons.groups_rounded,
              columns: [dprCol('Site'), dprCol('Assigned'), dprCol('Present'), dprCol('Absent'), dprCol('Not recorded'), dprCol('Shifts')],
              rows: sites
                  .map((s) => DataRow(cells: [
                        DataCell(dprCell(str(s['site_name']), bold: true)),
                        DataCell(dprCell(str(s['assigned']))),
                        DataCell(dprCell(str(s['present']), color: const Color(0xff047857), bold: true)),
                        DataCell(dprCell(str(s['absent']))),
                        DataCell(dprCell(str(s['not_recorded']), color: asInt(s['not_recorded']) > 0 ? const Color(0xffb45309) : null)),
                        DataCell(dprCell(asList(s['shifts']).map((x) => '${str(x['shift'])} ${str(x['present'])}/${str(x['assigned'])}').join(' · '))),
                      ]))
                  .toList(),
            ),
    );
  }

  // ---------------------------------------------------------------- weather
  Widget _weatherCard() {
    final linked = asJson(links['weather']).isNotEmpty;
    final w = asJson(model['weather']);
    final edit = canEdit && !linked;
    final conds = (lists['weather_conditions'] as List? ?? const ['SUNNY', 'CLOUDY', 'RAINY', 'DUSTY']).map((e) => e.toString()).toList();
    final hums = (lists['humidity_levels'] as List? ?? const ['HIGH', 'MEDIUM', 'LOW']).map((e) => e.toString()).toList();
    final cond = linked ? str(w['condition']) : str(_dirty['weather_condition'] ?? day['weather_condition']);
    final hum = linked ? str(w['humidity_level']) : str(_dirty['humidity_level'] ?? day['humidity_level']);
    return DprCard(
      title: 'Weather',
      icon: Icons.wb_sunny_rounded,
      actions: [_printSwitch('weather')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('weather'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in conds)
            ChoiceChip(
              label: Text(c),
              selected: cond.toUpperCase() == c.toUpperCase(),
              onSelected: edit
                  ? (v) {
                      setState(() => _dirty['weather_condition'] = v ? c : null);
                      _changed('weather_condition', v ? c : null);
                    }
                  : null,
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final k in _dayDec)
            SizedBox(
              width: 120,
              child: linked
                  ? Text('${k == 'temp_max' ? 'Max' : 'Min'} °C: ${str(w[k])}')
                  : TextField(
                      controller: _ctl[k],
                      enabled: edit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: dprInput(k == 'temp_max' ? 'Max °C' : 'Min °C'),
                      onChanged: (v) => _changed(k, v.trim()),
                    ),
            ),
          const Text('Humidity', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final h in hums)
            ChoiceChip(
              label: Text(h),
              selected: hum.toUpperCase() == h.toUpperCase(),
              onSelected: edit
                  ? (v) {
                      setState(() => _dirty['humidity_level'] = v ? h : null);
                      _changed('humidity_level', v ? h : null);
                    }
                  : null,
            ),
        ]),
        const SizedBox(height: 10),
        if (!linked)
          TextField(
            controller: _ctl['weather_remarks'],
            enabled: edit,
            decoration: dprInput('Remarks (optional)'),
            onChanged: (v) => _changed('weather_remarks', v),
          ),
        if (edit && others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Also save the weather and remarks in:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            for (final o in others)
              FilterChip(
                label: Text(str(o['code']), style: const TextStyle(fontSize: 12)),
                selected: _applyDayTo.contains(asInt(o['contract_id'])),
                onSelected: (v) => setState(() => v ? _applyDayTo.add(asInt(o['contract_id'])) : _applyDayTo.remove(asInt(o['contract_id']))),
              ),
          ]),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- figures (tap = change)
  Future<void> _figure(String key, String label, Json cell, {required String kind, required bool sourced, String? section}) async {
    if (section != null && asJson(links[section]).isNotEmpty) {
      dprSnack(context, 'This section is the same as contract ${str(asJson(links[section])['code'])}: change it there.', error: true);
      return;
    }
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => UccFigureDialog(
        contractId: cid,
        date: date,
        figureKey: key,
        label: label,
        cell: cell,
        kind: kind,
        sourced: sourced,
        otherContracts: others,
      ),
    );
    if (r == true) await _afterChange();
  }

  Widget _cellBox(Json cell, VoidCallback? onTap, {bool bold = false}) {
    final m = str(cell['m']);
    final v = str(cell['v']);
    final color = m == 'manual' ? const Color(0xffb45309) : (m == 'system' ? const Color(0xff047857) : AppColors.textPrimary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 54, minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: m == 'manual' ? const Color(0xfffff7ed) : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: m == 'manual' ? const Color(0xfffdba74) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(v.isEmpty ? '—' : fmtQty(v), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: v.isEmpty ? AppColors.textSecondary : color)),
          if (m == 'manual' && cell['s'] != null) ...[
            const SizedBox(width: 4),
            Text('(${fmtQty(cell['s'])})', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ]),
      ),
    );
  }

  Widget _rowsTable(String section, String table, String title, Json data, List<(String, String)> fields) {
    final rows = asList(data['rows']);
    final total = asJson(data['total']);
    final tableOn = asJson(layout['tables'])[table] != false;
    return AppDataTableCard(
      title: title,
      subtitle: tableOn ? null : 'This table is not printed today (layout)',
      icon: section == 'manpower' ? Icons.groups_rounded : Icons.precision_manufacturing_rounded,
      emptyMessage: 'No row. Add rows in Setup (or load the client\'s lists).',
      columns: [dprCol(table == 'staff' ? 'Position' : (table == 'trades' ? 'Trade' : (table == 'plant' ? 'Equipment' : 'Tool'))), ...fields.map((f) => dprCol(f.$2))],
      rows: [
        ...rows.map((r) => DataRow(cells: [
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                dprCell(str(r['name']), bold: true),
                if (r['auto'] == true) const SourceTag(mode: 'system', system: 'Auto row'),
                if (r['sourced'] != true && r['auto'] != true) const SourceTag(mode: 'typed'),
                if (r['unavailable'] == true) const Icon(Icons.cloud_off_rounded, size: 15, color: AppColors.danger),
              ])),
              ...fields.map((f) {
                final cell = asJson(asJson(r['cells'])[f.$1]);
                final key = r['auto'] == true ? '${str(r['key'])}:${f.$1}' : 'line:${str(r['line_id'])}:${f.$1}';
                return DataCell(_cellBox(cell, () => _figure(key, '${str(r['name'])} – ${f.$2}', cell, kind: 'count', sourced: r['sourced'] == true, section: section)));
              }),
            ])),
        DataRow(color: WidgetStateProperty.all(AppColors.background), cells: [
          DataCell(dprCell('TOTAL', bold: true)),
          ...fields.map((f) {
            final cell = asJson(total[f.$1]);
            return DataCell(_cellBox(cell, () => _figure('tot:$table:${f.$1}', 'Total $title – ${f.$2}', cell, kind: 'count', sourced: true, section: section), bold: true));
          }),
        ]),
      ],
    );
  }

  Widget _manpowerCard() {
    final mp = asJson(model['manpower']);
    final g = asJson(mp['grand']);
    const f = [('total', 'Total'), ('present', 'Present'), ('absent', 'Absent')];
    return DprCard(
      title: 'Manpower – staff | tradesmen',
      subtitle: 'Green = from the system, orange = your value (system value in brackets). Tap any figure to change it.',
      icon: Icons.engineering_rounded,
      actions: [_printSwitch('manpower')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('manpower'),
        _rowsTable('manpower', 'staff', 'Staff', asJson(mp['staff']), f),
        const SizedBox(height: 10),
        _rowsTable('manpower', 'trades', 'Tradesmen', asJson(mp['trades']), f),
        const SizedBox(height: 8),
        Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final x in f) ...[
            Text(x.$2, style: const TextStyle(color: AppColors.textSecondary)),
            _cellBox(asJson(g[x.$1]),
                () => _figure('tot:manpower:${x.$1}', 'Grand total – ${x.$2}', asJson(g[x.$1]), kind: 'count', sourced: true, section: 'manpower'),
                bold: true),
          ],
        ]),
      ]),
    );
  }

  Widget _plantCard() {
    final pl = asJson(model['plant']);
    const f = [('operative', 'Operative'), ('breakdown', 'Breakdown'), ('idle', 'Idle')];
    return DprCard(
      title: 'Plant | tools',
      subtitle: 'Plant from the equipment system: Working = Operative, Standby = Idle. Tools: your figures (kept for the next days when "from this day on").',
      icon: Icons.precision_manufacturing_rounded,
      actions: [_printSwitch('plant')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('plant'),
        _rowsTable('plant', 'plant', 'Plant', asJson(pl['plant']), f),
        const SizedBox(height: 10),
        _rowsTable('plant', 'tools', 'Tools', asJson(pl['tools']), f),
      ]),
    );
  }

  // ---------------------------------------------------------------- BOQ
  Widget _boqCard() {
    final groups = asList(asJson(model['boq'])['groups']);
    const f = [('qty', 'Quantity', 'display'), ('budget', 'Budget', 'display'), ('curr', 'CURR (today)', 'curr'), ('cum', 'CUMUL', 'cum'), ('balance', 'Balance', 'display')];
    return DprCard(
      title: 'Overall progress (BOQ)',
      subtitle: 'CURR = activities of today. CUMUL = done before the system + every day. Tap a figure to change it.',
      icon: Icons.list_alt_rounded,
      actions: [_printSwitch('boq')],
      child: groups.isEmpty
          ? const Text('No BOQ yet. Add it in Setup → BOQ (or import the Excel file).', style: TextStyle(color: AppColors.textSecondary))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final g in groups) ...[
                AppDataTableCard(
                  title: str(g['name']).isEmpty ? 'Main BOQ' : str(g['name']),
                  icon: Icons.table_rows_rounded,
                  columns: [dprCol('Item'), dprCol('Description'), dprCol('Unit'), ...f.map((x) => dprCol(x.$2))],
                  rows: asList(g['rows']).map((r) {
                    if (str(r['row_type']) != 'item') {
                      return DataRow(color: WidgetStateProperty.all(str(r['row_type']) == 'section' ? const Color(0xffe2efda) : null), cells: [
                        DataCell(dprCell('')),
                        DataCell(dprCell(str(r['description']), bold: str(r['row_type']) == 'section', width: 320)),
                        DataCell(dprCell(str(r['unit']))),
                        ...f.map((x) => DataCell(dprCell(x.$1 == 'qty' ? fmtQty(r['qty']) : ''))),
                      ]);
                    }
                    final cells = asJson(r['cells']);
                    return DataRow(cells: [
                      DataCell(dprCell(str(r['item_no']), bold: true)),
                      DataCell(dprCell(str(r['description']), width: 320)),
                      DataCell(dprCell(str(r['unit']))),
                      ...f.map((x) {
                        final cell = asJson(cells[x.$1]);
                        final over = r['over'] == true && (x.$1 == 'cum' || x.$1 == 'balance');
                        return DataCell(Container(
                          color: over ? const Color(0xfffee2e2) : null,
                          child: _cellBox(cell, () => _figure('boq:${str(r['boq_id'])}:${x.$1}', 'BOQ ${str(r['item_no'])} – ${x.$2}', cell, kind: x.$3, sourced: true)),
                        ));
                      }),
                    ]);
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
            ]),
    );
  }

  // ---------------------------------------------------------------- activities
  Future<void> _editActivity([Json? a]) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UccActivityDialog(contractId: cid, date: date, activity: a, boq: asList(_b?['boq']), areas: asList(_b?['areas']), lists: lists),
    );
    if (r == true) await _afterChange();
  }

  Future<void> _moveActivity(List<Json> acts, int i, int d) async {
    final ids = acts.map((a) => asInt(a['activity_id'])).toList();
    final j = i + d;
    if (j < 0 || j >= ids.length) return;
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    await _run(() => DprApi.reorderActivities(cid, date, ids));
  }

  Widget _activitiesCard() {
    final acts = asList(_b?['activities']);
    final areas = {for (final a in asList(_b?['areas'])) asInt(a['area_id']): str(a['name'])};
    return DprCard(
      title: 'Activities of the day',
      subtitle: 'With a BOQ item: its quantity goes to CURR / CUMUL. With an area: printed on the area page (crews, W-HRS, output).',
      icon: Icons.construction_rounded,
      actions: [
        _printSwitch('activities'),
        if (canEdit) IconButton(tooltip: 'Add activity', onPressed: () => _editActivity(), icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ],
      child: acts.isEmpty
          ? const Text('No activity yet. Tap + to add one.', style: TextStyle(color: AppColors.textSecondary))
          : Column(children: [
              for (var i = 0; i < acts.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(str(acts[i]['description']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          [
                            if (str(acts[i]['item_no']).isNotEmpty) 'BOQ ${str(acts[i]['item_no'])}',
                            if ((asNum(acts[i]['qty']) ?? 0) != 0) '${fmtQty(acts[i]['qty'])} ${str(acts[i]['unit'])}',
                            if (str(acts[i]['location']).isNotEmpty) str(acts[i]['location']),
                            if (acts[i]['area_id'] != null) areas[asInt(acts[i]['area_id'])] ?? '',
                            if (str(acts[i]['chainage']).isNotEmpty) 'Ch. ${str(acts[i]['chainage'])}',
                            if (asList(acts[i]['crews']).isNotEmpty) '${asList(acts[i]['crews']).length} crew row(s)',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ]),
                    ),
                    if (canEdit) ...[
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Up', onPressed: i == 0 ? null : () => _moveActivity(acts, i, -1), icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Down',
                          onPressed: i == acts.length - 1 ? null : () => _moveActivity(acts, i, 1),
                          icon: const Icon(Icons.arrow_downward_rounded, size: 18)),
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Edit', onPressed: () => _editActivity(acts[i]), icon: const Icon(Icons.edit_rounded, size: 18)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                        onPressed: () async {
                          if (await dprConfirm(context, 'Delete activity', 'Delete "${str(acts[i]['description'])}"?', ok: 'Delete', danger: true)) {
                            await _run(() => DprApi.deleteActivity(cid, date, asInt(acts[i]['activity_id'])));
                          }
                        },
                      ),
                    ],
                  ]),
                ),
            ]),
    );
  }

  // ---------------------------------------------------------------- materials & WIR
  Future<void> _editMaterial([Json? m]) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UccMaterialDialog(contractId: cid, date: date, row: m, areas: asList(_b?['areas']), lists: lists),
    );
    if (r == true) await _afterChange();
  }

  Widget _materialsCard() {
    final rows = asList(model['materials']);
    final linked = asJson(links['materials']).isNotEmpty;
    return DprCard(
      title: 'Delivered materials at site',
      icon: Icons.local_shipping_rounded,
      actions: [
        _printSwitch('materials'),
        if (canEdit && !linked) IconButton(tooltip: 'Add material', onPressed: () => _editMaterial(), icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('materials'),
        AppDataTableCard(
          title: 'Materials',
          icon: Icons.inventory_rounded,
          emptyMessage: 'No delivery today.',
          columns: [dprCol('Material'), dprCol('Unit'), dprCol('Qty'), dprCol('Supplier'), dprCol('Delivery note'), dprCol('Bridge / area'), dprCol('')],
          rows: rows
              .map((x) => DataRow(cells: [
                    DataCell(dprCell(str(x['description']), bold: true)),
                    DataCell(dprCell(str(x['unit']))),
                    DataCell(dprCell(fmtQty(x['qty']))),
                    DataCell(dprCell(str(x['supplier']))),
                    DataCell(dprCell(str(x['delivery_note']))),
                    DataCell(dprCell(str(x['area']))),
                    DataCell(canEdit && !linked
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Edit', onPressed: () => _editMaterial(x), icon: const Icon(Icons.edit_rounded, size: 18)),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                              onPressed: () async {
                                if (await dprConfirm(context, 'Delete material', 'Delete "${str(x['description'])}"?', ok: 'Delete', danger: true)) {
                                  await _run(() => DprApi.deleteMaterial(cid, date, asInt(x['material_id'])));
                                }
                              },
                            ),
                          ])
                        : const SizedBox.shrink()),
                  ]))
              .toList(),
        ),
      ]),
    );
  }

  Future<void> _editWir([Json? q]) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UccWirDialog(contractId: cid, date: date, row: q, areas: asList(_b?['areas']), lists: lists),
    );
    if (r == true) await _afterChange();
  }

  Widget _wirCard() {
    final linked = asJson(links['wir']).isNotEmpty;
    final rows = linked ? asList(model['wir']) : asList(_b?['wir']);
    return DprCard(
      title: 'Work inspection requests (WIR)',
      icon: Icons.fact_check_rounded,
      actions: [
        _printSwitch('wir'),
        if (canEdit && !linked) IconButton(tooltip: 'Add WIR', onPressed: () => _editWir(), icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('wir'),
        AppDataTableCard(
          title: 'WIR register',
          icon: Icons.assignment_turned_in_rounded,
          emptyMessage: 'No WIR today.',
          columns: [dprCol('WIR Ref.'), dprCol('Activity'), dprCol('Location / chainage'), dprCol('MS Ref.'), dprCol('Status'), dprCol('')],
          rows: rows
              .map((x) => DataRow(cells: [
                    DataCell(dprCell(str(x['ref_no']), bold: true)),
                    DataCell(dprCell(str(x['description']), width: 220)),
                    DataCell(dprCell([str(x['location']), str(x['chainage'])].where((e) => e.isNotEmpty).join(' / '))),
                    DataCell(dprCell(str(x['ms_ref']))),
                    DataCell(dprCell(str(x['result']))),
                    DataCell(canEdit && !linked
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Edit', onPressed: () => _editWir(x), icon: const Icon(Icons.edit_rounded, size: 18)),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                              onPressed: () async {
                                if (await dprConfirm(context, 'Delete WIR', 'Delete "${str(x['ref_no'])}"?', ok: 'Delete', danger: true)) {
                                  await _run(() => DprApi.deleteQa(cid, date, asInt(x['qa_id'])));
                                }
                              },
                            ),
                          ])
                        : const SizedBox.shrink()),
                  ]))
              .toList(),
        ),
      ]),
    );
  }

  Widget _notesCard() {
    final linked = asJson(links['notes']).isNotEmpty;
    return DprCard(
      title: 'General remarks',
      subtitle: 'Not in the client\'s form: switch it on in the layout to print it.',
      icon: Icons.sticky_note_2_rounded,
      actions: [_printSwitch('notes')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _linkBanner('notes'),
        if (linked)
          Text(str(model['notes']))
        else
          TextField(
            controller: _ctl['remarks'],
            enabled: canEdit,
            minLines: 2,
            maxLines: 6,
            decoration: dprInput('Remarks'),
            onChanged: (v) => _changed('remarks', v),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- photos
  Future<void> _addPhoto(ImageSource source) async {
    try {
      final XFile? f = await ImagePicker().pickImage(source: source, maxWidth: 2200, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final lower = f.name.toLowerCase();
      final name = lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp') ? f.name : '${f.name}.jpg';
      await _run(() => DprApi.addPhoto(cid, date, bytes, name, {}), done: 'Photo added.');
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _addPhotoFile() async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Photos', extensions: ['jpg', 'jpeg', 'png', 'webp'])]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    await _run(() => DprApi.addPhoto(cid, date, bytes, f.name, {}), done: 'Photo added.');
  }

  Widget _photosCard() {
    final photos = asList(model['photos']);
    return DprCard(
      title: 'Photos',
      subtitle: 'Choose an area to print a photo on that area\'s page. Photos per page: layout.',
      icon: Icons.photo_library_rounded,
      actions: [
        _printSwitch('photos'),
        if (canEdit)
          PopupMenuButton<String>(
            tooltip: 'Add photo',
            icon: const Icon(Icons.add_a_photo_rounded, color: AppColors.primary),
            onSelected: (v) {
              if (v == 'camera') _addPhoto(ImageSource.camera);
              if (v == 'gallery') _addPhoto(ImageSource.gallery);
              if (v == 'file') _addPhotoFile();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'camera', child: Text('Take a photo')),
              PopupMenuItem(value: 'gallery', child: Text('From the gallery')),
              PopupMenuItem(value: 'file', child: Text('From a file')),
            ],
          ),
      ],
      child: photos.isEmpty
          ? const Text('No photo for this day.', style: TextStyle(color: AppColors.textSecondary))
          : Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in photos)
                _UccPhotoTile(
                  key: ValueKey(p['photo_id']),
                  contractId: cid,
                  date: date,
                  photo: p,
                  areas: asList(_b?['areas']),
                  canEdit: canEdit,
                  onChanged: _afterChange,
                ),
            ]),
    );
  }

  // ---------------------------------------------------------------- layout of the day
  Widget _layoutCard() {
    final dayLayout = _b?['layout_day'];
    return DprCard(
      title: 'What is printed – this day',
      subtitle: dayLayout == null ? 'Same as the contract default (Setup → Layout).' : 'Changed for this day only.',
      icon: Icons.print_rounded,
      actions: [
        if (canEdit && dayLayout != null)
          TextButton.icon(
            onPressed: () async {
              if (await dprConfirm(context, 'Back to the contract default', 'Use the contract\'s default layout for this day again?')) {
                _changed('layout', null);
              }
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Contract default'),
          ),
      ],
      child: UccLayoutEditor(
        sections: asList(_b?['ucc_sections']),
        layout: layout,
        enabled: canEdit,
        onChanged: (l) {
          setState(() => _b!['model'] = {...model, 'layout': l});
          _changed('layout', l);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------
class _UccActivityDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final Json? activity;
  final List<Json> boq;
  final List<Json> areas;
  final Json lists;
  const _UccActivityDialog({required this.contractId, required this.date, this.activity, required this.boq, required this.areas, required this.lists});

  @override
  State<_UccActivityDialog> createState() => _UccActivityDialogState();
}

class _CrewRow {
  String kind;
  final TextEditingController name;
  final TextEditingController nos;
  final TextEditingController hours;
  _CrewRow(this.kind, String n, String no, String h)
      : name = TextEditingController(text: n),
        nos = TextEditingController(text: no),
        hours = TextEditingController(text: h);
  void dispose() {
    name.dispose();
    nos.dispose();
    hours.dispose();
  }
}

class _UccActivityDialogState extends State<_UccActivityDialog> {
  late int? _boqId = widget.activity?['boq_id'] == null ? null : asInt(widget.activity!['boq_id']);
  late int? _areaId = widget.activity?['area_id'] == null ? null : asInt(widget.activity!['area_id']);
  late final TextEditingController _desc = TextEditingController(text: str(widget.activity?['own_description']));
  late final TextEditingController _loc = TextEditingController(text: str(widget.activity?['location']));
  late final TextEditingController _qty =
      TextEditingController(text: (asNum(widget.activity?['qty']) ?? 0) == 0 ? '' : fmtQty(widget.activity?['qty']).replaceAll(',', ''));
  late final TextEditingController _unit = TextEditingController(text: str(widget.activity?['own_unit']));
  late final TextEditingController _chain = TextEditingController(text: str(widget.activity?['chainage']));
  late final TextEditingController _remarks = TextEditingController(text: str(widget.activity?['remarks']));
  late final List<_CrewRow> _crews = asList(widget.activity?['crews'])
      .map((c) => _CrewRow(str(c['kind']), str(c['name']), fmtQty(c['nos']).replaceAll(',', ''), fmtQty(c['hours']).replaceAll(',', '')))
      .toList();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_desc, _loc, _qty, _unit, _chain, _remarks]) {
      c.dispose();
    }
    for (final c in _crews) {
      c.dispose();
    }
    super.dispose();
  }

  Json? get _item => _boqId == null ? null : widget.boq.where((b) => asInt(b['boq_id']) == _boqId).firstOrNull;

  Future<void> _pickBoq() async {
    final r = await showDialog<int>(context: context, builder: (_) => _BoqSearch(items: widget.boq));
    if (r != null) setState(() => _boqId = r == -1 ? null : r);
  }

  Future<void> _save() async {
    if (_boqId == null && _desc.text.trim().isEmpty) {
      setState(() => _error = 'Choose the BOQ item or write the activity.');
      return;
    }
    if (_boqId != null && _qty.text.trim().isEmpty) {
      setState(() => _error = 'Enter the quantity done today (0 if none).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.saveActivity(widget.contractId, widget.date, widget.activity == null ? null : asInt(widget.activity!['activity_id']), {
        'boq_id': _boqId,
        'description': _desc.text.trim(),
        'location': _loc.text.trim(),
        'qty': _qty.text.trim().replaceAll(',', ''),
        'unit': _unit.text.trim(),
        'area_id': _areaId,
        'chainage': _chain.text.trim(),
        'remarks': _remarks.text.trim(),
        'crews': _crews
            .where((c) => c.name.text.trim().isNotEmpty)
            .map((c) => {'kind': c.kind, 'name': c.name.text.trim(), 'nos': c.nos.text.trim(), 'hours': c.hours.text.trim()})
            .toList(),
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

  Widget _crewEditor() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('Crews on this activity (area page: No., W-HRS)', style: TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(
            onPressed: () => setState(() => _crews.add(_CrewRow('plant', '', '', ''))), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Plant')),
        TextButton.icon(
            onPressed: () => setState(() => _crews.add(_CrewRow('trade', '', '', ''))), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Tradesmen')),
      ]),
      const Text('W-HRS empty = No. × working hours / day (Setup).', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      for (var i = 0; i < _crews.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(
              width: 92,
              child: Text(_crews[i].kind == 'plant' ? 'PLANT' : 'TRADESMEN',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _crews[i].kind == 'plant' ? AppColors.primary : const Color(0xff047857))),
            ),
            Expanded(flex: 3, child: TextField(controller: _crews[i].name, decoration: dprInput('Name'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _crews[i].nos, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dprInput('No.'))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _crews[i].hours, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dprInput('W-HRS'))),
            IconButton(
                tooltip: 'Remove',
                onPressed: () {
                  final removed = _crews.removeAt(i);
                  setState(() {});
                  // dispose after the TextFields of this frame let go of the controllers
                  WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                },
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    final units = (widget.lists['units'] as List? ?? const []).map((e) => e.toString()).toList();
    return AlertDialog(
      title: Text(widget.activity == null ? 'New activity' : 'Edit activity'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: _pickBoq,
              child: InputDecorator(
                decoration: dprInput('BOQ item (optional)', suffix: const Icon(Icons.search_rounded)),
                child: Text(it == null ? 'None — write the activity below' : '${str(it['item_no'])} — ${str(it['description'])} (${str(it['unit'])})'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              decoration: dprInput(it == null ? 'Activity (required)' : 'Activity text (empty = the BOQ description)'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _loc, decoration: dprInput('Location'))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: dprInput(it == null ? 'Output (optional)' : 'Qty today (${str(it['unit'])})'),
                ),
              ),
              if (it == null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: dprInput('Unit', hint: units.take(4).join(', ')),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _areaId,
                  decoration: dprInput('Area / bridge (optional)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— none —')),
                    ...widget.areas.where((a) => a['is_active'] == true || asInt(a['area_id']) == _areaId).map(
                        (a) => DropdownMenuItem<int?>(value: asInt(a['area_id']), child: Text(str(a['name'])))),
                  ],
                  onChanged: (v) => setState(() => _areaId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _chain, decoration: dprInput('Chainage'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _remarks, decoration: dprInput('Remarks')),
            const SizedBox(height: 12),
            _crewEditor(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _BoqSearch extends StatefulWidget {
  final List<Json> items;
  const _BoqSearch({required this.items});

  @override
  State<_BoqSearch> createState() => _BoqSearchState();
}

class _BoqSearchState extends State<_BoqSearch> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.items.where((b) => q.isEmpty || '${str(b['item_no'])} ${str(b['description'])}'.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text('BOQ item'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(children: [
          TextField(autofocus: true, decoration: dprInput('Search item no. or description', suffix: const Icon(Icons.search_rounded)), onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: 8),
          ListTile(dense: true, leading: const Icon(Icons.block_rounded), title: const Text('No BOQ item (free activity)'), onTap: () => Navigator.pop(context, -1)),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No BOQ item. Add the BOQ in Setup.'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: Text(str(list[i]['item_no']), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                      title: Text(str(list[i]['description'])),
                      subtitle: Text('${str(list[i]['unit'])} · contract ${fmtQty(list[i]['contract_qty'])}'),
                      onTap: () => Navigator.pop(context, asInt(list[i]['boq_id'])),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _UccMaterialDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final Json? row;
  final List<Json> areas;
  final Json lists;
  const _UccMaterialDialog({required this.contractId, required this.date, this.row, required this.areas, required this.lists});

  @override
  State<_UccMaterialDialog> createState() => _UccMaterialDialogState();
}

class _UccMaterialDialogState extends State<_UccMaterialDialog> {
  static const _fields = [
    ('description', 'Material / specification / grade (required)'),
    ('unit', 'Unit'),
    ('qty', 'Qty delivered'),
    ('supplier', 'Supplier'),
    ('delivery_note', 'Delivery note No.'),
    ('mar_ref', 'MAR Ref.'),
    ('element', 'Element'),
    ('boq_ref', 'BOQ Ref.'),
    ('intended_use', 'Intended use'),
  ];
  late final Map<String, TextEditingController> _c = {
    for (final f in _fields) f.$1: TextEditingController(text: f.$1 == 'qty' ? fmtQty(widget.row?['qty']).replaceAll(',', '') : str(widget.row?[f.$1])),
  };
  late int? _areaId = widget.row?['area_id'] == null ? null : asInt(widget.row!['area_id']);
  String? _error;
  bool _busy = false;

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
      await DprApi.saveMaterial(widget.contractId, widget.date, widget.row == null ? null : asInt(widget.row!['material_id']), {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'area_id': _areaId,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row == null ? 'New delivery' : 'Edit delivery'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final f in _fields) ...[
              TextField(controller: _c[f.$1], decoration: dprInput(f.$2), keyboardType: f.$1 == 'qty' ? const TextInputType.numberWithOptions(decimal: true) : null),
              const SizedBox(height: 8),
            ],
            DropdownButtonFormField<int?>(
              initialValue: _areaId,
              decoration: dprInput('Bridge / area'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('— none —')),
                ...widget.areas.map((a) => DropdownMenuItem<int?>(value: asInt(a['area_id']), child: Text(str(a['name'])))),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _UccWirDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final Json? row;
  final List<Json> areas;
  final Json lists;
  const _UccWirDialog({required this.contractId, required this.date, this.row, required this.areas, required this.lists});

  @override
  State<_UccWirDialog> createState() => _UccWirDialogState();
}

class _UccWirDialogState extends State<_UccWirDialog> {
  late final TextEditingController _ref = TextEditingController(text: str(widget.row?['ref_no']));
  late final TextEditingController _desc = TextEditingController(text: str(widget.row?['description']));
  late final TextEditingController _loc = TextEditingController(text: str(widget.row?['location']));
  late final TextEditingController _chain = TextEditingController(text: str(widget.row?['chainage']));
  late final TextEditingController _ms = TextEditingController(text: str(widget.row?['ms_ref']));
  late final TextEditingController _comments = TextEditingController(text: str(widget.row?['remarks']));
  late String? _status = str(widget.row?['result']).isEmpty ? null : str(widget.row?['result']);
  late int? _areaId = widget.row?['area_id'] == null ? null : asInt(widget.row!['area_id']);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_ref, _desc, _loc, _chain, _ms, _comments]) {
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
      await DprApi.saveQa(widget.contractId, widget.date, widget.row == null ? null : asInt(widget.row!['qa_id']), {
        'type': 'WIR',
        'ref_no': _ref.text.trim(),
        'description': _desc.text.trim(),
        'location': _loc.text.trim(),
        'chainage': _chain.text.trim(),
        'ms_ref': _ms.text.trim(),
        'result': _status,
        'remarks': _comments.text.trim(),
        'area_id': _areaId,
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

  @override
  Widget build(BuildContext context) {
    final statuses = (widget.lists['wir_status'] as List? ?? const []).map((e) => e.toString()).toSet().toList();
    if (_status != null && !statuses.contains(_status)) statuses.add(_status!);
    return AlertDialog(
      title: Text(widget.row == null ? 'New WIR' : 'Edit WIR'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(controller: _ref, decoration: dprInput('WIR Ref.'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _ms, decoration: dprInput('MS Ref.'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _desc, decoration: dprInput('Activity / work description')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _loc, decoration: dprInput('Location'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _chain, decoration: dprInput('Chainage'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _areaId,
                  decoration: dprInput('Bridge / area'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— none —')),
                    ...widget.areas.map((a) => DropdownMenuItem<int?>(value: asInt(a['area_id']), child: Text(str(a['name'])))),
                  ],
                  onChanged: (v) => setState(() => _areaId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _status,
                  decoration: dprInput('Status'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    ...statuses.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _comments, decoration: dprInput('Comments')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _UccPhotoTile extends StatefulWidget {
  final int contractId;
  final String date;
  final Json photo;
  final List<Json> areas;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const _UccPhotoTile(
      {super.key, required this.contractId, required this.date, required this.photo, required this.areas, required this.canEdit, required this.onChanged});

  @override
  State<_UccPhotoTile> createState() => _UccPhotoTileState();
}

class _UccPhotoTileState extends State<_UccPhotoTile> {
  Uint8List? _bytes;
  bool _failed = false;
  late final TextEditingController _cap = TextEditingController(text: str(widget.photo['caption']));
  late final TextEditingController _loc = TextEditingController(text: str(widget.photo['location']));
  late int? _areaId = widget.photo['area_id'] == null ? null : asInt(widget.photo['area_id']);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    DprApi.photoBytes(widget.contractId, asInt(widget.photo['photo_id'])).then((b) {
      if (mounted) setState(() => _bytes = b);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _cap.dispose();
    _loc.dispose();
    super.dispose();
  }

  void _changed({bool now = false}) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: now ? 10 : 1000), () async {
      try {
        await DprApi.updatePhoto(widget.contractId, widget.date, asInt(widget.photo['photo_id']), {
          'slot': widget.photo['slot'],
          'boq_activity': str(widget.photo['boq_activity']),
          'location': _loc.text.trim(),
          'caption': _cap.text.trim(),
          'area_id': _areaId,
        });
        await widget.onChanged();
      } catch (e) {
        if (mounted) dprSnack(context, e.toString(), error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: SizedBox(
            height: 150,
            child: _bytes != null
                ? Image.memory(_bytes!, fit: BoxFit.cover)
                : Center(
                    child: _failed
                        ? const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary)
                        : const CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Row(children: [
              Text('No. ${str(widget.photo['slot'])}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
              const Spacer(),
              if (widget.canEdit)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove photo',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                  onPressed: () async {
                    if (await dprConfirm(context, 'Remove photo', 'Remove this photo from the report?', ok: 'Remove', danger: true)) {
                      try {
                        await DprApi.deletePhoto(widget.contractId, widget.date, asInt(widget.photo['photo_id']));
                        await widget.onChanged();
                      } catch (e) {
                        if (context.mounted) dprSnack(context, e.toString(), error: true);
                      }
                    }
                  },
                ),
            ]),
            DropdownButtonFormField<int?>(
              initialValue: _areaId,
              isExpanded: true,
              decoration: dprInput('Area page'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('General photos')),
                ...widget.areas.map((a) => DropdownMenuItem<int?>(value: asInt(a['area_id']), child: Text(str(a['name'])))),
              ],
              onChanged: widget.canEdit
                  ? (v) {
                      setState(() => _areaId = v);
                      _changed(now: true);
                    }
                  : null,
            ),
            const SizedBox(height: 6),
            TextField(controller: _loc, enabled: widget.canEdit, decoration: dprInput('Location'), onChanged: (_) => _changed()),
            const SizedBox(height: 6),
            TextField(controller: _cap, enabled: widget.canEdit, decoration: dprInput('Caption'), onChanged: (_) => _changed()),
          ]),
        ),
      ]),
    );
  }
}
