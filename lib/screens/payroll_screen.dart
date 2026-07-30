// payroll_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:printing/printing.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
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
  List<dynamic> _filteredBatches = [];
  List<dynamic> _sites = [];
  
  int? _selectedSiteId;

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
      final response = await ApiConfig.dio.get('/sites/all-sites'); // ✅ كان /admin/sites (404)
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
    // تحليل التاريخ بشكل محلي بحت لتجنب فرق توقيت الـ UTC
    final parsedDate = DateTime.parse(dateStr);
    return DateFormat('yyyy-MM-dd').format(DateTime(parsedDate.year, parsedDate.month, parsedDate.day));
  } catch (e) {
    return dateStr;
  }
}
Future<void> _fetchPayrollReports() async {
    setState(() => _isLoadingBatches = true);
    try {
      // ✅ استخدام Query Parameters بشكل نظيف وآمن مع Dio
      final queryParams = <String, dynamic>{};
      if (_selectedSiteId != null) {
        queryParams['site_id'] = _selectedSiteId;
      }

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
        return id.contains(q) || by.contains(q);
      }).toList();
    });
  }

Future<void> _generatePayroll() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      _showSnack('Please select start and end dates', Colors.orange);
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final response = await ApiConfig.dio.post('/admin/payroll/generate', data: {
        'start_date': _startDateController.text,
        'end_date': _endDateController.text,
        // ✅ يتم إرسال site_id فقط إن وجد، وعندما يكون All Sites (null) لن يتم إرساله ليحسب السيرفر كل المواقع
        if (_selectedSiteId != null) 'site_id': _selectedSiteId,
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
      
      // ✅ فحص إذا كان الخطأ قادماً من الـ Dio (أي استجابة من السيرفر)
      if (e is DioException && e.response?.data != null) {
        // أخذ الرسالة القادمة من الباك إند (مثل: تداخل التواريخ أو عدم وجود حضور)
        errorMessage = e.response?.data['message'] ?? errorMessage;
      }
      
      // عرضها بلون برتقالي تحذيري لطيف بدلاً من الأحمر القاتم للـ Exception
      _showSnack(errorMessage, Colors.orange[800]!);
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _markBatchAsPaid(int batchId) async {
    try {
      await ApiConfig.dio.patch('/admin/payroll/batch/$batchId/mark-paid');
      _showSnack('Batch marked as paid', Colors.green);
      _fetchPayrollReports();
    } catch (e) {
      _showSnack('Failed to update payment status', dangerColor);
    }
  }

// متغير لتخزين آخر تاريخ انتهى عنده آخر كشف رواتب (مثلاً تاريخ اليوم القادم المسموح)
DateTime? _lastBatchEndDate;

 Future<void> _fetchLastBatchDate() async {
  try {
    final response = await ApiConfig.dio.get('/admin/payroll/last-date');
    if (response.data['success'] && response.data['last_end_date'] != null) {
      // استخراج التاريخ كـ String أو DateTime بدقة
      String lastEndStr = response.data['last_end_date'].toString();
      if (lastEndStr.contains('T')) lastEndStr = lastEndStr.split('T')[0];
      
      DateTime parsedEnd = DateTime.parse(lastEndStr);
      DateTime nextStart = parsedEnd.add(const Duration(days: 1));
      
      setState(() {
        _lastBatchEndDate = parsedEnd;
        // تعبئة الـ Start Date تلقائياً باليوم التالي لآخر انتهاء ليكون مقفلاً وصحيحاً
        _startDateController.text = "${nextStart.year.toString().padLeft(4, '0')}-"
            "${nextStart.month.toString().padLeft(2, '0')}-"
            "${nextStart.day.toString().padLeft(2, '0')}";
      });
    }
  } catch (_) {}
}

Future<void> _selectDate(TextEditingController controller, {bool isStartDate = false}) async {
  // تحديد التاريخ الافتراضي عند فتح التقويم
  final initial = isStartDate && _lastBatchEndDate != null 
      ? _lastBatchEndDate!.add(const Duration(days: 1)) 
      : DateTime.now();

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2025),
    lastDate: DateTime(2035),
    // 🛠️ هنا السر: منع وتغميق الأيام القديمة والسماح فقط بالأيام اللاحقة لآخر كشف
    selectableDayPredicate: (DateTime day) {
      if (isStartDate && _lastBatchEndDate != null) {
        // إذا كان حقل بداية، امنع أي يوم يساوي أو يسبق آخر تاريخ انتهاء تم عمله
        // (يعني إذا آخر كشف انتهى في 17، سيتم إغلاق يوم 17 وما قبله، ويُفتح من 18 وطالع)
        return day.isAfter(_lastBatchEndDate!);
      }
      return true; // باقي الحقول مفتوحة عادي
    },
  );

  if (picked != null) {
    // تثبيت التاريخ كـ String خام تماماً بدون مشاكل إزاحة توقيت (UTC)
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
    // إذا كان النص يحتوي على وقت (T)، نقوم بأخذ الجزء الخاص بالتاريخ فقط كنص خام دون إدخاله في DateTime يتحكم به الـ UTC
    String str = dateInput.toString();
    if (str.contains('T')) {
      str = str.split('T')[0]; // يأخذ الجزء YYYY-MM-DD مباشرة كما أرسله السيرفر
    }
    
    // أو للتأكد تماماً وإعادة تنسيقه بشكل نظيف:
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
      final List workers = data['workers'] ?? [];
      _showBatchDetailsSheet(batch, workers);
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showSnack('Error loading batch details: $e', dangerColor);
    }
  }

  void _showBatchDetailsSheet(Map batch, List workers) {
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
                        Text('Batch #${batch['payroll_batch_id'] ?? ''}',
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: primaryColor)),
                        Text(
                          'Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: dangerColor),
                    tooltip: 'Export Batch PDF Report',
                    onPressed: () => _exportBatchPdfReport(batch, workers),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(batch['status']?.toString() ?? 'Pending'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: workers.length,
                itemBuilder: (context, index) {
                  final w = workers[index];
                  return _WorkerPayrollCard(
                    worker: w,
                    onPreview: () => _openPayslipPreview(batch, w),
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
                        Text('Total Workers: ${batch['total_workers'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Total Amount: \$${batch['total_amount'] ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 16)),
                      ],
                    ),
                  ),
                  if ((batch['status'] ?? 'Pending') != 'Paid')
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
              ),
            ),
          ],
        ),
      ),
    );
  }

