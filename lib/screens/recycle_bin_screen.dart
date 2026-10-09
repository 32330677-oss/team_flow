// lib/screens/recycle_bin_screen.dart
//
// Recycle Bin (Admin): people deleted in the last 30 days. Restore brings back
// every record with its original ids; "Delete now" removes the entry for good.
// After 30 days the server purges entries automatically.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';

const Color _kPrimary = Color(0xFF1A2A6C);
const Color _kDanger = Color(0xFFC62828);

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  String _status = 'Deleted';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _err(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      final d = e.response!.data as Map;
      final blockers = (d['blockers'] as List?)?.map((b) => '• ${b['message']}').join('\n');
      return [d['message'] ?? fallback, if (blockers != null && blockers.isNotEmpty) blockers].join('\n\n');
    }
    return fallback;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiConfig.dio.get('/recycle-bin', queryParameters: {'status': _status});
      _items = (res.data['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      _snack(_err(e, 'Failed to load the recycle bin'), _kDanger);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _askReason(String title, String message, String confirm, {bool danger = false}) async {
    final controller = TextEditingController();
    String? err;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: InputDecoration(labelText: 'Reason (min. 5 characters)', errorText: err, border: const OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: danger ? ElevatedButton.styleFrom(backgroundColor: _kDanger, foregroundColor: Colors.white) : null,
              onPressed: () {
                if (controller.text.trim().length < 5) { setD(() => err = 'Please enter a clear reason'); return; }
                Navigator.pop(ctx, controller.text.trim());
              },
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final reason = await _askReason('Restore ${item['entity_name']}',
        'Every record comes back exactly as it was (attendance, payroll lines, assignments, history).', 'Restore');
    if (reason == null) return;
    try {
      final res = await ApiConfig.dio.post('/recycle-bin/${item['recycle_id']}/restore', data: {'reason': reason});
      final warnings = (res.data['data']?['warnings'] as List? ?? []);
      if (warnings.isNotEmpty && mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restored — payroll to correct'),
            content: Text(warnings.map((w) => '• ${w['message']}').join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      } else {
        _snack('${item['entity_name']} restored', Colors.green.shade700);
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot restore yet'),
          content: SingleChildScrollView(child: Text(_err(e, 'Restore failed'))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _purge(Map<String, dynamic> item) async {
    final reason = await _askReason('Delete ${item['entity_name']} permanently?',
        'This cannot be undone. All archived records of this person are erased now.', 'Delete permanently', danger: true);
    if (reason == null) return;
    try {
      await ApiConfig.dio.delete('/recycle-bin/${item['recycle_id']}', data: {'reason': reason});
      _snack('Deleted permanently', Colors.grey.shade800);
      _load();
    } catch (e) {
      _snack(_err(e, 'Failed to delete permanently'), _kDanger);
    }
  }

  int _total(Map<String, dynamic> item) {
    final counts = item['row_counts'];
    if (counts is! Map) return 0;
    return counts.values.whereType<num>().fold<int>(0, (a, b) => a + b.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(title: 'Recycle Bin'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                _status == 'Deleted'
                    ? 'Deleted people can be restored for 30 days, then they are deleted for good.'
                    : 'People restored from the bin.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Deleted', label: Text('In bin'), icon: Icon(Icons.delete_outline, size: 18)),
                ButtonSegment(value: 'Restored', label: Text('Restored'), icon: Icon(Icons.restore, size: 18)),
              ],
              selected: {_status},
              onSelectionChanged: (s) { setState(() => _status = s.first); _load(); },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.delete_sweep_outlined, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(_status == 'Deleted' ? 'The recycle bin is empty' : 'Nothing restored yet',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _card(_items[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> item) {
    final inBin = item['status'] == 'Deleted';
    final daysLeft = int.tryParse('${item['days_left'] ?? 0}') ?? 0;
    final urgent = daysLeft <= 3;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              backgroundColor: _kPrimary.withOpacity(0.08),
              child: Icon(item['entity_type'] == 'Staff' ? Icons.badge_outlined : Icons.engineering_outlined, color: _kPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item['entity_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text('${item['entity_type']} • ${item['entity_code'] ?? ''} • ${_total(item)} records',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                  inBin
                      ? 'Deleted ${item['deleted_at']} by ${item['deleted_by']} — "${item['reason']}"'
                      : 'Restored ${item['restored_at']} by ${item['restored_by']} — "${item['restore_reason']}"',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
              ]),
            ),
            if (inBin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: urgent ? Colors.red.shade50 : Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: urgent ? _kDanger : Colors.blueGrey.shade700)),
              ),
          ]),
          if (inBin) ...[
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              TextButton.icon(
                onPressed: () => _purge(item),
                icon: const Icon(Icons.delete_forever_outlined, color: _kDanger, size: 18),
                label: const Text('Delete now', style: TextStyle(color: _kDanger)),
              ),
              FilledButton.icon(onPressed: () => _restore(item), icon: const Icon(Icons.restore, size: 18), label: const Text('Restore')),
            ]),
          ],
        ]),
      ),
    );
  }
}
