// payroll_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:team_flow/constants.dart';

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
      final response = await ApiConfig.dio.get('/admin/sites');
      final responseData = response.data;
      List sitesList = [];
      if (responseData is List) {
        sitesList = responseData;
      } else if (responseData is Map && responseData['data'] is List) {
        sitesList = responseData['data'];
      } else if (responseData is Map && responseData['sites'] is List) {
        sitesList = responseData['sites'];
      }

      // تحويل الـ site_id ليكون int دائماً لتجنب مشاكل المقارنة
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
      _showSnack('Failed to load sites: $e', dangerColor);
    }
  }

  Future<void> _fetchPayrollReports() async {
    setState(() => _isLoadingBatches = true);
    try {
      String url = '/admin/payroll/report';
      if (_selectedSiteId != null) {
        url += '?site_id=$_selectedSiteId';
      }
      final response = await ApiConfig.dio.get(url);
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
        if (_selectedSiteId != null) 'site_id': _selectedSiteId,
      });
      if (response.data['success'] == true || response.statusCode == 200 || response.statusCode == 201) {
        _showSnack('Payroll batch generated successfully', Colors.green);
        _startDateController.clear();
        _endDateController.clear();
        _fetchPayrollReports();
      }
    } catch (e) {
      _showSnack('Error generating payroll: $e', dangerColor);
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

  Future<void> _selectDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDate(dynamic dateInput) {
    if (dateInput == null) return '';
    final str = dateInput.toString();
    return str.contains('T') ? str.split('T')[0] : str;
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

  Future<void> _exportBatchPdfReport(Map batch, List workers) async {
    try {
      final pdf = pw.Document();
      final ttfRegular = await PdfGoogleFonts.robotoRegular();
      final ttfBold = await PdfGoogleFonts.robotoBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.ltr,
          theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
          build: (context) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TEAM FLOW', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                pw.Text('Comprehensive Payroll Report', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Batch #${batch['payroll_batch_id']} • Period: ${_formatDate(batch['start_date'])} to ${_formatDate(batch['end_date'])}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.Divider(height: 20),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Worker Name', 'Regular Hours', 'Overtime Hours', 'Base Salary', 'Overtime Pay', 'Net Salary'],
              data: workers.map((w) {
                return [
                  w['worker_name'] ?? 'Worker #${w['worker_id']}',
                  w['regular_hours_worked']?.toString() ?? '0',
                  w['overtime_hours_worked']?.toString() ?? '0',
                  '\$${w['base_salary'] ?? 0}',
                  '\$${w['overtime_pay'] ?? 0}',
                  '\$${w['net_salary'] ?? 0}',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Workers: ${workers.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('Total Amount: \$${batch['total_amount'] ?? 0}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.indigo900)),
                ],
              ),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
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
      child: DropdownButton<int?>(
  value: _selectedSiteId,
  hint: const Text('All Sites'),
  isExpanded: true,
  items: [
    const DropdownMenuItem<int?>(
      value: null,
      child: Text('All Sites'),
    ),
    ..._sites.map((site) {
      return DropdownMenuItem<int?>(
        value: site['site_id'] as int?,
        child: Text(site['site_name'] ?? 'Unknown Site'),
      );
    }).toList(),
  ],
  onChanged: (value) {
    setState(() {
      _selectedSiteId = value;
    });
    // إعادة جلب التقارير تلقائياً عند تغيير الموقع
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
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Start Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  onTap: () => _selectDate(_startDateController),
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
      final pdf = pw.Document();
      final w = widget.worker;
      final b = widget.batch;

      final ttfRegular = await PdfGoogleFonts.robotoRegular();
      final ttfBold = await PdfGoogleFonts.robotoBold();

      final regularHours = _num(w['regular_hours_worked']);
      final overtimeHours = _num(w['overtime_hours_worked']);
      final hourlyRate = _num(w['hourly_rate_snapshot']);
      final overtimeRate = _num(w['overtime_hourly_rate_snapshot']);
      final baseSalary = _num(w['base_salary']);
      final overtimePay = _num(w['overtime_pay']);
      final netSalary = _num(w['net_salary']);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.ltr,
          theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TEAM FLOW', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Payslip', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Batch #${b['payroll_batch_id']}  •  Period: ${_fmtDate(b['start_date'])} to ${_fmtDate(b['end_date'])}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.Divider(height: 24),
              pw.Text(w['worker_name'] ?? 'Worker #${w['worker_id']}',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              _pdfRow('Regular Working Hours', '${regularHours.toStringAsFixed(2)} h'),
              _pdfRow('Overtime Working Hours', '${overtimeHours.toStringAsFixed(2)} h'),
              _pdfRow('Hourly Rate', '\$${hourlyRate.toStringAsFixed(2)}'),
              _pdfRow('Overtime Hourly Rate', '\$${overtimeRate.toStringAsFixed(2)}'),
              pw.Divider(height: 24),
              _pdfRow('Base Salary', '\$${baseSalary.toStringAsFixed(2)}'),
              _pdfRow('Overtime Pay', '\$${overtimePay.toStringAsFixed(2)}'),
              pw.Divider(height: 24),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('NET SALARY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('\$${netSalary.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Text('Generated on ${intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
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