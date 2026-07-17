import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart'; 
import 'package:team_flow/constants.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  Map<String, List<dynamic>> groupedAttendance = {}; 
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      isLoading = true;
      groupedAttendance.clear();
    });
    
    try {
      final response = await ApiConfig.dio.get('/admin/attendance/pending');
      
      Map<String, List<dynamic>> tempGrouped = {};
      for (var item in response.data['data']) {
        String rawDate = item['record_date']?.toString() ?? "1970-01-01";
        String date = rawDate.substring(0, 10); 
        
        if (!tempGrouped.containsKey(date)) {
          tempGrouped[date] = [];
        }
        tempGrouped[date]!.add(item);
      }

      setState(() {
        groupedAttendance = tempGrouped;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching data: $e");
      setState(() => isLoading = false);
    }
  }

  // الدالة المحدثة لحل مشكلة تعليق الزر وإظهار الرسالة
  Future<void> _review(int id, String status, {String? note}) async {
    // 1. تفعيل وضع التحميل لمنع الضغط المتكرر وتنبيه المستخدم
    setState(() => isLoading = true);
    
    try {
      print("Attempting to review ID: $id with status: $status"); 
      
      final response = await ApiConfig.dio.post('/admin/attendance/review', data: {
        'attendance_id': id,
        'status': status,
        'admin_note': note
      });
      
      print("Response data: ${response.data}"); 
      
      if (response.data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت العملية بنجاح'), backgroundColor: Colors.green),
        );
        // إعادة جلب البيانات لتحديث الشاشة واختفاء الكرت المستهدف
        await _fetchData(); 
      }
    } on DioException catch (e) {
      // 2. التقاط خطأ الـ 400 القادم من السيرفر وعرض الرسالة المناسبة
      String errorMessage = 'حدث خطأ غير متوقع';
      if (e.response != null && e.response!.data['message'] != null) {
        errorMessage = e.response!.data['message']; // سيعرض: "لا يمكن قبول السجل لأنه مرفوض..."
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ في الاتصال بالسيرفر'), backgroundColor: Colors.red),
      );
    } finally {
      // 3. إلغاء وضع التحميل بأي حال من الأحوال لفك تعليق الأزرار
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("مراجعة الحضور المجمعة")),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : ListView(
              children: groupedAttendance.keys.map((date) {
                return ExpansionTile(
                  title: Text("تاريخ: $date", style: const TextStyle(fontWeight: FontWeight.bold)),
                  children: groupedAttendance[date]!.map((item) {
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(item['full_name']),
                        subtitle: Text("الموقع: ${item['site_name']} | الحالة: ${item['status']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green), 
                              onPressed: () => _review(item['attendance_id'], 'Approved')
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red), 
                              onPressed: () async {
                                String? note = await _showRejectDialog(context);
                                if (note != null && note.trim().isNotEmpty) {
                                  _review(item['attendance_id'], 'Rejected', note: note);
                                }
                              }
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }

  Future<String?> _showRejectDialog(BuildContext context) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("سبب الرفض"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "اكتب السبب...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("تأكيد"))
        ],
      )
    );
  }
}