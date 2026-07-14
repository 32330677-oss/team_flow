import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'project_management_screen.dart'; // استيراد صفحة المشاريع الجديدة
import 'workers_screen.dart'; // تم إضافة استيراد صفحة العمال الجديدة هنا
import 'worker_assignment_screen.dart'; // استيراد شاشة التعيينات الجديدة
import 'hr_management_screen.dart'; // 👈 أضف هذا السطر هنا
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  // دالة تسجيل الخروج ومسح الذاكرة الآمنة
  Future<void> _handleLogout(BuildContext context) async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'jwt_token');
    await storage.delete(key: 'user_role');

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // مصفوفة تحتوي على الكاردات الأربعة الأساسية للنظام لتسهيل بنائها
    final List<Map<String, dynamic>> dashboardItems = [
      {
        'title': 'إدارة المشاريع',
        'icon': Icons.business,
        'color': const Color(0xff1a2a6c),
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProjectManagementScreen()),
          );
        },
      },
      {
        'title': 'توزيع وحركة العمال', // 👈 تم تغيير الاسم هنا
        'icon': Icons.alt_route,       // 👈 تم تغيير الأيقونة لتناسب الحركة والتوزيع
        'color': const Color(0xffb21f1f),
        'onTap': () {
          // 👈 تم الربط الفعلي هنا بشاشة التعيينات الجديدة بدلاً من تركه فارغاً
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WorkerAssignmentScreen()),
          );
        },
      },
      {
  'title': 'إدارة العمال والمشرفين', // يمكنك تغيير العنوان ليصبح أشمل
  'icon': Icons.people,
  'color': const Color(0xfffdbb2d),
  'onTap': () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HRManagementScreen()), // 👈 التوجيه للشاشة الوسيطة
    );
  },
},
      {
        'title': 'الحضور والرواتب',
        'icon': Icons.analytics,
        'color': Colors.green.shade700,
        'onTap': () {
          // سنبرمجها في المرحلة القادمة
        },
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المدير', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xff1a2a6c),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _handleLogout(context);
                      },
                      child: const Text('خروج', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أهلاً بك مجدداً، المدير',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c)),
            ),
            const SizedBox(height: 5),
            const Text(
              'اختر أحد الأقسام لإدارتها ومتابعة سير العمل:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                itemCount: dashboardItems.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final item = dashboardItems[index];
                  return InkWell(
                    onTap: item['onTap'],
                    borderRadius: BorderRadius.circular(15),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            colors: [item['color'], item['color'].withOpacity(0.8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item['icon'], size: 45, color: Colors.white),
                            const SizedBox(height: 12),
                            Text(
                              item['title'],
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
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