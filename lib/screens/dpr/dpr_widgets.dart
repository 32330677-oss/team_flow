// lib/screens/dpr/dpr_widgets.dart
//
// Pieces shared by the Daily Progress Report pages: the contract tabs + date
// bar, section cards, the "where does this number come from" chip, messages.
// Colours: AppColors (same as the rest of the app).

import 'package:flutter/material.dart';

import '../../services/dpr_api.dart';
import '../../widgets/app_data_table.dart';

void dprSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
}

InputDecoration dprInput(String label, {String? hint, Widget? suffix, bool dense = true}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: dense,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
    );

/// White rounded card with a title, like the rest of the app.
class DprCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final String? subtitle;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  const DprCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.actions = const [],
    this.subtitle,
    this.accent,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ),
            ...actions,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class DprMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;
  const DprMessage({super.key, required this.icon, required this.text, this.color = AppColors.primary, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: color),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}

/// Banner (warnings, info).
class DprBanner extends StatelessWidget {
  final List<String> lines;
  final Color color;
  final IconData icon;
  const DprBanner({super.key, required this.lines, this.color = const Color(0xffb45309), this.icon = Icons.warning_amber_rounded});

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(l, style: TextStyle(fontSize: 12.5, color: color, height: 1.35)),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }
}

/// Contract tabs (one tab per contract) + report date. Every DPR page sits under it.
class DprContractBar extends StatefulWidget {
  final bool showDate;
  final List<Widget> actions;
  final ValueChanged<List<Json>>? onContracts;
  const DprContractBar({super.key, this.showDate = true, this.actions = const [], this.onContracts});

  @override
  State<DprContractBar> createState() => _DprContractBarState();
}

class _DprContractBarState extends State<DprContractBar> {
  List<Json> _contracts = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DprApi.contracts();
      final active = list.where((c) => c['is_active'] == true).toList();
      DprState.templates.value = {for (final c in list) asInt(c['contract_id']): str(c['template']).isEmpty ? 'ucc' : str(c['template'])};
      if (!mounted) return;
      setState(() {
        _contracts = active;
        _loading = false;
      });
      final cur = DprState.contractId.value;
      if (active.isNotEmpty && (cur == null || !active.any((c) => asInt(c['contract_id']) == cur))) {
        DprState.contractId.value = asInt(active.first['contract_id']);
      }
      widget.onContracts?.call(active);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DprState.date.value,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) DprState.date.value = picked;
  }

  void _shiftDay(int k) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = DprState.date.value.add(Duration(days: k));
    if (next.isAfter(today)) return;
    DprState.date.value = next;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2, color: AppColors.primary);
    if (_error != null) return DprBanner(lines: [_error!], color: AppColors.danger, icon: Icons.error_outline_rounded);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_contracts.isEmpty)
            const Text('No contract yet. Add one in Setup.', style: TextStyle(color: AppColors.textSecondary))
          else
            ValueListenableBuilder<int?>(
              valueListenable: DprState.contractId,
              builder: (_, sel, __) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _contracts.map((c) {
                  final id = asInt(c['contract_id']);
                  final on = id == sel;
                  return Tooltip(
                    message: str(c['title']),
                    child: ChoiceChip(
                      label: Text('${str(c['code'])} · ${str(c['title'])}', overflow: TextOverflow.ellipsis),
                      selected: on,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.background,
                      side: BorderSide(color: on ? AppColors.primary : AppColors.border),
                      labelStyle: TextStyle(
                          color: on ? Colors.white : AppColors.textPrimary, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 12.5),
                      onSelected: (_) => DprState.contractId.value = id,
                    ),
                  );
                }).toList(),
              ),
            ),
          if (widget.showDate)
            ValueListenableBuilder<DateTime>(
              valueListenable: DprState.date,
              builder: (_, dt, __) => Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Previous day',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => _shiftDay(-1),
                  ),
                  InkWell(
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.event_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(fmtDay(ymd(dt)), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ]),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Next day',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => _shiftDay(1),
                  ),
                ]),
              ),
            ),
          ...widget.actions,
        ],
      ),
    );
  }
}

/// Listens to the chosen contract (and date) and rebuilds the page body.
class DprSelection extends StatelessWidget {
  final bool withDate;
  final Widget Function(BuildContext context, int contractId, String date) builder;
  const DprSelection({super.key, required this.builder, this.withDate = true});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: DprState.contractId,
      builder: (ctx, cid, _) {
        if (cid == null) {
          return const DprMessage(icon: Icons.assignment_outlined, text: 'Choose a contract above.');
        }
        if (!withDate) return builder(ctx, cid, DprState.dateStr);
        return ValueListenableBuilder<DateTime>(
          valueListenable: DprState.date,
          builder: (ctx2, dt, __) => builder(ctx2, cid, ymd(dt)),
        );
      },
    );
  }
}

/// Small coloured label: where a figure comes from.
class SourceTag extends StatelessWidget {
  final String mode; // system / override / manual
  final String? system;
  const SourceTag({super.key, required this.mode, this.system});

  @override
  Widget build(BuildContext context) {
    late final Color c;
    late final String t;
    switch (mode) {
      case 'override':
        c = const Color(0xffb45309);
        t = 'Manual';
        break;
      case 'system':
        c = const Color(0xff047857);
        t = (system == null || system!.isEmpty) ? 'System' : system!;
        break;
      default:
        c = AppColors.textSecondary;
        t = 'Typed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// A KPI tile (dashboard).
class DprKpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? note;
  const DprKpi({super.key, required this.label, required this.value, required this.icon, this.color = AppColors.primary, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color)),
            if (note != null) Text(note!, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

/// Table cell with horizontal padding (AppDataTableCard has no cell padding).
Widget dprCell(String text, {bool bold = false, Color? color, double? width, TextAlign align = TextAlign.left, int maxLines = 2}) {
  final t = Text(text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? AppColors.textPrimary, fontSize: 12.5));
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: width == null ? t : SizedBox(width: width, child: t),
  );
}

DataColumn dprCol(String label, {bool numeric = false}) => DataColumn(label: Text('  $label'), numeric: numeric);

Future<bool> dprConfirm(BuildContext context, String title, String text, {String ok = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: danger ? AppColors.danger : AppColors.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(dCtx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

ButtonStyle dprPrimaryButton() => ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
ButtonStyle dprAccentButton() => ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
