import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class ContractSitesScreen extends StatefulWidget {
  final int contractId;
  final String contractName;

  const ContractSitesScreen({
    super.key,
    required this.contractId,
    required this.contractName,
  });

  @override
  State<ContractSitesScreen> createState() => _ContractSitesScreenState();
}

class _ContractSitesScreenState extends State<ContractSitesScreen> {
  final Dio _dio = Dio();
  late final String _apiUrl;
  
  List _sites = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiUrl = 'http://192.168.1.3:5000/api/sites';
    _fetchSites();
  }

  // 1. جلب المواقع التابعة للعقد الحالي
  Future<void> _fetchSites() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get('$_apiUrl/contract/${widget.contractId}');
      if (response.data['status'] == 'success') {
        setState(() {
          _sites = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل جلب مواقع العقد'), backgroundColor: Colors.red),
      );
    }
  }

  // 2. إضافة موقع جديد مربوط بالعقد الحالي
  Future<void> _addSite() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await _dio.post(_apiUrl, data: {
  'site_name': _nameController.text.trim(),
  'location': _detailsController.text.trim(), // 👈 تم تعديل المفتاح هنا إلى location
  'contract_id': widget.contractId, 
  'supervisor_id': null 
      });

      if (response.data['status'] == 'success') {
        Navigator.pop(context);
        _nameController.clear();
        _detailsController.clear();
        _fetchSites(); // تحديث القائمة فوراً
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء الموقع بنجاح!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
  // 👈 أضف هذا السطر لمراقبة الخطأ الحقيقي
  print("🚨 DIO ERROR DETAILS: $e");
  
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('فشل إنشاء الموقع الجديد'), backgroundColor: Colors.red),
  );
}
  }

  // 3. نافذة إضافة موقع جديد (Dialog)
  void _showAddSiteDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20, left: 20, right: 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('إضافة موقع لـ ${widget.contractName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'اسم الموقع / القطاع *', border: OutlineInputBorder()),
                  validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال اسم الموقع' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detailsController,
                  decoration: const InputDecoration(labelText: 'تفاصيل الموقع الجغرافي أو العنوان', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
  onPressed: () => _addSite(), // 👈 التعديل هنا لضمان تشغيل الدالة فوراً
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xffb21f1f), 
    padding: const EdgeInsets.symmetric(vertical: 12)
  ),
  child: const Text('حفظ الموقع', style: TextStyle(color: Colors.white, fontSize: 16)),
),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مواقع: ${widget.contractName}'),
        backgroundColor: const Color(0xffb21f1f), 
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSiteDialog,
        backgroundColor: const Color(0xffb21f1f),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sites.isEmpty
              ? const Center(child: Text('لا يوجد مواقع مسجلة لهذا العقد حالياً', style: TextStyle(fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _sites.length,
                  itemBuilder: (context, index) {
                    final site = _sites[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.location_on, color: Colors.white, size: 20),
                        ),
                        title: Text(site['site_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('العنوان: ${site['location_details'] ?? 'غير محدد'}\nالمشرف: ${site['supervisor_name'] ?? 'لم يتم تعيين مشرف بعد'}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: site['status'] == 'Active' ? Colors.green.shade100 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
  site['site_status'] == 'Active' ? 'نشط' : 'متوقف', // 👈 التعديل هنا لـ site_status
  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}