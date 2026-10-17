// lib/screens/dpr/dpr_pages.dart
//
// Daily Progress Report pages that only READ: Dashboard, Allocation matrix
// (the workbook's Alloc sheet), Archive of issued reports, and the
// Differences page (manual values vs system values, for the Admin).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import '../payroll_export_service.dart';
import 'dpr_widgets.dart';

// ======================================================================
// Dashboard
// ======================================================================
class DprDashboardPage extends StatelessWidget {
  /// Called with a date when a day of the last 30 days is tapped (opens the daily report).
  final ValueChanged<String>? onOpenDay;
  const DprDashboardPage({super.key, this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const DprContractBar(),
      Expanded(
        child: DprSelection(
          builder: (ctx, cid, date) => _Dashboard(key: ValueKey('$cid|$date'), contractId: cid, date: date, onOpenDay: onOpenDay),
        ),
      ),
    ]);
  }
}

class _Dashboard extends StatefulWidget {
  final int contractId;
  final String date;
  final ValueChanged<String>? onOpenDay;
  const _Dashboard({super.key, required this.contractId, required this.date, this.onOpenDay});

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  Json? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DprApi.dashboard(widget.contractId, widget.date);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return _error != null
          ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
          : const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final k = asJson(d['kpis']);
    final h = asJson(d['header']);
    final days = asList(d['days']);
    final variance = asNum(k['schedule_variance']) ?? 0;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        DprBanner(lines: (d['warnings'] as List? ?? const []).map((e) => e.toString()).toList()),
        Wrap(spacing: 10, runSpacing: 10, children: [
          DprKpi(label: 'Time elapsed', value: fmtPct(k['time_elapsed']), icon: Icons.hourglass_bottom_rounded,
              note: 'day ${str(h['days_elapsed'])} of ${str(h['revised_duration'])}'),
          DprKpi(label: 'Physical progress (BOQ)', value: fmtPct(k['physical_progress']), icon: Icons.trending_up_rounded, color: const Color(0xff047857)),
          DprKpi(label: 'Schedule variance', value: '${variance >= 0 ? '+' : ''}${(variance * 100).toStringAsFixed(1)}%',
              icon: variance >= 0 ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
              color: variance >= 0 ? const Color(0xff047857) : AppColors.danger, note: 'progress − time'),
          DprKpi(label: 'Manpower today', value: str(k['manpower_today']), icon: Icons.groups_rounded),
          DprKpi(label: 'Cum. man-days', value: fmtQty(k['cum_man_days']), icon: Icons.stacked_bar_chart_rounded),
          DprKpi(label: 'Open NCRs', value: str(k['open_ncrs']), icon: Icons.report_gmailerrorred_rounded, color: AppColors.danger),
          DprKpi(label: 'Open concerns', value: str(k['open_concerns']), icon: Icons.warning_amber_rounded, color: const Color(0xffb45309)),
          DprKpi(label: 'LTI-free days', value: str(k['lti_free_days']), icon: Icons.health_and_safety_rounded, color: const Color(0xff047857)),
          DprKpi(label: 'Safe man-hours', value: fmtQty(k['safe_man_hours']), icon: Icons.shield_rounded, color: const Color(0xff047857)),
          DprKpi(label: 'Near misses to date', value: str(k['near_misses_to_date']), icon: Icons.report_problem_rounded, color: const Color(0xffb45309)),
        ]),
        const SizedBox(height: 14),
        DprCard(
          title: 'Time vs physical progress',
          icon: Icons.timeline_rounded,
          child: Column(children: [
            _progressLine('Time elapsed', asNum(k['time_elapsed']) ?? 0, AppColors.primary),
            const SizedBox(height: 10),
            _progressLine('Physical progress', asNum(k['physical_progress']) ?? 0, const Color(0xff047857)),
          ]),
        ),
        DprCard(
          title: 'Daily manpower & plant – last 30 days',
          subtitle: 'Tap a day to open its report. Dot: green = issued, amber = draft, grey = nothing yet',
          icon: Icons.bar_chart_rounded,
          child: _DaysChart(days: days, onTap: widget.onOpenDay),
        ),
        DprCard(
          title: 'Cumulative man-days by trade (own forces)',
          icon: Icons.groups_2_rounded,
          child: _HBars(items: asList(k['cum_by_trade']).map((t) => MapEntry(str(t['name']), asNum(t['cum']) ?? 0)).toList()),
        ),
        AppDataTableCard(
          title: 'BOQ progress – cumulative to ${fmtDay(widget.date)}',
          subtitle: 'Earned value = cum. qty (max contract qty) × rate',
          icon: Icons.list_alt_rounded,
          emptyMessage: 'No BOQ yet.',
          columns: [dprCol('Item'), dprCol('Description'), dprCol('Unit'), dprCol('Contract'), dprCol('Cum.'), dprCol('%'), dprCol('Rate'),
            dprCol('Amount'), dprCol('Earned'), dprCol('Balance')],
          rows: [
            ...asList(k['boq']).map((b) => DataRow(cells: [
                  DataCell(dprCell(str(b['item_no']), bold: true)),
                  DataCell(dprCell(str(b['description']), width: 220)),
                  DataCell(dprCell(str(b['unit']))),
                  DataCell(dprCell(fmtQty(b['contract_qty'], minDecimals: 1))),
                  DataCell(dprCell(fmtQty(b['cum'], minDecimals: 1), bold: true)),
                  DataCell(_pctBar(asNum(b['pct']))),
                  DataCell(dprCell(fmtQty(b['rate']))),
                  DataCell(dprCell(fmtQty(b['amount']))),
                  DataCell(dprCell(fmtQty(b['earned']), bold: true)),
                  DataCell(dprCell(fmtQty(b['balance'], minDecimals: 1))),
                ])),
            if (asList(k['boq']).isNotEmpty)
              DataRow(cells: [
                DataCell(dprCell('TOTAL', bold: true)),
                DataCell(dprCell('Overall weighted progress', bold: true)),
                DataCell(dprCell('')),
                DataCell(dprCell('')),
                DataCell(dprCell('')),
                DataCell(dprCell(fmtPct(k['physical_progress']), bold: true)),
                DataCell(dprCell('')),
                DataCell(dprCell(fmtQty(k['boq_total_amount']), bold: true)),
                DataCell(dprCell(fmtQty(k['boq_total_earned']), bold: true)),
                DataCell(dprCell('')),
              ]),
          ],
        ),
      ]),
    );
  }

  Widget _progressLine(String label, double v, Color c) => Row(children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 14, color: c, backgroundColor: AppColors.border),
          ),
        ),
        SizedBox(width: 70, child: Text(fmtPct(v), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: c))),
      ]);

  Widget _pctBar(double? v) {
    if (v == null) return dprCell('');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: 90,
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: v.clamp(0, 1).toDouble(), minHeight: 6, color: const Color(0xff047857), backgroundColor: AppColors.border),
            ),
          ),
          const SizedBox(width: 6),
          Text(fmtPct(v), style: const TextStyle(fontSize: 11.5)),
        ]),
      ),
    );
  }
}

