// lib/screens/dpr/dpr_report_screen.dart
//
// The daily report of one contract (sections 1-11 of the workbook).
//   * Left: what is filled in. Right (wide screens) or second tab: the PDF
//     exactly as it will be printed, refreshed after every change.
//   * Every change is saved on the server at once (autosave); closing the app
//     loses nothing.
//   * Figures from Team Flow / the equipment system are shown with their
//     source. They can be replaced for the day with a manual value (reason
//     required), restored, and their history is kept.
//   * Sections can be switched off for printing (per day).
//   * Issue = full preview, warnings, then the report number is frozen.
// Read only when the account has no dpr.edit (e.g. the Admin).

import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import '../payroll_export_service.dart';
import 'dpr_ucc_report.dart';
import 'dpr_widgets.dart';

class DprReportPage extends StatelessWidget {
  const DprReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const DprContractBar(),
      Expanded(
        child: DprSelection(
          // the client's form (default) or the DPR workbook, as chosen in Setup for the contract
          builder: (ctx, cid, date) => ValueListenableBuilder<Map<int, String>>(
            valueListenable: DprState.templates,
            builder: (_, t, __) => (t[cid] ?? 'ucc') == 'dpr'
                ? DprDayEditor(key: ValueKey('dpr|$cid|$date'), contractId: cid, date: date)
                : UccDayEditor(key: ValueKey('ucc|$cid|$date'), contractId: cid, date: date),
          ),
        ),
      ),
    ]);
  }
}

class DprDayEditor extends StatefulWidget {
  final int contractId;
  final String date;
  const DprDayEditor({super.key, required this.contractId, required this.date});

  @override
  State<DprDayEditor> createState() => _DprDayEditorState();
}

const _textFields = ['weather_remarks', 'tbt_topic', 'hse_observations', 'next_day_plan', 'remarks'];
const _decFields = ['temp_max', 'temp_min', 'humidity', 'wind', 'hours_lost'];
const _intFields = ['tbt_attendees', 'hse_inspections', 'incidents', 'near_misses', 'first_aid', 'lti', 'ptws'];

class _DprDayEditorState extends State<DprDayEditor> with SingleTickerProviderStateMixin {
  Json? _b; // the day bundle from the server
  String? _error;
  int _version = 0;
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, dynamic> _dirty = {};
  Timer? _saveTimer;
  Timer? _pdfTimer;
  bool _saving = false;
  String _saveState = '';
  bool _saveFailed = false;
  Uint8List? _pdf;
  bool _pdfLoading = false;
  String? _pdfError;
  int _pdfSeq = 0;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  int get cid => widget.contractId;
  String get date => widget.date;
  bool get canEdit => DprState.can('dpr.edit');
  bool get canOverride => DprState.can('dpr.override');
  Json get model => asJson(_b?['model']);
  Json get day => asJson(_b?['day']);
  Json get sections => asJson(_b?['sections']);

