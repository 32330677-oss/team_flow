import 'package:flutter/material.dart';
import '../constants.dart'; 

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

  int? _selectedWorkerId;
  int? _selectedSiteId;

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
      debugPrint('خطأ في جلب البيانات: $e');
    }
    setState(() => _isLoading = false);
  }

Future<void> _createAssignment() async {
    if (_selectedWorkerId == null || _selectedSiteId == null) {
      _showSnackBar('يرجى تحديد العامل والموقع أولاً', Colors.orange);
      return;
    }
    try {
      // حذفنا السطر الخاص بـ assigned_by_user_id: 5 
      final response = await ApiConfig.dio.post('/assignments', data: {
  'worker_id': _selectedWorkerId,
  'site_id': _selectedSiteId,
});
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pop(context);
        _loadData(); 
        _showSnackBar('تم حفظ التعيين بنجاح!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('فشل حفظ البيانات', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('توزيع عامل على موقع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              DropdownButtonFormField<int>(
                hint: const Text('اختر العامل'),
                value: _selectedWorkerId,
                items: _workers.map((w) => DropdownMenuItem<int>(
                  value: int.tryParse(w['worker_id'].toString()), 
                  child: Text(w['full_name'] ?? 'بدون اسم')
                )).toList(),
                onChanged: (val) => setSheetState(() => _selectedWorkerId = val),
              ),
              DropdownButtonFormField<int>(
                hint: const Text('اختر الموقع'),
                value: _selectedSiteId,
                items: _sites.map((s) => DropdownMenuItem<int>(
                  // تأكد من مفاتيح الـ JSON هنا (مثل site_id و site_name)
                  value: int.tryParse(s['site_id']?.toString() ?? '0'), 
                  child: Text(s['site_name'] ?? 'موقع بدون اسم')
                )).toList(),
                onChanged: (val) => setSheetState(() => _selectedSiteId = val),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _createAssignment, child: const Text('حفظ التعيين')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توزيع العمال'), backgroundColor: const Color(0xff1a2a6c)),
      floatingActionButton: FloatingActionButton(onPressed: _openAddSheet, child: const Icon(Icons.link)),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _assignments.length,
        itemBuilder: (context, index) {
          final item = _assignments[index];
          return Card(
            child: ListTile(
              title: Text(item['worker_name'] ?? 'عامل'),
              subtitle: Text('الموقع: ${item["project_name"] ?? "غير محدد"}'),
            ),
          );
        },
      ),
    );
  }
}