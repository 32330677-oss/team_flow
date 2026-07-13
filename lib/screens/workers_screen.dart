import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart'; // 👈 أضف نقطتين ليرجع خطوة للخلف ويبحث في مجلد lib
class WorkersScreen extends StatefulWidget {
  const WorkersScreen({Key? key}) : super(key: key);

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  // تهيئة دايو مع تحديد وقت انتهاء للطلب لمنع تعليق الشاشة
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  // دمج المسار المركزي مع موديول العمال ديناميكياً
  final String _apiUrl = '${ApiConfig.baseUrl}/workers'; 
  
  List<dynamic> _workers = [];
  bool _isLoading = true;

  // Controllers للـ Form
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _positionController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  // حساب إحصائيات سريعة للعدادات العليا
  int get _totalWorkers => _workers.length;
  int get _activeWorkers => _workers.where((w) => w['status'] == 'Active').length;

  // جلب العمال من الباكيند
  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _workers = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('حدث خطأ أثناء جلب العمال: $e', Colors.red);
    }
  }

  // إضافة عامل جديد للباكيند
  Future<void> _addWorker() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      _showSnackBar('يرجى ملء الحقول الأساسية: كود العامل والاسم الكامل', Colors.orange);
      return;
    }

    try {
      final response = await _dio.post(_apiUrl, data: {
        'worker_unique_id': code,
        'full_name': name,
        'phone_number': _phoneController.text.trim(),
        'nationality': _nationalityController.text.trim(),
        'job_position': _positionController.text.trim(),
        'notes': _notesController.text.trim(),
      });

      if (response.statusCode == 201) {
        Navigator.pop(context); // إغلاق الفورم
        _clearControllers();
        _fetchWorkers(); // تحديث القائمة فوراً
        _showSnackBar('تم إضافة العامل بنجاح', Colors.green);
      }
    } catch (e) {
      _showSnackBar('فشل الحفظ: تأكد من اتصال السيرفر أو عدم تكرار الكود.', Colors.red);
    }
  }

  void _clearControllers() {
    _codeController.clear();
    _nameController.clear();
    _phoneController.clear();
    _nationalityController.clear();
    _positionController.clear();
    _notesController.clear();
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: bgColor),
    );
  }

  // نافذة الإضافة بتصميم منسق ومعالجة حركة الكيبورد
  void _openAddWorkerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20, left: 20, right: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 15),
              const Text('إضافة عامل جديد للنظام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c))),
              const SizedBox(height: 15),
              TextField(controller: _codeController, decoration: const InputDecoration(labelText: 'كود العامل (ID) *', prefixIcon: Icon(Icons.badge))),
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الكامل *', prefixIcon: Icon(Icons.person))),
              TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone))),
              TextField(controller: _nationalityController, decoration: const InputDecoration(labelText: 'الجنسية', prefixIcon: Icon(Icons.flag))),
              TextField(controller: _positionController, decoration: const InputDecoration(labelText: 'المسمى الوظيفي', prefixIcon: Icon(Icons.work))),
              TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'ملاحظات إضافية', prefixIcon: Icon(Icons.note))),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: _addWorker,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: const Color(0xff1a2a6c),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('حفظ العامل في المنظومة', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // بناء كارد العدادات العلوي الصغير (KPI Widget)
  Widget _buildKPICard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('إدارة العمال مركزياً', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xff1a2a6c),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddWorkerSheet,
        backgroundColor: const Color(0xfffdbb2d),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // صف العدادات الذكية في أعلى الشاشة
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildKPICard('إجمالي العمال', '$_totalWorkers', const Color(0xff1a2a6c)),
                      _buildKPICard('النشطين حالياً', '$_activeWorkers', Colors.green),
                      _buildKPICard('المتوقفين', '${_totalWorkers - _activeWorkers}', Colors.red),
                    ],
                  ),
                ),
                Expanded(
                  child: _workers.isEmpty
                      ? const Center(child: Text('لا يوجد عمال مضافين حالياً في النظام'))
                      : ListView.builder(
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                            final worker = _workers[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xff1a2a6c).withOpacity(0.1),
                                  child: Text(
                                    worker['worker_unique_id'].toString(),
                                    style: const TextStyle(color: Color(0xff1a2a6c), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(worker['full_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                isThreeLine: true, // 👈 التموضع الصحيح داخل الـ ListTile
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '${worker['job_position'] ?? 'عامِل'} • ${worker['nationality'] ?? 'غير محدد'}\n📞 ${worker['phone_number'] ?? 'لا يوجد هاتف'}',
                                    style: TextStyle(color: Colors.grey[600], height: 1.3),
                                  ),
                                ),
                                trailing: Chip(
                                  label: Text(
                                    worker['status'] == 'Active' ? 'نشط' : 'متوقف',
                                    style: TextStyle(color: worker['status'] == 'Active' ? Colors.green[800] : Colors.red[800], fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: worker['status'] == 'Active' ? Colors.green[50] : Colors.red[50],
                                  side: BorderSide(color: worker['status'] == 'Active' ? Colors.green.shade200 : Colors.red.shade200),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}