import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart';
import 'package:dio/dio.dart';
import '../widgets/app_data_table.dart';
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
String _recordDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final Set<int> _selectedWorkerIds = <int>{};
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
      final response = await ApiConfig.dio.get(
        '/attendance/sites/${widget.siteId}/workers',
        queryParameters: {'record_date': _recordDate},
      );
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
        'record_date': _recordDate,
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

  Future<void> _chooseAttendanceDate() async {
    final current = DateTime.parse(_recordDate);
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select attendance date',
    );
    if (selected == null || !mounted) return;

    setState(() {
      _recordDate = DateFormat('yyyy-MM-dd').format(selected);
    });
    await _fetchWorkers();
  }

  void _setRecordDateFromManualDateTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return;
    final nextDate = DateFormat('yyyy-MM-dd').format(parsed);
    if (nextDate != _recordDate && mounted) {
      setState(() => _recordDate = nextDate);
    }
  }

  bool _canBulkCheckIn(Map worker) {
    final workflow = worker['workflow_status']?.toString();
    return workflow == null || workflow == 'Draft';
  }

  bool _canBulkCheckOut(Map worker) {
    final workflow = worker['workflow_status']?.toString();
    return workflow == 'Draft' && worker['check_in_time'] != null && worker['check_out_time'] == null;
  }

  List<int> _eligibleSelectedWorkerIds(bool checkIn) {
    return _workers.where((worker) {
      final id = int.tryParse(worker['worker_id'].toString());
      if (id == null || !_selectedWorkerIds.contains(id)) return false;
      return checkIn ? _canBulkCheckIn(worker) && worker['check_in_time'] == null : _canBulkCheckOut(worker);
    }).map<int>((worker) => int.parse(worker['worker_id'].toString())).toList();
  }

  Future<void> _bulkAttendanceAction({required bool checkIn}) async {
    final workerIds = _eligibleSelectedWorkerIds(checkIn);
    if (workerIds.isEmpty) {
      _showToast(checkIn ? 'Select workers who are not checked in.' : 'Select workers who are checked in and not checked out.', Colors.orange);
      return;
    }
    final selectedDateTime = await _pickLocalDateTime(helpText: checkIn ? 'Select Bulk Check-In Time' : 'Select Bulk Check-Out Time');
    if (selectedDateTime == null) return;
    if (checkIn) _setRecordDateFromManualDateTime(selectedDateTime);

    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.post(
        checkIn ? '/attendance/bulk/checkin' : '/attendance/bulk/checkout',
        data: {
          'site_id': widget.siteId,
          'record_date': _recordDate,
          'worker_ids': workerIds,
          checkIn ? 'check_in_time' : 'check_out_time': selectedDateTime,
        },
      );
      final data = response.data is Map ? response.data as Map : <String, dynamic>{};
      final successful = (data['successful'] as List?)?.length ?? 0;
      final failed = (data['failed'] as List?)?.length ?? 0;
      if (mounted) {
        setState(() => _selectedWorkerIds.removeAll(workerIds));
        _showToast(failed == 0 ? '$successful workers updated successfully.' : '$successful updated, $failed failed.', failed == 0 ? Colors.green : Colors.orange);
      }
      await _fetchWorkers();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final data = e.response?.data;
      _showToast(data is Map && data['message'] != null ? data['message'].toString() : 'Bulk attendance action failed.', Colors.red);
    }
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showAttendanceStatusDialog(int workerId, {String? currentStatus}) async {
    final selectedStatus = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Set Worker Status'),
        children: [
          _statusOption(dialogContext, 'Absent', 'Absent', Icons.person_off, Colors.red),
          _statusOption(dialogContext, 'Sick', 'Sick Leave', Icons.sick, Colors.orange),
          _statusOption(dialogContext, 'Vacation', 'Annual Leave', Icons.beach_access, Colors.blue),
          _statusOption(dialogContext, 'Holiday', 'Holiday', Icons.event, Colors.purple),
        ],
      ),
    );

    if (selectedStatus == null || !mounted) return;
    await _handleAction(
      '/attendance/status',
      workerId,
      extraData: {
        'attendance_status': selectedStatus,
        'remarks': '$selectedStatus - recorded by supervisor',
      },
    );
  }

  Widget _statusOption(BuildContext context, String value, String label, IconData icon, Color color) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  // Sends a local wall-clock datetime without UTC conversion. The date is
  // selected explicitly so a night shift can end after midnight.
  Future<String?> _pickLocalDateTime({required String helpText, DateTime? initial}) async {
    final seed = initial ?? DateTime.parse(_recordDate);
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(seed.year, seed.month, seed.day),
      firstDate: DateTime(seed.year, seed.month, seed.day).subtract(const Duration(days: 1)),
      lastDate: DateTime(seed.year, seed.month, seed.day).add(const Duration(days: 2)),
      helpText: 'Select date',
    );
    if (selectedDate == null || !mounted) return null;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
      helpText: helpText,
    );
    if (selectedTime == null) return null;

    // Deliberately omit Z/toUtc(): backend stores supervisor-selected local time.
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    ));
  }

  // -------------------------------------------------------------------
  // Opens a manual picker and sends a literal local wall-clock datetime.
  // The selected shift date is propagated separately as record_date.
  // -------------------------------------------------------------------
