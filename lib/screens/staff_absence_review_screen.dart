import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class StaffAbsenceReviewScreen extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;

  const StaffAbsenceReviewScreen({
    super.key,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<StaffAbsenceReviewScreen> createState() => _StaffAbsenceReviewScreenState();
}

class _StaffAbsenceReviewScreenState extends State<StaffAbsenceReviewScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<dynamic> _staffAbsences = [];
  final Set<int> _selectedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _fetchAbsences();
  }

  String get _startStr => DateFormat('yyyy-MM-dd').format(widget.startDate);
  String get _endStr => DateFormat('yyyy-MM-dd').format(widget.endDate);

  Future<void> _fetchAbsences() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(
        '/staff-attendance/admin/absences',
        queryParameters: {'start_date': _startStr, 'end_date': _endStr},
      );
      setState(() {
        _staffAbsences = response.data['data'] ?? [];
        _selectedIds.clear();
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to load absences')
          : 'Failed to load absences';
      _showSnack(msg, Colors.red);
    }
  }

  Future<void> _markSelectedPaid() async {
    if (_selectedIds.isEmpty) {
      _showSnack('Please select at least one absence day.', Colors.orange);
      return;
    }
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Grant Management-Paid Leave (${_selectedIds.length})'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            hintText: 'Why is management paying for this absence?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiConfig.dio.post('/staff-attendance/admin/absences/mark-paid', data: {
        'staff_attendance_ids': _selectedIds.toList(),
        'reason': reason,
      });
      _showSnack(response.data['message'] ?? 'Updated successfully', Colors.green.shade700);
      await _fetchAbsences();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to update absences')
          : 'Failed to update absences';
      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _unmarkSelected() async {
    if (_selectedIds.isEmpty) {
      _showSnack('Please select at least one absence day.', Colors.orange);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final response = await ApiConfig.dio.post('/staff-attendance/admin/absences/unmark-paid', data: {
        'staff_attendance_ids': _selectedIds.toList(),
      });
      _showSnack(response.data['message'] ?? 'Updated successfully', Colors.blue);
      await _fetchAbsences();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to update absences')
          : 'Failed to update absences';
      _showSnack(msg, Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: CustomAppBar(
        title: 'Absences: $_startStr → $_endStr',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAbsences),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staffAbsences.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('No absences in this period 🎉', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _staffAbsences.length,
                  itemBuilder: (context, index) {
                    final staff = Map<String, dynamic>.from(_staffAbsences[index]);
                    final absences = (staff['absences'] as List).cast<Map>();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ExpansionTile(
                        title: Text(staff['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${staff['staff_unique_id'] ?? ''} • Absent ${staff['total_absences']} day(s) — '
                          '${staff['paid_count']} paid, ${staff['unpaid_count']} unpaid',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        children: absences.map((a) {
                          final id = a['staff_attendance_id'] as int;
                          final isPaid = a['is_management_paid_absence'] == true;
                          final date = (a['record_date'] ?? '').toString().split('T')[0];
                          final selected = _selectedIds.contains(id);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selectedIds.add(id);
                              } else {
                                _selectedIds.remove(id);
                              }
                            }),
                            title: Text(date),
                            subtitle: isPaid
                                ? Text(
                                    'Management-paid${a['management_paid_reason'] != null ? ': ${a['management_paid_reason']}' : ''}',
                                    style: TextStyle(color: Colors.green.shade700, fontSize: 11.5, fontWeight: FontWeight.w600),
                                  )
                                : const Text('Unpaid absence', style: TextStyle(fontSize: 11.5, color: Colors.red)),
                            secondary: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isPaid ? Colors.green : Colors.red).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isPaid ? 'Paid' : 'Unpaid',
                                style: TextStyle(
                                  color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _staffAbsences.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _unmarkSelected,
                        icon: const Icon(Icons.money_off, size: 18),
                        label: Text('Unmark (${_selectedIds.length})'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _markSelectedPaid,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.paid, size: 18, color: Colors.white),
                        label: Text('Mark Paid (${_selectedIds.length})', style: const TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}