import 'package:flutter/material.dart';
import 'payroll_adjustments_screen.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import 'staff_absence_review_screen.dart';
import 'payroll_export_service.dart';
import '../widgets/monthly_report_card.dart';
import '../widgets/preliminary_report_card.dart'; // ← جديد
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

  // Monthly payroll is the default; a custom day range stays available.
  bool _monthlyMode = true;
  late DateTime _selectedMonth;

  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _monthStart(DateTime m) => DateTime(m.year, m.month, 1);
  DateTime _monthEnd(DateTime m) => DateTime(m.year, m.month + 1, 0);

  /// Months that have fully ended (newest first). A month whose last day is
  /// after today cannot be generated: its remaining days have no attendance.
  List<DateTime> get _availableMonths {
    final months = <DateTime>[];
    var cursor = DateTime(_today.year, _today.month, 1);
    if (_monthEnd(cursor).isAfter(_today)) {
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    for (var i = 0; i < 24; i++) {
      months.add(DateTime(cursor.year, cursor.month - i, 1));
    }
    return months;
  }

  void _applyMonth(DateTime month) {
    _selectedMonth = month;
    _startDateController.text = _ymd.format(_monthStart(month));
    _endDateController.text = _ymd.format(_monthEnd(month));
  }

  /// Working days the payroll counts: every day except Friday.
  int _workingDays(DateTime start, DateTime end) {
    var count = 0;
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday != DateTime.friday) count++;
    }
    return count;
  }

  bool _isFullCalendarMonth(DateTime start, DateTime end) =>
      start.day == 1 && start.year == end.year && start.month == end.month &&
      end.day == _monthEnd(start).day;

  @override
  void initState() {
    super.initState();
    _applyMonth(_availableMonths.first);
    _loadBatches();
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  bool _includeHistory = false;

  Future<void> _loadBatches() async {
    setState(() => _isLoadingBatches = true);
    try {
      final response = await ApiConfig.dio.get(
        '/staff-payroll/report',
        queryParameters: {if (_includeHistory) 'include_history': '1'},
      );
      final List all = (response.data is Map ? response.data['data'] : null) as List? ?? [];

      // Hide Superseded / Voided unless "Show history" is on
      // (also protects against a backend that still returns every version).
      final visible = _includeHistory
          ? all
          : all.where((b) {
              final s = (b['status'] ?? '').toString();
              return s != 'Superseded' && s != 'Voided';
            }).toList();

      if (!mounted) return;
      setState(() {
        _batches = visible;
        _isLoadingBatches = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBatches = false);
      _showSnack('Failed to load payroll batches', AppColors.danger);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    // A payroll period must already have ended, so future dates are not offered.
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isAfter(_today) ? current : _today,
      firstDate: DateTime(2023),
      lastDate: _today,
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {});
    }
  }

  /// Summary shown before anything is generated: what period, how many
  /// working days, and how missing attendance is treated.
  Future<bool> _confirmGeneration(DateTime start, DateTime end) async {
    final calendarDays = end.difference(start).inDays + 1;
    final workingDays = _workingDays(start, end);
    final fullMonth = _isFullCalendarMonth(start, end);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate staff payroll?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryLine(Icons.date_range, 'Period',
                  fullMonth
                      ? '${DateFormat('MMMM yyyy').format(start)} (${_ymd.format(start)} → ${_ymd.format(end)})'
                      : '${_ymd.format(start)} → ${_ymd.format(end)}'),
              _summaryLine(Icons.calendar_view_month, 'Days',
                  '$calendarDays calendar days · $workingDays working days (Fridays excluded)'),
              _summaryLine(Icons.category_outlined, 'Type', fullMonth ? 'Full month' : 'Custom range'),
              const SizedBox(height: 10),
              if (!fullMonth)
                _noteBox(
                  Colors.orange,
                  'This is not a full calendar month. Each salary is prorated to $workingDays working days '
                  'out of this range, and this range cannot be generated again unless the batch is voided.',
                ),
              _noteBox(
                AppColors.primary,
                'Only Approved attendance is paid. A working day with no approved record counts as an unpaid absence. '
                'Staff hired or terminated inside the period are paid only for the days they were employed.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _summaryLine(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            SizedBox(width: 56, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _noteBox(Color color, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: color is MaterialColor ? color.shade900 : color)),
      );

  /// Unresolved (Draft / Submitted / Rejected) attendance: says plainly that
  /// these days will be deducted, and scrolls when the list is long.
  Future<bool?> _confirmPendingDeduction(List pendingList, {required String continueLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${pendingList.length} day(s) not approved yet'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _noteBox(
                AppColors.danger,
                'If you continue, every day below is treated as an UNPAID ABSENCE and deducted from the salary. '
                'To pay them, cancel, approve the attendance first, then generate again.',
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pendingList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = pendingList[i];
                    final note = '${item['note'] ?? ''}'.trim();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['full_name'] ?? 'Staff'}'),
                      subtitle: Text(
                        '${item['record_date'] ?? ''}'
                        '${item['attendance_status'] != null ? ' · ${item['attendance_status']}' : ''}'
                        '${note.isNotEmpty ? '\nSupervisor: $note' : ''}',
                      ),
                      trailing: Text('${item['status'] ?? ''}',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(continueLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _generateBatch() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select the start and end dates', Colors.orange);
      return;
    }
    final start = DateTime.tryParse(_startDateController.text);
    final end = DateTime.tryParse(_endDateController.text);
    if (start == null || end == null || end.isBefore(start)) {
      _showSnack('The end date must be on or after the start date', Colors.orange);
      return;
    }
    if (end.isAfter(_today)) {
      _showSnack('This period has not ended yet (it ends ${_ymd.format(end)}). Generate it after that day.', Colors.orange);
      return;
    }
    if (!await _confirmGeneration(start, end)) return;

    setState(() => _isGenerating = true);
    try {
      final requestData = <String, dynamic>{
        'start_date': _startDateController.text,
        'end_date': _endDateController.text,
      };
      Future<Response<dynamic>> generate({required bool acknowledgePending}) {
        return ApiConfig.dio.post(
          '/staff-payroll/generate',
          data: {
            ...requestData,
            if (acknowledgePending) 'acknowledge_pending': true,
          },
        );
      }

      Response<dynamic> response;
      try {
        response = await generate(acknowledgePending: false);
      } on DioException catch (e) {
        final data = e.response?.data;
        if (e.response?.statusCode != 409 ||
            data is! Map ||
            data['code'] != 'PENDING_ATTENDANCE') {
          rethrow;
        }

        if (!mounted) return;
        final acknowledge = await _confirmPendingDeduction(
          data['pending_attendance'] as List? ?? const [],
          continueLabel: 'Deduct these days & generate',
        );
        if (acknowledge != true) return;
        response = await generate(acknowledgePending: true);
      }
      _showSnack(response.data['message'] ?? 'Payroll batch generated', Colors.green.shade700);
      if (_monthlyMode) {
        _applyMonth(_selectedMonth);
      } else {
        _startDateController.clear();
        _endDateController.clear();
      }
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to generate batch') : 'Failed to generate batch';
      _showSnack(msg, AppColors.danger);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }


  Future<void> _openAbsenceReview() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select the start and end dates first', Colors.orange);
      return;
    }
    final start = DateTime.tryParse(_startDateController.text);
    final end = DateTime.tryParse(_endDateController.text);
    if (start == null || end == null) {
      _showSnack('Invalid date range', Colors.orange);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffAbsenceReviewScreen(startDate: start, endDate: end),
      ),
    );
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

  Future<String?> _askReason(String title, String message, String confirm) async {
    final controller = TextEditingController();
    String? err;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'Reason (required, min. 5 characters)', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().length < 5) {
                  setD(() => err = 'Please enter a clear reason');
                  return;
                }
                Navigator.pop(ctx, controller.text.trim());
              },
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return reason;
  }

  /// D-03: atomic correction. The server validates, generates the new version,
  /// verifies it and only then marks this batch Superseded (one transaction).
  Future<void> _supersede(int batchId, {String? reason, bool acknowledgePending = false}) async {
    reason ??= await _askReason(
      'Correct (supersede) batch #$batchId',
      'A new version is generated for the same period from the current approved attendance. '
          'This batch is kept as "Superseded" for audit. Paid batches can never be superseded.',
      'Generate new version',
    );
    if (reason == null) return;
    try {
      final res = await ApiConfig.dio.post('/staff-payroll/batch/$batchId/new-version', data: {
        'reason': reason,
        if (acknowledgePending) 'acknowledge_pending': true,
      });
      _showSnack((res.data['message'] ?? 'New version generated').toString(), Colors.green.shade700);
      _loadBatches();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'PENDING_ATTENDANCE' && !acknowledgePending) {
        if (!mounted) return;
        final ok = await _confirmPendingDeduction(
          data['pending_attendance'] as List? ?? const [],
          continueLabel: 'Deduct these days & create version',
        );
        if (ok == true) await _supersede(batchId, reason: reason, acknowledgePending: true);
        return;
      }
      final msg = data is Map ? (data['message'] ?? 'Failed to supersede') : 'Failed to supersede';
      _showSnack(msg.toString(), AppColors.danger);
    }
  }

  /// D-03: void a Generated, not finalized batch (kept for audit, nothing deleted).
  Future<void> _voidBatch(int batchId) async {
    final reason = await _askReason(
      'Void batch #$batchId',
      'Use only for a batch generated by mistake. It stays in the history as "Voided" and the period can be generated again.',
      'Void batch',
    );
    if (reason == null) return;
    try {
      final res = await ApiConfig.dio.patch('/staff-payroll/batch/$batchId/void', data: {'reason': reason});
      _showSnack((res.data['message'] ?? 'Batch voided').toString(), Colors.blueGrey);
      _loadBatches();
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to void') : 'Failed to void';
      _showSnack(msg.toString(), AppColors.danger);
    }
  }

