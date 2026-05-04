class LeaseModel {
  const LeaseModel({
    required this.id,
    this.leaseTitle,
    required this.ownerName,
    required this.contactNumber,
    required this.barangay,
    required this.soilType,
    required this.areaHectares,
    this.areaSqm,
    required this.price,
    this.pricePerSqm,
    this.totalLeasePrice,
    required this.description,
    this.rentalStartDate,
    this.rentalEndDate,
    this.durationValue,
    this.durationUnit,
    this.durationMonths,
    this.locationDescription,
    this.contractStatus,
    this.status,
    this.createdAt,
  });

  final int id;
  final String? leaseTitle;
  final String ownerName;
  final String contactNumber;
  final String barangay;
  final String soilType;
  final double areaHectares;
  final double? areaSqm;
  final double price;
  final double? pricePerSqm;
  final double? totalLeasePrice;
  final String description;
  final DateTime? rentalStartDate;
  final DateTime? rentalEndDate;
  final double? durationValue;
  final String? durationUnit;
  final double? durationMonths;
  final String? locationDescription;
  final String? contractStatus;
  final String? status;
  final DateTime? createdAt;

  factory LeaseModel.fromJson(Map<String, dynamic> json) {
    return LeaseModel(
      id: _parseInt(json['id']) ?? 0,
      leaseTitle: _parseString(json['lease_title']),
      ownerName: _parseString(json['owner_name']) ?? '',
      contactNumber: _parseString(json['contact_number']) ?? '',
      barangay: _parseString(json['barangay']) ?? '',
      soilType: _parseString(json['soil_type']) ?? '',
      areaHectares: _parseDouble(json['area_hectares']) ?? 0,
      areaSqm: _parseDouble(json['area_sqm']),
      price: _parseDouble(json['price']) ??
          _parseDouble(json['total_lease_price']) ??
          0,
      pricePerSqm: _parseDouble(json['price_per_sqm']),
      totalLeasePrice: _parseDouble(json['total_lease_price']),
      description: _parseString(json['description']) ?? '',
      rentalStartDate: _parseDateTime(json['rental_start_date']),
      rentalEndDate: _parseDateTime(json['rental_end_date']),
      durationValue: _parseDouble(json['duration_value']),
      durationUnit: _parseString(json['duration_unit']),
      durationMonths: _parseDouble(json['duration_months']),
      locationDescription: _parseString(json['location_description']),
      contractStatus: _parseString(json['contract_status']),
      status: _parseString(json['status']),
      createdAt: _parseDateTime(json['created_at']),
    );
  }
}

String? _parseString(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String && value.trim().isNotEmpty) {
    return double.tryParse(value.trim());
  }

  return null;
}

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String && value.trim().isNotEmpty) {
    return int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.toInt();
  }

  return null;
}

DateTime? _parseDateTime(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }

  return null;
}
