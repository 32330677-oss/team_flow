// lib/assistant/assistant_navigation.dart
//
// Opens the screen behind an assistant "Open" button.
// The ids are the same as the backend list (services/assistantScreens.js).
// The backend only sends ids allowed for the user's role; unknown ids are
// ignored here.

import 'package:flutter/material.dart';

import '../constants.dart';
import '../screens/change_password_screen.dart';
import '../screens/payroll_adjustments_screen.dart';
import '../screens/recycle_bin_screen.dart';
import '../screens/rejected_records_screen.dart';
import '../screens/staff_screen.dart';
import '../screens/staff_supervisor_attendance_screen.dart';
import '../screens/transfer_request_screen.dart';
import '../widgets/admin_shell.dart';
import 'help_entry.dart';

class AssistantNavigation {
  /// Pages opened on top of the current page (not sidebar pages).
  static final Map<String, Widget Function()> _pushed = {
    'change_password': () => const ChangePasswordScreen(),
    'payroll_adjustments': () => const PayrollAdjustmentsScreen(),
    'recycle_bin': () => const RecycleBinScreen(),
    'staff_management': () => const StaffScreen(),
    'rejected_records': () => const RejectedRecordsScreen(),
    'transfer_request': () => const TransferRequestScreen(),
    'staff_attendance': () => const StaffSupervisorAttendanceScreen(),
  };

  /// Home pages of the supervisor apps: the first page after login.
  static const Set<String> _homes = {'supervisor_home', 'staff_supervisor_home'};

  /// Closes the help pages (Help Center, topic, chat), then opens [screenId].
  /// Returns false when the id is unknown (nothing happens).
  static bool open(BuildContext context, String screenId) {
    final nav = ApiConfig.navigatorKey.currentState;
    if (nav == null) return false;

    // Admin sidebar page: the sidebar replaces the whole page stack.
    if (AdminChromeState.hasItem(screenId)) {
      AdminChromeState.openById(screenId);
      return true;
    }
    if (_homes.contains(screenId)) {
      nav.popUntil((route) => route.isFirst);
      return true;
    }
    final builder = _pushed[screenId];
    if (builder == null) return false;
    // Leave the help pages (the chat is kept in memory) and open the page in
    // their place, so "Back" returns to where the user was before asking.
    nav.popUntil((route) => route.isFirst || !HelpEntry.isHelpRoute(route));
    nav.push(MaterialPageRoute(builder: (_) => builder()));
    return true;
  }
}
