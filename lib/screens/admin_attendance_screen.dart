import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final Set<int> _selectedIds = <int>{};
  Map<String, List<Map<String, dynamic>>> _grouped = {};
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await ApiConfig.dio.get('/admin/attendance/pending');
      final raw = response.data is Map ? response.data['data'] : null;
      final grouped = <String, List<Map<String, dynamic>>>{};

      if (raw is List) {
        for (final value in raw) {
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          final rawDate = '${item['record_date'] ?? '1970-01-01'}';
          final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
          grouped.putIfAbsent(date, () => <Map<String, dynamic>>[]).add(item);
        }
      }

      final sorted = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
      final ordered = <String, List<Map<String, dynamic>>>{};
      for (final date in sorted) {
        ordered[date] = grouped[date]!;
      }

      if (!mounted) return;
      setState(() {
        _grouped = ordered;
        _selectedIds.clear();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_errorMessage(e, 'Failed to load attendance records.'), false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Failed to load attendance records.', false);
    }
  }

  String _errorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }

  List<int> _idsForDate(List<Map<String, dynamic>> items) {
    return items
        .map((item) => int.tryParse('${item['attendance_id']}'))
        .whereType<int>()
        .toList();
  }

  Future<void> _reviewSelected(List<int> ids, String status, {String? note}) async {
    if (ids.isEmpty || _working) return;
    setState(() => _working = true);

    final succeeded = <int>[];
    final failed = <int>[];
    for (final id in ids) {
      try {
        await ApiConfig.dio.post('/admin/attendance/review', data: {
          'attendance_id': id,
          'status': status,
          'admin_note': note,
        });
        succeeded.add(id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() => _working = false);
    if (failed.isEmpty) {
      _showMessage('${succeeded.length} record(s) processed successfully.', true);
    } else {
      _showMessage('${succeeded.length} succeeded, ${failed.length} failed.', false);
    }
    await _fetchData();
  }

  Future<String?> _askRejectionReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject attendance record'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Explain what the supervisor must correct',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showManagementLeaveDialog(int attendanceId) async {
    final hours = TextEditingController();
    final reason = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Management leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Hours', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    final hoursValue = double.tryParse(hours.text.trim());
    final reasonValue = reason.text.trim();
    hours.dispose();
    reason.dispose();
    if (result != true || hoursValue == null || hoursValue < 0 || hoursValue > 24) {
      if (result == true && mounted) _showMessage('Hours must be a number between 0 and 24.', false);
      return;
    }

    try {
      await ApiConfig.dio.patch('/attendance/$attendanceId/management-leave', data: {
        'hours': hoursValue,
        'reason': reasonValue,
      });
      if (!mounted) return;
      _showMessage('Management leave saved.', true);
      await _fetchData();
    } on DioException catch (e) {
      if (mounted) _showMessage(_errorMessage(e, 'Failed to save management leave.'), false);
    }
  }

  Future<void> _showSettingsDialog() async {
    bool lunchPaid = false;
    int minutes = 480;
    try {
      final response = await ApiConfig.dio.get('/admin/attendance/settings/breaks');
      final data = response.data is Map ? response.data['data'] : null;
      if (data is Map) {
        lunchPaid = '${data['is_lunch_paid']}'.toLowerCase() == 'true';
        minutes = int.tryParse('${data['standard_work_minutes']}') ?? 480;
      }
    } catch (_) {
      if (mounted) _showMessage('Failed to load settings.', false);
      return;
    }
    if (!mounted) return;

    final minutesController = TextEditingController(text: '$minutes');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Attendance settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lunch is paid'),
                value: lunchPaid,
                onChanged: (value) => setDialogState(() => lunchPaid = value),
              ),
              TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Standard work minutes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final value = int.tryParse(minutesController.text.trim());
                if (value == null || value <= 0 || value > 1440) {
                  _showMessage('Minutes must be between 1 and 1440.', false);
                  return;
                }
                try {
                  await ApiConfig.dio.put('/admin/attendance/settings/breaks', data: {
                    'is_lunch_paid': lunchPaid,
                    'standard_work_minutes': value,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) _showMessage('Settings updated.', true);
                } on DioException catch (e) {
                  if (mounted) _showMessage(_errorMessage(e, 'Failed to update settings.'), false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    minutesController.dispose();
  }

  void _showMessage(String message, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: color.withOpacity(.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(.15), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _timeCell(String label, dynamic value) {
    final text = value == null ? '--' : '${value}'.replaceFirst('T', ' ');
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 3),
          Text(text.length > 16 ? text.substring(11, 16) : text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    final rejected = status == 'Rejected';
    final color = rejected ? Colors.red : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(30)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _recordCard(Map<String, dynamic> item) {
    final id = int.tryParse('${item['attendance_id']}');
    if (id == null) return const SizedBox.shrink();
    final status = '${item['status'] ?? item['attendance_status'] ?? 'Submitted'}';
    final rejected = status == 'Rejected';
    final selected = _selectedIds.contains(id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey.shade200, width: selected ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: selected, onChanged: (v) => setState(() => v == true ? _selectedIds.add(id) : _selectedIds.remove(id))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item['full_name'] ?? 'Worker'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${item['site_name'] ?? 'Unknown site'}', style: TextStyle(color: Colors.grey.shade600)),
            ])),
            _statusChip(status),
          ]),
          const Divider(height: 22),
          Row(children: [
            _timeCell('Check-in', item['check_in_time']),
            const SizedBox(width: 10),
            _timeCell('Check-out', item['check_out_time']),
            const SizedBox(width: 10),
            _timeCell('Hours', item['total_working_hours'] ?? '--'),
          ]),
          if (rejected && item['admin_rejection_notes'] != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text('${item['admin_rejection_notes']}', style: TextStyle(color: Colors.red.shade800)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!rejected)
                OutlinedButton.icon(
                  onPressed: _working ? null : () => _reviewSelected([id], 'Approved'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
                ),
              OutlinedButton.icon(
                onPressed: _working ? null : () async {
                  final note = await _askRejectionReason();
                  if (note != null) await _reviewSelected([id], 'Rejected', note: note);
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'management') _showManagementLeaveDialog(id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'management', child: Text('Management leave hours')),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.more_horiz, size: 18),
                  label: const Text('More'),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _daySection(String date, List<Map<String, dynamic>> items) {
    final ids = _idsForDate(items);
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    final selected = ids.where(_selectedIds.contains).toList();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        title: Row(children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) => setState(() {
              if (value == true) {
                _selectedIds.addAll(ids);
              } else {
                _selectedIds.removeAll(ids);
              }
            }),
          ),
          Expanded(child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          Text('${items.length} records', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ]),
        subtitle: selected.isEmpty ? null : Padding(
          padding: const EdgeInsets.only(left: 58, bottom: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _working ? null : () => _reviewSelected(selected, 'Approved'),
              icon: const Icon(Icons.check, size: 18),
              label: Text('Approve ${selected.length}'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            ),
            FilledButton.icon(
              onPressed: _working ? null : () async {
                final note = await _askRejectionReason();
                if (note != null) await _reviewSelected(selected, 'Rejected', note: note);
              },
              icon: const Icon(Icons.close, size: 18),
              label: Text('Reject ${selected.length}'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            ),
          ]),
        ),
        children: [Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(children: items.map(_recordCard).toList()),
        )],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _grouped.values.expand((items) => items).toList();
    final pending = allItems.where((i) => '${i['status']}' == 'Submitted').length;
    final rejected = allItems.where((i) => '${i['status']}' == 'Rejected').length;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Admin Attendance Review',
        actions: [
          IconButton(onPressed: _showSettingsDialog, icon: const Icon(Icons.tune), tooltip: 'Settings'),
          IconButton(onPressed: _fetchData, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: _grouped.isEmpty
                  ? ListView(children: const [SizedBox(height: 220), Center(child: Text('No attendance records to review.'))])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                      children: [
                        LayoutBuilder(builder: (context, constraints) {
                          final cards = [
                            _summaryCard('Submitted', '$pending', Icons.pending_actions, Colors.orange),
                            _summaryCard('Rejected', '$rejected', Icons.warning_amber, Colors.red),
                            _summaryCard('Total records', '${allItems.length}', Icons.people_alt_outlined, Colors.indigo),
                          ];
                          return constraints.maxWidth < 650
                              ? Column(children: cards.map((card) => Padding(padding: const EdgeInsets.only(bottom: 8), child: card)).toList())
                              : Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1]), const SizedBox(width: 10), Expanded(child: cards[2])]);
                        }),
                        const SizedBox(height: 10),
                        ..._grouped.entries.map((entry) => _daySection(entry.key, entry.value)),
                      ],
                    ),
            ),
      bottomNavigationBar: _working
          ? const LinearProgressIndicator(minHeight: 3)
          : null,
    );
  }
}