Future<void> _performCheckIn(int workerId) async {
  final selectedDateTime = await _pickLocalDateTime(helpText: 'Select Check-In Time');
  if (selectedDateTime == null) return;
  _setRecordDateFromManualDateTime(selectedDateTime);

  await _handleAction(
    '/attendance/checkin',
    workerId,
    extraData: {'check_in_time': selectedDateTime},
  );
}

Future<void> _performCheckOut(int workerId) async {
  final selectedDateTime = await _pickLocalDateTime(helpText: 'Select Check-Out Date and Time');
  if (selectedDateTime == null) return;

  await _handleAction(
    '/attendance/checkout',
    workerId,
    extraData: {'check_out_time': selectedDateTime},
  );
}


// NEW: manual end-of-break time picker, mirrors _performCheckOut.
Future<void> _performEndLeave(int workerId) async {
  final selectedDateTime = await _pickLocalDateTime(helpText: 'Select Break End Date and Time');
  if (selectedDateTime == null) return;

  await _handleAction(
    '/attendance/leave/end',
    workerId,
    extraData: {'leave_end_time': selectedDateTime},
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
            _buildLeaveOption(ctx, 'Lunch', 'Lunch Break', Icons.lunch_dining, Colors.purple),
          ],
        ),
      ),
    ),
  );

  if (type == null) return;
  if (!mounted) return;

  // Select the calendar date explicitly so breaks can cross midnight safely.
  final selectedDateTime = await _pickLocalDateTime(helpText: 'Select Break Start Date and Time');
  if (selectedDateTime == null) return;

  await _handleAction(
    '/attendance/leave/start',
    workerId,
    extraData: {
      'leave_type': type,
      'leave_start_time': selectedDateTime,
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
        'date': _recordDate,
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
      final response = await ApiConfig.dio.post(
        '/attendance/submit',
        data: {
          'siteId': widget.siteId,
          'record_date': _recordDate,
        },
      );
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


  Widget _buildWorkersTable() {
    if (_workers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text(
              'All workers accounted for or none available!',
              style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final rows = _workers.map<DataRow>((worker) {
      final workerId = int.parse(worker['worker_id'].toString());
      final hasCheckIn = worker['check_in_time'] != null;
      final hasCheckOut = worker['check_out_time'] != null;
      final workflowStatus = worker['workflow_status']?.toString();
      final attendanceStatus = worker['attendance_status']?.toString();
      final isSubmitted = workflowStatus == 'Submitted';
      final isDraft = workflowStatus == null || workflowStatus == 'Draft';
      final isRejected = workflowStatus == 'Rejected';
      final isOnBreak = worker['current_leave_id'] != null;

      final status = isRejected
          ? 'Rejected'
          : attendanceStatus == 'Absent'
              ? 'Absent'
              : attendanceStatus == 'Sick'
                  ? 'Sick Leave'
                  : attendanceStatus == 'Vacation'
                      ? 'Annual Leave'
                      : attendanceStatus == 'Holiday'
                          ? 'Holiday'
                          : isOnBreak
                              ? 'On Break'
                              : hasCheckOut
                                  ? 'Checked Out'
                                  : hasCheckIn
                                      ? 'Checked In'
                                      : 'Not Checked In';

      final statusColor = isRejected
          ? Colors.red
          : status == 'Absent'
              ? Colors.red
              : status == 'Sick Leave'
                  ? Colors.orange
                  : status == 'Annual Leave'
                  ? Colors.blue
                      : status == 'Holiday'
                          ? Colors.purple
              : status == 'On Break'
                  ? Colors.orange
                  : status == 'Checked In'
                      ? Colors.green
                      : status == 'Checked Out'
                          ? Colors.blue
                          : Colors.grey;

      return DataRow(cells: [
        DataCell(
          SizedBox(
            width: 180,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xff1a2a6c).withOpacity(0.10),
                  child: Text(
                    (worker['full_name'] ?? 'W').toString().substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Color(0xff1a2a6c), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    worker['full_name']?.toString() ?? 'Worker',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
        ),
        DataCell(Text(_attendanceTimeText(worker['check_in_time']))),
        DataCell(Text(_attendanceTimeText(worker['check_out_time']))),
        DataCell(
          PopupMenuButton<String>(
            tooltip: 'Worker actions',
            icon: const Icon(Icons.more_horiz, color: Color(0xff1a2a6c)),
            onSelected: (action) async {
              switch (action) {
                case 'status':
                  await _showAttendanceStatusDialog(workerId, currentStatus: attendanceStatus);
                  break;
                case 'checkin':
                  await _performCheckIn(workerId);
                  break;
                case 'break':
                  if (isOnBreak) {
                    await _performEndLeave(workerId);
                  } else {
                    await _startLeaveDialog(workerId);
                  }
                  break;
                case 'checkout':
                  await _performCheckOut(workerId);
                  break;
                case 'lunch':
                  await _editWorkerLunch(workerId);
                  break;
                case 'transfer':
                  await _openTransferSheet(worker);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'status',
                enabled: !hasCheckIn && isDraft,
                child: Text(attendanceStatus == null ? 'Set status' : 'Edit status'),
              ),
              PopupMenuItem(
                value: 'checkin',
                enabled: !hasCheckIn && !isRejected && isDraft,
                child: const Text('Check In'),
              ),
              PopupMenuItem(
                value: 'break',
                enabled: hasCheckIn && !hasCheckOut && !isSubmitted && !isRejected,
                child: Text(isOnBreak ? 'End Break' : 'Start Break'),
              ),
              PopupMenuItem(
                value: 'checkout',
                enabled: hasCheckIn && !hasCheckOut && !isSubmitted && !isRejected,
                child: const Text('Check Out'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'lunch', child: Text('Edit Lunch')),
              const PopupMenuItem(value: 'transfer', child: Text('Transfer Worker')),
            ],
          ),
        ),
        DataCell(
          Checkbox(
            value: _selectedWorkerIds.contains(workerId),
            onChanged: (checked) => setState(() {
              if (checked == true) {
                _selectedWorkerIds.add(workerId);
              } else {
                _selectedWorkerIds.remove(workerId);
              }
            }),
          ),
        ),
      ]);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: AppDataTableCard(
        title: 'Workers Attendance',
        subtitle: '${_workers.length} workers',
        icon: Icons.groups_rounded,
        accentColor: const Color(0xff1a2a6c),
        padding: const EdgeInsets.all(12),
        columns: const [
          DataColumn(label: Text('Worker')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Check In')),
          DataColumn(label: Text('Check Out')),
          DataColumn(label: Text('Actions')),
          DataColumn(label: Text('Select')),
        ],
        rows: rows,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('yyyy/MM/dd').format(DateTime.parse(_recordDate));

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
                                    InkWell(
                                      onTap: _chooseAttendanceDate,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Text('Selected', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                            SizedBox(width: 4),
                                            Icon(Icons.edit_calendar, size: 13, color: Colors.green),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tap the date to change the manual shift date',
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
                          Row(
                            children: [
                              Checkbox(
                                value: _workers.isNotEmpty && _selectedWorkerIds.length == _workers.length,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedWorkerIds.addAll(_workers.map<int>((w) => int.parse(w['worker_id'].toString())));
                                    } else {
                                      _selectedWorkerIds.clear();
                                    }
                                  });
                                },
                              ),
                              const Expanded(child: Text('Select all workers', style: TextStyle(fontWeight: FontWeight.bold))),
                              Text('${_selectedWorkerIds.length} selected', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: ElevatedButton.icon(onPressed: _selectedWorkerIds.isEmpty ? null : () => _bulkAttendanceAction(checkIn: true), icon: const Icon(Icons.login), label: const Text('Bulk Check-in'))),
                              const SizedBox(width: 8),
                              Expanded(child: ElevatedButton.icon(onPressed: _selectedWorkerIds.isEmpty ? null : () => _bulkAttendanceAction(checkIn: false), icon: const Icon(Icons.logout), label: const Text('Bulk Check-out'))),
                            ],
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
                Expanded(child: _buildWorkersTable()),
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