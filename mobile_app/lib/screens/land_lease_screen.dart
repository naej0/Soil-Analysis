import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const List<String> _durationUnits = ['days', 'months', 'years'];

  static const List<String> _leaseMediaExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'bmp',
    'gif',
    'tif',
    'tiff',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'zip',
    'shp',
    'shx',
    'dbf',
    'prj',
    'cpg',
  ];

  final ImagePicker _imagePicker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _ownerController = TextEditingController();
  final _contactController = TextEditingController();
  final _barangayController = TextEditingController();
  final _areaSqmController = TextEditingController();
  final _priceController = TextEditingController();
  final _rentalStartDateController = TextEditingController();
  final _durationController = TextEditingController(text: '6');
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedSoilType = ApiConfig.supportedSoilTypes.first;
  String _selectedDurationUnit = _durationUnits[1];
  DateTime? _rentalStartDate;
  List<File> _selectedMediaFiles = const [];

  bool _loadingList = false;
  bool _submitting = false;
  int? _loadingMediaLeaseId;
  int? _loadingContractLeaseId;
  String? _submissionStatus;
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
    _titleController.dispose();
    _ownerController.dispose();
    _contactController.dispose();
    _barangayController.dispose();
    _areaSqmController.dispose();
    _priceController.dispose();
    _rentalStartDateController.dispose();
    _durationController.dispose();
    _locationController.dispose();
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

    final rentalStartDate = _rentalStartDate;
    if (rentalStartDate == null) {
      _showMessage('Select the rental start date.');
      return;
    }

    setState(() {
      _submitting = true;
      _submissionStatus = 'Saving lease listing...';
    });

    try {
      final lease = await widget.apiService.createLease(
        leaseTitle: _titleController.text.trim(),
        ownerName: _ownerController.text.trim(),
        contactNumber: _contactController.text.trim(),
        barangay: _barangayController.text.trim(),
        soilType: _selectedSoilType,
        areaSqm: _areaSqmController.text.trim(),
        price: _emptyToNull(_priceController.text),
        description: _descriptionController.text.trim(),
        rentalStartDate: _formatDateForQuery(rentalStartDate),
        durationValue: _durationController.text.trim(),
        durationUnit: _selectedDurationUnit,
        locationDescription: _locationController.text.trim(),
      );

      final mediaFiles = List<File>.from(_selectedMediaFiles);
      final failedUploads = <String>[];

      for (var index = 0; index < mediaFiles.length; index++) {
        if (!mounted) {
          return;
        }

        setState(() {
          _submissionStatus =
              'Uploading media ${index + 1} of ${mediaFiles.length}...';
        });

        final file = mediaFiles[index];
        try {
          await widget.apiService.uploadLeaseMedia(
            leaseId: lease.id,
            file: file,
          );
        } on ApiException {
          failedUploads.add(_fileName(file));
        }
      }

      _clearCreateForm();
      await _loadLeases();

      if (!mounted) {
        return;
      }

      if (failedUploads.isNotEmpty) {
        final fileLabel = failedUploads.length == 1
            ? failedUploads.first
            : '${failedUploads.length} media files';
        _showMessage(
          'Lease listing created, but $fileLabel could not be uploaded.',
        );
      } else {
        _showMessage(
          mediaFiles.isEmpty
              ? 'Lease listing created successfully.'
              : 'Lease listing and media uploaded successfully.',
        );
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submissionStatus = null;
        });
      }
    }
  }

  void _clearCreateForm() {
    _titleController.clear();
    _ownerController.clear();
    _contactController.clear();
    _barangayController.clear();
    _areaSqmController.clear();
    _priceController.clear();
    _rentalStartDateController.clear();
    _durationController.text = '6';
    _locationController.clear();
    _descriptionController.clear();

    setState(() {
      _selectedSoilType = ApiConfig.supportedSoilTypes.first;
      _selectedDurationUnit = _durationUnits[1];
      _rentalStartDate = null;
      _selectedMediaFiles = const [];
    });
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickRentalStartDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _rentalStartDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20, 12, 31),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    setState(() {
      _rentalStartDate = pickedDate;
      _rentalStartDateController.text = _formatDateOnly(pickedDate);
    });
  }

  Future<void> _captureLeasePhoto() async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedImage == null) {
        return;
      }

      final capturedFile = File(pickedImage.path);

      setState(() {
        final filesByPath = {
          for (final file in _selectedMediaFiles) file.path: file,
          capturedFile.path: capturedFile,
        };
        _selectedMediaFiles = filesByPath.values.toList();
      });
    } on PlatformException {
      _showMessage('Could not open the camera right now.');
    } catch (_) {
      _showMessage('Could not capture lease photo right now.');
    }
  }

  Future<void> _pickLeaseMedia() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: _leaseMediaExtensions,
      );

      if (result == null) {
        return;
      }

      final pickedFiles = result.files
          .where((file) => file.path != null && file.path!.trim().isNotEmpty)
          .map((file) => File(file.path!))
          .toList();

      if (pickedFiles.isEmpty) {
        _showMessage('No uploadable media file was selected.');
        return;
      }

      setState(() {
        final filesByPath = {
          for (final file in _selectedMediaFiles) file.path: file,
          for (final file in pickedFiles) file.path: file,
        };
        _selectedMediaFiles = filesByPath.values.toList();
      });
    } on PlatformException {
      _showMessage('Could not open the file picker right now.');
    } catch (_) {
      _showMessage('Could not select lease media right now.');
    }
  }

  void _removeSelectedMedia(File file) {
    setState(() {
      _selectedMediaFiles = _selectedMediaFiles
          .where((selectedFile) => selectedFile.path != file.path)
          .toList();
    });
  }

  Future<void> _viewLeaseMedia(LeaseModel lease) async {
    setState(() {
      _loadingMediaLeaseId = lease.id;
    });

    List<Map<String, dynamic>> mediaItems = const [];
    try {
      final details = await widget.apiService.getLeaseDetails(lease.id);
      mediaItems = _extractLeaseMedia(details);
    } on ApiException catch (error) {
      if (mounted) {
        _showMessage('Could not load lease media: ${error.message}');
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _loadingMediaLeaseId = null;
        });
      }
    }

    if (!mounted) {
      return;
    }

    await _showLeaseMediaSheet(lease, mediaItems);
  }

  Future<void> _viewLeaseContract(LeaseModel lease) async {
    setState(() {
      _loadingContractLeaseId = lease.id;
    });

    Map<String, dynamic>? contract;
    try {
      contract = await widget.apiService.getLeaseContract(lease.id);
    } on ApiException catch (error) {
      if (mounted) {
        _showMessage('Could not load generated contract: ${error.message}');
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _loadingContractLeaseId = null;
        });
      }
    }

    if (!mounted || contract == null) {
      return;
    }

    await _showLeaseContractSheet(lease, contract);
  }

  List<Map<String, dynamic>> _extractLeaseMedia(Map<String, dynamic> data) {
    final leaseData = data['lease'];
    if (leaseData is Map) {
      final leaseMedia = _mapJsonList(leaseData['media']);
      if (leaseMedia.isNotEmpty) {
        return leaseMedia;
      }
    }

    return _mapJsonList(data['media']);
  }

  List<Map<String, dynamic>> _mapJsonList(dynamic value) {
    final items = value is List ? value : const [];

    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _openUploadedFile(String filePath) async {
    final url = widget.apiService.buildUploadedFileUrl(filePath);
    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme) {
      _showMessage('This uploaded file does not have a valid URL.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showMessage('Could not open the uploaded file.');
      }
    } catch (_) {
      _showMessage('Could not open the uploaded file.');
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

  String? _validateRequiredText(String? value, String message) {
    return value == null || value.trim().isEmpty ? message : null;
  }

  String? _validateRequiredPositiveNumber(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }

    final parsedValue = double.tryParse(value.trim());
    if (parsedValue == null || parsedValue <= 0) {
      return 'Enter a valid number greater than zero.';
    }

    return null;
  }

  String? _validateOptionalPositiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsedValue = double.tryParse(value.trim());
    if (parsedValue == null || parsedValue <= 0) {
      return 'Enter a valid number greater than zero.';
    }

    return null;
  }

  String _formatNumber(double value) {
    final roundedWhole = value.roundToDouble();
    if ((value - roundedWhole).abs() < 0.05) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatAreaForLease(LeaseModel lease) {
    final areaSqm = lease.areaSqm;
    if (areaSqm != null && areaSqm > 0) {
      return '${_formatNumber(areaSqm)} sqm';
    }

    if (lease.areaHectares > 0) {
      return '${_formatNumber(lease.areaHectares)} ha';
    }

    return 'Area TBD';
  }

  String _formatPrimaryPriceForLease(LeaseModel lease) {
    final totalLeasePrice = lease.totalLeasePrice;
    if (totalLeasePrice != null && totalLeasePrice > 0) {
      return _formatPrice(totalLeasePrice);
    }

    if (lease.price > 0) {
      return _formatPrice(lease.price);
    }

    return 'Price TBD';
  }

  String? _formatPricePerSqmForLease(LeaseModel lease) {
    final pricePerSqm = lease.pricePerSqm;
    if (pricePerSqm == null || pricePerSqm <= 0) {
      return null;
    }

    return '${_formatPrice(pricePerSqm)} / sqm';
  }

  String _formatDuration(LeaseModel lease) {
    final value = lease.durationValue;
    final unit = lease.durationUnit?.trim();

    if (value != null && value > 0 && unit != null && unit.isNotEmpty) {
      return '${_formatNumber(value)} $unit';
    }

    final months = lease.durationMonths;
    if (months != null && months > 0) {
      return '${_formatNumber(months)} months';
    }

    return 'Not specified';
  }

  String _formatPrice(double value) {
    final roundedWhole = value.roundToDouble();
    final hasFraction = (value - roundedWhole).abs() >= 0.005;
    final fixedValue =
        hasFraction ? value.toStringAsFixed(2) : value.round().toString();
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

  String _formatDateForQuery(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateOnly(DateTime value) {
    final local = value.toLocal();
    return '${_monthLabel(local.month)} ${local.day}, ${local.year}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Unknown date';
    }

    final local = value.toLocal();
    final month = _monthLabel(local.month);
    final hour =
        local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
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

  String _fileName(File file) {
    final parts = file.path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? file.path : parts.last;
  }

  IconData _mediaIconForFile(File file) {
    final name = _fileName(file).toLowerCase();

    if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv') ||
        name.endsWith('.webm')) {
      return Icons.videocam_outlined;
    }

    if (name.endsWith('.zip') ||
        name.endsWith('.shp') ||
        name.endsWith('.shx') ||
        name.endsWith('.dbf') ||
        name.endsWith('.prj') ||
        name.endsWith('.cpg')) {
      return Icons.folder_zip_outlined;
    }

    return Icons.image_outlined;
  }

  String _displayText(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  String? _textFrom(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _firstNonEmptyText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = _textFrom(value);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  double? _doubleFrom(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    final text = _textFrom(value);
    return text == null ? null : double.tryParse(text);
  }

  String _formatContractPrice(dynamic value, {String suffix = ''}) {
    final amount = _doubleFrom(value);
    if (amount == null || amount <= 0) {
      return 'Not available';
    }
    return '${_formatPrice(amount)}$suffix';
  }

  String _formatGeneratedAt(dynamic value) {
    final text = _textFrom(value);
    if (text == null) {
      return 'Not available';
    }

    return _formatDate(DateTime.tryParse(text));
  }

  String _mediaDisplayName(Map<String, dynamic> media) {
    return _firstNonEmptyText([
          media['original_file_name'],
          media['saved_file_name'],
          media['file_path'],
        ]) ??
        'Uploaded media';
  }

  String? _mediaFilePath(Map<String, dynamic> media) {
    return _textFrom(media['file_path']);
  }

  String _mediaExtension(Map<String, dynamic> media) {
    final explicitExtension = _textFrom(media['file_extension']);
    if (explicitExtension != null) {
      return explicitExtension.startsWith('.')
          ? explicitExtension.toLowerCase()
          : '.$explicitExtension'.toLowerCase();
    }

    final name = _mediaDisplayName(media);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return '';
    }

    return name.substring(dotIndex).toLowerCase();
  }

  String _mediaMetadata(Map<String, dynamic> media) {
    final parts = [
      _textFrom(media['file_type']),
      _mediaExtension(media).isEmpty ? null : _mediaExtension(media),
    ].whereType<String>().toList();

    return parts.isEmpty ? 'Uploaded file' : parts.join(' | ');
  }

  bool _isImageMedia(Map<String, dynamic> media) {
    final fileType = (_textFrom(media['file_type']) ?? '').toLowerCase();
    final extension = _mediaExtension(media);

    return fileType.contains('photo') ||
        fileType.contains('image') ||
        const {
          '.bmp',
          '.gif',
          '.heic',
          '.heif',
          '.jpeg',
          '.jpg',
          '.png',
          '.tif',
          '.tiff',
          '.webp',
        }.contains(extension);
  }

  IconData _mediaIconForItem(Map<String, dynamic> media) {
    final fileType = (_textFrom(media['file_type']) ?? '').toLowerCase();
    final extension = _mediaExtension(media);

    if (_isImageMedia(media)) {
      return Icons.image_outlined;
    }

    if (fileType.contains('video') ||
        const {'.avi', '.mkv', '.mov', '.mp4', '.webm'}.contains(extension)) {
      return Icons.videocam_outlined;
    }

    if (const {'.cpg', '.dbf', '.prj', '.shp', '.shx', '.zip'}
        .contains(extension)) {
      return Icons.folder_zip_outlined;
    }

    return Icons.insert_drive_file_outlined;
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

  Widget _buildDateField(BuildContext context) {
    return TextFormField(
      controller: _rentalStartDateController,
      readOnly: true,
      onTap: _submitting ? null : _pickRentalStartDate,
      validator: (value) => _validateRequiredText(
        value,
        'Select the rental start date.',
      ),
      decoration: _buildDropdownDecoration(
        context,
        label: 'Rental Start Date',
        icon: Icons.calendar_today_outlined,
      ).copyWith(
        suffixIcon: Icon(
          Icons.event_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMediaPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.perm_media_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lease Media',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _submitting ? null : _captureLeasePhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take Photo'),
              ),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickLeaseMedia,
                icon: const Icon(Icons.attach_file_outlined, size: 18),
                label: const Text('Add File'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Optional: upload photos, videos, shapefile parts, or a zipped shapefile.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          if (_selectedMediaFiles.isEmpty)
            Text(
              'No media selected.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            )
          else
            Column(
              children: _selectedMediaFiles
                  .map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            _mediaIconForFile(file),
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fileName(file),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Remove media',
                            onPressed: _submitting
                                ? null
                                : () => _removeSelectedMedia(file),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
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
                  _submitting
                      ? (_submissionStatus ?? 'Saving lease listing...')
                      : 'Create Lease Listing',
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

  Widget _buildLeaseActionButton({
    required bool loading,
    required IconData icon,
    required String label,
    required String loadingLabel,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(loading ? loadingLabel : label),
    );
  }

  Future<void> _showLeaseMediaSheet(
    LeaseModel lease,
    List<Map<String, dynamic>> mediaItems,
  ) {
    final title = _displayText(lease.leaseTitle, 'Lease Media');

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return FractionallySizedBox(
          heightFactor: mediaItems.isEmpty ? 0.45 : 0.86,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (mediaItems.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No media uploaded for this lease.',
                          textAlign: TextAlign.center,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: mediaItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _buildUploadedMediaItem(
                            sheetContext,
                            mediaItems[index],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUploadedMediaItem(
    BuildContext context,
    Map<String, dynamic> media,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = _mediaDisplayName(media);
    final filePath = _mediaFilePath(media);
    final hasFilePath = filePath != null;
    final isImage = _isImageMedia(media);
    final url = hasFilePath
        ? Uri.encodeFull(widget.apiService.buildUploadedFileUrl(filePath))
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _mediaIconForItem(media),
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _mediaMetadata(media),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasFilePath)
            Text(
              'File path unavailable.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
            )
          else if (isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return Container(
                    height: 180,
                    alignment: Alignment.center,
                    color: colorScheme.surface,
                    child: const CircularProgressIndicator(),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: colorScheme.surface,
                    child: Text(
                      'Preview unavailable. Tap Open to view this file.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openUploadedFile(filePath),
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                label: const Text('Open'),
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openUploadedFile(filePath),
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                label: const Text('Open'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showLeaseContractSheet(
    LeaseModel lease,
    Map<String, dynamic> contract,
  ) {
    final contractNumber =
        _textFrom(contract['contract_number']) ?? 'Not available';
    final contractBody = _textFrom(contract['contract_body']) ??
        'No contract body was returned.';

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Generated Contract',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildContractInfoTile(
                        sheetContext,
                        label: 'Contract Number',
                        value: contractNumber,
                      ),
                      _buildContractInfoTile(
                        sheetContext,
                        label: 'Price per sqm',
                        value: _formatContractPrice(
                          contract['price_per_sqm'],
                          suffix: ' / sqm',
                        ),
                      ),
                      _buildContractInfoTile(
                        sheetContext,
                        label: 'Total Lease Price',
                        value: _formatContractPrice(
                          contract['total_lease_price'],
                        ),
                      ),
                      _buildContractInfoTile(
                        sheetContext,
                        label: 'Generated At',
                        value: _formatGeneratedAt(contract['generated_at']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _displayText(lease.leaseTitle, 'Contract Body'),
                    style:
                        Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withOpacity(0.35),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.1),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          contractBody,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                height: 1.35,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContractInfoTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return SizedBox(
      width: 220,
      child: _buildMetricTile(
        context,
        label: label,
        value: value,
      ),
    );
  }

  Widget _buildLeaseCard(BuildContext context, LeaseModel lease) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = _displayText(
      lease.leaseTitle,
      lease.ownerName.trim().isEmpty ? 'Unnamed Lease' : lease.ownerName,
    );
    final ownerName = _displayText(lease.ownerName, 'Unnamed Owner');
    final pricePerSqm = _formatPricePerSqmForLease(lease);

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
                        displayTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if ((lease.leaseTitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ownerName,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
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
                            label: 'Area: ${_formatAreaForLease(lease)}',
                          ),
                          if (pricePerSqm != null)
                            _buildSummaryChip(
                              context,
                              icon: Icons.price_change_outlined,
                              label: pricePerSqm,
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
                    _formatPrimaryPriceForLease(lease),
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
                        label: 'Rental Start',
                        value: lease.rentalStartDate == null
                            ? 'Not specified'
                            : _formatDateOnly(lease.rentalStartDate!),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _buildMetricTile(
                        context,
                        label: 'Duration',
                        value: _formatDuration(lease),
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
            if ((lease.locationDescription ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildMetricTile(
                context,
                label: 'Location Description',
                value: lease.locationDescription!.trim(),
              ),
            ],
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildLeaseActionButton(
                  loading: _loadingMediaLeaseId == lease.id,
                  icon: Icons.photo_library_outlined,
                  label: 'View Media',
                  loadingLabel: 'Loading Media...',
                  onPressed: () => _viewLeaseMedia(lease),
                ),
                _buildLeaseActionButton(
                  loading: _loadingContractLeaseId == lease.id,
                  icon: Icons.description_outlined,
                  label: 'View Generated Contract',
                  loadingLabel: 'Loading Contract...',
                  onPressed: () => _viewLeaseContract(lease),
                ),
              ],
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
                        'Add lease details, rental duration, land area, and optional media for farmers to review.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildFormGroup(
                        context,
                        title: 'Listing Details',
                        description:
                            'Name the lease and set when the rental period begins.',
                        children: [
                          CustomTextField(
                            controller: _titleController,
                            label: 'Lease Title',
                            prefixIcon: Icons.title_outlined,
                            validator: (value) => _validateRequiredText(
                              value,
                              'Enter the lease title.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDateField(context),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _durationController,
                            label: 'Duration Value',
                            prefixIcon: Icons.timelapse_outlined,
                            keyboardType: TextInputType.number,
                            validator: (value) =>
                                _validateRequiredPositiveNumber(
                              value,
                              'Enter the lease duration.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedDurationUnit,
                            decoration: _buildDropdownDecoration(
                              context,
                              label: 'Duration Unit',
                              icon: Icons.calendar_view_month_outlined,
                            ),
                            items: _durationUnits
                                .map(
                                  (unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            onChanged: _submitting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedDurationUnit = value;
                                      });
                                    }
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                            validator: (value) => _validateRequiredText(
                              value,
                              'Enter the owner name.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _contactController,
                            label: 'Contact Number',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (value) => _validateRequiredText(
                              value,
                              'Enter the contact number.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFormGroup(
                        context,
                        title: 'Land Details',
                        description:
                            'Highlight the barangay, soil type, land area, and field location.',
                        children: [
                          CustomTextField(
                            controller: _barangayController,
                            label: 'Barangay',
                            prefixIcon: Icons.place_outlined,
                            validator: (value) => _validateRequiredText(
                              value,
                              'Enter the barangay.',
                            ),
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
                            onChanged: _submitting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedSoilType = value;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _areaSqmController,
                            label: 'Area (sqm)',
                            prefixIcon: Icons.straighten_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) =>
                                _validateRequiredPositiveNumber(
                              value,
                              'Enter the land area in square meters.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _locationController,
                            label: 'Location Description',
                            prefixIcon: Icons.map_outlined,
                            maxLines: 2,
                            validator: (value) => _validateRequiredText(
                              value,
                              'Enter the location description.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFormGroup(
                        context,
                        title: 'Pricing / Description',
                        description:
                            'Price is optional because the backend can compute price using soil type and square meters.',
                        children: [
                          CustomTextField(
                            controller: _priceController,
                            label: 'Lease Price (Optional)',
                            prefixIcon: Icons.payments_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _validateOptionalPositiveNumber,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _descriptionController,
                            label: 'Lease Description',
                            prefixIcon: Icons.notes_outlined,
                            maxLines: 3,
                            validator: (value) => _validateRequiredText(
                              value,
                              'Add a lease description.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFormGroup(
                        context,
                        title: 'Media Uploads',
                        description:
                            'Optional: attach photos, videos, shapefile parts, or zipped shapefiles.',
                        children: [
                          _buildMediaPicker(context),
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
                      'Review farmland listings below. Barangay, soil type, area, rental duration, and computed price are highlighted for faster farm decisions.',
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
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
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      )
                    else ...[
                      _buildSectionLabel(context, 'Saved Listings'),
                      const SizedBox(height: 12),
                      ..._leases
                          .map((lease) => _buildLeaseCard(context, lease)),
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
