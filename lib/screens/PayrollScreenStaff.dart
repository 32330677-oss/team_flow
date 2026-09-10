import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

class AppColors {
  static const Color primary = Color(0xFF1A2A6C);
  static const Color danger = Colors.red;
  static const Color success = Colors.green;
  static const Color warning = Colors.orange;
}

class StaffPayrollScreen extends StatefulWidget {
  const StaffPayrollScreen({super.key});

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> {
  bool _isGenerating = false;
  bool _isLoadingBatches = true;
  List<dynamic> _batches = [];

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadBatches() async {
    setState(() => _isLoadingBatches = true);
    try {
      final response = await ApiConfig.dio.get('/staff-payroll/report');
      setState(() {
        _batches = response.data['data'] ?? [];
        _isLoadingBatches = false;
      });
    } catch (e) {
      setState(() => _isLoadingBatches = false);
      _showSnack('Failed to load payroll batches', AppColors.danger);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(2035));
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {});
    }
  }

  Future<void> _generateBatch() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select the start and end dates', Colors.orange);
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final response = await ApiConfig.dio.post('/staff-payroll/generate', data: {
        'start_date': _startDateController.text,
        'end_date': _endDateController.text,
      });
      _showSnack(response.data['message'] ?? 'Payroll batch generated', Colors.green.shade700);
      _startDateController.clear();
      _endDateController.clear();
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to generate batch') : 'Failed to generate batch';
      _showSnack(msg, AppColors.danger);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _openBatchDetails(int batchId) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final response = await ApiConfig.dio.get('/staff-payroll/batch/$batchId');
      if (!mounted) return;
      Navigator.pop(context);
      _showBatchDetailsSheet(response.data['batch'], response.data['staff'] ?? []);
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnack('Failed to load batch details', AppColors.danger);
    }
  }

  Future<void> _finalizeBatch(int batchId) async {
    try {
      await ApiConfig.dio.patch('/staff-payroll/batch/$batchId/finalize');
      _showSnack('Batch finalized', Colors.indigo);
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to finalize') : 'Failed to finalize';
      _showSnack(msg, AppColors.danger);
    }
  }

  Future<void> _markPaid(int batchId) async {
    try {
      await ApiConfig.dio.patch('/staff-payroll/batch/$batchId/mark-paid');
      _showSnack('Batch marked as paid', Colors.green.shade700);
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to mark paid') : 'Failed to mark paid';
      _showSnack(msg, AppColors.danger);
    }
  }

  Future<void> _supersede(int batchId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supersede & Correct'),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Reason for correction...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Proceed')),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      final res = await ApiConfig.dio.post('/staff-payroll/batch/$batchId/new-version', data: {'reason': reason});
      final params = res.data['next_version_params'];
      if (params != null) {
        _startDateController.text = params['start_date'] ?? '';
        _endDateController.text = params['end_date'] ?? '';
      }
      _showSnack('Batch superseded. Generate the new version now.', Colors.deepOrange);
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to supersede') : 'Failed to supersede';
      _showSnack(msg, AppColors.danger);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  String _fmtDate(dynamic v) => v == null ? '' : v.toString().split('T')[0];

  void _showBatchDetailsSheet(Map batch, List staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final isFinalized = batch['is_finalized'] == 1 || batch['is_finalized'] == true;
          final status = batch['status']?.toString() ?? 'Generated';
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Image.asset('assets/images/logo.png', width: 40, height: 40, errorBuilder: (c, e, s) => const Icon(Icons.business, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Staff Payroll Batch #${batch['staff_payroll_batch_id']} (v${batch['version_number'] ?? 1})',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          Text('Period: ${_fmtDate(batch['start_date'])} to ${_fmtDate(batch['end_date'])}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: status == 'Paid' ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: TextStyle(color: status == 'Paid' ? Colors.green : Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: staff.isEmpty
                    ? const Center(child: Text('No staff in this batch'))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: staff.length,
                        itemBuilder: (context, index) {
                          final s = Map<String, dynamic>.from(staff[index]);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(s['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                      Text('${(double.tryParse(s['net_salary'].toString()) ?? 0).toStringAsFixed(0)} ل.س',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                    ],
                                  ),
                                  Text('ID: ${s['staff_unique_id'] ?? ''} • Position: ${s['position'] ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 14, runSpacing: 4, children: [
                                    Text('Base salary: ${s['monthly_salary_snapshot']}', style: const TextStyle(fontSize: 12)),
                                    Text('Working days: ${s['working_days_in_period']}', style: const TextStyle(fontSize: 12)),
                                    Text('Present: ${s['present_days']}', style: const TextStyle(fontSize: 12, color: Colors.green)),
                                    Text('Paid leave: ${s['paid_leave_days']}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                                    Text('Absences: ${s['unpaid_absence_days']}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                                  ]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  children: [
                    Expanded(child: Text('Total: ${batch['total_amount']} ل.س (${batch['total_staff']} staff)', style: const TextStyle(fontWeight: FontWeight.bold))),
                    if (status != 'Paid' && status != 'Superseded') ...[
                      if (!isFinalized)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _finalizeBatch(batch['staff_payroll_batch_id']);
                          },
                          icon: const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                          label: const Text('Finalize', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _markPaid(batch['staff_payroll_batch_id']);
                          },
                          icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                          label: const Text('Mark Paid', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _supersede(batch['staff_payroll_batch_id']);
                        },
                        child: const Text('Supersede'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(title: 'Staff Payroll'),
      body: RefreshIndicator(
        onRefresh: _loadBatches,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Generate Staff Payroll', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _startDateController, readOnly: true, onTap: () => _pickDate(_startDateController), decoration: const InputDecoration(labelText: 'Start Date', border: OutlineInputBorder()))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: _endDateController, readOnly: true, onTap: () => _pickDate(_endDateController), decoration: const InputDecoration(labelText: 'End Date', border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generateBatch,
                          icon: _isGenerating
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.bolt, color: Colors.white),
                          label: Text(_isGenerating ? 'Generating...' : 'Generate Batch', style: const TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Payroll History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(height: 10),
              _isLoadingBatches
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
                  : _batches.isEmpty
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No payroll batches yet')))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _batches.length,
                          itemBuilder: (context, index) {
                            final b = _batches[index];
                            final isPaid = (b['status'] ?? '') == 'Paid';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: (isPaid ? Colors.green : Colors.orange).withOpacity(0.15), child: Icon(Icons.badge, color: isPaid ? Colors.green : AppColors.primary)),
                                title: Text('Batch #${b['staff_payroll_batch_id']}'),
                                subtitle: Text('${_fmtDate(b['start_date'])} → ${_fmtDate(b['end_date'])} • ${b['total_staff']} staff • ${b['total_amount']} ل.س'),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: (isPaid ? Colors.green : Colors.orange).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                  child: Text(b['status'] ?? '', style: TextStyle(color: isPaid ? Colors.green : Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                                onTap: () => _openBatchDetails(b['staff_payroll_batch_id']),
                              ),
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }
}