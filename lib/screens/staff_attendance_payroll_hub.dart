import 'package:flutter/material.dart';
import 'staff_attendance_review_screen.dart';
import 'PayrollScreenStaff.dart';
import '../widgets/custom_app_bar.dart';

class StaffAttendancePayrollHub extends StatelessWidget {
  const StaffAttendancePayrollHub({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Staff Attendance & Payroll',
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.fact_check_rounded), text: 'Attendance'),
              Tab(icon: Icon(Icons.payments_rounded), text: 'Payroll'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            StaffAttendanceReviewScreen(),
            StaffPayrollScreen(),
          ],
        ),
      ),
    );
  }
}