/// Stacked bars: own manpower + subcontractor manpower, with total plant as a dot line.
class _DaysChart extends StatelessWidget {
  final List<Json> days;
  final ValueChanged<String>? onTap;
  const _DaysChart({required this.days, this.onTap});

  @override
  Widget build(BuildContext context) {
    final maxV = days.fold<int>(1, (m, d) => math.max(m, math.max(asInt(d['total_manpower']), asInt(d['total_plant']))));
    const h = 170.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: h + 46,
        child: LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth / math.max(days.length, 1)).clamp(8, 40).toDouble();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: days.map((d) {
              final own = asInt(d['own_manpower']);
              final sub = asInt(d['subcon_manpower']);
              final pl = asInt(d['total_plant']);
              final st = str(d['status']);
              final dot = st == 'Issued' ? const Color(0xff047857) : (st == 'Draft' ? const Color(0xffb45309) : AppColors.border);
              return Tooltip(
                message: '${fmtDay(d['date'])} (${str(d['day'])})\nOwn manpower $own · Subcon $sub · Plant $pl\nReport: $st',
                child: InkWell(
                  onTap: onTap == null ? null : () => onTap!(str(d['date'])),
                  child: SizedBox(
                    width: w,
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${own + sub}', style: const TextStyle(fontSize: 8.5, color: AppColors.textSecondary)),
                      Container(height: h * sub / maxV, width: w * 0.6, color: AppColors.accent),
                      Container(height: h * own / maxV, width: w * 0.6, color: AppColors.primary),
                      const SizedBox(height: 3),
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                      const SizedBox(height: 2),
                      Text(str(d['date']).length >= 10 ? str(d['date']).substring(8, 10) : '', style: const TextStyle(fontSize: 9.5)),
                    ]),
                  ),
                ),
              );
            }).toList()),
          );
        }),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, children: [
        _legend(AppColors.primary, 'Own manpower'),
        _legend(AppColors.accent, 'Subcontractor manpower'),
      ]),
    ]);
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, color: c),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

