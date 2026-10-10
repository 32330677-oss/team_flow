// lib/screens/daily_site_report_screen.dart
//
// Daily Site Manpower Report (Admin): the PDF sent to the sub-contractor.
// Choose the date, the sites (all / some / one), the shift, who it is for and
// who it is issued by; the live preview shows the counts before generating.
// Every generated report gets a number (DSR-YYYYMMDD-####) and can be
// re-printed later exactly as it was issued.
//
// Backend: /api/reports/daily-site/* (Admin only).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import 'payroll_export_service.dart';

// ASIK logo palette (same as the PDF).
const Color _kCharcoal = Color(0xff4b4a4d);
const Color _kGold = Color(0xffcbab5a);
const Color _kGoldDark = Color(0xff8a6a1f);
const Color _kGoldPale = Color(0xfffbf8ef);
const Color _kInk = Color(0xff2b2a2e);
const Color _kMuted = Color(0xff6e6d72);
const Color _kLine = Color(0xffe2e1e3);
const Color _kBg = Color(0xfff6f6f7);
const Color _kDanger = Color(0xffb3261e);

class DailySiteReportScreen extends StatefulWidget {
  const DailySiteReportScreen({super.key});

  @override
  State<DailySiteReportScreen> createState() => _DailySiteReportScreenState();
}

class _DailySiteReportScreenState extends State<DailySiteReportScreen> {
  final _apiFmt = DateFormat('yyyy-MM-dd');
  final _longFmt = DateFormat('EEEE, d MMMM yyyy');

  bool _loading = true;
  String? _loadError;

  DateTime _today = DateTime.now();
  DateTime _date = DateTime.now();
  String _shift = 'All';
  List<Map<String, dynamic>> _sites = [];
  final Set<int> _selected = {};
  List<Map<String, dynamic>> _signatories = [];
  int? _signatoryId;
  final _recipientCtrl = TextEditingController();
  bool _recipientTouched = false;
  bool _includeStaff = true;
  bool _showAbsentNames = true;

  Map<String, dynamic>? _preview;
  bool _previewLoading = false;
  String? _previewError;
  Timer? _debounce;
  int _previewSeq = 0;

  bool _generating = false;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recipientCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ data
  String _err(Object e, String fallback) {
    if (e is DioException) {
      final raw = e.response?.data;
      if (raw is Map && raw['message'] != null) return raw['message'].toString();
      if (raw is List<int>) {
        try {
          final d = jsonDecode(utf8.decode(raw));
          if (d is Map && d['message'] != null) return d['message'].toString();
        } catch (_) {}
      }
    }
    return fallback;
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kDanger : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await ApiConfig.dio.get('/reports/daily-site/options');
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      _sites = (d['sites'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _signatories = (d['signatories'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final t = DateTime.tryParse(d['business_today']?.toString() ?? '');
      if (t != null) {
        _today = t;
        _date = t;
      }
      _selected
        ..clear()
        ..addAll(_sites.map((s) => s['site_id'] as int));
      if (_signatoryId == null && _signatories.length == 1) _signatoryId = _signatories.first['signatory_id'] as int;
      _applyDefaultRecipient();
      _loading = false;
      if (mounted) setState(() {});
      _schedulePreview(immediate: true);
      _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _err(e, 'Failed to load the report options.');
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiConfig.dio.get('/reports/daily-site/history', queryParameters: {'limit': 20});
      _history = (res.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() {});
    } catch (_) {/* history is optional on this page */}
  }

  /// Fills "Prepared for" with the client of the chosen sites when they all
  /// share one, until the user types something himself.
  void _applyDefaultRecipient() {
    if (_recipientTouched) return;
    final clients = _sites
        .where((s) => _selected.contains(s['site_id']))
        .map((s) => (s['client_name'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    _recipientCtrl.text = clients.length == 1 ? clients.first : '';
  }

  Map<String, dynamic> _body() => {
        'date': _apiFmt.format(_date),
        'shift': _shift,
        'site_ids': _selected.length == _sites.length ? 'all' : _selected.toList(),
        'recipient_name': _recipientCtrl.text.trim(),
        if (_signatoryId != null) 'signatory_id': _signatoryId,
        'include_staff': _includeStaff,
        'show_absent_names': _showAbsentNames,
      };

  void _changed({bool recipient = true}) {
    if (recipient) _applyDefaultRecipient();
    setState(() {});
    _schedulePreview();
  }

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    if (_selected.isEmpty) {
      setState(() {
        _preview = null;
        _previewError = null;
      });
      return;
    }
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 450), _runPreview);
  }

  Future<void> _runPreview() async {
    final seq = ++_previewSeq;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final res = await ApiConfig.dio.post('/reports/daily-site/preview', data: _body());
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = Map<String, dynamic>.from(res.data['data'] as Map);
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _previewLoading = false;
        _previewError = _err(e, 'Could not load the preview.');
      });
    }
  }