  @override
  void initState() {
    super.initState();
    for (final k in [..._textFields, ..._decFields, ..._intFields]) {
      _ctl[k] = TextEditingController();
    }
    _load(first: true);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _pdfTimer?.cancel();
    if (_dirty.isNotEmpty) {
      // last change still waiting: send it (fire and forget)
      DprApi.patchDay(cid, date, _version, Map<String, dynamic>.from(_dirty)).catchError((_) => <String, dynamic>{});
    }
    for (final c in _ctl.values) {
      c.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  void _fillControllers() {
    final d = day;
    for (final k in _ctl.keys) {
      _ctl[k]!.text = str(d[k]);
    }
  }

  Future<void> _load({bool first = false, bool refresh = false}) async {
    try {
      final b = await DprApi.day(cid, date, refresh: refresh);
      if (!mounted) return;
      setState(() {
        _b = b;
        _error = null;
        if (first || refresh || _dirty.isEmpty) _version = asInt(b['version']);
        if (first || refresh) _fillControllers();
      });
      _schedulePdf(immediate: first);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  // ---------------------------------------------------------------- autosave
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
      final r = await DprApi.patchDay(cid, date, _version, fields);
      _version = asInt(r['version']);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = false;
        _saveState = 'Saved ✓ ${TimeOfDay.now().format(context)}';
      });
      await _load();
      _schedulePdf();
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
        // keep the change to retry
        fields.forEach((k, v) => _dirty.putIfAbsent(k, () => v));
        setState(() => _saveState = 'Not saved: ${e.message}');
        if (e.status != null && e.status! < 500) {
          dprSnack(context, e.message, error: true);
          _dirty.clear();
        }
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
      if (!mounted) return;
      setState(() {
        _pdfLoading = false;
        _pdfError = e.toString();
      });
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

  // ---------------------------------------------------------------- downloads / issue / copy
  Future<void> _download(String format) async {
    try {
      final bytes = format == 'pdf' ? await DprApi.draftPdf(cid, date) : await DprApi.draftXlsx(cid, date);
      final code = str(asJson(_b?['contract'])['code']);
      final no = str(asJson(model['header'])['report_no']);
      await PayrollExportService.exportBytes(bytes, '${code}_${no}_${date}_DRAFT.$format');
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

  Future<void> _copyFrom() async {
    final sources = asList(_b?['copy_from']);
    if (sources.isEmpty) return;
    final r = await showDialog<_CopyChoice>(context: context, builder: (_) => _CopyDialog(sources: sources));
    if (r == null) return;
    await _run(() async {
      final out = await DprApi.copyDay(cid, date, r.fromId, r.parts);
      if (!mounted) return;
      final skipped = (out['skipped'] as List? ?? const []).map((e) => e.toString()).toList();
      final copied = asJson(out['copied']);
      dprSnack(context, 'Copied from ${str(out['from'])}: ${copied.entries.map((e) => '${e.key} ${e.value}').join(', ')}'
          '${skipped.isNotEmpty ? ' — skipped: ${skipped.join('; ')}' : ''}');
    });
    if (mounted) await _load(refresh: true);
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

  Widget _statusBar() {
    final h = asJson(model['header']);
    final reports = asList(_b?['reports']);
    final issued = reports.where((r) => r['status'] == 'Issued').toList();
    final missing = asList(model['missing']);
    final changed = _b?['changed_since_issue'] == true;
    final copyFrom = asList(_b?['copy_from']);
    Widget chip(String t, Color c, IconData i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: c),
            const SizedBox(width: 5),
            Text(t, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(str(h['report_no']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
        Text('${str(h['day_name'])}  ·  day ${str(h['days_elapsed'])} of ${str(h['revised_duration'])}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        if (issued.isNotEmpty)
          chip('Issued Rev.${str(issued.first['revision'])} · ${str(issued.first['issued_at'])}', const Color(0xff047857), Icons.verified_rounded)
        else
          chip('Draft', AppColors.textSecondary, Icons.edit_note_rounded),
        if (changed) chip('Changed since issue – revise to reissue', const Color(0xffb45309), Icons.history_toggle_off_rounded),
        if (missing.isNotEmpty) chip('${missing.length} missing', const Color(0xffb45309), Icons.rule_rounded),
        if (_saveState.isNotEmpty)
          Text(_saveState, style: TextStyle(fontSize: 12, color: _saveFailed ? AppColors.danger : AppColors.textSecondary)),
        const SizedBox(width: 8),
        if (canEdit && copyFrom.isNotEmpty)
          OutlinedButton.icon(onPressed: _copyFrom, icon: const Icon(Icons.content_copy_rounded, size: 17), label: const Text('Copy from…')),
        OutlinedButton.icon(onPressed: () => _download('pdf'), icon: const Icon(Icons.picture_as_pdf_rounded, size: 17), label: const Text('PDF')),
        OutlinedButton.icon(onPressed: () => _download('xlsx'), icon: const Icon(Icons.grid_on_rounded, size: 17), label: const Text('Excel')),
        IconButton(tooltip: 'Reload figures from the systems', onPressed: () => _load(refresh: true), icon: const Icon(Icons.refresh_rounded)),
        if (issued.isEmpty && DprState.can('dpr.issue'))
          ElevatedButton.icon(style: dprAccentButton(), onPressed: () => _issue(), icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Issue report')),
        if (issued.isNotEmpty && DprState.can('dpr.revise'))
          ElevatedButton.icon(style: dprPrimaryButton(), onPressed: () => _issue(revise: true), icon: const Icon(Icons.restart_alt_rounded, size: 17), label: const Text('Revise')),
      ]),
    );
  }

  Widget _preview() {
    if (_pdf == null) {
      if (_pdfError != null) {
        return DprMessage(icon: Icons.picture_as_pdf_outlined, color: AppColors.danger, text: _pdfError!,
            action: OutlinedButton(onPressed: _loadPdf, child: const Text('Try again')));
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
      if (_pdfLoading)
        const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3, color: AppColors.accent)),
    ]);
  }

  // ---------------------------------------------------------------- the form
  Widget _form() {
    final m = model;
    final warnings = (m['warnings'] as List? ?? const []).map((e) => e.toString()).toList();
    final missing = asList(m['missing']).map((x) => str(x['label'])).toList();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          if (!canEdit) const DprBanner(lines: ['Read only: your account can view this report but not change it.'], color: AppColors.primary, icon: Icons.visibility_rounded),
          DprBanner(lines: warnings),
          if (missing.isNotEmpty)
            DprBanner(lines: ['Not filled in yet: ${missing.join(', ')}.'], color: AppColors.textSecondary, icon: Icons.rule_rounded),
          _headerCard(),
          _weatherCard(),
          _manpowerCard(),
          _subconCard(),
          _summaryCard(),
          _workCard(),
          _qaCard(),
          _hseCard(),
          _registersCard(),
          _textCard('plan', '9. Planned activities – next working day', Icons.event_note_rounded, 'next_day_plan'),
          _textCard('remarks', '10. General remarks / instructions / RFIs / visitors', Icons.sticky_note_2_rounded, 'remarks'),
          _photosCard(),
          _printCard(),
        ],
      ),
    );
  }

  Widget _printSwitch(String key) {
    final on = sections[key] != false;
    return Tooltip(
      message: on ? 'Printed — tap to leave out of the report' : 'Not printed — tap to print',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: canEdit
            ? () {
                final s = Map<String, dynamic>.from(sections);
                s[key] = !on;
                setState(() => _b!['sections'] = s);
                _changed('sections', s);
              }
            : null,
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

  Widget _headerCard() {
    final h = asJson(model['header']);
    Widget kv(String k, String v) => SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(v.isEmpty ? '—' : v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        );
    final cur = str(h['currency']);
    return DprCard(
      title: str(h['project_name']).isEmpty ? 'Project' : str(h['project_name']),
      subtitle: 'From Setup — change it there',
      icon: Icons.apartment_rounded,
      child: Wrap(children: [
        kv('Agreement No.', str(h['agreement_no'])),
        kv('Client', str(h['client'])),
        kv('Consultant', str(h['consultant'])),
        kv('Main contractor', str(h['main_contractor'])),
        kv('Contract value ($cur)', fmtQty(h['contract_value'])),
        kv('Commencement', fmtDay(h['commencement_date'])),
        kv('Original completion', fmtDay(h['original_completion'])),
        kv('EOT / VO granted', '${str(h['eot_days'])} days EOT | VO: $cur ${fmtQty(h['vo_value'])}'),
        kv('Revised completion', fmtDay(h['revised_completion'])),
        kv('Days remaining', str(h['days_remaining'])),
        kv('% Time elapsed', fmtPct(h['time_elapsed'])),
        kv('% Physical progress (BOQ)', fmtPct(h['physical_progress'])),
      ]),
    );
  }

  List<String> _list(String k) => (asJson(_b?['lists'])[k] as List? ?? const []).map((e) => e.toString()).toList();

  Widget _dropdown(String key, String label, List<String> items) {
    final v = str(day[key]);
    final all = [...items];
    if (v.isNotEmpty && !all.contains(v)) all.insert(0, v);
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        value: v.isEmpty ? null : v,
        isExpanded: true,
        decoration: dprInput(label),
        items: all.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
        onChanged: canEdit
            ? (x) {
                setState(() => _b!['day'] = {...day, key: x});
                _changed(key, x);
              }
            : null,
      ),
    );
  }

  Widget _numField(String key, String label, {bool decimal = true, double width = 120}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: _ctl[key],
        enabled: canEdit,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.\-]' : r'[0-9]'))],
        decoration: dprInput(label),
        onChanged: (t) => _changed(key, t.trim().isEmpty ? null : t.trim()),
      ),
    );
  }

  Widget _textField(String key, String label, {int lines = 1}) {
    return TextField(
      controller: _ctl[key],
      enabled: canEdit,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      decoration: dprInput(label),
      onChanged: (t) => _changed(key, t),
    );
  }

  Widget _weatherCard() {
    return DprCard(
      title: '1. Weather & site conditions',
      icon: Icons.wb_sunny_rounded,
      actions: [_printSwitch('weather')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _dropdown('weather_am', 'Morning', _list('weather')),
          _dropdown('weather_pm', 'Afternoon', _list('weather')),
          _numField('temp_max', 'Max °C', width: 100),
          _numField('temp_min', 'Min °C', width: 100),
          _numField('humidity', 'Humidity %', width: 110),
          _numField('wind', 'Wind km/h', width: 110),
          _numField('hours_lost', 'Hours lost', width: 110),
        ]),
        const SizedBox(height: 10),
        _textField('weather_remarks', 'Remarks / midday-break compliance'),
      ]),
    );
  }

  // ---------------------------------------------------------------- counts
  Future<void> _editCount(Json row) async {
    final src = asJson(row['source']);
    final mode = str(src['mode']);
    final lineId = asInt(row['line_id']);
    final name = row['subcontractor'] != null && str(row['subcontractor']).isNotEmpty ? '${str(row['subcontractor'])} – ${str(row['name'])}' : str(row['name']);
    if (mode == 'manual' || mode.isEmpty) {
      if (!canEdit) return;
      final v = await showDialog<int>(context: context, builder: (_) => _IntDialog(title: name, initial: asInt(row['today'])));
      if (v == null) return;
      await _run(() => DprApi.setCount(cid, date, lineId, v));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _OverrideDialog(
        contractId: cid,
        date: date,
        lineId: lineId,
        name: name,
        source: src,
        current: asInt(row['today']),
        canOverride: canOverride,
        onChanged: _afterChange,
      ),
    );
  }

  Widget _todayCell(Json row) {
    final src = asJson(row['source']);
    final mode = str(src['mode']).isEmpty ? 'manual' : str(src['mode']);
    final unavailable = src['unavailable'] == true;
    final clickable = (mode == 'manual' && canEdit) || mode != 'manual';
    return InkWell(
      onTap: clickable ? () => _editCount(row) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(unavailable && mode == 'system' ? '?' : str(row['today']),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: mode == 'override' ? const Color(0xffb45309) : AppColors.textPrimary)),
          const SizedBox(width: 6),
          SourceTag(mode: mode, system: str(src['system'])),
          if (clickable) ...[
            const SizedBox(width: 4),
            Icon(mode == 'manual' ? Icons.edit_rounded : Icons.tune_rounded, size: 14, color: AppColors.textSecondary),
          ],
        ]),
      ),
    );
  }

  DataRow _lineRow(Json r, {bool plant = false}) {
    final idle = asInt(r['idle']);
    return DataRow(cells: [
      DataCell(dprCell(str(r['name']), bold: true, width: 170)),
      DataCell(dprCell(plant ? str(r['ownership']) : str(r['category']), color: AppColors.textSecondary)),
      DataCell(_todayCell(r)),
      DataCell(dprCell(fmtQty(r['allocated'], dash: true), align: TextAlign.center)),
      DataCell(dprCell(fmtQty(r['idle'], dash: true), color: idle < 0 ? AppColors.danger : null, bold: idle < 0)),
      DataCell(dprCell(fmtQty(r['cum']))),
    ]);
  }

  DataRow _totalRow(String label, Json t) => DataRow(
        color: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.06)),
        cells: [
          DataCell(dprCell(label, bold: true)),
          DataCell(dprCell('')),
          DataCell(dprCell(str(t['today']), bold: true)),
          DataCell(dprCell(str(t['allocated']), bold: true)),
          DataCell(dprCell(str(t['idle']), bold: true)),
          DataCell(dprCell(fmtQty(t['cum']), bold: true)),
        ],
      );

  Widget _manpowerCard() {
    final p = asJson(model['manpower']);
    final trades = asList(p['trades']);
    final plant = asList(p['plant']);
    final cats = asList(p['by_category']);
    return DprCard(
      title: '2. Own manpower by trade & own plant',
      subtitle: 'Tap a figure to see its source, change it for the day, or restore it',
      icon: Icons.engineering_rounded,
      actions: [_printSwitch('manpower')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDataTableCard(
          title: 'Own manpower',
          icon: Icons.groups_rounded,
          padding: const EdgeInsets.all(10),
          emptyMessage: 'No trade lines. Add them in Setup.',
          columns: [dprCol('Trade'), dprCol('Category'), dprCol('Today'), dprCol('Allocated'), dprCol('Idle / Indirect'), dprCol('Cum. Man-days')],
          rows: [...trades.map((r) => _lineRow(r)), if (trades.isNotEmpty) _totalRow('TOTAL OWN MANPOWER', asJson(p['own_manpower']))],
        ),
        const SizedBox(height: 10),
        AppDataTableCard(
          title: 'Own plant / equipment',
          icon: Icons.precision_manufacturing_rounded,
          padding: const EdgeInsets.all(10),
          emptyMessage: 'No plant lines. Add them in Setup.',
          columns: [dprCol('Equipment'), dprCol('Ownership'), dprCol('Today'), dprCol('Allocated'), dprCol('Idle'), dprCol('Cum. Equip-days')],
          rows: [...plant.map((r) => _lineRow(r, plant: true)), if (plant.isNotEmpty) _totalRow('TOTAL OWN PLANT', asJson(p['own_plant']))],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cats
              .where((c) => asInt(c['today']) > 0 || (asNum(c['cum']) ?? 0) > 0)
              .map((c) => Chip(
                    backgroundColor: AppColors.background,
                    side: const BorderSide(color: AppColors.border),
                    label: Text('${str(c['category'])}: ${str(c['today'])} today · ${fmtQty(c['cum'])} cum.', style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
        ),
      ]),
    );
  }

  Widget _subconCard() {
    final s = asJson(model['subcontractors']);
    final lines = asList(s['lines']);
    DataRow row(Json r) {
      final idle = asInt(r['idle']);
      return DataRow(cells: [
        DataCell(dprCell(str(r['subcontractor']), bold: true, width: 150)),
        DataCell(dprCell(str(r['name']), width: 130)),
        DataCell(dprCell(str(r['res_type']), color: AppColors.textSecondary)),
        DataCell(_todayCell(r)),
        DataCell(dprCell(fmtQty(r['allocated'], dash: true))),
        DataCell(dprCell(fmtQty(r['idle'], dash: true), color: idle < 0 ? AppColors.danger : null)),
        DataCell(dprCell(fmtQty(r['cum']))),
        DataCell(dprCell(fmtQty(r['cum_hours']))),
      ]);
    }

    DataRow tot(String label, Json t) => DataRow(
          color: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.06)),
          cells: [
            DataCell(dprCell(label, bold: true)),
            DataCell(dprCell('')),
            DataCell(dprCell('')),
            DataCell(dprCell(str(t['today']), bold: true)),
            DataCell(dprCell(str(t['allocated']), bold: true)),
            DataCell(dprCell(str(t['idle']), bold: true)),
            DataCell(dprCell(fmtQty(t['cum']), bold: true)),
            DataCell(dprCell(fmtQty(t['cum_hours']), bold: true)),
          ],
        );
    return DprCard(
      title: '3. Subcontractor resources',
      icon: Icons.handshake_rounded,
      actions: [_printSwitch('subcon')],
      child: AppDataTableCard(
        title: 'Subcontractors',
        icon: Icons.handshake_rounded,
        padding: const EdgeInsets.all(10),
        emptyMessage: 'No subcontractor lines. Add them in Setup.',
        columns: [dprCol('Subcontractor'), dprCol('Resource'), dprCol('Type'), dprCol('Today'), dprCol('Allocated'), dprCol('Idle'), dprCol('Cum. days'), dprCol('Cum. hours')],
        rows: [
          ...lines.map(row),
          if (lines.isNotEmpty) tot('MANPOWER TOTAL', asJson(s['manpower'])),
          if (lines.isNotEmpty) tot('PLANT TOTAL', asJson(s['plant'])),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final s = asJson(model['summary']);
    return DprCard(
      title: 'Resource summary',
      icon: Icons.summarize_rounded,
      actions: [_printSwitch('summary')],
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        DprKpi(label: 'Total manpower on site', value: str(s['total_manpower']), icon: Icons.groups_rounded),
        DprKpi(label: 'Total plant on site', value: str(s['total_plant']), icon: Icons.local_shipping_rounded),
        DprKpi(label: 'Man-hours today', value: fmtQty(s['man_hours_today']), icon: Icons.schedule_rounded),
        DprKpi(label: 'Cum. man-days', value: fmtQty(s['cum_man_days']), icon: Icons.stacked_bar_chart_rounded),
        DprKpi(label: 'Cum. man-hours', value: fmtQty(s['cum_man_hours']), icon: Icons.timelapse_rounded),
      ]),
    );
  }

  // ---------------------------------------------------------------- activities
  Future<void> _editActivity([Json? a]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ActivityDialog(
        contractId: cid,
        date: date,
        activity: a,
        boq: asList(_b?['boq']),
        lines: asList(_b?['lines']),
      ),
    );
    if (saved == true) await _afterChange();
  }

  Widget _workCard() {
    final w = asJson(model['work']);
    final acts = asList(w['activities']);
    final raw = {for (final a in asList(_b?['activities'])) asInt(a['activity_id']): a};
    return DprCard(
      title: '4. Work progress – activities & BOQ quantities',
      icon: Icons.construction_rounded,
      actions: [
        _printSwitch('work'),
        if (canEdit)
          IconButton(tooltip: 'Add activity', onPressed: () => _editActivity(), icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDataTableCard(
          title: 'Activities executed today',
          subtitle: 'Man-hours = crew allocated × hours / day (Setup)',
          icon: Icons.construction_rounded,
          padding: const EdgeInsets.all(10),
          emptyMessage: canEdit ? 'No activity yet. Tap + to add one.' : 'No activity.',
          columns: [dprCol('BOQ'), dprCol('Description'), dprCol('Location'), dprCol('Unit'), dprCol('Contract'), dprCol('Today'),
            dprCol('Prev. cum.'), dprCol('Cum.'), dprCol('%'), dprCol('Balance'), dprCol('Crew'), dprCol('MH'), dprCol('Out/MH'), dprCol('')],
          rows: acts.map((a) {
            final id = asInt(a['activity_id']);
            return DataRow(cells: [
              DataCell(dprCell(str(a['item_no']), bold: true)),
              DataCell(dprCell(str(a['description']), width: 180)),
              DataCell(dprCell(str(a['location']), width: 110)),
              DataCell(dprCell(str(a['unit']))),
              DataCell(dprCell(fmtQty(a['contract_qty'], minDecimals: 1))),
              DataCell(dprCell(fmtQty(a['today'], minDecimals: 1), bold: true)),
              DataCell(dprCell(fmtQty(a['prev_cum'], minDecimals: 1))),
              DataCell(dprCell(fmtQty(a['cum'], minDecimals: 1), bold: true)),
              DataCell(dprCell(fmtPct(a['pct']))),
              DataCell(dprCell(fmtQty(a['balance'], minDecimals: 1))),
              DataCell(dprCell(str(a['crew']))),
              DataCell(dprCell(fmtQty(a['man_hours']))),
              DataCell(dprCell(fmtRatio(a['output_per_mh']))),
              DataCell(canEdit
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                          onPressed: () => _editActivity(raw[id])),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                        onPressed: () async {
                          if (await dprConfirm(context, 'Delete activity', 'Delete ${str(a['item_no'])} – ${str(a['location'])}?', ok: 'Delete', danger: true)) {
                            await _run(() => DprApi.deleteActivity(cid, date, id));
                          }
                        },
                      ),
                    ])
                  : const SizedBox.shrink()),
            ]);
          }).toList(),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          Text('Activities: ${str(w['count'])}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
          Text('Man-hours allocated: ${fmtQty(w['man_hours_allocated'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Unallocated / indirect: ${fmtQty(w['unallocated_man_hours'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- QA
  Future<void> _editQa([Json? q]) async {
    final r = await showDialog<Json>(context: context, builder: (_) => _QaDialog(qa: q, types: _list('qa_types'), results: _list('qa_results')));
    if (r == null) return;
    await _run(() => DprApi.saveQa(cid, date, q == null ? null : asInt(q['qa_id']), r));
  }

  Widget _qaCard() {
    final list = asList(_b?['qa']);
    return DprCard(
      title: '5. Quality assurance / quality control',
      icon: Icons.verified_rounded,
      actions: [
        _printSwitch('qa'),
        if (canEdit) IconButton(tooltip: 'Add entry', onPressed: () => _editQa(), icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary)),
      ],
      child: AppDataTableCard(
        title: 'QA / QC entries today',
        icon: Icons.fact_check_rounded,
        padding: const EdgeInsets.all(10),
        emptyMessage: 'No QA / QC entry today.',
        columns: [dprCol('Type'), dprCol('Ref No.'), dprCol('Description'), dprCol('Location'), dprCol('Result'), dprCol('Remarks'), dprCol('')],
        rows: list
            .map((q) => DataRow(cells: [
                  DataCell(dprCell(str(q['type']), bold: true)),
                  DataCell(dprCell(str(q['ref_no']))),
                  DataCell(dprCell(str(q['description']), width: 200)),
                  DataCell(dprCell(str(q['location']), width: 120)),
                  DataCell(StatusBadge.fromStatus(str(q['result']).isEmpty ? '—' : str(q['result']))),
                  DataCell(dprCell(str(q['remarks']), width: 140)),
                  DataCell(canEdit
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary), onPressed: () => _editQa(q)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                            onPressed: () async {
                              if (await dprConfirm(context, 'Delete entry', 'Delete ${str(q['type'])} ${str(q['ref_no'])}?', ok: 'Delete', danger: true)) {
                                await _run(() => DprApi.deleteQa(cid, date, asInt(q['qa_id'])));
                              }
                            },
                          ),
                        ])
                      : const SizedBox.shrink()),
                ]))
            .toList(),
      ),
    );
  }

  // ---------------------------------------------------------------- HSE
  Widget _hseCard() {
    final h = asJson(model['hse']);
    final ltifr = h['ltifr'] == null ? '—' : '${fmtRatio(h['ltifr'])} / ${fmtRatio(h['trir'])}';
    return DprCard(
      title: '6. Health, safety & environment',
      icon: Icons.health_and_safety_rounded,
      actions: [_printSwitch('hse')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _numField('incidents', 'Incidents today', decimal: false, width: 140),
          _numField('near_misses', 'Near misses today', decimal: false, width: 150),
          _numField('first_aid', 'First aid cases', decimal: false, width: 140),
          _numField('lti', 'LTI today', decimal: false, width: 110),
          _numField('ptws', 'PTWs issued', decimal: false, width: 120),
          _numField('hse_inspections', 'HSE inspections', decimal: false, width: 140),
          _numField('tbt_attendees', 'Toolbox talk attendees', decimal: false, width: 180),
        ]),
        const SizedBox(height: 10),
        _textField('tbt_topic', 'Toolbox talk topic'),
        const SizedBox(height: 10),
        _textField('hse_observations', 'HSE observations & corrective actions', lines: 2),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          DprKpi(label: 'Safe man-hours since last LTI', value: fmtQty(h['safe_man_hours']), icon: Icons.shield_rounded, color: const Color(0xff047857)),
          DprKpi(label: 'LTI-free days', value: str(h['lti_free_days']), icon: Icons.event_available_rounded, color: const Color(0xff047857)),
          DprKpi(label: 'LTIs to date', value: str(h['ltis_to_date']), icon: Icons.personal_injury_rounded, color: AppColors.danger),
          DprKpi(label: 'Near misses to date', value: str(h['near_misses_to_date']), icon: Icons.report_problem_rounded, color: const Color(0xffb45309)),
          DprKpi(label: 'LTIFR / TRIR (200k MH)', value: ltifr, icon: Icons.query_stats_rounded),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- NCR / concerns (as of the report date)
  Widget _registersCard() {
    final ncr = asList(asJson(model['ncr'])['entries']);
    final con = asList(asJson(model['concerns'])['entries']);
    return DprCard(
      title: '7 – 8. NCRs and areas of concern (open as of this date)',
      subtitle: 'Kept in the registers (Registers page). Status is shown as it was on the report date.',
      icon: Icons.report_rounded,
      actions: [_printSwitch('ncr'), _printSwitch('concerns')],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDataTableCard(
          title: 'Non-conformance reports',
          icon: Icons.report_gmailerrorred_rounded,
          accentColor: AppColors.danger,
          padding: const EdgeInsets.all(10),
          emptyMessage: 'No open NCR on this date.',
          columns: [dprCol('NCR No.'), dprCol('Raised'), dprCol('Description'), dprCol('Responsible'), dprCol('Target'), dprCol('Status'), dprCol('Days open')],
          rows: ncr
              .map((x) => DataRow(cells: [
                    DataCell(dprCell(str(x['ncr_no']), bold: true)),
                    DataCell(dprCell(fmtDay(x['date_raised']))),
                    DataCell(dprCell(str(x['description']), width: 220)),
                    DataCell(dprCell(str(x['responsible']))),
                    DataCell(dprCell(fmtDay(x['target_date']))),
                    DataCell(StatusBadge.fromStatus(str(x['status']) == 'Open' ? 'Pending' : 'Completed')),
                    DataCell(dprCell(str(x['days_open']))),
                  ]))
              .toList(),
        ),
        const SizedBox(height: 10),
        AppDataTableCard(
          title: 'Areas of concern / delays / constraints',
          icon: Icons.warning_amber_rounded,
          accentColor: const Color(0xffb45309),
          padding: const EdgeInsets.all(10),
          emptyMessage: 'No open concern on this date.',
          columns: [dprCol('Raised'), dprCol('Issue'), dprCol('Impact'), dprCol('Severity'), dprCol('By whom'), dprCol('Target')],
          rows: con
              .map((x) => DataRow(cells: [
                    DataCell(dprCell(fmtDay(x['date_raised']))),
                    DataCell(dprCell(str(x['issue']), width: 240)),
                    DataCell(dprCell(str(x['impact']))),
                    DataCell(dprCell(str(x['severity']), bold: true, color: str(x['severity']) == 'High' ? AppColors.danger : null)),
                    DataCell(dprCell(str(x['by_whom']))),
                    DataCell(dprCell(fmtDay(x['target_date']))),
                  ]))
              .toList(),
        ),
      ]),
    );
  }

  Widget _textCard(String section, String title, IconData icon, String field) {
    return DprCard(
      title: title,
      icon: icon,
      actions: [_printSwitch(section)],
      child: _textField(field, title.replaceFirst(RegExp(r'^\d+\.\s*'), ''), lines: 3),
    );
  }

  // ---------------------------------------------------------------- photos
  Future<void> _addPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? f = await picker.pickImage(source: source, maxWidth: 2200, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final name = f.name.toLowerCase().endsWith('.png') || f.name.toLowerCase().endsWith('.jpg') ||
              f.name.toLowerCase().endsWith('.jpeg') || f.name.toLowerCase().endsWith('.webp')
          ? f.name
          : '${f.name}.jpg';
      await _run(() async {
        await DprApi.addPhoto(cid, date, bytes, name, {});
      }, done: 'Photo added.');
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _addPhotoFile() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Photos', extensions: ['jpg', 'jpeg', 'png', 'webp']),
    ]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    await _run(() async {
      await DprApi.addPhoto(cid, date, bytes, f.name, {});
    }, done: 'Photo added.');
  }

  Widget _photosCard() {
    final photos = asList(_b?['photos']);
    return DprCard(
      title: '11. Site photographs',
      subtitle: '6 per page in the report (more photos add pages)',
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
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No photo for this day.', style: TextStyle(color: AppColors.textSecondary)),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: photos
                  .map((p) => _PhotoTile(
                        key: ValueKey(p['photo_id']),
                        contractId: cid,
                        date: date,
                        photo: p,
                        canEdit: canEdit,
                        onChanged: _afterChange,
                      ))
                  .toList(),
            ),
    );
  }

  Widget _printCard() {
    final list = asList(_b?['section_list']);
    return DprCard(
      title: 'Printed sections',
      subtitle: 'Choose what this day\'s report contains (also from each section)',
      icon: Icons.print_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: list.map((s) {
          final k = str(s['key']);
          final on = sections[k] != false;
          return FilterChip(
            label: Text(str(s['label'])),
            selected: on,
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            checkmarkColor: AppColors.primary,
            onSelected: canEdit
                ? (v) {
                    final m = Map<String, dynamic>.from(sections);
                    m[k] = v;
                    setState(() => _b!['sections'] = m);
                    _changed('sections', m);
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }
}

// ======================================================================
// Dialogs
// ======================================================================
/// "120.5000" -> "120.5", "120.0000" -> "120" (DECIMAL from the server, shown without useless zeros).
String _trimDec(String s) {
  if (!s.contains('.')) return s;
  final t = s.replaceFirst(RegExp(r'0+$'), '');
  return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
}

class _IntDialog extends StatefulWidget {
  final String title;
  final int initial;
  const _IntDialog({required this.title, required this.initial});

  @override
  State<_IntDialog> createState() => _IntDialogState();
}

class _IntDialogState extends State<_IntDialog> {
  late final TextEditingController _c = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Number on site today (typed every day: this line has no system source).',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: dprInput('Today'),
            onSubmitted: (_) => Navigator.pop(context, int.tryParse(_c.text.trim()) ?? 0),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(style: dprPrimaryButton(), onPressed: () => Navigator.pop(context, int.tryParse(_c.text.trim()) ?? 0), child: const Text('Save')),
      ],
    );
  }
}

class _OverrideDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final int lineId;
  final String name;
  final Json source;
  final int current;
  final bool canOverride;
  final Future<void> Function() onChanged;
  const _OverrideDialog({
    required this.contractId,
    required this.date,
    required this.lineId,
    required this.name,
    required this.source,
    required this.current,
    required this.canOverride,
    required this.onChanged,
  });

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late final TextEditingController _value = TextEditingController(text: '${widget.current}');
  final TextEditingController _reason = TextEditingController();
  List<Json>? _history;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await DprApi.overrideHistory(widget.contractId, widget.date, widget.lineId);
      if (mounted) setState(() => _history = h);
    } catch (_) {
      if (mounted) setState(() => _history = []);
    }
  }

  Future<void> _do(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
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
    final s = widget.source;
    final ov = asJson(s['override']);
    final isOverride = str(s['mode']) == 'override';
    final sys = s['system_value'];
    return AlertDialog(
      title: Text(widget.name),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Value from ${str(s['system']).isEmpty ? 'the system' : str(s['system'])}: ${sys == null ? 'not available now' : str(sys)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(isOverride
                    ? 'Used in the report: ${str(ov['value'])} (manual, by ${str(ov['by'])} ${str(ov['at'])}) — reason: ${str(ov['reason'])}'
                    : 'Used in the report: the system value.',
                    style: TextStyle(color: isOverride ? const Color(0xffb45309) : AppColors.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 4),
                const Text('The system data itself is never changed: the manual value only replaces it in this report.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ]),
            ),
            if (widget.canOverride) ...[
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _value,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: dprInput('Manual value'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _reason, enabled: !_busy, decoration: dprInput('Reason (required)'))),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            const Text('History of this figure today', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_history == null)
              const LinearProgressIndicator(minHeight: 2, color: AppColors.primary)
            else if (_history!.isEmpty)
              const Text('No manual value so far.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5))
            else
              ..._history!.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(h['active'] == true ? Icons.radio_button_checked_rounded : Icons.history_rounded,
                          size: 16, color: h['active'] == true ? const Color(0xffb45309) : AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${str(h['value'])} (system then: ${h['system_value'] == null ? '—' : str(h['system_value'])}) · ${str(h['created_by'])} ${str(h['created_at'])}'
                          ' · ${str(h['reason'])}${h['active'] == true ? '' : ' · removed ${str(h['reverted_at'])} by ${str(h['reverted_by'])}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (widget.canOverride && h['active'] != true)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _value.text = str(h['value']);
                                  _reason.text = 'Restored: ${str(h['reason'])}';
                                },
                          child: const Text('Use again'),
                        ),
                    ]),
                  )),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
        if (widget.canOverride && isOverride)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _do(() => DprApi.revertOverride(widget.contractId, widget.date, widget.lineId)),
            icon: const Icon(Icons.undo_rounded, size: 17),
            label: const Text('Use the system value'),
          ),
        if (widget.canOverride)
          ElevatedButton(
            style: dprPrimaryButton(),
            onPressed: _busy
                ? null
                : () {
                    final v = int.tryParse(_value.text.trim());
                    if (v == null) {
                      setState(() => _error = 'Enter a whole number.');
                      return;
                    }
                    if (_reason.text.trim().length < 3) {
                      setState(() => _error = 'Write the reason of the change.');
                      return;
                    }
                    _do(() => DprApi.setOverride(widget.contractId, widget.date, widget.lineId, v, _reason.text.trim()));
                  },
            child: const Text('Save manual value'),
          ),
      ],
    );
  }
}

