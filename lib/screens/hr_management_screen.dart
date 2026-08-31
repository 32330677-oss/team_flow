import 'package:flutter/material.dart';
import 'workers_screen.dart'; // شاشة العمال الحالية لديك
import 'supervisor_management_screen.dart'; // شاشة المشرفين
import 'staff_screen.dart'; // شاشة الموظفين الإداريين الجديدة
import '../widgets/custom_app_bar.dart';

class HRManagementScreen extends StatelessWidget {
  const HRManagementScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(
        title: 'HR Management',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 1. Workers Management Card
            _buildCategoryCard(
              context,
              title: 'Workers Management',
              subtitle: 'View workers, add new workers, and edit their details',
              icon: Icons.engineering_outlined,
              gradientColors: [const Color(0xff1a2a6c), const Color(0xff2753a7)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WorkersScreen()),
                );
              },
            ),
            const SizedBox(height: 20),

            // 2. Supervisors Management Card
            _buildCategoryCard(
              context,
              title: 'Supervisors Management',
              subtitle: 'Create supervisor accounts, activate/deactivate, and manage access',
              icon: Icons.manage_accounts_outlined,
              gradientColors: [const Color(0xffb21f1f), const Color(0xfff12711)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SupervisorManagementScreen()),
                );
              },
            ),
            const SizedBox(height: 20),

            // 3. Staff Management Card (New)
            _buildCategoryCard(
              context,
              title: 'Staff Management',
              subtitle: 'Manage administrative staff, salaries, positions, and accounts',
              icon: Icons.badge_rounded,
              gradientColors: [const Color(0xff134e5e), const Color(0xff71b280)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const StaffScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
            child: Row(
              children: [
                Icon(icon, size: 45, color: Colors.white),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}