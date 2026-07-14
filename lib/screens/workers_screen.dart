import 'package:flutter/material.dart';
import '../constants.dart'; // ✅ الاستيراد الموحد

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({Key? key}) : super(key: key);

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  // ✅ لا داعي لتعريف Dio هنا، سنستخدم ApiConfig.dio

  List<dynamic> _workers = [];
  bool _isLoading = true;

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

  int get _totalWorkers => _workers.length;
  int get _activeWorkers => _workers.where((w) => w['status'] == 'Active').length;

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      // ✅ استخدام ApiConfig.dio الموحد
      final response = await ApiConfig.dio.get('/workers');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _workers = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('حدث خطأ أثناء جلب العمال', Colors.red);
    }
  }

  Future<void> _addWorker() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      _showSnackBar('يرجى ملء الحقول الأساسية', Colors.orange);
      return;
    }

    try {
      // ✅ التوكن يرسل تلقائياً بواسطة الـ Interceptor
      final response = await ApiConfig.dio.post('/workers', data: {
        'worker_unique_id': code,
        'full_name': name,
        'phone_number': _phoneController.text.trim(),
        'nationality': _nationalityController.text.trim(),
        'job_position': _positionController.text.trim(),
        'notes': _notesController.text.trim(),
      });

      if (response.statusCode == 201) {
        Navigator.pop(context);
        _clearControllers();
        _fetchWorkers();
        _showSnackBar('تم إضافة العامل بنجاح', Colors.green);
      }
    } catch (e) {
      _showSnackBar('فشل الحفظ: تأكد من عدم تكرار كود العامل', Colors.red);
    }
  }
 // دالة فتح النافذة
void _openAddWorkerSheet() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
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
            TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.note))),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _addWorker,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xff1a2a6c)),
              child: const Text('حفظ العامل', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}

// دالة الكارد
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

  // ... (باقي كود الـ UI يظل كما هو دون تغيير في المنطق)
  // [تم الاحتفاظ بنفس بنية الـ UI لضمان استقرار الواجهة]
  
  @override
  Widget build(BuildContext context) {
    // الواجهة تظل كما هي، تأكد فقط من استدعاء الدوال المحدثة أعلاه
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('إدارة العمال', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xff1a2a6c),
        centerTitle: true,
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
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildKPICard('إجمالي العمال', '$_totalWorkers', const Color(0xff1a2a6c)),
                      _buildKPICard('النشطين', '$_activeWorkers', Colors.green),
                      _buildKPICard('المتوقفين', '${_totalWorkers - _activeWorkers}', Colors.red),
                    ],
                  ),
                ),
                // بقية الـ ListView كما كانت تماماً
                Expanded(child: ListView.builder(
                    itemCount: _workers.length,
                    itemBuilder: (context, index) {
                      final worker = _workers[index];
                      return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                          child: ListTile(
                              title: Text(worker['full_name']),
                              subtitle: Text(worker['job_position'] ?? ''),
                              trailing: Text(worker['status'] == 'Active' ? 'نشط' : 'متوقف')
                          )
                      );
                    }
                )),
              ],
            ),
    );
  }
  
  // (أضف دالة _openAddWorkerSheet و _buildKPICard من كودك السابق هنا)
}