// استبدل الدالة القديمة بالكامل بهذه — لا حاجة لـ pw.Document ولا PdfGoogleFonts هنا
Future<void> _exportBatchPdfReport(Map batch, List workers) async {
  try {
    final startDate = _formatDate(batch['start_date']);
    final endDate = _formatDate(batch['end_date']);
    final batchId = batch['payroll_batch_id'];

    final rowsHtml = workers.map((w) {
      final name = (w['worker_name'] ?? 'Worker #${w['worker_id']}').toString();
      return '''
        <tr>
          <td class="name-cell" dir="rtl">$name</td>
          <td>${w['regular_hours_worked'] ?? 0}</td>
          <td>\$${w['hourly_rate_snapshot'] ?? 0}</td>
          <td>${w['overtime_hours_worked'] ?? 0}</td>
          <td>\$${w['overtime_hourly_rate_snapshot'] ?? 0}</td>
          <td>\$${w['base_salary'] ?? 0}</td>
          <td>\$${w['overtime_pay'] ?? 0}</td>
          <td class="net">\$${w['net_salary'] ?? 0}</td>
        </tr>
      ''';
    }).join();

    final htmlContent = '''
    <!DOCTYPE html>
    <html lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;700&display=swap');
        body { font-family: 'Cairo', sans-serif; padding: 24px; color:#222; }
        .header { display:flex; justify-content:space-between; align-items:center;
                  border-bottom:2px solid #1a2a6c; padding-bottom:12px; }
        .logo { font-size:20px; font-weight:700; color:#1a2a6c; }
        .meta { font-size:11px; color:#777; margin-top:6px; }
        table { width:100%; border-collapse:collapse; margin-top:16px; font-size:11px; }
        th { background:#1a2a6c; color:#fff; padding:8px; text-align:center; }
        td { padding:7px; text-align:center; border-bottom:1px solid #eee; }
        .name-cell { text-align:right; font-weight:600; }
        .net { font-weight:700; color:#1a2a6c; }
        .summary { margin-top:16px; background:#f2f3f7; padding:12px; border-radius:6px;
                   display:flex; justify-content:space-between; font-weight:700; }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="logo">TEAM FLOW</div>
        <div>Comprehensive Payroll Report</div>
      </div>
      <div class="meta">Batch #$batchId &nbsp;•&nbsp; Period: $startDate to $endDate</div>
      <table>
        <thead>
          <tr>
            <th>Worker Name</th><th>Reg Hours</th><th>Hourly Rate</th>
            <th>OT Hours</th><th>OT Rate</th><th>Base Salary</th>
            <th>OT Pay</th><th>Net Salary</th>
          </tr>
        </thead>
        <tbody>$rowsHtml</tbody>
      </table>
      <div class="summary">
        <span>Total Workers: ${workers.length}</span>
        <span>Total Amount: \$${batch['total_amount'] ?? 0}</span>
      </div>
    </body>
    </html>
    ''';

    await Printing.layoutPdf(
      onLayout: (format) async => Printing.convertHtml(format: format, html: htmlContent),
    );
  } catch (e) {
    _showSnack('Error exporting batch report: $e', dangerColor);
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
    final isPaid = status == 'Paid';
    final color = isPaid ? Colors.green : Colors.orange;
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
      appBar: AppBar(
        title: const Text('Payroll Management'),
        backgroundColor: primaryColor,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchSites();
          await _fetchPayrollReports();
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
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Payroll History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryColor)),
                  const Spacer(),
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
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: (isPaid ? Colors.green : accentColor).withOpacity(0.15),
                                  child: Icon(Icons.receipt_long, color: isPaid ? Colors.green : primaryColor),
                                ),
                                title: Row(
                                  children: [
                                    Text('Batch #${batch['payroll_batch_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.picture_as_pdf, color: dangerColor, size: 20),
                                      tooltip: 'Export PDF',
                                      onPressed: () async {
                                        try {
                                          final res = await ApiConfig.dio.get('/admin/payroll/batch/${batch['payroll_batch_id']}');
                                          final rData = res.data;
                                          _exportBatchPdfReport(rData['batch'] ?? {}, rData['workers'] ?? []);
                                        } catch (e) {
                                          _showSnack('Could not load PDF data', dangerColor);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Period: ${_formatDate(batch['start_date'])} → ${_formatDate(batch['end_date'])}\n'
                                  'Workers: ${batch['total_workers']} • Total: \$${batch['total_amount']} • By: ${batch['generated_by'] ?? 'Admin'}',
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
    },
  )
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
    readOnly: true, // لمنع الكتابة اليدوية الخاطئة
    onTap: () => _selectDate(_startDateController, isStartDate: true), // عند الضغط يفتح التقويم
    decoration: const InputDecoration(
      labelText: 'Start Date',
      suffixIcon: Icon(Icons.calendar_today, size: 18), // أيقونة تقويم تدل أنه قابل للاختيار
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
        ],
      ),
    );
  }
}