class _HBars extends StatelessWidget {
  final List<MapEntry<String, double>> items;
  const _HBars({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No trade line.', style: TextStyle(color: AppColors.textSecondary));
    final maxV = items.fold<double>(1, (m, e) => math.max(m, e.value));
    return Column(
      children: items
          .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 160, child: Text(e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 14,
                          width: math.max(2, c.maxWidth * e.value / maxV),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 70, child: Text(fmtQty(e.value == e.value.roundToDouble() ? e.value.toInt() : e.value), textAlign: TextAlign.right)),
                ]),
              ))
          .toList(),
    );
  }
}

// ======================================================================
// Allocation matrix (Alloc)
// ======================================================================
class DprAllocPage extends StatelessWidget {
  const DprAllocPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const DprContractBar(),
      Expanded(child: DprSelection(builder: (ctx, cid, date) => _Alloc(key: ValueKey('$cid|$date'), contractId: cid, date: date))),
    ]);
  }
}

class _Alloc extends StatefulWidget {
  final int contractId;
  final String date;
  const _Alloc({super.key, required this.contractId, required this.date});

  @override
  State<_Alloc> createState() => _AllocState();
}

class _AllocState extends State<_Alloc> {
  Json? _m;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await DprApi.day(widget.contractId, widget.date);
      if (mounted) setState(() => _m = asJson(b['model']));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) {
      return _error != null
          ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
          : const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final a = asJson(m['allocation']);
    final acts = asList(a['activities']);
    final rows = asList(a['rows']);
    final mp = asJson(a['manpower']);
    final pl = asJson(a['plant']);
    final mh = asJson(a['man_hours']);
    final eh = asJson(a['equip_hours']);
    final perMp = (mp['per_activity'] as List? ?? const []);
    final perPl = (pl['per_activity'] as List? ?? const []);
    final perMh = (mh['per_activity'] as List? ?? const []);
    final perEh = (eh['per_activity'] as List? ?? const []);
    final outMh = (a['output_per_mh'] as List? ?? const []);
    Color? statusColor(String s) => s == 'Over-allocated' ? AppColors.danger : (s == 'Balanced' ? const Color(0xff047857) : null);
    DataRow total(String label, Json t, List per, {bool hours = false}) => DataRow(cells: [
          DataCell(dprCell(label, bold: true)),
          DataCell(dprCell('')),
          DataCell(dprCell(hours ? fmtQty(t['deployed']) : str(t['deployed']), bold: true)),
          ...List.generate(acts.length, (i) => DataCell(dprCell(i < per.length ? (hours ? fmtQty(per[i]) : str(per[i])) : '', bold: true))),
          DataCell(dprCell(hours ? fmtQty(t['allocated']) : str(t['allocated']), bold: true)),
          DataCell(dprCell(hours ? fmtQty(t['idle']) : str(t['idle']), bold: true)),
          DataCell(dprCell(hours ? '' : fmtPct(t['utilisation'], decimals: 0), bold: true)),
          DataCell(dprCell('')),
        ]);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const DprBanner(
          lines: ['Deployed = on site today. Allocated = crew / plant entered on the activities. '
              'Unallocated = idle or indirect (staff, drivers). Red = more allocated than on site: correct the activities.'],
          color: AppColors.primary,
          icon: Icons.info_outline_rounded,
        ),
        AppDataTableCard(
          title: 'Resource allocation matrix',
          subtitle: '${str(asJson(m['header'])['report_no'])} · ${fmtDay(widget.date)} · ${acts.length} activities',
          icon: Icons.grid_view_rounded,
          emptyMessage: 'No resource line.',
          columns: [
            dprCol('Resource'),
            dprCol('Group'),
            dprCol('Deployed'),
            ...acts.asMap().entries.map((e) => DataColumn(
                label: Tooltip(
                    message: '${str(e.value['item_no'])} – ${str(e.value['location'])}\n${fmtQty(e.value['qty'])} ${str(e.value['unit'])}',
                    child: Text('  ${str(e.value['item_no'])}')))),
            dprCol('Total'),
            dprCol('Idle'),
            dprCol('Util.'),
            dprCol('Status'),
          ],
          rows: [
            ...rows.map((r) {
              final per = (r['per_activity'] as List? ?? const []);
              final st = str(r['status']);
              return DataRow(cells: [
                DataCell(dprCell(str(r['resource']), bold: true, width: 200)),
                DataCell(dprCell(str(r['group']), color: AppColors.textSecondary)),
                DataCell(dprCell(fmtQty(r['deployed'], dash: true), bold: true)),
                ...List.generate(acts.length, (i) => DataCell(dprCell(i < per.length ? fmtQty(per[i], dash: true) : ''))),
                DataCell(dprCell(fmtQty(r['allocated'], dash: true))),
                DataCell(dprCell(fmtQty(r['idle'], dash: true), color: asInt(r['idle']) < 0 ? AppColors.danger : null)),
                DataCell(dprCell(fmtPct(r['utilisation'], decimals: 0))),
                DataCell(dprCell(st, bold: st == 'Over-allocated', color: statusColor(st))),
              ]);
            }),
            total('TOTAL MANPOWER (nos)', mp, perMp),
            total('TOTAL PLANT (nos)', pl, perPl),
            total('MAN-HOURS', mh, perMh, hours: true),
            total('EQUIPMENT-HOURS', eh, perEh, hours: true),
            DataRow(cells: [
              DataCell(dprCell('OUTPUT PER MAN-HOUR', bold: true)),
              DataCell(dprCell('')),
              DataCell(dprCell('')),
              ...List.generate(acts.length, (i) => DataCell(dprCell(i < outMh.length ? fmtRatio(outMh[i], decimals: 3) : ''))),
              DataCell(dprCell('')),
              DataCell(dprCell('')),
              DataCell(dprCell('')),
              DataCell(dprCell('')),
            ]),
          ],
        ),
      ]),
    );
  }
}

