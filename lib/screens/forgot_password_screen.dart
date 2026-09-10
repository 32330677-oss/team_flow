import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmittingEmail = false;
  bool _isSubmittingReset = false;
  bool _codeSent = false;
  bool _hideNew = true;
  bool _hideConfirm = true;

  static const Color _primaryDark = Color(0xff1a2a6c);

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() => _isSubmittingEmail = true);

    try {
      await ApiConfig.dio.post('/auth/forgot-password', data: {
        'email': _emailController.text.trim(),
      });

      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _isSubmittingEmail = false;
      });
      _showSnack('If this email is registered, a code has been sent.', Colors.green);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingEmail = false);
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Something went wrong. Please try again.')
          : 'Connection error. Please try again.';
      _showSnack(msg, Colors.red);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmittingEmail = false);
      _showSnack('Connection error. Please try again.', Colors.red);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;

    setState(() => _isSubmittingReset = true);

    try {
      await ApiConfig.dio.post('/auth/reset-password-otp', data: {
        'email': _emailController.text.trim(),
        'otp': _otpController.text.trim(),
        'new_password': _newPasswordController.text,
      });

      if (!mounted) return;
      _showSnack('Password reset successfully. Please log in.', Colors.green);
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingReset = false);
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to reset password.')
          : 'Connection error. Please try again.';
      _showSnack(msg, Colors.red);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmittingReset = false);
      _showSnack('Connection error. Please try again.', Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password', style: TextStyle(color: Colors.white)),
        backgroundColor: _primaryDark,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _codeSent ? _buildResetForm() : _buildEmailForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset_rounded, size: 64, color: _primaryDark),
          const SizedBox(height: 16),
          const Text(
            'Enter the email address linked to your account and we will send you a verification code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Please enter your email';
              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(val.trim());
              return ok ? null : 'Please enter a valid email';
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmittingEmail ? null : _sendCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSubmittingEmail
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Send Code', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mark_email_read_rounded, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Enter the 6-digit code sent to ${_emailController.text.trim()} and set your new password.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Verification Code',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            validator: (val) {
              if (val == null || !RegExp(r'^\d{6}$').hasMatch(val.trim())) {
                return 'Please enter the 6-digit code';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _newPasswordController,
            obscureText: _hideNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                icon: Icon(_hideNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hideNew = !_hideNew),
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Please enter a new password';
              if (val.length < 8) return 'Password must be at least 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _hideConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_person_outlined),
              suffixIcon: IconButton(
                icon: Icon(_hideConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
              ),
            ),
            validator: (val) {
              if (val != _newPasswordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmittingReset ? null : _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSubmittingReset
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Reset Password', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isSubmittingEmail
                ? null
                : () {
                    setState(() => _codeSent = false);
                  },
            child: const Text('Use a different email', style: TextStyle(color: _primaryDark)),
          ),
          TextButton(
            onPressed: _isSubmittingEmail ? null : _sendCode,
            child: const Text('Resend Code', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}