Future<void> _exportBatchExcel(int batchId) async {
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      '/staff-payroll/batch/$batchId/export.xlsx',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty Excel response');
    await PayrollExportService.exportBytes(
      bytes,
      'staff_payroll_batch_$batchId.xlsx',
    );
    if (mounted) _showSnack('Excel report is ready.', Colors.green);
  } on DioException catch (e) {
    final data = e.response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Failed to export Excel report.';
    _showSnack(message, AppColors.danger);
  } catch (_) {
    _showSnack('Failed to export Excel report.', AppColors.danger);
  }
}
Future<void> _exportBatchPdf(int batchId) async {
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      '/staff-payroll/batch/$batchId/export.pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty PDF response');
    await PayrollExportService.exportBytes(
      bytes,
      'staff_payroll_batch_$batchId.pdf',
    );
    if (mounted) _showSnack('PDF report is ready.', Colors.green);
  } on DioException catch (e) {
    final data = e.response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Failed to export PDF report.';
    _showSnack(message, AppColors.danger);
  } catch (_) {
    _showSnack('Failed to export PDF report.', AppColors.danger);
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
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      tooltip: 'Export PDF Report',
                      onPressed: () => _exportBatchPdf(batch['staff_payroll_batch_id']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.table_view, color: AppColors.danger),
                      tooltip: 'Export Excel Report',
                      onPressed: () => _exportBatchExcel(batch['staff_payroll_batch_id']),
                    ),
                    const SizedBox(width: 4),
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
                                      Text('${(double.tryParse(s['net_salary'].toString()) ?? 0).toStringAsFixed(0)} USD',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                    ],
                                  ),
                                  Text('ID: ${s['staff_unique_id'] ?? ''} • Position: ${s['position'] ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  // Retro pay: adjustments for earlier paid months (already in the net above).
                                  for (final a in (s['adjustments'] is List ? s['adjustments'] as List : const []))
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(top: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xffeef3ff), borderRadius: BorderRadius.circular(8)),
                                      child: Text(
                                        'Adjustment ${a['origin_date'] != null ? 'for ${a['origin_date']}' : '(manual)'}: '
                                        '${(num.tryParse('${a['amount']}') ?? 0) > 0 ? '+' : ''}${a['amount']} ${a['currency'] ?? ''} — ${a['reason'] ?? ''}',
                                        style: const TextStyle(fontSize: 12, color: Color(0xff1a2a6c)),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 14, runSpacing: 4, children: [
                                    Text('Base salary: ${s['prorated_base_salary'] ?? s['monthly_salary_snapshot']}', style: const TextStyle(fontSize: 12)),
                                    Text('Working days: ${s['working_days_in_period']}', style: const TextStyle(fontSize: 12)),
                                    Text('Present: ${s['present_days']}', style: const TextStyle(fontSize: 12, color: Colors.green)),
                                    Text('Paid leave: ${s['paid_leave_days']}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                                    Text('Mgmt-paid absence: ${s['management_paid_days'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.teal)),
                                    Text('Unpaid absences: ${s['unpaid_absence_days']}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                                  ]),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                                    child: Wrap(spacing: 14, runSpacing: 4, children: [
                                      Text('Required hrs: ${s['required_hours'] ?? '-'}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      Text('OT earned: ${s['ot_earned_hours'] ?? 0}h',
                                          style: const TextStyle(fontSize: 12, color: Colors.blue)),
                                      Text('OT used: ${s['ot_used_hours'] ?? 0}h',
                                          style: const TextStyle(fontSize: 12, color: Colors.orange)),
                                      Text('OT remaining: ${s['ot_remaining_hours'] ?? 0}h',
                                          style: const TextStyle(fontSize: 12, color: Colors.green)),
                                      Text(
                                        'Shortage: ${s['shortage_hours'] ?? 0}h',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: (double.tryParse('${s['shortage_hours'] ?? 0}') ?? 0) > 0 ? Colors.red : Colors.grey,
                                        ),
                                      ),
                                      if ((double.tryParse('${s['salary_deduction_amount'] ?? 0}') ?? 0) > 0)
                                        Text(
                                          'Deduction: -${s['salary_deduction_amount']}',
                                          style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                                        ),
                                    ]),
                                  ),
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
                    Expanded(child: Text('Total: ${batch['total_amount']} ${batch['currency'] ?? 'USD'} (${batch['total_staff']} staff)', style: const TextStyle(fontWeight: FontWeight.bold))),
                    if (status == 'Generated' && !isFinalized) ...[
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _voidBatch(batch['staff_payroll_batch_id']);
                        },
                        child: const Text('Void', style: TextStyle(color: AppColors.danger)),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _finalizeBatch(batch['staff_payroll_batch_id']);
                        },
                        icon: const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                        label: const Text('Finalize', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                      ),
                    ],
                    if (status == 'Generated' && isFinalized) ...[
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _supersede(batch['staff_payroll_batch_id']);
                        },
                        child: const Text('Correct (supersede)'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _markPaid(batch['staff_payroll_batch_id']);
                        },
                        icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                        label: const Text('Mark Paid', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
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
      appBar: CustomAppBar(
        title: 'Staff Payroll',
        actions: [
          IconButton(
            icon: const Icon(Icons.price_change_outlined),
            tooltip: 'Payroll adjustments',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PayrollAdjustmentsScreen(initialType: 'Staff')),
            ),
          ),
        ],
      ),
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
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, icon: Icon(Icons.calendar_month), label: Text('Monthly (recommended)')),
                            ButtonSegment(value: false, icon: Icon(Icons.date_range), label: Text('Custom range')),
                          ],
                          selected: {_monthlyMode},
                          onSelectionChanged: _isGenerating
                              ? null
                              : (s) => setState(() {
                                    _monthlyMode = s.first;
                                    if (_monthlyMode) {
                                      _applyMonth(_selectedMonth);
                                    } else {
                                      _startDateController.clear();
                                      _endDateController.clear();
                                    }
                                  }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_monthlyMode) ...[
                        DropdownButtonFormField<DateTime>(
                          value: _availableMonths.firstWhere(
                            (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
                            orElse: () => _availableMonths.first,
                          ),
                          decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
                          items: _availableMonths
                              .map((m) => DropdownMenuItem(value: m, child: Text(DateFormat('MMMM yyyy').format(m))))
                              .toList(),
                          onChanged: _isGenerating ? null : (m) => setState(() => _applyMonth(m!)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_startDateController.text} → ${_endDateController.text} · '
                          '${_workingDays(_monthStart(_selectedMonth), _monthEnd(_selectedMonth))} working days (Fridays excluded). '
                          'Only months that have fully ended are listed.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _startDateController, readOnly: true, onTap: () => _pickDate(_startDateController), decoration: const InputDecoration(labelText: 'Start Date', border: OutlineInputBorder()))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: _endDateController, readOnly: true, onTap: () => _pickDate(_endDateController), decoration: const InputDecoration(labelText: 'End Date', border: OutlineInputBorder()))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _noteBox(
                          Colors.orange,
                          'Custom ranges are for special cases. Salaries are prorated to the working days of the range, '
                          'and a range that overlaps an existing batch cannot be generated.',
                        ),
                      ],
                                          const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isGenerating ? null : _openAbsenceReview,
                          icon: const Icon(Icons.event_busy, size: 18),
                          label: const Text('Review Absences (Management-Paid Leave)'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generateBatch,
                          icon: _isGenerating
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.bolt, color: Colors.white),
                          label: Text(
                            _isGenerating
                                ? 'Generating...'
                                : (_monthlyMode
                                    ? 'Generate ${DateFormat('MMMM yyyy').format(_selectedMonth)} Payroll'
                                    : 'Generate Batch'),
                            style: const TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                            const SizedBox(height: 16),
              const MonthlyReportCard(
                title: 'Monthly Staff Hours & Payroll Report',
                subtitle: 'Staff / employees only. Daily hours, totals and stored staff payroll values for the selected month or day range.',
                endpoint: '/staff-payroll/monthly-report.xlsx',
                pdfEndpoint: '/staff-payroll/monthly-report.pdf',
                filePrefix: 'staff_hours_payroll',
              ),
              const SizedBox(height: 16),
              const PreliminaryReportCard(), // ← جديد: كشف أولي غير رسمي قبل الـ approve
              const SizedBox(height: 20),
              Row(children: [
  const Text('Payroll History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
  const Spacer(),
  FilterChip(
    visualDensity: VisualDensity.compact,
    label: const Text('Show history'),
    selected: _includeHistory,
    onSelected: (v) {
      setState(() => _includeHistory = v);
      _loadBatches();
    },
  ),
]),
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
      leading: CircleAvatar(
        backgroundColor: (isPaid ? Colors.green : Colors.orange).withOpacity(0.15),
        child: Icon(Icons.badge, color: isPaid ? Colors.green : AppColors.primary),
      ),
      title: Text('Batch #${b['staff_payroll_batch_id']}'),
      subtitle: Text('${_fmtDate(b['start_date'])} → ${_fmtDate(b['end_date'])} • ${b['total_staff']} staff • ${b['total_amount']} USD'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
            tooltip: 'Export PDF Report',
            onPressed: () => _exportBatchPdf(b['staff_payroll_batch_id']),
          ),
          IconButton(
            icon: const Icon(Icons.table_view, color: AppColors.danger, size: 20),
            tooltip: 'Export Excel',
            onPressed: () => _exportBatchExcel(b['staff_payroll_batch_id']),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isPaid ? Colors.green : Colors.orange).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              b['status'] ?? '',
              style: TextStyle(
                color: isPaid ? Colors.green : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
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
