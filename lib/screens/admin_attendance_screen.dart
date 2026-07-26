import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  Map<String, List<dynamic>> groupedAttendance = {};
  final Set<int> _selectedIds = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      isLoading = true;
      groupedAttendance.clear();
      _selectedIds.clear();
    });

    try {
      final response = await ApiConfig.dio.get('/admin/attendance/pending');
      
      Map<String, List<dynamic>> tempGrouped = {};
      for (var item in response.data['data']) {
        String rawDate = item['record_date']?.toString() ?? "1970-01-01";
        String date = rawDate.substring(0, 10);

        if (!tempGrouped.containsKey(date)) {
          tempGrouped[date] = [];
        }
        tempGrouped[date]!.add(item);
      }

      setState(() {
        groupedAttendance = tempGrouped;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching data: $e");
      setState(() => isLoading = false);
      _showSnackBar('Failed to fetch data', Colors.red);
    }
  }

  Future<void> _reviewMultiple(List<int> ids, String status, {String? note}) async {
    if (ids.isEmpty) return;
    setState(() => isLoading = true);

    try {
      for (int id in ids) {
        await ApiConfig.dio.post('/admin/attendance/review', data: {
          'attendance_id': id,
          'status': status,
          'admin_note': note,
        });
      }

      _showSnackBar('Selected records processed successfully', Colors.green);
      await _fetchData();
    } on DioException catch (e) {
      String errorMessage = 'An unexpected error occurred';
      if (e.response != null && e.response!.data['message'] != null) {
        errorMessage = e.response!.data['message'];
      }
      _showSnackBar(errorMessage, Colors.red);
    } catch (e) {
      _showSnackBar('Server connection error', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<String?> _showRejectDialog(BuildContext context) {
    TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rejection Reason"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter rejection reason for supervisor...",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text("Confirm Reject", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // نافذة الإعدادات السريعة لأوقات الدوام والاستراحات
Future<void> _showSettingsDialog(BuildContext context) async {
    TimeOfDay? lunchStart;
    TimeOfDay? lunchEnd;
    TextEditingController workMinutesController = TextEditingController();
    bool isFetchingSettings = true;

    // دالة مساعدة لتحويل TimeOfDay إلى نص HH:mm
    String timeToString(TimeOfDay time) {
      final hours = time.hour.toString().padLeft(2, '0');
      final minutes = time.minute.toString().padLeft(2, '0');
      return '$hours:$minutes';
    }

    // دالة مساعدة لتحويل نص القادم من الباكت إند إلى TimeOfDay
 TimeOfDay parseTimeString(String? timeStr) {
      if (timeStr == null || timeStr.isEmpty) {
        return const TimeOfDay(hour: 12, minute: 0);
      }
      try {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } catch (_) {}
      return const TimeOfDay(hour: 12, minute: 0);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            if (isFetchingSettings) {
              ApiConfig.dio.get('/admin/attendance/settings/breaks').then((res) {
                if (res.data['status'] == 'success') {
                  final data = res.data['data'];
                  lunchStart = parseTimeString(data['lunch_start_time'] ?? '12:00');
                  lunchEnd = parseTimeString(data['lunch_end_time'] ?? '13:00');
                  workMinutesController.text = data['standard_work_minutes']?.toString() ?? '480';
                  setStateDialog(() => isFetchingSettings = false);
                }
              }).catchError((_) {
                setStateDialog(() => isFetchingSettings = false);
              });
            }

            return AlertDialog(
              title: const Text("Break & Work Settings"),
              content: isFetchingSettings
                  ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Lunch Break Time Window", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          
                          // زر اختيار وقت بداية الغداء
                          ListTile(
                            tileColor: Colors.grey.shade100,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            title: Text("Start Time: ${lunchStart != null ? lunchStart!.format(context) : 'Select'}"),
                            trailing: const Icon(Icons.access_time),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: lunchStart ?? const TimeOfDay(hour: 12, minute: 0),
                              );
                              if (picked != null) {
                                setStateDialog(() => lunchStart = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 8),

                          // زر اختيار وقت نهاية الغداء
                          ListTile(
                            tileColor: Colors.grey.shade100,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            title: Text("End Time: ${lunchEnd != null ? lunchEnd!.format(context) : 'Select'}"),
                            trailing: const Icon(Icons.access_time),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: lunchEnd ?? const TimeOfDay(hour: 13, minute: 0),
                              );
                              if (picked != null) {
                                setStateDialog(() => lunchEnd = picked);
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // حقل دقائق الدوام الكامل
                          TextField(
                            controller: workMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Standard Work Minutes (e.g. 480)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () async {
                    // Restriction: التحقق أن وقت النهاية بعد وقت البداية
                    if (lunchStart != null && lunchEnd != null) {
                      int startMinutes = lunchStart!.hour * 60 + lunchStart!.minute;
                      int endMinutes = lunchEnd!.hour * 60 + lunchEnd!.minute;

                      if (endMinutes <= startMinutes) {
                        _showSnackBar('Error: Lunch end time must be after start time!', Colors.red);
                        return;
                      }
                    }

                    try {
                      await ApiConfig.dio.put('/admin/attendance/settings/breaks', data: {
  'lunch_start_time': lunchStart != null ? timeToString(lunchStart!) : null,
  'lunch_end_time': lunchEnd != null ? timeToString(lunchEnd!) : null,
  'standard_work_minutes': int.tryParse(workMinutesController.text) ?? 480,
});
                      Navigator.pop(ctx);
                      _showSnackBar('Settings updated successfully', Colors.green);
                    } catch (e) {
                      print("=== FULL ERROR DETAILS ===");
                      print(e);
                      if (e is DioException) {
                        print("Response data: ${e.response?.data}");
                        print("Response status: ${e.response?.statusCode}");
                      }
                      
                      String errorMsg = 'Failed to update settings';
                      if (e is DioException && e.response?.data != null) {
                        if (e.response?.data is Map && e.response?.data['message'] != null) {
                          errorMsg = e.response?.data['message'];
                        }
                      }
                      _showSnackBar(errorMsg, Colors.red);
                    }
                  },
                  child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleSelectAllForDate(String date, List<dynamic> items, bool? value) {
    setState(() {
      for (var item in items) {
        int id = item['attendance_id'];
        if (value == true) {
          _selectedIds.add(id);
        } else {
          _selectedIds.remove(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Attendance Review"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Break & Work Settings',
            onPressed: () => _showSettingsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : groupedAttendance.isEmpty
              ? const Center(
                  child: Text(
                    "No pending records to review 🎉",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(8.0),
                  children: groupedAttendance.keys.map((date) {
                    List<dynamic> dayItems = groupedAttendance[date]!;
                    
                    bool isDayAllSelected = dayItems.isNotEmpty &&
                        dayItems.every((item) => _selectedIds.contains(item['attendance_id']));
                    
                    List<int> daySelectedIds = dayItems
                        .where((item) => _selectedIds.contains(item['attendance_id']))
                        .map<int>((item) => item['attendance_id'] as int)
                        .toList();

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Row(
                          children: [
                            Checkbox(
                              value: isDayAllSelected,
                              onChanged: (val) => _toggleSelectAllForDate(date, dayItems, val),
                            ),
                            Expanded(
                              child: Text(
                                "Date: $date",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: daySelectedIds.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(left: 48.0, bottom: 8.0, right: 8.0),
                                child: Wrap(
                                  spacing: 8.0,
                                  runSpacing: 4.0,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      icon: const Icon(Icons.check, color: Colors.white, size: 18),
                                      label: Text("Approve (${daySelectedIds.length})", style: const TextStyle(color: Colors.white)),
                                      onPressed: () => _reviewMultiple(daySelectedIds, 'Approved'),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      icon: const Icon(Icons.cancel, color: Colors.white, size: 18),
                                      label: Text("Reject (${daySelectedIds.length})", style: const TextStyle(color: Colors.white)),
                                      onPressed: () async {
                                        String? note = await _showRejectDialog(context);
                                        if (note != null && note.trim().isNotEmpty) {
                                          _reviewMultiple(daySelectedIds, 'Rejected', note: note);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              )
                            : null,
                        children: dayItems.map((item) {
                          int id = item['attendance_id'];
                          bool isSelected = _selectedIds.contains(id);
                          bool isRejected = item['status'] == 'Rejected';

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isRejected ? Colors.red.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Colors.blue : (isRejected ? Colors.red.shade200 : Colors.grey.shade300),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                              leading: Checkbox(
                                value: isSelected,
                                onChanged: (bool? val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.add(id);
                                    } else {
                                      _selectedIds.remove(id);
                                    }
                                  });
                                },
                              ),
                              title: Text(
                                item['full_name'] ?? 'Worker',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text("Site: ${item['site_name']}", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                  Text("Status: ${item['status']}", style: const TextStyle(fontSize: 12)),
                                  if (isRejected && item['admin_rejection_notes'] != null)
                                    Text(
                                      "Note: ${item['admin_rejection_notes']}",
                                      style: const TextStyle(color: Colors.red, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 26),
                                    onPressed: () => _reviewMultiple([id], 'Approved'),
                                    tooltip: 'Approve Single',
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    icon: const Icon(Icons.cancel, color: Colors.red, size: 26),
                                    onPressed: () async {
                                      String? note = await _showRejectDialog(context);
                                      if (note != null && note.trim().isNotEmpty) {
                                        _reviewMultiple([id], 'Rejected', note: note);
                                      }
                                    },
                                    tooltip: 'Reject Single',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}