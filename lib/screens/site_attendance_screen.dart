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
  bool _applyLunchToAll = false;
  TimeOfDay? _defaultLunchStart;
  TimeOfDay? _defaultLunchEnd;
  final Map<int, Map<String, TimeOfDay>> _lunchOverrides = {};

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    if (!mounted) return;
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
  // UNCHANGED: _handleAction still accepts an optional extraData map so
  // additional fields (leave_type, check_in_time, check_out_time...) can
  // be merged into the request payload without duplicating this method.
  // -------------------------------------------------------------------
  Future<void> _handleAction(String endpoint, int workerId, {Map<String, dynamic>? extraData}) async {
    if (!mounted) return;
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
      final data = e.response?.data;
      final msg = data is Map && data['message'] != null ? data['message'].toString() : 'Connection error';
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
  // NEW: Opens a time picker for Check-In, then converts the selected
  // time (combined with today's date, since record_date stays CURDATE()
  // on the backend) into a UTC ISO string and forwards it via extraData.
  // Same pattern used for check_in_time/check_out_time in
  // rejected_records_screen.dart's _resubmit flow.
  // -------------------------------------------------------------------
Future<void> _performCheckIn(int workerId) async {
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Select Check-In Time',
  );
  if (pickedTime == null) return;

  final now = DateTime.now();
  final selectedDateTime = DateTime(
    now.year, now.month, now.day, pickedTime.hour, pickedTime.minute,
  );

  // NOTE: no .toUtc() here. We send the literal wall-clock time the
  // Supervisor picked, exactly as-is, to avoid the timezone double-shift.
  _handleAction(
    '/attendance/checkin',
    workerId,
    extraData: {'check_in_time': selectedDateTime.toIso8601String()},
  );
}

Future<void> _performCheckOut(int workerId) async {
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Select Check-Out Time',
  );
  if (pickedTime == null) return;

  final now = DateTime.now();
  final selectedDateTime = DateTime(
    now.year, now.month, now.day, pickedTime.hour, pickedTime.minute,
  );

  await _handleAction(
    '/attendance/checkout',
    workerId,
    extraData: {'check_out_time': selectedDateTime.toIso8601String()},
  );
}