// ======================================================================
// Archive
// ======================================================================
class DprArchivePage extends StatelessWidget {
  const DprArchivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const DprContractBar(showDate: false),
      Expanded(child: DprSelection(withDate: false, builder: (ctx, cid, _) => _Archive(key: ValueKey(cid), contractId: cid))),
    ]);
  }
}

class _Archive extends StatefulWidget {
  final int contractId;
  const _Archive({super.key, required this.contractId});

  @override
  State<_Archive> createState() => _ArchiveState();
}

class _ArchiveState extends State<_Archive> {
  List<Json>? _list;
  String? _error;
  bool _showSuperseded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await DprApi.reports(widget.contractId);
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _download(Json r, String format) async {
    try {
      final id = asInt(r['report_id']);
      final bytes = format == 'pdf' ? await DprApi.reportPdf(widget.contractId, id) : await DprApi.reportXlsx(widget.contractId, id);
      final rev = asInt(r['revision']);
      await PayrollExportService.exportBytes(bytes, '${str(r['report_no'])}_${str(r['report_date'])}${rev > 0 ? '_Rev$rev' : ''}.$format');
    } catch (e) {
      if (mounted) dprSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return _error != null
          ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
          : const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final shown = list.where((r) => _showSuperseded || r['status'] == 'Issued').toList();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        AppDataTableCard(
          title: 'Issued reports',
          subtitle: '${list.where((r) => r['status'] == 'Issued').length} issued · frozen: their PDF / Excel never change',
          icon: Icons.inventory_2_rounded,
          emptyMessage: 'No issued report yet.',
          trailing: FilterChip(
            label: const Text('Show superseded'),
            selected: _showSuperseded,
            onSelected: (v) => setState(() => _showSuperseded = v),
          ),
          columns: [dprCol('Date'), dprCol('Report No.'), dprCol('Rev.'), dprCol('Status'), dprCol('Issued'), dprCol('By'), dprCol('Notes'), dprCol('Files')],
          rows: shown
              .map((r) => DataRow(cells: [
                    DataCell(dprCell(fmtDay(r['report_date']), bold: true)),
                    DataCell(dprCell(str(r['report_no']), bold: true, color: AppColors.primary)),
                    DataCell(dprCell(str(r['revision']))),
                    DataCell(StatusBadge.fromStatus(r['status'] == 'Issued' ? 'Approved' : 'Completed')),
                    DataCell(dprCell(str(r['issued_at']))),
                    DataCell(dprCell(str(r['issued_by']))),
                    DataCell(dprCell(str(r['notes']), width: 200)),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger), onPressed: () => _download(r, 'pdf')),
                      IconButton(tooltip: 'Excel', icon: const Icon(Icons.grid_on_rounded, color: Color(0xff047857)), onPressed: () => _download(r, 'xlsx')),
                    ])),
                  ]))
              .toList(),
        ),
      ]),
    );
  }
}

