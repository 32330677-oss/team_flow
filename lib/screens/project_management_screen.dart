import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'project_contracts_screen.dart';
import 'package:team_flow/constants.dart';

class ProjectManagementScreen extends StatefulWidget {
  const ProjectManagementScreen({super.key});

  @override
  State<ProjectManagementScreen> createState() => _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends State<ProjectManagementScreen> {
  final Dio _dio = ApiConfig.dio;
  final String _apiUrl = '/projects';  
  List _projects = [];
  List _filteredProjects = [];
  bool _isLoading = true;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProjects();
    _searchController.addListener(_filterProjects);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _clientController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProjects = _projects.where((project) {
        final name = (project['project_name'] ?? '').toLowerCase();
        final client = (project['client_name'] ?? '').toLowerCase();
        return name.contains(query) || client.contains(query);
      }).toList();
    });
  }

  Future<void> _fetchProjects() async {
    setState(() => _isLoading = true);
    try {
      final response = await _dio.get(_apiUrl);
      if (response.data['status'] == 'success') {
        setState(() {
          _projects = response.data['data'];
          _filteredProjects = _projects;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load projects from server'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveProject({int? projectId}) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final data = {
        'project_name': _nameController.text.trim(),
        'client_name': _clientController.text.trim(),
        'location': _locationController.text.trim(),
      };

      Response response;
      if (projectId == null) {
        response = await _dio.post(_apiUrl, data: data);
      } else {
        response = await _dio.put('$_apiUrl/$projectId', data: data);
      }

      if (response.data['status'] == 'success') {
        Navigator.pop(context); 
        _nameController.clear();
        _clientController.clear();
        _locationController.clear();
        _fetchProjects(); 
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(projectId == null ? 'Project created successfully!' : 'Project updated successfully!'), 
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operation failed. Please try again.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _changeProjectStatus(int projectId, String newStatus) async {
    try {
      final response = await _dio.patch('$_apiUrl/$projectId/status', data: {'status': newStatus});
      if (response.data['status'] == 'success') {
        _fetchProjects();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Project status updated to $newStatus'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update project status'), backgroundColor: Colors.red),
      );
    }
  }

  void _showProjectDialog({Map<String, dynamic>? project}) {
    if (project != null) {
      _nameController.text = project['project_name'] ?? '';
      _clientController.text = project['client_name'] ?? '';
      _locationController.text = project['location'] ?? '';
    } else {
      _nameController.clear();
      _clientController.clear();
      _locationController.clear();
    }

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
              Text(project == null ? 'Add New Project' : 'Edit Project', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Project Name *', border: OutlineInputBorder()),
                validator: (value) => value == null || value.isEmpty ? 'Please enter project name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientController,
                decoration: const InputDecoration(labelText: 'Client Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _saveProject(projectId: project?['project_id']),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1a2a6c), padding: const EdgeInsets.symmetric(vertical: 12)),
                child: Text(project == null ? 'Save Project' : 'Update Changes', style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
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
      appBar: AppBar(
        title: const Text('Project Management'),
        backgroundColor: const Color(0xff1a2a6c),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProjectDialog(),
        backgroundColor: const Color(0xff1a2a6c),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search projects by name or client...',
                prefixIcon: const Icon(Icons.search, color: Color(0xff1a2a6c)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProjects.isEmpty
                    ? const Center(child: Text('No projects found', style: TextStyle(fontSize: 16, color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        itemCount: _filteredProjects.length,
                        itemBuilder: (context, index) {
                          final project = _filteredProjects[index];
                          final currentStatus = project['status'] ?? 'Active';
                          return Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                radius: 24,
                                backgroundColor: Color(0xfff4a742),
                                child: Icon(Icons.business, color: Colors.white),
                              ),
                              title: Text(project['project_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('Client: ${project['client_name'] ?? 'N/A'}\nLocation: ${project['location'] ?? 'N/A'}'),
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
                                        _showProjectDialog(project: project);
                                      } else {
                                        _changeProjectStatus(project['project_id'], value);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit Project')),
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
          ),
        ],
      ),
    );
  }
}