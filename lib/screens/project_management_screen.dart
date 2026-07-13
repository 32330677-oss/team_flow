import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'project_contracts_screen.dart'; // 👈 استيراد شاشة العقود المخصصة للمشروع

class ProjectManagementScreen extends StatefulWidget {
  const ProjectManagementScreen({super.key});

  @override
  State<ProjectManagementScreen> createState() => _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends State<ProjectManagementScreen> {
  final Dio _dio = Dio();
  final String _apiUrl = 'http://192.168.1.3:5000/api/projects'; 
  
  List _projects = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProjects(); 
  }

  Future<void> _fetchProjects() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get(_apiUrl);
      if (response.data['status'] == 'success') {
        setState(() {
          _projects = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل جلب المشاريع من السيرفر'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _addProject() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final response = await _dio.post(_apiUrl, data: {
        'project_name': _nameController.text.trim(),
        'client_name': _clientController.text.trim(),
        'location': _locationController.text.trim(),
      });

      if (response.data['status'] == 'success') {
        Navigator.pop(context); 
        _nameController.clear();
        _clientController.clear();
        _locationController.clear();
        _fetchProjects(); 
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة المشروع بنجاح!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إنشاء المشروع الجديد'), backgroundColor: Colors.red),
      );
    }
  }

  void _showAddProjectDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, 
          top: 20, left: 20, right: 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('إضافة مشروع جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المشروع *', border: OutlineInputBorder()),
                validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال اسم المشروع' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientController,
                decoration: const InputDecoration(labelText: 'اسم العميل', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'الموقع الجغرافي', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _addProject,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1a2a6c), padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('حفظ المشروع', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المشاريع'),
        backgroundColor: const Color(0xff1a2a6c),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProjectDialog,
        backgroundColor: const Color(0xff1a2a6c),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('لا يوجد مشاريع مضافة حالياً', style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final project = _projects[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        // 👈 تفعيل الضغط على كارد المشروع للانتقال التلقائي لشاشة عقوده
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProjectContractsScreen(
                                projectId: project['project_id'],
                                projectName: project['project_name'],
                              ),
                            ),
                          );
                        },
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xfff4a742),
                          child: Icon(Icons.business, color: Colors.white),
                        ),
                        title: Text(project['project_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('العميل: ${project['client_name'] ?? 'غير محدد'} \nالموقع: ${project['location'] ?? 'غير محدد'}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: project['status'] == 'Active' ? Colors.green.shade100 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            project['status'] == 'Active' ? 'نشط' : project['status'],
                            style: TextStyle(color: project['status'] == 'Active' ? Colors.green.shade800 : Colors.black),
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