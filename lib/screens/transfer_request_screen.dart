import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';
import '../widgets/searchable_picker_sheet.dart';
import '../screens/payroll_export_service.dart'; // reuse generic byte export/share

class TransferRequestScreen extends StatefulWidget {
  const TransferRequestScreen({super.key});

  @override
  State<TransferRequestScreen> createState() => _TransferRequestScreenState();
}

class _TransferRequestScreenState extends State<TransferRequestScreen>
    with SingleTickerProviderStateMixin {
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
String? _selectedCurrentShiftType;
String? _selectedTargetShiftType;
  // B3: the business date the transfer should take effect (default today).
  DateTime _effectiveDate = DateTime.now();
  // C-11: a reason is mandatory for every transfer request.
  final TextEditingController _reasonController = TextEditingController();

  // "My Requests": every request this supervisor sent, with its status and
  // the PDF document (Pending copy, or the electronically stamped decision).
  late final TabController _tabController = TabController(length: 2, vsync: this);
  List<dynamic> _myRequests = [];
  bool _isLoadingMine = false;
  String _statusFilter = 'All';
  int? _downloadingId;

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    setState(() => _isLoadingMine = true);
    try {
      final response = await ApiConfig.dio.get('/transfers/mine');
      if (!mounted) return;
      setState(() {
        _myRequests = _parseListResponse(response.data);
        _isLoadingMine = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMine = false);
      _showSnack('Failed to load your transfer requests', Colors.red);
    }
  }

  String get _effectiveDateStr =>
      '${_effectiveDate.year.toString().padLeft(4, '0')}-${_effectiveDate.month.toString().padLeft(2, '0')}-${_effectiveDate.day.toString().padLeft(2, '0')}';

  Future<void> _pickEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      helpText: 'Transfer effective date',
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }
  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadMyRequests();
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
Future<void> _downloadTransferDocument(int requestId, {String? status}) async {
  setState(() => _downloadingId = requestId);
  try {
    final response = await ApiConfig.dio.get<List<int>>(
      '/transfers/$requestId/document',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty document');
    await PayrollExportService.exportBytes(
        bytes, 'Transfer_Request_${requestId}_${status ?? 'Pending'}.pdf');
  } on DioException catch (e) {
    final msg = e.response?.data is Map
        ? (e.response?.data['message'] ?? 'Failed to download document')
        : 'Failed to download document';
    _showSnack(msg, Colors.red);
  } catch (_) {
    _showSnack('Failed to download document', Colors.red);
  } finally {
    if (mounted) setState(() => _downloadingId = null);
  }
}
  // 2. جلب العمال التابعين للموقع الحالي الذي يختاره المشرف
Future<void> _loadWorkersForSite(int siteId) async {
    setState(() {
      _isLoadingWorkers = true;
      _selectedWorker = null; // إعادة تعيين العامل عند تغيير الموقع
    });
    try {
      // إرسال التاريخ الحالي بصيغة YYYY-MM-DD لتجنب خطأ السيرفر
      final String today = DateTime.now().toIso8601String().split('T')[0];

      final response = await ApiConfig.dio.get(
        '/attendance/sites/$siteId/workers',
        queryParameters: {
  'record_date': today,
  'shift_type': _selectedCurrentShiftType,
},
      );
      
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

  if (picked == null) return;

  setState(() {
    _selectedCurrentSite = picked;
    _selectedCurrentShiftType = null;
    _selectedWorker = null;
    _workersInSite = [];
  });

  if (!mounted) return;

  final selectedShift = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Current Shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Day'),
            onTap: () => Navigator.pop(context, 'Day'),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Night'),
            onTap: () => Navigator.pop(context, 'Night'),
          ),
        ],
      ),
    ),
  );

  if (selectedShift == null) {
    setState(() {
      _selectedCurrentSite = null;
      _selectedCurrentShiftType = null;
      _workersInSite = [];
    });
    return;
  }

  setState(() {
    _selectedCurrentShiftType = selectedShift;
  });

  if (picked['site_id'] != null) {
    await _loadWorkersForSite(picked['site_id']);
  }
}



Future<void> _pickTargetShift() async {
  final selectedShift = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Target Shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Day'),
            onTap: () => Navigator.pop(context, 'Day'),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Night'),
            onTap: () => Navigator.pop(context, 'Night'),
          ),
        ],
      ),
    ),
  );

  if (selectedShift != null) {
    setState(() {
      _selectedTargetShiftType = selectedShift;
    });
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
if (_selectedWorker == null ||
    _selectedCurrentSite == null ||
    _selectedCurrentShiftType == null ||
    _selectedTargetSite == null ||
    _selectedTargetShiftType == null) {
    _showSnack('Please fill in all fields', Colors.orange);
    return;
  }

  if (_selectedCurrentSite!['site_id'] ==
        _selectedTargetSite!['site_id'] &&
    _selectedCurrentShiftType == _selectedTargetShiftType) {
  _showSnack(
    'Target site and shift cannot be the same as current',
    Colors.orange,
  );
  return;
}

  if (_reasonController.text.trim().length < 5) {
    _showSnack('Please enter the reason for the transfer (min. 5 characters)', Colors.orange);
    return;
  }

  setState(() => _isSubmitting = true);

  try {
 final response = await ApiConfig.dio.post('/transfers', data: {
  'transfer_reason': _reasonController.text.trim(),
  'worker_id': _selectedWorker!['worker_id'],
  'current_site_id': _selectedCurrentSite!['site_id'],
  'current_shift_type': _selectedCurrentShiftType,
  'target_site_id': _selectedTargetSite!['site_id'],
  'target_shift_type': _selectedTargetShiftType,
  'effective_date': _effectiveDateStr,
});

    if (!mounted) return;

    final requestId =
        response.data is Map ? response.data['request_id'] : null;

    _showSnack(
      'Transfer request submitted successfully',
      Colors.green,
    );

    if (requestId != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Transfer Request Created'),
          content: Text('Request ID: #$requestId\n\n'
              'The request and its PDF document stay under "My Requests". '
              'Once the Admin decides, the document is re-issued with an electronic '
              'APPROVED / REJECTED stamp.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _downloadTransferDocument(requestId, status: 'Pending');
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Transfer Document'),
            ),
          ],
        ),
      );
    }

