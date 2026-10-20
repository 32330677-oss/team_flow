// lib/screens/staff_supervisor_assignment_screen.dart
//
// Assign/unassign a Staff Supervisor to a staff member, and show the
// assignment history. Separate from workers' site-assignment screens.

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';
import '../widgets/help_tip.dart';

class StaffSupervisorAssignmentScreen extends StatefulWidget {
  final Map<String, dynamic> staff;

  const StaffSupervisorAssignmentScreen({super.key, required this.staff});

  @override
  State<StaffSupervisorAssignmentScreen> createState() => _StaffSupervisorAssignmentScreenState();
}

class _StaffSupervisorAssignmentScreenState extends State<StaffSupervisorAssignmentScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  bool _isLoading = true;
  List<dynamic> _history = [];
  List<dynamic> _staffSupervisors = [];

  int get _staffId => widget.staff['staff_id'] as int;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/staff/$_staffId/supervisor-assignments'),
        ApiConfig.dio.get('/users/supervisors', queryParameters: {'role': 'StaffSupervisor'}),
      ]);
      setState(() {
        _history = results[0].data['data'] ?? [];
        _staffSupervisors = (results[1].data['data'] as List? ?? [])
            .where((s) => s['status'] == 'Active')
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Failed to load supervisor assignment data', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openAssignDialog() async {
    if (_staffSupervisors.isEmpty) {
      _showSnack('No active Staff Supervisors available. Create one first.', Colors.orange);
      return;
    }
    int? selectedSupervisorId;
    final dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign Staff Supervisor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedSupervisorId,
                  decoration: const InputDecoration(labelText: 'Staff Supervisor', border: OutlineInputBorder()),
                  items: _staffSupervisors
                      .map<DropdownMenuItem<int>>((s) => DropdownMenuItem(
                            value: s['user_id'] as int,
                            child: Text(s['full_name'] ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSupervisorId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Effective Date', border: OutlineInputBorder()),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      dateController.text = picked.toIso8601String().split('T')[0];
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selectedSupervisorId == null) {
                  _showSnack('Please select a Staff Supervisor.', Colors.orange);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedSupervisorId == null) return;

    try {
      await ApiConfig.dio.post('/staff/$_staffId/supervisor-assignments', data: {
        'supervisor_user_id': selectedSupervisorId,
        'assigned_date': dateController.text,
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      });
      if (!mounted) return;
      _showSnack('Staff Supervisor assigned successfully', Colors.green.shade700);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to assign supervisor') : 'Failed to assign supervisor';
      _showSnack(msg, Colors.red);
    }
  }

  Future<void> _unassignCurrent() async {
    final lastDay = await pickLastAssignedDay(
      context,
      title: 'Unassign Staff Supervisor',
      message: 'The Staff Supervisor stops supervising this staff member after the last day.',
    );
    if (lastDay == null) return;

    try {
      await ApiConfig.dio.delete('/staff/$_staffId/supervisor-assignments/current', data: {'last_day': lastDay});
      if (!mounted) return;
      _showSnack('Staff Supervisor unassigned', Colors.blue);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to unassign') : 'Failed to unassign';
      _showSnack(msg, Colors.red);
    }
  }

  /// Correct the FIRST day of one assignment (a date entered wrong).
  /// The server checks the hire date, the last day and overlaps.
  Future<void> _changeStartDate(Map a) async {
    final id = a['staff_assignment_id'];
    final current = '${a['assigned_date'] ?? ''}'.split('T')[0];
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'New FIRST day under ${a['supervisor_name'] ?? 'this supervisor'}',
    );
    if (picked == null || !mounted) return;
    final newStart = picked.toIso8601String().split('T')[0];
    if (newStart == current) return;

    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change start date'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a['supervisor_name'] ?? ''}: $current  →  $newStart',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'The supervisor records this staff member\'s attendance from $newStart. '
                'Attendance and payroll are not changed.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtl,
                decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reasonCtl.text.trim().length < 3) {
                _showSnack('A reason is required.', Colors.orange);
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final reason = reasonCtl.text.trim();
    reasonCtl.dispose();
    if (ok != true) return;

    try {
      final r = await ApiConfig.dio.patch(
        '/staff/$_staffId/supervisor-assignments/$id/start-date',
        data: {'new_start_date': newStart, 'reason': reason},
      );
      if (!mounted) return;
      _showSnack(r.data is Map ? (r.data['message'] ?? 'Start date changed') : 'Start date changed', Colors.green.shade700);
      _loadAll();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to change the start date') : 'Failed to change the start date';
      _showSnack(msg, Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOpenAssignment = _history.any((a) => a['unassigned_date'] == null);
    final current = hasOpenAssignment
        ? _history.firstWhere((a) => a['unassigned_date'] == null)
        : null;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(title: '${widget.staff['full_name'] ?? 'Staff'} — Supervisor'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.supervisor_account, color: primaryColor),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current != null ? 'Current: ${current['supervisor_name'] ?? ''}' : 'No supervisor assigned',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (current != null)
                                  Text(
                                    'Since ${(current['assigned_date'] ?? '').toString().split('T')[0]}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          if (hasOpenAssignment)
                            TextButton.icon(
                              onPressed: _unassignCurrent,
                              icon: const Icon(Icons.link_off, size: 16, color: Colors.orange),
                              label: const Text('Unassign', style: TextStyle(color: Colors.orange)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openAssignDialog,
                      icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                      label: Text(
                        hasOpenAssignment ? 'Reassign' : 'Assign Staff Supervisor',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Assignment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  AppDataTableCard(
                    title: 'History',
                    icon: Icons.history,
                    accentColor: primaryColor,
                    emptyMessage: 'No supervisor assignments recorded yet.',
                    columns: const [
                      DataColumn(label: Text('Supervisor')),
                      DataColumn(label: Text('From')),
                      DataColumn(label: Text('To')),
                      DataColumn(label: Text('Notes')),
                      DataColumn(label: Text('')),
                    ],
                    rows: _history.map((a) {
                      final from = '${a['assigned_date'] ?? ''}'.split('T')[0];
                      final to = a['unassigned_date'] == null ? null : '${a['unassigned_date']}'.split('T')[0];
                      // A cancelled row (last day before first day) has no day to move.
                      final cancelled = to != null && to.compareTo(from) < 0;
                      return DataRow(cells: [
                        DataCell(Text(a['supervisor_name'] ?? '')),
                        DataCell(Text(from)),
                        DataCell(Text(to ?? 'Present')),
                        DataCell(Text(a['notes'] ?? '-')),
                        DataCell(cancelled
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                                tooltip: 'Change start date',
                                onPressed: () => _changeStartDate(a),
                              )),
                      ]);
                    }).toList(),
                  ),
                ],
              ),
            ),
    );
  }
}