  Future<void> _download(Future<Response<List<int>>> Function() call, String fallbackName) async {
    final res = await call();
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty report');
    final no = res.headers.value('x-report-no');
    await PayrollExportService.exportBytes(bytes, '${no ?? fallbackName}.pdf');
    if (mounted) _snack('Report ${no ?? ''} is ready.');
  }

  Future<void> _generate() async {
    if (_selected.isEmpty) {
      _snack('Choose at least one site.', error: true);
      return;
    }
    if (_signatoryId == null) {
      _snack('Choose who the report is issued by.', error: true);
      return;
    }
    setState(() => _generating = true);
    try {
      await _download(
        () => ApiConfig.dio.post<List<int>>(
          '/reports/daily-site/generate',
          data: _body(),
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)),
        ),
        'Daily_Site_Report_${_apiFmt.format(_date)}',
      );
      _loadHistory();
    } catch (e) {
      if (mounted) _snack(_err(e, 'Failed to generate the report.'), error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _reprint(Map<String, dynamic> h) async {
    try {
      await _download(
        () => ApiConfig.dio.get<List<int>>(
          '/reports/daily-site/${h['report_id']}/pdf',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)),
        ),
        h['report_no']?.toString() ?? 'Daily_Site_Report',
      );
    } catch (e) {
      if (mounted) _snack(_err(e, 'Failed to re-print the report.'), error: true);
    }
  }

  // --------------------------------------------------------- signatories
  Future<void> _addSignatory() async {
    final nameCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    String? error;
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add "Issued by" person'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name', hintText: 'e.g. Eng. Hamza Al-Ali', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Job title', hintText: 'e.g. Operations Manager', border: OutlineInputBorder()),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: _kDanger)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kCharcoal),
              onPressed: () async {
                try {
                  final res = await ApiConfig.dio.post('/reports/daily-site/signatories',
                      data: {'full_name': nameCtrl.text.trim(), 'title': titleCtrl.text.trim()});
                  if (ctx.mounted) Navigator.pop(ctx, Map<String, dynamic>.from(res.data['data'] as Map));
                } catch (e) {
                  setD(() => error = _err(e, 'Could not save.'));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    titleCtrl.dispose();
    if (created == null) return;
    setState(() {
      _signatories = [..._signatories, created]
        ..sort((a, b) => a['full_name'].toString().compareTo(b['full_name'].toString()));
      _signatoryId = created['signatory_id'] as int;
    });
  }

  Future<void> _removeSignatory(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from the list?'),
        content: Text('${s['full_name']} will no longer be offered as "Issued by". Reports already issued keep the name.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiConfig.dio.put('/reports/daily-site/signatories/${s['signatory_id']}', data: {'is_active': false});
      setState(() {
        _signatories.removeWhere((x) => x['signatory_id'] == s['signatory_id']);
        if (_signatoryId == s['signatory_id']) _signatoryId = null;
      });
    } catch (e) {
      _snack(_err(e, 'Could not remove.'), error: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: _today,
      helpText: 'Report date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _kCharcoal, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _date = picked;
    _changed(recipient: false);
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: CustomAppBar(
        title: 'Daily Site Report',
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _loadOptions),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _errorState()
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 1050;
                  final form = _formColumn();
                  final side = _sideColumn();
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 24 : 14),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: wide
                            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(flex: 6, child: form),
                                const SizedBox(width: 20),
                                Expanded(flex: 5, child: side),
                              ])
                            : Column(children: [form, const SizedBox(height: 14), side]),
                      ),
                    ),
                  );
                }),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: _kDanger),
            const SizedBox(height: 10),
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: _loadOptions, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _card({required String step, required String title, String? hint, Widget? trailing, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _kGoldPale, shape: BoxShape.circle),
            child: Text(step, style: const TextStyle(color: _kGoldDark, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _kInk)),
              if (hint != null) Text(hint, style: const TextStyle(fontSize: 12, color: _kMuted)),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _formColumn() {
    final allSelected = _selected.length == _sites.length && _sites.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 1. Date & shift
      _card(
        step: '1',
        title: 'Date & shift',
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kInk,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              side: const BorderSide(color: _kLine),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18, color: _kGoldDark),
            label: Text(
              '${_longFmt.format(_date)}${DateUtils.isSameDay(_date, _today) ? '  (today)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: _kCharcoal,
              selectedForegroundColor: Colors.white,
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'All', label: Text('Day & Night')),
              ButtonSegment(value: 'Day', label: Text('Day')),
              ButtonSegment(value: 'Night', label: Text('Night')),
            ],
            selected: {_shift},
            onSelectionChanged: (v) {
              _shift = v.first;
              _changed(recipient: false);
            },
          ),
        ]),
      ),

      // 2. Sites
      _card(
        step: '2',
        title: 'Sites in the report',
        hint: '${_selected.length} of ${_sites.length} selected',
        trailing: TextButton(
          onPressed: () {
            if (allSelected) {
              _selected.clear();
            } else {
              _selected
                ..clear()
                ..addAll(_sites.map((s) => s['site_id'] as int));
            }
            _changed();
          },
          child: Text(allSelected ? 'Clear' : 'Select all'),
        ),
        child: _sites.isEmpty
            ? const Text('There is no Active site.', style: TextStyle(color: _kMuted))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sites.map((s) {
                  final id = s['site_id'] as int;
                  final on = _selected.contains(id);
                  final shifts = (s['shifts'] as List? ?? []).join(' & ');
                  return FilterChip(
                    selected: on,
                    showCheckmark: true,
                    checkmarkColor: Colors.white,
                    selectedColor: _kCharcoal,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: on ? _kCharcoal : _kLine),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    label: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(s['site_name']?.toString() ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : _kInk)),
                      Text(
                        [s['project_name'], shifts].where((x) => x != null && x.toString().isNotEmpty).join(' · '),
                        style: TextStyle(fontSize: 11, color: on ? Colors.white70 : _kMuted),
                      ),
                    ]),
                    onSelected: (v) {
                      v ? _selected.add(id) : _selected.remove(id);
                      _changed();
                    },
                  );
                }).toList(),
              ),
      ),

      // 3. From / to
      _card(
        step: '3',
        title: 'Prepared for & issued by',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _recipientCtrl,
            onChanged: (_) {
              _recipientTouched = true;
            },
            decoration: const InputDecoration(
              labelText: 'Prepared for (sub-contractor / client)',
              helperText: 'Filled from the project client when all chosen sites share one.',
              prefixIcon: Icon(Icons.apartment_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                // Rebuilt when the selection changes from code (e.g. a person was just added).
                key: ValueKey('sig-$_signatoryId-${_signatories.length}'),
                initialValue: _signatoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Issued by (printed and signed on the report)',
                  prefixIcon: Icon(Icons.draw_rounded),
                  border: OutlineInputBorder(),
                ),
                hint: Text(_signatories.isEmpty ? 'Add a person first' : 'Choose a person'),
                items: _signatories
                    .map((s) => DropdownMenuItem<int>(
                          value: s['signatory_id'] as int,
                          child: Text('${s['full_name']}  —  ${s['title']}', overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _signatoryId = v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Add person', onPressed: _addSignatory, icon: const Icon(Icons.person_add_alt_1_rounded)),
            if (_signatoryId != null)
              IconButton(
                tooltip: 'Remove this person from the list',
                onPressed: () => _removeSignatory(_signatories.firstWhere((s) => s['signatory_id'] == _signatoryId)),
                icon: const Icon(Icons.delete_outline_rounded, color: _kMuted),
              ),
          ]),
        ]),
      ),

      // 4. Content options
      _card(
        step: '4',
        title: 'Content',
        child: Column(children: [
          _switch('Include site staff', 'Engineers, foremen and other staff assigned to the site.', _includeStaff, (v) {
            _includeStaff = v;
            _changed(recipient: false);
          }),
          const Divider(height: 1, color: _kLine),
          _switch('Show names of people not on site', 'Absent, sick, on leave or not recorded yet. Off = counts only.', _showAbsentNames,
              (v) {
            _showAbsentNames = v;
            _changed(recipient: false);
          }),
        ]),
      ),
    ]);
  }

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: _kGold,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12, color: _kMuted)),
        value: value,
        onChanged: onChanged,
      );

  Widget _sideColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _previewCard(),
      const SizedBox(height: 14),
      _historyCard(),
    ]);
  }

  Widget _previewCard() {
    final t = _preview?['totals'] as Map?;
    final sites = (_preview?['sites'] as List? ?? []).cast<Map>();
    final onSite = (t?['on_site_total'] ?? 0) as num;
    final assigned = (t?['assigned_total'] ?? 0) as num;
    final workers = t?['workers'] as Map?;
    final staff = t?['staff'] as Map?;
    final rate = assigned > 0 ? '${(onSite * 100 / assigned).round()}%' : '-';
    final canGenerate = !_generating && _selected.isNotEmpty && _signatoryId != null;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kLine)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: _kCharcoal,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ON SITE', style: TextStyle(color: _kGold, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_selected.isEmpty ? '—' : '$onSite / $assigned',
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                Text('${_longFmt.format(_date)} · ${_shift == 'All' ? 'Day & Night' : _shift}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            if (_previewLoading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
            else
              Text(rate, style: const TextStyle(color: _kGold, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        Container(height: 3, color: _kGold),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: _previewError != null
              ? Text(_previewError!, style: const TextStyle(color: _kDanger))
              : _selected.isEmpty
                  ? const Text('Choose at least one site.', style: TextStyle(color: _kMuted))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        _stat('Workers', workers),
                        if (_includeStaff) _stat('Staff', staff),
                        _statNotOnSite(workers, _includeStaff ? staff : null),
                      ]),
                      const SizedBox(height: 12),
                      for (final s in sites) _sitePreviewRow(s),
                    ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_signatoryId == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Choose who the report is issued by (step 3).', style: TextStyle(color: _kGoldDark, fontSize: 12)),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kGold,
                foregroundColor: _kInk,
                disabledBackgroundColor: _kLine,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: canGenerate ? _generate : null,
              icon: _generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kInk))
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_generating ? 'Generating…' : 'Generate PDF report',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Counts use check-ins recorded so far today. Hours, rates and personal details are never included.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: _kMuted),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String label, Map? c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: 1, color: _kMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${c?['on_site'] ?? 0} / ${c?['assigned'] ?? 0}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kInk)),
        ]),
      );

  Widget _statNotOnSite(Map? w, Map? s) {
    int v(Map? m, String k) => ((m?[k] ?? 0) as num).toInt();
    final total = v(w, 'assigned') - v(w, 'on_site') + v(s, 'assigned') - v(s, 'on_site');
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NOT ON SITE', style: TextStyle(fontSize: 10.5, letterSpacing: 1, color: _kMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('$total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kInk)),
      ]),
    );
  }

  Widget _sitePreviewRow(Map s) {
    final shifts = (s['shifts'] as List? ?? []).cast<Map>();
    final staff = s['staff'] as Map?;
    final parts = <String>[
      for (final sh in shifts) '${sh['shift_type']} ${sh['counts']['on_site']}/${sh['counts']['assigned']}',
      if (_includeStaff && staff != null && (staff['assigned'] ?? 0) > 0) 'Staff ${staff['on_site']}/${staff['assigned']}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _kLine))),
      child: Row(children: [
        Expanded(
          child: Text(s['site_name']?.toString() ?? '',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: _kInk)),
        ),
        Text(parts.join('   ·   '), style: const TextStyle(fontSize: 12.5, color: _kMuted)),
      ]),
    );
  }

  Widget _historyCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kLine)),
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Issued reports', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _kInk)),
        const Text('Re-print gives the exact report that was issued.', style: TextStyle(fontSize: 12, color: _kMuted)),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No report issued yet.', style: TextStyle(color: _kMuted)),
          )
        else
          for (final h in _history)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(right: 4),
              title: Text(h['report_no']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: Text(
                [
                  h['report_date'],
                  h['shift_filter'] == 'All' ? 'Day & Night' : h['shift_filter'],
                  '${(h['site_ids'] as List?)?.length ?? 0} site(s)',
                  'on site ${(h['totals'] as Map?)?['on_site_total'] ?? '-'}',
                  if ((h['recipient_name'] ?? '').toString().isNotEmpty) 'for ${h['recipient_name']}',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: IconButton(
                tooltip: 'Re-print',
                icon: const Icon(Icons.print_rounded, color: _kCharcoal),
                onPressed: () => _reprint(h),
              ),
            ),
      ]),
    );
  }
}
