import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConfig {
static const String baseUrl = 'http://localhost:5000/api';
  // 1. هنا عرفنا المتغير باسم 'storage' (بدون _)
  static const FlutterSecureStorage storage = FlutterSecureStorage();

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 2. وهنا استدعيناه باسم 'storage' (بدون _)
          String? token = await storage.read(key: 'jwt_token');
          
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
}