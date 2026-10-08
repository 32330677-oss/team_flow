import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../screens/payroll_export_service.dart';

/// PRELIMINARY (unofficial) staff attendance & expected payroll PDF.
///
/// Read-only on the server: it counts Submitted + Approved attendance as if
/// everything were approved, and calculates the expected salary with the same
/// formula as staff payroll generation. Nothing is approved or generated.
class PreliminaryReportCard extends StatefulWidget {
  const PreliminaryReportCard({super.key});

  @override
  State<PreliminaryReportCard> createState() => _PreliminaryReportCardState();
}

class _PreliminaryReportCardState extends State<PreliminaryReportCard> {
  // ASIK logo colours
  static const Color _charcoal = Color(0xff4b4a4d);
  static const Color _gold = Color(0xffcbab5a);
  static const Color _goldLight = Color(0xfff4ecd6);
  static const Color _red = Color(0xffb3261e);
  static const int _maxDays = 40;

  late DateTimeRange _range;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  final _dayFmt = DateFormat('dd MMM yyyy');
  final _apiFmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _setThisMonth(notify: false);
  }

  int get _days => _range.end.difference(_range.start).inDays + 1;

  void _setThisMonth({bool notify = true}) {
    final now = DateTime.now();
    final r = DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0));
    if (!notify) {
      _range = r;
      return;
    }
    setState(() {
      _range = r;
      _message = null;
    });
  }

  void _setLastMonth() {
    final now = DateTime.now();
    setState(() {
      _range = DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0));
      _message = null;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Preliminary report period',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _charcoal,
                onPrimary: Colors.white,
                secondaryContainer: _goldLight,
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    if (picked.end.difference(picked.start).inDays + 1 > _maxDays) {
      setState(() {
        _isError = true;
        _message = 'The period cannot be longer than $_maxDays days.';
      });
      return;
    }
    setState(() {
      _range = picked;
      _message = null;
    });
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final from = _apiFmt.format(_range.start);
    final to = _apiFmt.format(_range.end);
    try {
      final response = await ApiConfig.dio.get<List<int>>(
        '/staff-payroll/preliminary-report.pdf',
        queryParameters: {'start_date': from, 'end_date': to},
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty report');
      await PayrollExportService.exportBytes(bytes, 'PRELIMINARY_staff_payroll_${from}_to_$to.pdf');
      if (!mounted) return;
      setState(() {
        _isError = false;
        _message = 'Preliminary PDF ready. It is NOT official — nothing was approved or generated.';
      });
    } on DioException catch (e) {
      var msg = 'Failed to generate the preliminary report.';
      final raw = e.response?.data;
      if (raw is List<int>) {
        try {
          final decoded = jsonDecode(utf8.decode(raw));
          if (decoded is Map && decoded['message'] != null) msg = decoded['message'].toString();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = msg;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = 'Failed to generate the preliminary report.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String label, VoidCallback onTap) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _charcoal)),
        onPressed: _busy ? null : onTap,
        backgroundColor: _goldLight,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _goldLight),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: _charcoal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: _gold, width: 3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: _gold.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.fact_check_outlined, color: _gold, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preliminary Staff Report (before approval)',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 3),
                      Text('Every day, absence and the expected salary, counting Submitted + Approved records. Unofficial.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xffe8e2d2))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _red.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Not official: records are not yet reviewed by the Admin. Draft / Rejected days are shown and '
                    'counted as unpaid absence, exactly as payroll would. Nothing is approved or saved.',
                    style: TextStyle(fontSize: 12, color: _red),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _chip('This month', _setThisMonth),
                  _chip('Last month', _setLastMonth),
                ]),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _busy ? null : _pickRange,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xfffbf8ef),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range_rounded, color: _charcoal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_dayFmt.format(_range.start)}  →  ${_dayFmt.format(_range.end)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _charcoal),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: _goldLight, borderRadius: BorderRadius.circular(20)),
                          child: Text('$_days ${_days == 1 ? 'day' : 'days'}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _charcoal)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_rounded, color: _gold, size: 20),
                    label: Text(_busy ? 'Generating...' : 'Print Preliminary PDF',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _charcoal,
                      disabledBackgroundColor: _charcoal.withOpacity(0.55),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!,
                      style: TextStyle(fontSize: 12, color: _isError ? _red : const Color(0xff2e7d32))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
