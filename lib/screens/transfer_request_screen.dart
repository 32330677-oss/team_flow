import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';
import '../widgets/searchable_picker_sheet.dart';

class TransferRequestScreen extends StatefulWidget {
  const TransferRequestScreen({super.key});

  @override
  State<TransferRequestScreen> createState() => _TransferRequestScreenState();
}

class _TransferRequestScreenState extends State<TransferRequestScreen> {
  static const Color primaryColor = Color(0xff1a2a6c);

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLoadingWorkers = false;

  List<dynamic> _supervisorSites = []; // مواقع المشرف الخاصة به
  List<dynamic> _allSites = [];        // كل مواقع الشركة (للنقل إليها)
  List<dynamic> _workersInSite = [];   // عمال الموقع الحالي فقط

  Map<String, dynamic>? _selectedWorker;
  Map<String, dynamic>? _selectedCurrentSite;
  Map<String, dynamic>? _selectedTargetSite;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // دالة مساعدة لاستخراج القائمة بغض النظر عن هيكل الـ JSON القادم
  List<dynamic> _parseListResponse(dynamic responseData) {
    if (responseData is List) {
      return responseData;
    } else if (responseData is Map) {
      if (responseData['data'] is List) {
        return responseData['data'];
      }
    }
    return [];
  }

  // 1. جلب مواقع المشرف ومواقع الشركة في البداية
Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiConfig.dio.get('/sites/my-sites'),      // مواقع المشرف الحالية
        ApiConfig.dio.get('/sites/all-sites'),     // تم التعديل هنا لتتم إضافة /sites/ بشكل صحيح
      ]);

      setState(() {
        _supervisorSites = _parseListResponse(results[0].data);
        _allSites = _parseListResponse(results[1].data);
        _isLoading = false;
      });
    } catch (e) {
      if (e is DioException) {
        print('==============================');
        print('DIOC EXCEPTION CAUGHT!');
        print('Failed URL Path: ${e.requestOptions.path}');
        print('Status Code: ${e.response?.statusCode}');
        print('Response Data: ${e.response?.data}');
        print('==============================');
      } else {
        print('General Error: $e');
      }
      
      setState(() => _isLoading = false);
      _showSnack('Failed to load sites data', Colors.red);
    }
  }

  // 2. جلب العمال التابعين للموقع الحالي الذي يختاره المشرف
  Future<void> _loadWorkersForSite(int siteId) async {
    setState(() {
      _isLoadingWorkers = true;
      _selectedWorker = null; // إعادة تعيين العامل عند تغيير الموقع
    });
    try {
      final response = await ApiConfig.dio.get('/attendance/sites/$siteId/workers');
      setState(() {
        _workersInSite = _parseListResponse(response.data);
        _isLoadingWorkers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingWorkers = false;
        _workersInSite = [];
      });
      _showSnack('Failed to load workers for this site', Colors.red);
    }
  }

  Future<void> _pickCurrentSite() async {
    if (_supervisorSites.isEmpty) {
      _showSnack('No supervisor sites available', Colors.orange);
      return;
    }
    final picked = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Select Current Site',
      items: _supervisorSites,
      labelBuilder: (s) => s['site_name'] ?? '',
    );
    if (picked != null) {
      setState(() => _selectedCurrentSite = picked);
      if (picked['site_id'] != null) {
        _loadWorkersForSite(picked['site_id']);
      }
    }
  }

  Future<void> _pickWorker() async {
    if (_selectedCurrentSite == null) {
      _showSnack('Please select the current site first', Colors.orange);
      return;
    }
    if (_workersInSite.isEmpty) {
      _showSnack('No active workers available in this site', Colors.orange);
      return;
    }

    final picked = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Select Worker',
      items: _workersInSite,
      labelBuilder: (w) => w['full_name'] ?? '',
      subtitleBuilder: (w) => 'ID: ${w['worker_unique_id'] ?? w['worker_id'] ?? ''}',
    );
    if (picked != null) setState(() => _selectedWorker = picked);
  }

  Future<void> _pickTargetSite() async {
    if (_allSites.isEmpty) {
      _showSnack('No target sites available', Colors.orange);
      return;
    }
    final picked = await SearchablePickerSheet.show<dynamic>(
      context,
      title: 'Select Target Site',
      items: _allSites,
      labelBuilder: (s) => s['site_name'] ?? '',
    );
    if (picked != null) setState(() => _selectedTargetSite = picked);
  }

  Future<void> _submit() async {
    if (_selectedWorker == null || _selectedCurrentSite == null || _selectedTargetSite == null) {
      _showSnack('Please fill in all fields', Colors.orange);
      return;
    }
    if (_selectedCurrentSite!['site_id'] == _selectedTargetSite!['site_id']) {
      _showSnack('Target site cannot be the same as current site', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiConfig.dio.post('/transfers', data: {
        'worker_id': _selectedWorker!['worker_id'],
        'current_site_id': _selectedCurrentSite!['site_id'],
        'target_site_id': _selectedTargetSite!['site_id'],
      });
      if (!mounted) return;
      _showSnack('Transfer request submitted successfully', Colors.green);
      setState(() {
        _selectedWorker = null;
        _selectedCurrentSite = null;
        _selectedTargetSite = null;
        _workersInSite = [];
      });
    } on DioException catch (e) {
      String msg = e.response?.data['message'] ?? 'Failed to submit request';
      _showSnack(msg, Colors.red);
    } catch (e) {
      _showSnack('Server connection error', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Widget _buildSelector({
    required String label,
    required IconData icon,
    required String? value,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(icon, color: primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      value ?? 'Click to search & select',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: value != null ? Colors.black87 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search, color: Colors.grey),
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
        title: const Text('Worker Transfer Request'),
        backgroundColor: primaryColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelector(
                    label: 'Current Site',
                    icon: Icons.location_on_outlined,
                    value: _selectedCurrentSite?['site_name'],
                    onTap: _pickCurrentSite,
                  ),
                  const SizedBox(height: 16),
                  _buildSelector(
                    label: 'Worker',
                    icon: Icons.person,
                    value: _selectedWorker?['full_name'],
                    onTap: _pickWorker,
                    isLoading: _isLoadingWorkers,
                  ),
                  const SizedBox(height: 16),
                  _buildSelector(
                    label: 'Target Site',
                    icon: Icons.location_on,
                    value: _selectedTargetSite?['site_name'],
                    onTap: _pickTargetSite,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}