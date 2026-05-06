import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/info_card.dart';
import 'admin_leases_screen.dart';
import 'admin_productivity_screen.dart';
import 'admin_soil_logs_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
    required this.onLogout,
  });

  final ApiService apiService;
  final UserModel currentUser;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const List<String> _paymentStatuses = [
    'unpaid',
    'partial',
    'paid',
    'overdue',
  ];
  static const List<String> _rentalStatuses = [
    'pending',
    'approved',
    'rejected',
    'active',
    'completed',
    'cancelled',
  ];

  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _leasePayments = <Map<String, dynamic>>[];
  String? _errorMessage;
  String? _paymentErrorMessage;
  bool _isLoading = true;
  bool _isPaymentLoading = false;
  int? _updatingRentalStatusId;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadLeasePayments();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final dashboard = await widget.apiService.getAdminDashboard(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLeasePayments({bool showLoader = true}) async {
    if (mounted && (showLoader || _leasePayments.isEmpty)) {
      setState(() {
        _isPaymentLoading = true;
        _paymentErrorMessage = null;
      });
    }

    try {
      final payments = await widget.apiService.getAdminLeasePayments(
        adminUserId: widget.currentUser.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _leasePayments = payments;
        _paymentErrorMessage = null;
        _isPaymentLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentErrorMessage = error.message;
        _isPaymentLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentErrorMessage = 'Failed to load lease payment records.';
        _isPaymentLoading = false;
      });
    }
  }

  Future<void> _refreshAdminData() async {
    await Future.wait([
      _loadDashboard(),
      _loadLeasePayments(showLoader: false),
    ]);
  }

  Future<void> _openUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminUsersScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openRestrictedUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminUsersScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
          restrictedOnly: true,
        ),
      ),
    );
  }

  Future<void> _openLeases() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminLeasesScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
          showActiveOnly: true,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openFlaggedLeases() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminLeasesScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
          showFlaggedOnly: true,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openProductivity() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminProductivityScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _openSoilLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminSoilLogsScreen(
          apiService: widget.apiService,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _loadDashboard();
  }

  Map<String, dynamic> _section(String key) {
    final section = _dashboard?[key];
    if (section is Map<String, dynamic>) {
      return section;
    }
    if (section is Map) {
      return Map<String, dynamic>.from(section);
    }
    return <String, dynamic>{};
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', ''));
    }
    return null;
  }

  String _display(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'N/A' : text;
  }

  String _formatMoney(dynamic value) {
    final amount = _asDouble(value);
    if (amount == null) {
      return 'N/A';
    }

    final fixed = amount.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return 'PHP ${buffer.toString()}.${parts[1]}';
  }

  String _formatInputAmount(dynamic value) {
    final amount = _asDouble(value);
    if (amount == null) {
      return '';
    }
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _formatDateValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return 'N/A';
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text;
    }

    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _statusValue(
    dynamic value,
    List<String> allowed,
    String fallback,
  ) {
    final status = value?.toString().trim().toLowerCase() ?? '';
    return allowed.contains(status) ? status : fallback;
  }

  String? _validatePaymentAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter the amount paid.';
    }
    final amount = double.tryParse(text);
    if (amount == null || amount < 0) {
      return 'Enter a valid amount.';
    }
    return null;
  }

  void _showAdminMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showUpdatePaymentDialog(
    Map<String, dynamic> payment,
  ) async {
    final rentalId = _asInt(payment['rental_id'] ?? payment['id']);
    if (rentalId <= 0) {
      _showAdminMessage('Rental request ID is missing.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: _formatInputAmount(payment['amount_paid']),
    );
    var selectedStatus = _statusValue(
      payment['payment_status'],
      _paymentStatuses,
      'unpaid',
    );
    var submitting = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> submitPayment() async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                setDialogState(() {
                  submitting = true;
                });

                try {
                  await widget.apiService.updateLeaseRentalPayment(
                    rentalId: rentalId,
                    adminUserId: widget.currentUser.id,
                    amountPaid: amountController.text.trim(),
                    paymentStatus: selectedStatus,
                  );
                  await _loadLeasePayments(showLoader: false);
                  if (!mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                  _showAdminMessage('Lease payment updated successfully.');
                } on ApiException catch (error) {
                  if (!mounted) {
                    return;
                  }
                  _showAdminMessage(error.message);
                  setDialogState(() {
                    submitting = false;
                  });
                }
              }

              return AlertDialog(
                title: const Text('Update Payment'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _validatePaymentAmount,
                        decoration: const InputDecoration(
                          labelText: 'Amount Paid',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Payment Status',
                          border: OutlineInputBorder(),
                        ),
                        items: _paymentStatuses
                            .map(
                              (status) => DropdownMenuItem<String>(
                                value: status,
                                child: Text(status),
                              ),
                            )
                            .toList(),
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() {
                                  selectedStatus = value;
                                });
                              },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: submitting ? null : submitPayment,
                    icon: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(submitting ? 'Saving...' : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      amountController.dispose();
    }
  }

  Future<void> _updateRentalStatus(
    Map<String, dynamic> payment,
    String status,
  ) async {
    final rentalId = _asInt(payment['rental_id'] ?? payment['id']);
    if (rentalId <= 0) {
      _showAdminMessage('Rental request ID is missing.');
      return;
    }

    setState(() {
      _updatingRentalStatusId = rentalId;
    });

    try {
      await widget.apiService.updateLeaseRentalStatus(
        rentalId: rentalId,
        adminUserId: widget.currentUser.id,
        rentalStatus: status,
        // TODO: Replace this temporary admin ID with the actual approving admin ID from the session.
        approvedBy: status == 'approved' ? 1 : null,
      );
      await _loadLeasePayments(showLoader: false);
      if (mounted) {
        _showAdminMessage('Lease rental status updated successfully.');
      }
    } on ApiException catch (error) {
      if (mounted) {
        _showAdminMessage(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingRentalStatusId = null;
        });
      }
    }
  }

  int _metricCount({
    required String sectionKey,
    required String nestedKey,
    List<String> flatFallbackKeys = const [],
  }) {
    final section = _section(sectionKey);

    if (section.containsKey(nestedKey)) {
      return _asInt(section[nestedKey]);
    }

    final dashboard = _dashboard;
    if (dashboard != null) {
      for (final key in flatFallbackKeys) {
        if (dashboard.containsKey(key)) {
          return _asInt(dashboard[key]);
        }
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalUsers = _metricCount(
      sectionKey: 'users',
      nestedKey: 'total',
      flatFallbackKeys: const ['total_users'],
    );

    final restrictedUsers = _metricCount(
      sectionKey: 'users',
      nestedKey: 'restricted',
      flatFallbackKeys: const ['restricted_users'],
    );

    final activeLeases = _metricCount(
      sectionKey: 'leases',
      nestedKey: 'active',
      flatFallbackKeys: const ['active_lease_listings'],
    );

    final flaggedLeases = _metricCount(
      sectionKey: 'leases',
      nestedKey: 'flagged',
      flatFallbackKeys: const [
        'flagged_lease_listings',
        'total_flagged_leases',
      ],
    );

    final totalProductivity = _metricCount(
      sectionKey: 'productivity',
      nestedKey: 'total_records',
      flatFallbackKeys: const ['total_productivity_records'],
    );

    final totalSoilLogs = _metricCount(
      sectionKey: 'soil_analysis_logs',
      nestedKey: 'total_logs',
      flatFallbackKeys: const [
        'total_soil_analyses',
        'total_soil_analysis_logs',
      ],
    );

    final metrics = <_AdminMetric>[
      _AdminMetric(
        label: 'Users',
        value: '$totalUsers',
        icon: Icons.people_outline,
        onTap: _openUsers,
      ),
      _AdminMetric(
        label: 'Restricted Users',
        value: '$restrictedUsers',
        icon: Icons.block_outlined,
        onTap: _openRestrictedUsers,
      ),
      _AdminMetric(
        label: 'Active Leases',
        value: '$activeLeases',
        icon: Icons.storefront_outlined,
        onTap: _openLeases,
      ),
      _AdminMetric(
        label: 'Flagged Leases',
        value: '$flaggedLeases',
        icon: Icons.flag_outlined,
        onTap: _openFlaggedLeases,
      ),
      _AdminMetric(
        label: 'Productivity Records',
        value: '$totalProductivity',
        icon: Icons.insights_outlined,
        onTap: _openProductivity,
      ),
      _AdminMetric(
        label: 'Soil Logs',
        value: '$totalSoilLogs',
        icon: Icons.history_edu_outlined,
        onTap: _openSoilLogs,
      ),
    ];

    final modules = <_AdminModuleEntry>[
      _AdminModuleEntry(
        title: 'Users',
        subtitle: 'View registered accounts and current moderation status.',
        icon: Icons.manage_accounts_outlined,
        onTap: _openUsers,
      ),
      _AdminModuleEntry(
        title: 'Leases',
        subtitle: 'View lease listings and their current review state.',
        icon: Icons.fact_check_outlined,
        onTap: _openLeases,
      ),
      _AdminModuleEntry(
        title: 'Productivity',
        subtitle: 'Review submitted productivity records across users.',
        icon: Icons.bar_chart_outlined,
        onTap: _openProductivity,
      ),
      _AdminModuleEntry(
        title: 'Soil Logs',
        subtitle: 'Review soil analysis log history from the backend.',
        icon: Icons.analytics_outlined,
        onTap: _openSoilLogs,
      ),
    ];

    if (_isLoading && _dashboard == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _dashboard == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadDashboard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;

    final metricCrossAxisCount = width >= 900 ? 3 : 2;
    final metricAspectRatio = width >= 900
        ? 2.1
        : width >= 600
            ? 1.7
            : 1.35;

    final moduleCrossAxisCount = width >= 1100
        ? 3
        : width >= 700
            ? 2
            : 1;

    final moduleAspectRatio = moduleCrossAxisCount == 1 ? 1.85 : 1.45;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: _refreshAdminData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAdminData,
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
              title: 'Administrator',
              icon: Icons.admin_panel_settings_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currentUser.fullName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(widget.currentUser.email),
                  const SizedBox(height: 8),
                  Text(
                    'Use the admin tools below to review users, leases, productivity records, and soil analysis logs.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            InfoCard(
              title: 'System Overview',
              icon: Icons.dashboard_outlined,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: metricCrossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: metricAspectRatio,
                ),
                itemBuilder: (context, index) {
                  return _AdminMetricCard(metric: metrics[index]);
                },
              ),
            ),
            InfoCard(
              title: 'Lease Payment Monitoring',
              icon: Icons.payments_outlined,
              child: _buildLeasePaymentMonitoring(context),
            ),
            Text(
              'Admin Modules',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: modules.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: moduleCrossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: moduleAspectRatio,
              ),
              itemBuilder: (context, index) {
                return _AdminModuleCard(module: modules[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeasePaymentMonitoring(BuildContext context) {
    if (_isPaymentLoading && _leasePayments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_paymentErrorMessage != null && _leasePayments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _paymentErrorMessage!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadLeasePayments,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    if (_leasePayments.isEmpty) {
      return Text(
        'No lease rental payment records are available right now.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    return Column(
      children: [
        if (_paymentErrorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _paymentErrorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        for (final payment in _leasePayments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildLeasePaymentRecord(context, payment),
          ),
      ],
    );
  }

  Widget _buildLeasePaymentRecord(
    BuildContext context,
    Map<String, dynamic> payment,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final rentalId = _asInt(payment['rental_id'] ?? payment['id']);
    final rentalStatus = _statusValue(
      payment['rental_status'],
      _rentalStatuses,
      'pending',
    );
    final paymentStatus = _statusValue(
      payment['payment_status'],
      _paymentStatuses,
      'unpaid',
    );
    final updatingStatus = _updatingRentalStatusId == rentalId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _display(payment['lease_title']),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(label: Text(paymentStatus)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _buildPaymentText('Renter', _display(payment['renter_name'])),
              _buildPaymentText('Contact', _display(payment['renter_contact'])),
              _buildPaymentText('Total', _formatMoney(payment['total_amount'])),
              _buildPaymentText(
                'Paid',
                _formatMoney(payment['amount_paid']),
              ),
              _buildPaymentText(
                'Balance',
                _formatMoney(payment['balance_amount']),
              ),
              _buildPaymentText(
                'Due',
                _formatDateValue(payment['payment_due_date']),
              ),
              _buildPaymentText('Rental Status', rentalStatus),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showUpdatePaymentDialog(payment),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Update Payment'),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: rentalStatus,
                  decoration: const InputDecoration(
                    labelText: 'Rental Status',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: _rentalStatuses
                      .map(
                        (status) => DropdownMenuItem<String>(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
                  onChanged: updatingStatus
                      ? null
                      : (value) {
                          if (value == null || value == rentalStatus) {
                            return;
                          }
                          _updateRentalStatus(payment, value);
                        },
                ),
              ),
              if (updatingStatus)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentText(String label, String value) {
    return Text('$label: $value');
  }
}

class _AdminMetric {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.metric});

  final _AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: metric.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(metric.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminModuleEntry {
  const _AdminModuleEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _AdminModuleCard extends StatelessWidget {
  const _AdminModuleCard({required this.module});

  final _AdminModuleEntry module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: module.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  module.icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                module.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                module.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