class _ActivityDialog extends StatefulWidget {
  final int contractId;
  final String date;
  final Json? activity;
  final List<Json> boq;
  final List<Json> lines;
  const _ActivityDialog({required this.contractId, required this.date, required this.activity, required this.boq, required this.lines});

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  int? _boqId;
  late final TextEditingController _loc = TextEditingController(text: str(widget.activity?['location']));
  late final TextEditingController _qty = TextEditingController(text: _trimDec(str(widget.activity?['qty'])));
  late final TextEditingController _rem = TextEditingController(text: str(widget.activity?['remarks']));
  final Map<int, TextEditingController> _alloc = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boqId = widget.activity == null ? null : asInt(widget.activity!['boq_id']);
    final a = asJson(widget.activity?['alloc']);
    for (final l in widget.lines) {
      final id = asInt(l['line_id']);
      final v = a['$id'];
      _alloc[id] = TextEditingController(text: v == null || asInt(v) == 0 ? '' : '${asInt(v)}');
    }
  }

  @override
  void dispose() {
    _loc.dispose();
    _qty.dispose();
    _rem.dispose();
    for (final c in _alloc.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBoq() async {
    final picked = await showDialog<int>(context: context, builder: (_) => _BoqPicker(boq: widget.boq));
    if (picked != null) setState(() => _boqId = picked);
  }

  Future<void> _save() async {
    if (_boqId == null) {
      setState(() => _error = 'Choose the BOQ item.');
      return;
    }
    if (_qty.text.trim().isEmpty) {
      setState(() => _error = 'Enter the quantity done today.');
      return;
    }
    final alloc = <String, int>{};
    _alloc.forEach((k, c) {
      final v = int.tryParse(c.text.trim()) ?? 0;
      if (v > 0) alloc['$k'] = v;
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DprApi.saveActivity(widget.contractId, widget.date, widget.activity == null ? null : asInt(widget.activity!['activity_id']), {
        'boq_id': _boqId,
        'location': _loc.text.trim(),
        'qty': _qty.text.trim(),
        'remarks': _rem.text.trim(),
        'alloc': alloc,
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

  Widget _allocGroup(String title, List<Json> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 12.5)),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: lines.map((l) {
          final id = asInt(l['line_id']);
          final label = str(l['subcontractor']).isNotEmpty ? '${str(l['subcontractor'])} – ${str(l['name'])}' : str(l['name']);
          return SizedBox(
            width: 170,
            child: TextField(
              controller: _alloc[id],
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: dprInput(label),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Json? b;
    for (final x in widget.boq) {
      if (asInt(x['boq_id']) == _boqId) b = x;
    }
    final trades = widget.lines.where((l) => l['kind'] == 'trade').toList();
    final plant = widget.lines.where((l) => l['kind'] == 'plant').toList();
    final sub = widget.lines.where((l) => l['kind'] == 'subcon').toList();
    return AlertDialog(
      title: Text(widget.activity == null ? 'New activity' : 'Edit activity'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              onTap: _busy ? null : _pickBoq,
              child: InputDecorator(
                decoration: dprInput('BOQ item', suffix: const Icon(Icons.search_rounded)),
                child: Text(b == null ? 'Choose…' : '${str(b['item_no'])} — ${str(b['description'])} (${str(b['unit'])})',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _loc, enabled: !_busy, decoration: dprInput('Location / zone / level'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _qty,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: dprInput('Qty today${b == null ? '' : ' (${str(b['unit'])})'}'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _rem, enabled: !_busy, decoration: dprInput('Remarks')),
            const SizedBox(height: 6),
            const Text('Crew / plant on this activity (feeds Allocated, Idle and the man-hours):',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            _allocGroup('Own manpower', trades),
            _allocGroup('Own plant', plant),
            _allocGroup('Subcontractors', sub),
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

class _BoqPicker extends StatefulWidget {
  final List<Json> boq;
  const _BoqPicker({required this.boq});

  @override
  State<_BoqPicker> createState() => _BoqPickerState();
}

class _BoqPickerState extends State<_BoqPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.boq
        .where((b) => q.isEmpty || str(b['item_no']).toLowerCase().contains(q) || str(b['description']).toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: const Text('BOQ item'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: dprInput('Search item no. or description', suffix: const Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No BOQ item. Add the BOQ in Setup.'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = list[i];
                      return ListTile(
                        dense: true,
                        leading: Text(str(b['item_no']), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                        title: Text(str(b['description']), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${str(b['unit'])} · contract ${fmtQty(b['contract_qty'])}'),
                        onTap: () => Navigator.pop(context, asInt(b['boq_id'])),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _QaDialog extends StatefulWidget {
  final Json? qa;
  final List<String> types;
  final List<String> results;
  const _QaDialog({required this.qa, required this.types, required this.results});

  @override
  State<_QaDialog> createState() => _QaDialogState();
}

class _QaDialogState extends State<_QaDialog> {
  late String? _type = str(widget.qa?['type']).isEmpty ? null : str(widget.qa?['type']);
  late String? _result = str(widget.qa?['result']).isEmpty ? null : str(widget.qa?['result']);
  late final TextEditingController _ref = TextEditingController(text: str(widget.qa?['ref_no']));
  late final TextEditingController _desc = TextEditingController(text: str(widget.qa?['description']));
  late final TextEditingController _loc = TextEditingController(text: str(widget.qa?['location']));
  late final TextEditingController _rem = TextEditingController(text: str(widget.qa?['remarks']));
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    _desc.dispose();
    _loc.dispose();
    _rem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = [...widget.types];
    if (_type != null && !types.contains(_type)) types.add(_type!);
    final results = [...widget.results];
    if (_result != null && !results.contains(_result)) results.add(_result!);
    return AlertDialog(
      title: Text(widget.qa == null ? 'New QA / QC entry' : 'Edit QA / QC entry'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _type,
                  decoration: dprInput('Type'),
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _ref, decoration: dprInput('Ref No.'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _desc, decoration: dprInput('Description / activity')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _loc, decoration: dprInput('Location'))),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _result,
                  decoration: dprInput('Result'),
                  items: results.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _result = v),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _rem, decoration: dprInput('Remarks')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: dprPrimaryButton(),
          onPressed: () {
            if (_type == null) {
              setState(() => _error = 'Choose the type.');
              return;
            }
            Navigator.pop<Json>(context, {
              'type': _type,
              'ref_no': _ref.text.trim(),
              'description': _desc.text.trim(),
              'location': _loc.text.trim(),
              'result': _result ?? '',
              'remarks': _rem.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatefulWidget {
  final int contractId;
  final String date;
  final Json photo;
  final bool canEdit;
  final Future<void> Function() onChanged;
  const _PhotoTile({super.key, required this.contractId, required this.date, required this.photo, required this.canEdit, required this.onChanged});

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  Uint8List? _bytes;
  bool _failed = false;
  late final TextEditingController _act = TextEditingController(text: str(widget.photo['boq_activity']));
  late final TextEditingController _loc = TextEditingController(text: str(widget.photo['location']));
  late final TextEditingController _cap = TextEditingController(text: str(widget.photo['caption']));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final b = await DprApi.photoBytes(widget.contractId, asInt(widget.photo['photo_id']));
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _act.dispose();
    _loc.dispose();
    _cap.dispose();
    super.dispose();
  }

  void _changed() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1000), () async {
      try {
        await DprApi.updatePhoto(widget.contractId, widget.date, asInt(widget.photo['photo_id']), {
          'slot': widget.photo['slot'],
          'boq_activity': _act.text.trim(),
          'location': _loc.text.trim(),
          'caption': _cap.text.trim(),
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
                        : const CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
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
            TextField(controller: _act, enabled: widget.canEdit, decoration: dprInput('BOQ / activity'), onChanged: (_) => _changed()),
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

class _CopyChoice {
  final int fromId;
  final List<String> parts;
  const _CopyChoice(this.fromId, this.parts);
}

class _CopyDialog extends StatefulWidget {
  final List<Json> sources;
  const _CopyDialog({required this.sources});

  @override
  State<_CopyDialog> createState() => _CopyDialogState();
}

class _CopyDialogState extends State<_CopyDialog> {
  late int _from = asInt(widget.sources.first['contract_id']);
  static const _parts = {
    'weather': 'Weather & site conditions',
    'hse': 'Health, safety & environment',
    'plan': 'Planned activities – next day',
    'remarks': 'General remarks',
    'counts': 'Typed counts (lines without a system source)',
    'overrides': 'Manual values over system figures',
    'qa': 'QA / QC entries (added)',
    'activities': 'Activities with the same BOQ item no. (added)',
  };
  final Set<String> _on = {'weather', 'hse', 'plan', 'counts', 'overrides'};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy from another contract'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Same date. What you tick replaces (or is added to) this contract\'s day; the other contract is not changed.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _from,
              decoration: dprInput('Copy from'),
              items: widget.sources
                  .map((s) => DropdownMenuItem(value: asInt(s['contract_id']), child: Text('${str(s['code'])} · ${str(s['title'])}')))
                  .toList(),
              onChanged: (v) => setState(() => _from = v ?? _from),
            ),
            const SizedBox(height: 6),
            ..._parts.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  value: _on.contains(e.key),
                  title: Text(e.value, style: const TextStyle(fontSize: 13)),
                  onChanged: (v) => setState(() => v == true ? _on.add(e.key) : _on.remove(e.key)),
                )),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: dprPrimaryButton(),
          onPressed: _on.isEmpty ? null : () => Navigator.pop(context, _CopyChoice(_from, _on.toList())),
          child: const Text('Copy'),
        ),
      ],
    );
  }
}

/// Full preview before issuing (or revising): the PDF, what is missing, the
/// warnings, then confirm.
class DprIssuePage extends StatefulWidget {
  final int contractId;
  final String date;
  final bool revise;
  final Json model;
  const DprIssuePage({super.key, required this.contractId, required this.date, required this.revise, required this.model});

  @override
  State<DprIssuePage> createState() => DprIssuePageState();
}

class DprIssuePageState extends State<DprIssuePage> {
  Uint8List? _pdf;
  String? _error;
  bool _busy = false;
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final b = await DprApi.draftPdf(widget.contractId, widget.date);
      if (mounted) setState(() => _pdf = b);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _go({bool acceptSources = false}) async {
    if (widget.revise && _notes.text.trim().length < 3) {
      setState(() => _error = 'Write the reason of the revision.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{'accept_warnings': true, 'notes': _notes.text.trim(), if (acceptSources) 'accept_missing_sources': true};
    try {
      if (widget.revise) {
        await DprApi.revise(widget.contractId, widget.date, body);
      } else {
        await DprApi.issue(widget.contractId, widget.date, body);
      }
      if (mounted) Navigator.pop(context, true);
    } on DprException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'SOURCES_MISSING') {
        final ok = await dprConfirm(context, 'Equipment system not answering',
            '${e.message}\n\nIssue anyway with the plant figures missing?', ok: 'Issue anyway', danger: true);
        if (ok) await _go(acceptSources: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = asList(widget.model['missing']).map((x) => str(x['label'])).toList();
    final warnings = (widget.model['warnings'] as List? ?? const []).map((e) => e.toString()).toList();
    final h = asJson(widget.model['header']);
    final side = Container(
      width: 360,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Text(widget.revise ? 'Issue a new revision' : 'Issue the report',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
        const SizedBox(height: 4),
        Text('${str(h['report_no'])} · ${fmtDay(h['report_date'])}', style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        const Text('After issuing, this report is frozen: its PDF and Excel never change. A later correction is issued as a new revision.',
            style: TextStyle(fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 14),
        if (missing.isNotEmpty) DprBanner(lines: ['Not filled in: ${missing.join(', ')}.'], color: AppColors.textSecondary, icon: Icons.rule_rounded),
        DprBanner(lines: warnings),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          decoration: dprInput(widget.revise ? 'Reason of the revision (required)' : 'Notes (optional)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: dprAccentButton(),
          onPressed: _busy || _pdf == null ? null : () => _go(),
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : const Icon(Icons.send_rounded),
          label: Text(widget.revise ? 'Issue revision' : 'Issue report'),
        ),
      ]),
    );
    final pdf = _pdf;
    final preview = pdf == null
        ? (_error != null && _pdf == null
            ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
            : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
        : PdfPreview(
            build: (format) async => pdf,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            maxPageWidth: 820,
          );
    return Scaffold(
      backgroundColor: const Color(0xffe5e7eb),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.revise ? 'Full preview – revision' : 'Full preview before issuing'),
      ),
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? Row(children: [Expanded(child: preview), side])
            : Column(children: [Expanded(child: preview), SizedBox(height: 330, child: side)]),
      ),
    );
  }
}
