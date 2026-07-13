import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/auth_service.dart'; // تأكد من صحة مسار ملف الخدمة عندك
import 'admin_dashboard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  bool _isPasswordHidden = true;
  final _storage = const FlutterSecureStorage();
  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("الرجاء ملء جميع الحقول"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.login(email, password);

    setState(() {
      _isLoading = false;
    });

if (result != null && result['status'] == 'success') {
  String token = result['token'];
  String role = result['user']['role']; // سحب الـ role (Admin أو Supervisor)
  String fullName = result['user']['full_name'] ?? 'المستخدم';

  // 👈 حفظ البيانات في ذاكرة الهاتف المشفرة
  await _storage.write(key: 'jwt_token', value: token);
  await _storage.write(key: 'user_role', value: role);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("أهلاً بك يا $fullName، تم تسجيل الدخول بنجاح!"), backgroundColor: Colors.green),
  );

  // التوجيه الذكي (المبدئي) بناءً على الـ Role
  Future.delayed(const Duration(seconds: 1), () {
    if (role == 'Admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      );
    } else {
      // شاشة مؤقتة للمشرف لكي لا نتشتت الآن
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('لوحة المشرف')),
            body: const Center(child: Text('مرحباً بك يا مشرف. شاشتك قيد التطوير حالياً بعد إنهاء قسم الأدمن.')),
          ),
        ),
      );
    }
  });
} else {
      String errorMsg = result?['message'] ?? "فشل الاتصال بالسيرفر";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 1️⃣ تدرج لوني أنيق للخلفية يناسب هويّة التطبيق
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff1a2a6c), Color(0xff275d8c)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 2️⃣ شعار التطبيق أو أيقونة تعبيرية
                const Icon(
                  Icons.group_work_rounded,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                const Text(
                  "TEAM FLOW",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "إدارة المهام والعمل الجماعي بكل سلاسة",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 40),

                // 3️⃣ كارد أبيض يحتوي على حقول الإدخال
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "تسجيل الدخول",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff1a2a6c),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // حقل البريد الإلكتروني
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "البريد الإلكتروني",
                          prefixIcon: const Icon(Icons.email_outlined, color: Color(0xff275d8c)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // حقل كلمة المرور
                      TextField(
                        controller: _passwordController,
                        obscureText: _isPasswordHidden,
                        decoration: InputDecoration(
                          labelText: "كلمة المرور",
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xff275d8c)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordHidden = !_isPasswordHidden;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 4️⃣ زر تسجيل الدخول التفاعلي مع مؤشر التحميل
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff1a2a6c),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "دخول",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}