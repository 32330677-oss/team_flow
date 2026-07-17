import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // تأكد من استيراد dio لقراءة الـ DioException
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
  String _searchQuery = "";
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
      final response = await ApiConfig.dio.post('/assignments', data: {
        'worker_id': _selectedWorkerId,
        'site_id': _selectedSiteId,
      });
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.pop(context);
        _selectedWorkerId = null; // تصفير الاختيار بعد الحفظ
        _selectedSiteId = null;   // تصفير الاختيار بعد الحفظ
        _loadData(); 
        _showSnackBar('تم حفظ التعيين بنجاح!', Colors.green);
      }
    } catch (e) {
      // تعديل ذكي: قراءة الرسالة الدقيقة القادمة من الباك-إند لمنع التكرار
      String errorMessage = 'فشل حفظ البيانات';
      if (e is DioException && e.response?.data != null) {
        errorMessage = e.response?.data['message'] ?? 'حدث خطأ غير معروف';
      }
      _showSnackBar(errorMessage, Colors.red);
    }
  }

Future<void> _deleteAssignment(int assignmentId) async {
  // إضافة تنبيه تأكيدي لمنع الأخطاء
  bool? confirm = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تأكيد'),
      content: const Text('هل أنت متأكد من إنهاء تعيين هذا العامل؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
      ],
    ),
  );

  if (confirm != true) return;

  try {
    await ApiConfig.dio.delete('/assignments/$assignmentId');
    _loadData(); // ستقوم بإعادة تحميل البيانات وسيختفي العامل فوراً لأن الباك-إند سيستثنيه
    _showSnackBar('تم إنهاء التعيين بنجاح', Colors.blue);
  } catch (e) {
    _showSnackBar('فشل إنهاء التعيين', Colors.red);
  }
}
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')), 
        backgroundColor: color
      )
    );
  }

  // فنكشن لفلترة العمال التابعين لموقع معين
  List<dynamic> _getWorkersForSite(int siteId) {
    return _assignments.where((item) => item['site_id'] == siteId).toList();
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            top: 20, 
            left: 20, 
            right: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Text(
                  'توزيع عامل على موقع', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'اختر العامل',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                value: _selectedWorkerId,
                items: _workers.map((w) => DropdownMenuItem<int>(
                  value: int.tryParse(w['worker_id'].toString()), 
                  child: Text(w['full_name'] ?? 'بدون اسم')
                )).toList(),
                onChanged: (val) => setSheetState(() => _selectedWorkerId = val),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'اختر الموقع',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                value: _selectedSiteId,
                items: _sites.map((s) => DropdownMenuItem<int>(
                  value: int.tryParse(s['site_id']?.toString() ?? '0'), 
                  child: Text(s['site_name'] ?? 'موقع بدون اسم')
                )).toList(),
                onChanged: (val) => setSheetState(() => _selectedSiteId = val),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1a2a6c),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
                onPressed: _createAssignment, 
                child: const Text('حفظ التعيين', style: TextStyle(color: Colors.white, fontSize: 16))
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
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

@override
Widget build(BuildContext context) {
 // تصفية المواقع: تشمل المواقع التي تطابق البحث بالاسم، 
  // أو المواقع التي تحتوي على عامل يطابق البحث بالاسم.
  final filteredSites = _sites.where((site) {
    final siteName = site['site_name'].toString().toLowerCase();
    final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
    
    // الحصول على عمال الموقع الحالي
    final workersInSite = _getWorkersForSite(siteId);
    
    // هل البحث يطابق اسم الموقع؟
    final matchesSiteName = siteName.contains(_searchQuery.toLowerCase());
    
    // هل البحث يطابق اسم أي عامل داخل هذا الموقع؟
    final matchesWorkerName = workersInSite.any((w) => 
      w['worker_name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
    );

    return matchesSiteName || matchesWorkerName;
  }).toList();

  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: AppBar(
      title: const Text('توزيع العمال والمواقع', style: TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xff1a2a6c),
      centerTitle: true,
    ),
    body: _isLoading 
      ? const Center(child: CircularProgressIndicator()) 
      : Column(
          children: [
            // الإحصائيات
            Padding(
  padding: const EdgeInsets.all(12),
  child: Row(
    children: [
      // إضافة لون (Color) كمعامل ثالث
      _buildStatCard('المواقع', _sites.length.toString(), const Color(0xff1a2a6c)),
      const SizedBox(width: 10),
      _buildStatCard('التعيينات', _assignments.length.toString(), Colors.blue),
    ],
  ),
),
            // حقل البحث
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
  onChanged: (val) => setState(() => _searchQuery = val),
  decoration: InputDecoration(
    hintText: 'ابحث بالموقع أو العامل...',
    prefixIcon: const Icon(Icons.search),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30), // حواف دائرية كاملة
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: BorderSide.none,
    ),
  ),
)
            ),
            // القائمة
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredSites.length,
                itemBuilder: (context, index) {
                  final site = filteredSites[index];
                  final siteId = int.tryParse(site['site_id']?.toString() ?? '0') ?? 0;
                  final siteWorkers = _getWorkersForSite(siteId);

                  // استبدل الـ Card الخاص بالـ ExpansionTile بهذا الكود داخل الـ ListView
return Card(
  elevation: 0, // تصميم مسطح وعصري
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
    subtitle: Text('عدد العمال: ${siteWorkers.length}'),
    children: siteWorkers.map((assignment) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: ListTile(
          leading: const Icon(Icons.person_outline, color: Colors.grey),
          title: Text(assignment['worker_name'] ?? 'عامل'),
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
}