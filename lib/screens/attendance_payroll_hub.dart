import 'package:flutter/material.dart';
import 'admin_attendance_screen.dart'; // تأكد أن هذا الملف موجود في نفس المجلد

class AttendancePayrollHub extends StatelessWidget {
  const AttendancePayrollHub({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الحضور والرواتب'),
          backgroundColor: const Color(0xff1a2a6c),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.assignment_turned_in), text: 'الحضور'),
              Tab(icon: Icon(Icons.attach_money), text: 'الرواتب'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            // ✅ تم استبدال الـ Text القديم بالشاشة الجديدة التي برمجناها
            AdminAttendanceScreen(), 
            
            // شاشة الرواتب (سنعمل عليها لاحقاً)
            Center(child: Text("شاشة الرواتب ستظهر هنا")),
          ],
        ),
      ),
    );
  }
}