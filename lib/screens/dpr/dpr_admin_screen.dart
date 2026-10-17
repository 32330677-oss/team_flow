// lib/screens/dpr/dpr_admin_screen.dart
//
// Admin view of the Daily Progress Report: everything READ ONLY (the Admin's
// permission is dpr.view): dashboard, daily reports, allocation, registers,
// issued reports, and the manual values typed over the system values.

import 'package:flutter/material.dart';

import '../../services/access_service.dart';
import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/custom_app_bar.dart';
import 'dpr_pages.dart';
import 'dpr_registers_screen.dart';
import 'dpr_report_screen.dart';
import 'dpr_widgets.dart';

class DprAdminScreen extends StatefulWidget {
  const DprAdminScreen({super.key});

  @override
  State<DprAdminScreen> createState() => _DprAdminScreenState();
}

class _DprAdminScreenState extends State<DprAdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await AccessService.me();
      DprState.permissions = a.permissions.toSet();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Daily Progress Report (DPR)',
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Daily report'),
            Tab(text: 'Allocation'),
            Tab(text: 'NCR & concerns'),
            Tab(text: 'Issued reports'),
            Tab(text: 'Manual vs system'),
          ],
        ),
      ),
      body: !_ready
          ? (_error != null
              ? DprMessage(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _error!)
              : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
          : TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
              DprDashboardPage(onOpenDay: (d) {
                DprState.date.value = parseYmd(d);
                _tabs.animateTo(1);
              }),
              const DprReportPage(),
              const DprAllocPage(),
              const DprRegistersPage(),
              const DprArchivePage(),
              const DprDifferencesPage(),
            ]),
    );
  }
}
