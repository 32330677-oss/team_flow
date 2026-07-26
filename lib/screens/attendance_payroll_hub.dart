import 'package:flutter/material.dart';
import 'admin_attendance_screen.dart'; 
import 'payroll_screen.dart';

class AttendancePayrollHub extends StatelessWidget {
  const AttendancePayrollHub({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance & Payroll Management'),
          backgroundColor: const Color(0xff1a2a6c),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.assignment_turned_in), text: 'Attendance'),
              Tab(icon: Icon(Icons.attach_money), text: 'Payroll'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // Admin attendance screen
            AdminAttendanceScreen(), 
            
            // Payroll screen
            PayrollScreen(),
          ],
        ),
      ),
    );
  }
}