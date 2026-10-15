// lib/screens/project_daily_report_screen.dart
//
// PROJECT DAILY REPORT (Admin): one Word file in the client's form
// (UCC-IMS-CM-3003A) that combines both systems:
//   * STAFF and TRADESMEN (total / present / absent) from Team Flow;
//   * PLANT and TOOLS (operative / breakdown / idle) from Equipment Flow.
// A "profile" holds what does not change from day to day (header, project
// info, which sites of each system, the rows of the form, name mappings, BOQ).
// The Admin picks the profile, the date and the sections, optionally types the
// weather and the activities, checks the preview and downloads the .docx.
// What neither system knows (BOQ progress, photos...) stays empty for Word.
//
// Backend: /api/reports/project-daily/* (Admin only).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import 'payroll_export_service.dart';

// ASIK palette (same as the Daily Site Report screen).
const Color _kCharcoal = Color(0xff4b4a4d);
const Color _kGold = Color(0xffcbab5a);
const Color _kGoldDark = Color(0xff8a6a1f);
const Color _kGoldPale = Color(0xfffbf8ef);
const Color _kOlive = Color(0xff666633);
const Color _kInk = Color(0xff2b2a2e);
const Color _kMuted = Color(0xff6e6d72);
const Color _kLine = Color(0xffe2e1e3);
const Color _kBg = Color(0xfff6f6f7);
const Color _kDanger = Color(0xffb3261e);
const Color _kWarn = Color(0xff9a6700);
const Color _kWarnBg = Color(0xfffff8e6);

const Map<String, String> _kSections = {
  'info': 'Project info',
  'weather': 'Weather',
  'manpower': 'Manpower',
  'plant': 'Plant & tools',
  'boq': 'BOQ page',
  'activities': 'Activities',
  'photos': 'Photos page',
};
const Map<String, IconData> _kSectionIcons = {
  'info': Icons.badge_outlined,
  'weather': Icons.wb_sunny_outlined,
  'manpower': Icons.groups_2_outlined,
  'plant': Icons.precision_manufacturing_outlined,
  'boq': Icons.table_rows_outlined,
  'activities': Icons.construction_outlined,
  'photos': Icons.photo_library_outlined,
};
const Map<String, String> _kSky = {'sunny': 'Sunny', 'cloudy': 'Cloudy', 'rainy': 'Rainy', 'dusty': 'Dusty'};
const Map<String, IconData> _kSkyIcons = {
  'sunny': Icons.wb_sunny_rounded,
  'cloudy': Icons.cloud_rounded,
  'rainy': Icons.water_drop_rounded,
  'dusty': Icons.blur_on_rounded,
};

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map((e) => _map(e)).toList() : <Map<String, dynamic>>[];
List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