class _WorkerPayrollCard extends StatelessWidget {
  final Map worker;
  final VoidCallback onPreview;

  const _WorkerPayrollCard({required this.worker, required this.onPreview});

  @override
  Widget build(BuildContext context) {
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
                  child: Text(worker['worker_name'] ?? 'Worker #${worker['worker_id']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff1a2a6c))),
                ),
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Payslip'),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat('Regular', '${worker['regular_hours_worked']} h', Colors.blueGrey),
                _miniStat('Overtime', '${worker['overtime_hours_worked']} h', Colors.orange.shade800),
                _miniStat('Net Pay', '\$${worker['net_salary']}', Colors.green.shade700, bold: true),
              ],
            ),
          ],
        ),
      ),
    );
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

class _PayslipDialog extends StatefulWidget {
  final Map batch;
  final Map worker;

  const _PayslipDialog({required this.batch, required this.worker});

  @override
  State<_PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends State<_PayslipDialog> {
  bool _isExporting = false;

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.contains('T') ? s.split('T')[0] : s;
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final w = widget.worker;
      final b = widget.batch;

      final regularHours = _num(w['regular_hours_worked']);
      final overtimeHours = _num(w['overtime_hours_worked']);
      final hourlyRate = _num(w['hourly_rate_snapshot']);
      final overtimeRate = _num(w['overtime_hourly_rate_snapshot']);
      final baseSalary = _num(w['base_salary']);
      final overtimePay = _num(w['overtime_pay']);
      final netSalary = _num(w['net_salary']);
      final workerName = w['worker_name'] ?? 'Worker #${w['worker_id']}';
      final batchId = b['payroll_batch_id'];
      final startDate = _fmtDate(b['start_date']);
      final endDate = _fmtDate(b['end_date']);
      final generatedDate = intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final htmlContent = '''
      <!DOCTYPE html>
      <html lang="en">
      <head>
          <meta charset="UTF-8">
          <style>
              @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;700&display=swap');
              body {
                  font-family: 'Cairo', sans-serif;
                  color: #333;
                  padding: 30px;
                  margin: 0;
                  direction: ltr;
              }
              .header {
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                  border-bottom: 2px solid #3f51b5;
                  padding-bottom: 15px;
              }
              .logo { font-size: 24px; font-weight: bold; color: #3f51b5; }
              .title { font-size: 16px; color: #666; }
              .meta { font-size: 12px; color: #888; margin-top: 5px; }
              .worker-name { font-size: 18px; font-weight: bold; margin-top: 20px; }
              .row {
                  display: flex;
                  justify-content: space-between;
                  padding: 8px 0;
                  border-bottom: 1px solid #eee;
                  font-size: 14px;
              }
              .net-box {
                  margin-top: 30px;
                  background-color: #f5f5f5;
                  padding: 15px;
                  border-radius: 8px;
                  display: flex;
                  justify-content: space-between;
                  font-size: 16px;
                  font-weight: bold;
              }
              .footer {
                  margin-top: 50px;
                  font-size: 10px;
                  color: #aaa;
                  text-align: center;
              }
          </style>
      </head>
      <body>
          <div class="header">
              <div class="logo">TEAM FLOW</div>
              <div class="title">Payslip</div>
          </div>
          <div class="meta">Batch #$batchId • Period: $startDate to $endDate</div>
          
          <div class="worker-name">$workerName</div>
          <br>
          
          <div class="row"><span>Regular Working Hours</span><span>${regularHours.toStringAsFixed(2)} h</span></div>
          <div class="row"><span>Overtime Working Hours</span><span>${overtimeHours.toStringAsFixed(2)} h</span></div>
          <div class="row"><span>Hourly Rate</span><span>\$${hourlyRate.toStringAsFixed(2)}</span></div>
          <div class="row"><span>Overtime Hourly Rate</span><span>\$${overtimeRate.toStringAsFixed(2)}</span></div>
          <div class="row"><span>Base Salary</span><span>\$${baseSalary.toStringAsFixed(2)}</span></div>
          <div class="row"><span>Overtime Pay</span><span>\$${overtimePay.toStringAsFixed(2)}</span></div>
          
          <div class="net-box">
              <span>NET SALARY</span>
              <span>\$${netSalary.toStringAsFixed(2)}</span>
          </div>
          
          <div class="footer">Generated on $generatedDate</div>
      </body>
      </html>
      ''';

      await Printing.layoutPdf(
        onLayout: (format) async => await Printing.convertHtml(
          format: format,
          html: htmlContent,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final b = widget.batch;
    final regularHours = _num(w['regular_hours_worked']);
    final overtimeHours = _num(w['overtime_hours_worked']);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text('Batch #${b['payroll_batch_id']} • Payslip', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
            _infoRow('Regular Hours', '${regularHours.toStringAsFixed(2)} h'),
            _infoRow('Overtime Hours', '${overtimeHours.toStringAsFixed(2)} h'),
            _infoRow('Base Salary', '\$${_num(w['base_salary']).toStringAsFixed(2)}'),
            _infoRow('Overtime Pay', '\$${_num(w['overtime_pay']).toStringAsFixed(2)}'),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Net Salary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('\$${_num(w['net_salary']).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff1a2a6c))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _isExporting ? null : _exportPdf,
                icon: _isExporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print, color: Colors.white, size: 18),
                label: Text(_isExporting ? 'Exporting...' : 'Export Payslip PDF', style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1a2a6c),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
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