// ======================================================================
// Differences: manual values vs system values
// ======================================================================
class DprDifferencesPage extends StatefulWidget {
  const DprDifferencesPage({super.key});

  @override
  State<DprDifferencesPage> createState() => _DprDifferencesPageState();
}

class _DprDifferencesPageState extends State<DprDifferencesPage> {
  List<Json>? _rows;
  List<Json> _contracts = [];
  int? _contract;
  bool _withRemoved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _contracts = await DprApi.contracts();
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    try {
      final r = await DprApi.differences(contractId: _contract, includeReverted: _withRemoved);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(padding: const EdgeInsets.all(14), children: [
      const DprBanner(
        lines: ['Figures typed over the values of Team Flow / the equipment system, with the reason, who and when. '
            'The system data itself is never changed.'],
        color: AppColors.primary,
        icon: Icons.compare_arrows_rounded,
      ),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<int?>(
            value: _contract,
            decoration: dprInput('Contract'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All contracts')),
              ..._contracts.map((c) => DropdownMenuItem<int?>(value: asInt(c['contract_id']), child: Text('${str(c['code'])} · ${str(c['title'])}'))),
            ],
            onChanged: (v) {
              _contract = v;
              _load();
            },
          ),
        ),
        FilterChip(
          label: const Text('Include removed manual values'),
          selected: _withRemoved,
          onSelected: (v) {
            _withRemoved = v;
            _load();
          },
        ),
        IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      const SizedBox(height: 12),
      if (rows == null)
        (_error != null
            ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
            : const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.primary))))
      else
        AppDataTableCard(
          title: 'Manual values vs system values',
          subtitle: '${rows.length} entries',
          icon: Icons.compare_arrows_rounded,
          emptyMessage: 'No manual value: every figure comes from the systems.',
          columns: [dprCol('Contract'), dprCol('Date'), dprCol('Figure'), dprCol('System'), dprCol('Manual'), dprCol('Difference'),
            dprCol('Reason'), dprCol('By'), dprCol('When'), dprCol('Status')],
          rows: rows.map((r) {
            final diff = r['difference'];
            final dn = diff == null ? null : asInt(diff);
            return DataRow(cells: [
              DataCell(dprCell(str(r['contract_code']), bold: true)),
              DataCell(dprCell(fmtDay(r['report_date']))),
              DataCell(dprCell(str(r['field']), width: 200)),
              DataCell(dprCell(r['system_value'] == null ? '—' : str(r['system_value']))),
              DataCell(dprCell(str(r['manual_value']), bold: true, color: const Color(0xffb45309))),
              DataCell(dprCell(dn == null ? '—' : '${dn > 0 ? '+' : ''}$dn', bold: true, color: dn == null || dn == 0 ? null : (dn > 0 ? const Color(0xff047857) : AppColors.danger))),
              DataCell(dprCell(str(r['reason']), width: 220)),
              DataCell(dprCell(str(r['created_by']))),
              DataCell(dprCell(str(r['created_at']))),
              DataCell(r['active'] == true
                  ? StatusBadge(label: r['issued'] == true ? 'In issued report' : 'In use', color: const Color(0xffb45309))
                  : StatusBadge(label: 'Removed ${str(r['reverted_at'])}', color: AppColors.textSecondary)),
            ]);
          }).toList(),
        ),
    ]);
  }
}
