import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representasi data Greenhouse pada Firebase Firestore
/// Sesuai struktur dokumen Firestore:
/// - name: String (Nama greenhouse)
/// - area: number (Ukuran luas kuadrat dalam m²)
/// - location: Map { latitude: number, longitude: number }
/// - created_at: Timestamp (Waktu dibuat)
class GreenhouseModel {
  final String? id;
  final String name;
  final double area;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;

  // Konfigurasi Tanaman & Tanah (Agronomi Greenhouse)
  final String? plantType; // Jenis Tanaman (e.g., Tomat, Cabai, Melon)
  final String? plantVariety; // Varietas (e.g., Tomat Cherry, Rawit Merah)
  final String? soilType; // Jenis Tanah / Media (e.g., Tanah Humus, Cocopeat)
  final DateTime? plantingDate; // Tanggal Mulai Tanam

  // Koneksi Perangkat IoT Hardware (ESP32/NodeMCU)
  final String? iotDeviceId; // Device ID (e.g., "GH_01", "greenhouse")

  GreenhouseModel({
    this.id,
    required this.name,
    required this.area,
    required this.latitude,
    required this.longitude,
    this.createdAt,
    this.plantType,
    this.plantVariety,
    this.soilType,
    this.plantingDate,
    this.iotDeviceId,
  });

  /// Mengecek apakah greenhouse sudah disetting tanamannya
  bool get isConfigured =>
      plantType != null &&
      plantType!.trim().isNotEmpty &&
      plantVariety != null &&
      plantVariety!.trim().isNotEmpty;

  /// Mengecek apakah greenhouse sudah terhubung ke node IoT hardware
  bool get hasIotDevice =>
      iotDeviceId != null && iotDeviceId!.trim().isNotEmpty;

  /// Mengonversi model menjadi format Map untuk disimpan ke Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'area': area,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'plant_type': plantType ?? '',
      'plant_variety': plantVariety ?? '',
      'soil_type': soilType ?? '',
      'iot_device_id': iotDeviceId ?? '',
      if (plantingDate != null)
        'planting_date': Timestamp.fromDate(plantingDate!),
    };
  }

  /// Membuat instance GreenhouseModel dari DocumentSnapshot Firestore
  factory GreenhouseModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot, [
    SnapshotOptions? options,
  ]) {
    final data = snapshot.data();
    final loc = data?['location'] as Map<String, dynamic>?;
    final createdAtRaw = data?['created_at'];
    final plantingDateRaw = data?['planting_date'];

    DateTime? parsedCreatedAt;
    if (createdAtRaw is Timestamp) {
      parsedCreatedAt = createdAtRaw.toDate();
    } else if (createdAtRaw is String) {
      parsedCreatedAt = DateTime.tryParse(createdAtRaw);
    }

    DateTime? parsedPlantingDate;
    if (plantingDateRaw is Timestamp) {
      parsedPlantingDate = plantingDateRaw.toDate();
    } else if (plantingDateRaw is String) {
      parsedPlantingDate = DateTime.tryParse(plantingDateRaw);
    }

    return GreenhouseModel(
      id: snapshot.id,
      name: data?['name'] ?? '',
      area: parseDouble(data?['area']),
      latitude: parseDouble(loc?['latitude']),
      longitude: parseDouble(loc?['longitude']),
      createdAt: parsedCreatedAt,
      plantType: data?['plant_type'],
      plantVariety: data?['plant_variety'],
      soilType: data?['soil_type'],
      plantingDate: parsedPlantingDate,
      iotDeviceId: data?['iot_device_id'],
    );
  }

  /// Helper untuk parsing angka aman (bisa num atau string dari REST integerValue)
  static double parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  /// Membuat instance GreenhouseModel dari Map umum
  factory GreenhouseModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    final loc = map['location'] as Map<String, dynamic>?;
    final createdAtRaw = map['created_at'];
    final plantingDateRaw = map['planting_date'];

    DateTime? parsedCreatedAt;
    if (createdAtRaw is Timestamp) {
      parsedCreatedAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      parsedCreatedAt = createdAtRaw;
    } else if (createdAtRaw is String) {
      parsedCreatedAt = DateTime.tryParse(createdAtRaw);
    }

    DateTime? parsedPlantingDate;
    if (plantingDateRaw is Timestamp) {
      parsedPlantingDate = plantingDateRaw.toDate();
    } else if (plantingDateRaw is DateTime) {
      parsedPlantingDate = plantingDateRaw;
    } else if (plantingDateRaw is String) {
      parsedPlantingDate = DateTime.tryParse(plantingDateRaw);
    }

    return GreenhouseModel(
      id: docId ?? map['id'],
      name: map['name'] ?? '',
      area: parseDouble(map['area']),
      latitude: parseDouble(loc?['latitude'] ?? map['latitude']),
      longitude: parseDouble(loc?['longitude'] ?? map['longitude']),
      createdAt: parsedCreatedAt,
      plantType: map['plant_type'] ?? map['plantType'],
      plantVariety: map['plant_variety'] ?? map['plantVariety'],
      soilType: map['soil_type'] ?? map['soilType'],
      plantingDate: parsedPlantingDate,
      iotDeviceId: map['iot_device_id'] ?? map['iotDeviceId'],
    );
  }

  GreenhouseModel copyWith({
    String? id,
    String? name,
    double? area,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    String? plantType,
    String? plantVariety,
    String? soilType,
    DateTime? plantingDate,
    String? iotDeviceId,
    bool clearPlantConfig = false,
    bool clearIotDevice = false,
  }) {
    return GreenhouseModel(
      id: id ?? this.id,
      name: name ?? this.name,
      area: area ?? this.area,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      plantType: clearPlantConfig ? null : (plantType ?? this.plantType),
      plantVariety: clearPlantConfig ? null : (plantVariety ?? this.plantVariety),
      soilType: clearPlantConfig ? null : (soilType ?? this.soilType),
      plantingDate: clearPlantConfig ? null : (plantingDate ?? this.plantingDate),
      iotDeviceId: clearIotDevice ? null : (iotDeviceId ?? this.iotDeviceId),
    );
  }
}
