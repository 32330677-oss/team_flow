import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart'; // ✅ استيراد ملف الإعدادات الموحد

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
  
  Map<int, String> _attendanceStates = {}; 

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  // 1. جلب قائمة العمال
  Future<void> _fetchWorkers() async {
    try {
      // ✅ استدعاء الـ dio الموحد مباشرة (يقرأ ويرسل التوكن والـ IP تلقائياً بالخلفية)
      final response = await ApiConfig.dio.get(
        '/attendance/sites/${widget.siteId}/workers', 
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _workers = response.data['data'];
          _isLoading = false;
          
          for (var worker in _workers) {
            _attendanceStates[worker['worker_id']] = 'Present';
          }
        });
      }
    } catch (e) {
      print("🚨 Error fetching workers: $e");
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ في جلب عمال الموقع أو غير مصرح لك')),
      );
    }
  }

  // 2. إرسال سجل الحضور والغياب
  Future<void> _submitAttendance() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Map<String, dynamic>> attendanceData = _attendanceStates.entries.map((entry) {
        return {
          'worker_id': entry.key,
          'status': entry.value,
        };
      }).toList();

      // ✅ استخدام الـ dio الموحد لعملية الـ Post أيضاً بكل بساطة وسرعة
      final response = await ApiConfig.dio.post(
        '/attendance',
        data: {
          'siteId': widget.siteId,
          'attendance': attendanceData,
        },
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ سجل الحضور والغياب بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); 
      }
    } catch (e) {
      print("🚨 Error submitting attendance: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء حفظ الحضور، يرجى المحاولة لاحقاً'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('حضور عمال: ${widget.siteName}'),
        backgroundColor: Colors.blueAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workers.isEmpty
              ? const Center(child: Text('لا يوجد عمال معينين في هذا الموقع حالياً.'))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _workers.length,
                        itemBuilder: (context, index) {
                          final worker = _workers[index];
                          final workerId = worker['worker_id'];
                          final currentStatus = _attendanceStates[workerId];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(
                                worker['full_name'],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(worker['job_position'] ?? 'عامل رئيسي'),
                              trailing: ToggleButtons(
                                borderRadius: BorderRadius.circular(8),
                                constraints: const BoxConstraints(minWidth: 70, minHeight: 36),
                                isSelected: [
                                  currentStatus == 'Present',
                                  currentStatus == 'Absent',
                                ],
                                onPressed: (int buttonIndex) {
                                  setState(() {
                                    _attendanceStates[workerId] = buttonIndex == 0 ? 'Present' : 'Absent';
                                  });
                                },
                                fillColor: currentStatus == 'Present' 
                                    ? Colors.green.withOpacity(0.2) 
                                    : Colors.red.withOpacity(0.2),
                                selectedColor: currentStatus == 'Present' ? Colors.green : Colors.red,
                                children: const [
                                  Text('حاضر 🟢', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('غائب 🔴', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _submitAttendance,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'حفظ وإرسال كشف الحضور',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}