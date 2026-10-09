import 'package:flutter/material.dart';

/// Marks the content area of the Admin shell (persistent sidebar).
/// Screens use it to know they are shown next to the sidebar, and to open the
/// sidebar as a drawer on narrow screens.
class AdminShellScope extends InheritedWidget {
  /// Opens the sidebar drawer (narrow screens only).
  final VoidCallback openMenu;

  /// True on wide screens, where the sidebar is always visible.
  final bool persistentSidebar;

  const AdminShellScope({
    super.key,
    required this.openMenu,
    required this.persistentSidebar,
    required super.child,
  });

  static AdminShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminShellScope>();

  /// True when [context] belongs to a page's main Scaffold (not a Scaffold
  /// nested inside another page, e.g. the screens inside a tab hub).
  static bool isPageLevelScaffold(BuildContext context) {
    var scaffolds = 0;
    context.visitAncestorElements((element) {
      if (element.widget is AdminShellScope) return false;
      if (element is StatefulElement && element.state is ScaffoldState) scaffolds++;
      return true;
    });
    return scaffolds <= 1;
  }

  @override
  bool updateShouldNotify(AdminShellScope oldWidget) =>
      oldWidget.persistentSidebar != persistentSidebar;
}
