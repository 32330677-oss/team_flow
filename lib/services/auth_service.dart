import 'package:dio/dio.dart';

class AuthService {
  // ملاحظة: 10.0.2.2 هو الآي بي الذي يفهمه إيموليتر الأندرويد للوصول للـ localhost على لابتوبك
final String baseUrl = "http://192.168.1.3:5000/api/auth";
  final Dio dio = Dio(BaseOptions(
  connectTimeout: const Duration(milliseconds: 10000), // 10 ثوانٍ كاملة للاتصال
  receiveTimeout: const Duration(milliseconds: 10000), // 10 ثوانٍ لاستلام البيانات
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
        return response.data; // إرجاع التوكن وبيانات الأدمن بنجاح
      }
    } on DioException catch (e) {
      print("Login Error: ${e.response?.data ?? e.message}");
      return e.response?.data; 
    }
    return null;
  }
}