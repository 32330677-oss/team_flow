import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
class SiteAttendanceScreen extends StatefulWidget {
  final int siteId;
  final String siteName;

  const SiteAttendanceScreen({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  @override
  _SiteAttendanceScreenState createState() => _SiteAttendanceScreenState();
}

class _SiteAttendanceScreenState extends State<SiteAttendanceScreen> {
  bool _isLoading = true;
  List<dynamic> _workers = [];
  List<dynamic> _rejectedRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. جلب العمال
      final workersRes = await ApiConfig.dio.get('/attendance/sites/${widget.siteId}/workers');
      // 2. جلب المرفوضات لكل المشرف
      final rejectedRes = await ApiConfig.dio.get('/attendance/rejected');

      if (!mounted) return;
      setState(() {
        _workers = workersRes.data['data'];
        // فلترة المرفوضات الخاصة بهذا الموقع فقط
        _rejectedRecords = (rejectedRes.data['data'] as List)
            .where((r) => r['site_id'] == widget.siteId)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ في تحميل البيانات')));
    }
  }

Future<void> _handleAction(String endpoint, int workerId) async {
    setState(() => _isLoading = true);
    try {
      print("Sending request to: $endpoint with workerId: $workerId");
      await ApiConfig.dio.post(endpoint, data: {
        'worker_id': workerId,
        'site_id': widget.siteId
      });
      
      await _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم التنفيذ!'), 
        backgroundColor: Colors.green
      ));
    } catch (e) {
      // هذه هي النسخة التي ستكشف لنا السبب الحقيقي للخطأ
      String errorMessage = 'خطأ غير معروف';
      
      if (e is DioException) {
        if (e.response != null && e.response!.data != null) {
          // هنا نصل لرسالة الخطأ التي يرسلها السيرفر فعلياً
          errorMessage = e.response!.data['message'] ?? e.response!.data.toString();
        } else {
          errorMessage = e.message ?? 'خطأ في الاتصال';
        }
      } else {
        errorMessage = e.toString();
      }

      print("ERROR DETAILS: $errorMessage");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
      ));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitDay() async {
    setState(() => _isLoading = true);
    try {
      await ApiConfig.dio.post('/attendance/submit', data: {'siteId': widget.siteId});
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل الإرسال النهائي')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.siteName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // --- منطقة المرفوضات (تظهر فقط إذا وُجد شيء) ---
                if (_rejectedRecords.isNotEmpty)
                  ExpansionTile(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    title: Text("${_rejectedRecords.length} سجل مرفوض يحتاج تصحيح", 
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    children: _rejectedRecords.map((record) => ListTile(
                      title: Text(record['full_name']),
                      subtitle: Text("ملاحظة الأدمن: ${record['admin_rejection_notes'] ?? 'لا يوجد'}"),
                      trailing: const Icon(Icons.edit, color: Colors.blue),
                      onTap: () { /* هنا تفتح شاشة التعديل الخاصة بك */ },
                    )).toList(),
                  ),

                // --- قائمة العمال ---
                Expanded(
                  child: ListView.builder(
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final worker = _workers[index];
                      final workerId = worker['worker_id'];
                      final attendanceId = worker['attendance_id'];
                    final bool isInBreak = worker['current_leave_id'] != null;
                 return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          title: Text(worker['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(worker['job_position'] ?? 'عامل'),
              const SizedBox(height: 10),
              
              // المنطق الذكي للأزرار
              attendanceId == null
                  ? ElevatedButton.icon(
                      onPressed: () => _handleAction('/attendance/checkin', workerId),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('تسجيل حضور'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    )
                  : Wrap(
                      spacing: 5,
                      children: [
                        // [هنا الجزء المعدل] نتحقق من حالة الاستراحة
                        isInBreak
                            ? TextButton.icon(
                                onPressed: () => _handleAction('/attendance/leave/end', workerId),
                                icon: const Icon(Icons.play_arrow, color: Colors.green),
                                label: const Text('إنهاء الاستراحة'),
                              )
                            : TextButton.icon(
                                onPressed: () => _handleAction('/attendance/leave/start', workerId),
                                icon: const Icon(Icons.timer_off, color: Colors.orange),
                                label: const Text('استراحة'),
                              ),
                        
                        // زر الخروج (يظهر دائماً إذا كان مسجل حضور)
                        TextButton.icon(
                          onPressed: () => _handleAction('/attendance/checkout', workerId),
                          icon: const Icon(Icons.exit_to_app, color: Colors.red),
                          label: const Text('إنهاء'),
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

                // --- زر الإرسال النهائي ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _submitDay,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('حفظ وإرسال نهائي للمراجعة'),
                  ),
                ),
              ],
            ),
    );
  }
}