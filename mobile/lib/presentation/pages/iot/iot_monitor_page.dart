import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_db/database_helper.dart';
import '../../../models/greenhouse_model.dart';
import '../../../services/greenhouse_service.dart';
import '../../widgets/custom_sub_app_bar.dart';
import 'iot_monitoring_page.dart';

class IoTMonitorPage extends StatefulWidget {
  const IoTMonitorPage({super.key});

  @override
  State<IoTMonitorPage> createState() => _IoTMonitorPageState();
}

class _IoTMonitorPageState extends State<IoTMonitorPage> {
  final GreenhouseService _greenhouseService = GreenhouseService();

  List<GreenhouseModel> _greenhouses = [];
  GreenhouseModel? _selectedGreenhouse;
  bool _isLoadingGreenhouses = true;
  bool _isLoadingTelemetry = false;

  Map<String, double>? _liveTelemetry;
  Map<String, dynamic>? _latestDbLog;

  @override
  void initState() {
    super.initState();
    _loadGreenhouses();
  }

  Future<void> _loadGreenhouses() async {
    setState(() => _isLoadingGreenhouses = true);
    try {
      List<GreenhouseModel> list = [];
      try {
        list = await _greenhouseService.fetchGreenhouses();
      } catch (e) {
        debugPrint('[IoTMonitor] Gagal fetch cloud Firestore: $e');
      }

      // Fallback ke SQLite jika cloud kosong
      if (list.isEmpty) {
        final dbRows = await DatabaseHelper.instance.getGreenhousesByUser(1);
        if (dbRows.isNotEmpty) {
          list = dbRows.map((row) {
            return GreenhouseModel(
              id: row['id']?.toString(),
              name: row['nama_greenhouse'] ?? 'Greenhouse #${row['id']}',
              area: (row['luas'] as num?)?.toDouble() ?? 100.0,
              latitude: (row['latitude'] as num?)?.toDouble() ?? -6.2,
              longitude: (row['longitude'] as num?)?.toDouble() ?? 106.8,
              plantType: row['jenis_tanaman'],
              plantVariety: row['varietas'],
              soilType: row['jenis_tanah'],
              iotDeviceId: 'GH_0${row['id'] ?? 1}',
            );
          }).toList();
        }
      }

      // Jika tetap kosong, gunakan unit greenhouse default
      if (list.isEmpty) {
        list = [
          GreenhouseModel(
            id: '1',
            name: 'Greenhouse Utama (A)',
            area: 120.0,
            latitude: -6.2088,
            longitude: 106.8456,
            plantType: 'Tomat',
            plantVariety: 'Cherry Ruby',
            soilType: 'Cocopeat & Sekam',
            iotDeviceId: 'GH_01',
          ),
          GreenhouseModel(
            id: '2',
            name: 'Greenhouse B (Sayur Daun)',
            area: 95.0,
            latitude: -6.2095,
            longitude: 106.8462,
            plantType: 'Selada',
            plantVariety: 'Romaine Hijau',
            soilType: 'Hidroponik NFT',
            iotDeviceId: 'GH_02',
          ),
          GreenhouseModel(
            id: '3',
            name: 'Greenhouse C (Hortikultura)',
            area: 150.0,
            latitude: -6.2102,
            longitude: 106.8470,
            plantType: 'Cabai Rawit',
            plantVariety: 'Hibrida Unggul',
            soilType: 'Tanah Humus Subur',
            iotDeviceId: 'GH_03',
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _greenhouses = list;
          _selectedGreenhouse = list.first;
          _isLoadingGreenhouses = false;
        });
        _fetchTelemetryForSelected();
      }
    } catch (e) {
      debugPrint('[IoTMonitor] Error in _loadGreenhouses: $e');
      if (mounted) {
        setState(() => _isLoadingGreenhouses = false);
      }
    }
  }