String _apiError(Object e, String fallback) {
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

class _Activity {
  final description = TextEditingController();
  final location = TextEditingController();
  _Activity([String d = '', String l = '']) {
    description.text = d;
    location.text = l;
  }
  bool get isEmpty => description.text.trim().isEmpty && location.text.trim().isEmpty;
  Map<String, String> toJson() => {'description': description.text.trim(), 'location': location.text.trim()};
  void dispose() {
    description.dispose();
    location.dispose();
  }
}

class ProjectDailyReportScreen extends StatefulWidget {
  const ProjectDailyReportScreen({super.key});

  @override
  State<ProjectDailyReportScreen> createState() => _ProjectDailyReportScreenState();
}

class _ProjectDailyReportScreenState extends State<ProjectDailyReportScreen> {
  final _apiFmt = DateFormat('yyyy-MM-dd');
  final _longFmt = DateFormat('EEEE, d MMMM yyyy');

  bool _loading = true;
  String? _loadError;
  DateTime _today = DateTime.now();
  DateTime _date = DateTime.now();

  List<Map<String, dynamic>> _profiles = [];
  int? _profileId;
  List<Map<String, dynamic>> _tfSites = [];
  Map<String, dynamic> _equipment = {};
  Map<String, dynamic> _defaults = {};

  final Map<String, bool> _sections = {for (final k in _kSections.keys) k: true};
  bool _fillPresentAbsent = true;
  bool _pendingAsOperative = false;

  final Set<String> _sky = {};
  final _tMax = TextEditingController();
  final _tMin = TextEditingController();
  String _humidity = '';
  final List<_Activity> _activities = [];

  Map<String, dynamic>? _preview;
  bool _previewLoading = false;
  String? _previewError;
  Timer? _debounce;
  int _previewSeq = 0;

  // unmapped name -> chosen row ("kind|name" -> label)
  final Map<String, String> _mapChoice = {};
  bool _savingMap = false;

  bool _generating = false;
  List<Map<String, dynamic>> _history = [];

  Map<String, dynamic>? get _profile {
    for (final p in _profiles) {
      if (p['profile_id'] == _profileId) return p;
    }
    return null;
  }

  Map<String, dynamic> get _config => _map(_profile?['config']);

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tMax.dispose();
    _tMin.dispose();
    for (final a in _activities) {
      a.dispose();
    }
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kDanger : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ------------------------------------------------------------------ data
  Future<void> _loadOptions({int? select}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await ApiConfig.dio.get('/reports/project-daily/options');
      final d = _map(res.data['data']);
      _profiles = _list(d['profiles']);
      _tfSites = _list(d['team_flow_sites']);
      _equipment = _map(d['equipment']);
      _defaults = _map(d['defaults']);
      final t = DateTime.tryParse(d['business_today']?.toString() ?? '');
      if (t != null) {
        _today = t;
        if (_date.isAfter(t)) _date = t;
      }
      final active = _profiles.where((p) => p['is_active'] == true).toList();
      final wanted = select ?? _profileId;
      if (wanted != null && active.any((p) => p['profile_id'] == wanted)) {
        _profileId = wanted;
      } else {
        _profileId = active.isNotEmpty ? active.first['profile_id'] as int : null;
      }
      _applyProfileDefaults();
      _loading = false;
      if (mounted) setState(() {});
      _schedulePreview(immediate: true);
      _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _apiError(e, 'Failed to load the report options.');
      });
    }
  }

  void _applyProfileDefaults() {
    final d = _map(_config['defaults']);
    final s = _map(d['sections']);
    for (final k in _kSections.keys) {
      _sections[k] = s[k] != false;
    }
    _fillPresentAbsent = d['fill_present_absent'] != false;
    _pendingAsOperative = d['pending_as_operative'] == true;
    _mapChoice.clear();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiConfig.dio.get('/reports/project-daily/history', queryParameters: {'limit': 20});
      _history = _list(res.data['data']);
      if (mounted) setState(() {});
    } catch (_) {/* optional on this page */}
  }

  Map<String, dynamic> _body() => {
        'profile_id': _profileId,
        'date': _apiFmt.format(_date),
        'sections': _sections,
        'fill_present_absent': _fillPresentAbsent,
        'pending_as_operative': _pendingAsOperative,
        'weather': {
          for (final k in _kSky.keys) k: _sky.contains(k),
          'temp_max': _tMax.text.trim(),
          'temp_min': _tMin.text.trim(),
          'humidity': _humidity,
        },
        'activities': _activities.where((a) => !a.isEmpty).map((a) => a.toJson()).toList(),
      };

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    if (_profileId == null) {
      setState(() {
        _preview = null;
        _previewError = null;
      });
      return;
    }
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 400), _runPreview);
  }

  Future<void> _runPreview() async {
    final seq = ++_previewSeq;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final res = await ApiConfig.dio.post('/reports/project-daily/preview', data: _body());
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = _map(res.data['data']);
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _previewLoading = false;
        _previewError = _apiError(e, 'Could not load the preview.');
      });
    }
  }

  Future<void> _download(Future<Response<List<int>>> Function() call, String fallbackName) async {
    final res = await call();
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty file');
    final no = res.headers.value('x-report-no');
    await PayrollExportService.exportBytes(bytes, '${no ?? fallbackName}.docx');
    final warnings = int.tryParse(res.headers.value('x-report-warnings') ?? '') ?? 0;
    _snack(warnings > 0
        ? 'Report ${no ?? ''} is ready ($warnings note${warnings == 1 ? '' : 's'}: see the preview).'
        : 'Report ${no ?? ''} is ready.');
  }

  Future<void> _generate() async {
    if (_profileId == null) {
      _snack('Choose a report profile.', error: true);
      return;
    }
    if (!_sections.values.any((v) => v)) {
      _snack('Choose at least one section.', error: true);
      return;
    }
    setState(() => _generating = true);
    try {
      await _download(
        () => ApiConfig.dio.post<List<int>>(
          '/reports/project-daily/generate',
          data: _body(),
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)),
        ),
        'Project_Daily_Report_${_apiFmt.format(_date)}',
      );
      _loadHistory();
    } catch (e) {
      _snack(_apiError(e, 'Failed to generate the report.'), error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _redownload(Map<String, dynamic> h) async {
    try {
      await _download(
        () => ApiConfig.dio.get<List<int>>(
          '/reports/project-daily/${h['report_id']}/docx',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)),
        ),
        h['report_no']?.toString() ?? 'Project_Daily_Report',
      );
    } catch (e) {
      _snack(_apiError(e, 'Failed to download the report.'), error: true);
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
    setState(() {});
    _schedulePreview(immediate: true);
  }

  // ------------------------------------------------------------- suggestions
  void _useSuggestedWeather() {
    final w = _map(_map(_preview?['suggestions'])['weather']);
    setState(() {
      for (final k in _kSky.keys) {
        if (w[k] == true) _sky.add(k);
      }
    });
  }

  void _addSuggestedActivity(Map<String, dynamic> a) {
    final d = (a['description'] ?? '').toString();
    final l = (a['location'] ?? '').toString();
    if (_activities.any((x) => x.description.text.trim() == d && x.location.text.trim() == l)) return;
    setState(() {
      final empty = _activities.where((x) => x.isEmpty).toList();
      if (empty.isNotEmpty) {
        empty.first.description.text = d;
        empty.first.location.text = l;
      } else {
        _activities.add(_Activity(d, l));
      }
    });
  }

  // ------------------------------------------------------------- mappings
  Future<void> _saveMappings() async {
    final p = _profile;
    if (p == null || _mapChoice.isEmpty) return;
    final cfg = _config;
    final maps = {
      'staff': _map(cfg['staff_map']),
      'trades': _map(cfg['trade_map']),
      'equipment': _map(cfg['equipment_map']),
    };
    _mapChoice.forEach((key, label) {
      final i = key.indexOf('|');
      maps[key.substring(0, i)]![key.substring(i + 1)] = label;
    });
    setState(() => _savingMap = true);
    try {
      await ApiConfig.dio.put('/reports/project-daily/profiles/${p['profile_id']}', data: {
        'config': {'staff_map': maps['staff'], 'trade_map': maps['trades'], 'equipment_map': maps['equipment']},
      });
      _snack('Saved. These names go to the chosen rows from now on.');
      _mapChoice.clear();
      await _loadOptions(select: p['profile_id'] as int);
    } catch (e) {
      _snack(_apiError(e, 'Could not save the mapping.'), error: true);
    } finally {
      if (mounted) setState(() => _savingMap = false);
    }
  }

  // ------------------------------------------------------------- profiles
  Future<void> _openProfileEditor({Map<String, dynamic>? profile}) async {
    final saved = await Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProfileEditor(
        profile: profile,
        defaults: _map(_defaults['config']),
        tfSites: _tfSites,
        equipment: _equipment,
      ),
    ));
    if (saved != null) await _loadOptions(select: saved);
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: CustomAppBar(
        title: 'Project Daily Report',
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

  ButtonStyle get _outlined => OutlinedButton.styleFrom(
        foregroundColor: _kInk,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: const BorderSide(color: _kLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _formColumn() {
    final active = _profiles.where((p) => p['is_active'] == true).toList();
    final suggestions = _map(_preview?['suggestions']);
    final suggestedSky = _map(suggestions['weather']).entries.where((e) => e.value == true).map((e) => e.key).toList();
    final suggestedActs = _list(suggestions['activities']);
    var step = 2; // cards 3.. are numbered by what is shown
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 1. Profile & date
      _card(
        step: '1',
        title: 'Profile & date',
        hint: 'A profile = one agreement: header, project info, its sites in both systems, the form rows and the BOQ.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (active.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kGoldPale, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _kGoldDark),
                const SizedBox(width: 10),
                const Expanded(child: Text('No profile yet. Create the first one (for example "Agreement 71 - T2 Underground").')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kCharcoal),
                  onPressed: () => _openProfileEditor(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New profile'),
                ),
              ]),
            )
          else
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 420),
                child: DropdownButtonFormField<int>(
                  key: ValueKey(_profileId),
                  value: _profileId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Profile',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: active
                      .map((p) => DropdownMenuItem<int>(value: p['profile_id'] as int, child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _profileId = v;
                      _applyProfileDefaults();
                    });
                    _schedulePreview(immediate: true);
                  },
                ),
              ),
              OutlinedButton.icon(
                style: _outlined,
                onPressed: _profile == null ? null : () => _openProfileEditor(profile: _profile),
                icon: const Icon(Icons.tune_rounded, size: 18, color: _kGoldDark),
                label: const Text('Edit profile'),
              ),
              TextButton.icon(
                onPressed: () => _openProfileEditor(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New profile'),
              ),
            ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: _outlined,
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 18, color: _kGoldDark),
              label: Text(
                '${_longFmt.format(_date)}${DateUtils.isSameDay(_date, _today) ? '  (today)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
      ),

      // 2. Sections
      _card(
        step: '2',
        title: 'What goes in the report',
        hint: 'A section switched off is not printed. Empty cells stay empty for Word.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kSections.entries.map((e) {
              final on = _sections[e.key] ?? true;
              return FilterChip(
                selected: on,
                showCheckmark: false,
                avatar: Icon(_kSectionIcons[e.key], size: 18, color: on ? Colors.white : _kMuted),
                label: Text(e.value, style: TextStyle(color: on ? Colors.white : _kInk, fontWeight: FontWeight.w600)),
                selectedColor: _kCharcoal,
                backgroundColor: Colors.white,
                side: BorderSide(color: on ? _kCharcoal : _kLine),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (v) {
                  setState(() => _sections[e.key] = v);
                  _schedulePreview();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (_sections['manpower'] == true)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeTrackColor: _kGold,
              title: const Text('Fill PRESENT and ABSENT'),
              subtitle: const Text('Off = only the TOTAL column is filled (as on the paper form).'),
              value: _fillPresentAbsent,
              onChanged: (v) => setState(() => _fillPresentAbsent = v),
            ),
          if (_sections['plant'] == true)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeTrackColor: _kGold,
              title: const Text('Count machines not recorded yet as OPERATIVE'),
              subtitle: const Text('Deployed on the site but nothing recorded for the date yet.'),
              value: _pendingAsOperative,
              onChanged: (v) {
                setState(() => _pendingAsOperative = v);
                _schedulePreview();
              },
            ),
        ]),
      ),

      // 3. Weather
      if (_sections['weather'] == true)
        _card(
          step: '${++step}',
          title: 'Weather',
          hint: 'Optional. Leave empty to fill it in Word.',
          trailing: suggestedSky.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: _useSuggestedWeather,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text('From site report: ${suggestedSky.map((k) => _kSky[k]).join(', ')}'),
                ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kSky.entries.map((e) {
                final on = _sky.contains(e.key);
                return FilterChip(
                  selected: on,
                  showCheckmark: false,
                  avatar: Icon(_kSkyIcons[e.key], size: 18, color: on ? Colors.white : _kGoldDark),
                  label: Text(e.value, style: TextStyle(color: on ? Colors.white : _kInk)),
                  selectedColor: _kCharcoal,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: on ? _kCharcoal : _kLine),
                  onSelected: (v) => setState(() => v ? _sky.add(e.key) : _sky.remove(e.key)),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 110, child: _numField(_tMax, 'Max °C')),
              SizedBox(width: 110, child: _numField(_tMin, 'Min °C')),
              SegmentedButton<String>(
                style: SegmentedButton.styleFrom(selectedBackgroundColor: _kCharcoal, selectedForegroundColor: Colors.white),
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'high', label: Text('High')),
                  ButtonSegment(value: 'medium', label: Text('Medium')),
                  ButtonSegment(value: 'low', label: Text('Low')),
                ],
                selected: _humidity.isEmpty ? <String>{} : {_humidity},
                onSelectionChanged: (v) => setState(() => _humidity = v.isEmpty ? '' : v.first),
              ),
              const Text('Humidity', style: TextStyle(color: _kMuted, fontSize: 12)),
            ]),
          ]),
        ),

      // 4. Activities
      if (_sections['activities'] == true)
        _card(
          step: '${++step}',
          title: 'Activities',
          hint: 'Optional. Empty = 3 blank lines in the Word file.',
          trailing: TextButton.icon(
            onPressed: () => setState(() => _activities.add(_Activity())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add line'),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (suggestedActs.isNotEmpty) ...[
              const Text('Suggestions (Daily Site Report and equipment supervisors) — tap to add:',
                  style: TextStyle(fontSize: 12, color: _kMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestedActs.map((a) {
                  return ActionChip(
                    avatar: Icon(a['source'] == 'equipment' ? Icons.precision_manufacturing_outlined : Icons.summarize_outlined,
                        size: 16, color: _kGoldDark),
                    label: Text('${a['description']}  ·  ${a['location']}', overflow: TextOverflow.ellipsis),
                    backgroundColor: _kGoldPale,
                    side: const BorderSide(color: _kLine),
                    onPressed: () => _addSuggestedActivity(a),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (_activities.isEmpty)
              const Text('No activity typed.', style: TextStyle(color: _kMuted))
            else
              ..._activities.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      SizedBox(
                        width: 26,
                        child: Text('${e.key + 1}', style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(flex: 3, child: _textField(e.value.description, 'Description')),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _textField(e.value.location, 'Location')),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close_rounded, color: _kMuted),
                        onPressed: () {
                          final removed = _activities[e.key];
                          setState(() => _activities.removeAt(e.key));
                          // dispose after the row is gone from the tree
                          WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                        },
                      ),
                    ]),
                  )),
          ]),
        ),

      // 5. Generate
      _card(
        step: '${++step}',
        title: 'Generate',
        hint: 'Word file (.docx) in the client form UCC-IMS-CM-3003A. Photos and BOQ progress are added in Word.',
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _kOlive,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _generating || _profileId == null ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.description_rounded),
            label: Text(_generating ? 'Generating…' : 'Generate Word file'),
          ),
        ),
      ),
    ]);
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
        maxLength: 6,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _textField(TextEditingController c, String label) => TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  // ------------------------------------------------------------ side column
  Widget _sideColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _previewCard(),
      _historyCard(),
    ]);
  }

  Widget _previewCard() {
    final p = _preview;
    final warnings = _strings(p?['warnings']);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          decoration: const BoxDecoration(
            color: _kCharcoal,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.visibility_rounded, color: _kGold, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (_previewLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
            else
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                onPressed: _profileId == null ? null : () => _schedulePreview(immediate: true),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _profileId == null
              ? const Text('Choose or create a profile.', style: TextStyle(color: _kMuted))
              : _previewError != null
                  ? Text(_previewError!, style: const TextStyle(color: _kDanger))
                  : p == null
                      ? const Text('Loading…', style: TextStyle(color: _kMuted))
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _sourcesLine(p),
                          const SizedBox(height: 12),
                          if (warnings.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: _kWarnBg, borderRadius: BorderRadius.circular(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: warnings
                                    .map((w) => Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            const Icon(Icons.warning_amber_rounded, size: 16, color: _kWarn),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(w, style: const TextStyle(fontSize: 12.5, color: _kWarn))),
                                          ]),
                                        ))
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_sections['manpower'] == true) _manpowerPreview(_map(p['manpower'])),
                          if (_sections['plant'] == true) _plantPreview(_map(p['plant'])),
                          _unmappedBlock(_map(p['unmapped'])),
                        ]),
        ),
      ]),
    );
  }

  Widget _sourcesLine(Map<String, dynamic> p) {
    final s = _map(p['sources']);
    final tf = _list(s['team_flow_sites']).map((x) => x['site_name']).join(', ');
    final eq = _list(s['equipment_sites']).map((x) => x['site_name']).join(', ');
    Widget chip(IconData i, String label, String value, bool ok) => Row(children: [
          Icon(i, size: 16, color: ok ? _kGoldDark : _kDanger),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12.5, color: _kMuted)),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _kInk), overflow: TextOverflow.ellipsis),
          ),
        ]);
    return Column(children: [
      chip(Icons.groups_2_rounded, 'Team Flow', tf, true),
      const SizedBox(height: 4),
      chip(Icons.precision_manufacturing_rounded, 'Equipment', eq, s['equipment_ok'] != false),
    ]);
  }

  Widget _kpi(String label, String value, {Color color = _kInk}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _kMuted)),
          ]),
        ),
      );

  Widget _rowsTable(List<Map<String, dynamic>> rows, List<String> cols, List<String> keys) {
    final shown = rows.where((r) => keys.any((k) => _int(r[k]) > 0)).toList();
    if (shown.isEmpty) return const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Nothing for this date.', style: TextStyle(color: _kMuted, fontSize: 12.5)));
    const h = TextStyle(fontSize: 11, color: _kMuted, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(3)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(horizontalInside: BorderSide(color: _kLine, width: 0.6)),
        children: [
          TableRow(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(cols[0], style: h)),
            for (final c in cols.skip(1)) Text(c, style: h, textAlign: TextAlign.right),
          ]),
          for (final r in shown)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(r['label'].toString(), style: const TextStyle(fontSize: 12.5, color: _kInk)),
              ),
              for (final k in keys)
                Text('${_int(r[k])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
        ],
      ),
    );
  }

  Widget _manpowerPreview(Map<String, dynamic> m) {
    final st = _map(m['staff_total']);
    final tt = _map(m['trade_total']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('MANPOWER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _kGoldDark, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('Staff (present ${_int(st['present'])})', '${_int(st['total'])}'),
        const SizedBox(width: 8),
        _kpi('Tradesmen (present ${_int(tt['present'])})', '${_int(tt['total'])}'),
        const SizedBox(width: 8),
        _kpi('Grand total', '${_int(m['grand_total'])}', color: _kOlive),
      ]),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Rows of the form', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          _rowsTable(_list(m['staff']), ['STAFF', 'Total', 'Present', 'Absent'], ['total', 'present', 'absent']),
          _rowsTable(_list(m['trades']), ['TRADESMEN', 'Total', 'Present', 'Absent'], ['total', 'present', 'absent']),
        ],
      ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _plantPreview(Map<String, dynamic> m) {
    final pt = _map(m['plant_total']);
    final tt = _map(m['tool_total']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('PLANT & TOOLS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _kGoldDark, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('Operative', '${_int(pt['operative']) + _int(tt['operative'])}', color: Colors.green.shade800),
        const SizedBox(width: 8),
        _kpi('Breakdown', '${_int(pt['breakdown']) + _int(tt['breakdown'])}', color: _kDanger),
        const SizedBox(width: 8),
        _kpi('Idle', '${_int(pt['idle']) + _int(tt['idle'])}', color: _kWarn),
      ]),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Rows of the form', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          _rowsTable(_list(m['plant']), ['PLANT', 'Oper.', 'Brkdn', 'Idle'], ['operative', 'breakdown', 'idle']),
          _rowsTable(_list(m['tools']), ['TOOL', 'Oper.', 'Brkdn', 'Idle'], ['operative', 'breakdown', 'idle']),
        ],
      ),
      const SizedBox(height: 6),
    ]);
  }

  /// Names that are not a row of the form: choose the row, save it in the profile.
  Widget _unmappedBlock(Map<String, dynamic> u) {
    final cfg = _config;
    final groups = <String, List<String>>{
      'staff': _strings(u['staff']),
      'trades': _strings(u['trades']),
      'equipment': _strings(u['equipment']),
    }..removeWhere((_, v) => v.isEmpty);
    if (groups.isEmpty) return const SizedBox.shrink();
    List<String> targets(String kind) {
      if (kind == 'staff') return _strings(cfg['staff_rows']);
      if (kind == 'trades') return _strings(cfg['trade_rows']);
      return [..._strings(cfg['plant_rows']), ..._strings(cfg['tool_rows'])];
    }

    const kindLabel = {'staff': 'Staff position', 'trades': 'Trade', 'equipment': 'Equipment type'};
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: _kGold), borderRadius: BorderRadius.circular(10), color: _kGoldPale),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Names not on the form', style: TextStyle(fontWeight: FontWeight.w700, color: _kInk)),
        const Text('Each one is printed on its own extra row. Choose the row it belongs to:',
            style: TextStyle(fontSize: 12, color: _kMuted)),
        const SizedBox(height: 8),
        for (final g in groups.entries)
          for (final name in g.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${kindLabel[g.key]}\n', style: const TextStyle(fontSize: 10.5, color: _kMuted)),
                    TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ])),
                ),
                Expanded(
                  flex: 3,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Keep its own row'),
                    value: _mapChoice['${g.key}|$name'],
                    items: targets(g.key).map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() {
                      if (v == null) {
                        _mapChoice.remove('${g.key}|$name');
                      } else {
                        _mapChoice['${g.key}|$name'] = v;
                      }
                    }),
                  ),
                ),
              ]),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kCharcoal),
            onPressed: _mapChoice.isEmpty || _savingMap ? null : _saveMappings,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(_savingMap ? 'Saving…' : 'Save mapping'),
          ),
        ),
      ]),
    );
  }

  Widget _historyCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kLine)),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Issued reports', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _kInk)),
        const SizedBox(height: 6),
        if (_history.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('None yet.', style: TextStyle(color: _kMuted)))
        else
          ..._history.map((h) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.description_outlined, color: _kGoldDark),
                title: Text(h['report_no']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${h['profile_name'] ?? ''} · ${h['report_date'] ?? ''} · ${h['generated_by'] ?? ''}',
                    overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: () => _redownload(h), child: const Text('Download')),
              )),
      ]),
    );
  }
}

