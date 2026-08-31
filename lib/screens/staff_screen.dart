import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/app_data_table.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({Key? key}) : super(key: key);

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final String _apiUrl = '/staff';

  List<dynamic> _staffList = [];
  bool _isLoading = true;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get(_apiUrl);
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _staffList = response.data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error loading staff: $e');
      _showSnackBar('Failed to load staff members', AppColors.danger);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _toggleStatus(int staffId, String currentStatus) async {
    final newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    try {
      final response = await ApiConfig.dio.patch('$_apiUrl/$staffId/status', data: {
        'status': newStatus,
      });

      if (response.statusCode == 200) {
        _loadStaff();
        _showSnackBar('Staff status updated to $newStatus', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Failed to update staff status', AppColors.danger);
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

  void _openAddOrEditSheet({Map<String, dynamic>? staff}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AddEditStaffSheet(
        staff: staff,
        apiUrl: _apiUrl,
        onSaved: () {
          _loadStaff();
          _showSnackBar(
            staff == null ? 'Staff member added successfully!' : 'Staff member updated successfully!',
            Colors.green.shade700,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredStaff = _staffList.where((s) {
      final fullName = (s['full_name'] ?? '').toString().toLowerCase();
      final position = (s['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      // تمت إزالة البحث بواسطة الـ username لعدم وجوده
      return fullName.contains(query) || position.contains(query);
    }).toList();

    final activeCount = _staffList.where((s) => s['status'] == 'Active').length;
    final inactiveCount = _staffList.length - activeCount;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: const CustomAppBar(
        title: 'Staff Management',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildStatCard('Total', _staffList.length.toString(), AppColors.primary),
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
                      hintText: 'Search by name or position...', // تم التعديل
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
                  child: filteredStaff.isEmpty
                      ? const Center(child: Text('No staff members found', style: TextStyle(color: Colors.grey, fontSize: 16)))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            AppDataTableCard(
                              title: 'Staff List',
                              icon: Icons.badge_rounded,
                              accentColor: AppColors.primary,
                              emptyMessage: 'No staff members registered yet.',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Total: ${filteredStaff.length}',
                                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              columns: const [
                                DataColumn(label: Text('#')),
                                DataColumn(label: Text('Staff Info')),
                                DataColumn(label: Text('Salary')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: List.generate(filteredStaff.length, (index) {
                                final stf = filteredStaff[index];
                                final isActive = stf['status'] == 'Active';

                                return DataRow(
                                  cells: [
                                    DataCell(Text('${index + 1}')),
                                    DataCell(
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(stf['full_name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text('${stf['staff_unique_id'] ?? ''} • ${stf['position'] ?? 'No Position'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text('${stf['monthly_salary'] ?? '0.00'}')),
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
                                            onPressed: () => _openAddOrEditSheet(staff: stf),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                                              color: isActive ? Colors.orange : Colors.green,
                                              size: 20,
                                            ),
                                            onPressed: () => _toggleStatus(stf['staff_id'], stf['status']),
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

class _AddEditStaffSheet extends StatefulWidget {
  final Map<String, dynamic>? staff;
  final String apiUrl;
  final VoidCallback onSaved;

  const _AddEditStaffSheet({
    this.staff,
    required this.apiUrl,
    required this.onSaved,
  });

  @override
  State<_AddEditStaffSheet> createState() => _AddEditStaffSheetState();
}

class _AddEditStaffSheetState extends State<_AddEditStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _positionController;
  late TextEditingController _salaryController;
  late TextEditingController _dailyHoursController;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.staff?['full_name'] ?? '');
    _phoneController = TextEditingController(text: widget.staff?['phone_number'] ?? '');
    _positionController = TextEditingController(text: widget.staff?['position'] ?? '');
    _salaryController = TextEditingController(text: widget.staff?['monthly_salary']?.toString() ?? '');
    _dailyHoursController = TextEditingController(text: widget.staff?['standard_daily_hours']?.toString() ?? '8.00');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _salaryController.dispose();
    _dailyHoursController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final isEditing = widget.staff != null;
      final staffId = widget.staff?['staff_id'];

      // تم حذف username و password لعدم وجودهما في الباك إند
      final payload = {
        'full_name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'position': _positionController.text.trim().isEmpty ? null : _positionController.text.trim(),
        'monthly_salary': double.parse(_salaryController.text.trim()),
        'standard_daily_hours': double.tryParse(_dailyHoursController.text.trim()) ?? 8.00,
      };

      if (isEditing) {
        final response = await ApiConfig.dio.put('${widget.apiUrl}/$staffId', data: payload);
        if (response.statusCode == 200) {
          Navigator.pop(context);
          widget.onSaved();
        }
      } else {
        final response = await ApiConfig.dio.post(widget.apiUrl, data: payload);
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
    final isEditing = widget.staff != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  isEditing ? 'Edit Staff Member' : 'Add New Staff Member',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Please enter full name' : null,
              ),
              const SizedBox(height: 16),
              // تم حذف حقل الـ Username وحقل الـ Password نهائياً
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _positionController,
                decoration: const InputDecoration(
                  labelText: 'Position / Job Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _salaryController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monthly Salary *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Please enter monthly salary';
                  if (double.tryParse(val) == null || double.parse(val) < 0) return 'Invalid salary value';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dailyHoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Standard Daily Hours',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time),
                ),
              ),
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
                    : Text(isEditing ? 'Update Staff Member' : 'Save Staff Member', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}