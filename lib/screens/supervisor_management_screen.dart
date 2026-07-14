import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart'; // تأكد من مسار ملف الـ constants لديك لاستيراد ApiConfig

class SupervisorManagementScreen extends StatefulWidget {
  const SupervisorManagementScreen({Key? key}) : super(key: key);

  @override
  State<SupervisorManagementScreen> createState() => _SupervisorManagementScreenState();
}

class _SupervisorManagementScreenState extends State<SupervisorManagementScreen> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  // استخدام المسار المركزي للباكيند الذي قمنا بتهيئته للمشرفين
  final String _apiUrl = '${ApiConfig.baseUrl}/users/supervisors';

  List<dynamic> _supervisors = [];
  bool _isLoading = true;

  // أجهزة التحكم بالمدخلات لنموذج إضافة مشرف جديد
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSupervisors();
  }

  // حساب الإحصائيات الفورية للمشرفين
  int get _totalSupervisors => _supervisors.length;
  int get _activeSupervisors => _supervisors.where((s) => s['status'] == 'Active').length;
  int get _inactiveSupervisors => _totalSupervisors - _activeSupervisors;

  // 1. جلب قائمة المشرفين من الباكيند
  Future<void> _fetchSupervisors() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _supervisors = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('حدث خطأ أثناء جلب قائمة المشرفين', Colors.red);
    }
  }

  // 2. إرسال طلب إنشاء مشرف جديد للباكيند
  Future<void> _addSupervisor() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await _dio.post(_apiUrl, data: {
        'full_name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      });

      if (response.statusCode == 201 && response.data['status'] == 'success') {
        Navigator.pop(context); // إغلاق نافذة الإدخال
        _clearControllers();
        _fetchSupervisors(); // تحديث القائمة فوراً
        _showSnackBar('تم إضافة المشرف بنجاح وتفعيل حسابه', Colors.green);
      }
    } catch (e) {
      String errorMessage = 'فشل حفظ المشرف، تأكد من أن اسم المستخدم غير مكرر.';
      if (e is DioException && e.response != null) {
        errorMessage = e.response!.data['message'] ?? errorMessage;
      }
      _showSnackBar(errorMessage, Colors.red);
    }
  }

  // 3. تعديل حالة المشرف (نشط / متوقف) وإرسالها للباكيند
  Future<void> _toggleStatus(int userId, String currentStatus) async {
    final newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    try {
      final response = await _dio.patch('$_apiUrl/$userId/status', data: {
        'status': newStatus,
      });

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        _fetchSupervisors(); // إعادة جلب البيانات لتحديث الحالة على الواجهة
        _showSnackBar(
          newStatus == 'Active' ? 'تم تفعيل حساب المشرف' : 'تم تعطيل حساب المشرف بنجاح',
          Colors.orange,
        );
      }
    } catch (e) {
      _showSnackBar('فشل تعديل حالة المشرف، يرجى التحقق من اتصال السيرفر', Colors.red);
    }
  }

  void _clearControllers() {
    _nameController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: bgColor),
    );
  }

  // نافذة (BottomSheet) منسقة لإضافة المشرف
  void _openAddSupervisorSheet() {
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
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 15),
                const Text(
                  'إنشاء حساب مشرف جديد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xffb21f1f)),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل للمشرف *', prefixIcon: Icon(Icons.person)),
                  validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال الاسم الكامل' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم للـ Login *', prefixIcon: Icon(Icons.alternate_email)),
                  validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال اسم مستخدم فريد' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الحساب *', prefixIcon: Icon(Icons.lock)),
                  validator: (val) => val == null || val.length < 6 ? 'كلمة المرور يجب أن لا تقل عن 6 خانات' : null,
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: _addSupervisor,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xffb21f1f),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('حفظ حساب المشرف وتفعيله', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // بناء كروت الإحصائيات (KPI Widget) بلون متناسق
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
        title: const Text('إدارة المشرفين (Supervisors)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xffb21f1f),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSupervisorSheet,
        backgroundColor: const Color(0xfffdbb2d),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // صف العدادات الإحصائية للمشرفين
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildKPICard('إجمالي المشرفين', '$_totalSupervisors', const Color(0xffb21f1f)),
                      _buildKPICard('النشطين حالياً', '$_activeSupervisors', Colors.green),
                      _buildKPICard('المعطلين', '$_inactiveSupervisors', Colors.red),
                    ],
                  ),
                ),
                Expanded(
                  child: _supervisors.isEmpty
                      ? const Center(child: Text('لا يوجد مشرفين مسجلين في النظام حالياً'))
                      : ListView.builder(
                          itemCount: _supervisors.length,
                          itemBuilder: (context, index) {
                            final supervisor = _supervisors[index];
                            final isUserActive = supervisor['status'] == 'Active';

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xffb21f1f).withOpacity(0.1),
                                  child: const Icon(Icons.person, color: Color(0xffb21f1f)),
                                ),
                                title: Text(
                                  supervisor['full_name'] ?? 'مستخدم بدون اسم',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    'اسم المستخدم: @${supervisor['username'] ?? 'غير محدد'}\nالصلاحية: مشرف موقع',
                                    style: TextStyle(color: Colors.grey[600], height: 1.3),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // نص الحالة
                                    Text(
                                      isUserActive ? 'نشط' : 'معطل',
                                      style: TextStyle(
                                        color: isUserActive ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // سويتش لتغيير حالة حساب المشرف فوراً
                                    Switch(
                                      value: isUserActive,
                                      activeColor: Colors.green,
                                      inactiveThumbColor: Colors.red,
                                      inactiveTrackColor: Colors.red.shade100,
                                      onChanged: (val) {
                                        _toggleStatus(
                                          supervisor['user_id'],
                                          supervisor['status'],
                                        );
                                      },
                                    ),
                                  ],
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