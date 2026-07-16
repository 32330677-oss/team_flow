import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ استيراد الحزمة لحفظ التوكن
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class AuthService {
  final String baseUrl = "http://192.168.1.3:5000/api/auth";
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 10000), 
    receiveTimeout: const Duration(milliseconds: 10000), 
  ));

  // دالة إرسال طلب تسجيل الدخول للباكيند
Future<Map<String, dynamic>?> login(String email, String password) async {
  try {
    final response = await dio.post('$baseUrl/login', data: {
      'email': email,
      'password': password,
    });

    if (response.statusCode == 200) {
      final responseData = response.data;

      // 1. تنظيف أي توكن قديم في SharedPreferences لضمان عدم وجود تضارب
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('token'); 

      // 2. التوحيد: الحفظ في FlutterSecureStorage وباسم 'jwt_token'
      if (responseData != null && responseData['token'] != null) {
        const storage = FlutterSecureStorage();
        await storage.write(key: 'jwt_token', value: responseData['token']);
        print("🔑 Token saved securely to jwt_token and old token cleared.");
      }

      return responseData;
    }
  } catch (e) {
    print("❌ Login Error: $e");
    return null;
  }
  return null;
}
}