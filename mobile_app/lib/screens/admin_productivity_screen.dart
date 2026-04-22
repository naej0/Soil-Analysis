import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';

class AdminProductivityScreen extends StatefulWidget {
  const AdminProductivityScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
  });

  final ApiService apiService;
  final UserModel currentUser;

  @override
  State<AdminProductivityScreen> createState() => _AdminProductivityScreenState();
}

class _AdminProductivityScreenState extends State<AdminProductivityScreen> {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords({bool showLoader = true}) async {
    if (mounted && (showLoader || _records.isEmpty)) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final records = await widget.apiService.getAdminProductivity(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _isLoading = false;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    }
  }

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'N/A' : text;
  }

  String _formatDate(dynamic value) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.isEmpty ? 'N/A' : text;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _records.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Productivity')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Productivity'),
        actions: [
          IconButton(
            onPressed: () {
              _loadRecords();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadRecords(showLoader: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            InfoCard(
              title: 'Productivity Records',
              icon: Icons.insights_outlined,
              child: Text('Total records loaded: ${_records.length}'),
            ),
            if (_records.isEmpty)
              const InfoCard(
                title: 'No Records',
                icon: Icons.bar_chart_outlined,
                child: Text('No productivity records are available right now.'),
              ),
            for (final record in _records)
              InfoCard(
                title: _display(record['crop_name']),
                icon: Icons.bar_chart_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('User ID: ${_display(record['user_id'])}')),
                        Chip(label: Text('Soil: ${_display(record['soil_type'])}')),
                        Chip(label: Text('Status: ${_display(record['status'])}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Area: ${_display(record['area_hectares'])} ha'),
                    const SizedBox(height: 4),
                    Text('Yield: ${_display(record['yield_amount'])}'),
                    const SizedBox(height: 4),
                    Text('Reviewed by: ${_display(record['reviewed_by'])}'),
                    const SizedBox(height: 4),
                    Text('Reviewed at: ${_formatDate(record['reviewed_at'])}'),
                    const SizedBox(height: 8),
                    Text('Notes: ${_display(record['notes'])}'),
                    const SizedBox(height: 8),
                    Text('Created: ${_formatDate(record['created_at'])}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
