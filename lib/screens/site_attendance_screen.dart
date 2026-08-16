import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import 'rejected_records_screen.dart';
import 'package:intl/intl.dart';

class SiteAttendanceScreen extends StatefulWidget {
  final int siteId;
  final String siteName;

  const SiteAttendanceScreen({super.key, required this.siteId, required this.siteName});

  @override
  _SiteAttendanceScreenState createState() => _SiteAttendanceScreenState();
}

class _SiteAttendanceScreenState extends State<SiteAttendanceScreen> {
  bool _isLoading = true;
  List<dynamic> _workers = [];
  List<dynamic> _mySitesForTransfer = [];

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/attendance/sites/${widget.siteId}/workers');
      if (!mounted) return;
      setState(() {
        _workers = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showToast('Failed to load workers', Colors.red);
    }
  }

  // -------------------------------------------------------------------
  // UPDATED: _handleAction now accepts an optional extraData map so that
  // additional fields (like leave_type) can be merged into the request
  // payload without duplicating this method for every action.
  // -------------------------------------------------------------------
// frontend/lib/screens/site_attendance_screen.dart
// 1. Updated the generalized helper to accept and merge extra fields
Future<void> _handleAction(String endpoint, int workerId, {Map<String, dynamic>? extraData}) async {
  setState(() => _isLoading = true);
  try {
    final Map<String, dynamic> payload = {
      'worker_id': workerId,
      'site_id': widget.siteId,
    };
    if (extraData != null) {
      payload.addAll(extraData);
    }

    await ApiConfig.dio.post(endpoint, data: payload);
    await _fetchWorkers();
  } on DioException catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    final msg = e.response?.data['message'] ?? 'Connection error';
    _showToast(msg, Colors.red);
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showToast('Connection error', Colors.red);
  }
}

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  // -------------------------------------------------------------------
  // UPDATED: The leave/break selection sheet now:
  // 1) Only shows field-appropriate types: Rest, Sick, Annual.
  //    'Management' is intentionally EXCLUDED here — it is exclusively
  //    set by an Admin through the separate management-leave endpoint
  //    in the admin dashboard, never from this supervisor-facing screen.
  // 2) Actually forwards the chosen leave_type to the backend via
  //    _handleAction's extraData parameter (this was previously ignored).
  // -------------------------------------------------------------------
