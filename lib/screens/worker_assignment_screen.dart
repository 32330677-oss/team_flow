import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';

class WorkerAssignmentScreen extends StatefulWidget {
  const WorkerAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<WorkerAssignmentScreen> createState() => _WorkerAssignmentScreenState();
}

class _WorkerAssignmentScreenState extends State<WorkerAssignmentScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  List<dynamic> _assignments = [];
  List<dynamic> _workers = [];
  List<dynamic> _sites = []; // جلب المواقع الحقيقية من جدول sites
  bool _isLoading = true;

  int? _selectedWorkerId; // الحقل الحقيقي لربط المفتاح الأجنبي
  String? _selectedWorkerName;
  int? _selectedSiteId; // الحقل الحقيقي للموقع
  String? _selectedSiteName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // جلب البيانات من السيرفر بشكل مستقل لتفادي تجميد التطبيق
// استرجاع المسار الصحيح المسمى projects في السيرفر لإنهاء خطأ 404
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final resWorkers = await _dio.get('${ApiConfig.baseUrl}/workers');
      if (resWorkers.statusCode == 200) _workers = resWorkers.data['data'] ?? [];
    } catch (e) { debugPrint('خطأ عمال: $e'); }

    try {
      // تعديل المسار إلى projects بناءً على كود الباكيند الفعلي لديك
      final resSites = await _dio.get('${ApiConfig.baseUrl}/projects'); 
      if (resSites.statusCode == 200) _sites = resSites.data['data'] ?? [];
    } catch (e) { debugPrint('خطأ مشاريع: $e'); }

    try {
      final resAssignments = await _dio.get('${ApiConfig.baseUrl}/assignments');
      if (resAssignments.statusCode == 200) _assignments = resAssignments.data['data'] ?? [];
    } catch (e) { debugPrint('خطأ تعيينات: $e'); }

    setState(() => _isLoading = false);
  }

  // إرسال التعيين للحفظ الدائم بالداتابيز
  Future<void> _createAssignment() async {
    if (_selectedWorkerId == null || _selectedSiteId == null) {
      _showSnackBar('يرجى تحديد العامل والموقع أولاً', Colors.orange);
      return;
    }

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/assignments',
        data: {
          'worker_id': _selectedWorkerId,
          'site_id': _selectedSiteId,
          'contract_id': null, // اختياري في الداتابيز
          'assigned_by_user_id': 1 // قيمة افتراضية للآدمن
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pop(context);
        _loadData(); // تحديث فوري للشاشة والقراءة من الداتابيز مباشرة
        _showSnackBar('تم حفظ التعيين في الداتابيز بنجاح!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('فشل حفظ البيانات في قاعدة البيانات', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _openAddSheet() {
    setState(() {
      _selectedWorkerId = null;
      _selectedWorkerName = null;
      _selectedSiteId = null;
      _selectedSiteName = null;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text('توزيع عامل على موقع جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
              ),
              const SizedBox(height: 20),
              
              // 1. اختيار العامل
              const Text('اختر العامل:', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<int>(
                hint: const Text('اختر العامل المستهدف'),
                value: _selectedWorkerId,
                items: _workers.map((w) => DropdownMenuItem<int>(
                  value: int.tryParse(w['worker_id'].toString()), 
                  child: Text(w['full_name'] ?? 'بدون اسم')
                )).toList(),
                onChanged: (val) {
                  final selected = _workers.firstWhere((w) => int.tryParse(w['worker_id'].toString()) == val);
                  setSheetState(() {
                    _selectedWorkerId = val;
                    _selectedWorkerName = selected['full_name'];
                  });
                },
              ),
              const SizedBox(height: 15),

              // 2. اختيار الموقع
              const Text('اختر الموقع / السايت:', style: TextStyle(fontWeight: FontWeight.bold)),
DropdownButtonFormField<int>(
  hint: const Text('اختر الموقع الحقيقي'),
  value: _selectedSiteId,
  items: _sites.map((s) => DropdownMenuItem<int>(
    value: int.tryParse(s['project_id'].toString()), // 👈 استخدام project_id الحقيقي
    child: Text(s['project_name'] ?? 'بدون اسم')    // 👈 استخدام project_name الحقيقي
  )).toList(),
  onChanged: (val) {
    final selected = _sites.firstWhere((s) => int.tryParse(s['project_id'].toString()) == val);
    setSheetState(() {
      _selectedSiteId = val;
      _selectedSiteName = selected['project_name'];
    });
  },
),
              const SizedBox(height: 25),

              ElevatedButton(
                onPressed: _createAssignment,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xff1a2a6c)),
                child: const Text('حفظ في قاعدة البيانات', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('توزيع وحركة العمال', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        backgroundColor: const Color(0xff1a2a6c),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSheet, 
        backgroundColor: const Color(0xffb21f1f),
        child: const Icon(Icons.link, color: Colors.white)
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(child: Text('لا توجد تعيينات مخزنة حالياً في الداتابيز.'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final item = _assignments[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xff1a2a6c),
                            child: Icon(Icons.person_pin, color: Colors.white),
                          ),
                          title: Text(item['worker_name'] ?? 'عامل غير معروف', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              '📍 الموقع: ${item["project_name"] ?? "غير محدد"}\n📅 التاريخ: ${item["start_date"] ?? ""}', 
                              style: const TextStyle(height: 1.3)
                            ),
                          ),
                          trailing: Chip(
                            label: const Text('نشط', style: TextStyle(fontSize: 12, color: Colors.green)), 
                            backgroundColor: Colors.green.shade100
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}