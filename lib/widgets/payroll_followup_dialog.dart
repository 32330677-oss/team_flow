// lib/widgets/payroll_followup_dialog.dart
//
// After an Admin attendance correction, the server says what it means for
// payroll (data.payroll_adjustment / data.payroll_hint). This dialog shows it
// in plain words. Returns false when there was nothing to show (the caller
// then shows its usual snackbar).

import 'package:flutter/material.dart';

Future<bool> showPayrollFollowUp(BuildContext context, dynamic responseBody) async {
  if (responseBody is! Map) return false;
  final data = responseBody['data'];
  if (data is! Map) return false;
  final adj = data['payroll_adjustment'];
  final hint = data['payroll_hint'];
  if (adj == null && hint == null) return false;

  String title;
  IconData icon;
  Color color;
  final lines = <Widget>[];

  if (adj is Map && adj['adjustment_id'] != null) {
    final amount = num.tryParse('${adj['amount']}') ?? 0;
    final currency = '${adj['currency'] ?? ''}';
    final negative = amount < 0;
    title = negative ? 'Deduction to confirm' : 'Payroll adjustment created';
    icon = negative ? Icons.remove_circle_outline : Icons.add_card_outlined;
    color = negative ? Colors.orange.shade800 : Colors.green.shade700;
    lines.add(Text(
      '${amount > 0 ? '+' : ''}${amount.toStringAsFixed(2)} $currency',
      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color),
    ));
    lines.add(const SizedBox(height: 8));
    if (adj['before'] != null && adj['after'] != null) {
      lines.add(Text('Pay before the correction: ${adj['before']} $currency'));
      lines.add(Text('Pay after the correction: ${adj['after']} $currency'));
      lines.add(const SizedBox(height: 8));
    }
    lines.add(Text(negative
        ? 'The paid batch was not changed. Confirm this deduction in "Payroll adjustments" to take it from the next payroll.'
        : 'The paid batch was not changed. This amount is added automatically to the next payroll batch of this person.'));
  } else if (adj is Map && (adj['amount'] == 0 || adj['amount'] == 0.0)) {
    title = 'No pay difference';
    icon = Icons.check_circle_outline;
    color = Colors.blueGrey;
    lines.add(const Text('The correction was saved. It does not change what was paid, so there is nothing to adjust.'));
  } else if (adj is Map && adj['error'] != null) {
    title = 'Amount not computed';
    icon = Icons.warning_amber_rounded;
    color = Colors.red.shade700;
    lines.add(Text('The correction was saved, but the pay difference could not be computed: ${adj['error']}'));
    lines.add(const SizedBox(height: 8));
    lines.add(const Text('Add a manual adjustment in "Payroll adjustments" if money is owed.'));
  } else if (hint is Map) {
    final supersede = hint['action'] == 'supersede';
    title = supersede ? 'Finalized payroll to correct' : 'Payroll to regenerate';
    icon = supersede ? Icons.published_with_changes : Icons.refresh;
    color = Colors.indigo;
    lines.add(Text('${hint['message'] ?? ''}'));
  } else {
    return false;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(title)),
      ]),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: lines),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
  return true;
}
