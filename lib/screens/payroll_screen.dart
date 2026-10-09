// payroll_screen.dart
import 'package:flutter/material.dart';
import 'payroll_adjustments_screen.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'payroll_export_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/monthly_report_card.dart';
import '../widgets/help_tip.dart';
String formatSyp(dynamic value) {
  final amount = double.tryParse(value?.toString() ?? '0') ?? 0;
  return '${NumberFormat('#,##0', 'en_US').format(amount)} ل.س';
}

/// D-10: each batch carries its own currency. Worker batches are SYP.
String formatMoney(dynamic value, dynamic currency) {
  final cur = (currency ?? 'SYP').toString().toUpperCase();
  if (cur == 'SYP') return formatSyp(value);
  final amount = double.tryParse(value?.toString() ?? '0') ?? 0;
  return '${NumberFormat('#,##0.00', 'en_US').format(amount)} $cur';
}

/// Off-cycle = urgent payroll of ONE worker, outside the normal period payroll.
bool isOffCycleBatch(Map b) => (b['batch_type'] ?? 'Regular').toString() == 'OffCycle';

const Color offCycleColor = Color(0xff8a4b00);
const Color offCycleBg = Color(0xfffff4e0);

String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String _dateOnly(dynamic v) {
  if (v == null) return '';
  final s = v.toString();
  return s.contains('T') ? s.split('T')[0] : s;
}

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({Key? key}) : super(key: key);

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);
  static const Color accentColor = Color(0xfffdbb2d);
  static const Color dangerColor = Color(0xffb21f1f);

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isGenerating = false;
  bool _isLoadingBatches = true;
  bool _isLoadingSites = true;

  List<dynamic> _payrollBatches = [];
  bool _includeHistory = false;
  List<dynamic> _filteredBatches = [];
  List<dynamic> _sites = [];

  int? _selectedSiteId;
  DateTime? _dailyAttendanceDate;
  bool _isExportingDailyAttendance = false;

  @override
  void initState() {
    super.initState();
    _fetchSites();
    _fetchPayrollReports();
    _fetchLastBatchDate();
    _searchController.addListener(_filterBatches);
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSites() async {
    try {
      final response = await ApiConfig.dio.get('/sites/all-sites');
      final responseData = response.data;
      List sitesList = [];
      if (responseData is List) {
        sitesList = responseData;
      } else if (responseData is Map && responseData['data'] is List) {
        sitesList = responseData['data'];
      }

      final formattedSites = sitesList.map((site) {
        return {
          ...site,
          'site_id': site['site_id'] != null ? int.parse(site['site_id'].toString()) : null,
        };
      }).toList();

      setState(() {
        _sites = formattedSites;
        _isLoadingSites = false;
      });
    } catch (e) {
      setState(() => _isLoadingSites = false);
      _showSnack('Failed to load sites', dangerColor);
    }
  }

  String formatDisplayDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parsedDate = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd').format(DateTime(parsedDate.year, parsedDate.month, parsedDate.day));
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _fetchPayrollReports() async {
    setState(() => _isLoadingBatches = true);
    try {
      final queryParams = <String, dynamic>{};
      if (_selectedSiteId != null) {
        queryParams['site_id'] = _selectedSiteId;
      }
      if (_includeHistory) queryParams['include_history'] = '1';

      final response = await ApiConfig.dio.get(
        '/admin/payroll/report',
        queryParameters: queryParams,
      );

      final responseData = response.data;
      List batchesList = [];
      if (responseData is List) {
        batchesList = responseData;
      } else if (responseData is Map && responseData['data'] is List) {
        batchesList = responseData['data'];
      }

      setState(() {
        _payrollBatches = batchesList;
        _filteredBatches = _payrollBatches;
        _isLoadingBatches = false;
      });
    } catch (e) {
      setState(() => _isLoadingBatches = false);
      _showSnack('Failed to load payroll reports', dangerColor);
    }
  }

  void _filterBatches() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredBatches = _payrollBatches.where((b) {
        final id = b['payroll_batch_id'].toString();
        final by = (b['generated_by'] ?? '').toString().toLowerCase();
        final worker = (b['scope_worker_name'] ?? '').toString().toLowerCase();
        final type = isOffCycleBatch(b) ? 'off-cycle offcycle' : '';
        return id.contains(q) || by.contains(q) || worker.contains(q) || type.contains(q);
      }).toList();
    });
  }

  /// C-03: the server refuses to generate while attendance in the period is
  /// not approved, and returns the list. The Admin either fixes it first or
  /// explicitly confirms that those records are NOT paid in this batch.
  Future<bool> _confirmPendingAttendance(Map data) async {
    final List rows = (data['pending_attendance'] as List?) ?? [];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unapproved attendance in this period'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['message']?.toString() ?? ''),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length > 50 ? 50 : rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['full_name']} · ${r['site_name']} (${r['shift_type'] ?? 'Day'})'),
                      subtitle: Text('${r['record_date']}'),
                      trailing: StatusPill(label: '${r['status']}', color: WorkflowColors.of(r['status']?.toString())),
                    );
                  },
                ),
              ),
              if (rows.length > 50)
                Text('…and ${rows.length - 50} more', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel — review first')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate without them', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _reasonDialog(String title, String message, String confirmLabel, Color color) async {
    final ctrl = TextEditingController();
    String? err;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Reason (required, min. 5 characters)',
                    errorText: err,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: () {
                if (ctrl.text.trim().length < 5) {
                  setD(() => err = 'Please enter a clear reason');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// D-03: void a Generated (not finalized) batch. Nothing is deleted.
  Future<void> _voidBatch(int batchId) async {
    final reason = await _reasonDialog(
      'Void batch #$batchId',
      'Use this only for a batch generated by mistake. The batch stays in the history as "Voided" '
          'and its period can be generated again. Finalized or paid batches cannot be voided.',
      'Void batch',
      dangerColor,
    );
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/void', data: {'reason': reason});
      _showSnack(r.data['message']?.toString() ?? 'Batch voided', Colors.blueGrey);
      _fetchPayrollReports();
      _fetchLastBatchDate();
    } on DioException catch (e) {
      _showSnack(e.response?.data is Map ? (e.response?.data['message'] ?? 'Failed to void batch').toString() : 'Failed to void batch', dangerColor);
    }
  }

  /// D-03: correct a finalized, unpaid batch. Generation, verification and
  /// superseding happen in one server transaction; the old batch is only
  /// marked Superseded if the replacement was created successfully.
  Future<void> _supersedeBatch(int batchId, {bool acknowledgePending = false, String? reason}) async {
    reason ??= await _reasonDialog(
      'Correct (supersede) batch #$batchId',
      'A new version is generated for the same period and site from the current approved attendance. '
          'This batch is kept as "Superseded" for audit. Paid batches can never be superseded.',
      'Generate new version',
      Colors.indigo,
    );
    if (reason == null) return;
    try {
      final r = await ApiConfig.dio.post('/admin/payroll/batch/$batchId/supersede', data: {
        'reason': reason,
        if (acknowledgePending) 'acknowledge_pending': true,
      });
      _showSnack(r.data['message']?.toString() ?? 'New version generated', Colors.green.shade700);
      _fetchPayrollReports();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'PENDING_ATTENDANCE' && !acknowledgePending) {
        if (await _confirmPendingAttendance(data)) {
          await _supersedeBatch(batchId, acknowledgePending: true, reason: reason);
        }
        return;
      }
      _showSnack(data is Map ? (data['message'] ?? 'Failed to supersede batch').toString() : 'Failed to supersede batch', dangerColor);
    }
  }

  Future<void> _generatePayroll({bool acknowledgePending = false}) async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select start and end dates', Colors.orange);
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final response = await ApiConfig.dio.post('/admin/payroll/generate', data: {
        'start_date': _startDateController.text,
        'end_date': _endDateController.text,
        if (_selectedSiteId != null) 'site_id': _selectedSiteId,
        if (acknowledgePending) 'acknowledge_pending': true,
      });
      if (response.data['success'] == true || response.statusCode == 200 || response.statusCode == 201) {
        _showSnack('Payroll batch generated successfully', Colors.green);
        _startDateController.clear();
        _endDateController.clear();
        _fetchPayrollReports();
        _fetchLastBatchDate();
      }
    } catch (e) {
      String errorMessage = 'Error generating payroll';

      if (e is DioException && e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data['code'] == 'PENDING_ATTENDANCE' && !acknowledgePending) {
          if (mounted) setState(() => _isGenerating = false);
          if (await _confirmPendingAttendance(data)) {
            await _generatePayroll(acknowledgePending: true);
          }
          return;
        }
        if (data['code'] == 'OFFCYCLE_NOT_FINALIZED') {
          if (mounted) setState(() => _isGenerating = false);
          await _showOffCycleNotFinalized(data);
          return;
        }
        errorMessage = (data['message'] ?? errorMessage).toString();
      }

      _showSnack(errorMessage, Colors.orange[800]!);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// The normal payroll skips days already paid off-cycle, so those off-cycle
  /// batches must be finalized first. Lets the Admin open them directly.
  Future<void> _showOffCycleNotFinalized(Map data) async {
    final List list = (data['offcycle_batches'] as List?) ?? [];
    final openId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize the off-cycle payroll first'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'These workers were paid off-cycle inside this period. The normal payroll skips their paid days, '
                'so their off-cycle batches must be finalized (or voided) before you generate it.',
              ),
              const SizedBox(height: 12),
              ...list.map((b) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_pin_outlined, color: offCycleColor),
                    title: Text('${b['worker_name']}'),
                    subtitle: Text('Batch #${b['payroll_batch_id']} · ${b['start_date']} → ${b['end_date']}'),
                    trailing: TextButton(
                      onPressed: () => Navigator.pop(ctx, int.tryParse('${b['payroll_batch_id']}')),
                      child: const Text('Open'),
                    ),
                  )),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
    if (openId != null) _openBatchDetails(openId);
  }

  Future<void> _openOffCycleDialog() async {
    final result = await showDialog<Map>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const _OffCycleDialog(),
      ),
    );
    if (result == null || !mounted) return;
    final batchId = int.tryParse('${result['batch_id']}');
    _showSnack(
      'Off-cycle batch #${result['batch_id']} created for ${result['worker_name']}. Finalize it, then mark it paid.',
      Colors.green.shade700,
    );
    await _fetchPayrollReports();
    if (batchId != null && mounted) _openBatchDetails(batchId);
  }

  Future<void> _selectDailyAttendanceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dailyAttendanceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Select attendance date',
    );
    if (picked != null && mounted) {
      setState(() => _dailyAttendanceDate = picked);
    }
  }

  Future<void> _exportDailyAttendance() async {
    final selected = _dailyAttendanceDate;
    if (selected == null) {
      _showSnack('Select an attendance date first.', Colors.orange);
      return;
    }

    final date = DateFormat('yyyy-MM-dd').format(selected);
    setState(() => _isExportingDailyAttendance = true);
    try {
      final response = await ApiConfig.dio.get(
        '/admin/payroll/daily-attendance/export.xlsx',
        queryParameters: {
          'date': date,
          if (_selectedSiteId != null) 'site_id': _selectedSiteId,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data is List<int>
          ? List<int>.from(response.data as List<int>)
          : <int>[];
      if (bytes.isEmpty) throw Exception('Empty attendance report');
      await PayrollExportService.exportBytes(bytes, 'daily_attendance_$date.xlsx');
      if (mounted) _showSnack('Daily attendance report exported.', Colors.green);
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        final message = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Failed to export daily attendance report.';
        _showSnack(message, dangerColor);
      }
    } catch (_) {
      if (mounted) _showSnack('Failed to export daily attendance report.', dangerColor);
    } finally {
      if (mounted) setState(() => _isExportingDailyAttendance = false);
    }
  }

Future<void> _finalizeBatch(int batchId) async {
  try {
    await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/finalize');
    _showSnack('Payroll batch finalized successfully', Colors.green.shade700);
    _fetchPayrollReports();
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to finalize batch')
        : 'Failed to finalize batch';
    _showSnack(msg, dangerColor);
  } catch (e) {
    _showSnack('Failed to finalize batch', dangerColor);
  }
}

Future<void> _markBatchAsPaid(int batchId) async {
  try {
    await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/mark-paid');
    _showSnack('Batch marked as paid', Colors.green);
    _fetchPayrollReports();
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to update payment status')
        : 'Failed to update payment status';
    _showSnack(msg, dangerColor);
  } catch (e) {
    _showSnack('Failed to update payment status', dangerColor);
  }
}

  // Stores the end date of the most recent batch (optionally scoped to the
  // selected site) so the "Start Date" picker can't create overlaps.
  DateTime? _lastBatchEndDate;

  Future<void> _fetchLastBatchDate() async {
    try {
      final queryParams = <String, dynamic>{};
      if (_selectedSiteId != null) {
        queryParams['site_id'] = _selectedSiteId;
      }
      final response = await ApiConfig.dio.get(
        '/admin/payroll/last-date',
        queryParameters: queryParams,
      );
      if (response.data['success'] == true && response.data['last_end_date'] != null) {
        String lastEndStr = response.data['last_end_date'].toString();
        if (lastEndStr.contains('T')) lastEndStr = lastEndStr.split('T')[0];

        DateTime parsedEnd = DateTime.parse(lastEndStr);
        DateTime nextStart = parsedEnd.add(const Duration(days: 1));

        setState(() {
          _lastBatchEndDate = parsedEnd;
          _startDateController.text = "${nextStart.year.toString().padLeft(4, '0')}-"
              "${nextStart.month.toString().padLeft(2, '0')}-"
              "${nextStart.day.toString().padLeft(2, '0')}";
        });
      } else {
        setState(() => _lastBatchEndDate = null);
      }
    } catch (_) {}
  }

Future<void> _selectDate(TextEditingController controller, {bool isStartDate = false}) async {
  final initial = isStartDate && _lastBatchEndDate != null
      ? _lastBatchEndDate!.add(const Duration(days: 1))
      : DateTime.now();

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2025),
    lastDate: DateTime(2035),
    // لم يعد فيه selectableDayPredicate يمنع التواريخ —
    // بس بنحذر الأدمن إذا اختار فترة قديمة (تصحيح/Supersede)
  );

  if (picked != null) {
    if (isStartDate &&
        _lastBatchEndDate != null &&
        !picked.isAfter(_lastBatchEndDate!)) {
      final confirmOverlap = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overlapping Period'),
          content: const Text(
            'This start date overlaps an existing payroll period.\n\n'
            '• Not finalized batch for the SAME period and site: it is replaced by a new version.\n'
            '• Finalized batch: generation is refused — use "Correct (supersede)" on that batch with a reason.\n'
            '• Paid batch: can never be regenerated; differences go through attendance corrections.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmOverlap != true) return;
    }

    final String formattedDate = "${picked.year.toString().padLeft(4, '0')}-"
        "${picked.month.toString().padLeft(2, '0')}-"
        "${picked.day.toString().padLeft(2, '0')}";

    setState(() {
      controller.text = formattedDate;
    });
  }
}

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDate(dynamic dateInput) {
    if (dateInput == null || dateInput.toString().isEmpty) return '';
    try {
      String str = dateInput.toString();
      if (str.contains('T')) {
        str = str.split('T')[0];
      }
      DateTime parsed = DateTime.parse(str);
      return DateFormat('yyyy-MM-dd').format(DateTime(parsed.year, parsed.month, parsed.day));
    } catch (e) {
      return dateInput.toString();
    }
  }

  Future<void> _openBatchDetails(int batchId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final response = await ApiConfig.dio.get('/admin/payroll/batch/$batchId');
      if (!mounted) return;
      Navigator.pop(context);

      final data = response.data;
      final batch = data['batch'] ?? {};
      // NEW SHAPE: one entry per worker, each carrying a `sites` list with
      // the per-site hours/rates/pay breakdown. No more duplicated
      // net_salary rows fanned out across sites.
      final List workers = data['workers'] ?? [];
      final List offcyclePaid = data['offcycle_paid'] ?? [];
      final Map offSummary = data['offcycle_summary'] is Map ? data['offcycle_summary'] : {};
      _showBatchDetailsSheet(batch, workers, offcyclePaid, offSummary);
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnack('Error loading batch details: $e', dangerColor);
    }
  }

  void _showBatchDetailsSheet(Map batch, List workers, [List offcyclePaid = const [], Map offSummary = const {}]) {
    final bool offCycle = isOffCycleBatch(batch);
    final currency = batch['currency'];
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
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('Batch #${batch['payroll_batch_id'] ?? ''} (v${batch['version_number'] ?? 1})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryColor)),
              ),
              const SizedBox(width: 8),
              if (offCycle) ...[
                const StatusPill(label: 'Off-cycle', color: offCycleColor, icon: Icons.person_pin_outlined),
                const SizedBox(width: 6),
              ],
              if ((batch['is_finalized'] == 1 || batch['is_finalized'] == true))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Finalized', style: TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Not Finalized', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          Text(
            'Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          if (offCycle)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Paid separately for ${batch['scope_worker_name'] ?? 'one worker'} · Reason: ${batch['offcycle_reason'] ?? '-'}',
                style: const TextStyle(color: offCycleColor, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    ),
    IconButton(
  icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
  tooltip: 'Export PDF Report',
  onPressed: () => _exportBatchPdf(batch),
),
    IconButton(
      icon: const Icon(Icons.table_view, color: dangerColor),
      tooltip: 'Export Excel Report',
      onPressed: () => _exportBatchExcel(batch),
    ),
    const SizedBox(width: 8),
    _statusChip(batch['status']?.toString() ?? 'Pending'),
  ],
),
            ),
            const Divider(height: 1),
            Expanded(
              child: workers.isEmpty && offcyclePaid.isEmpty
                  ? const Center(child: Text('No workers found in this batch.'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      // workers, then (when any) the "paid off-cycle" section header + one card each
                      itemCount: workers.length + (offcyclePaid.isEmpty ? 0 : 1 + offcyclePaid.length),
                      itemBuilder: (context, index) {
                        if (index < workers.length) {
                          final w = Map<String, dynamic>.from(workers[index]);
                          return _WorkerPayrollCard(
                            worker: w,
                            onPreview: () => _openPayslipPreview(batch, w),
                            onOpenBatch: (id) {
                              Navigator.pop(context);
                              _openBatchDetails(id);
                            },
                          );
                        }
                        final i = index - workers.length;
                        if (i == 0) return _OffCycleSectionHeader(count: offcyclePaid.length);
                        final o = Map<String, dynamic>.from(offcyclePaid[i - 1]);
                        return _OffCyclePaidCard(
                          entry: o,
                          currency: currency,
                          onOpen: () {
                            Navigator.pop(context);
                            _openBatchDetails(int.parse('${o['payroll_batch_id']}'));
                          },
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Workers: ${batch['total_workers'] ?? workers.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            offcyclePaid.isEmpty
                                ? 'Total Amount: ${formatMoney(batch['total_amount'], currency)}'
                                : 'To pay in this batch: ${formatMoney(batch['total_amount'], currency)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 16)),
                        if (offcyclePaid.isNotEmpty) ...[
                          Text('Already paid off-cycle: ${formatMoney(offSummary['total'], currency)}',
                              style: const TextStyle(color: offCycleColor, fontWeight: FontWeight.w600, fontSize: 12.5)),
                          Text('Period total: ${formatMoney(offSummary['period_total'], currency)}',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                        ],
                      ],
                    ),
                  ),
                if ((batch['status'] ?? 'Pending') == 'Generated' &&
                    !(batch['is_finalized'] == 1 || batch['is_finalized'] == true)) ...[
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _voidBatch(batch['payroll_batch_id']);
                    },
                    icon: const Icon(Icons.block, color: dangerColor, size: 18),
                    label: const Text('Void', style: TextStyle(color: dangerColor)),
                  ),
                  const SizedBox(width: 8),
                ],
                if ((batch['status'] ?? 'Pending') == 'Generated' &&
                    (batch['is_finalized'] == 1 || batch['is_finalized'] == true)) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _supersedeBatch(batch['payroll_batch_id']);
                    },
                    icon: const Icon(Icons.published_with_changes, size: 18),
                    label: const Text('Correct (supersede)'),
                  ),
                  const SizedBox(width: 8),
                ],
                if ((batch['status'] ?? 'Pending') == 'Generated') ...[
  if (!(batch['is_finalized'] == 1 || batch['is_finalized'] == true))
    ElevatedButton.icon(
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Finalize Payroll Batch'),
            content: const Text(
              'Finalizing locks this period and confirms management approval. '
              'After finalizing, it can no longer be regenerated — only superseded with a new correction. Continue?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Finalize', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          Navigator.pop(context);
          await _finalizeBatch(batch['payroll_batch_id']);
        }
      },
      icon: const Icon(Icons.lock_outline, color: Colors.white, size: 18),
      label: const Text('Finalize', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
    )
  else
    ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        _confirmMarkPaid(batch['payroll_batch_id']);
      },
      icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
      label: const Text('Mark Paid', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
    ),
],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The server generates and streams the final .xlsx — the client only
  // downloads/shares the bytes. No calculation happens here.
  Future<void> _exportBatchExcel(Map batch) async {
    final batchId = int.tryParse('${batch['payroll_batch_id']}');
    if (batchId == null) {
      _showSnack('Invalid payroll batch.', dangerColor);
      return;
    }
    try {
    final response = await ApiConfig.dio.get<List<int>>(
  '/admin/payroll/batch/$batchId/export.xlsx',
  options: Options(
    responseType: ResponseType.bytes,
    receiveTimeout: const Duration(seconds: 90),
  ),
);
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty Excel response');
      await PayrollExportService.exportBytes(
        bytes,
        'payroll_batch_$batchId.xlsx',
      );
      if (mounted) _showSnack('Excel payroll file is ready.', Colors.green);
   } on DioException catch (e, stack) {
  print('Excel Dio error: ${e.message}');
  print('Status: ${e.response?.statusCode}');
  print('Response: ${e.response?.data}');
  print(stack);

  final data = e.response?.data;
  final message = data is Map && data['message'] != null
      ? data['message'].toString()
      : 'Failed to export Excel payroll file.';

  _showSnack(message, dangerColor);
} catch (e, stack) {
  print('Excel export error: $e');
  print(stack);
  _showSnack(
    'Excel export failed: $e',
    dangerColor,
  );
}
  }
