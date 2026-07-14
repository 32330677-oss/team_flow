import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ استيراد الحزمة لحفظ التوكن

class AuthService {
  final String baseUrl = "http://192.168.1.3:5000/api/auth";
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 10000), 
    receiveTimeout: const Duration(milliseconds: 10000), 
  ));

  // دالة إرسال طلب تسجيل الدخول للباكيند
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await dio.post(
        '$baseUrl/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final responseData = response.data;

        // ✅ التعديل الاحترافي: حفظ التوكن في الذاكرة المحلية عند نجاح الدخول
        if (responseData != null && responseData['token'] != null) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', responseData['token']); // حفظ التوكن باسم 'token'
          print("🔑 Saved Token Successfully: ${responseData['token']}");
        }

        return responseData; // إرجاع التوكن وبيانات الأدمن بنجاح
      }
    } on DioException catch (e) {
      print("Login Error: ${e.response?.data ?? e.message}");
      return e.response?.data; 
    }
    return null;
  }
}