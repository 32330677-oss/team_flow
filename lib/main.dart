import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// استيراد ملف إعدادات الـ API لربط الـ navigatorKey
import 'constants.dart'; // تأكد أن المسار يوافق هيكل مشروعك

// استيراد الشاشات الخاصة بك
import 'screens/login_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/supervisor_dashboard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // دالة لفحص حالة تسجيل الدخول وتحديد الشاشة الافتتاحية
// دالة لفحص حالة تسجيل الدخول وتحديد الشاشة الافتتاحية (نسخة آمنة)
  Future<Widget> _checkLoginStatus() async {
    const storage = FlutterSecureStorage();
    
    try {
      // قراءة التوكن والـ Role من الذاكرة الآمنة
      String? token = await storage.read(key: 'jwt_token');
      String? role = await storage.read(key: 'user_role');

      // إذا كان التوكن موجوداً
      if (token != null && token.isNotEmpty) {
        if (role == 'Admin') {
          return const AdminDashboardScreen();
        } else if (role == 'Supervisor') {
          // قراءة الـ user_id ومعالجته بلطف باستخدام int.tryParse لمنع الـ Crash
          String? userIdRaw = await storage.read(key: 'user_id');
          int? supervisorId = userIdRaw != null ? int.tryParse(userIdRaw) : null;
          
          // إذا كانت البيانات تالفة (التوكن موجود لكن الـ ID ليس رقماً صالحاً)
          if (supervisorId == null) {
            await storage.deleteAll(); // تنظيف الذاكرة التالفة
            return const LoginScreen();
          }

          String? userName = await storage.read(key: 'user_name') ?? 'Supervisor';
          
          return SupervisorDashboard(
            supervisorId: supervisorId,
            supervisorName: userName,
          );
        }
      }
    } catch (e) {
      // لو حدث أي خطأ غير متوقع في قراءة التخزين، نمسح البيانات ونرجع لصفحة اللوجن بأمان
      await storage.deleteAll();
    }
    
    // في حال عدم وجود توكن أو أي حالة أخرى، نذهب لصفحة اللوجن
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team Flow',
      debugShowCheckedModeBanner: false,
      
      // ✅ ربط الـ navigatorKey لتمكين الخروج التلقائي عند خطأ 401
      navigatorKey: ApiConfig.navigatorKey,
      
      // ✅ ضبط الاتجاه ليصبح من اليسار لليمين (LTR) ليتناسب مع الواجهات الإنجليزية والـ Sidebar
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },

      locale: const Locale('en', 'US'), 
      supportedLocales: const [
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Cairo', // ✅ تم تغيير الخط هنا ليدعم الحروف العربية ويحل المشكلة نهائياً
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
      },
      // استخدام FutureBuilder لعرض شاشة انتظار بيضاء صغيرة أثناء فحص الذاكرة
      home: FutureBuilder<Widget>(
        future: _checkLoginStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xff1a2a6c)),
              ),
            );
          }
          return snapshot.data ?? const LoginScreen();
        },
      ),
    );
  }
}