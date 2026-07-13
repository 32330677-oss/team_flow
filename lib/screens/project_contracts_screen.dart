import 'contract_sites_screen.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
class ProjectContractsScreen extends StatefulWidget {
  final int projectId;
  final String projectName;

  const ProjectContractsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<ProjectContractsScreen> createState() => _ProjectContractsScreenState();
}

class _ProjectContractsScreenState extends State<ProjectContractsScreen> {
  final Dio _dio = Dio();
  late final String _apiUrl;
  
  List _contracts = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _overtimeRateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // تحضير رابط جلب العقود بناءً على الـ ID الخاص بالمشروع الحالي
    _apiUrl = 'http://192.168.1.3:5000/api/contracts';
    _fetchContracts();
  }

  // 1. جلب عقود المشروع
  Future<void> _fetchContracts() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get('$_apiUrl/project/${widget.projectId}');
      if (response.data['status'] == 'success') {
        setState(() {
          _contracts = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل جلب عقود المشروع'), backgroundColor: Colors.red),
      );
    }
  }

  // 2. إضافة عقد جديد مربوط بالمشروع الحالي
  Future<void> _addContract() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await _dio.post(_apiUrl, data: {
        'contract_name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'project_id': widget.projectId, // 👈 ربط تلقائي بالمشروع الحالي
        'hourly_rate': double.parse(_rateController.text.trim()),
        'overtime_hourly_rate': double.parse(_overtimeRateController.text.trim()),
        'admin_id': null // يمكن تمريره لاحقاً من التوكن
      });

      if (response.data['status'] == 'success') {
        Navigator.pop(context);
        _nameController.clear();
        _descController.clear();
        _rateController.clear();
        _overtimeRateController.clear();
        _fetchContracts(); // تحديث القائمة
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة العقد بنجاح!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إنشاء العقد الجديد'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddContractDialog() {
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
                Text('إضافة عقد لـ ${widget.projectName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'اسم العقد *', border: OutlineInputBorder()),
                  validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال اسم العقد' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'الوصف أو التفاصيل', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'أجر الساعة العادي *', border: OutlineInputBorder(), prefixText: '\$ '),
                  validator: (value) => value == null || value.isEmpty ? 'الرجاء تحديد أجر الساعة' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _overtimeRateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'أجر ساعة الإضافي (Overtime) *', border: OutlineInputBorder(), prefixText: '\$ '),
                  validator: (value) => value == null || value.isEmpty ? 'الرجاء تحديد أجر الإضافي' : null,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _addContract,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffb21f1f), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('حفظ العقد', style: TextStyle(color: Colors.white, fontSize: 16)),
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
        title: Text('عقود: ${widget.projectName}'),
        backgroundColor: const Color(0xffb21f1f), // اللون الأحمر المخصص للعقود حسب الـ Dashboard
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContractDialog,
        backgroundColor: const Color(0xffb21f1f),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contracts.isEmpty
              ? const Center(child: Text('لا يوجد عقود مسجلة لهذا المشروع حالياً', style: TextStyle(fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _contracts.length,
                  itemBuilder: (context, index) {
                    final contract = _contracts[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        onTap: () {
    // 👈 عند الضغط على العقد، ننتقل لشاشة المواقع الخاصة به
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContractSitesScreen(
          contractId: contract['contract_id'],
          contractName: contract['contract_name'],
        ),
      ),
    );
  },
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xffb21f1f),
                          child: Icon(Icons.gavel, color: Colors.white, size: 20),
                        ),
                        title: Text(contract['contract_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${contract['description'] ?? 'لا يوجد وصف'}\nالساعة: \$${contract['hourly_rate']} | الإضافي: \$${contract['overtime_hourly_rate']}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}