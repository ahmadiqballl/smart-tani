import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/greenhouse_model.dart';

/// Service untuk menangani operasi CRUD ke Firebase Firestore pada collection 'greenhouses'
/// Mendukung Firebase Native SDK sekaligus Firestore REST API fallback (berguna di Linux desktop
/// atau saat file konfigurasi native belum dipasang).
class GreenhouseService {
  static const String projectId = 'smart-greenhouse-ad587';
  static const String restBaseUrl =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/greenhouses';

  final FirebaseFirestore? _customFirestore;

  GreenhouseService({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  bool get _isFirebaseReady => Firebase.apps.isNotEmpty;

  FirebaseFirestore? get _firestore =>
      _customFirestore ?? (_isFirebaseReady ? FirebaseFirestore.instance : null);

  /// Menambahkan greenhouse baru ke Firestore
  Future<String> addGreenhouse(GreenhouseModel greenhouse) async {
    // 1. Coba menggunakan Firebase SDK jika aplikasi Firebase sudah terinisialisasi
    if (_isFirebaseReady && _firestore != null) {
      try {
        final docRef = await _firestore!
            .collection('greenhouses')
            .add(greenhouse.toFirestore());
        debugPrint('[GreenhouseService] Sukses via SDK Firestore: ${docRef.id}');
        return docRef.id;
      } catch (e) {
        debugPrint('[GreenhouseService] SDK Firestore error, fallback ke REST: $e');
      }
    }

    // 2. Fallback via Firestore REST API (langsung tembus ke database Firestore publik)
    return await _addViaRest(greenhouse);
  }

  Future<String> _addViaRest(GreenhouseModel greenhouse) async {
    final Map<String, dynamic> fields = {
      'name': {'stringValue': greenhouse.name},
      'area': {'doubleValue': greenhouse.area},
      'location': {
        'mapValue': {
          'fields': {
            'latitude': {'doubleValue': greenhouse.latitude},
            'longitude': {'doubleValue': greenhouse.longitude},
          }
        }
      },
      'created_at': {
        'timestampValue': (greenhouse.createdAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
      'plant_type': {'stringValue': greenhouse.plantType ?? ''},
      'plant_variety': {'stringValue': greenhouse.plantVariety ?? ''},
      'soil_type': {'stringValue': greenhouse.soilType ?? ''},
    };

    if (greenhouse.plantingDate != null) {
      fields['planting_date'] = {
        'timestampValue': greenhouse.plantingDate!.toUtc().toIso8601String(),
      };
    }

    final body = json.encode({'fields': fields});

    final response = await http.post(
      Uri.parse(restBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final String fullPath = data['name'] ?? '';
      final docId = fullPath.split('/').last;
      debugPrint('[GreenhouseService] Sukses via REST API: $docId');
      return docId;
    } else {
      throw Exception(
        'Gagal menyimpan ke Firestore (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Mengambil daftar greenhouse dari Firestore
  Future<List<GreenhouseModel>> fetchGreenhouses() async {
    if (_isFirebaseReady && _firestore != null) {
      try {
        final snapshot = await _firestore!
            .collection('greenhouses')
            .orderBy('created_at', descending: true)
            .get();
        return snapshot.docs
            .map((doc) => GreenhouseModel.fromFirestore(doc))
            .toList();
      } catch (e) {
        debugPrint('[GreenhouseService] SDK get error, fallback ke REST: $e');
      }
    }

    return await _fetchViaRest();
  }

  Future<List<GreenhouseModel>> _fetchViaRest() async {
    try {
      final response = await http.get(Uri.parse(restBaseUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List documents = data['documents'] ?? [];
        final list = documents.map<GreenhouseModel>((doc) {
          final fields = doc['fields'] ?? {};
          final name = fields['name']?['stringValue'] ?? '';
          final area = GreenhouseModel.parseDouble(
            fields['area']?['doubleValue'] ?? fields['area']?['integerValue'],
          );

          final locFields = fields['location']?['mapValue']?['fields'] ?? {};
          final lat = GreenhouseModel.parseDouble(
            locFields['latitude']?['doubleValue'] ?? locFields['latitude']?['integerValue'],
          );
          final lng = GreenhouseModel.parseDouble(
            locFields['longitude']?['doubleValue'] ?? locFields['longitude']?['integerValue'],
          );

          final createdAtStr = fields['created_at']?['timestampValue'];
          final plantingDateStr = fields['planting_date']?['timestampValue'];
          final docName = (doc['name'] as String? ?? '').split('/').last;

          return GreenhouseModel(
            id: docName,
            name: name,
            area: area,
            latitude: lat,
            longitude: lng,
            createdAt:
                createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
            plantType: fields['plant_type']?['stringValue'],
            plantVariety: fields['plant_variety']?['stringValue'],
            soilType: fields['soil_type']?['stringValue'],
            plantingDate: plantingDateStr != null
                ? DateTime.tryParse(plantingDateStr)
                : null,
            iotDeviceId: fields['iot_device_id']?['stringValue'],
          );
        }).toList();

        // Urutkan dari yang terbaru
        list.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        return list;
      }
    } catch (e) {
      debugPrint('[GreenhouseService] Fetch via REST error: $e');
    }
    return [];
  }

  /// Mengambil data satu greenhouse berdasarkan ID
  Future<GreenhouseModel?> getGreenhouseById(String id) async {
    if (_isFirebaseReady && _firestore != null) {
      try {
        final doc = await _firestore!.collection('greenhouses').doc(id).get();
        if (doc.exists) {
          return GreenhouseModel.fromFirestore(doc);
        }
      } catch (e) {
        debugPrint('[GreenhouseService] SDK getById error, fallback REST: $e');
      }
    }

    try {
      final response = await http.get(Uri.parse('$restBaseUrl/$id'));
      if (response.statusCode == 200) {
        final doc = json.decode(response.body);
        final fields = doc['fields'] ?? {};
        final name = fields['name']?['stringValue'] ?? '';
        final area = GreenhouseModel.parseDouble(
          fields['area']?['doubleValue'] ?? fields['area']?['integerValue'],
        );

        final locFields = fields['location']?['mapValue']?['fields'] ?? {};
        final lat = GreenhouseModel.parseDouble(
          locFields['latitude']?['doubleValue'] ?? locFields['latitude']?['integerValue'],
        );
        final lng = GreenhouseModel.parseDouble(
          locFields['longitude']?['doubleValue'] ?? locFields['longitude']?['integerValue'],
        );

        final createdAtStr = fields['created_at']?['timestampValue'];
        final plantingDateStr = fields['planting_date']?['timestampValue'];
        final docName = (doc['name'] as String? ?? '').split('/').last;

        return GreenhouseModel(
          id: docName,
          name: name,
          area: area,
          latitude: lat,
          longitude: lng,
          createdAt:
              createdAtStr != null ? DateTime.tryParse(createdAtStr) : null,
          plantType: fields['plant_type']?['stringValue'],
          plantVariety: fields['plant_variety']?['stringValue'],
          soilType: fields['soil_type']?['stringValue'],
          plantingDate: plantingDateStr != null
              ? DateTime.tryParse(plantingDateStr)
              : null,
          iotDeviceId: fields['iot_device_id']?['stringValue'],
        );
      }
    } catch (e) {
      debugPrint('[GreenhouseService] getGreenhouseById REST error: $e');
    }
    return null;
  }

  /// Mengupdate atau menghubungkan Device ID IoT ke Greenhouse
  Future<void> updateIotDevice({
    required String id,
    required String? iotDeviceId,
  }) async {
    final deviceId = iotDeviceId?.trim() ?? '';
    // 1. Coba via Firebase SDK
    if (_isFirebaseReady && _firestore != null) {
      try {
        await _firestore!.collection('greenhouses').doc(id).update({
          'iot_device_id': deviceId,
        });
        debugPrint('[GreenhouseService] updateIotDevice sukses via SDK: $id -> $deviceId');
        return;
      } catch (e) {
        debugPrint('[GreenhouseService] SDK updateIotDevice error, fallback REST: $e');
      }
    }

    // 2. Fallback via REST API
    final url = '$restBaseUrl/$id?updateMask.fieldPaths=iot_device_id';
    final body = json.encode({
      'fields': {
        'iot_device_id': {'stringValue': deviceId},
      }
    });

    final res = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Gagal update IoT Device via REST: ${res.statusCode}');
    }
    debugPrint('[GreenhouseService] updateIotDevice sukses via REST: $id -> $deviceId');
  }

  /// Mencari apakah suatu Device ID IoT sudah digunakan oleh greenhouse lain (1 Sensor = 1 Greenhouse)
  Future<GreenhouseModel?> findGreenhouseByIotDevice(
    String deviceId, {
    String? excludeGreenhouseId,
  }) async {
    final sanitized = deviceId.trim().toLowerCase();
    if (sanitized.isEmpty) return null;

    try {
      final all = await fetchGreenhouses();
      for (final gh in all) {
        if (excludeGreenhouseId != null && gh.id == excludeGreenhouseId) {
          continue;
        }
        if (gh.iotDeviceId != null &&
            gh.iotDeviceId!.trim().toLowerCase() == sanitized) {
          return gh;
        }
      }
    } catch (e) {
      debugPrint('[GreenhouseService] findGreenhouseByIotDevice error: $e');
    }
    return null;
  }

  /// Mengambil data telemetri live dari Firebase Realtime Database
  /// Mendukung path /devices/{deviceId} atau fallback /greenhouse untuk sensor utama
  Future<Map<String, double>?> fetchLiveIotTelemetry(String deviceId) async {
    final sanitizedId = deviceId.trim();
    if (sanitizedId.isEmpty) return null;

    final lower = sanitizedId.toLowerCase();
    final isSensor1Alias = lower == 'greenhouse' ||
        lower == 'gh_01' ||
        lower == 'gh-01' ||
        lower == 'gh01' ||
        lower == '1' ||
        lower == 'sensor 1';

    final endpointsToTry = [
      'https://smart-greenhouse-ad587-default-rtdb.asia-southeast1.firebasedatabase.app/devices/$sanitizedId.json',
      if (isSensor1Alias)
        'https://smart-greenhouse-ad587-default-rtdb.asia-southeast1.firebasedatabase.app/greenhouse.json',
    ];

    for (final url in endpointsToTry) {
      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final data = json.decode(res.body);
          if (data is Map) {
            return {
              'suhu': GreenhouseModel.parseDouble(data['suhu']),
              'kelembapan': GreenhouseModel.parseDouble(data['kelembapan']),
              'cahaya': GreenhouseModel.parseDouble(data['cahaya']),
            };
          }
        }
      } catch (e) {
        debugPrint('Fetch live IoT error ($url): $e');
      }
    }
    return null;
  }

  /// Memperbarui konfigurasi tanaman & jenis tanah pada greenhouse
  Future<void> updatePlantConfig({
    required String id,
    required String plantType,
    required String plantVariety,
    required String soilType,
    DateTime? plantingDate,
  }) async {
    final effectiveDate = plantingDate ?? DateTime.now();

    // 1. Coba via Firebase SDK
    if (_isFirebaseReady && _firestore != null) {
      try {
        await _firestore!.collection('greenhouses').doc(id).update({
          'plant_type': plantType,
          'plant_variety': plantVariety,
          'soil_type': soilType,
          'planting_date': Timestamp.fromDate(effectiveDate),
        });
        debugPrint('[GreenhouseService] updatePlantConfig sukses via SDK: $id');
        return;
      } catch (e) {
        debugPrint('[GreenhouseService] SDK update error, fallback ke REST: $e');
      }
    }

    // 2. Fallback via Firestore REST API
    final url =
        '$restBaseUrl/$id?updateMask.fieldPaths=plant_type&updateMask.fieldPaths=plant_variety&updateMask.fieldPaths=soil_type&updateMask.fieldPaths=planting_date';

    final body = json.encode({
      'fields': {
        'plant_type': {'stringValue': plantType},
        'plant_variety': {'stringValue': plantVariety},
        'soil_type': {'stringValue': soilType},
        'planting_date': {
          'timestampValue': effectiveDate.toUtc().toIso8601String(),
        },
      }
    });

    final res = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Gagal update konfigurasi tanaman via REST: ${res.statusCode}');
    }
    debugPrint('[GreenhouseService] updatePlantConfig sukses via REST: $id');
  }

  /// Mereset konfigurasi tanaman pada greenhouse (kembali ke state belum dikonfigurasi)
  Future<void> resetPlantConfig(String id) async {
    // 1. Coba via Firebase SDK
    if (_isFirebaseReady && _firestore != null) {
      try {
        await _firestore!.collection('greenhouses').doc(id).update({
          'plant_type': FieldValue.delete(),
          'plant_variety': FieldValue.delete(),
          'soil_type': FieldValue.delete(),
          'planting_date': FieldValue.delete(),
        });
        debugPrint('[GreenhouseService] resetPlantConfig sukses via SDK: $id');
        return;
      } catch (e) {
        debugPrint('[GreenhouseService] SDK reset error, fallback ke REST: $e');
      }
    }

    // 2. Fallback via REST: Kosongkan string
    final url =
        '$restBaseUrl/$id?updateMask.fieldPaths=plant_type&updateMask.fieldPaths=plant_variety&updateMask.fieldPaths=soil_type&updateMask.fieldPaths=planting_date';

    final body = json.encode({
      'fields': {
        'plant_type': {'stringValue': ''},
        'plant_variety': {'stringValue': ''},
        'soil_type': {'stringValue': ''},
      }
    });

    final res = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Gagal reset konfigurasi tanaman via REST: ${res.statusCode}');
    }
    debugPrint('[GreenhouseService] resetPlantConfig sukses via REST: $id');
  }

  /// Menghapus dokumen greenhouse berdasarkan ID
  Future<void> deleteGreenhouse(String id) async {
    if (_isFirebaseReady && _firestore != null) {
      try {
        await _firestore!.collection('greenhouses').doc(id).delete();
        return;
      } catch (e) {
        debugPrint('[GreenhouseService] SDK delete error, fallback REST: $e');
      }
    }

    final url = '$restBaseUrl/$id';
    final res = await http.delete(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Gagal menghapus via REST: ${res.statusCode}');
    }
  }
}