Future<void> _startLeaveDialog(int workerId) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Wrap(
          runSpacing: 12,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select Break / Leave Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c)),
            ),
            const Divider(),
            _buildLeaveOption(ctx, 'Rest', 'Rest Break', Icons.free_breakfast, Colors.blue),
            _buildLeaveOption(ctx, 'Sick', 'Sick Leave', Icons.sick, Colors.red),
            _buildLeaveOption(ctx, 'Annual', 'Annual Leave', Icons.beach_access, Colors.orange),
          ],
        ),
      ),
    ),
  );

  if (type == null) return;

  // Safely forward the selected leave type in the request
  _handleAction(
    '/attendance/leave/start',
    workerId,
    extraData: {'leave_type': type},
  );
}

  Widget _buildLeaveOption(BuildContext ctx, String value, String title, IconData icon, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => Navigator.pop(ctx, value),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Future<void> _openTransferSheet(Map worker) async {
    try {
      final res = await ApiConfig.dio.get('/sites/my-sites');
      _mySitesForTransfer = (res.data is List) ? res.data : (res.data['data'] ?? []);
    } catch (e) {
      _showToast('Failed to load your assigned sites', Colors.red);
      return;
    }

    if (!mounted) return;
    Map? selectedTargetSite;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Transfer Worker: ${worker['full_name'] ?? ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text('Current Site: ${widget.siteName}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (_mySitesForTransfer.where((s) => s['site_id'] != widget.siteId).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No other assigned sites available for transfer', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  )
                else
                  DropdownButtonFormField<Map>(
                    decoration: InputDecoration(
                      labelText: 'Select Target Site',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.location_on, color: Color(0xff1a2a6c)),
                    ),
                    value: selectedTargetSite,
                    items: _mySitesForTransfer
                        .where((s) => s['site_id'] != widget.siteId)
                        .map<DropdownMenuItem<Map>>((s) => DropdownMenuItem<Map>(
                              value: s,
                              child: Text(s['site_name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (value) => setModalState(() => selectedTargetSite = value),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: (selectedTargetSite == null || isSubmitting)
                      ? null
                      : () async {
                          setModalState(() => isSubmitting = true);
                          try {
                            await ApiConfig.dio.post('/transfers', data: {
                              'worker_id': worker['worker_id'],
                              'current_site_id': widget.siteId,
                              'target_site_id': selectedTargetSite!['site_id'],
                            });
                            if (!mounted) return;
                            Navigator.pop(sheetContext);
                            _showToast('Transfer request submitted successfully', Colors.green);
                          } on DioException catch (e) {
                            setModalState(() => isSubmitting = false);
                            final msg = e.response?.data['message'] ?? 'Failed to submit request';
                            _showToast(msg, Colors.red);
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, color: Colors.white),
                  label: Text(isSubmitting ? 'Sending...' : 'Send Transfer Request', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1a2a6c),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitDay() async {
    bool hasActiveCheckIns = _workers.any((w) => w['attendance_id'] != null);
    if (!hasActiveCheckIns) {
      _showToast('No active attendance records to submit.', Colors.orange);
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Submission'),
        content: const Text('Are you sure you want to end the day and submit records for review? Make sure all workers have checked out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1a2a6c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.post('/attendance/submit', data: {'siteId': widget.siteId});
      if (response.data['status'] == 'success') {
        await _fetchWorkers();
        if (!mounted) return;
        _showToast('Day submitted successfully', Colors.green);
        if (_workers.isEmpty) Navigator.pop(context);
      }
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      final msg = e.response?.data['message'] ?? 'Final submission failed. Ensure all workers have checked out.';
      _showToast(msg, Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      _showToast('Server connection error', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = DateFormat('yyyy/MM/dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xfff8f9fa),
      appBar: AppBar(
        backgroundColor: const Color(0xff1a2a6c),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.siteName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('Daily Attendance', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
            tooltip: 'Rejected Records',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RejectedRecordsScreen())),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xff1a2a6c)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xff1a2a6c).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.today_rounded, color: Color(0xff1a2a6c), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      formattedDate,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff1a2a6c)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                      child: const Text('Today', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Active attendance date',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _workers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('All workers accounted for or none available!', style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                            final worker = _workers[index];
                            final bool isCheckedIn = worker['attendance_id'] != null;
                            final bool isOnBreak = worker['current_leave_id'] != null;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: const Color(0xff1a2a6c).withOpacity(0.1),
                                                child: Text(
                                                  (worker['full_name'] ?? 'W')[0].toUpperCase(),
                                                  style: const TextStyle(color: Color(0xff1a2a6c), fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      worker['full_name'] ?? 'Worker',
                                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff2d3748)),
                                                    ),
                                                    Text(
                                                      worker['job_position'] ?? 'Worker',
                                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.swap_horiz_rounded, color: Colors.deepOrange),
                                          tooltip: 'Transfer Worker',
                                          onPressed: () => _openTransferSheet(worker),
                                        ),
                                      ],
                                    ),
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: !isCheckedIn
                                                ? Colors.grey.shade100
                                                : isOnBreak
                                                    ? Colors.orange.shade50
                                                    : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                !isCheckedIn
                                                    ? Icons.remove_circle_outline
                                                    : isOnBreak
                                                        ? Icons.pause_circle_filled
                                                        : Icons.check_circle,
                                                size: 14,
                                                color: !isCheckedIn
                                                    ? Colors.grey
                                                    : isOnBreak
                                                        ? Colors.orange
                                                        : Colors.green,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                !isCheckedIn
                                                    ? 'Not Checked In'
                                                    : isOnBreak
                                                        ? 'On Break'
                                                        : 'Checked In',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: !isCheckedIn
                                                      ? Colors.grey.shade700
                                                      : isOnBreak
                                                          ? Colors.orange.shade800
                                                          : Colors.green.shade800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        !isCheckedIn
                                            ? ElevatedButton.icon(
                                                onPressed: () => _handleAction('/attendance/checkin', worker['worker_id']),
                                                icon: const Icon(Icons.login, size: 14, color: Colors.white),
                                                label: const Text('Check In', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xff1a2a6c),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  elevation: 0,
                                                ),
                                              )
                                            : Row(
                                                children: [
                                                  OutlinedButton.icon(
                                                    onPressed: () {
                                                      if (isOnBreak) {
                                                        // Ending a break/leave never needs a leave_type.
                                                        _handleAction('/attendance/leave/end', worker['worker_id']);
                                                      } else {
                                                        // Starting a break opens the type-selection sheet,
                                                        // which forwards the chosen leave_type itself.
                                                        _startLeaveDialog(worker['worker_id']);
                                                      }
                                                    },
                                                    icon: Icon(isOnBreak ? Icons.play_arrow : Icons.pause, size: 14, color: isOnBreak ? Colors.green : Colors.orange),
                                                    label: Text(isOnBreak ? 'End' : 'Break', style: TextStyle(fontSize: 12, color: isOnBreak ? Colors.green : Colors.orange)),
                                                    style: OutlinedButton.styleFrom(
                                                      side: BorderSide(color: isOnBreak ? Colors.green : Colors.orange),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  ElevatedButton.icon(
                                                    onPressed: () => _handleAction('/attendance/checkout', worker['worker_id']),
                                                    icon: const Icon(Icons.logout, size: 14, color: Colors.white),
                                                    label: const Text('Checkout', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.red.shade600,
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      elevation: 0,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitDay,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      label: const Text(
                        'Submit Day for Review',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff1a2a6c),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}