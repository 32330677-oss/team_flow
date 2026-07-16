import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart'; // لتنسيق التاريخ
import 'package:team_flow/constants.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  Map<String, List<dynamic>> groupedAttendance = {}; // تجميع البيانات حسب التاريخ
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
      // التاريخ القادم من السيرفر هو "2026-07-16"
      String rawDate = item['record_date']?.toString() ?? "1970-01-01";
      
      // نقوم بقص أول 10 أحرف (YYYY-MM-DD) فقط. 
      // هذا لن يلمس التوقيت نهائياً ولن يتأثر بتوقيت لبنان أو UTC.
      String date = rawDate.substring(0, 10); 
      print("Debug: record_date=${item['record_date']}, formatted=$date");
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
                            IconButton(icon: const Icon(Icons.check, color: Colors.green), 
                                onPressed: () => _review(item['attendance_id'], 'Approved')),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red), 
                                onPressed: () async {
                                  String? note = await _showRejectDialog(context);
                                  if (note != null) _review(item['attendance_id'], 'Rejected', note: note);
                                }),
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

Future<void> _review(int id, String status, {String? note}) async {
  try {
    print("Attempting to review ID: $id with status: $status"); // سجل العملية
    
    final response = await ApiConfig.dio.post('/admin/attendance/review', data: {
      'attendance_id': id,
      'status': status,
      'admin_note': note
    });
    
    print("Response data: ${response.data}"); // سجل رد السيرفر
    
    if (response.data['status'] == 'success') {
      _fetchData(); // تحديث القائمة فقط إذا نجح السيرفر
    }
  } catch (e) {
    // هنا سنعرف السبب الحقيقي (هل هو 401 Unauthorized؟ أم 500 Server Error؟)
    if (e is DioException) {
      print("Dio Error: ${e.response?.data}"); 
    }
    print("Error reviewing record: $e");
  }
}

Future<String?> _showRejectDialog(BuildContext context) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("سبب الرفض"),
      content: TextField(controller: controller, decoration: const InputDecoration(hintText: "اكتب السبب...")),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("تأكيد"))],
    ));
  }}