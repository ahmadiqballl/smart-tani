import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/theme/app_theme.dart';
import '../models/greenhouse_model.dart';
import '../services/greenhouse_service.dart';

/// Form Modal Bottom Sheet untuk menambahkan data Greenhouse baru ke Firebase Firestore
/// Dilengkapi pemilihan titik koordinat langsung pada peta OpenStreetMap (OSM)
class AddGreenhouseSheet extends StatefulWidget {
  const AddGreenhouseSheet({super.key});

  /// Helper untuk membuka Bottom Sheet secara praktis
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddGreenhouseSheet(),
    );
  }

  @override
  State<AddGreenhouseSheet> createState() => _AddGreenhouseSheetState();
}

class _AddGreenhouseSheetState extends State<AddGreenhouseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _areaController = TextEditingController();
  final _mapController = MapController();

  final GreenhouseService _greenhouseService = GreenhouseService();

  // Titik koordinat awal (Default: Yogyakarta)
  LatLng _selectedLocation = const LatLng(-7.7828, 110.3670);
  String _addressPreview = 'Ketuk pada peta untuk menentukan titik koordinat lahan';
  bool _isLoadingAddress = false;
  bool _isGettingGps = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  /// Mengambil lokasi GPS perangkat saat ini jika izin diberikan
  Future<void> _fetchCurrentLocation() async {
    setState(() => _isGettingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isGettingGps = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isGettingGps = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isGettingGps = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final newPoint = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _selectedLocation = newPoint;
          _isGettingGps = false;
        });
        _mapController.move(newPoint, 16.0);
        _reverseGeocode(newPoint);
      }
    } catch (e) {
      debugPrint('Gagal mendapatkan GPS: $e');
      if (mounted) setState(() => _isGettingGps = false);
    }
  }

  /// Reverse Geocoding via OpenStreetMap Nominatim API untuk melihat alamat teks
  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _isLoadingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'TaniGreenApp/1.0 (contact@tanigreen.id)',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _addressPreview = data['display_name'] ?? 'Alamat terdeteksi';
            _isLoadingAddress = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Gagal reverse geocode: $e');
    }

    if (mounted) {
      setState(() {
        _addressPreview =
            'Titik: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
        _isLoadingAddress = false;
      });
    }
  }

  /// Submit form dan kirim data ke Firebase Firestore
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final areaValue = double.tryParse(_areaController.text.trim().replaceAll(',', '.'));
    if (areaValue == null || areaValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Luas area harus berupa angka yang valid (> 0)'),
          backgroundColor: AppTheme.statusAlert,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final newGreenhouse = GreenhouseModel(
        name: _nameController.text.trim(),
        area: areaValue,
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
        createdAt: DateTime.now(),
      );

      await _greenhouseService.addGreenhouse(newGreenhouse);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.panelElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.statusOk, width: 1),
            ),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.statusOk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Greenhouse "${newGreenhouse.name}" berhasil disimpan ke Firebase!',
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('Error submit greenhouse: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.panelElevated,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.statusAlert, width: 1),
            ),
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.statusAlert),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Gagal menyimpan ke Firebase: $e',
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.ground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.borderQuiet, width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Grab Handle ──
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderQuiet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Sheet Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'FIREBASE FIRESTORE',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tambah Greenhouse Baru',
                      style: AppTheme.headline,
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.borderQuiet, height: 24),

          // ── Form Body (Scrollable) ──
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Nama Greenhouse
                    const Text(
                      'Nama Greenhouse',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Contoh: Greenhouse Melon Blok A',
                        hintStyle: const TextStyle(
                          color: AppTheme.inkTertiary,
                          fontSize: 13.5,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelElevated,
                        prefixIcon: const Icon(
                          Icons.domain_rounded,
                          color: AppTheme.accent,
                          size: 20,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.borderQuiet,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.accent,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.statusAlert,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.statusAlert,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nama greenhouse tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // 2. Ukuran Luas Kuadrat (m²)
                    const Text(
                      'Ukuran Luas Area (m²)',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _areaController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Contoh: 250 atau 120.5',
                        hintStyle: const TextStyle(
                          color: AppTheme.inkTertiary,
                          fontSize: 13.5,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelElevated,
                        prefixIcon: const Icon(
                          Icons.square_foot_rounded,
                          color: AppTheme.accent,
                          size: 20,
                        ),
                        suffixText: 'm²',
                        suffixStyle: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.borderQuiet,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.accent,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.statusAlert,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.statusAlert,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ukuran luas kuadrat harus diisi';
                        }
                        final parsed = double.tryParse(
                          value.trim().replaceAll(',', '.'),
                        );
                        if (parsed == null || parsed <= 0) {
                          return 'Masukkan angka valid lebih besar dari 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // 3. Titik Lokasi pada Peta OpenStreetMap (OSM)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: AppTheme.accent,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Titik Lokasi (OpenStreetMap)',
                              style: TextStyle(
                                color: AppTheme.ink,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _isGettingGps ? null : _fetchCurrentLocation,
                          icon: _isGettingGps
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.accent,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location_rounded,
                                  size: 14,
                                  color: AppTheme.accent,
                                ),
                          label: const Text(
                            'Lokasi Saya',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Peta Interaktif OSM
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: AppTheme.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.borderQuiet,
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _selectedLocation,
                              initialZoom: 15.0,
                              onTap: (tapPosition, point) {
                                setState(() {
                                  _selectedLocation = point;
                                });
                                _reverseGeocode(point);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.tanigreen.mobile',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _selectedLocation,
                                    width: 50,
                                    height: 50,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accent,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.agriculture_rounded,
                                            size: 18,
                                            color: AppTheme.ground,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_drop_down_rounded,
                                          size: 16,
                                          color: AppTheme.accent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Tombol Zoom Peta
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              children: [
                                _buildZoomButton(
                                  icon: Icons.add_rounded,
                                  onTap: () {
                                    final currentZoom =
                                        _mapController.camera.zoom;
                                    _mapController.move(
                                      _mapController.camera.center,
                                      currentZoom + 1,
                                    );
                                  },
                                ),
                                const SizedBox(height: 6),
                                _buildZoomButton(
                                  icon: Icons.remove_rounded,
                                  onTap: () {
                                    final currentZoom =
                                        _mapController.camera.zoom;
                                    _mapController.move(
                                      _mapController.camera.center,
                                      currentZoom - 1,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // Petunjuk sentuh peta
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.ground.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.borderQuiet,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    size: 12,
                                    color: AppTheme.accent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Ketuk peta untuk geser titik',
                                    style: TextStyle(
                                      color: AppTheme.inkSecondary,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Kotak info koordinat & alamat terpilih
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.panelElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderQuiet),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.borderQuiet,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'LAT: ${_selectedLocation.latitude.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.borderQuiet,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'LNG: ${_selectedLocation.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isLoadingAddress)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6, top: 2),
                                  child: SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.only(right: 6, top: 2),
                                  child: Icon(
                                    Icons.place_rounded,
                                    size: 13,
                                    color: AppTheme.inkTertiary,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _addressPreview,
                                  style: const TextStyle(
                                    color: AppTheme.inkSecondary,
                                    fontSize: 11.5,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Tombol Simpan ──
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.ground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor:
                              AppTheme.accent.withValues(alpha: 0.5),
                        ),
                        child: _isSubmitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.ground,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Menyimpan ke Firebase...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.ground,
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_upload_rounded, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Simpan ke Firebase',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
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
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.ground.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.borderQuiet),
          ),
          child: Icon(icon, color: AppTheme.ink, size: 18),
        ),
      ),
    );
  }
}
