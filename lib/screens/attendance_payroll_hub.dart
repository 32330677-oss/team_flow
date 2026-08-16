import 'package:flutter/material.dart';
import 'admin_attendance_screen.dart'; 
import 'payroll_screen.dart';
import '../widgets/custom_app_bar.dart';
class AttendancePayrollHub extends StatelessWidget {
  const AttendancePayrollHub({super.key});

  @override
Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Attendance & Payroll Management',
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.assignment_turned_in), text: 'Attendance'),
              Tab(icon: Icon(Icons.attach_money), text: 'Payroll'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminAttendanceScreen(), 
            PayrollScreen(),
          ],
        ),
      ),
    );
  }
}