_reasonController.clear();
_tabController.animateTo(1);
_loadMyRequests();
setState(() {
  _effectiveDate = DateTime.now();
  _selectedWorker = null;
  _selectedCurrentSite = null;
  _selectedCurrentShiftType = null;
  _selectedTargetSite = null;
  _selectedTargetShiftType = null;
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
        title: const Text(
          'Worker Transfer Request',
          style: TextStyle(color: Colors.white), // 👈 أضف هذا السطر
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white), // 👈 وأضف هذا السطر أيضاً
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          tabs: [
            const Tab(icon: Icon(Icons.add_circle_outline), text: 'New Request'),
            Tab(
              icon: const Icon(Icons.folder_open_rounded),
              text: _pendingCount > 0 ? 'My Requests ($_pendingCount)' : 'My Requests',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewRequestTab(),
          _buildMyRequestsTab(),
        ],
      ),
    );
  }

  int get _pendingCount => _myRequests.where((r) => r['status'] == 'Pending').length;

  Widget _buildNewRequestTab() {
    return _isLoading
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
const SizedBox(height: 16),
_buildSelector(
  label: 'Target Shift',
  icon: Icons.schedule,
  value: _selectedTargetShiftType,
  onTap: _pickTargetShift,
),
const SizedBox(height: 16),
_buildSelector(
  label: 'Effective Date (first day at the new site)',
  icon: Icons.event,
  value: _effectiveDateStr,
  onTap: _pickEffectiveDate,
),
const SizedBox(height: 16),
TextField(
  controller: _reasonController,
  maxLines: 3,
  maxLength: 500,
  decoration: InputDecoration(
    labelText: 'Reason for transfer (required)',
    hintText: 'Why should this worker move?',
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
),
const SizedBox(height: 20),
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
            );
  }

  // ------------------------------------------------------------ My Requests

  static const _statusColors = {
    'Pending': Color(0xff8a6d00),
    'Approved': Color(0xff1b7f3b),
    'Rejected': Color(0xffb3261e),
  };

  String _fmtDateTime(dynamic v) {
    if (v == null) return '';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return v.toString();
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _buildMyRequestsTab() {
    final filtered = _statusFilter == 'All'
        ? _myRequests
        : _myRequests.where((r) => r['status'] == _statusFilter).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: ['All', 'Pending', 'Approved', 'Rejected'].map((f) {
              final count = f == 'All' ? _myRequests.length : _myRequests.where((r) => r['status'] == f).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$f ($count)'),
                  selected: _statusFilter == f,
                  selectedColor: primaryColor.withOpacity(0.15),
                  onSelected: (_) => setState(() => _statusFilter = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadMyRequests,
            child: _isLoadingMine && _myRequests.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Center(
                          child: Text('No transfer requests yet',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _buildRequestCard(filtered[i]),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(dynamic r) {
    final status = (r['status'] ?? 'Pending').toString();
    final color = _statusColors[status] ?? Colors.grey;
    final id = r['request_id'] is int ? r['request_id'] as int : int.tryParse('${r['request_id']}') ?? 0;
    final decided = status != 'Pending';
    final busy = _downloadingId == id;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['worker_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('Request #$id · ${r['worker_unique_id'] ?? ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('${r['current_site_name']} (${r['current_shift_type']})',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                ),
                Flexible(
                  child: Text('${r['target_site_name']} (${r['target_shift_type']})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(
              'Effective: ${r['effective_date'] ?? '-'} · Sent: ${_fmtDateTime(r['created_at'])}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          if ((r['request_reason'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Text('Reason: ${r['request_reason']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
          if (decided)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.5), width: 1.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(status == 'Approved' ? Icons.verified_rounded : Icons.cancel_rounded, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${status == 'Approved' ? 'Approved' : 'Rejected'} by ${r['reviewed_by_name'] ?? 'Admin'}',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(_fmtDateTime(r['reviewed_at']),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        if ((r['admin_notes'] ?? '').toString().trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${status == 'Rejected' ? 'Reason' : 'Note'}: ${r['admin_notes']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : () => _downloadTransferDocument(id, status: status),
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.picture_as_pdf_outlined, color: primaryColor),
                label: Text(
                  decided ? 'Download stamped PDF' : 'Download PDF',
                  style: const TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
