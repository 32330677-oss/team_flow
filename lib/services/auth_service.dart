import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl =
      'https://team-flow-backend-f15z.onrender.com/api/auth/';

  static const FlutterSecureStorage storage = FlutterSecureStorage( );

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  /// تسجيل الدخول عبر Backend الموجود على Render
  Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await dio.post(
        'login',
        data: <String, dynamic>{
          'email': email.trim(),
          'password': password,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final responseData = Map<String, dynamic>.from(
        response.data as Map,
      );

      final token = responseData['token'];

      if (token == null || token.toString().trim().isEmpty) {
        print('Login succeeded, but no token was returned.');
        return responseData;
      }

      final prefs = await SharedPreferences.getInstance();

      // حذف أي Token قديم حتى لا يحدث تضارب بين الجلسات.
      await prefs.remove('token');
      await prefs.remove('jwt_token');

      // حفظ التوكن في التخزين الآمن فقط.
      await storage.write(
        key: 'jwt_token',
        value: token.toString(),
      );

      print('Token saved securely.');

      return responseData;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;

      print('Login failed. HTTP status: $statusCode');
      print('Login response: $responseData');

      return _loginError(error);
    } catch (error) {
      print('Login error: $error');
      return _errorResult(
        'UNKNOWN',
        'Something went wrong. Please try again.',
      );
    }
  }

  /// Turns a failed login request into a clear message for the login screen.
  /// The screen reads `message`; `code` tells it what kind of failure it was.
  Map<String, dynamic> _loginError(DioException error) {
    final response = error.response;

    // No answer from the server at all.
    if (response == null) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return _errorResult(
            'TIMEOUT',
            'The server is taking too long to respond. Please try again in a moment.',
          );
        default:
          return _errorResult(
            'NO_CONNECTION',
            'Cannot reach the server. Check your internet connection and try again.',
          );
      }
    }

    final status = response.statusCode ?? 0;
    String? serverMessage;
    final data = response.data;
    if (data is Map && data['message'] != null) {
      final text = data['message'].toString().trim();
      if (text.isNotEmpty) serverMessage = text;
    }

    if (status == 401) {
      return _errorResult(
        'INVALID_CREDENTIALS',
        'Incorrect email or password.',
      );
    }
    if (status == 403) {
      return _errorResult(
        'ACCOUNT_DISABLED',
        serverMessage ?? 'This account is deactivated. Please contact the administrator.',
      );
    }
    if (status == 429) {
      return _errorResult(
        'TOO_MANY_ATTEMPTS',
        serverMessage ?? 'Too many failed login attempts. Please wait 15 minutes and try again.',
      );
    }
    if (status >= 500) {
      return _errorResult(
        'SERVER_ERROR',
        'The server is temporarily unavailable. Please try again in a few minutes.',
      );
    }
    return _errorResult(
      'REQUEST_FAILED',
      serverMessage ?? 'Login failed. Please try again.',
    );
  }

  Map<String, dynamic> _errorResult(String code, String message) {
    return <String, dynamic>{
      'status': 'error',
      'code': code,
      'message': message,
    };
  }

  /// قراءة التوكن المحفوظ عند فتح التطبيق.
  Future<String?> getToken() async {
    return storage.read(key: 'jwt_token');
  }

  /// حذف الجلسة الحالية عند تسجيل الخروج.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('jwt_token');
    await storage.delete(key: 'jwt_token');
  }
}
