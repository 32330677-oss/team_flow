// lib/screens/daily_site_report_screen.dart
//
// Daily Site Report (Admin): the PDF sent to the sub-contractor.
// Choose the date, the sites (all / some / one), the shift, who it is for and
// who it is issued by; the live preview shows the counts before generating.
// Step 5 holds the notes per site (weather, work done, plan for tomorrow,
// HSE, issues). They are optional, saved as a draft on this device per date,
// and printed only when filled. The PDF carries head counts only: no names,
// check-in times, hours or rates.
// Every generated report gets a number (DSR-YYYYMMDD-####) and can be
// re-printed later exactly as it was issued.
//
// Backend: /api/reports/daily-site/* (Admin only).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// Same keys as the backend (services/dailySiteReportPdfLayout.js).
const Map<String, String> _kWeather = {
  'sunny': 'Sunny',
  'cloudy': 'Cloudy',
  'rain': 'Rain',
  'wind': 'Strong wind',
  'dust': 'Dust',
  'hot': 'Extreme heat',
  'cold': 'Cold',
  'storm': 'Storm',
};
const Map<String, IconData> _kWeatherIcon = {
  'sunny': Icons.wb_sunny_rounded,
  'cloudy': Icons.cloud_rounded,
  'rain': Icons.water_drop_rounded,
  'wind': Icons.air_rounded,
  'dust': Icons.blur_on_rounded,
  'hot': Icons.thermostat_rounded,
  'cold': Icons.ac_unit_rounded,
  'storm': Icons.thunderstorm_rounded,
};
const Map<String, String> _kImpact = {'none': 'No impact', 'slowed': 'Work slowed', 'stopped': 'Work stopped'};
const Map<String, String> _kHse = {
  'no_incident': 'No incident',
  'near_miss': 'Near miss',
  'first_aid': 'First aid',
  'lost_time': 'Lost time',
};

/// Notes typed for one site. Empty fields are not sent and not printed.
class _SiteNotes {
  String weather = '';
  String impact = '';
  String hse = '';
  final workDone = TextEditingController();
  final workPlanned = TextEditingController();
  final toolbox = TextEditingController();
  final hseDetails = TextEditingController();
  final issues = TextEditingController();

  List<TextEditingController> get _texts => [workDone, workPlanned, toolbox, hseDetails, issues];

  bool get isEmpty => weather.isEmpty && impact.isEmpty && hse.isEmpty && _texts.every((c) => c.text.trim().isEmpty);

  bool get hasWork => workDone.text.trim().isNotEmpty || workPlanned.text.trim().isNotEmpty;
  bool get hasHse => hse.isNotEmpty || toolbox.text.trim().isNotEmpty || hseDetails.text.trim().isNotEmpty;

  Map<String, String> toJson() {
    final m = <String, String>{
      'weather': weather,
      'weather_impact': impact,
      'hse_status': hse,
      'work_done': workDone.text.trim(),
      'work_planned': workPlanned.text.trim(),
      'toolbox_talk': toolbox.text.trim(),
      'hse_details': hseDetails.text.trim(),
      'issues': issues.text.trim(),
    };
    m.removeWhere((_, v) => v.isEmpty);
    return m;
  }

  void fromJson(Map m, {bool textsOnly = false}) {
    String v(String k) => (m[k] ?? '').toString();
    if (!textsOnly) {
      weather = _kWeather.containsKey(v('weather')) ? v('weather') : '';
      impact = _kImpact.containsKey(v('weather_impact')) ? v('weather_impact') : '';
      hse = _kHse.containsKey(v('hse_status')) ? v('hse_status') : '';
      hseDetails.text = v('hse_details');
    }
    workDone.text = v('work_done');
    workPlanned.text = v('work_planned');
    toolbox.text = v('toolbox_talk');
    issues.text = v('issues');
  }

  void clear() {
    weather = '';
    impact = '';
    hse = '';
    for (final c in _texts) {
      c.clear();
    }
  }

