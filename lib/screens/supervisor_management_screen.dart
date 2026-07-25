import 'package:flutter/material.dart';
import 'package:team_flow/constants.dart'; // ✅ الاستيراد الموحد

class SupervisorManagementScreen extends StatefulWidget {
  const SupervisorManagementScreen({Key? key}) : super(key: key);

  @override
  State<SupervisorManagementScreen> createState() => _SupervisorManagementScreenState();
}

class _SupervisorManagementScreenState extends State<SupervisorManagementScreen> {
  final String _apiUrl = '/users/supervisors';

  List<dynamic> _supervisors = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSupervisors();
  }

  int get _totalSupervisors => _supervisors.length;
  int get _activeSupervisors => _supervisors.where((s) => s['status'] == 'Active').length;
  int get _inactiveSupervisors => _totalSupervisors - _activeSupervisors;

  Future<void> _fetchSupervisors() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _supervisors = response.data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to fetch supervisors', Colors.red);
    }
  }

  Future<void> _saveSupervisor({int? supervisorId}) async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (supervisorId != null) {
        final data = {
          'full_name': name,
          'username': username,
        };
        final response = await ApiConfig.dio.put('$_apiUrl/$supervisorId', data: data);
        if (response.statusCode == 200) {
          Navigator.pop(context);
          _clearControllers();
          _fetchSupervisors();
          _showSnackBar('Supervisor updated successfully', Colors.green);
        }
      } else {
        final data = {
          'full_name': name,
          'username': username,
          'password': password,
        };
        final response = await ApiConfig.dio.post(_apiUrl, data: data);
        if (response.statusCode == 201) {
          Navigator.pop(context);
          _clearControllers();
          _fetchSupervisors();
          _showSnackBar('Supervisor added successfully', Colors.green);
        }
      }
    } catch (e) {
      _showSnackBar('Operation failed: Check username uniqueness', Colors.red);
    }
  }

  Future<void> _toggleStatus(int userId, String currentStatus) async {
    final newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    try {
      final response = await ApiConfig.dio.patch('$_apiUrl/$userId/status', data: {
        'status': newStatus,
      });

      if (response.statusCode == 200) {
        _fetchSupervisors();
        _showSnackBar('Supervisor status updated to $newStatus', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Failed to update supervisor status', Colors.red);
    }
  }

  void _clearControllers() {
    _nameController.clear();
    _usernameController.clear();
    _passwordController.clear();
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: bgColor),
    );
  }

  void _openSupervisorSheet({Map<String, dynamic>? supervisor}) {
    final isEditing = supervisor != null;
    final int? supervisorId = supervisor?['user_id'];

    if (isEditing) {
      _nameController.text = supervisor['full_name'] ?? '';
      _usernameController.text = supervisor['username'] ?? '';
      _passwordController.clear();
    } else {
      _clearControllers();
    }

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
              children: [
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 15),
                Text(
                  isEditing ? 'Edit Supervisor' : 'Add New Supervisor',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xffb21f1f)),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person)),
                  validator: (val) => val == null || val.isEmpty ? 'Please enter full name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username (Login) *', prefixIcon: Icon(Icons.alternate_email)),
                  validator: (val) => val == null || val.isEmpty ? 'Please enter a unique username' : null,
                ),
                const SizedBox(height: 12),
                if (!isEditing) ...[
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password *', prefixIcon: Icon(Icons.lock)),
                    validator: (val) => val == null || val.length < 6 ? 'Password must be at least 6 characters' : null,
                  ),
                  const SizedBox(height: 25),
                ],
                ElevatedButton(
                  onPressed: () => _saveSupervisor(supervisorId: supervisorId),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xffb21f1f),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    isEditing ? 'Update Supervisor' : 'Save & Activate Supervisor',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKPICard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Supervisors Management', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xffb21f1f),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSupervisorSheet(),
        backgroundColor: const Color(0xfffdbb2d),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildKPICard('Total Supervisors', '$_totalSupervisors', const Color(0xffb21f1f)),
                      _buildKPICard('Active', '$_activeSupervisors', Colors.green),
                      _buildKPICard('Inactive', '$_inactiveSupervisors', Colors.red),
                    ],
                  ),
                ),
                Expanded(
                  child: _supervisors.isEmpty
                      ? const Center(child: Text('No supervisors registered yet'))
                      : ListView.builder(
                          itemCount: _supervisors.length,
                          itemBuilder: (context, index) {
                            final supervisor = _supervisors[index];
                            final isUserActive = supervisor['status'] == 'Active';
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xffb21f1f).withOpacity(0.1),
                                  child: const Icon(Icons.person, color: Color(0xffb21f1f)),
                                ),
                                title: Text(supervisor['full_name'] ?? 'Unnamed User', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Username: @${supervisor['username'] ?? 'N/A'} \nStatus: ${isUserActive ? 'Active' : 'Inactive'}', style: TextStyle(color: isUserActive ? Colors.green[700] : Colors.red[700])),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openSupervisorSheet(supervisor: supervisor);
                                    } else if (value == 'status') {
                                      _toggleStatus(supervisor['user_id'], supervisor['status']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 8), Text('Edit')]),
                                    ),
                                    PopupMenuItem(
                                      value: 'status',
                                      child: Row(children: [
                                        Icon(isUserActive ? Icons.block : Icons.check_circle, color: isUserActive ? Colors.orange : Colors.green, size: 20),
                                        const SizedBox(width: 8),
                                        Text(isUserActive ? 'Deactivate' : 'Activate'),
                                      ]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}