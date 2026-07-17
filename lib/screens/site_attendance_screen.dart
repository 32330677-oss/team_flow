import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import 'rejected_records_screen.dart';
import 'package:intl/intl.dart';
class SiteAttendanceScreen extends StatefulWidget {
  final int siteId;
  final String siteName;

  const SiteAttendanceScreen({super.key, required this.siteId, required this.siteName});

  @override
  _SiteAttendanceScreenState createState() => _SiteAttendanceScreenState();
}

class _SiteAttendanceScreenState extends State<SiteAttendanceScreen> {
  bool _isLoading = true;
  List<dynamic> _workers = [];

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/attendance/sites/${widget.siteId}/workers');
      if (!mounted) return;
      setState(() {
        _workers = response.data['data'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ في تحميل العمال')));
    }
  }

  Future<void> _handleAction(String endpoint, int workerId) async {
    setState(() => _isLoading = true);
    try {
      await ApiConfig.dio.post(endpoint, data: {'worker_id': workerId, 'site_id': widget.siteId});
      await _fetchWorkers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ في الاتصال'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

 Future<void> _submitDay() async {
  // 1. إضافة تأكيد قبل الإرسال النهائي
  bool? confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تأكيد الإرسال'),
      content: const Text('هل أنت متأكد من إنهاء اليوم وإرسال السجلات للمراجعة؟ لا يمكن التراجع عن هذا الإجراء.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
      ],
    ),
  );

  if (confirm != true) return;

  setState(() => _isLoading = true);
  try {
    // إرسال الطلب للسيرفر
    final response = await ApiConfig.dio.post('/attendance/submit', data: {'siteId': widget.siteId});
    
    // إذا نجح، نقوم بتحديث القائمة بدلاً من إغلاق الشاشة فوراً
    // (بفضل تعديل السيرفر، العمال الذين تم إرسالهم سيختفون تلقائياً)
    await _fetchWorkers();
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال اليوم بنجاح'), backgroundColor: Colors.green));
    
    // إذا أصبحت القائمة فارغة، نخرج من الشاشة
    if (_workers.isEmpty) Navigator.pop(context);
    
  } catch (e) {
    // معالجة رسالة الخطأ القادمة من السيرفر (مثل: لم يسجل الجميع خروجهم)
    String errorMsg = 'فشل الإرسال النهائي';
    if (e is DioException && e.response?.data['message'] != null) {
      errorMsg = e.response!.data['message'];
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
  } finally {
    setState(() => _isLoading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    String formattedDate = DateFormat('yyyy/MM/dd', 'ar').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        // العنوان هنا مباشرة
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.siteName, style: const TextStyle(fontSize: 18)),
            Text(
              'تاريخ اليوم: $formattedDate',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ), actions: [
        IconButton(icon: const Icon(Icons.warning_amber_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedRecordsScreen()))),
      ]),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _workers.length,
            itemBuilder: (context, index) {
              final worker = _workers[index];
              return Card(
                child: ListTile(
                  title: Text(worker['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(worker['job_position'] ?? 'عامل'),
                    worker['attendance_id'] == null 
                      ? ElevatedButton.icon(onPressed: () => _handleAction('/attendance/checkin', worker['worker_id']), icon: const Icon(Icons.check_circle), label: const Text('تسجيل حضور'))
                      : Wrap(spacing: 5, children: [
                          TextButton.icon(onPressed: () => _handleAction(worker['current_leave_id'] != null ? '/attendance/leave/end' : '/attendance/leave/start', worker['worker_id']), icon: Icon(worker['current_leave_id'] != null ? Icons.play_arrow : Icons.timer_off), label: Text(worker['current_leave_id'] != null ? 'إنهاء الاستراحة' : 'استراحة')),
                          TextButton.icon(onPressed: () => _handleAction('/attendance/checkout', worker['worker_id']), icon: const Icon(Icons.exit_to_app), label: const Text('إنهاء')),
                        ]),
                  ]),
                ),
              );
            },
          )),
          Padding(padding: const EdgeInsets.all(16.0), child: ElevatedButton(onPressed: _submitDay, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: const Text('حفظ وإرسال نهائي للمراجعة'))),
        ],
      ),
    );
  }
}