  Future<void> _fetchTelemetryForSelected() async {
    if (_selectedGreenhouse == null) return;
    setState(() => _isLoadingTelemetry = true);

    try {
      Map<String, double>? liveData;
      // 1. Ambil live telemetri dari Realtime Database jika ada IoT device
      final deviceId = _selectedGreenhouse!.iotDeviceId;
      if (deviceId != null && deviceId.trim().isNotEmpty) {
        liveData = await _greenhouseService.fetchLiveIotTelemetry(deviceId);
      }

      // 2. Ambil log database lokal terakhir
      Map<String, dynamic>? dbLog;
      final numericId = int.tryParse(_selectedGreenhouse!.id ?? '') ??
          (_greenhouses.indexOf(_selectedGreenhouse!) + 1);
      final logs = await DatabaseHelper.instance.getSensorLogsByGreenhouse(numericId);
      if (logs.isNotEmpty) {
        dbLog = logs.first;
      }

      if (mounted) {
        setState(() {
          _liveTelemetry = liveData;
          _latestDbLog = dbLog;
          _isLoadingTelemetry = false;
        });
      }
    } catch (e) {
      debugPrint('[IoTMonitor] Error fetch telemetry: $e');
      if (mounted) setState(() => _isLoadingTelemetry = false);
    }
  }

  /// Menghitung parameter sensor spesifik berdasarkan greenhouse yang sedang dipilih
  /// Sensor aktif: Suhu Udara, Kelembapan Udara, dan Intensitas Cahaya
  Map<String, dynamic> _computeParametersForCurrentGh() {
    final gh = _selectedGreenhouse;
    final ghIndex = gh != null ? _greenhouses.indexOf(gh) : 0;

    // Nilai acuan default per greenhouse jika belum ada streaming live
    double baseTemp;
    double baseHumidity;
    double baseLight;

    if (ghIndex == 0) {
      baseTemp = 26.8;
      baseHumidity = 76.0;
      baseLight = 840.0;
    } else if (ghIndex == 1) {
      baseTemp = 24.5;
      baseHumidity = 82.0;
      baseLight = 760.0;
    } else {
      baseTemp = 29.2;
      baseHumidity = 64.0;
      baseLight = 920.0;
    }

    // Override dengan database log jika ada
    if (_latestDbLog != null) {
      baseTemp = (_latestDbLog!['suhu'] as num?)?.toDouble() ?? baseTemp;
      baseHumidity = (_latestDbLog!['kelembapan_udara'] as num?)?.toDouble() ?? baseHumidity;
      baseLight = (_latestDbLog!['cahaya'] as num?)?.toDouble() ?? baseLight;
    }

    // Override dengan live telemetri Firebase RTDB jika online
    if (_liveTelemetry != null) {
      if (_liveTelemetry!['suhu'] != null && _liveTelemetry!['suhu']! > 0) {
        baseTemp = _liveTelemetry!['suhu']!;
      }
      if (_liveTelemetry!['kelembapan'] != null && _liveTelemetry!['kelembapan']! > 0) {
        baseHumidity = _liveTelemetry!['kelembapan']!;
      }
      if (_liveTelemetry!['cahaya'] != null && _liveTelemetry!['cahaya']! > 0) {
        baseLight = _liveTelemetry!['cahaya']!;
      }
    }

    // Evaluasi Status Suhu
    String statusSuhu;
    Color colorSuhu;
    if (baseTemp < 22) {
      statusSuhu = 'Sejuk Dingin (<22°C)';
      colorSuhu = const Color(0xFF4FC3F7);
    } else if (baseTemp <= 29) {
      statusSuhu = 'Optimal (22-29°C)';
      colorSuhu = const Color(0xFFFFA726);
    } else {
      statusSuhu = 'Waspada Hangat (>29°C)';
      colorSuhu = const Color(0xFFFF5252);
    }

    // Evaluasi Status Kelembapan
    String statusLembap;
    Color colorLembap;
    if (baseHumidity < 55) {
      statusLembap = 'Kering (<55%)';
      colorLembap = const Color(0xFFFFB74D);
    } else if (baseHumidity <= 80) {
      statusLembap = 'Normal Lembap (55-80%)';
      colorLembap = const Color(0xFF29B6F6);
    } else {
      statusLembap = 'Terlalu Lembap (>80%)';
      colorLembap = const Color(0xFF4DB6AC);
    }

    // Evaluasi Status Cahaya
    String statusCahaya;
    Color colorCahaya;
    if (baseLight < 500) {
      statusCahaya = 'Pencahayaan Rendah';
      colorCahaya = const Color(0xFF90A4AE);
    } else if (baseLight <= 1000) {
      statusCahaya = 'Pencahayaan Baik';
      colorCahaya = const Color(0xFFFFD54F);
    } else {
      statusCahaya = 'Intensitas Terik Tinggi';
      colorCahaya = const Color(0xFFFFB300);
    }

    return {
      'suhu': baseTemp,
      'statusSuhu': statusSuhu,
      'colorSuhu': colorSuhu,
      'kelembapan': baseHumidity,
      'statusLembap': statusLembap,
      'colorLembap': colorLembap,
      'cahaya': baseLight,
      'statusCahaya': statusCahaya,
      'colorCahaya': colorCahaya,
    };
  }

