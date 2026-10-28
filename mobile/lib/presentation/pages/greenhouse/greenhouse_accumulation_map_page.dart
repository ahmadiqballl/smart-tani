import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/greenhouse_model.dart';
import '../../../services/greenhouse_service.dart';
import '../../widgets/custom_sub_app_bar.dart';
import 'greenhouse_detail_page.dart';

class GreenhouseAccumulationMapPage extends StatefulWidget {
  final List<GreenhouseModel>? initialGreenhouses;

  const GreenhouseAccumulationMapPage({
    super.key,
    this.initialGreenhouses,
  });

  @override
  State<GreenhouseAccumulationMapPage> createState() =>
      _GreenhouseAccumulationMapPageState();
}

class _GreenhouseAccumulationMapPageState
    extends State<GreenhouseAccumulationMapPage>
    with TickerProviderStateMixin {
  final GreenhouseService _greenhouseService = GreenhouseService();
  final MapController _mapController = MapController();

  List<GreenhouseModel> _greenhouses = [];
  bool _isLoading = true;
  GreenhouseModel? _selectedGreenhouse;

  // ── Live GPS & Compass ──
  LatLng? _currentLiveLocation;
  double _compassHeading = 0.0; // derajat 0–360
  double _mapRotation = 0.0; // rotasi peta saat ini
  bool _isLiveTrackingFollow = false;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;

  // Animasi pulsing blue dot
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Setup pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.35, end: 0.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.initialGreenhouses != null &&
        widget.initialGreenhouses!.isNotEmpty) {
      _greenhouses = widget.initialGreenhouses!;
      _isLoading = false;
      _selectedGreenhouse = _greenhouses.first;
    } else {
      _loadData();
    }

    // Start GPS + compass after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLiveLocationAndCompass();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // GPS & Compass
  // ═══════════════════════════════════════════════════════════════

  Future<void> _initLiveLocationAndCompass() async {
    // 1. Minta izin lokasi
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    // 2. Ambil posisi awal
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentLiveLocation = LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (e) {
      debugPrint('Initial position error: $e');
    }

    // 3. Streaming GPS real-time (update setiap 3 meter)
    try {
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
      _positionStream = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen((Position pos) {
        if (!mounted) return;
        final livePoint = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentLiveLocation = livePoint;
          if (_isLiveTrackingFollow) {
            _mapController.move(livePoint, _mapController.camera.zoom);
          }
        });
      });
    } catch (e) {
      debugPrint('GPS Stream error: $e');
    }

    // 4. Streaming sensor kompas hardware
    try {
      _compassStream = FlutterCompass.events?.listen((event) {
        if (event.heading != null && mounted) {
          setState(() {
            _compassHeading = event.heading!;
          });
        }
      });
    } catch (e) {
      debugPrint('Compass error: $e');
    }
  }

  /// Putar peta agar menghadap utara (rotasi = 0°)
  void _resetToNorth() {
    setState(() {
      _mapRotation = 0.0;
      _isLiveTrackingFollow = false;
    });
    _mapController.rotate(0.0);
  }

  /// Pusatkan peta ke lokasi live pengguna
  void _goToMyLocation() {
    if (_currentLiveLocation != null) {
      _mapController.move(_currentLiveLocation!, 16.0);
      setState(() => _isLiveTrackingFollow = true);
    }
  }

  String _headingToCardinal(double heading) {
    const directions = [
      'U', 'TL', 'T', 'TG', 'S', 'BD', 'B', 'BL'
    ];
    final index = ((heading + 22.5) % 360 / 45).floor();
    return '${directions[index]} (${heading.toStringAsFixed(0)}°)';
  }

  // ═══════════════════════════════════════════════════════════════
  // Data
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list = await _greenhouseService.fetchGreenhouses();
      if (mounted) {
        setState(() {
          _greenhouses = list;
          _isLoading = false;
          if (list.isNotEmpty) {
            _selectedGreenhouse = list.first;
            _fitBoundsToGreenhouses();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalArea =>
      _greenhouses.fold<double>(0.0, (acc, gh) => acc + gh.area);

  LatLng get _centerPoint {
    if (_greenhouses.isEmpty) return const LatLng(-7.7828, 110.3670);
    double latSum = 0;
    double lngSum = 0;
    int count = 0;
    for (final gh in _greenhouses) {
      if (gh.latitude != 0.0 && gh.longitude != 0.0) {
        latSum += gh.latitude;
        lngSum += gh.longitude;
        count++;
      }
    }
    if (count == 0) return const LatLng(-7.7828, 110.3670);
    return LatLng(latSum / count, lngSum / count);
  }

  void _fitBoundsToGreenhouses() {
    if (_greenhouses.isEmpty) return;
    _mapController.move(_centerPoint, 13.5);
  }

  // ═══════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ground,
      body: SafeArea(
        child: Column(
          children: [
            CustomSubAppBar(
              title: 'Peta Akumulasi Greenhouse',
              subtitle: 'Sebaran Spasial & Rekapitulasi Luas Lahan',
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.neonLime),
                tooltip: 'Segarkan Peta',
                onPressed: _loadData,
              ),
            ),

            // Top HUD Summary Bar
            _buildAkumulasiHudBar(),

            // Map Area
            Expanded(
              child: Stack(
                children: [
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(color: AppTheme.neonLime),
                    )
                  else
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _centerPoint,
                        initialZoom: 13.5,
                        initialRotation: _mapRotation,
                        minZoom: 4,
                        maxZoom: 18,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) {
                            setState(() => _mapRotation = pos.rotation);
                          }
                        },
                        onTap: (_, __) {
                          setState(() => _selectedGreenhouse = null);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.tanigreen.mobile',
                          errorTileCallback: (tile, error, stackTrace) {
                            debugPrint('Peta offline / Tile load error: $error');
                          },
                        ),
                        MarkerLayer(
                          markers: [
                            // ── Blue Dot: Posisi Real-Time Pengguna ──
                            if (_currentLiveLocation != null)
                              Marker(
                                point: _currentLiveLocation!,
                                width: 60,
                                height: 60,
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, _) {
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Outer pulsing ring
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF2196F3)
                                                .withValues(alpha: _pulseAnimation.value),
                                          ),
                                        ),
                                        // Inner ring
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF2196F3)
                                                .withValues(alpha: 0.25),
                                          ),
                                        ),
                                        // Bearing arrow (rotates with compass)
                                        Transform.rotate(
                                          angle: _compassHeading * (math.pi / 180),
                                          child: const Icon(
                                            Icons.navigation_rounded,
                                            color: Color(0xFF1565C0),
                                            size: 18,
                                          ),
                                        ),
                                        // Solid center dot
                                        Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF2196F3),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF2196F3)
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),

                            // ── Greenhouse Markers ──
                            ..._greenhouses.map((gh) {
                              final isSelected =
                                  _selectedGreenhouse?.id == gh.id;
                              final lat = gh.latitude != 0.0
                                  ? gh.latitude
                                  : -7.7828;
                              final lng = gh.longitude != 0.0
                                  ? gh.longitude
                                  : 110.3670;

                              return Marker(
                                point: LatLng(lat, lng),
                                width: 140,
                                height: 75,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedGreenhouse = gh);
                                    _mapController.move(
                                        LatLng(lat, lng), 15.0);
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppTheme.neonLime
                                              : AppTheme.darkForest,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppTheme.darkForest
                                                : AppTheme.neonLime,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          gh.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isSelected
                                                ? AppTheme.darkForest
                                                : AppTheme.creamWhite,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.location_on_rounded,
                                        color: isSelected
                                            ? AppTheme.neonLime
                                            : const Color(0xFF2ECC71),
                                        size: isSelected ? 36 : 28,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),

                  // ── Compass Widget (Kiri Atas) ──
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildCompassWidget(),
                  ),

                  // ── Floating Action Buttons (Kanan) ──
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        // Tombol "Hadap Utara" (reset bearing)
                        FloatingActionButton.small(
                          heroTag: 'btn_north',
                          backgroundColor: _mapRotation.abs() < 1
                              ? AppTheme.cardSurface
                              : const Color(0xFF1565C0),
                          foregroundColor: _mapRotation.abs() < 1
                              ? AppTheme.textGrey
                              : Colors.white,
                          tooltip: 'Hadap Utara',
                          onPressed: _resetToNorth,
                          child: Transform.rotate(
                            angle: -_mapRotation * (math.pi / 180),
                            child: const Icon(Icons.explore_rounded, size: 22),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // My Location
                        FloatingActionButton.small(
                          heroTag: 'btn_my_loc',
                          backgroundColor: _isLiveTrackingFollow
                              ? const Color(0xFF2196F3)
                              : AppTheme.cardSurface,
                          foregroundColor: _isLiveTrackingFollow
                              ? Colors.white
                              : AppTheme.neonLime,
                          tooltip: 'Lokasi Saya',
                          onPressed: _goToMyLocation,
                          child: const Icon(Icons.my_location_rounded),
                        ),
                        const SizedBox(height: 8),
                        // Fit All Greenhouses
                        FloatingActionButton.small(
                          heroTag: 'btn_center_map',
                          backgroundColor: AppTheme.cardSurface,
                          foregroundColor: AppTheme.neonLime,
                          tooltip: 'Pusatkan Peta ke Semua Greenhouse',
                          onPressed: () {
                            _fitBoundsToGreenhouses();
                            setState(() => _isLiveTrackingFollow = false);
                          },
                          child: const Icon(Icons.crop_free_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_zoom_in',
                          backgroundColor: AppTheme.cardSurface,
                          foregroundColor: AppTheme.neonLime,
                          tooltip: 'Perbesar',
                          onPressed: () {
                            _mapController.move(
                              _mapController.camera.center,
                              _mapController.camera.zoom + 1,
                            );
                          },
                          child: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btn_zoom_out',
                          backgroundColor: AppTheme.cardSurface,
                          foregroundColor: AppTheme.neonLime,
                          tooltip: 'Perkecil',
                          onPressed: () {
                            _mapController.move(
                              _mapController.camera.center,
                              _mapController.camera.zoom - 1,
                            );
                          },
                          child: const Icon(Icons.remove_rounded),
                        ),
                      ],
                    ),
                  ),

                  // ── Live Location Info Badge (Bawah Kiri) ──
                  if (_currentLiveLocation != null)
                    Positioned(
                      left: 16,
                      bottom: _selectedGreenhouse != null ? 200 : 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2196F3).withValues(alpha: 0.5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF2196F3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Arah: ${_headingToCardinal(_compassHeading)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${_currentLiveLocation!.latitude.toStringAsFixed(5)}, '
                                  '${_currentLiveLocation!.longitude.toStringAsFixed(5)}',
                                  style: TextStyle(
                                    color: AppTheme.textGrey.withValues(alpha: 0.85),
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Bottom Selected Greenhouse Card ──
                  if (_selectedGreenhouse != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _buildSelectedGreenhouseSheet(_selectedGreenhouse!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Compass Widget
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCompassWidget() {
    return GestureDetector(
      onTap: _resetToNorth,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.cardSurface.withValues(alpha: 0.92),
          border: Border.all(
            color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rotating compass ring with compass heading
            Transform.rotate(
              angle: -_compassHeading * (math.pi / 180),
              child: CustomPaint(
                size: const Size(56, 56),
                painter: _CompassRingPainter(),
              ),
            ),
            // "N" label at bearing north
            Transform.rotate(
              angle: -_compassHeading * (math.pi / 180),
              child: const Align(
                alignment: Alignment(0, -0.65),
                child: Text(
                  'N',
                  style: TextStyle(
                    color: Color(0xFFFF1744),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            // Center bearing arrow (fixed, pointing "up" = device heading)
            const Icon(
              Icons.navigation_rounded,
              color: Color(0xFFFF1744),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HUD Bar
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAkumulasiHudBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonLime.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.roofing_rounded,
                      color: AppTheme.neonLime, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Greenhouse',
                      style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${_greenhouses.length} Unit',
                      style: const TextStyle(
                        color: AppTheme.creamWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 32,
            width: 1,
            color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.square_foot_rounded,
                      color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Akumulasi Luas',
                      style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${_totalArea.toStringAsFixed(0)} m²',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Selected Greenhouse Bottom Sheet
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSelectedGreenhouseSheet(GreenhouseModel gh) {
    final variety = gh.plantVariety?.isNotEmpty == true
        ? gh.plantVariety!
        : (gh.plantType?.isNotEmpty == true ? gh.plantType! : 'Belum Dikonfigurasi');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.neonLime.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.neonLime.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco_rounded,
                    color: AppTheme.neonLime, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gh.name,
                      style: const TextStyle(
                        color: AppTheme.creamWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Varietas: $variety • Luas: ${gh.area.toStringAsFixed(0)} m²',
                      style: const TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppTheme.textGrey, size: 20),
                onPressed: () => setState(() => _selectedGreenhouse = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                      ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      size: 13,
                      color: (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                          ? const Color(0xFF2ECC71)
                          : Colors.orange,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                          ? 'IoT: ${gh.iotDeviceId}'
                          : 'IoT Belum Terhubung',
                      style: TextStyle(
                        color: (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                            ? const Color(0xFF2ECC71)
                            : Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GreenhouseDetailPage(greenhouse: gh),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Detail Greenhouse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonLime,
                  foregroundColor: AppTheme.darkForest,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Custom Painter: Compass Ring (garis derajat + tanda arah)
// ═══════════════════════════════════════════════════════════════

class _CompassRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Draw tick marks every 30°, major tick at 0/90/180/270
    for (int i = 0; i < 360; i += 30) {
      final angle = (i - 90) * (math.pi / 180);
      final isMajor = (i % 90 == 0);
      final innerR = isMajor ? radius - 8 : radius - 5;

      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final inner = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );

      canvas.drawLine(inner, outer, isMajor ? majorTickPaint : tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
