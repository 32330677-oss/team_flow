import 'package:flutter/material.dart';
import 'admin_shell_scope.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    // Inside the Admin shell on a narrow screen, the first page of a section
    // has no back button: show the menu button that opens the sidebar.
    Widget? leading;
    final shell = AdminShellScope.maybeOf(context);
    if (shell != null &&
        !shell.persistentSidebar &&
        !(ModalRoute.of(context)?.canPop ?? false) &&
        AdminShellScope.isPageLevelScaffold(context)) {
      leading = IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Menu',
        onPressed: shell.openMenu,
      );
    }
    return AppBar(
      leading: leading,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: const Color(0xff1a2a6c), // 👈 اللون الموحد لكل التطبيق
      iconTheme: const IconThemeData(color: Colors.white),
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );
}