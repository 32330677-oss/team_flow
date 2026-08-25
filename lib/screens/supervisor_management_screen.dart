import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';

class SupervisorManagementScreen extends StatefulWidget {
  const SupervisorManagementScreen({Key? key}) : super(key: key);

  @override
  State<SupervisorManagementScreen> createState() => _SupervisorManagementScreenState();
}

class _SupervisorManagementScreenState extends State<SupervisorManagementScreen> {
  final String _apiUrl = '/users/supervisors';

  List<dynamic> _supervisors = [];
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
  }

  Future<void> _loadSupervisors() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _supervisors = response.data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error loading supervisors: $e');
      _showSnackBar('Failed to load supervisors', AppColors.danger);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _toggleStatus(int userId, String currentStatus) async {
    final newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    try {
      final response = await ApiConfig.dio.patch('$_apiUrl/$userId/status', data: {
        'status': newStatus,
      });

      if (response.statusCode == 200) {
        _loadSupervisors();
        _showSnackBar('Supervisor status updated to $newStatus', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Failed to update supervisor status', AppColors.danger);
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

  void _openAddOrEditSheet({Map<String, dynamic>? supervisor}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddEditSupervisorSheet(
        supervisor: supervisor,
        apiUrl: _apiUrl,
        onSaved: () {
          _loadSupervisors();
          _showSnackBar(
            supervisor == null ? 'Supervisor added successfully!' : 'Supervisor updated successfully!',
            Colors.green.shade700,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSupervisors = _supervisors.where((s) {
      final fullName = (s['full_name'] ?? '').toString().toLowerCase();
      final username = (s['username'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return fullName.contains(query) || username.contains(query);
    }).toList();

    final activeCount = _supervisors.where((s) => s['status'] == 'Active').length;
    final inactiveCount = _supervisors.length - activeCount;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(
        title: 'Supervisors Management',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildStatCard('Total', _supervisors.length.toString(), AppColors.primary),
                      const SizedBox(width: 10),
                      _buildStatCard('Active', activeCount.toString(), Colors.green.shade700),
                      const SizedBox(width: 10),
                      _buildStatCard('Inactive', inactiveCount.toString(), AppColors.danger),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search by name or username...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filteredSupervisors.isEmpty
                      ? const Center(child: Text('No supervisors found', style: TextStyle(color: Colors.grey, fontSize: 16)))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            AppDataTableCard(
                              title: 'Supervisors List',
                              icon: Icons.supervisor_account,
                              accentColor: AppColors.primary,
                              emptyMessage: 'No supervisors registered yet.',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Total: ${filteredSupervisors.length}',
                                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              columns: const [
                                DataColumn(label: Text('#')),
                                DataColumn(label: Text('Full Name')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: List.generate(filteredSupervisors.length, (index) {
                                final sup = filteredSupervisors[index];
                                final isActive = sup['status'] == 'Active';

                                return DataRow(
                                  cells: [
                                    DataCell(Text('${index + 1}')),
                                    DataCell(
                                      Row(
                                        children: [
                                          const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(sup['full_name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isActive ? 'Active' : 'Inactive',
                                          style: TextStyle(
                                            color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20),
                                            onPressed: () => _openAddOrEditSheet(supervisor: sup),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                                              color: isActive ? Colors.orange : Colors.green,
                                              size: 20,
                                            ),
                                            onPressed: () => _toggleStatus(sup['user_id'], sup['status']),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ],
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _openAddOrEditSheet(),
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

class _AddEditSupervisorSheet extends StatefulWidget {
  final Map<String, dynamic>? supervisor;
  final String apiUrl;
  final VoidCallback onSaved;

  const _AddEditSupervisorSheet({
    this.supervisor,
    required this.apiUrl,
    required this.onSaved,
  });

  @override
  State<_AddEditSupervisorSheet> createState() => _AddEditSupervisorSheetState();
}

class _AddEditSupervisorSheetState extends State<_AddEditSupervisorSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supervisor?['full_name'] ?? '');
    _usernameController = TextEditingController(text: widget.supervisor?['username'] ?? '');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

   setState(() {
  _isSubmitting = true;
  _errorMessage = null;
});

    try {
      final isEditing = widget.supervisor != null;
      final supervisorId = widget.supervisor?['user_id'];

      if (isEditing) {
        final response = await ApiConfig.dio.put('${widget.apiUrl}/$supervisorId', data: {
          'full_name': _nameController.text.trim(),
          'username': _usernameController.text.trim(),
        });
        if (response.statusCode == 200) {
          Navigator.pop(context);
          widget.onSaved();
        }
      } else {
        final response = await ApiConfig.dio.post(widget.apiUrl, data: {
          'full_name': _nameController.text.trim(),
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.trim(),
        });
        if (response.statusCode == 201 || response.statusCode == 200) {
          Navigator.pop(context);
          widget.onSaved();
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'Operation failed')
          : 'Operation failed';
      setState(() => _errorMessage = msg);
    } catch (e) {
      setState(() => _errorMessage = 'Connection error, please try again');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supervisor != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                isEditing ? 'Edit Supervisor' : 'Add New Supervisor',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (val) => val == null || val.isEmpty ? 'Please enter full name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: (val) => val == null || val.isEmpty ? 'Please enter username' : null,
            ),
            if (!isEditing) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (val) => val == null || val.length < 6 ? 'Password must be at least 6 characters' : null,
              ),
            ],
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
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 22),
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
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Update Supervisor' : 'Save Supervisor', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}