class LocationInfo {
  const LocationInfo({
    required this.lat,
    required this.lng,
    this.barangay,
  });

  final double lat;
  final double lng;
  final String? barangay;

  factory LocationInfo.fromJson(dynamic json) {
    final normalizedJson = _asMap(json);
    return LocationInfo(
      lat: _asDouble(normalizedJson['lat']) ?? 0,
      lng: _asDouble(normalizedJson['lng']) ?? 0,
      barangay: _asNullableString(normalizedJson['barangay']),
    );
  }
}

class SoilInfo {
  const SoilInfo({
    required this.soilType,
    required this.soilName,
  });

  final String soilType;
  final String soilName;

  factory SoilInfo.fromJson(dynamic json) {
    final normalizedJson = _asMap(json);
    return SoilInfo(
      soilType: _asString(normalizedJson['soil_type']),
      soilName: _asString(normalizedJson['soil_name']),
    );
  }
}

class ClimateInfo {
  const ClimateInfo({
    this.temperature,
    this.humidity,
    this.precipitation,
    this.rain,
    this.weatherCode,
    this.windSpeed,
    this.time,
  });

  final double? temperature;
  final double? humidity;
  final double? precipitation;
  final double? rain;
  final int? weatherCode;
  final double? windSpeed;
  final String? time;

  factory ClimateInfo.fromJson(dynamic json) {
    final normalizedJson = _asMap(json);
    return ClimateInfo(
      temperature: _asDouble(normalizedJson['temperature']),
      humidity: _asDouble(normalizedJson['humidity']),
      precipitation: _asDouble(normalizedJson['precipitation']),
      rain: _asDouble(normalizedJson['rain']),
      weatherCode: _asInt(normalizedJson['weather_code']),
      windSpeed: _asDouble(normalizedJson['wind_speed']),
      time: _asNullableString(normalizedJson['time']),
    );
  }
}

class RecommendationItem {
  const RecommendationItem({
    required this.cropName,
    required this.suitability,
    this.notes,
  });

  final String cropName;
  final String suitability;
  final String? notes;

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      cropName: _asString(json['crop_name']),
      suitability: _asString(json['suitability']),
      notes: _asNullableString(json['notes']),
    );
  }
}

class DashboardModel {
  const DashboardModel({
    required this.location,
    required this.soil,
    required this.climate,
    required this.advisory,
    required this.recommendations,
  });

  final LocationInfo location;
  final SoilInfo soil;
  final ClimateInfo climate;
  final List<String> advisory;
  final List<RecommendationItem> recommendations;

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      location: LocationInfo.fromJson(_asMap(json['location'])),
      soil: SoilInfo.fromJson(_asMap(json['soil'])),
      climate: ClimateInfo.fromJson(_asMap(json['climate'])),
      advisory: _asList(json['advisory'])
          .map(_asNullableString)
          .whereType<String>()
          .toList(),
      recommendations: _asList(json['recommendations'])
          .map(_asMap)
          .map(RecommendationItem.fromJson)
          .where(_hasRecommendationContent)
          .toList(),
    );
  }
}

class ClimateCurrentModel {
  const ClimateCurrentModel({
    required this.location,
    required this.climate,
  });

  final LocationInfo location;
  final ClimateInfo climate;

  factory ClimateCurrentModel.fromJson(Map<String, dynamic> json) {
    return ClimateCurrentModel(
      location: LocationInfo.fromJson(_asMap(json['location'])),
      climate: ClimateInfo.fromJson(_asMap(json['climate'])),
    );
  }
}

class GeoJsonFeatureCollection {
  const GeoJsonFeatureCollection({
    required this.type,
    required this.features,
  });

  final String type;
  final List<Map<String, dynamic>> features;

  factory GeoJsonFeatureCollection.fromJson(Map<String, dynamic> json) {
    return GeoJsonFeatureCollection(
      type: _asString(json['type'], fallback: 'FeatureCollection'),
      features: _asList(json['features'])
          .map(_asMap)
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }
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

bool _hasRecommendationContent(RecommendationItem item) {
  return item.cropName.isNotEmpty ||
      item.suitability.isNotEmpty ||
      (item.notes?.isNotEmpty ?? false);
}
