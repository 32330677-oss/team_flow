import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1A2A6C); // اللون الرئيسي الأزرق الغامق
  static const Color danger = Colors.red;          // لون التنبيهات والأخطاء
  static const Color success = Colors.green;       // لون النجاح
  static const Color warning = Colors.orange;      // لون التحذير
}
class StaffPayrollScreen extends StatefulWidget {
  const StaffPayrollScreen({super.key});

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> {
  bool _isLoading = false;
  bool _isSaving = false;
  List<dynamic> _draftPayrollItems = [];
  List<dynamic> _existingBatches = [];
  bool _isLoadingBatches = true;

  // Date range controllers for payroll batch period
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
      final response = await ApiConfig.dio.get('/staff-payroll/batches');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _existingBatches = response.data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error loading batches: $e');
    } finally {
      setState(() => _isLoadingBatches = false);
    }
  }

  Future<void> _previewPayrollDraft() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnackBar('Please select both start and end dates first', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.post('/staff-payroll/preview-batch', data: {
        'start_date': _startDateController.text.trim(),
        'end_date': _endDateController.text.trim(),
      });

      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _draftPayrollItems = data['items'] ?? data['data'] ?? [];
        });
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to load preview') : 'Failed to load preview';
      _showSnackBar(msg, AppColors.danger);
    } catch (e) {
      _showSnackBar('Network error: $e', AppColors.danger);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePayrollBatch() async {
    if (_draftPayrollItems.isEmpty) {
      _showSnackBar('No staff records found in the draft to save', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await ApiConfig.dio.post('/staff-payroll/generate-batch', data: {
        'start_date': _startDateController.text.trim(),
        'end_date': _endDateController.text.trim(),
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnackBar('Payroll batch successfully saved!', Colors.green.shade700);
        setState(() {
          _draftPayrollItems = [];
          _startDateController.clear();
          _endDateController.clear();
        });
        _loadBatches();
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to save batch') : 'Failed to save batch';
      _showSnackBar(msg, AppColors.danger);
    } catch (e) {
      _showSnackBar('Network error: $e', AppColors.danger);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<String?> _promptForReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supersede & Correct Reason'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter reason for correction/superseding...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Proceed', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBatchDetailsSheet(Map batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isFinalized = batch['is_finalized'] == 1 || batch['is_finalized'] == true;
          final status = batch['status']?.toString() ?? 'Generated';

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Batch #${batch['staff_payroll_batch_id']} Details',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Text('Period: ${batch['start_date']} to ${batch['end_date']}',
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                Text('Status: $status | Finalized: ${isFinalized ? "Yes" : "No"}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 15),
                const Text('Financial Actions:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _financeActions(batch, () {
                  _loadBatches();
                  Navigator.pop(context);
                }),
                const SizedBox(height: 20),
                const Text('Batch Items Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: (batch['items'] as List?)?.length ?? 0,
                    itemBuilder: (context, index) {
                      final item = batch['items'][index];
                      return ListTile(
                        dense: true,
                        title: Text(item['full_name'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Net Salary: ${item['net_salary']}'),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _financeActions(Map batch, VoidCallback onChanged) {
    final isFinalized = batch['is_finalized'] == 1 || batch['is_finalized'] == true;
    final status = batch['status']?.toString() ?? 'Generated';

    if (status == 'Superseded') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
        child: const Text('This batch has been superseded by a newer version.',
            style: TextStyle(fontWeight: FontWeight.w600)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!isFinalized)
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await ApiConfig.dio.patch('/staff-payroll/batch/${batch['staff_payroll_batch_id']}/finalize');
                onChanged();
              } on DioException catch (e) {
                final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to finalize') : 'Failed to finalize';
                _showSnackBar(msg, AppColors.danger);
              }
            },
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Finalize'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        if (isFinalized && status != 'Paid')
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await ApiConfig.dio.patch('/staff-payroll/batch/${batch['staff_payroll_batch_id']}/mark-paid');
                onChanged();
              } on DioException catch (e) {
                final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to mark paid') : 'Failed to mark paid';
                _showSnackBar(msg, AppColors.danger);
              }
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Mark Paid'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final reason = await _promptForReason(context);
            if (reason == null || reason.trim().isEmpty) return;
            try {
              final res = await ApiConfig.dio.post(
                '/staff-payroll/batch/${batch['staff_payroll_batch_id']}/new-version',
                data: {'reason': reason},
              );
              // res.data['next_version_params'] has start_date/end_date/version_number/supersedes_batch_id
              if (res.data != null && res.data['next_version_params'] != null) {
                final params = res.data['next_version_params'];
                setState(() {
                  _startDateController.text = params['start_date'] ?? '';
                  _endDateController.text = params['end_date'] ?? '';
                });
              }
              onChanged();
            } on DioException catch (e) {
              final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to supersede') : 'Failed to supersede';
              _showSnackBar(msg, AppColors.danger);
            }
          },
          icon: const Icon(Icons.difference_outlined, size: 18, color: Colors.deepOrange),
          label: const Text('Supersede & Correct', style: TextStyle(color: Colors.deepOrange)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,##0', 'en_US');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: const CustomAppBar(title: 'Staff Payroll Management'),
        body: Column(
          children: [
            const Material(
              color: Colors.white,
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: 'Generate & Preview', icon: Icon(Icons.playlist_add_check)),
                  Tab(text: 'Existing Batches', icon: Icon(Icons.history)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Generate & Preview
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _startDateController,
                                    decoration: const InputDecoration(
                                      labelText: 'Start Date (YYYY-MM-DD)',
                                      prefixIcon: Icon(Icons.date_range),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _endDateController,
                                    decoration: const InputDecoration(
                                      labelText: 'End Date (YYYY-MM-DD)',
                                      prefixIcon: Icon(Icons.date_range),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: _isLoading ? null : _previewPayrollDraft,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Text('Preview'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Payroll Draft Breakdown:',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _draftPayrollItems.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Select a date period and click "Preview" to view staff calculations.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _draftPayrollItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _draftPayrollItems[index];
                                    final workerName = item['full_name'] ?? item['worker_name'] ?? 'Unknown Staff';
                                    final position = item['position'] ?? 'Staff Member';
                                    final presentDays = item['present_days'] ?? item['days_worked'] ?? 0;
                                    final netSalary = double.tryParse(item['net_salary'].toString()) ?? 0.0;

                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      elevation: 2,
                                      child: ListTile(
                                        title: Text(workerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text('Position: $position | Present Days: $presentDays'),
                                        trailing: Text(
                                          '${currencyFormat.format(netSalary)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (_draftPayrollItems.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _isSaving ? null : _savePayrollBatch,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: const Text(
                              'Save Payroll Batch to Database',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Tab 2: Existing Batches History
                  _isLoadingBatches
                      ? const Center(child: CircularProgressIndicator())
                      : // بالسطر الصحيح:
_existingBatches.isEmpty
    ? const Center(child: Text('No payroll batches recorded yet.'))
    : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _existingBatches.length,
        itemBuilder: (context, index) {
          final batch = _existingBatches[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text('Batch #${batch['staff_payroll_batch_id']} (${batch['status']})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Period: ${batch['start_date']} to ${batch['end_date']}'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showBatchDetailsSheet(batch),
            ),
          );
        },
      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}