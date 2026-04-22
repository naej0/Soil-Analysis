class ProductivityBasis {
  const ProductivityBasis({
    this.soilTypeId,
    this.soilTypeName,
    this.soilDescription,
    this.productivityLevelId,
    this.productivityLevel,
    this.displayOrder,
    this.nutrientRetention,
    this.drainageCondition,
    this.compactionRisk,
    this.waterHoldingCapacity,
    this.basisExplanation,
  });

  final int? soilTypeId;
  final String? soilTypeName;
  final String? soilDescription;
  final int? productivityLevelId;
  final String? productivityLevel;
  final int? displayOrder;
  final String? nutrientRetention;
  final String? drainageCondition;
  final String? compactionRisk;
  final String? waterHoldingCapacity;
  final String? basisExplanation;

  factory ProductivityBasis.fromJson(Map<String, dynamic> json) {
    return ProductivityBasis(
      soilTypeId: _asInt(json['soil_type_id']),
      soilTypeName: _asNullableString(json['soil_type_name']),
      soilDescription: _asNullableString(json['soil_description']),
      productivityLevelId: _asInt(json['productivity_level_id']),
      productivityLevel: _asNullableString(json['productivity_level']),
      displayOrder: _asInt(json['display_order']),
      nutrientRetention: _asNullableString(json['nutrient_retention']),
      drainageCondition: _asNullableString(json['drainage_condition']),
      compactionRisk: _asNullableString(json['compaction_risk']),
      waterHoldingCapacity: _asNullableString(json['water_holding_capacity']),
      basisExplanation: _asNullableString(json['basis_explanation']),
    );
  }
}

class RecommendedCrop {
  const RecommendedCrop({
    required this.cropName,
    required this.suitability,
    this.notes,
  });

  final String cropName;
  final String suitability;
  final String? notes;

  factory RecommendedCrop.fromJson(Map<String, dynamic> json) {
    return RecommendedCrop(
      cropName: _asString(json['crop_name']),
      suitability: _asString(json['suitability']),
      notes: _asNullableString(json['notes']),
    );
  }
}

class FertilizerItem {
  const FertilizerItem({
    this.id,
    this.fertilizerCode,
    this.commonName,
    this.displayName,
    this.aliases,
    this.nValue,
    this.pValue,
    this.kValue,
    this.category,
    this.note,
  });

  final int? id;
  final String? fertilizerCode;
  final String? commonName;
  final String? displayName;
  final String? aliases;
  final double? nValue;
  final double? pValue;
  final double? kValue;
  final String? category;
  final String? note;

  factory FertilizerItem.fromJson(Map<String, dynamic> json) {
    return FertilizerItem(
      id: _asInt(json['id']),
      fertilizerCode: _asNullableString(json['fertilizer_code']),
      commonName: _asNullableString(json['common_name']),
      displayName: _asNullableString(json['display_name']),
      aliases: _asNullableString(json['aliases']),
      nValue: _asDouble(json['n_value']),
      pValue: _asDouble(json['p_value']),
      kValue: _asDouble(json['k_value']),
      category: _asNullableString(json['category']),
      note: _asNullableString(json['note']),
    );
  }
}

class FertilizerRecommendation {
  const FertilizerRecommendation({
    this.id,
    this.soilTypeName,
    this.productivityLevel,
    this.cropName,
    this.priorityOrder,
    this.recommendationRole,
    this.displayLabel,
    this.guidanceText,
    this.applicationRateText,
    this.applicationTimingText,
    this.reasonBasis,
    this.sourceTitle,
    this.sourceOrganization,
    this.sourceYear,
    this.sourceLink,
    required this.fertilizer,
  });

  final int? id;
  final String? soilTypeName;
  final String? productivityLevel;
  final String? cropName;
  final int? priorityOrder;
  final String? recommendationRole;
  final String? displayLabel;
  final String? guidanceText;
  final String? applicationRateText;
  final String? applicationTimingText;
  final String? reasonBasis;
  final String? sourceTitle;
  final String? sourceOrganization;
  final int? sourceYear;
  final String? sourceLink;
  final FertilizerItem fertilizer;

  factory FertilizerRecommendation.fromJson(Map<String, dynamic> json) {
    return FertilizerRecommendation(
      id: _asInt(json['id']),
      soilTypeName: _asNullableString(json['soil_type_name']),
      productivityLevel: _asNullableString(json['productivity_level']),
      cropName: _asNullableString(json['crop_name']),
      priorityOrder: _asInt(json['priority_order']),
      recommendationRole: _asNullableString(json['recommendation_role']),
      displayLabel: _asNullableString(json['display_label']),
      guidanceText: _asNullableString(json['guidance_text']),
      applicationRateText: _asNullableString(json['application_rate_text']),
      applicationTimingText: _asNullableString(json['application_timing_text']),
      reasonBasis: _asNullableString(json['reason_basis']),
      sourceTitle: _asNullableString(json['source_title']),
      sourceOrganization: _asNullableString(json['source_organization']),
      sourceYear: _asInt(json['source_year']),
      sourceLink: _asNullableString(json['source_link']),
      fertilizer: FertilizerItem.fromJson(_asMap(json['fertilizer'])),
    );
  }
}

class SoilAnalysisSupportResponse {
  const SoilAnalysisSupportResponse({
    required this.soilType,
    required this.soilDescription,
    this.productivityBasis,
    this.recommendedCrops = const [],
    this.fertilizerRecommendations = const [],
    this.fertilizerCatalog = const [],
    this.cropNameFilter,
    this.productivityLevelFilter,
  });

  final String soilType;
  final String soilDescription;
  final ProductivityBasis? productivityBasis;
  final List<RecommendedCrop> recommendedCrops;
  final List<FertilizerRecommendation> fertilizerRecommendations;
  final List<FertilizerItem> fertilizerCatalog;
  final String? cropNameFilter;
  final String? productivityLevelFilter;

  factory SoilAnalysisSupportResponse.fromJson(Map<String, dynamic> json) {
    final filters = _asMap(json['filters']);
    final productivityBasisJson = _asMap(json['productivity_basis']);

    return SoilAnalysisSupportResponse(
      soilType: _asString(json['soil_type']),
      soilDescription: _asString(json['soil_description']),
      productivityBasis: productivityBasisJson.isEmpty
          ? null
          : ProductivityBasis.fromJson(productivityBasisJson),
      recommendedCrops: _asList(json['recommended_crops'])
          .map(_asMap)
          .map(RecommendedCrop.fromJson)
          .where((item) => item.cropName.isNotEmpty)
          .toList(),
      fertilizerRecommendations: _asList(json['fertilizer_recommendations'])
          .map(_asMap)
          .map(FertilizerRecommendation.fromJson)
          .toList(),
      fertilizerCatalog: _asList(json['fertilizer_catalog'])
          .map(_asMap)
          .map(FertilizerItem.fromJson)
          .toList(),
      cropNameFilter: _asNullableString(filters['crop_name']),
      productivityLevelFilter:
          _asNullableString(filters['productivity_level']),
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
