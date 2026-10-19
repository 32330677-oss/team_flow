// lib/widgets/arrow_time_picker.dart
//
// Drop-in replacement for showTimePicker (same inputs, same result: the
// picked TimeOfDay, or null on Cancel) that uses tap-only arrows instead of
// the rotating clock:
//
//      ▲              ⏫  ▲
//     17      :      07
//      ▼              ⏬  ▼
//
//   hour   ▲ / ▼   : ±1 hour
//   minute ⏫ / ⏬  : ±15 minutes. From a time that is not on a quarter
//                    (17:07) the first tap goes to the nearest quarter in
//                    that direction (17:15 / 17:00).
//   minute ▲ / ▼   : ±1 minute
//
// Minutes carry into the hour (17:59 + 1 min = 18:00) and the day wraps
// (23:xx + 1 h = 00:xx), exactly like a clock. Only the time of day is
// returned; any date logic stays with the caller.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

Future<TimeOfDay?> showArrowTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => _ArrowTimeDialog(initial: initialTime, title: helpText),
  );
}

class _ArrowTimeDialog extends StatefulWidget {
  final TimeOfDay initial;
  final String? title;

  const _ArrowTimeDialog({required this.initial, this.title});

  @override
  State<_ArrowTimeDialog> createState() => _ArrowTimeDialogState();
}

class _ArrowTimeDialogState extends State<_ArrowTimeDialog> {
  static const int _day = 24 * 60;
  late int _minutes; // minutes since midnight, 0..1439

  @override
  void initState() {
    super.initState();
    _minutes = widget.initial.hour * 60 + widget.initial.minute;
  }

  void _set(int value) => setState(() => _minutes = ((value % _day) + _day) % _day);

  void _addHour(int delta) => _set(_minutes + delta * 60);
  void _addMinute(int delta) => _set(_minutes + delta);

  /// ±15 minutes, snapping to the quarter: 17:07 -> 17:15 (up) / 17:00 (down).
  void _addQuarter(int direction) {
    final rem = _minutes % 15;
    if (direction > 0) {
      _set(_minutes + (15 - rem));
    } else {
      _set(_minutes - (rem == 0 ? 15 : rem));
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  Widget _arrow(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 30,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = _minutes ~/ 60;
    final minute = _minutes % 60;
    final valueStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return AlertDialog(
      title: Text(widget.title ?? 'Select time'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hour
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _arrow(Icons.keyboard_arrow_up, '+1 hour', () => _addHour(1)),
              Text(_two(hour), style: valueStyle),
              _arrow(Icons.keyboard_arrow_down, '-1 hour', () => _addHour(-1)),
              Text('hour', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(':', style: valueStyle),
          ),
          // Minute
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _arrow(Icons.keyboard_double_arrow_up, '+15 minutes', () => _addQuarter(1)),
                  _arrow(Icons.keyboard_arrow_up, '+1 minute', () => _addMinute(1)),
                ],
              ),
              Text(_two(minute), style: valueStyle),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _arrow(Icons.keyboard_double_arrow_down, '-15 minutes', () => _addQuarter(-1)),
                  _arrow(Icons.keyboard_arrow_down, '-1 minute', () => _addMinute(-1)),
                ],
              ),
              Text('15 min   |   1 min', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}