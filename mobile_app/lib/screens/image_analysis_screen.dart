import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ai_prediction_model.dart';
import '../models/dashboard_model.dart';
import '../models/soil_analysis_support_model.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/info_card.dart';
import '../widgets/recommendation_card.dart';

class ImageAnalysisScreen extends StatefulWidget {
  const ImageAnalysisScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ImageAnalysisScreen> createState() => _ImageAnalysisScreenState();
}

class _ImageAnalysisScreenState extends State<ImageAnalysisScreen> {
  static const int _initialVisibleRecommendationCount = 6;

  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  AiUploadResponse? _uploadResponse;
  AiPredictionResponse? _predictionResponse;
  SoilAnalysisSupportResponse? _soilAnalysisSupport;

  Map<String, dynamic>? _cropRecommendationsPayload;
  List<RecommendationItem> _recommendations = const [];

  bool _isBusy = false;
  bool _isCropRecommendationsLoading = false;
  bool _isUsingCropRecommendationFallback = false;
  bool _showAllRecommendations = false;
  bool _showLongWaitMessage = false;

  String? _supportErrorMessage;
  String? _recommendationsErrorMessage;

  Timer? _longWaitTimer;
  _AnalysisStage _analysisStage = _AnalysisStage.idle;

  @override
  void dispose() {
    _stopLongWaitTimer();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          _showMessage('Camera permission is required to capture an image.');
          return;
        }
      }

      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (pickedFile == null) {
        return;
      }

      if (!widget.apiService.isSupportedSoilImagePath(pickedFile.path)) {
        _showMessage(
          'Unsupported file type. Allowed: ${widget.apiService.supportedSoilImageExtensionsLabel}',
        );
        return;
      }

      setState(() {
        _selectedImage = File(pickedFile.path);
        _uploadResponse = null;
        _predictionResponse = null;
        _soilAnalysisSupport = null;
        _cropRecommendationsPayload = null;
        _recommendations = const [];
        _isCropRecommendationsLoading = false;
        _isUsingCropRecommendationFallback = false;
        _showAllRecommendations = false;
        _showLongWaitMessage = false;
        _supportErrorMessage = null;
        _recommendationsErrorMessage = null;
        _analysisStage = _AnalysisStage.idle;
      });
    } on PlatformException {
      _showMessage(_buildImageSelectionErrorMessage(source));
    } catch (_) {
      _showMessage('Could not select an image right now. Please try again.');
    }
  }

  Future<void> _analyzeImage() async {
    final image = _selectedImage;
    if (image == null) {
      _showMessage('Pick or capture an image first.');
      return;
    }

    if (!widget.apiService.isSupportedSoilImagePath(image.path)) {
      _showMessage(
        'Unsupported file type. Allowed: ${widget.apiService.supportedSoilImageExtensionsLabel}',
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _analysisStage = _AnalysisStage.uploading;
      _showLongWaitMessage = false;
      _uploadResponse = null;
      _predictionResponse = null;
      _soilAnalysisSupport = null;
      _cropRecommendationsPayload = null;
      _recommendations = const [];
      _isCropRecommendationsLoading = false;
      _isUsingCropRecommendationFallback = false;
      _showAllRecommendations = false;
      _supportErrorMessage = null;
      _recommendationsErrorMessage = null;
    });

    _startLongWaitTimer();

    try {
      final upload = await widget.apiService.uploadSoilImage(image);
      if (!mounted) return;

      setState(() {
        _uploadResponse = upload;
        _analysisStage = _AnalysisStage.classifying;
      });

      final prediction = await widget.apiService.predictSoil(
        fileName: upload.fileName,
        userId: null,
        originalFileName: upload.originalFileName,
        lat: null,
        lng: null,
        barangay: null,
        soilName: null,
      );
      if (!mounted) return;

      final predictedSoil = prediction.prediction?.trim();
      final hasPredictedSoil =
          predictedSoil != null && predictedSoil.isNotEmpty;

      final cropRecommendationsFuture = hasPredictedSoil
          ? widget.apiService.getCropRecommendationsBySoilType(predictedSoil)
          : null;

      setState(() {
        _predictionResponse = prediction;
        _analysisStage = _AnalysisStage.preparingAdvice;
        _cropRecommendationsPayload = null;
        _isCropRecommendationsLoading = hasPredictedSoil;
        _isUsingCropRecommendationFallback = false;
      });

      SoilAnalysisSupportResponse? supportResponse;
      String? supportErrorMessage;

      if (hasPredictedSoil) {
        try {
          supportResponse = await widget.apiService.fetchSoilAnalysisSupport(
            predictedSoil,
          );
        } on ApiException catch (error) {
          supportErrorMessage = _buildSupportErrorMessage(error.message);
        }
      }

      if (!mounted) return;

      setState(() {
        _soilAnalysisSupport = supportResponse;
        _supportErrorMessage = supportErrorMessage;
        _analysisStage = _AnalysisStage.completed;
      });

      if (hasPredictedSoil) {
        unawaited(
          _loadCropRecommendationsForSoil(
            predictedSoil,
            supportFallback: supportResponse,
            backendFuture: cropRecommendationsFuture,
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(
        _buildAnalysisErrorMessage(
          error.message,
          stage: _analysisStage,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        _buildAnalysisErrorMessage(
          'Image analysis could not be completed right now. Please try again.',
          stage: _analysisStage,
        ),
      );
    } finally {
      _stopLongWaitTimer();
      if (mounted) {
        setState(() {
          _isBusy = false;
          _showLongWaitMessage = false;
          if (_analysisStage != _AnalysisStage.completed) {
            _analysisStage = _predictionResponse == null
                ? _AnalysisStage.idle
                : _AnalysisStage.completed;
          }
        });
      }
    }
  }

  String _formatPercent(double? value, {int fractionDigits = 1}) {
    if (value == null) {
      return 'N/A';
    }
    return '${(value * 100).toStringAsFixed(fractionDigits)}%';
  }

  String _buildImageSelectionErrorMessage(ImageSource source) {
    if (source == ImageSource.camera) {
      return 'Could not access the camera right now. Please check permissions and try again.';
    }
    return 'Could not access the photo library right now. Please check permissions and try again.';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _displayValue(dynamic value, {String fallback = 'N/A'}) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  void _startLongWaitTimer() {
    _stopLongWaitTimer();
    _longWaitTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_isBusy) return;
      setState(() {
        _showLongWaitMessage = true;
      });
    });
  }

  void _stopLongWaitTimer() {
    _longWaitTimer?.cancel();
    _longWaitTimer = null;
  }

  String _truncateMiddle(String value, {int maxLength = 44}) {
    if (value.length <= maxLength) {
      return value;
    }

    final preservedCharacters = maxLength - 3;
    final startLength = (preservedCharacters / 2).ceil();
    final endLength = preservedCharacters - startLength;

    return '${value.substring(0, startLength)}...${value.substring(value.length - endLength)}';
  }

  String _analysisStageLabel(_AnalysisStage stage) {
    switch (stage) {
      case _AnalysisStage.uploading:
        return 'Uploading soil image...';
      case _AnalysisStage.classifying:
        return 'Classifying soil type...';
      case _AnalysisStage.preparingAdvice:
        return 'Preparing crop advice...';
      case _AnalysisStage.completed:
        return 'Soil analysis ready';
      case _AnalysisStage.idle:
        return 'Upload and Analyze';
    }
  }

  String _analysisStageDescription(_AnalysisStage stage) {
    switch (stage) {
      case _AnalysisStage.uploading:
        return 'Sending your soil photo so we can begin the analysis.';
      case _AnalysisStage.classifying:
        return 'Checking the image now to identify the most likely soil type.';
      case _AnalysisStage.preparingAdvice:
        return 'Matching crops and practical field guidance for this soil type.';
      case _AnalysisStage.completed:
        return 'Review the soil type and guidance below.';
      case _AnalysisStage.idle:
        return 'Select a clear soil photo, then start the analysis.';
    }
  }

  int _analysisStageOrder(_AnalysisStage stage) {
    switch (stage) {
      case _AnalysisStage.idle:
        return 0;
      case _AnalysisStage.uploading:
        return 1;
      case _AnalysisStage.classifying:
        return 2;
      case _AnalysisStage.preparingAdvice:
      case _AnalysisStage.completed:
        return 3;
    }
  }

  String _analysisButtonLabel() {
    if (_isBusy) {
      return _analysisStageLabel(_analysisStage);
    }
    return 'Upload and Analyze';
  }

  String _buildAnalysisErrorMessage(
    String message, {
    required _AnalysisStage stage,
  }) {
    final normalized = message.toLowerCase();

    if (normalized.contains('could not connect to backend') ||
        normalized.contains('network request failed')) {
      if (stage == _AnalysisStage.uploading) {
        return 'We could not upload the soil photo. Please check your internet connection and try again.';
      }
      if (stage == _AnalysisStage.classifying) {
        return 'We lost connection while checking the soil type. Please try again.';
      }
      return 'We lost connection while preparing the soil advice. Please try again.';
    }

    if (stage == _AnalysisStage.uploading) {
      return 'The soil photo could not be uploaded right now. Please try again.';
    }
    if (stage == _AnalysisStage.classifying) {
      return 'We could not finish identifying the soil type right now. Please try again.';
    }
    if (stage == _AnalysisStage.preparingAdvice) {
      return 'The soil type is ready, but the advice could not be completed right now.';
    }
    return message;
  }

  String _buildRecommendationErrorMessage(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('could not connect to backend') ||
        normalized.contains('network request failed')) {
      return 'The soil type is ready, but we could not load the crop advice right now. Please try again in a moment.';
    }

    return 'The soil type is ready, but crop advice is not available right now.';
  }

  String _buildSupportErrorMessage(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('could not connect to backend') ||
        normalized.contains('network request failed')) {
      return 'The soil type is ready, but detailed soil support could not be loaded right now. Showing general guidance where available.';
    }

    return 'The soil type is ready, but detailed soil support is not available right now. Showing general guidance where available.';
  }

  bool _matchesCurrentPredictedSoil(String soilType) {
    return _predictionResponse?.prediction?.trim() == soilType;
  }

  List<RecommendationItem> _mapBackendRecommendationItems(dynamic value) {
    final items = value as List? ?? const [];

    return items
        .map(
          (item) => RecommendationItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((item) => item.cropName.trim().isNotEmpty)
        .toList();
  }

  List<RecommendationItem> _mapSupportRecommendationItems(
    SoilAnalysisSupportResponse? support,
  ) {
    return (support?.recommendedCrops ?? const <RecommendedCrop>[])
        .map(
          (item) => RecommendationItem(
            cropName: item.cropName,
            suitability: item.suitability,
            notes: item.notes,
          ),
        )
        .toList();
  }

  Future<_CropRecommendationResult> _loadFallbackCropRecommendations(
    String soilType, {
    SoilAnalysisSupportResponse? supportFallback,
  }) async {
    final supportRecommendations =
        _mapSupportRecommendationItems(supportFallback);

    if (supportRecommendations.isNotEmpty) {
      return _CropRecommendationResult(
        recommendations: supportRecommendations,
        isUsingFallback: true,
      );
    }

    try {
      final recommendations =
          await widget.apiService.getRecommendationsBySoil(soilType);

      return _CropRecommendationResult(
        recommendations: recommendations,
        isUsingFallback: true,
      );
    } on ApiException catch (error) {
      return _CropRecommendationResult(
        recommendations: const [],
        isUsingFallback: true,
        errorMessage: _buildRecommendationErrorMessage(error.message),
      );
    }
  }

  Future<void> _loadCropRecommendationsForSoil(
    String soilType, {
    SoilAnalysisSupportResponse? supportFallback,
    Future<Map<String, dynamic>>? backendFuture,
  }) async {
    Map<String, dynamic>? cropRecommendationsPayload;
    List<RecommendationItem> recommendations = const [];
    String? recommendationsErrorMessage;
    var isUsingFallback = false;

    try {
      final payload = await (backendFuture ??
          widget.apiService.getCropRecommendationsBySoilType(soilType));

      final backendRecommendations =
          _mapBackendRecommendationItems(payload['recommendations']);

      if (backendRecommendations.isNotEmpty) {
        cropRecommendationsPayload = payload;
        recommendations = backendRecommendations;
      } else {
        final fallback = await _loadFallbackCropRecommendations(
          soilType,
          supportFallback: supportFallback,
        );
        recommendations = fallback.recommendations;
        recommendationsErrorMessage = fallback.errorMessage;
        isUsingFallback = fallback.isUsingFallback;
      }
    } on ApiException {
      final fallback = await _loadFallbackCropRecommendations(
        soilType,
        supportFallback: supportFallback,
      );
      recommendations = fallback.recommendations;
      recommendationsErrorMessage = fallback.errorMessage;
      isUsingFallback = fallback.isUsingFallback;
    } catch (_) {
      final fallback = await _loadFallbackCropRecommendations(
        soilType,
        supportFallback: supportFallback,
      );
      recommendations = fallback.recommendations;
      recommendationsErrorMessage = fallback.errorMessage;
      isUsingFallback = fallback.isUsingFallback;
    }

    if (!mounted || !_matchesCurrentPredictedSoil(soilType)) {
      return;
    }

    setState(() {
      _cropRecommendationsPayload = cropRecommendationsPayload;
      _recommendations = recommendations;
      _recommendationsErrorMessage = recommendationsErrorMessage;
      _isCropRecommendationsLoading = false;
      _isUsingCropRecommendationFallback = isUsingFallback;
      _showAllRecommendations = false;
    });
  }

  String? _firstNonEmptyText(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  String _joinAdviceSections(
    Iterable<String?> values, {
    required String fallback,
  }) {
    final sections = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty) {
        continue;
      }

      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        sections.add(normalized);
      }
    }

    if (sections.isEmpty) {
      return fallback;
    }

    return sections.join('\n\n');
  }

  String? _buildProductivityInsight(ProductivityBasis? basis) {
    if (basis == null) {
      return null;
    }

    final insights = <String>[];

    if ((basis.nutrientRetention ?? '').isNotEmpty) {
      insights.add('Nutrient retention: ${basis.nutrientRetention}.');
    }
    if ((basis.drainageCondition ?? '').isNotEmpty) {
      insights.add('Drainage condition: ${basis.drainageCondition}.');
    }
    if ((basis.compactionRisk ?? '').isNotEmpty) {
      insights.add('Compaction risk: ${basis.compactionRisk}.');
    }
    if ((basis.waterHoldingCapacity ?? '').isNotEmpty) {
      insights.add('Water-holding capacity: ${basis.waterHoldingCapacity}.');
    }

    if (insights.isEmpty) {
      return null;
    }

    return insights.join(' ');
  }

  String _buildManagementAdvice(
    SoilAnalysisSupportResponse? support,
    _SoilDecisionSupport? fallback,
  ) {
    final firstGuidance = _firstNonEmptyText(
      (support?.fertilizerRecommendations ?? const <FertilizerRecommendation>[])
          .map((item) => item.guidanceText),
    );

    return _joinAdviceSections(
      [
        support?.productivityBasis?.basisExplanation,
        _buildProductivityInsight(support?.productivityBasis),
        firstGuidance,
      ],
      fallback: fallback?.managementAdvice ??
          'Field guidance is not available right now.',
    );
  }

  String _fertilizerRecommendationTitle(
    FertilizerRecommendation recommendation,
  ) {
    final label = recommendation.displayLabel?.trim() ?? '';
    if (label.isNotEmpty) {
      return label;
    }

    return _firstNonEmptyText([
          recommendation.fertilizer.displayName,
          recommendation.fertilizer.commonName,
          recommendation.fertilizer.fertilizerCode,
        ]) ??
        'Suggested fertilizer';
  }

  String _buildFertilizerRecommendationBody(
    FertilizerRecommendation recommendation,
  ) {
    final title = _fertilizerRecommendationTitle(recommendation);
    final fertilizerName = _firstNonEmptyText([
      recommendation.fertilizer.displayName,
      recommendation.fertilizer.commonName,
      recommendation.fertilizer.fertilizerCode,
    ]);

    return _joinAdviceSections(
      [
        if (fertilizerName != null && fertilizerName != title) fertilizerName,
        recommendation.guidanceText,
        recommendation.applicationRateText == null
            ? null
            : 'Rate: ${recommendation.applicationRateText}',
        recommendation.applicationTimingText == null
            ? null
            : 'Timing: ${recommendation.applicationTimingText}',
        recommendation.reasonBasis == null
            ? null
            : 'Why: ${recommendation.reasonBasis}',
      ],
      fallback: 'No fertilizer guidance is currently available.',
    );
  }

  Widget _buildSoftFallbackNote(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  _SoilDecisionSupport? _decisionSupportForPrediction(String? soilType) {
    final normalized = soilType?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return null;
    }

    switch (normalized) {
      case 'clay':
        return const _SoilDecisionSupport(
          productivityLevel: 'Moderate',
          productivityExplanation:
              'Clay can retain nutrients well, but drainage and compaction can reduce field performance if unmanaged.',
          fertilizerRecommendation:
              'Use balanced fertilizer in split applications and add organic matter to improve structure.',
          managementAdvice:
              'Avoid tillage when the soil is too wet, maintain drainage, and use residue cover to reduce crusting.',
        );
      case 'clay loam':
        return const _SoilDecisionSupport(
          productivityLevel: 'Moderate',
          productivityExplanation:
              'Clay loam provides better balance than heavy clay, but some drainage and compaction sensitivity can still limit field performance.',
          fertilizerRecommendation:
              'Apply a balanced NPK program and maintain soil organic matter to support structure and nutrient availability.',
          managementAdvice:
              'Preserve organic matter, avoid repeated compaction, and monitor moisture before field operations.',
        );
      case 'loam':
        return const _SoilDecisionSupport(
          productivityLevel: 'High',
          productivityExplanation:
              'Loam generally offers favorable drainage, aeration, and nutrient-holding capacity for many crops.',
          fertilizerRecommendation:
              'Use moderate balanced fertilizer and replenish nutrients after harvest with organic inputs when available.',
          managementAdvice:
              'Maintain mulch or crop residue, monitor moisture regularly, and rotate crops to sustain soil condition.',
        );
      case 'rock land':
        return const _SoilDecisionSupport(
          productivityLevel: 'Low',
          productivityExplanation:
              'Rock land usually has limited rooting depth and moisture storage, which can restrict overall productivity.',
          fertilizerRecommendation:
              'Use localized fertilizer placement near the root zone and focus on organic amendments where practical.',
          managementAdvice:
              'Choose tolerant crops, reduce erosion risk, and conserve water with mulch or ground cover.',
        );
      case 'silty clay':
        return const _SoilDecisionSupport(
          productivityLevel: 'Moderate',
          productivityExplanation:
              'Silty clay can be productive, but it may become dense and poorly drained under prolonged wet conditions.',
          fertilizerRecommendation:
              'Apply balanced nutrients carefully and include organic matter to improve aggregation and root development.',
          managementAdvice:
              'Manage drainage, minimize traffic on wet soil, and maintain surface cover to reduce sealing and runoff.',
        );
      default:
        return const _SoilDecisionSupport(
          productivityLevel: 'Moderate',
          productivityExplanation:
              'This soil type has moderate agricultural potential based on the current image classification result.',
          fertilizerRecommendation:
              'Use a balanced fertilizer program and adjust rates based on crop demand and field observation.',
          managementAdvice:
              'Maintain organic matter, monitor moisture, and avoid unnecessary soil disturbance during wet conditions.',
        );
    }
  }

  Color _productivityColor(BuildContext context, String level) {
    switch (level.toLowerCase()) {
      case 'high':
        return Colors.green.shade700;
      case 'moderate':
      case 'medium':
        return Colors.orange.shade700;
      case 'low':
        return Colors.red.shade700;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _buildSummaryPanel(
    BuildContext context, {
    required String soilType,
    required String confidenceLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colorScheme.surface.withOpacity(0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Final prediction',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            soilType,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Main soil type identified from the uploaded image.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$confidenceLabel confidence',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceText(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(body),
      ],
    );
  }

  Widget _buildTechnicalDetailItem(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayValue = _displayValue(value);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: displayValue,
            child: Text(
              _truncateMiddle(displayValue),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisStatusCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentStep = _analysisStageOrder(_analysisStage).clamp(1, 3);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.12),
              ),
            ),
            child: Text(
              'Step $currentStep of 3',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _analysisStageLabel(_analysisStage),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _analysisStageDescription(_analysisStage),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _buildProgressStepRow(
            context,
            label: 'Upload soil image',
            step: 1,
          ),
          const SizedBox(height: 10),
          _buildProgressStepRow(
            context,
            label: 'Classify soil type',
            step: 2,
          ),
          const SizedBox(height: 10),
          _buildProgressStepRow(
            context,
            label: 'Prepare crop advice',
            step: 3,
          ),
          if (_showLongWaitMessage) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.12),
                ),
              ),
              child: Text(
                'This is taking a little longer than usual. Please keep this screen open while we finish your soil analysis.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressStepRow(
    BuildContext context, {
    required String label,
    required int step,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentStep = _analysisStageOrder(_analysisStage);
    final isComplete = currentStep > step;
    final isCurrent = currentStep == step;

    return Row(
      children: [
        Icon(
          isComplete
              ? Icons.check_circle
              : isCurrent
                  ? Icons.timelapse
                  : Icons.radio_button_unchecked,
          size: 18,
          color: isComplete || isCurrent
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isComplete || isCurrent
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton(BuildContext context) {
    final label = _analysisButtonLabel();
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: colorScheme.primary.withOpacity(0.88),
          disabledForegroundColor: colorScheme.onPrimary,
        ),
        onPressed: _isBusy ? null : _analyzeImage,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isBusy) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ] else ...[
                const Icon(Icons.analytics_outlined, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingAdviceContent(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.38),
        borderRadius: BorderRadius.circular(14),
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
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropRecommendationLoadingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading crop recommendations for the final soil type...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _predictionResponse;
    final support = _soilAnalysisSupport;
    final productivityBasis = support?.productivityBasis;
    final fertilizerRecommendations = support?.fertilizerRecommendations ??
        const <FertilizerRecommendation>[];

    final finalSoilType = prediction?.prediction?.trim() ?? '';
    final hasFinalSoilType = finalSoilType.isNotEmpty;

    final confidenceLabel = _formatPercent(
      prediction?.confidence,
      fractionDigits: 1,
    );

    final decisionSupport = _decisionSupportForPrediction(
      prediction?.prediction,
    );

    final productivityLevel = productivityBasis?.productivityLevel ??
        decisionSupport?.productivityLevel;

    final productivityExplanation = productivityBasis?.basisExplanation ??
        decisionSupport?.productivityExplanation;

    final managementAdvice = _buildManagementAdvice(
      support,
      decisionSupport,
    );

    final showSupportFallbackNotice =
        _supportErrorMessage != null && support == null;

    final hasBackendCropRecommendations = _cropRecommendationsPayload != null;

    final hasHiddenRecommendations =
        _recommendations.length > _initialVisibleRecommendationCount;

    final visibleRecommendations = _showAllRecommendations ||
            !hasHiddenRecommendations
        ? _recommendations
        : _recommendations.take(_initialVisibleRecommendationCount).toList();

    final remainingRecommendationCount =
        _recommendations.length - visibleRecommendations.length;

    final isPreparingAdvice =
        _isBusy && _analysisStage == _AnalysisStage.preparingAdvice;

    final isCropRecommendationsLoading =
        !isPreparingAdvice && _isCropRecommendationsLoading;

    final cropRecommendationDescription = hasBackendCropRecommendations ||
            !_isUsingCropRecommendationFallback
        ? 'These crop suggestions are matched to the final soil type.'
        : 'These crop suggestions are matched to the final soil type using the available recommendation data.';

    return Scaffold(
      appBar: AppBar(title: const Text('Soil Image Analysis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'Select a Soil Photo',
                icon: Icons.photo_camera_back_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedImage != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImage!,
                          height: 220,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('No soil photo selected yet.'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Select or capture a clear soil photo, then review the final soil type and field guidance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      label: 'Choose from Gallery',
                      icon: Icons.photo_library_outlined,
                      onPressed: _isBusy
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      label: 'Capture with Camera',
                      icon: Icons.camera_alt_outlined,
                      onPressed:
                          _isBusy ? null : () => _pickImage(ImageSource.camera),
                    ),
                    const SizedBox(height: 12),
                    _buildAnalyzeButton(context),
                    if (_isBusy) _buildAnalysisStatusCard(context),
                  ],
                ),
              ),
              if (prediction != null)
                InfoCard(
                  title: 'Predicted Soil Type',
                  icon: Icons.science_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryPanel(
                        context,
                        soilType: hasFinalSoilType
                            ? finalSoilType
                            : 'No classified soil type available',
                        confidenceLabel: confidenceLabel,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The guidance below is based on this final soil type only.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              if (prediction != null)
                InfoCard(
                  title: 'Recommended Crops',
                  icon: Icons.eco_outlined,
                  child: isPreparingAdvice
                      ? _buildPendingAdviceContent(
                          context,
                          title: 'Preparing crop advice...',
                          body:
                              'Recommended crops will appear here as soon as we finish matching them to the soil type.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cropRecommendationDescription,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            if (isCropRecommendationsLoading)
                              _buildCropRecommendationLoadingState(context)
                            else if (_recommendationsErrorMessage != null)
                              Text(
                                _recommendationsErrorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              )
                            else if (_recommendations.isEmpty)
                              const Text(
                                'No crop recommendations are currently available for this soil type.',
                              )
                            else ...[
                              if (hasHiddenRecommendations)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withOpacity(0.1),
                                    ),
                                  ),
                                  child: Text(
                                    _showAllRecommendations
                                        ? 'Showing all ${_recommendations.length} crop recommendations.'
                                        : 'Showing the top ${visibleRecommendations.length} crop recommendations first for easier mobile scanning.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ...visibleRecommendations.map(
                                (item) => RecommendationCard(
                                  recommendation: item,
                                ),
                              ),
                              if (hasHiddenRecommendations ||
                                  _showAllRecommendations)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _showAllRecommendations =
                                            !_showAllRecommendations;
                                      });
                                    },
                                    icon: Icon(
                                      _showAllRecommendations
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                    label: Text(
                                      _showAllRecommendations
                                          ? 'Show Fewer Crops'
                                          : 'View More Crops ($remainingRecommendationCount)',
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                ),
              if (prediction != null &&
                  ((productivityLevel?.isNotEmpty ?? false) ||
                      isPreparingAdvice))
                InfoCard(
                  title: 'Estimated Soil Productivity',
                  icon: Icons.bar_chart_outlined,
                  child: isPreparingAdvice
                      ? _buildPendingAdviceContent(
                          context,
                          title: 'Estimating soil productivity...',
                          body:
                              'A simple summary of expected field productivity will appear here shortly.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showSupportFallbackNotice)
                              _buildSoftFallbackNote(
                                context,
                                _supportErrorMessage!,
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _productivityColor(
                                  context,
                                  productivityLevel ?? 'N/A',
                                ).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _productivityColor(
                                    context,
                                    productivityLevel ?? 'N/A',
                                  ).withOpacity(0.18),
                                ),
                              ),
                              child: Text(
                                productivityLevel ?? 'N/A',
                                style: TextStyle(
                                  color: _productivityColor(
                                    context,
                                    productivityLevel ?? 'N/A',
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _displayValue(
                                productivityExplanation,
                                fallback:
                                    'Productivity details are not available right now.',
                              ),
                            ),
                          ],
                        ),
                ),
              if (prediction != null &&
                  ((support != null || decisionSupport != null) ||
                      isPreparingAdvice))
                InfoCard(
                  title: 'Fertilizer Recommendation',
                  icon: Icons.agriculture_outlined,
                  child: isPreparingAdvice
                      ? _buildPendingAdviceContent(
                          context,
                          title: 'Preparing fertilizer advice...',
                          body:
                              'A practical fertilizer suggestion will appear here after the soil check finishes.',
                        )
                      : support != null
                          ? fertilizerRecommendations.isEmpty
                              ? _buildGuidanceText(
                                  context,
                                  title: 'Suggested approach',
                                  body:
                                      'No fertilizer recommendations are currently available for this soil type and productivity level.',
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var index = 0;
                                        index <
                                            fertilizerRecommendations.length;
                                        index++) ...[
                                      _buildGuidanceText(
                                        context,
                                        title: _fertilizerRecommendationTitle(
                                          fertilizerRecommendations[index],
                                        ),
                                        body:
                                            _buildFertilizerRecommendationBody(
                                          fertilizerRecommendations[index],
                                        ),
                                      ),
                                      if (index <
                                          fertilizerRecommendations.length - 1)
                                        const SizedBox(height: 16),
                                    ],
                                  ],
                                )
                          : _buildGuidanceText(
                              context,
                              title: 'Suggested approach',
                              body: decisionSupport?.fertilizerRecommendation ??
                                  'No fertilizer recommendations are currently available for this soil type.',
                            ),
                ),
              if (prediction != null &&
                  ((support != null || decisionSupport != null) ||
                      isPreparingAdvice))
                InfoCard(
                  title: 'Soil Management Advice',
                  icon: Icons.tips_and_updates_outlined,
                  child: isPreparingAdvice
                      ? _buildPendingAdviceContent(
                          context,
                          title: 'Preparing soil management advice...',
                          body:
                              'Field guidance for watering, tillage, and care will appear here shortly.',
                        )
                      : _buildGuidanceText(
                          context,
                          title: 'Field guidance',
                          body: managementAdvice,
                        ),
                ),
              if (prediction != null)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      leading: Icon(
                        Icons.tune_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Technical Details (Optional)'),
                      subtitle: const Text(
                        'Tap to view upload and prediction details',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      children: [
                        if (_uploadResponse != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Upload Details',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTechnicalDetailItem(
                            context,
                            label: 'Saved file name',
                            value: _uploadResponse!.fileName,
                          ),
                          _buildTechnicalDetailItem(
                            context,
                            label: 'Original upload',
                            value: _uploadResponse!.originalFileName,
                          ),
                          const SizedBox(height: 4),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Top Predictions',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (prediction.topPredictions.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No technical prediction breakdown is available.',
                            ),
                          )
                        else
                          ...prediction.topPredictions.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.soilType,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _formatPercent(
                                          entry.confidence,
                                          fractionDigits: 1,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: entry.confidence,
                                      minHeight: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoilDecisionSupport {
  const _SoilDecisionSupport({
    required this.productivityLevel,
    required this.productivityExplanation,
    required this.fertilizerRecommendation,
    required this.managementAdvice,
  });

  final String productivityLevel;
  final String productivityExplanation;
  final String fertilizerRecommendation;
  final String managementAdvice;
}

class _CropRecommendationResult {
  const _CropRecommendationResult({
    required this.recommendations,
    required this.isUsingFallback,
    this.errorMessage,
  });

  final List<RecommendationItem> recommendations;
  final bool isUsingFallback;
  final String? errorMessage;
}

enum _AnalysisStage {
  idle,
  uploading,
  classifying,
  preparingAdvice,
  completed,
}
