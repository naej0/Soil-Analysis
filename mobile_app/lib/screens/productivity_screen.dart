import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/productivity_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/info_card.dart';

class ProductivityScreen extends StatefulWidget {
  const ProductivityScreen({
    super.key,
    required this.apiService,
    required this.currentUser,
  });

  final ApiService apiService;
  final UserModel currentUser;

  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cropController = TextEditingController();
  final _areaController = TextEditingController();
  final _yieldController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedSoilType = ApiConfig.supportedSoilTypes.first;
  bool _loadingRecords = false;
  bool _submitting = false;
  List<ProductivityRecord> _records = const [];
  String? _recordsMessage;
  bool _recordsMessageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _cropController.dispose();
    _areaController.dispose();
    _yieldController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loadingRecords = true;
      _recordsMessage = null;
      _recordsMessageIsError = false;
    });

    try {
      final records = await widget.apiService.getProductivityRecords(widget.currentUser.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _recordsMessage = null;
        _recordsMessageIsError = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordsMessage =
            'Saved productivity records could not be loaded right now. Pull down to try again.';
        _recordsMessageIsError = true;
      });
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _loadingRecords = false;
        });
      }
    }
  }

  Future<void> _createRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.apiService.createProductivityRecord(
        userId: widget.currentUser.id,
        soilType: _selectedSoilType,
        cropName: _cropController.text.trim(),
        areaHectares: _areaController.text.trim(),
        yieldAmount: _yieldController.text.trim(),
        notes: _notesController.text.trim(),
      );

      _cropController.clear();
      _areaController.clear();
      _yieldController.clear();
      _notesController.clear();

      await _loadRecords();

      if (!mounted) {
        return;
      }
      _showMessage(
        _recordsMessageIsError
            ? 'Productivity record saved, but the history list could not be refreshed right now.'
            : 'Productivity record saved successfully.',
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

  String _formatYield(double value) => _formatNumber(value);

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

  double? _yieldPerHectare(ProductivityRecord record) {
    if (record.areaHectares <= 0 || record.yieldAmount <= 0) {
      return null;
    }
    return record.yieldAmount / record.areaHectares;
  }

  _ProductivityInsight _buildInsight(ProductivityRecord record) {
    final yieldPerHectare = _yieldPerHectare(record);

    if (yieldPerHectare == null) {
      return const _ProductivityInsight(
        status: 'Low Productivity',
        explanation:
            'This record shows a very light harvest for the recorded area. Check field notes, timing, and inputs before the next planting cycle.',
      );
    }

    if (yieldPerHectare >= 4) {
      return _ProductivityInsight(
        status: 'High Productivity',
        explanation:
            'This record shows a strong yield for the recorded area at about ${_formatNumber(yieldPerHectare)} per hectare.',
      );
    }

    if (yieldPerHectare >= 2) {
      return _ProductivityInsight(
        status: 'Moderate Productivity',
        explanation:
            'This record shows a workable yield for the recorded area at about ${_formatNumber(yieldPerHectare)} per hectare, with room to improve.',
      );
    }

    return _ProductivityInsight(
      status: 'Low Productivity',
      explanation:
          'This record suggests a lighter yield for the recorded area at about ${_formatNumber(yieldPerHectare)} per hectare.',
    );
  }

  Color _insightColor(BuildContext context, String status) {
    switch (status) {
      case 'High Productivity':
        return Colors.green.shade700;
      case 'Moderate Productivity':
        return Colors.orange.shade700;
      case 'Low Productivity':
        return Colors.red.shade700;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _recordsMessageColor(BuildContext context) {
    return _recordsMessageIsError
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
        onPressed: _submitting ? null : _createRecord,
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
                  _submitting ? 'Saving Productivity Record...' : 'Save Productivity Record',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, ProductivityRecord record) {
    final colorScheme = Theme.of(context).colorScheme;
    final insight = _buildInsight(record);
    final yieldPerHectare = _yieldPerHectare(record);

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
                        record.cropName.trim().isEmpty
                            ? 'Unnamed Crop'
                            : record.cropName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          record.soilType,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _insightColor(context, insight.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _insightColor(context, insight.status).withOpacity(0.18),
                    ),
                  ),
                  child: Text(
                    insight.status,
                    style: TextStyle(
                      color: _insightColor(context, insight.status),
                      fontWeight: FontWeight.w700,
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
                        label: 'Area',
                        value: _formatArea(record.areaHectares),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _buildMetricTile(
                        context,
                        label: 'Yield',
                        value: _formatYield(record.yieldAmount),
                      ),
                    ),
                    if (yieldPerHectare != null)
                      SizedBox(
                        width: itemWidth,
                        child: _buildMetricTile(
                          context,
                          label: 'Yield per ha',
                          value: _formatNumber(yieldPerHectare),
                        ),
                      ),
                    SizedBox(
                      width: itemWidth,
                      child: _buildMetricTile(
                        context,
                        label: 'Recorded',
                        value: _formatDate(record.createdAt),
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
                    'Productivity Interpretation',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    insight.explanation,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Field Notes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              record.notes?.trim().isNotEmpty == true
                  ? record.notes!.trim()
                  : 'No field notes were recorded for this harvest.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
      appBar: AppBar(title: const Text('Productivity Monitor')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRecords,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoCard(
                title: 'Farmer Profile',
                icon: Icons.person_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track harvest performance for the signed-in farmer and review past field results in one place.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.currentUser.fullName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(widget.currentUser.email),
                          const SizedBox(height: 4),
                          Text(
                            'User ID: ${widget.currentUser.id}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              InfoCard(
                title: 'Add Productivity Record',
                icon: Icons.add_chart_outlined,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record the crop, soil type, field area, and harvest yield to review productivity over time.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildFormGroup(
                        context,
                        title: 'Field Details',
                        description:
                            'Start with the soil type, crop, and planted area for this record.',
                        children: [
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
                            controller: _cropController,
                            label: 'Crop Name',
                            prefixIcon: Icons.grass_outlined,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter the crop name.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _areaController,
                            label: 'Area (ha)',
                            prefixIcon: Icons.square_foot_outlined,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter the planted area.';
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
                        title: 'Harvest Details',
                        description:
                            'Add the harvest result and any short field note worth remembering.',
                        children: [
                          CustomTextField(
                            controller: _yieldController,
                            label: 'Yield Amount',
                            prefixIcon: Icons.bar_chart_outlined,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter the harvest yield.';
                              }
                              if (double.tryParse(value.trim()) == null) {
                                return 'Enter a valid yield number.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _notesController,
                            label: 'Field Notes',
                            prefixIcon: Icons.notes_outlined,
                            maxLines: 3,
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
                title: 'Productivity History',
                icon: Icons.history_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review saved harvest records below. Pull down anytime to refresh.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                        '${_records.length} productivity record${_records.length == 1 ? '' : 's'} saved',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (_recordsMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _recordsMessage!,
                        style: TextStyle(color: _recordsMessageColor(context)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_loadingRecords)
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
                              'Loading saved productivity records...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      )
                    else if (_records.isEmpty)
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
                          'No productivity records have been saved yet. Add your first harvest record above to start tracking field results.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    else ...[
                      _buildSectionLabel(context, 'Saved Records'),
                      const SizedBox(height: 12),
                      ..._records.map((record) => _buildRecordCard(context, record)),
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

class _ProductivityInsight {
  const _ProductivityInsight({
    required this.status,
    required this.explanation,
  });

  final String status;
  final String explanation;
}
