import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';

class ApiConfig {
  static const String baseUrl = 'http://localhost:5000/api';
  
  // تعريف الـ storage بدون _
  static const FlutterSecureStorage storage = FlutterSecureStorage();

  // مفتاح عالمي للتحكم بالصفحات من داخل الـ Interceptor
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        // 1. إضافة التوكن مع كل طلب (Request)
        onRequest: (options, handler) async {
          String? token = await storage.read(key: 'jwt_token');
          
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        
        // 2. معالجة انتهاء صلاحية التوكن (خطأ 401)
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          if (error.response?.statusCode == 401) {
            // حذف كافة بيانات الجلسة المخزنة
            await storage.delete(key: 'jwt_token');
            await storage.delete(key: 'user_role');
            await storage.delete(key: 'user_id');
            await storage.delete(key: 'user_name');
            
            // إجبار التطبيق على الخروج وتوجيه المستخدم لصفحة تسجيل الدخول فوراً
            navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
          }
          return handler.next(error);
        },
      ),
    );
}