import 'contract_sites_screen.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:team_flow/constants.dart';
import '../widgets/custom_app_bar.dart';
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
  final Dio _dio = ApiConfig.dio;
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
    _apiUrl = '/contracts';
    _fetchContracts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _rateController.dispose();
    _overtimeRateController.dispose();
    super.dispose();
  }

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
        const SnackBar(content: Text('Failed to load project contracts'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveContract({int? contractId}) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final data = {
        'contract_name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'project_id': widget.projectId,
        'hourly_rate': double.parse(_rateController.text.trim()),
        'overtime_hourly_rate': double.parse(_overtimeRateController.text.trim()),
      };

      Response response;
      if (contractId == null) {
        response = await _dio.post(_apiUrl, data: data);
      } else {
        response = await _dio.put('$_apiUrl/$contractId', data: data);
      }

      if (response.data['status'] == 'success') {
        Navigator.pop(context);
        _clearForm();
        _fetchContracts();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(contractId == null ? 'Contract created successfully!' : 'Contract updated successfully!'), 
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save contract data'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _changeContractStatus(int contractId, String newStatus) async {
    try {
      final response = await _dio.patch('$_apiUrl/$contractId/status', data: {'status': newStatus});
      if (response.data['status'] == 'success') {
        _fetchContracts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contract status updated to $newStatus'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update contract status'), backgroundColor: Colors.red),
      );
    }
  }

  void _clearForm() {
    _nameController.clear();
    _descController.clear();
    _rateController.clear();
    _overtimeRateController.clear();
  }

  void _showContractDialog({Map<String, dynamic>? contract}) {
    if (contract != null) {
      _nameController.text = contract['contract_name'] ?? '';
      _descController.text = contract['description'] ?? '';
      _rateController.text = contract['hourly_rate']?.toString() ?? '';
      _overtimeRateController.text = contract['overtime_hourly_rate']?.toString() ?? '';
    } else {
      _clearForm();
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  contract == null ? 'Add Contract for ${widget.projectName}' : 'Edit Contract Details', 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), 
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Contract Name *', border: OutlineInputBorder()),
                  validator: (value) => value == null || value.isEmpty ? 'Please enter contract name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Description / Details', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Hourly Rate *', border: OutlineInputBorder(), prefixText: 'ل.س '),
                  validator: (value) => value == null || value.isEmpty ? 'Please enter hourly rate' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _overtimeRateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Overtime Hourly Rate *', border: OutlineInputBorder(), prefixText: 'ل.س '),
                  validator: (value) => value == null || value.isEmpty ? 'Please enter overtime rate' : null,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => _saveContract(contractId: contract?['contract_id']),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffb21f1f), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: Text(contract == null ? 'Save Contract' : 'Update Changes', style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Active':
        return Colors.green.shade800;
      case 'Suspended':
        return Colors.orange.shade800;
      case 'Completed':
        return Colors.grey.shade700;
      default:
        return Colors.black87;
    }
  }

  Color _getStatusBgColor(String? status) {
    switch (status) {
      case 'Active':
        return Colors.green.shade100;
      case 'Suspended':
        return Colors.orange.shade100;
      case 'Completed':
        return Colors.grey.shade300;
      default:
        return Colors.grey.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
   appBar: CustomAppBar(
      title: 'Contracts: ${widget.projectName}',
    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showContractDialog(),
        backgroundColor: const Color(0xffb21f1f),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contracts.isEmpty
              ? const Center(child: Text('No contracts registered for this project yet', style: TextStyle(fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: _contracts.length,
                  itemBuilder: (context, index) {
                    final contract = _contracts[index];
                    final currentStatus = contract['status'] ?? 'Active';
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () {
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
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('${contract['description'] ?? 'No description'}\nRate: \$${contract['hourly_rate']} | Overtime: \$${contract['overtime_hourly_rate']}'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusBgColor(currentStatus),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                currentStatus,
                                style: TextStyle(color: _getStatusColor(currentStatus), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showContractDialog(contract: contract);
                                } else {
                                  _changeContractStatus(contract['contract_id'], value);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit Contract')),
                                if (currentStatus != 'Active')
                                  const PopupMenuItem(value: 'Active', child: Text('Set Active', style: TextStyle(color: Colors.green))),
                                if (currentStatus != 'Suspended')
                                  const PopupMenuItem(value: 'Suspended', child: Text('Set Suspended', style: TextStyle(color: Colors.orange))),
                                if (currentStatus != 'Completed')
                                  const PopupMenuItem(value: 'Completed', child: Text('Set Completed', style: TextStyle(color: Colors.grey))),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}