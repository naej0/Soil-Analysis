import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';

class AdminSoilLogsScreen extends StatefulWidget {
  const AdminSoilLogsScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
  });

  final ApiService apiService;
  final UserModel currentUser;

  @override
  State<AdminSoilLogsScreen> createState() => _AdminSoilLogsScreenState();
}

class _AdminSoilLogsScreenState extends State<AdminSoilLogsScreen> {
  List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs({bool showLoader = true}) async {
    if (mounted && (showLoader || _logs.isEmpty)) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final logs = await widget.apiService.getAdminSoilLogs(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _logs = logs;
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
    if (_isLoading && _logs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Soil Logs')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Soil Logs'),
        actions: [
          IconButton(
            onPressed: () {
              _loadLogs();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadLogs(showLoader: false),
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
              title: 'Soil Analysis Logs',
              icon: Icons.analytics_outlined,
              child: Text('Total logs loaded: ${_logs.length}'),
            ),
            if (_logs.isEmpty)
              const InfoCard(
                title: 'No Logs',
                icon: Icons.history_outlined,
                child: Text('No soil analysis logs are available right now.'),
              ),
            for (final log in _logs)
              InfoCard(
                title: _display(log['predicted_soil_type']),
                icon: Icons.history_edu_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('User ID: ${_display(log['user_id'])}')),
                        Chip(label: Text('Confidence: ${_display(log['confidence'])}')),
                        Chip(label: Text('Barangay: ${_display(log['barangay'])}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Soil name: ${_display(log['soil_name'])}'),
                    const SizedBox(height: 4),
                    Text('Soil type: ${_display(log['soil_type'])}'),
                    const SizedBox(height: 4),
                    Text(
                      'Coordinates: ${_display(log['lat'])}, ${_display(log['lng'])}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Productivity level: ${_display(log['estimated_productivity_level'])}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fertilizer: ${_display(log['fertilizer_recommendation'])}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Management advice: ${_display(log['soil_management_advice'])}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crop recommendations: ${_display(log['crop_recommendations'])}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Original file: ${_display(log['original_file_name'])}',
                    ),
                    const SizedBox(height: 4),
                    Text('Stored image: ${_display(log['image_path'])}'),
                    const SizedBox(height: 8),
                    Text('Created: ${_formatDate(log['created_at'])}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
