import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class GeneratePayrollScreen extends StatefulWidget {
  const GeneratePayrollScreen({super.key});

  @override
  State<GeneratePayrollScreen> createState() => _GeneratePayrollScreenState();
}

class _GeneratePayrollScreenState extends State<GeneratePayrollScreen> {
  bool _isLoading = false;
  bool _isSaving = false;
  List<dynamic> _draftPayrollItems = [];
  
  // Date range controllers for the payroll batch period
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  final String baseUrl = 'https://your-api-domain.com/api'; // Update with your API URL

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  // 1. Preview payroll draft before saving
  Future<void> _previewPayrollDraft() async {
    if (_startDateController.text.isEmpty || _endDateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end dates first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Adjust this endpoint if you have a separate preview route, or use generate-batch if it returns items
      final response = await http.post(
        Uri.parse('$baseUrl/payroll/preview-batch'),
        headers: {
          'Authorization': 'Bearer YOUR_TOKEN_HERE',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'start_date': _startDateController.text,
          'end_date': _endDateController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _draftPayrollItems = data['items'] ?? data['data'] ?? [];
        });
      } else {
        final errorMsg = jsonDecode(response.body)['message'] ?? 'Failed to load payroll draft preview';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 2. Save Button - Commits and generates the batch into the database
  Future<void> _savePayrollBatch() async {
    if (_draftPayrollItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No staff records found in the draft to save')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Connects to your backend endpoint that runs inside a transaction and writes to the DB
      final response = await http.post(
        Uri.parse('$baseUrl/payroll/generate-batch'),
        headers: {
          'Authorization': 'Bearer YOUR_TOKEN_HERE',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'start_date': _startDateController.text,
          'end_date': _endDateController.text,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payroll batch successfully saved to database!')),
        );
        Navigator.pop(context, true); // Return to previous screen and refresh
      } else {
        final errorMsg = jsonDecode(response.body)['message'] ?? 'Failed to save payroll batch';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,##0', 'en_US');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate & Preview Monthly Payroll'),
        backgroundColor: const Color(0xFF1A2A6C),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period Selection Card
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startDateController,
                        decoration: const InputDecoration(
                          labelText: 'Start Date (YYYY-MM-DD)',
                          prefixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _endDateController,
                        decoration: const InputDecoration(
                          labelText: 'End Date (YYYY-MM-DD)',
                          prefixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A2A6C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                      onPressed: _isLoading ? null : _previewPayrollDraft,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Preview Draft'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Payroll Draft Breakdown:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Staff Payroll Items List
            Expanded(
              child: _draftPayrollItems.isEmpty
                  ? const Center(
                      child: Text(
                        'Select a date period and click "Preview Draft" to view staff calculations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _draftPayrollItems.length,
                      itemBuilder: (context, index) {
                        final item = _draftPayrollItems[index];
                        final workerName = item['full_name'] ?? item['worker_name'] ?? 'Unknown Staff';
                        final position = item['position'] ?? item['site_name'] ?? 'Staff Member';
                        final presentDays = item['present_days'] ?? item['days_worked'] ?? 0;
                        final paidLeaveDays = item['paid_leave_days'] ?? 0;
                        final absenceDays = item['unpaid_absence_days'] ?? 0;
                        final netSalary = double.tryParse(item['net_salary'].toString()) ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                workerName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('Position / Site: $position', style: const TextStyle(color: Colors.black87)),
                                  const SizedBox(height: 2),
                                  Text('Present: $presentDays | Paid Leave: $paidLeaveDays | Unpaid Absence: $absenceDays'),
                                ],
                              ),
                              trailing: Text(
                                '${currencyFormat.format(netSalary)} ل.س',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                  fontSize: 16,
                                ),
                              ),
                              isThreeLine: true,
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            // Final Save Button
            if (_draftPayrollItems.isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSaving ? null : _savePayrollBatch,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text(
                  'Save Payroll Batch to Database',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}