// ============================================================================
// Profile editor
// ============================================================================
class _ProfileEditor extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final Map<String, dynamic> defaults;
  final List<Map<String, dynamic>> tfSites;
  final Map<String, dynamic> equipment;
  const _ProfileEditor({required this.profile, required this.defaults, required this.tfSites, required this.equipment});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late Map<String, dynamic> _cfg;
  final _name = TextEditingController();
  final Map<String, TextEditingController> _header = {};
  final Map<String, TextEditingController> _info = {};
  final Map<String, TextEditingController> _rows = {};
  bool _pageNumbers = true;
  final Set<int> _tf = {};
  final Set<int> _eq = {};
  late List<Map<String, dynamic>> _boq;
  final Map<String, Map<String, dynamic>> _maps = {};
  final Map<String, bool> _sections = {};
  bool _fillPA = true;
  bool _pendingOp = false;
  bool _active = true;
  bool _saving = false;

  static const _headerFields = {'doc_ref': 'Document reference', 'rev_no': 'Rev. No.', 'rev_date': 'Rev. Date'};
  static const _infoFields = {
    'agreement_title': 'Title line (e.g. Daily Report – Agreement 71)',
    'project_ref': 'Project Ref.',
    'contract_ref': 'Contract',
    'project_name': 'Project Name',
    'project_location': 'Project Location',
    'client': 'Client',
    'consultant': 'Consultant',
    'commencement_date': 'Commencement (YYYY-MM-DD)',
    'completion_date': 'Completion Date (YYYY-MM-DD)',
  };
  static const _multiline = {'project_name', 'project_location', 'client'};
  static const _rowFields = {
    'staff_rows': 'STAFF rows',
    'trade_rows': 'TRADESMEN rows',
    'plant_rows': 'PLANT rows',
    'tool_rows': 'TOOL rows',
  };
  static const _mapFields = {'staff_map': 'Staff positions', 'trade_map': 'Trades', 'equipment_map': 'Equipment types'};

  bool get _isNew => widget.profile == null;

  @override
  void initState() {
    super.initState();
    _cfg = _map(widget.profile?['config'] ?? widget.defaults);
    _name.text = widget.profile?['name']?.toString() ?? '';
    _active = widget.profile?['is_active'] != false;
    final h = _map(_cfg['header']);
    for (final k in _headerFields.keys) {
      _header[k] = TextEditingController(text: (h[k] ?? '').toString());
    }
    _pageNumbers = h['page_numbers'] != false;
    final i = _map(_cfg['info']);
    for (final k in _infoFields.keys) {
      _info[k] = TextEditingController(text: (i[k] ?? '').toString());
    }
    for (final k in _rowFields.keys) {
      _rows[k] = TextEditingController(text: _strings(_cfg[k]).join('\n'));
    }
    _tf.addAll(_strings(_cfg['tf_site_ids']).map(int.parse));
    _eq.addAll(_strings(_cfg['eq_site_ids']).map(int.parse));
    _boq = _list(_cfg['boq']);
    for (final k in _mapFields.keys) {
      _maps[k] = _map(_cfg[k]);
    }
    final d = _map(_cfg['defaults']);
    final s = _map(d['sections']);
    for (final k in _kSections.keys) {
      _sections[k] = s[k] != false;
    }
    _fillPA = d['fill_present_absent'] != false;
    _pendingOp = d['pending_as_operative'] == true;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in [..._header.values, ..._info.values, ..._rows.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Map<String, dynamic> _configOut() => {
        'header': {for (final e in _header.entries) e.key: e.value.text.trim(), 'page_numbers': _pageNumbers},
        'info': {for (final e in _info.entries) e.key: e.value.text.trim()},
        'tf_site_ids': _tf.toList(),
        'eq_site_ids': _eq.toList(),
        for (final e in _rows.entries) e.key: _lines(e.value),
        ..._maps,
        'boq': _boq,
        'defaults': {'sections': _sections, 'fill_present_absent': _fillPA, 'pending_as_operative': _pendingOp},
      };

  Future<void> _save() async {
    if (_name.text.trim().length < 3) {
      _toast('Enter a profile name (at least 3 characters).');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {'name': _name.text.trim(), 'config': _configOut(), if (!_isNew) 'is_active': _active};
      final res = _isNew
          ? await ApiConfig.dio.post('/reports/project-daily/profiles', data: body)
          : await ApiConfig.dio.put('/reports/project-daily/profiles/${widget.profile!['profile_id']}', data: body);
      if (!mounted) return;
      Navigator.of(context).pop(_map(res.data['data'])['profile_id'] as int);
    } catch (e) {
      _toast(_apiError(e, 'Could not save the profile.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: _kDanger, behavior: SnackBarBehavior.floating));
  }

  /// Fills the empty project fields from the Team Flow project of the chosen sites.
  void _fillFromTeamFlow() {
    final chosen = widget.tfSites.where((s) => _tf.contains(s['site_id'])).toList();
    String one(String k) {
      final v = chosen.map((s) => (s[k] ?? '').toString()).where((x) => x.isNotEmpty).toSet();
      return v.length == 1 ? v.first : '';
    }

    void put(String field, String v) {
      if (_info[field]!.text.trim().isEmpty && v.isNotEmpty) _info[field]!.text = v;
    }

    setState(() {
      put('project_name', one('project_name').toUpperCase());
      put('client', one('client_name').toUpperCase());
      put('project_location', one('location').toUpperCase());
      final contract = one('contract_name');
      if (contract.isNotEmpty) put('agreement_title', 'Daily Report – $contract');
      if (_name.text.trim().isEmpty && contract.isNotEmpty) _name.text = contract;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCharcoal,
          foregroundColor: Colors.white,
          title: Text(_isNew ? 'New report profile' : 'Edit report profile'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kGold, foregroundColor: _kInk),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: _kGold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'General'), Tab(text: 'Sites'), Tab(text: 'Form rows'), Tab(text: 'BOQ')],
          ),
        ),
        body: TabBarView(children: [
          _pane(_generalTab()),
          _pane(_sitesTab()),
          _pane(_rowsTab()),
          _boqTab(),
        ]),
      ),
    );
  }

  Widget _pane(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child)),
      );

  Widget _box(String title, List<Widget> children, {String? hint, Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (trailing != null) trailing,
          ]),
          if (hint != null) Text(hint, style: const TextStyle(fontSize: 12, color: _kMuted)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _field(TextEditingController c, String label, {bool multi = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: multi ? 2 : 1,
          maxLines: multi ? 3 : 1,
          decoration: InputDecoration(labelText: label, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
      );

  Widget _generalTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _box('Profile', [
          _field(_name, 'Profile name (e.g. Agreement 71 - T2 Underground)'),
          if (!_isNew)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('An inactive profile is hidden from the report page; its reports stay downloadable.'),
              value: _active,
              activeTrackColor: _kGold,
              onChanged: (v) => setState(() => _active = v),
            ),
        ]),
        _box('Header (every page)', [
          Wrap(spacing: 10, children: [
            for (final e in _headerFields.entries) SizedBox(width: 240, child: _field(_header[e.key]!, e.value)),
          ]),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Print the page number'),
            value: _pageNumbers,
            activeTrackColor: _kGold,
            onChanged: (v) => setState(() => _pageNumbers = v),
          ),
        ]),
        _box(
          'Project info',
          [for (final e in _infoFields.entries) _field(_info[e.key]!, e.value, multi: _multiline.contains(e.key))],
          hint: 'Printed as typed. Empty Project Name, Location, Client and dates are taken from Team Flow (project / contract).',
          trailing: TextButton.icon(
            onPressed: _tf.isEmpty ? null : _fillFromTeamFlow,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('Fill from Team Flow'),
          ),
        ),
        _box('Defaults when issuing', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _kSections.entries)
              FilterChip(
                label: Text(e.value),
                selected: _sections[e.key] ?? true,
                selectedColor: _kGoldPale,
                checkmarkColor: _kGoldDark,
                onSelected: (v) => setState(() => _sections[e.key] = v),
              ),
          ]),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fill PRESENT and ABSENT'),
            value: _fillPA,
            activeTrackColor: _kGold,
            onChanged: (v) => setState(() => _fillPA = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Count machines not recorded yet as OPERATIVE'),
            value: _pendingOp,
            activeTrackColor: _kGold,
            onChanged: (v) => setState(() => _pendingOp = v),
          ),
        ]),
      ]);

  Widget _sitesTab() {
    final eqSites = _list(widget.equipment['sites']);
    final eqOk = widget.equipment['ok'] == true;
    Widget tile(String title, String sub, bool on, ValueChanged<bool> f) => CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: _kCharcoal,
          value: on,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub.isEmpty ? null : Text(sub),
          onChanged: (v) => f(v ?? false),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _box('Team Flow sites (manpower)', [
        if (widget.tfSites.isEmpty) const Text('There is no Active site.', style: TextStyle(color: _kMuted)),
        for (final s in widget.tfSites)
          tile(s['site_name'].toString(), [s['project_name'], s['contract_name']].where((x) => x != null).join(' · '),
              _tf.contains(s['site_id']), (v) => setState(() => v ? _tf.add(s['site_id'] as int) : _tf.remove(s['site_id']))),
      ], hint: 'Workers and staff assigned to these sites are counted.'),
      _box('Equipment Flow sites (plant)', [
        if (!eqOk)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _kWarnBg, borderRadius: BorderRadius.circular(10)),
            child: Text(widget.equipment['error']?.toString() ?? 'The equipment system is not reachable.',
                style: const TextStyle(color: _kWarn)),
          ),
        for (final s in eqSites)
          tile('${s['site_code']} · ${s['site_name']}', [s['project_name'], s['status'] == 'Active' ? null : s['status']].where((x) => x != null).join(' · '),
              _eq.contains(s['site_id']), (v) => setState(() => v ? _eq.add(s['site_id'] as int) : _eq.remove(s['site_id']))),
        if (eqOk && eqSites.isEmpty) const Text('No equipment site.', style: TextStyle(color: _kMuted)),
      ], hint: 'Machines of these equipment sites are counted. The two systems have separate site lists: link them here.'),
    ]);
  }

  Widget _rowsTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _box('Rows of the form', [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth >= 640 ? (c.maxWidth - 12) / 2 : c.maxWidth;
            return Wrap(spacing: 12, children: [
              for (final e in _rowFields.entries)
                SizedBox(
                  width: w,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _rows[e.key],
                      minLines: 6,
                      maxLines: 12,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: e.value,
                        alignLabelWithHint: true,
                        helperText: 'One row per line, printed in this order',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ], hint: 'The labels are printed exactly as typed. A name from the systems that matches no row gets its own row.'),
        _box('Name mappings', [
          for (final m in _mapFields.entries) ...[
            Text(m.value, style: const TextStyle(fontWeight: FontWeight.w600, color: _kGoldDark)),
            if (_maps[m.key]!.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('None.', style: TextStyle(color: _kMuted)))
            else
              for (final e in _maps[m.key]!.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e.key}  →  ${e.value}'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, color: _kMuted),
                    onPressed: () => setState(() => _maps[m.key]!.remove(e.key)),
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ], hint: 'Added from the report page ("Names not on the form"). Common names (Labourer, Site Engineer, Dump Truck…) are known already.'),
      ]);

  // ------------------------------------------------------------------ BOQ
  Widget _boqTab() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Expanded(
            child: Text('${_boq.length} lines · printed on page 2. CURR / BALANCE can stay empty and be filled in Word.',
                style: const TextStyle(color: _kMuted, fontSize: 12.5)),
          ),
          TextButton.icon(onPressed: () => _editBoq(null), icon: const Icon(Icons.add_rounded), label: const Text('Add line')),
          TextButton.icon(
            onPressed: () => setState(() => _boq.add({'type': 'gap'})),
            icon: const Icon(Icons.space_bar_rounded),
            label: const Text('Add gap'),
          ),
        ]),
      ),
      Expanded(
        child: _boq.isEmpty
            ? const Center(child: Text('No BOQ line. The BOQ page is skipped.', style: TextStyle(color: _kMuted)))
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _boq.length,
                onReorder: (a, b) => setState(() {
                  if (b > a) b -= 1;
                  _boq.insert(b, _boq.removeAt(a));
                }),
                itemBuilder: (context, i) {
                  final r = _boq[i];
                  final gap = r['type'] == 'gap';
                  final fill = r['fill'] == 'green' ? const Color(0xffe2efd9) : (r['fill'] == 'gray' ? const Color(0xffececec) : Colors.white);
                  return Card(
                    key: ObjectKey(r),
                    color: gap ? _kBg : fill,
                    elevation: 0,
                    shape: RoundedRectangleBorder(side: const BorderSide(color: _kLine), borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 34,
                        child: Text(gap ? '' : (r['task_code'] ?? '').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: _kGoldDark)),
                      ),
                      title: Text(
                        gap ? '— empty gap row —' : ((r['description'] ?? '').toString().isEmpty ? '(empty line)' : r['description'].toString()),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: r['bold'] == true ? FontWeight.w700 : FontWeight.normal, color: gap ? _kMuted : _kInk),
                      ),
                      subtitle: gap ? null : Text([r['unit'], r['quantity']].where((x) => x != null && '$x'.isNotEmpty).join('  ·  ')),
                      onTap: gap ? null : () => _editBoq(i),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline_rounded, color: _kMuted),
                          onPressed: () => setState(() => _boq.removeAt(i)),
                        ),
                        const SizedBox(width: 28),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _editBoq(int? index) async {
    final r = index == null ? <String, dynamic>{'type': 'line'} : Map<String, dynamic>.from(_boq[index]);
    const fields = {
      'task_code': 'Task Code',
      'cost_code': 'Cost Code',
      'unit': 'Unit',
      'quantity': 'Quantity',
      'budget': 'BUDGET',
      'curr_1': 'CURR (1)',
      'curr_2': 'CURR (2)',
      'balance': 'BALANCE',
    };
    final ctrls = {for (final k in fields.keys) k: TextEditingController(text: (r[k] ?? '').toString())};
    final desc = TextEditingController(text: (r['description'] ?? '').toString());
    bool bold = r['bold'] == true;
    String fill = (r['fill'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(index == null ? 'Add BOQ line' : 'Edit BOQ line'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: desc,
                  minLines: 2,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), alignLabelWithHint: true),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in fields.entries)
                    SizedBox(
                      width: 125,
                      child: TextField(
                        controller: ctrls[e.key],
                        decoration: InputDecoration(labelText: e.value, isDense: true, border: const OutlineInputBorder()),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Checkbox(value: bold, onChanged: (v) => setD(() => bold = v ?? false)),
                  const Text('Bold'),
                  const Spacer(),
                  const Text('Fill: '),
                  DropdownButton<String>(
                    value: fill,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('None')),
                      DropdownMenuItem(value: 'green', child: Text('Green (contract value)')),
                      DropdownMenuItem(value: 'gray', child: Text('Gray (section)')),
                    ],
                    onChanged: (v) => setD(() => fill = v ?? ''),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final out = <String, dynamic>{'type': 'line', 'description': desc.text.trim()};
      for (final k in fields.keys) {
        final v = ctrls[k]!.text.trim();
        if (v.isNotEmpty) out[k] = v;
      }
      if (bold) out['bold'] = true;
      if (fill.isNotEmpty) out['fill'] = fill;
      setState(() {
        if (index == null) {
          _boq.add(out);
        } else {
          _boq[index] = out;
        }
      });
    }
    // the dialog is still animating out: dispose a moment later
    Future.delayed(const Duration(milliseconds: 500), () {
      desc.dispose();
      for (final c in ctrls.values) {
        c.dispose();
      }
    });
  }
}
