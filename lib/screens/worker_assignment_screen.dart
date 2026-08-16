import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/searchable_picker_sheet.dart';
import '../widgets/custom_app_bar.dart';
class WorkerAssignmentScreen extends StatefulWidget {
  const WorkerAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<WorkerAssignmentScreen> createState() => _WorkerAssignmentScreenState();
}

class _WorkerAssignmentScreenState extends State<WorkerAssignmentScreen> {
  List<dynamic> _assignments = [];
  List<dynamic> _workers = [];
  List<dynamic> _sites = []; 
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final resWorkers = await ApiConfig.dio.get('/workers');
      if (resWorkers.statusCode == 200) _workers = resWorkers.data['data'] ?? [];
      
      final resSites = await ApiConfig.dio.get('/sites/all-sites');
      if (resSites.statusCode == 200) _sites = resSites.data['data'] ?? [];
      
      final resAssignments = await ApiConfig.dio.get('/assignments');
      if (resAssignments.statusCode == 200) _assignments = resAssignments.data['data'] ?? [];
      
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteAssignment(int assignmentId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: const Text('Are you sure you want to end this worker assignment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiConfig.dio.delete('/assignments/$assignmentId');
      _loadData(); 
      _showSnackBar('Assignment ended successfully', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed to end assignment', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color, {Duration? duration}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<dynamic> _getWorkersForSite(int siteId) {
    return _assignments.where((item) => item['site_id'] == siteId).toList();
  }

  // فتح نافذة الإضافة كـ Stateful Bottom Sheet مستقلة لضمان استجابة الأزرار
  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddAssignmentSheet(
        workers: _workers,
        sites: _sites,
        onAssigned: () {
          _loadData();
          _showSnackBar('Assignment saved successfully!', Colors.green);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSites = _sites.where((site) {
      final siteName = site['site_name'].toString().toLowerCase();
      final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
      final workersInSite = _getWorkersForSite(siteId);
      
      final matchesSiteName = siteName.contains(_searchQuery.toLowerCase());
      final matchesWorkerName = workersInSite.any((w) => 
        w['worker_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
      );

      return matchesSiteName || matchesWorkerName;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
     appBar: CustomAppBar(
        title: 'Workers & Sites Distribution',
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _buildStatCard('Sites', _sites.length.toString(), const Color(0xff1a2a6c)),
                    const SizedBox(width: 10),
                    _buildStatCard('Assignments', _assignments.length.toString(), Colors.blue),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by site or worker...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredSites.length,
                  itemBuilder: (context, index) {
                    final site = filteredSites[index];
                    final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
                    final siteWorkers = _getWorkersForSite(siteId);

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xff1a2a6c).withOpacity(0.1),
                          child: const Icon(Icons.business, color: Color(0xff1a2a6c)),
                        ),
                        title: Text(site['site_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Workers Count: ${siteWorkers.length}'),
                        children: siteWorkers.map((assignment) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border(top: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.person_outline, color: Colors.grey),
                              title: Text(assignment['worker_name'] ?? 'Worker'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                onPressed: () => _deleteAssignment(assignment['assignment_id']),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xff1a2a6c),
        onPressed: _openAddSheet,
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Text(title, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 5),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ويدجت منفصل خاص بنافذة الإضافة لضمان استجابة الأزرار وحالة الحقول بشكل مثالي
class _AddAssignmentSheet extends StatefulWidget {
  final List<dynamic> workers;
  final List<dynamic> sites;
  final VoidCallback onAssigned;

  const _AddAssignmentSheet({
    required this.workers,
    required this.sites,
    required this.onAssigned,
  });

  @override
  State<_AddAssignmentSheet> createState() => _AddAssignmentSheetState();
}

class _AddAssignmentSheetState extends State<_AddAssignmentSheet> {
  int? _selectedWorkerId;
  int? _selectedSiteId;
  Map<String, dynamic>? _selectedWorkerObj;
  Map<String, dynamic>? _selectedSiteObj;
  bool _isSubmitting = false;
  String? _errorMessage; // متغير لحفظ وإظهار الخطأ داخل النافذة مباشرة

  Future<void> _submit() async {
    setState(() => _errorMessage = null); // إعادة تعيين الخطأ عند المحاولة الجديدة

    if (_selectedWorkerId == null || _selectedSiteId == null) {
      setState(() => _errorMessage = 'Please select both worker and site first');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiConfig.dio.post('/assignments', data: {
        'worker_id': _selectedWorkerId,
        'site_id': _selectedSiteId,
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pop(context);
        widget.onAssigned();
      }
    } on DioException catch (e) {
      final errorMessage = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Failed to save data')
          : 'Failed to save data';

      setState(() => _errorMessage = errorMessage);
    } catch (e) {
      setState(() => _errorMessage = 'Connection error, please try again');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              'Assign Worker to Site', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
          ),
          const SizedBox(height: 20),
          
          InkWell(
            onTap: () async {
              final picked = await SearchablePickerSheet.show<dynamic>(
                context,
                title: 'Select Worker',
                items: widget.workers,
                labelBuilder: (w) => w['full_name'] ?? '',
                subtitleBuilder: (w) => 'ID: ${w['worker_unique_id'] ?? ''}',
              );
              if (picked != null) {
                setState(() {
                  _selectedWorkerObj = picked;
                  _selectedWorkerId = int.tryParse(picked['worker_id'].toString());
                  _errorMessage = null; // إزالة الخطأ عند الاختيار
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Worker',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              child: Text(
                _selectedWorkerObj?['full_name'] ?? 'Click to search & select worker',
                style: TextStyle(
                  color: _selectedWorkerObj != null ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          InkWell(
            onTap: () async {
              final picked = await SearchablePickerSheet.show<dynamic>(
                context,
                title: 'Select Site',
                items: widget.sites,
                labelBuilder: (s) => s['site_name'] ?? '',
              );
              if (picked != null) {
                setState(() {
                  _selectedSiteObj = picked;
                  _selectedSiteId = int.tryParse(picked['site_id'].toString());
                  _errorMessage = null; // إزالة الخطأ عند الاختيار
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Site',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              child: Text(
                _selectedSiteObj?['site_name'] ?? 'Click to search & select site',
                style: TextStyle(
                  color: _selectedSiteObj != null ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
          ),

          // عرض رسالة الخطأ بوضوح داخل النافذة المنبثقة مباشرة إن وجدت
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff1a2a6c),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Save Assignment', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}