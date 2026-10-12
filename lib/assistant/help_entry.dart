// lib/assistant/help_entry.dart
//
// One entry point for the "Help & Assistant" buttons:
//   * AI assistant enabled on the server (ANTHROPIC_API_KEY set) → chat.
//   * Otherwise (or if the server cannot be asked) → Help Center (search).
// Every help page uses a route name starting with "/help" so the "Open"
// buttons can close all of them before opening the target screen.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../screens/assistant_screen.dart';
import '../screens/help_center_screen.dart';

class HelpEntry {
  static const String routePrefix = '/help';
  static const String centerRoute = '/help/center';
  static const String topicRoute = '/help/topic';
  static const String chatRoute = '/help/chat';

  /// null = not asked yet. Re-checked when another user logs in.
  static bool? aiEnabled;
  static String? _checkedFor;

  static bool isHelpRoute(Route<dynamic> route) => route.settings.name?.startsWith(routePrefix) ?? false;

  static Future<bool> _checkAi() async {
    final uid = await ApiConfig.storage.read(key: 'user_id');
    if (aiEnabled != null && uid == _checkedFor) return aiEnabled!;
    try {
      final res = await ApiConfig.dio.get(
        '/assistant/status',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      final data = res.data;
      aiEnabled = data is Map && data['enabled'] == true;
      _checkedFor = uid;
    } catch (_) {
      // Unknown: use the Help Center this time and ask again next time.
      return false;
    }
    return aiEnabled!;
  }

  /// Opens the AI chat when it is enabled, otherwise the Help Center.
  static Future<void> open({String? contextScreen}) async {
    final ai = await _checkAi();
    ApiConfig.navigatorKey.currentState?.push(MaterialPageRoute(
      settings: RouteSettings(name: ai ? chatRoute : centerRoute),
      builder: (_) => ai ? AssistantScreen(contextScreen: contextScreen) : HelpCenterScreen(contextScreen: contextScreen),
    ));
  }

  static void openHelpCenter({String? contextScreen}) {
    ApiConfig.navigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: centerRoute),
      builder: (_) => HelpCenterScreen(contextScreen: contextScreen),
    ));
  }

  static void openAssistantChat({String? contextScreen}) {
    ApiConfig.navigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: chatRoute),
      builder: (_) => AssistantScreen(contextScreen: contextScreen),
    ));
  }
}
