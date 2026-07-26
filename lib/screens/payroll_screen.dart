import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart'; // استيراد إعدادات الـ ApiConfig المركزية

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({Key? key}) : super(key: key);

  @override
  _PayrollScreenState createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  bool _isLoading = false;
  List<dynamic> _payrollBatches = [];

  @override
  void initState() {
    super.initState();
    _fetchPayrollReports();
  }

  Future<void> _fetchPayrollReports() async {
    try {
      final response = await ApiConfig.dio.get('/admin/payroll/report');
      if (response.data['success'] == true) {
        setState(() {
          _payrollBatches = response.data['data'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
    }
  }

  Future<void> _generatePayroll() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end dates')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiConfig.dio.post(
        '/admin/payroll/generate',
        data: {
          'start_date': _startDateController.text,
          'end_date': _endDateController.text,
        },
      );

      if (response.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payroll generated successfully!')),
        );
        _fetchPayrollReports(); // إعادة تحديث القائمة
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating payroll: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        // استخدام الصيغة المحلية لمنع اختلاف الأيام بسبب الـ Timezone
        controller.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // جلب وعرض تفاصيل الدفعة عند الضغط عليها
  Future<void> _showBatchDetails(int batchId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // تم تعديل الرابط هنا ليتوافق تماماً مع مسار السيرفر /admin/payroll/batch/:batchId
      final response = await ApiConfig.dio.get('/admin/payroll/batch/$batchId');
      Navigator.pop(context); // إغلاق الـ Loading

      if (response.data['success'] == true) {
        final batch = response.data['batch'];
        final List workers = response.data['workers'];

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Batch Details #${batch['payroll_batch_id']}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Period: ${_formatDate(batch['start_date'])} to ${_formatDate(batch['end_date'])}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Workers Breakdown:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: workers.length,
                      itemBuilder: (context, index) {
                        final w = workers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  w['worker_name'] ?? 'Worker #${w['worker_id']}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Regular Hours: ${w['regular_hours_worked']} hrs'),
                                    Text('Overtime: ${w['overtime_hours_worked']} hrs'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Rates: \$${w['hourly_rate_snapshot']}/h | OT: \$${w['overtime_hourly_rate_snapshot']}/h',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                    Text(
                                      'Net: \$${w['net_salary']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  // المجموع الشامل في الأسفل
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Summary Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Workers: ${batch['total_workers']}'),
                            Text('Total Amount: \$${batch['total_amount']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading details: $e')),
      );
    }
  }

  String _formatDate(dynamic dateInput) {
    if (dateInput == null) return '';
    String str = dateInput.toString();
    if (str.contains('T')) return str.split('T')[0];
    return str;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Management - Team Flow')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _startDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Start Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _startDateController),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _endDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'End Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _endDateController),
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _generatePayroll,
                      child: const Text('Generate Payroll'),
                    ),
                  ),
            const SizedBox(height: 24),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payroll History Reports',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _payrollBatches.length,
                itemBuilder: (context, index) {
                  final batch = _payrollBatches[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text('Batch ID: #${batch['payroll_batch_id']} (${batch['status']})'),
                      subtitle: Text('Period: ${_formatDate(batch['start_date'])} to ${_formatDate(batch['end_date'])}\nWorkers: ${batch['total_workers']} | Total: \$${batch['total_amount']}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showBatchDetails(batch['payroll_batch_id']),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}