// NEW: manual end-of-break time picker, mirrors _performCheckOut.
Future<void> _performEndLeave(int workerId) async {
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Select Break End Time',
  );
  if (pickedTime == null) return;

  final now = DateTime.now();
  final selectedDateTime = DateTime(
    now.year, now.month, now.day, pickedTime.hour, pickedTime.minute,
  );

  await _handleAction(
    '/attendance/leave/end',
    workerId,
    extraData: {'leave_end_time': selectedDateTime.toIso8601String()},
  );
}
  // -------------------------------------------------------------------
  // UNCHANGED: leave/break type selection sheet.
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
            _buildLeaveOption(ctx, 'Lunch', 'Lunch Break', Icons.lunch_dining, Colors.purple),
          ],
        ),
      ),
    ),
  );

  if (type == null) return;
  if (!mounted) return;

  // NEW: ask for the break start time before submitting.
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Select Break Start Time',
  );
  if (pickedTime == null) return;

  final now = DateTime.now();
  final selectedDateTime = DateTime(
    now.year, now.month, now.day, pickedTime.hour, pickedTime.minute,
  );

  await _handleAction(
    '/attendance/leave/start',
    workerId,
    extraData: {
      'leave_type': type,
      'leave_start_time': selectedDateTime.toIso8601String(),
    },
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
                            await _fetchWorkers();
                            if (!mounted) return;
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


  String _timeText(TimeOfDay? time) => time == null ? '' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _attendanceTimeText(dynamic value) {
    if (value == null || value.toString().isEmpty) return '--:--';
    final match = RegExp(r'(?:T| )(\d{2}:\d{2})').firstMatch(value.toString());
    return match?.group(1) ?? value.toString();
  }

  Future<TimeOfDay?> _pickLunchTime(String title, TimeOfDay? initial) async {
    return showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now(), helpText: title);
  }

  Future<void> _chooseDefaultLunchStart() async {
    final value = await _pickLunchTime('Select Lunch Start', _defaultLunchStart);
    if (value != null && mounted) setState(() => _defaultLunchStart = value);
  }

  Future<void> _chooseDefaultLunchEnd() async {
    final value = await _pickLunchTime('Select Lunch End', _defaultLunchEnd);
    if (value != null && mounted) setState(() => _defaultLunchEnd = value);
  }

  Future<void> _editWorkerLunch(int workerId) async {
    final current = _lunchOverrides[workerId];
    final start = await _pickLunchTime('Select Worker Lunch Start', current?['start'] ?? _defaultLunchStart);
    if (start == null || !mounted) return;
    final end = await _pickLunchTime('Select Worker Lunch End', current?['end'] ?? _defaultLunchEnd);
    if (end == null || !mounted) return;
    setState(() {
      _lunchOverrides[workerId] = {'start': start, 'end': end};
    });
  }

  Future<void> _saveLunchTimes() async {
    if (_defaultLunchStart == null || _defaultLunchEnd == null) {
      _showToast('Select the default lunch start and end time first.', Colors.orange);
      return;
    }
    final overrides = <String, dynamic>{};
    for (final entry in _lunchOverrides.entries) {
      overrides[entry.key.toString()] = {
        'start_time': _timeText(entry.value['start']),
        'end_time': _timeText(entry.value['end']),
      };
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.post('/attendance/lunch/bulk', data: {
        'siteId': widget.siteId,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'default_start_time': _timeText(_defaultLunchStart),
        'default_end_time': _timeText(_defaultLunchEnd),
        'overrides': overrides,
      });
      await _fetchWorkers();
      if (mounted && response.data['status'] == 'success') {
        _showToast('Lunch times saved successfully.', Colors.green);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final data = e.response?.data;
      _showToast(data is Map && data['message'] != null ? data['message'].toString() : 'Failed to save lunch times.', Colors.red);
    }
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Apply same lunch time to all workers', style: TextStyle(fontWeight: FontWeight.bold)),
                            value: _applyLunchToAll,
                            onChanged: (value) => setState(() => _applyLunchToAll = value ?? false),
                          ),
                          if (_applyLunchToAll) ...[
                            Row(
                              children: [
                                Expanded(child: OutlinedButton(onPressed: _chooseDefaultLunchStart, child: Text('Start: ${_timeText(_defaultLunchStart).isEmpty ? '--:--' : _timeText(_defaultLunchStart)}'))),
                                const SizedBox(width: 8),
                                Expanded(child: OutlinedButton(onPressed: _chooseDefaultLunchEnd, child: Text('End: ${_timeText(_defaultLunchEnd).isEmpty ? '--:--' : _timeText(_defaultLunchEnd)}'))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveLunchTimes, child: const Text('Save Lunch Times'))),
                          ],
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
                            final bool hasCheckIn = worker['check_in_time'] != null;
                            final bool hasCheckOut = worker['check_out_time'] != null;
                            final bool isSubmitted = worker['workflow_status'] == 'Submitted';
                            final bool isAbsent = worker['attendance_status'] == 'Absent';
                            final bool isCheckedIn = hasCheckIn;
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
                                      children: [
                                        Expanded(child: Text('Check-in: ${_attendanceTimeText(worker['check_in_time'])}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                                        Expanded(child: Text('Check-out: ${_attendanceTimeText(worker['check_out_time'])}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(
                                          'Lunch: ${_lunchOverrides[worker['worker_id']] == null ? 'Use default' : '${_timeText(_lunchOverrides[worker['worker_id']]!['start'])} - ${_timeText(_lunchOverrides[worker['worker_id']]!['end'])}'}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                        )),
                                        TextButton.icon(
                                          onPressed: () => _editWorkerLunch(worker['worker_id']),
                                          icon: const Icon(Icons.edit, size: 14),
                                          label: const Text('Edit lunch'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
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
                                                        : hasCheckOut
                                                            ? Icons.logout
                                                            : isAbsent
                                                                ? Icons.event_busy
                                                                : Icons.check_circle,
                                                size: 14,
                                                color: !isCheckedIn
                                                    ? Colors.grey
                                                    : isOnBreak
                                                        ? Colors.orange
                                                        : hasCheckOut
                                                            ? Colors.blue
                                                            : isAbsent
                                                                ? Colors.red
                                                                : Colors.green,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                !isCheckedIn
                                                    ? 'Not Checked In'
                                                    : isOnBreak
                                                        ? 'On Break'
                                                        : hasCheckOut
                                                            ? 'Checked Out'
                                                            : isAbsent
                                                                ? 'Absent'
                                                                : 'Checked In',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: !isCheckedIn
                                                      ? Colors.grey.shade700
                                                      : isOnBreak
                                                          ? Colors.orange.shade800
                                                          : hasCheckOut
                                                              ? Colors.blue.shade800
                                                              : isAbsent
                                                                  ? Colors.red.shade800
                                                                  : Colors.green.shade800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        !hasCheckIn
                                            ? ElevatedButton.icon(
                                                onPressed: () => _performCheckIn(worker['worker_id']),
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
                                                    onPressed: (hasCheckOut || isSubmitted) ? null : () async {
  if (isOnBreak) {
    await _performEndLeave(worker['worker_id']);
  } else {
    await _startLeaveDialog(worker['worker_id']);
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
                                                    onPressed: (hasCheckOut || isSubmitted) ? null : () => _performCheckOut(worker['worker_id']),
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