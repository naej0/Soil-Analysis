class AiUploadResponse {
  const AiUploadResponse({
    required this.message,
    required this.fileName,
    required this.originalFileName,
    required this.contentType,
    required this.sizeBytes,
  });

  final String message;
  final String fileName;
  final String originalFileName;
  final String contentType;
  final int sizeBytes;

  factory AiUploadResponse.fromJson(Map<String, dynamic> json) {
    return AiUploadResponse(
      message: _asString(json['message']),
      fileName: _asString(json['file_name']),
      originalFileName: _asString(json['original_file_name']),
      contentType: _asString(json['content_type']),
      sizeBytes: _asInt(json['size_bytes']) ?? 0,
    );
  }
}

class TopPrediction {
  const TopPrediction({
    required this.soilType,
    required this.confidence,
  });

  final String soilType;
  final double confidence;

  factory TopPrediction.fromJson(Map<String, dynamic> json) {
    return TopPrediction(
      soilType: _asString(json['soil_type']),
      confidence: _asDouble(json['confidence']) ?? 0,
    );
  }
}

class AiPredictionResponse {
  const AiPredictionResponse({
    required this.status,
    required this.fileName,
    required this.supportedSoilTypes,
    required this.message,
    this.prediction,
    this.confidence,
    this.topPredictions = const [],
    this.createdAt,
  });

  final String status;
  final String fileName;
  final String? prediction;
  final double? confidence;
  final List<TopPrediction> topPredictions;
  final List<String> supportedSoilTypes;
  final String message;
  final DateTime? createdAt;

  factory AiPredictionResponse.fromJson(Map<String, dynamic> json) {
    return AiPredictionResponse(
      status: _asString(json['status']),
      fileName: _asString(json['file_name']),
      prediction: _asNullableString(json['prediction']),
      confidence: _asDouble(json['confidence']),
      topPredictions: _asList(json['top_predictions'])
          .map(_asMap)
          .map(TopPrediction.fromJson)
          .where((item) => item.soilType.isNotEmpty)
          .toList(),
      supportedSoilTypes: _asList(json['supported_soil_types'])
          .map(_asNullableString)
          .whereType<String>()
          .toList(),
      message: _asString(json['message']),
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  return const <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? fallback : normalized;
}

String? _asNullableString(dynamic value) {
  final normalized = _asString(value);
  return normalized.isEmpty ? null : normalized;
}

double? _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
