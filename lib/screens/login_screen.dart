import 'package:flutter/material.dart';
import '../widgets/admin_shell.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'staff_supervisor_dashboard.dart';
import '../services/auth_service.dart';
import 'supervisor_dashboard.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _isPasswordHidden = true;
  final _storage = const FlutterSecureStorage();

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const Color _navy = Color(0xff1a2a6c);
  static const Color _navyLight = Color(0xff2a4d8f);
  static const Color _gold = Color(0xfffdbb2d);
  static const Color _ink = Color(0xff1f2937);
  static const Color _muted = Color(0xff6b7280);
  static const Color _line = Color(0xffe5e7eb);

  @override
  void initState() {
    super.initState();
    AdminChromeState.setEnabled(false); // no Admin sidebar on the login screen
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    // Put the cursor in the email field so the user can type right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // Enter in the email field: go to the password, or sign in if it is filled.
  void _onEmailSubmitted(String _) {
    if (_passwordController.text.isEmpty) {
      _passwordFocus.requestFocus();
    } else {
      _handleLogin();
    }
  }

  // ---------------------------------------------------------------------
  // Login logic: same endpoint, same storage keys, same role navigation.
  // ---------------------------------------------------------------------
  Future<void> _handleLogin() async {
    if (_isLoading) return; // ignore Enter / clicks while a request is running

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showSnack("Please enter your email", Colors.orange);
      _emailFocus.requestFocus();
      return;
    }
    if (password.isEmpty) {
      _showSnack("Please enter your password", Colors.orange);
      _passwordFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    Map<String, dynamic>? result;
    try {
      result = await _authService.login(email, password);
    } catch (_) {
      result = null;
    }

    if (!mounted) return;

    if (result != null && result['status'] == 'success') {
      final user = result['user'] as Map;
      final String token = result['token'].toString();
      final String role = user['role'].toString(); // Admin / Supervisor / StaffSupervisor
      final String fullName = (user['full_name'] ?? 'User').toString();

      final userIdRaw = user['user_id'] ?? user['id'];
      final int supervisorId =
          (userIdRaw != null) ? int.tryParse(userIdRaw.toString()) ?? 0 : 0;

      await _storage.write(key: 'jwt_token', value: token);
      await _storage.write(key: 'user_role', value: role);
      await _storage.write(key: 'user_id', value: supervisorId.toString());
      await _storage.write(key: 'user_name', value: fullName);

      if (!mounted) return;
      _showSnack("Welcome, $fullName!", Colors.green);

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        if (role == 'Admin') {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (context) => const AdminShell()));
        } else if (role == 'StaffSupervisor') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => StaffSupervisorDashboard(
                supervisorId: supervisorId,
                supervisorName: (user['full_name'] ?? 'Staff Supervisor').toString(),
              ),
            ),
          );
        } else {
          // role == 'Supervisor' (worker supervisor)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SupervisorDashboard(
                supervisorId: supervisorId,
                supervisorName:
                    (user['full_name'] ?? user['username'] ?? 'New Supervisor').toString(),
              ),
            ),
          );
        }
      });
    } else {
      setState(() => _isLoading = false);
      final String errorMsg =
          (result?['message'] ?? "Incorrect email or password").toString();
      final String? code = result?['code']?.toString();
      _showSnack(
        errorMsg,
        code == 'INVALID_CREDENTIALS' || code == 'ACCOUNT_DISABLED'
            ? Colors.red
            : Colors.orange.shade800,
      );
      // Only a wrong password needs to be typed again.
      if (code == 'INVALID_CREDENTIALS') {
        _passwordController.clear();
        _passwordFocus.requestFocus();
      }
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(14),
        ),
      );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff0f1b4c), _navy, _navyLight],
                stops: [0.0, 0.55, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(top: -110, right: -80, child: _circle(300, Colors.white.withOpacity(0.05))),
          Positioned(bottom: -140, left: -100, child: _circle(340, Colors.white.withOpacity(0.04))),
          Positioned(top: 90, left: -36, child: _circle(110, _gold.withOpacity(0.10))),
          Positioned(bottom: 70, right: -24, child: _circle(80, _gold.withOpacity(0.08))),

          // Content (centered, single column)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: _animated(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _logoCard(width: 240, height: 104)),
                        const SizedBox(height: 20),
                        const Text(
                          'TEAM FLOW',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            width: 40,
                            height: 3,
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ASIK Engineering Construction',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.78),
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.fromLTRB(26, 30, 26, 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.28),
                                blurRadius: 32,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: _formContent(),
                        ),
                        const SizedBox(height: 22),
                        _footer(Colors.white.withOpacity(0.55)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _animated(Widget child) => FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(position: _slideAnim, child: child),
      );

  Widget _circle(double d, Color color) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _logoCard({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/images/logo1.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.business_rounded, size: 48, color: _navy),
        ),
      ),
    );
  }

  Widget _footer(Color color) => Text(
        '© ${DateTime.now().year} ASIK Engineering Construction',
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 12),
      );

  Widget _formContent() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _ink),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in with your work email to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: _muted),
          ),
          const SizedBox(height: 28),
          _label('Email'),
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onSubmitted: _onEmailSubmitted,
            style: const TextStyle(fontSize: 15, color: _ink),
            decoration: _decoration(hint: 'name@company.com', icon: Icons.mail_outline_rounded),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _label('Password')),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _isLoading
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                          ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(fontSize: 13, color: _navyLight, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _isPasswordHidden,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _handleLogin(), // Enter = Sign in
            style: const TextStyle(fontSize: 15, color: _ink),
            decoration: _decoration(
              hint: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              suffix: ExcludeFocus(
                child: IconButton(
                  tooltip: _isPasswordHidden ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _isPasswordHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: _muted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _isPasswordHidden = !_isPasswordHidden),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _navy.withOpacity(0.75),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Sign in',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_return_rounded, size: 14, color: _muted),
              SizedBox(width: 6),
              Text('Press Enter to sign in', style: TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
      );

  InputDecoration _decoration({required String hint, required IconData icon, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xff9ca3af), fontSize: 14),
      prefixIcon: Icon(icon, color: _muted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xfff9fafb),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: border(_line),
      enabledBorder: border(_line),
            focusedBorder: border(_navy, 1.6),
    );
  }
}
