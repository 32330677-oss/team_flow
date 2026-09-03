import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class BulkAttendanceScreen extends StatefulWidget {
  const BulkAttendanceScreen({super.key});

  @override
  State<BulkAttendanceScreen> createState() => _BulkAttendanceScreenState();
}

class _BulkAttendanceScreenState extends State<BulkAttendanceScreen> {
  final TextEditingController _siteIdController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  
  bool _isLoading = false;
  List<dynamic> _workers = [];
  final Set<int> _selectedWorkerIds = {};
  Map<String, dynamic>? _actionResult;
  String? _errorMessage;

  @override
  void dispose() {
    _siteIdController.dispose();
    super.dispose();
  }

  // جلب العمال عند إدخال رقم الموقع
  Future<void> _fetchWorkers(String siteId) async {
    if (siteId.isEmpty) {
      setState(() {
        _workers = [];
        _selectedWorkerIds.clear();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://your-api-domain.com/api/workers?site_id=$siteId&status=Active'),
        headers: {
          'Authorization': 'Bearer YOUR_TOKEN_HERE',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _workers = data['data'] ?? data;
          _selectedWorkerIds.clear();
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load workers for this site.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // تنفيذ عملية الحضور أو الانصراف الجماعي
  Future<void> _submitBulkAction(String mode) async {
    final siteId = _siteIdController.text.trim();
    if (siteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a site ID first.')),
      );
      return;
    }
    if (_selectedWorkerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one worker.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _actionResult = null;
    });

    // تنسيق التاريخ والوقت ليتوافق مع الباك اند (YYYY-MM-DD HH:mm:ss)
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final formattedTime = '$formattedDate ${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';

    final endpoint = mode == 'checkin' 
        ? 'https://your-api-domain.com/api/attendance/workers/bulk-checkin'
        : 'https://your-api-domain.com/api/attendance/workers/bulk-checkout';

    final payload = {
      "site_id": int.parse(siteId),
      "record_date": formattedDate,
      "worker_ids": _selectedWorkerIds.toList(),
      mode == 'checkin' ? "check_in_time" : "check_out_time": formattedTime,
    };

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer YOUR_TOKEN_HERE',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      final responseData = jsonDecode(response.body);
      setState(() {
        _actionResult = responseData;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Bulk operation error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workers Bulk Attendance'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // حقول الإدخال الأساس
            TextField(
              controller: _siteIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Site ID',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value.isNotEmpty) _fetchWorkers(value);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) setState(() => _selectedTime = picked);
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // عرض الخطأ إن وجد
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade100,
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),

            // عرض نتيجة العملية
            if (_actionResult != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${_actionResult!['status']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Successful IDs: ${_actionResult!['successful']?.join(', ') ?? 'None'}'),
                    Text('Failed Count: ${_actionResult!['failed']?.length ?? 0}'),
                  ],
                ),
              ),

            // قائمة العمال
            Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Fixed here
children: [
  const Text('Workers List', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  if (_workers.isNotEmpty)
    TextButton(
      onPressed: () {
        setState(() {
          if (_selectedWorkerIds.length == _workers.length) {
            _selectedWorkerIds.clear();
          } else {
            _selectedWorkerIds.addAll(_workers.map<int>((w) => w['worker_id'] as int));
          }
        });
      },
      child: Text(
        _selectedWorkerIds.length == _workers.length ? 'Deselect All' : 'Select All',
      ),
    ),
],
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _isLoading && _workers.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _workers.isEmpty
                      ? const Center(child: Text('No workers found. Please enter a valid site ID.'))
                      : ListView.builder(
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                            final worker = _workers[index];
                            final workerId = worker['worker_id'] as int;
                            final isSelected = _selectedWorkerIds.contains(workerId);

                            return CheckboxListTile(
                              title: Text(worker['full_name'] ?? worker['name'] ?? 'Worker #$workerId'),
                              subtitle: Text('Status: ${worker['status'] ?? 'Active'}'),
                              value: isSelected,
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedWorkerIds.add(workerId);
                                  } else {
                                    _selectedWorkerIds.remove(workerId);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),

            // الأزرار السفلية للإرسال
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    onPressed: _isLoading || _selectedWorkerIds.isEmpty ? null : () => _submitBulkAction('checkin'),
                    child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Bulk Check-In (${_selectedWorkerIds.length})'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: _isLoading || _selectedWorkerIds.isEmpty ? null : () => _submitBulkAction('checkout'),
                    child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Bulk Check-Out (${_selectedWorkerIds.length})'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}