Future<void> _exportBatchPdf(Map batch) async {
  final batchId = int.tryParse('${batch['payroll_batch_id']}');
  if (batchId == null) {
    _showSnack('Invalid payroll batch.', dangerColor);
    return;
  }
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      '/admin/payroll/batch/$batchId/export.pdf',
      options: Options(
  responseType: ResponseType.bytes,
  receiveTimeout: const Duration(seconds: 90),
),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty PDF response');
    await PayrollExportService.exportBytes(bytes, 'payroll_batch_$batchId.pdf');
    if (mounted) _showSnack('PDF payroll report is ready.', Colors.green);
  } on DioException catch (e) {
    final data = e.response?.data;
    final message = data is Map && data['message'] != null
        ? data['message'].toString()
        : 'Failed to export PDF payroll report.';
    _showSnack(message, dangerColor);
  } catch (_) {
    _showSnack('Failed to export PDF payroll report.', dangerColor);
  }
}
  Future<void> _confirmMarkPaid(int batchId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: const Text('Mark this entire batch as paid? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) _markBatchAsPaid(batchId);
  }

  Widget _statusChip(String status) {
    final Color color;
    switch (status) {
      case 'Paid':
        color = Colors.green;
        break;
      case 'Superseded':
        color = Colors.blueGrey;
        break;
      case 'Voided':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  void _openPayslipPreview(Map batch, Map worker) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: _PayslipDialog(batch: batch, worker: worker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fb),
      appBar: CustomAppBar(
        title: ('Payroll Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.price_change_outlined),
            tooltip: 'Payroll adjustments',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PayrollAdjustmentsScreen(initialType: 'Worker')),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchSites();
          await _fetchPayrollReports();
          await _fetchLastBatchDate();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSiteFilterDropdown(),
              const SizedBox(height: 16),
                            _buildGenerateCard(),
              const SizedBox(height: 16),
              const MonthlyReportCard(
                title: 'Monthly Labor Hours & Payroll Report',
                subtitle: 'Workers / laborers only. Daily hours, totals and stored payroll values for the selected month or day range.',
                endpoint: '/admin/payroll/monthly-report.xlsx',
                pdfEndpoint: '/admin/payroll/monthly-report.pdf',
                filePrefix: 'labor_hours_payroll',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Flexible(child: Text('Payroll History', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryColor))),
                  const HelpTip(
                    title: 'Payroll batch states',
                    message: 'Generated: created, can be regenerated or voided while not finalized.\n'
                        'Finalized: approved; attendance in the period is locked. Can only be corrected with "Correct (supersede)".\n'
                        'Paid: final. Never regenerated or reopened.\n'
                        'Superseded / Voided: kept for audit only (shown with "Show history").\n'
                        'Off-cycle: urgent payroll of one worker. Locks only that worker\'s days; the next payroll skips them.',
                  ),
                  const SizedBox(width: 4),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Show history'),
                    selected: _includeHistory,
                    onSelected: (v) {
                      setState(() => _includeHistory = v);
                      _fetchPayrollReports();
                    },
                  ),
                  const SizedBox(width: 8),
                  Text('${_filteredBatches.length} batches', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by batch ID or generated-by...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              _isLoadingBatches
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _filteredBatches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('No payroll batches found', style: TextStyle(color: Colors.grey.shade600)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredBatches.length,
                          itemBuilder: (context, index) {
                            final batch = _filteredBatches[index];
                            final isPaid = (batch['status'] ?? 'Pending') == 'Paid';
                            final offCycle = isOffCycleBatch(batch);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: (isPaid ? Colors.green : (offCycle ? offCycleColor : accentColor)).withOpacity(0.15),
                                  child: Icon(offCycle ? Icons.person_pin_outlined : Icons.receipt_long,
                                      color: isPaid ? Colors.green : (offCycle ? offCycleColor : primaryColor)),
                                ),
                                title: Row(
                                  children: [
                                    Text('Batch #${batch['payroll_batch_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    IconButton(
  icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
  tooltip: 'Export PDF',
  onPressed: () => _exportBatchPdf(batch),
),
                                    IconButton(
                                      icon: const Icon(Icons.table_view, color: dangerColor, size: 20),
                                      tooltip: 'Export Excel',
                                      onPressed: () => _exportBatchExcel(batch),
                                    ),
                                  ],
                                ),
                               subtitle: Text(
  offCycle
      ? 'Off-cycle • ${batch['scope_worker_name'] ?? 'Worker'} • v${batch['version_number'] ?? 1} • ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}\n'
        'Total: ${formatMoney(batch['total_amount'], batch['currency'])} • By: ${batch['generated_by'] ?? 'Admin'}'
        '${(batch['is_finalized'] == 1 || batch['is_finalized'] == true) ? '' : ' • Not Finalized'}'
      : 'v${batch['version_number'] ?? 1} • Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}\n'
        'Workers: ${batch['total_workers']} • Total: ${formatMoney(batch['total_amount'], batch['currency'])} • By: ${batch['generated_by'] ?? 'Admin'}'
        '${(batch['is_finalized'] == 1 || batch['is_finalized'] == true) ? '' : ' • Not Finalized'}',
),
                                isThreeLine: true,
                                trailing: _statusChip(batch['status']?.toString() ?? 'Pending'),
                                onTap: () => _openBatchDetails(batch['payroll_batch_id']),
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

  Widget _buildSiteFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonFormField<int?>(
        value: _selectedSiteId,
        decoration: const InputDecoration(
          labelText: 'Filter by Site',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('All Sites (الكل)'),
          ),
          ..._sites.map((site) {
            return DropdownMenuItem<int?>(
              value: site['site_id'],
              child: Text(site['site_name'] ?? 'Site #${site['site_id']}'),
            );
          }).toList(),
        ],
        onChanged: (val) {
          setState(() {
            _selectedSiteId = val;
          });
          _fetchPayrollReports();
          _fetchLastBatchDate();
        },
      ),
    );
  }

  Widget _buildGenerateCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Generate New Payroll', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
              const Spacer(),
              if (_selectedSiteId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('For Selected Site', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startDateController,
                  readOnly: true,
                  onTap: () => _selectDate(_startDateController, isStartDate: true),
                  decoration: const InputDecoration(
                    labelText: 'Start Date',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _endDateController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'End Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  onTap: () => _selectDate(_endDateController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generatePayroll,
              icon: _isGenerating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt, color: Colors.white),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Payroll Batch', style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isGenerating ? null : _openOffCycleDialog,
              icon: const Icon(Icons.person_pin_outlined, color: offCycleColor),
              label: const Text('Pay one worker now (off-cycle)', style: TextStyle(color: offCycleColor)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: offCycleColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              'For an urgent payment before the period payroll. The next payroll skips the days paid here.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExportingDailyAttendance ? null : _selectDailyAttendanceDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_dailyAttendanceDate == null
                      ? 'Daily Attendance Date'
                      : DateFormat('yyyy-MM-dd').format(_dailyAttendanceDate!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isExportingDailyAttendance ? null : _exportDailyAttendance,
                  icon: _isExportingDailyAttendance
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_outlined),
                  label: const Text('Print Daily Attendance'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerPayrollCard extends StatelessWidget {
  final Map worker;
  final VoidCallback onPreview;
  final void Function(int batchId)? onOpenBatch;

  const _WorkerPayrollCard({required this.worker, required this.onPreview, this.onOpenBatch});

  @override
  Widget build(BuildContext context) {
    final sites = (worker['sites'] is List) ? (worker['sites'] as List) : [];
    
    // استخراج كل أنواع الدفع الفريدة للمرونة
    final uniquePayTypes = sites.map((s) => s['pay_type']?.toString()).where((t) => t != null).toSet();
    final isMixed = uniquePayTypes.length > 1;
    final payTypeLabel = isMixed ? 'Mixed' : (worker['pay_type'] ?? 'Hourly');
    final isDaily = payTypeLabel == 'Daily';

    // جمع المجاميع من الـ sites للتأكد من مطابقة الأرقام
    final totalDays = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['days_worked']?.toString() ?? '0') ?? 0));
    final totalRegular = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['regular_hours_worked']?.toString() ?? '0') ?? 0));
    final totalOvertime = sites.fold<num>(0, (sum, s) => sum + (num.tryParse(s['overtime_hours_worked']?.toString() ?? '0') ?? 0));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    worker['worker_name'] ?? 'Worker #${worker['worker_id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1a2a6c)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isMixed ? Colors.orange.shade50 : (isDaily ? Colors.purple.shade50 : Colors.blue.shade50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payTypeLabel,
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: isMixed ? Colors.orange.shade800 : (isDaily ? Colors.purple : Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Payslip'),
                ),
              ],
            ),
            // Part of this worker's period was already paid off-cycle.
            ...((worker['offcycle_batches'] is List) ? (worker['offcycle_batches'] as List) : const []).map((o) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: offCycleBg, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: offCycleColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Already paid ${_dateOnly(o['start_date'])} → ${_dateOnly(o['end_date'])}: '
                          '${formatMoney(o['amount'], o['currency'])} (off-cycle #${o['payroll_batch_id']}, '
                          '${o['status'] == 'Paid' ? 'paid' : 'not paid yet'}). This batch pays the other days only.',
                          style: const TextStyle(fontSize: 12, color: offCycleColor),
                        ),
                      ),
                      if (onOpenBatch != null)
                        TextButton(
                          onPressed: () => onOpenBatch!(int.parse('${o['payroll_batch_id']}')),
                          child: const Text('Open'),
                        ),
                    ],
                  ),
                )),
            // Retro pay: adjustments for earlier paid periods, already inside Net Pay.
            ..._adjustmentLines(worker),
            const Divider(),
            if (isMixed)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Sites / Types', '${sites.length} Records', Colors.blueGrey),
                  _miniStat('Total Days/Hrs', '${totalDays > 0 ? "$totalDays days" : ""} ${totalRegular > 0 ? "$totalRegular h" : ""}', Colors.blueGrey),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              )
            else if (isDaily)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat(
  'Days Worked',
  (double.tryParse(worker['days_worked'].toString()) ?? 0).toStringAsFixed(2),
  Colors.blueGrey,
),
                  _miniStat('Daily Rate',
                      worker['rate_changed'] == true
                          ? _ratesText(sites, 'daily_rate_snapshot')
                          : formatSyp(worker['daily_rate'] ?? sites.firstOrNull?['daily_rate_snapshot']),
                      Colors.blueGrey),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Regular', '$totalRegular h', Colors.blueGrey),
                  _miniStat('Overtime', '$totalOvertime h', Colors.orange.shade800),
                  _miniStat('Net Pay', formatSyp(worker['net_salary']), Colors.green.shade700, bold: true),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _adjustmentLines(Map worker) {
    final list = (worker['adjustments'] is List) ? (worker['adjustments'] as List) : const [];
    return list.map<Widget>((a) {
      final amount = num.tryParse('${a['amount']}') ?? 0;
      final origin = a['origin_date'] != null
          ? 'for ${a['origin_date']}${a['origin_batch_id'] != null ? ' (paid batch #${a['origin_batch_id']})' : ''}'
          : '(manual)';
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xffeef3ff), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(amount >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 16, color: const Color(0xff1a2a6c)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Adjustment $origin: ${amount > 0 ? '+' : ''}${formatMoney(a['amount'], a['currency'])} — ${a['reason'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xff1a2a6c)),
            ),
          ),
        ]),
      );
    }).toList();
  }

  Widget _miniStat(String label, String value, Color color, {bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Read-only payslip for a single worker within a batch. Iterates the
/// worker's `sites` breakdown and shows the single net-salary total once.
class _PayslipDialog extends StatefulWidget {
  final Map batch;
  final Map worker;

  const _PayslipDialog({required this.batch, required this.worker});

  @override
  State<_PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends State<_PayslipDialog> {
  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.contains('T') ? s.split('T')[0] : s;
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  List<Map<String, dynamic>> get _sites {
    final raw = widget.worker['sites'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final b = widget.batch;
    final sites = _sites;

    final uniquePayTypes = sites.map((s) => s['pay_type']?.toString()).where((t) => t != null).toSet();
    final isMixed = uniquePayTypes.length > 1;
    final payTypeLabel = isMixed ? 'Mixed' : (w['pay_type'] ?? 'Hourly');

    final totalRegularHours = sites.fold<double>(0, (sum, s) => sum + _num(s['regular_hours_worked']));
    final totalOvertimeHours = sites.fold<double>(0, (sum, s) => sum + _num(s['overtime_hours_worked']));
    final totalDaysWorked = sites.fold<double>(0, (sum, s) => sum + _num(s['days_worked']));
    final totalBaseSalary = sites.fold<double>(0, (sum, s) => sum + _num(s['base_salary']));
    final totalOvertimePay = sites.fold<double>(0, (sum, s) => sum + _num(s['overtime_pay']));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w['worker_name'] ?? 'Worker #${w['worker_id']}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
                        const SizedBox(height: 2),
                        Text(isOffCycleBatch(b) ? 'Off-cycle batch #${b['payroll_batch_id']} • Payslip' : 'Batch #${b['payroll_batch_id']} • Payslip',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),
              _infoRow('Period', '${_fmtDate(b['start_date'])} to ${_fmtDate(b['end_date'])}'),
              _infoRow('Payment Type', payTypeLabel),
              
              if (isMixed) ...[
                _infoRow(
  'Days Worked',
  (double.tryParse(w['days_worked'].toString()) ?? 0).toStringAsFixed(2),
),
                _infoRow('Total Regular Hours', '${totalRegularHours.toStringAsFixed(2)} h'),
                _infoRow('Total Overtime Hours', '${totalOvertimeHours.toStringAsFixed(2)} h'),
              ] else if (payTypeLabel == 'Daily') ...[
                _infoRow('Days Worked', '${totalDaysWorked.toStringAsFixed(0)}'),
                _infoRow('Daily Rate', w['rate_changed'] == true
                    ? _ratesText(sites, 'daily_rate_snapshot')
                    : formatSyp(w['daily_rate'] ?? sites.firstOrNull?['daily_rate_snapshot'])),
              ] else ...[
                _infoRow('Regular Hours', '${totalRegularHours.toStringAsFixed(2)} h'),
                _infoRow('Overtime Hours', '${totalOvertimeHours.toStringAsFixed(2)} h'),
                _infoRow('Regular Rate', w['rate_changed'] == true
                    ? _ratesText(sites, 'hourly_rate_snapshot')
                    : formatSyp(w['regular_rate'] ?? sites.firstOrNull?['hourly_rate_snapshot'])),
                _infoRow('Overtime Rate', formatSyp(w['overtime_rate'] ?? sites.firstOrNull?['overtime_hourly_rate_snapshot'])),
              ],

              _infoRow('Base Salary', formatSyp(totalBaseSalary)),
              _infoRow('Overtime Pay', formatSyp(totalOvertimePay)),

              const SizedBox(height: 12),
              Text('Per-site breakdown', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              ...sites.map((s) {
                final sType = s['pay_type'] ?? 'Hourly';
                final isDaily = sType == 'Daily';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(s['site_name']?.toString() ?? 'Site #${s['site_id']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDaily ? Colors.purple.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(sType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDaily ? Colors.purple : Colors.blue)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Rate period (a raise inside the batch period = one line per rate).
                      if (sites.length > 1 && s['rate_from'] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('Period: ${s['rate_from']} → ${s['rate_to']}',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
                        ),
                      if (isDaily)
                        Text(
                          'Days: ${_num(s['days_worked']).toStringAsFixed(0)}  •  Rate: ${formatSyp(s['daily_rate_snapshot'])}  •  Total: ${formatSyp(s['base_salary'])}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        )
                      else
                        Text(
                          'Regular: ${_num(s['regular_hours_worked']).toStringAsFixed(2)}h @ ${formatSyp(s['hourly_rate_snapshot'])}  •  Overtime: ${_num(s['overtime_hours_worked']).toStringAsFixed(2)}h @ ${formatSyp(s['overtime_hourly_rate_snapshot'])}',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                );
              }),

              ..._WorkerPayrollCard._adjustmentLines(w),
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net Salary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(formatSyp(w['net_salary']),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff1a2a6c))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'This is a read-only payroll summary. Export the complete batch from the Excel button.',
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Rates of a worker's payroll lines in date order, e.g. "100,000 ل.س → 120,000 ل.س"
/// (a raise inside the batch period gives one line per rate).
String _ratesText(List sites, String field) {
  final seen = <String>[];
  for (final s in sites) {
    final v = s is Map ? s[field] : null;
    if (v == null) continue;
    final label = formatSyp(v);
    if (seen.isEmpty || seen.last != label) seen.add(label);
  }
  return seen.join(' → ');
}

// ============================================================================
// Off-cycle payroll (urgent payroll of one worker)
// ============================================================================

/// Header of the "Paid off-cycle in this period" section in a batch's details.
class _OffCycleSectionHeader extends StatelessWidget {
  final int count;
  const _OffCycleSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_outlined, color: offCycleColor, size: 20),
              const SizedBox(width: 6),
              Text('Paid off-cycle in this period ($count)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: offCycleColor)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'These payments were made separately. They are not part of this batch total and their days are not paid again here.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

/// One off-cycle payment shown inside a normal batch.
class _OffCyclePaidCard extends StatelessWidget {
  final Map entry;
  final dynamic currency;
  final VoidCallback onOpen;
  const _OffCyclePaidCard({required this.entry, required this.currency, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final o = entry;
    final isPaid = o['status'] == 'Paid';
    final finalized = o['is_finalized'] == true || o['is_finalized'] == 1;
    final inThis = o['in_this_batch'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: offCycleBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: offCycleColor.withOpacity(0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${o['worker_name'] ?? 'Worker'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1a2a6c))),
                  ),
                  StatusPill(
                    label: isPaid ? 'Paid' : (finalized ? 'Finalized, not paid' : 'Not finalized'),
                    color: isPaid ? Colors.green.shade700 : (finalized ? Colors.indigo : Colors.orange.shade800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Off-cycle #${o['payroll_batch_id']} · ${_dateOnly(o['start_date'])} → ${_dateOnly(o['end_date'])}'
                '${(o['sites'] ?? '').toString().isNotEmpty ? ' · ${o['sites']}' : ''}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
              ),
              if ((o['reason'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Reason: ${o['reason']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inThis ? 'Remaining days are in this batch' : 'Whole period paid off-cycle',
                      style: const TextStyle(fontSize: 12, color: offCycleColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(formatMoney(o['amount'], o['currency'] ?? currency),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: offCycleColor)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog: choose the period and the worker, preview the exact amount
/// (server dry run, nothing saved), give a reason, create the batch.
/// Pops with {batch_id, worker_name} on success.
class _OffCycleDialog extends StatefulWidget {
  const _OffCycleDialog();

  @override
  State<_OffCycleDialog> createState() => _OffCycleDialogState();
}

class _OffCycleDialogState extends State<_OffCycleDialog> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  DateTime? _start;
  DateTime _end = DateTime.now();

  bool _loadingWorkers = false;
  String? _workersError;
  List<Map<String, dynamic>> _workers = [];
  int? _regularBatchInPeriod;

  Map<String, dynamic>? _selected;

  bool _loadingPreview = false;
  Map<String, dynamic>? _preview;     // successful dry run
  Map<String, dynamic>? _previewError; // server error body (message / code / pending_attendance)

  bool _creating = false;
  String? _reasonError;

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  String? _errorMessage(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      return ((e.response!.data as Map)['message'] ?? fallback).toString();
    }
    return fallback;
  }

  Future<void> _pickDate({required bool start}) async {
    final today = DateTime.now();
    final initial = start ? (_start ?? _end.subtract(const Duration(days: 6))) : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(2025),
      lastDate: today, // an off-cycle payroll never ends in the future
      helpText: start ? 'First day to pay' : 'Last day to pay',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
      _selected = null;
      _preview = null;
      _previewError = null;
    });
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    if (_start == null) return;
    setState(() {
      _loadingWorkers = true;
      _workersError = null;
    });
    try {
      final r = await ApiConfig.dio.get('/admin/payroll/offcycle/candidates', queryParameters: {
        'start_date': _isoDate(_start!),
        'end_date': _isoDate(_end),
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });
      final List data = (r.data is Map && r.data['data'] is List) ? r.data['data'] : [];
      if (!mounted) return;
      setState(() {
        _workers = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _regularBatchInPeriod = int.tryParse('${r.data['regular_batch_in_period']}');
        _loadingWorkers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingWorkers = false;
        _workersError = _errorMessage(e, 'Could not load workers for this period.');
      });
    }
  }

  Future<void> _loadPreview() async {
    final w = _selected;
    if (w == null || _start == null) return;
    setState(() {
      _loadingPreview = true;
      _preview = null;
      _previewError = null;
    });
    try {
      final r = await ApiConfig.dio.post('/admin/payroll/generate-offcycle', data: {
        'worker_id': w['worker_id'],
        'start_date': _isoDate(_start!),
        'end_date': _isoDate(_end),
        'dry_run': true,
      });
      if (!mounted) return;
      setState(() {
        _preview = Map<String, dynamic>.from(r.data as Map);
        _loadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = (e is DioException && e.response?.data is Map)
            ? Map<String, dynamic>.from(e.response!.data as Map)
            : {'message': 'Could not calculate the payroll. Check your connection and try again.'};
      });
    }
  }

  Future<void> _create() async {
    final w = _selected;
    if (w == null || _preview == null || _start == null) return;
    if (_reason.text.trim().length < 5) {
      setState(() => _reasonError = 'Write why this worker is paid now (at least 5 characters)');
      return;
    }
    setState(() {
      _creating = true;
      _reasonError = null;
    });
    try {
      final r = await ApiConfig.dio.post('/admin/payroll/generate-offcycle', data: {
        'worker_id': w['worker_id'],
        'start_date': _isoDate(_start!),
        'end_date': _isoDate(_end),
        'reason': _reason.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, {'batch_id': r.data['batch_id'], 'worker_name': w['full_name']});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        // Something changed since the preview (e.g. a record was rejected): show why.
        _preview = null;
        _previewError = (e is DioException && e.response?.data is Map)
            ? Map<String, dynamic>.from(e.response!.data as Map)
            : {'message': 'The off-cycle batch was not created. Try again.'};
      });
    }
  }

  // ---------------------------------------------------------------- UI parts

  Widget _sectionTitle(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: offCycleColor,
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xff1a2a6c))),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value == null ? 'Choose' : _isoDate(value),
            style: TextStyle(color: value == null ? Colors.grey.shade500 : null)),
      ),
    );
  }

  Widget _workerTile(Map<String, dynamic> w) {
    final approved = (w['approved'] as num?)?.toInt() ?? 0;
    final pending = (w['pending'] as num?)?.toInt() ?? 0;
    final alreadyOff = w['offcycle_batch_id'] != null;
    final selected = _selected != null && _selected!['worker_id'] == w['worker_id'];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected ? offCycleBg : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? offCycleColor : Colors.grey.shade200, width: selected ? 1.4 : 1),
      ),
      child: ListTile(
        dense: true,
        onTap: () {
          setState(() => _selected = w);
          _loadPreview();
        },
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? offCycleColor : Colors.grey),
        title: Text('${w['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${w['worker_unique_id'] ?? ''}${(w['sites'] ?? '').toString().isNotEmpty ? ' · ${w['sites']}' : ''}'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (alreadyOff)
                  StatusPill(label: 'Paid off-cycle #${w['offcycle_batch_id']}', color: offCycleColor)
                else ...[
                  StatusPill(label: '$approved approved', color: Colors.green.shade700),
                  if (pending > 0) StatusPill(label: '$pending waiting for approval', color: Colors.orange.shade800),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewPanel() {
    if (_selected == null) {
      return Text('Choose a worker above to see the amount.', style: TextStyle(color: Colors.grey.shade600));
    }
    if (_loadingPreview) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final err = _previewError;
    if (err != null) {
      final List pending = (err['pending_attendance'] as List?) ?? const [];
      final isPending = err['code'] == 'OFFCYCLE_PENDING_ATTENDANCE';
      final color = isPending ? Colors.orange.shade800 : Colors.red.shade700;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isPending ? Icons.hourglass_top : Icons.error_outline, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(isPending ? 'Approve this worker\'s attendance first' : 'This payroll cannot be created',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${err['message'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...pending.take(15).map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${row['record_date']} · ${row['site_name']} (${row['shift_type'] ?? 'Day'})',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                        StatusPill(label: '${row['status']}', color: WorkflowColors.of(row['status']?.toString())),
                      ],
                    ),
                  )),
              if (pending.length > 15)
                Text('…and ${pending.length - 15} more', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Approve them in Attendance review (search the worker\'s name), then tap "Check again".',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loadPreview,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Check again'),
              ),
            ),
          ],
        ),
      );
    }
    final p = _preview;
    if (p == null) return const SizedBox.shrink();
    final List lines = (p['lines'] as List?) ?? const [];
    final List noRecord = (p['days_without_record'] as List?) ?? const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: offCycleColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${p['worker']?['full_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Text(formatMoney(p['net_salary'], p['currency']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xff1a2a6c))),
            ],
          ),
          Text('${p['approved_records']} approved day(s) · ${p['start_date']} → ${p['end_date']}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          const Divider(height: 18),
          ...lines.map((l) {
            final daily = l['pay_type'] == 'Daily';
            final ot = (num.tryParse('${l['overtime_hours']}') ?? 0) > 0;
            final work = daily
                ? '${(num.tryParse('${l['days_worked']}') ?? 0).toStringAsFixed(2)} days × ${formatMoney(l['daily_rate'], p['currency'])}'
                : '${l['regular_hours']} h × ${formatMoney(l['hourly_rate'], p['currency'])}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l['site_name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('${l['from']} → ${l['to']} · $work'
                            '${ot ? ' · OT ${l['overtime_hours']} h' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  Text(formatMoney((num.tryParse('${l['base_salary']}') ?? 0) + (num.tryParse('${l['overtime_pay']}') ?? 0), p['currency']),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            );
          }),
          if (noRecord.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'No attendance recorded on ${noRecord.length} day(s): ${noRecord.take(10).join(', ')}${noRecord.length > 10 ? ' …' : ''}. '
                'Those days are not paid, and after you finalize this batch they cannot be recorded for this worker any more.',
                style: TextStyle(fontSize: 12, color: Colors.brown.shade700),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'After you finalize it, this worker\'s attendance from ${p['start_date']} to ${p['end_date']} is locked. '
            'Other workers are not affected. The next payroll for this period skips these days and shows this payment.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _preview != null && !_creating && !_loadingPreview;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580, maxHeight: 820),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.person_pin_outlined, color: offCycleColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Pay one worker now (off-cycle)',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: _creating ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pays one worker\'s approved attendance for the days you choose, before the normal payroll. '
                    'Nothing is saved until you press "Create off-cycle batch".',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  _sectionTitle('1', 'Days to pay'),
                  Row(
                    children: [
                      Expanded(child: _dateField('From', _start, () => _pickDate(start: true))),
                      const SizedBox(width: 10),
                      Expanded(child: _dateField('To', _end, () => _pickDate(start: false))),
                    ],
                  ),
                  if (_regularBatchInPeriod != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Payroll batch #$_regularBatchInPeriod already covers part of these days. Workers paid there cannot be paid off-cycle for the same days.',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  _sectionTitle('2', 'Worker'),
                  if (_start == null)
                    Text('Choose the first day to pay to see the workers with attendance in that period.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))
                  else ...[
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _loadWorkers(),
                      decoration: InputDecoration(
                        hintText: 'Search by name or worker ID',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 20), onPressed: _loadWorkers),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingWorkers)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_workersError != null)
                      Text(_workersError!, style: TextStyle(color: Colors.red.shade700))
                    else if (_workers.isEmpty)
                      Text('No worker has attendance in this period${_search.text.trim().isEmpty ? '' : ' matching the search'}.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView(
                          shrinkWrap: true,
                          children: _workers.map(_workerTile).toList(),
                        ),
                      ),
                  ],
                  _sectionTitle('3', 'Amount'),
                  _previewPanel(),
                  _sectionTitle('4', 'Reason'),
                  TextField(
                    controller: _reason,
                    maxLines: 2,
                    enabled: !_creating,
                    onChanged: (_) {
                      if (_reasonError != null) setState(() => _reasonError = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g. Worker travelling home, requested his pay',
                      errorText: _reasonError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _creating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: canCreate ? _create : null,
                  icon: _creating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, color: Colors.white, size: 18),
                  label: Text(_creating ? 'Creating…' : 'Create off-cycle batch', style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: offCycleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
