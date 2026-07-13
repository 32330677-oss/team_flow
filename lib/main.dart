import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// استيراد الشاشات الخاصة بك (تأكد من صحة المسارات في مشروعك)
import 'screens/login_screen.dart';
import 'screens/admin_dashboard_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // دالة لفحص حالة تسجيل الدخول وتحديد الشاشة الافتتاحية
  Future<Widget> _checkLoginStatus() async {
    const storage = FlutterSecureStorage();
    
    // قراءة التوكن والـ Role من الذاكرة الآمنة
    String? token = await storage.read(key: 'jwt_token');
    String? role = await storage.read(key: 'user_role');

    // إذا كان التوكن موجوداً والمستخدم Admin، نتوجه مباشرة للـ Dashboard
    if (token != null && role == 'Admin') {
      return const AdminDashboardScreen();
    }
    
    // في حال عدم وجود توكن أو إذا كان الحساب مشرف (قيد التطوير)، يذهب لصفحة اللوجن
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team Flow',
      debugShowCheckedModeBanner: false,
      
      // إجبار التطبيق على دعم الاتجاه العربي RTL
      locale: const Locale('ar', 'AE'), 
      supportedLocales: const [
        Locale('ar', 'AE'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto', // يمكنك استبداله بخط عربي لاحقاً
      ),
      
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