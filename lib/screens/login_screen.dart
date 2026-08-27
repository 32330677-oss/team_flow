import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/auth_service.dart'; // Make sure this path matches your project structure
import 'admin_dashboard_screen.dart';
import 'supervisor_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _isPasswordHidden = true;
  final _storage = const FlutterSecureStorage();

  // Simple entrance animation (purely cosmetic, no logic impact)
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // UNCHANGED LOGIC: same endpoint call, same response parsing, same
  // secure storage keys ('jwt_token', 'user_role', 'user_id', 'user_name'),
  // same role-based navigation (Admin -> AdminDashboardScreen,
  // otherwise -> SupervisorDashboard).
  // ---------------------------------------------------------------------
  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack("Please fill in all fields", Colors.orange);
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
      String role = result['user']['role']; // 'Admin' or 'Supervisor'
      String fullName = result['user']['full_name'] ?? 'User';

      final userIdRaw = result['user']['user_id'] ?? result['user']['id'];
      final int supervisorId =
          (userIdRaw != null) ? int.parse(userIdRaw.toString()) : 0;

      await _storage.write(key: 'jwt_token', value: token);
      await _storage.write(key: 'user_role', value: role);
      await _storage.write(key: 'user_id', value: supervisorId.toString());
      await _storage.write(key: 'user_name', value: fullName);

      _showSnack("Welcome, $fullName! Login successful.", Colors.green);

      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (role == 'Admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
          );
        } else {
          final userIdRaw = result['user']['user_id'] ?? result['user']['id'];
          final int supervisorId =
              (userIdRaw != null) ? int.parse(userIdRaw.toString()) : 0;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SupervisorDashboard(
                supervisorId: supervisorId,
                supervisorName:
                    result['user']['full_name'] ?? result['user']['username'] ?? 'New Supervisor',
              ),
            ),
          );
        }
      });
    } else {
      String errorMsg = result?['message'] ?? "InCorrect Password or Username";
      _showSnack(errorMsg, Colors.red);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
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
  // UI ONLY — redesigned below. No changes to state, controllers or logic.
  // ---------------------------------------------------------------------
  static const Color _primaryDark = Color(0xff1a2a6c);
  static const Color _primaryLight = Color(0xff2a4d8f);
  static const Color _accent = Color(0xfffdbb2d);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryDark, _primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Soft decorative circles
          Positioned(
            top: -60,
            right: -40,
            child: _decorativeCircle(180, Colors.white.withOpacity(0.06)),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: _decorativeCircle(220, Colors.white.withOpacity(0.05)),
          ),
          Positioned(
            top: size.height * 0.28,
            left: -30,
            child: _decorativeCircle(90, _accent.withOpacity(0.08)),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLogo(),
                        const SizedBox(height: 36),
                        _buildLoginCard(),
                        const SizedBox(height: 20),
                        Text(
                          'ASIK ENGINEERING CONSTRUCTION © ${DateTime.now().year}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 12,
                          ),
                        ),
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

  Widget _decorativeCircle(double diameter, Color color) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

Widget _buildLogo() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
  width: 280,
  height: 125,
  padding: const EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.18),
        blurRadius: 16,
        offset: const Offset(0, 7),
      ),
    ],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.asset(
      'assets/images/logo.png',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(
          Icons.business_rounded,
          size: 55,
          color: _primaryDark,
        );
      },
    ),
  ),
),

      const SizedBox(height: 10),
      const Text(
        'ASIK ENGINEERING CONSTRUCTION',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        'Workers Management System',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withOpacity(0.82),
        ),
      ),
    ],
  );
}



  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Sign In",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Enter your info to continue",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),

          // Email field
          _buildTextField(
            controller: _emailController,
            label: "Email",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 18),

          // Password field
          _buildTextField(
            controller: _passwordController,
            label: "Password",
            icon: Icons.lock_outline_rounded,
            obscureText: _isPasswordHidden,
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _isPasswordHidden = !_isPasswordHidden;
                });
              },
            ),
          ),

          const SizedBox(height: 30),

          // Login button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryDark,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: _primaryDark.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.6,
                      ),
                    )
                  : const Text(
                      "Sign In",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: _primaryLight),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primaryDark, width: 1.6),
        ),
      ),
    );
  }
}