  void dispose() {
    for (final c in _texts) {
      c.dispose();
    }
  }
}

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

  // Step 5: notes per site (draft kept on this device, per report date).
  final Map<int, _SiteNotes> _notes = {};
  Map<String, dynamic> _lastNotes = {};
  Timer? _draftTimer;
  static const _draftPrefix = 'dsr_notes_';

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
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraft();
    }
    _recipientCtrl.dispose();
    for (final n in _notes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ site notes
  _SiteNotes _notesFor(int siteId) => _notes.putIfAbsent(siteId, () => _SiteNotes());

  String get _draftKey => '$_draftPrefix${_apiFmt.format(_date)}';

  void _notesChanged() {
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        for (final e in _notes.entries)
          if (!e.value.isEmpty) e.key.toString(): e.value.toJson(),
      };
      if (data.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, jsonEncode(data));
      }
    } catch (_) {/* a draft is a convenience only */}
  }

  /// Loads the draft of the selected date (replaces what is on screen) and
  /// drops drafts older than two weeks.
  Future<void> _loadDraft() async {
    for (final n in _notes.values) {
      n.clear();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoff = _apiFmt.format(_today.subtract(const Duration(days: 14)));
      for (final k in prefs.getKeys().where((k) => k.startsWith(_draftPrefix)).toList()) {
        if (k.substring(_draftPrefix.length).compareTo(cutoff) < 0) await prefs.remove(k);
      }
      final raw = prefs.getString(_draftKey);
      if (raw != null) {
        final d = jsonDecode(raw);
        if (d is Map) {
          d.forEach((k, v) {
            final id = int.tryParse(k.toString());
            if (id != null && v is Map) _notesFor(id).fromJson(v);
          });
        }
      }
    } catch (_) {/* ignore a broken draft */}
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _notesBody() => {
        for (final id in _selected)
          if (_notes[id] != null && !_notes[id]!.isEmpty) id.toString(): _notes[id]!.toJson(),
      };

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
      _lastNotes = d['last_notes'] is Map ? Map<String, dynamic>.from(d['last_notes'] as Map) : {};
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
      _loadDraft();
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
        'site_notes': _notesBody(),
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
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      await _saveDraft(); // keep what was typed for the previous date
    }
    _date = picked;
    _changed(recipient: false);
    _loadDraft();
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
        ]),
      ),

      // 5. Site notes
      _notesCard(),
    ]);
  }

  Widget _notesCard() {
    final chosen = _sites.where((s) => _selected.contains(s['site_id'])).toList();
    final filled = chosen.where((s) => !(_notes[s['site_id']]?.isEmpty ?? true)).length;
    return _card(
      step: '5',
      title: 'Site notes',
      hint: chosen.isEmpty
          ? 'Optional. Choose sites first.'
          : 'Optional. $filled of ${chosen.length} site(s) filled. Empty notes are not printed.',
      child: chosen.isEmpty
          ? const Text('Choose at least one site in step 2.', style: TextStyle(color: _kMuted))
          : Container(
              decoration: BoxDecoration(border: Border.all(color: _kLine), borderRadius: BorderRadius.circular(10)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < chosen.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _kLine),
                  _siteNotesTile(chosen[i]),
                ],
              ]),
            ),
    );
  }

  Widget _siteNotesTile(Map<String, dynamic> site) {
    final id = site['site_id'] as int;
    final n = _notesFor(id);
    final last = _lastNotes[id.toString()] as Map?;
    final tags = <String>[
      if (n.weather.isNotEmpty) _kWeather[n.weather]!,
      if (n.hasWork) 'Work',
      if (n.hasHse) n.hse.isNotEmpty ? _kHse[n.hse]! : 'HSE',
      if (n.issues.text.trim().isNotEmpty) 'Issues',
    ];
    final incident = n.hse.isNotEmpty && n.hse != 'no_incident';

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('dsr-notes-$id'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        backgroundColor: _kGoldPale.withValues(alpha: 0.5),
        leading: Icon(
          n.isEmpty ? Icons.edit_note_rounded : Icons.check_circle_rounded,
          color: n.isEmpty ? _kMuted : (incident ? _kDanger : _kGold),
        ),
        title: Text(site['site_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: _kInk)),
        subtitle: Text(
          tags.isEmpty ? 'No notes' : tags.join(' · '),
          style: TextStyle(fontSize: 12, color: incident ? _kDanger : _kMuted),
        ),
        children: [
          if (last != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _kGoldDark, padding: EdgeInsets.zero),
                onPressed: () {
                  n.fromJson(Map<String, dynamic>.from(last['notes'] as Map? ?? {}), textsOnly: true);
                  _notesChanged();
                },
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                label: Text('Copy text from ${last['report_no']} (${last['report_date']})', style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          _notesLabel('Weather'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _kWeather.entries)
              ChoiceChip(
                avatar: Icon(_kWeatherIcon[e.key], size: 16, color: n.weather == e.key ? Colors.white : _kGoldDark),
                label: Text(e.value),
                selected: n.weather == e.key,
                showCheckmark: false,
                selectedColor: _kCharcoal,
                labelStyle: TextStyle(color: n.weather == e.key ? Colors.white : _kInk, fontSize: 12.5),
                side: BorderSide(color: n.weather == e.key ? _kCharcoal : _kLine),
                onSelected: (v) {
                  n.weather = v ? e.key : '';
                  if (!v) n.impact = '';
                  _notesChanged();
                },
              ),
          ]),
          if (n.weather.isNotEmpty) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(selectedBackgroundColor: _kCharcoal, selectedForegroundColor: Colors.white),
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [for (final e in _kImpact.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: n.impact.isEmpty ? <String>{} : {n.impact},
              onSelectionChanged: (v) {
                n.impact = v.isEmpty ? '' : v.first;
                _notesChanged();
              },
            ),
          ],
          _notesLabel('Work'),
          _notesField(n.workDone, 'Work carried out today', 'e.g. Level 7 slab rebar completed for zones A and B.', lines: 3, max: 1500),
          const SizedBox(height: 10),
          _notesField(n.workPlanned, 'Planned for tomorrow', 'e.g. Pour level 7 slab zone A (night shift).', lines: 2, max: 1000),
          _notesLabel('Health & safety'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _kHse.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: n.hse == e.key,
                showCheckmark: false,
                selectedColor: e.key == 'no_incident' ? _kCharcoal : _kDanger,
                labelStyle: TextStyle(color: n.hse == e.key ? Colors.white : _kInk, fontSize: 12.5),
                side: BorderSide(color: n.hse == e.key ? Colors.transparent : _kLine),
                onSelected: (v) {
                  n.hse = v ? e.key : '';
                  _notesChanged();
                },
              ),
          ]),
          const SizedBox(height: 10),
          _notesField(n.toolbox, 'Toolbox talk topic', 'e.g. Working at height', max: 160),
          if (incident || n.hseDetails.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _notesField(n.hseDetails, 'What happened and what was done', 'Short description, no personal details.', lines: 2, max: 800),
          ],
          _notesLabel('Issues, delays & instructions required'),
          _notesField(n.issues, 'Issues / delays / what you need from the client', 'e.g. Waiting for approval of the MEP sleeves.',
              lines: 2, max: 1200),
          if (!n.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () {
                  n.clear();
                  _notesChanged();
                },
                child: const Text('Clear notes for this site', style: TextStyle(color: _kMuted, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notesLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, letterSpacing: 1, color: _kGoldDark, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _notesField(TextEditingController c, String label, String hint, {int lines = 1, int max = 500}) => TextField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        maxLength: max,
        keyboardType: lines == 1 ? TextInputType.text : TextInputType.multiline,
        onChanged: (_) => _notesChanged(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: _kMuted),
          isDense: true,
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
        ),
      );

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
              'Head counts use check-ins recorded so far today. Names, check-in times, hours and rates are never printed.',
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
