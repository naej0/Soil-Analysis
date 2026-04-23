import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';

class AdminLeasesScreen extends StatefulWidget {
  const AdminLeasesScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
    this.showFlaggedOnly = false,
    this.showActiveOnly = false,
  });

  final ApiService apiService;
  final UserModel currentUser;
  final bool showFlaggedOnly;
  final bool showActiveOnly;

  @override
  State<AdminLeasesScreen> createState() => _AdminLeasesScreenState();
}

class _AdminLeasesScreenState extends State<AdminLeasesScreen> {
  List<Map<String, dynamic>> _leases = <Map<String, dynamic>>[];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeases();
  }

  Future<void> _loadLeases({bool showLoader = true}) async {
    if (mounted && (showLoader || _leases.isEmpty)) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final leases = await widget.apiService.getAdminLeases(
        adminUserId: widget.currentUser.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _leases = leases;
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
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load lease records.';
      });
    }
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' ||
        text == '1' ||
        text == 'yes' ||
        text == 'y';
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

  bool _isFlaggedLease(Map<String, dynamic> lease) {
    final status = lease['status']?.toString().trim().toLowerCase() ?? '';
    final flagReason = lease['flag_reason']?.toString().trim() ?? '';

    return _asBool(lease['is_flagged']) ||
        _asBool(lease['flagged']) ||
        status == 'flagged' ||
        flagReason.isNotEmpty;
  }

  bool _isActiveLease(Map<String, dynamic> lease) {
    final status = lease['status']?.toString().trim().toLowerCase() ?? '';

    return status == 'active' ||
        status == 'approved' ||
        status == 'available' ||
        status == 'published';
  }

  List<Map<String, dynamic>> get _visibleLeases {
    if (widget.showFlaggedOnly) {
      return _leases.where(_isFlaggedLease).toList();
    }

    if (widget.showActiveOnly) {
      return _leases.where(_isActiveLease).toList();
    }

    return _leases;
  }

  String get _screenTitle {
    if (widget.showFlaggedOnly) {
      return 'Flagged Leases';
    }
    if (widget.showActiveOnly) {
      return 'Active Leases';
    }
    return 'Admin Leases';
  }

  String get _infoText {
    if (widget.showFlaggedOnly) {
      return 'This admin view lists only flagged lease records.';
    }
    if (widget.showActiveOnly) {
      return 'This admin view lists only active lease records.';
    }
    return 'This admin view lists lease records and moderation fields without updating lease data.';
  }

  String get _summaryTitle {
    if (widget.showFlaggedOnly) {
      return 'Flagged Lease Records';
    }
    if (widget.showActiveOnly) {
      return 'Active Lease Records';
    }
    return 'Lease Records';
  }

  String get _emptyTitle {
    if (widget.showFlaggedOnly) {
      return 'No Flagged Leases';
    }
    if (widget.showActiveOnly) {
      return 'No Active Leases';
    }
    return 'No Leases';
  }

  String get _emptyMessage {
    if (widget.showFlaggedOnly) {
      return 'No flagged lease records are available right now.';
    }
    if (widget.showActiveOnly) {
      return 'No active lease records are available right now.';
    }
    return 'No lease records are available right now.';
  }

  @override
  Widget build(BuildContext context) {
    final visibleLeases = _visibleLeases;

    if (_isLoading && _leases.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_screenTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        actions: [
          IconButton(
            onPressed: () {
              _loadLeases();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadLeases(showLoader: false),
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
              title: 'Read Only',
              icon: Icons.visibility_outlined,
              child: Text(_infoText),
            ),
            const SizedBox(height: 12),
            InfoCard(
              title: _summaryTitle,
              icon: Icons.storefront_outlined,
              child: Text('Total records loaded: ${visibleLeases.length}'),
            ),
            const SizedBox(height: 12),
            if (visibleLeases.isEmpty)
              InfoCard(
                title: _emptyTitle,
                icon: Icons.storefront_outlined,
                child: Text(_emptyMessage),
              ),
            for (final lease in visibleLeases)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InfoCard(
                  title: _display(lease['owner_name']),
                  icon: Icons.storefront_outlined,
                  child: Builder(
                    builder: (context) {
                      final leaseId = lease['id'] as int? ?? 0;
                      final isFlagged = _isFlaggedLease(lease);
                      final status = _display(lease['status']);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lease ID: $leaseId'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('Status: $status')),
                              Chip(
                                label: Text(
                                  'Flagged: ${isFlagged ? 'Yes' : 'No'}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'Barangay: ${_display(lease['barangay'])}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Soil Type: ${_display(lease['soil_type'])}'),
                          const SizedBox(height: 4),
                          Text('Area: ${_display(lease['area_hectares'])} ha'),
                          const SizedBox(height: 4),
                          Text('Price: ${_display(lease['price'])}'),
                          const SizedBox(height: 4),
                          Text('Contact: ${_display(lease['contact_number'])}'),
                          const SizedBox(height: 8),
                          Text('Description: ${_display(lease['description'])}'),
                          if ((_display(lease['flag_reason']) != 'N/A')) ...[
                            const SizedBox(height: 8),
                            Text('Flag reason: ${_display(lease['flag_reason'])}'),
                          ],
                          const SizedBox(height: 8),
                          Text('Created: ${_formatDate(lease['created_at'])}'),
                          const SizedBox(height: 4),
                          Text(
                            'Moderated at: ${_formatDate(lease['moderated_at'])}',
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}