  @override
  Widget build(BuildContext context) {
    final params = _computeParametersForCurrentGh();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.ground,
        child: SafeArea(
          child: Column(
            children: [
              CustomSubAppBar(
                title: 'IoT Monitor',
                subtitle: 'Sensor Lingkungan Real-Time Per Greenhouse',
                trailing: GestureDetector(
                  onTap: () {
                    _fetchTelemetryForSelected();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Memperbarui telemetri ${_selectedGreenhouse?.name ?? "greenhouse"}...',
                          style: const TextStyle(color: AppTheme.darkForest),
                        ),
                        backgroundColor: AppTheme.neonLime,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.neonLime.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.neonLime.withValues(alpha: 0.4),
                      ),
                    ),
                    child: _isLoadingTelemetry
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.neonLime,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: AppTheme.neonLime,
                            size: 20,
                          ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.neonLime.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.sensors_rounded,
                                color: AppTheme.neonLime,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Node IoT Sensor Terhubung',
                                        style: TextStyle(
                                          color: AppTheme.creamWhite,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _liveTelemetry != null
                                              ? AppTheme.neonLime.withValues(alpha: 0.2)
                                              : Colors.amber.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _liveTelemetry != null ? 'CLOUD LIVE' : 'SYNC DB',
                                          style: TextStyle(
                                            color: _liveTelemetry != null
                                                ? AppTheme.neonLime
                                                : Colors.amber,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedGreenhouse != null
                                        ? '${_selectedGreenhouse!.name} • Device ID: ${_selectedGreenhouse!.iotDeviceId ?? "GH_NODE_01"}'
                                        : 'Protokol MQTT • Update tiap 5 detik',
                                    style: const TextStyle(
                                      color: AppTheme.pastelLime,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Pemilih Greenhouse Interaktif
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Pilih Unit Greenhouse',
                            style: TextStyle(
                              color: AppTheme.creamWhite,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_greenhouses.isNotEmpty)
                            Text(
                              '${_greenhouses.length} Greenhouse Terdaftar',
                              style: const TextStyle(
                                color: AppTheme.pastelLime,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_isLoadingGreenhouses)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(color: AppTheme.neonLime),
                          ),
                        )
                      else
                        SizedBox(
                          height: 78,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _greenhouses.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final gh = _greenhouses[index];
                              final isSelected = gh == _selectedGreenhouse;

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedGreenhouse = gh;
                                    _liveTelemetry = null;
                                  });
                                  _fetchTelemetryForSelected();
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 190,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.emeraldGreen.withValues(alpha: 0.35)
                                        : AppTheme.cardSurface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.neonLime
                                          : AppTheme.emeraldGreen.withValues(alpha: 0.3),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.home_work_rounded,
                                            size: 16,
                                            color: isSelected ? AppTheme.neonLime : AppTheme.textGrey,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              gh.name,
                                              style: TextStyle(
                                                color: isSelected ? AppTheme.creamWhite : AppTheme.textGrey,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        gh.plantType != null && gh.plantType!.isNotEmpty
                                            ? '${gh.plantType} (${gh.plantVariety ?? "-"})'
                                            : 'Luas: ${gh.area.toStringAsFixed(0)} m²',
                                        style: TextStyle(
                                          color: isSelected ? AppTheme.pastelLime : AppTheme.textGrey.withValues(alpha: 0.7),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: gh.hasIotDevice ? AppTheme.neonLime : Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            gh.hasIotDevice ? 'Node: ${gh.iotDeviceId}' : 'Sensor Log Lokal',
                                            style: TextStyle(
                                              color: isSelected ? AppTheme.creamWhite : AppTheme.textGrey,
                                              fontSize: 9.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Shortcut ke Halaman Telemetri & Multi-Valuta (FR-06, FR-07, FR-08)
                      InkWell(
                        onTap: () {
                          final gh = _selectedGreenhouse;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => IotMonitoringPage(
                                greenhouse: {
                                  'id': int.tryParse(gh?.id ?? '') ?? 1,
                                  'nama_greenhouse': gh?.name ?? 'Greenhouse Utama (A)',
                                  'biaya_operasional_idr': 1500000.0,
                                  'batas_suhu_maks': 35.0,
                                  'batas_lembap_min': 40.0,
                                },
                                userId: 1,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.neonLime.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.neonLime.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.currency_exchange_rounded, color: AppTheme.neonLime, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Valuasi Panen & Riwayat (${_selectedGreenhouse?.name ?? "Greenhouse"})',
                                      style: const TextStyle(
                                        color: AppTheme.neonLime,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Text(
                                      'Buka kalkulator ekspor 4 mata uang & riwayat sensor 4 zona waktu',
                                      style: TextStyle(
                                        color: AppTheme.pastelLime,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.neonLime, size: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Header Parameter Lingkungan
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Parameter Lingkungan • ${_selectedGreenhouse?.name ?? "Greenhouse"}',
                              style: const TextStyle(
                                color: AppTheme.creamWhite,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isLoadingTelemetry)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.neonLime,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Varietas: ${_selectedGreenhouse?.plantVariety ?? "Tanaman Pilihan"} • Media: ${_selectedGreenhouse?.soilType ?? "Cocopeat & Sekam"}',
                        style: const TextStyle(
                          color: AppTheme.pastelLime,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Kartu Utama Suhu Udara (Full Width Hero Card)
                      _buildHeroSensorCard(
                        title: 'Suhu Udara',
                        value: '${(params['suhu'] as double).toStringAsFixed(1)}°C',
                        status: params['statusSuhu'] as String,
                        icon: Icons.thermostat_rounded,
                        color: params['colorSuhu'] as Color,
                      ),
                      const SizedBox(height: 12),

                      // Kartu Kelembapan Udara & Intensitas Cahaya (2 Kolom Seimbang)
                      Row(
                        children: [
                          Expanded(
                            child: _buildSensorCard(
                              title: 'Kelembapan Udara',
                              value: '${(params['kelembapan'] as double).toStringAsFixed(0)}%',
                              status: params['statusLembap'] as String,
                              icon: Icons.water_drop_rounded,
                              color: params['colorLembap'] as Color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSensorCard(
                              title: 'Intensitas Cahaya',
                              value: '${(params['cahaya'] as double).toStringAsFixed(0)} Lux',
                              status: params['statusCahaya'] as String,
                              icon: Icons.wb_sunny_rounded,
                              color: params['colorCahaya'] as Color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
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

  /// Kartu Sensor Unggulan (Full Width) untuk Suhu Udara
  Widget _buildHeroSensorCard({
    required String title,
    required String value,
    required String status,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.creamWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }

  /// Kartu Sensor Standar untuk Kelembapan & Cahaya
  Widget _buildSensorCard({
    required String title,
    required String value,
    required String status,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.creamWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: 10.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
