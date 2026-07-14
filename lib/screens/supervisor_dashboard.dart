import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/screens/site_attendance_screen.dart';
class SupervisorDashboard extends StatefulWidget {
  final int supervisorId;
  final String supervisorName;

  const SupervisorDashboard({
    super.key,
    required this.supervisorId,
    required this.supervisorName,
  });

  @override
  State<SupervisorDashboard> createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard> {
  final Dio _dio = Dio();
  final String _apiUrl = 'http://192.168.1.3:5000/api/sites/supervisor';
  
  List _mySites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMySites();
  }

  // جلب المواقع المسؤولة عنها هذا المشرف تلقائياً
  Future<void> _fetchMySites() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get('$_apiUrl/${widget.supervisorId}');
      if (response.data['status'] == 'success') {
        setState(() {
          _mySites = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل جلب المواقع المسؤولة عنها'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المشرف'),
        backgroundColor: const Color(0xffb21f1f),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // هنا تضع منطق تسجيل الخروج والعودة لشاشة الـ Login
              Navigator.pushReplacementNamed(context, '/login'); 
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ترحيب بالمشرف
            Text(
              'مرحباً بك، ${widget.supervisorName} 👋',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 5),
            const Text(
              'المواقع الجغرافية المسؤولة عن متابعتها وتثبيت عمالها اليوم:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // قائمة المواقع المربوطة بالمشرف
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _mySites.isEmpty
                      ? const Center(
                          child: Text(
                            'لم يتم تعيين أي مواقع لك بعد.\nيرجى مراجعة الإدارة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _mySites.length,
                          itemBuilder: (context, index) {
                            final site = _mySites[index];
                            return Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => SiteAttendanceScreen(
        siteId: site['site_id'],   // مرر الـ site_id الديناميكي من الكرت
        siteName: site['site_name'], // مرر اسم الموقع لعرضه بالـ AppBar
      ),
    ),
  ); // <--- تأكد من وجود الفاصلة المنقوطة هنا لقفل الـ push
},
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 25,
                                        backgroundColor: Colors.orange,
                                        child: Icon(Icons.location_on, color: Colors.white, size: 28),
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              site['site_name'],
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'العقد: ${site['contract_name'] ?? 'غير محدد'} (${site['project_name'] ?? ''})',
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.map, size: 14, color: Colors.grey),
                                                const SizedBox(width: 4),
                                                Text(
                                                  site['location'] ?? 'موقع غير محدد جغرافياً',
                                                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}