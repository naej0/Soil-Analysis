import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/lease_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/info_card.dart';

class LandLeaseScreen extends StatefulWidget {
  const LandLeaseScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<LandLeaseScreen> createState() => _LandLeaseScreenState();
}

class _LandLeaseScreenState extends State<LandLeaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerController = TextEditingController();
  final _contactController = TextEditingController();
  final _barangayController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedSoilType = ApiConfig.supportedSoilTypes.first;
  bool _loadingList = false;
  bool _submitting = false;
  List<LeaseModel> _leases = const [];
  String? _leasesMessage;
  bool _leasesMessageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadLeases();
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _contactController.dispose();
    _barangayController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLeases() async {
    setState(() {
      _loadingList = true;
      _leasesMessage = null;
      _leasesMessageIsError = false;
    });

    try {
      final leases = await widget.apiService.getLeases();
      if (!mounted) {
        return;
      }
      setState(() {
        _leases = leases;
        _leasesMessage = null;
        _leasesMessageIsError = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _leasesMessage =
            'Lease listings could not be loaded right now. Pull down to try again.';
        _leasesMessageIsError = true;
      });
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _loadingList = false;
        });
      }
    }
  }

  Future<void> _createLease() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.apiService.createLease(
        ownerName: _ownerController.text.trim(),
        contactNumber: _contactController.text.trim(),
        barangay: _barangayController.text.trim(),
        soilType: _selectedSoilType,
        areaHectares: _areaController.text.trim(),
        price: _priceController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      _ownerController.clear();
      _contactController.clear();
      _barangayController.clear();
      _areaController.clear();
      _priceController.clear();
      _descriptionController.clear();

      await _loadLeases();

      if (!mounted) {
        return;
      }
      _showMessage(
        _leasesMessageIsError
            ? 'Lease listing saved, but the listings could not be refreshed right now.'
            : 'Lease listing created successfully.',
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
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

  String _formatNumber(double value) {
    final roundedWhole = value.roundToDouble();
    if ((value - roundedWhole).abs() < 0.05) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatArea(double value) => '${_formatNumber(value)} ha';

  String _formatPrice(double value) {
    final roundedWhole = value.roundToDouble();
    final hasFraction = (value - roundedWhole).abs() >= 0.005;
    final fixedValue = hasFraction
        ? value.toStringAsFixed(2)
        : value.round().toString();
    final parts = fixedValue.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }

    if (parts.length > 1) {
      return 'PHP ${buffer.toString()}.${parts[1]}';
    }
    return 'PHP ${buffer.toString()}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Unknown date';
    }

    final local = value.toLocal();
    final month = _monthLabel(local.month);
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$month ${local.day}, ${local.year} \u2022 $hour:$minute $period';
  }

  String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Color _leasesMessageColor(BuildContext context) {
    return _leasesMessageIsError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildDropdownDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.18)),
    );

    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.25),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: colorScheme.onSurfaceVariant),
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    );
  }

  Widget _buildFormGroup(
    BuildContext context, {
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: colorScheme.primary.withOpacity(0.88),
          disabledForegroundColor: colorScheme.onPrimary,
        ),
        onPressed: _submitting ? null : _createLease,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_submitting) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: 10),
              ] else ...[
                const Icon(Icons.save_outlined, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  _submitting ? 'Saving Lease Listing...' : 'Create Lease Listing',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaseCard(BuildContext context, LeaseModel lease) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lease.ownerName.trim().isEmpty
                            ? 'Unnamed Owner'
                            : lease.ownerName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildSummaryChip(
                            context,
                            icon: Icons.place_outlined,
                            label: 'Barangay: ${lease.barangay}',
                          ),
                          _buildSummaryChip(
                            context,
                            icon: Icons.terrain_outlined,
                            label: 'Soil Type: ${lease.soilType}',
                          ),
                          _buildSummaryChip(
                            context,
                            icon: Icons.straighten_outlined,
                            label: 'Area: ${_formatArea(lease.areaHectares)}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.1),
                    ),
                  ),
                  child: Text(
                    _formatPrice(lease.price),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.primary,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 360;
                final itemWidth = isCompact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _buildMetricTile(
                        context,
                        label: 'Contact Number',
                        value: lease.contactNumber,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _buildMetricTile(
                        context,
                        label: 'Listed On',
                        value: _formatDate(lease.createdAt),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.32),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listing Summary',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lease.description.trim().isNotEmpty
                        ? lease.description.trim()
                        : 'No additional land details were provided in this listing.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Land Lease Marketplace')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadLeases,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoCard(
                title: 'Lease Marketplace',
                icon: Icons.storefront_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Post farmland for lease and review available farm lots in one place.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.1),
                        ),
                      ),
                      child: Text(
                        '${_leases.length} lease listing${_leases.length == 1 ? '' : 's'} available',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (_leasesMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _leasesMessage!,
                        style: TextStyle(color: _leasesMessageColor(context)),
                      ),
                    ],
                  ],
                ),
              ),
              InfoCard(
                title: 'Create Lease Listing',
                icon: Icons.add_business_outlined,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add the owner details, farm location, soil type, and lease price so farmers can review the listing clearly.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildFormGroup(
                        context,
                        title: 'Owner / Contact Details',
                        description:
                            'Enter the land owner name and the best phone number for inquiries.',
                        children: [
                          CustomTextField(
                            controller: _ownerController,
                            label: 'Owner Name',
                            prefixIcon: Icons.person_outline,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter the owner name.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _contactController,
                            label: 'Contact Number',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter the contact number.'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFormGroup(
                        context,
                        title: 'Land Details',
                        description:
                            'Highlight the barangay, soil type, and land area so farmers can scan the listing faster.',
                        children: [
                          CustomTextField(
                            controller: _barangayController,
                            label: 'Barangay',
                            prefixIcon: Icons.place_outlined,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter the barangay.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSoilType,
                            decoration: _buildDropdownDecoration(
                              context,
                              label: 'Soil Type',
                              icon: Icons.terrain_outlined,
                            ),
                            items: ApiConfig.supportedSoilTypes
                                .map(
                                  (soilType) => DropdownMenuItem(
                                    value: soilType,
                                    child: Text(soilType),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedSoilType = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _areaController,
                            label: 'Area (ha)',
                            prefixIcon: Icons.straighten_outlined,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter the land area.';
                              }
                              if (double.tryParse(value.trim()) == null) {
                                return 'Enter a valid area number.';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFormGroup(
                        context,
                        title: 'Pricing / Description',
                        description:
                            'Add the lease price and a short summary of the lot so farmers know what to expect.',
                        children: [
                          CustomTextField(
                            controller: _priceController,
                            label: 'Lease Price',
                            prefixIcon: Icons.payments_outlined,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter the lease price.';
                              }
                              if (double.tryParse(value.trim()) == null) {
                                return 'Enter a valid price number.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _descriptionController,
                            label: 'Short Description',
                            prefixIcon: Icons.notes_outlined,
                            maxLines: 3,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Add a short land description.'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildSubmitButton(context),
                    ],
                  ),
                ),
              ),
              InfoCard(
                title: 'Available Lease Listings',
                icon: Icons.storefront_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review farmland listings below. Barangay, soil type, area, and price are highlighted for faster farm decisions.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (_loadingList)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.32),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              'Loading available land lease listings...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      )
                    else if (_leases.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.32),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          'No land lease listings have been posted yet. Create the first listing above to start the marketplace.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    else ...[
                      _buildSectionLabel(context, 'Saved Listings'),
                      const SizedBox(height: 12),
                      ..._leases.map((lease) => _buildLeaseCard(context, lease)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
