import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/greenhouse_model.dart';
import '../../../services/greenhouse_service.dart';
import '../schedule/jadwal_tanam_page.dart';

/// Halaman Detail per-Greenhouse
/// - Pengaturan awal: Menentukan jenis tanaman, varietas, dan jenis tanah (media tanam)
/// - Setelah di-setting: Menampilkan dashboard budidaya aktif tanaman, telemetri, dan rekomendasi
/// - Mendukung fitur Edit dan Reset konfigurasi kapan saja
class GreenhouseDetailPage extends StatefulWidget {
  final GreenhouseModel greenhouse;

  const GreenhouseDetailPage({
    super.key,
    required this.greenhouse,
  });

  @override
  State<GreenhouseDetailPage> createState() => _GreenhouseDetailPageState();
}

class _GreenhouseDetailPageState extends State<GreenhouseDetailPage> {
  final GreenhouseService _greenhouseService = GreenhouseService();

  late GreenhouseModel _currentGreenhouse;
  bool _isLoading = false;

  // Real-time IoT Data dari Firebase Realtime Database
  Map<String, double>? _iotData;
  Timer? _iotTimer;

  // Controller & State untuk Form Pengaturan Awal / Edit
  final _plantTypeController = TextEditingController();
  final _varietyController = TextEditingController();
  final _soilTypeController = TextEditingController();
  DateTime _selectedPlantingDate = DateTime.now();

  // Mode edit saat sudah configured
  bool _isEditing = false;

  // Preset Tanaman Populer
  final List<Map<String, dynamic>> _popularPlants = [
    {'name': 'Tomat', 'icon': '🍅', 'varieties': ['Cherry Ruby', 'Beefsteak', 'Servo F1', 'Tomat Apel']},
    {'name': 'Cabai', 'icon': '🌶️', 'varieties': ['Rawit Merah Hibrida', 'Keriting PM999', 'Katokkon', 'Cabai Besar Gada']},
    {'name': 'Melon', 'icon': '🍈', 'varieties': ['Inthanon RZ', 'Golden Emerald', 'Melon Alisha', 'Sky Rocket']},
    {'name': 'Selada', 'icon': '🥬', 'varieties': ['Romaine Hijau', 'Butterhead', 'Grand Rapids', 'Lollo Rossa']},
    {'name': 'Stroberi', 'icon': '🍓', 'varieties': ['Festival', 'Sweet Charlie', 'California']},
    {'name': 'Terong', 'icon': '🍆', 'varieties': ['Ungu Mustang', 'Hijau Antaboga']},
    {'name': 'Timun', 'icon': '🥒', 'varieties': ['Jepang Kyuri', 'Timun Hercules']},
    {'name': 'Bayam', 'icon': '🌱', 'varieties': ['Bayam Hijau Maestro', 'Bayam Merah Mira']},
  ];

  // Preset Media Tanah Populer
  final List<String> _popularSoilTypes = [
    'Tanah Humus Subur (Kompos Organik)',
    'Tanah Lempung Berpasir',
    'Media Cocopeat & Arang Sekam',
    'Hidroponik (Rockwool / NFT System)',
    'Tanah Alluvial Subur',
    'Campuran Tanah, Pupuk Kandang & Sekam (1:1:1)',
  ];

  @override
  void initState() {
    super.initState();
    _currentGreenhouse = widget.greenhouse;
    _populateControllers();
    _startIotPolling();
  }

  void _populateControllers() {
    _plantTypeController.text = _currentGreenhouse.plantType ?? '';
    _varietyController.text = _currentGreenhouse.plantVariety ?? '';
    _soilTypeController.text = _currentGreenhouse.soilType ?? '';
    _selectedPlantingDate = _currentGreenhouse.plantingDate ?? DateTime.now();
  }

  void _startIotPolling() {
    _iotTimer?.cancel();
    if (_currentGreenhouse.hasIotDevice) {
      _fetchIotData();
      _iotTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted && _currentGreenhouse.hasIotDevice) {
          _fetchIotData();
        }
      });
    }
  }

  Future<void> _fetchIotData() async {
    if (!_currentGreenhouse.hasIotDevice) return;
    try {
      final data = await _greenhouseService
          .fetchLiveIotTelemetry(_currentGreenhouse.iotDeviceId!);
      if (mounted && data != null) {
        setState(() => _iotData = data);
      }
    } catch (_) {}
  }

  Future<void> _saveIotDevice(String deviceId) async {
    final sanitized = deviceId.trim();
    if (_currentGreenhouse.id == null || sanitized.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // 1. Validasi 1 Sensor = 1 Greenhouse (Cegah Duplikasi)
      final occupiedGh = await _greenhouseService.findGreenhouseByIotDevice(
        sanitized,
        excludeGreenhouseId: _currentGreenhouse.id,
      );
      if (occupiedGh != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showOccupiedWarningDialog(sanitized, occupiedGh.name);
        }
        return;
      }

      // 2. Validasi Keberadaan & Keaktifan Sensor di Firebase Realtime Database
      final telemetry = await _greenhouseService.fetchLiveIotTelemetry(sanitized);
      if (telemetry == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showSensorOfflineWarningDialog(sanitized);
        }
        return;
      }

      // 3. Simpan relasi ke Firestore
      await _greenhouseService.updateIotDevice(
        id: _currentGreenhouse.id!,
        iotDeviceId: sanitized,
      );

      final updated = _currentGreenhouse.copyWith(iotDeviceId: sanitized);
      if (mounted) {
        setState(() {
          _currentGreenhouse = updated;
          _iotData = telemetry;
          _isLoading = false;
        });
        _startIotPolling();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.panelElevated,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.statusOk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Berhasil menghubungkan ke Node IoT "$sanitized"!',
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghubungkan IoT: $e'), backgroundColor: AppTheme.statusAlert),
        );
      }
    }
  }

  void _showOccupiedWarningDialog(String deviceId, String occupiedByName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('Sensor Sudah Terpakai', style: TextStyle(color: AppTheme.ink, fontSize: 16)),
          ],
        ),
        content: Text(
          'Sensor "$deviceId" saat ini sudah terhubung ke "$occupiedByName".\n\nSatu sensor fisik hanya dapat digunakan untuk 1 greenhouse agar data tidak tumpang tindih. Harap putuskan koneksi di "$occupiedByName" terlebih dahulu jika ingin menggunakannya di greenhouse ini.',
          style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.ground,
            ),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  void _showSensorOfflineWarningDialog(String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.sensors_off_rounded, color: AppTheme.statusAlert, size: 24),
            SizedBox(width: 10),
            Text('Sensor Tidak Terdeteksi', style: TextStyle(color: AppTheme.ink, fontSize: 16)),
          ],
        ),
        content: Text(
          'Perangkat "$deviceId" tidak ditemukan atau belum aktif mengirim data di Firebase Realtime Database.\n\nPastikan modul NodeMCU ESP8266 Anda sudah dinyalakan, terhubung ke internet/WiFi, dan telah mengirim data sensor.',
          style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.statusAlert,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectIot() async {
    if (_currentGreenhouse.id == null) return;
    setState(() => _isLoading = true);
    try {
      await _greenhouseService.updateIotDevice(
        id: _currentGreenhouse.id!,
        iotDeviceId: '',
      );
      final updated = _currentGreenhouse.copyWith(clearIotDevice: true);
      if (mounted) {
        setState(() {
          _currentGreenhouse = updated;
          _iotData = null;
          _isLoading = false;
        });
        _iotTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Koneksi perangkat IoT berhasil diputus.'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memutuskan: $e'), backgroundColor: AppTheme.statusAlert),
        );
      }
    }
  }

  void _showIotConfigSheet() {
    final controller = TextEditingController(text: _currentGreenhouse.iotDeviceId ?? '');
    final presets = ['GH_01', 'GH_02', 'GH_03'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Map<String, String> occupiedMap = {};
        bool isLoadingOccupied = true;
        bool isCheckingStatus = false;
        bool? isDetectedOnline;
        Map<String, double>? previewData;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            void runCheck(String id) async {
              final sanitized = id.trim();
              if (sanitized.isEmpty) {
                setSheetState(() {
                  isDetectedOnline = null;
                  previewData = null;
                });
                return;
              }

              setSheetState(() {
                isCheckingStatus = true;
              });

              // Jika sedang dipakai oleh greenhouse lain, tidak perlu cek live RTDB
              final lower = sanitized.toLowerCase();
              if (occupiedMap.containsKey(lower)) {
                setSheetState(() {
                  isCheckingStatus = false;
                  isDetectedOnline = false;
                });
                return;
              }

              final telemetry = await _greenhouseService.fetchLiveIotTelemetry(sanitized);
              if (context.mounted) {
                setSheetState(() {
                  isCheckingStatus = false;
                  isDetectedOnline = telemetry != null;
                  previewData = telemetry;
                });
              }
            }

            if (isLoadingOccupied) {
              _greenhouseService.fetchGreenhouses().then((all) {
                final map = <String, String>{};
                for (final gh in all) {
                  if (gh.id != _currentGreenhouse.id &&
                      gh.iotDeviceId != null &&
                      gh.iotDeviceId!.trim().isNotEmpty) {
                    map[gh.iotDeviceId!.trim().toLowerCase()] = gh.name;
                  }
                }
                if (context.mounted) {
                  setSheetState(() {
                    occupiedMap = map;
                    isLoadingOccupied = false;
                  });
                  if (controller.text.trim().isNotEmpty) {
                    runCheck(controller.text.trim());
                  }
                }
              });
            }

            final currentInput = controller.text.trim();
            final isOccupiedByOther = currentInput.isNotEmpty &&
                occupiedMap.containsKey(currentInput.toLowerCase());
            final occupiedByName = isOccupiedByOther ? occupiedMap[currentInput.toLowerCase()] : null;

            final canSubmit = currentInput.isNotEmpty &&
                !isOccupiedByOther &&
                !isCheckingStatus &&
                isDetectedOnline == true;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.panelElevated,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.borderQuiet,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.sensors_rounded, color: AppTheme.accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Konfigurasi Modul IoT',
                                style: TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '1 Sensor hanya untuk 1 Greenhouse',
                                style: AppTheme.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('ID Perangkat (Device ID)', style: AppTheme.caption),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Misal: GH_01 atau GH_02',
                        hintStyle: const TextStyle(color: AppTheme.inkTertiary, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.panel,
                        prefixIcon: const Icon(Icons.memory_rounded, color: AppTheme.accent, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 20),
                          tooltip: 'Cek Status Sensor',
                          onPressed: () => runCheck(controller.text),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.borderQuiet),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.borderQuiet),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.accent),
                        ),
                      ),
                      onChanged: (val) {
                        setSheetState(() {});
                        runCheck(val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Preset Sensor Cepat:', style: TextStyle(color: AppTheme.inkSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: presets.map((preset) {
                        final isSel = controller.text.trim().toLowerCase() == preset.toLowerCase();
                        final isUsedOther = occupiedMap.containsKey(preset.toLowerCase());
                        final isCurrent = _currentGreenhouse.iotDeviceId?.toLowerCase() == preset.toLowerCase();

                        String chipLabel = preset;
                        if (isUsedOther) {
                          chipLabel = '$preset (Terpakai)';
                        } else if (isCurrent) {
                          chipLabel = '$preset (Aktif)';
                        }

                        return ChoiceChip(
                          label: Text(chipLabel),
                          selected: isSel,
                          selectedColor: isUsedOther ? Colors.orange.withValues(alpha: 0.3) : AppTheme.accent,
                          backgroundColor: AppTheme.panel,
                          labelStyle: TextStyle(
                            color: isSel
                                ? (isUsedOther ? Colors.orange : AppTheme.ground)
                                : (isUsedOther ? AppTheme.inkTertiary : AppTheme.ink),
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSel
                                ? (isUsedOther ? Colors.orange : AppTheme.accent)
                                : AppTheme.borderQuiet,
                          ),
                          onSelected: (_) {
                            controller.text = preset;
                            setSheetState(() {});
                            runCheck(preset);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // ── Status Banner (Realtime Feedback) ──
                    if (isCheckingStatus) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderQuiet),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Memeriksa sensor di Firebase RTDB...',
                              style: TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ] else if (isOccupiedByOther) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sensor "$currentInput" sedang digunakan oleh "$occupiedByName". Satu sensor hanya dapat dipasang pada 1 greenhouse.',
                                style: const TextStyle(color: Colors.orange, fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (currentInput.isNotEmpty && isDetectedOnline == false) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.statusAlert.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.statusAlert.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.statusAlert, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Perangkat "$currentInput" tidak ditemukan di Firebase Realtime Database. Pastikan modul IoT fisik menyala dan mengirim data.',
                                style: const TextStyle(color: AppTheme.statusAlert, fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (isDetectedOnline == true && previewData != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.statusOk.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.statusOk.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.statusOk, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sensor terdeteksi online! Suhu: ${previewData!['suhu']?.toStringAsFixed(1)}°C, Lembap: ${previewData!['kelembapan']?.toStringAsFixed(1)}%, Cahaya: ${previewData!['cahaya']?.toStringAsFixed(0)} lx.',
                                style: const TextStyle(color: AppTheme.statusOk, fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderQuiet),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppTheme.inkTertiary, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pilih sensor yang aktif dan belum digunakan oleh greenhouse lain.',
                                style: TextStyle(color: AppTheme.inkSecondary, fontSize: 11.5, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (_currentGreenhouse.hasIotDevice) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _disconnectIot();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.statusAlert,
                                side: const BorderSide(color: AppTheme.statusAlert),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Putuskan', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: !canSubmit
                                ? null
                                : () {
                                    final deviceId = controller.text.trim();
                                    Navigator.pop(ctx);
                                    _saveIotDevice(deviceId);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.ground,
                              disabledBackgroundColor: AppTheme.borderQuiet,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(
                              _currentGreenhouse.hasIotDevice ? 'Simpan Perubahan' : 'Hubungkan Perangkat',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIotStatusCard() {
    final hasIot = _currentGreenhouse.hasIotDevice;
    final deviceId = _currentGreenhouse.iotDeviceId ?? '';
    final hasLiveData = _iotData != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasIot
              ? (hasLiveData ? AppTheme.statusOk.withValues(alpha: 0.4) : AppTheme.accent.withValues(alpha: 0.4))
              : AppTheme.borderQuiet,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: hasIot
                      ? AppTheme.statusOk.withValues(alpha: 0.15)
                      : AppTheme.borderQuiet.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasIot ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                  color: hasIot ? AppTheme.statusOk : AppTheme.inkTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hasIot ? 'IoT NodeMCU: $deviceId' : 'IoT Belum Terhubung',
                            style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasIot) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasLiveData
                                  ? AppTheme.statusOk.withValues(alpha: 0.15)
                                  : Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: hasLiveData ? AppTheme.statusOk : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasLiveData ? 'ONLINE' : 'SYNC',
                                  style: TextStyle(
                                    color: hasLiveData ? AppTheme.statusOk : Colors.orange,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasIot
                          ? (hasLiveData
                              ? 'Sinkronisasi Realtime RTDB aktif (setiap 3 dtk)'
                              : 'Menghubungkan ke Realtime Database...')
                          : 'Hubungkan 1 modul ESP8266 untuk telemetri real-time',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              if (hasIot)
                IconButton(
                  tooltip: 'Segarkan Data Sensor',
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 20),
                  onPressed: _fetchIotData,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showIotConfigSheet,
                  icon: Icon(hasIot ? Icons.settings_rounded : Icons.add_link_rounded, size: 16),
                  label: Text(
                    hasIot ? 'Konfigurasi IoT' : 'Hubungkan IoT',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (hasIot) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _disconnectIot,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusAlert,
                    side: BorderSide(color: AppTheme.statusAlert.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Putus', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _iotTimer?.cancel();
    _plantTypeController.dispose();
    _varietyController.dispose();
    _soilTypeController.dispose();
    super.dispose();
  }

  // Simpan Konfigurasi Tanaman ke Firebase
  Future<void> _saveConfiguration() async {
    final plantType = _plantTypeController.text.trim();
    final variety = _varietyController.text.trim();
    final soilType = _soilTypeController.text.trim();

    if (plantType.isEmpty || variety.isEmpty || soilType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap lengkapi jenis tanaman, varietas, dan jenis tanah.'),
          backgroundColor: AppTheme.statusAlert,
        ),
      );
      return;
    }

    if (_currentGreenhouse.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID Greenhouse tidak valid.'),
          backgroundColor: AppTheme.statusAlert,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _greenhouseService.updatePlantConfig(
        id: _currentGreenhouse.id!,
        plantType: plantType,
        plantVariety: variety,
        soilType: soilType,
        plantingDate: _selectedPlantingDate,
      );

      final updated = _currentGreenhouse.copyWith(
        plantType: plantType,
        plantVariety: variety,
        soilType: soilType,
        plantingDate: _selectedPlantingDate,
      );

      if (mounted) {
        setState(() {
          _currentGreenhouse = updated;
          _isEditing = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.panelElevated,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.statusOk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Konfigurasi budidaya "$plantType - $variety" berhasil disimpan!',
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error save plant config: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan ke Firebase: $e'),
            backgroundColor: AppTheme.statusAlert,
          ),
        );
      }
    }
  }

  // Reset Konfigurasi Tanaman
  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.statusAlert, size: 28),
            SizedBox(width: 10),
            Text(
              'Reset Konfigurasi?',
              style: TextStyle(color: AppTheme.ink, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Tindakan ini akan mengosongkan data tanaman, varietas, dan jenis tanah pada greenhouse ini. Anda dapat mengaturnya kembali dari awal.',
          style: TextStyle(color: AppTheme.inkSecondary, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.inkTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.statusAlert,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ya, Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && _currentGreenhouse.id != null) {
      setState(() => _isLoading = true);
      try {
        await _greenhouseService.resetPlantConfig(_currentGreenhouse.id!);
        if (mounted) {
          setState(() {
            _currentGreenhouse = _currentGreenhouse.copyWith(clearPlantConfig: true);
            _plantTypeController.clear();
            _varietyController.clear();
            _soilTypeController.clear();
            _isEditing = false;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konfigurasi tanaman berhasil direset ke pengaturan awal.'),
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal reset: $e'),
              backgroundColor: AppTheme.statusAlert,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = _currentGreenhouse.isConfigured && !_isEditing;

    return Scaffold(
      backgroundColor: AppTheme.ground,
      appBar: AppBar(
        backgroundColor: AppTheme.ground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.ink, size: 20),
          onPressed: () => Navigator.pop(context, _currentGreenhouse),
        ),
        title: Text(
          _currentGreenhouse.name,
          style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        actions: [
          if (hasConfig)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.ink),
              color: AppTheme.panelElevated,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (val == 'edit') {
                  setState(() {
                    _populateControllers();
                    _isEditing = true;
                  });
                } else if (val == 'reset') {
                  _confirmReset();
                } else if (val == 'iot') {
                  _showIotConfigSheet();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'iot',
                  child: Row(
                    children: [
                      Icon(Icons.sensors_rounded, color: AppTheme.accent, size: 18),
                      SizedBox(width: 10),
                      Text('Konfigurasi IoT', style: TextStyle(color: AppTheme.ink, fontSize: 13.5)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: AppTheme.accent, size: 18),
                      SizedBox(width: 10),
                      Text('Edit Tanaman & Tanah', style: TextStyle(color: AppTheme.ink, fontSize: 13.5)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt_rounded, color: AppTheme.statusAlert, size: 18),
                      SizedBox(width: 10),
                      Text('Reset Konfigurasi', style: TextStyle(color: AppTheme.statusAlert, fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Info Singkat Greenhouse (Banner Header) ──
                _buildGreenhouseHeaderCard(),
                const SizedBox(height: 20),

                // ── Kondisional: Tampilkan Form Pengaturan Awal ATAU Dashboard Budidaya ──
                if (!hasConfig) ...[
                  _buildSetupForm(),
                ] else ...[
                  _buildConfiguredDashboard(),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header Card Detail Unit ──
  Widget _buildGreenhouseHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderQuiet),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.home_work_rounded, color: AppTheme.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentGreenhouse.name,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.square_foot_rounded, color: AppTheme.inkTertiary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentGreenhouse.area.toStringAsFixed(1)} m²',
                      style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_rounded, color: AppTheme.accent, size: 14),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '${_currentGreenhouse.latitude.toStringAsFixed(4)}, ${_currentGreenhouse.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
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

  // ── Form Pengaturan Awal / Edit Konfigurasi ──
  Widget _buildSetupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner Penjelasan
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.panelElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _isEditing ? 'EDIT KONFIGURASI' : 'PENGATURAN AWAL',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_isEditing)
                    TextButton(
                      onPressed: () => setState(() => _isEditing = false),
                      child: const Text('Batal', style: TextStyle(color: AppTheme.inkTertiary, fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isEditing ? 'Ubah Data Budidaya Greenhouse' : 'Setting Tanaman & Media Tanah',
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tentukan jenis tanaman, varietas spesifik, dan media tanah. Pengaturan ini hanya perlu dilakukan satu kali di awal dan dapat diedit kembali kapan saja.',
                style: TextStyle(
                  color: AppTheme.inkSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // 1. Jenis Tanaman
        const Row(
          children: [
            Icon(Icons.eco_rounded, color: AppTheme.accent, size: 18),
            SizedBox(width: 8),
            Text(
              '1. Jenis Tanaman',
              style: TextStyle(color: AppTheme.ink, fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popularPlants.map((plant) {
            final isSelected = _plantTypeController.text.trim().toLowerCase() ==
                (plant['name'] as String).toLowerCase();
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(plant['icon'] as String, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(plant['name'] as String),
                ],
              ),
              selected: isSelected,
              selectedColor: AppTheme.accent,
              backgroundColor: AppTheme.panel,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.ground : AppTheme.ink,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12.5,
              ),
              side: BorderSide(
                color: isSelected ? AppTheme.accent : AppTheme.borderQuiet,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _plantTypeController.text = plant['name'] as String;
                    // Auto-select rekomendasi varietas pertama jika kosong
                    final varieties = plant['varieties'] as List<String>;
                    if (varieties.isNotEmpty) {
                      _varietyController.text = varieties.first;
                    }
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _plantTypeController,
          style: const TextStyle(color: AppTheme.ink, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Atau ketik jenis tanaman lainnya...',
            hintStyle: const TextStyle(color: AppTheme.inkTertiary, fontSize: 12.5),
            filled: true,
            fillColor: AppTheme.panel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // 2. Varietas / Jenis Spesifik
        const Row(
          children: [
            Icon(Icons.local_florist_rounded, color: AppTheme.accent, size: 18),
            SizedBox(width: 8),
            Text(
              '2. Varietas / Kultivar Tanaman',
              style: TextStyle(color: AppTheme.ink, fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildVarietyRecommendations(),
        const SizedBox(height: 10),
        TextField(
          controller: _varietyController,
          style: const TextStyle(color: AppTheme.ink, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Contoh: Cherry Ruby, Inthanon RZ, dsb.',
            hintStyle: const TextStyle(color: AppTheme.inkTertiary, fontSize: 12.5),
            filled: true,
            fillColor: AppTheme.panel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 3. Jenis Tanah / Media Tanam
        const Row(
          children: [
            Icon(Icons.layers_rounded, color: AppTheme.accent, size: 18),
            SizedBox(width: 8),
            Text(
              '3. Jenis Tanah / Media Tanam',
              style: TextStyle(color: AppTheme.ink, fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popularSoilTypes.map((soil) {
            final isSelected = _soilTypeController.text.trim().toLowerCase() == soil.toLowerCase();
            return ChoiceChip(
              label: Text(soil),
              selected: isSelected,
              selectedColor: AppTheme.accent,
              backgroundColor: AppTheme.panel,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.ground : AppTheme.ink,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected ? AppTheme.accent : AppTheme.borderQuiet,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _soilTypeController.text = soil);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _soilTypeController,
          style: const TextStyle(color: AppTheme.ink, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Atau ketik komposisi jenis media tanam...',
            hintStyle: const TextStyle(color: AppTheme.inkTertiary, fontSize: 12.5),
            filled: true,
            fillColor: AppTheme.panel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderQuiet),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 4. Tanggal Tanam
        const Row(
          children: [
            Icon(Icons.calendar_month_rounded, color: AppTheme.accent, size: 18),
            SizedBox(width: 8),
            Text(
              '4. Tanggal Mulai Tanam',
              style: TextStyle(color: AppTheme.ink, fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedPlantingDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.accent,
                    surface: AppTheme.panelElevated,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              setState(() => _selectedPlantingDate = picked);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderQuiet),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_rounded, color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  _formatFullDate(_selectedPlantingDate),
                  style: const TextStyle(color: AppTheme.ink, fontSize: 13.5),
                ),
                const Spacer(),
                const Text('Pilih', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Tombol Simpan
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _saveConfiguration,
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              _isEditing ? 'Perbarui Konfigurasi' : 'Simpan & Terapkan Konfigurasi',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.ground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVarietyRecommendations() {
    final currentPlant = _plantTypeController.text.trim().toLowerCase();
    final matchedPlant = _popularPlants.firstWhere(
      (p) => (p['name'] as String).toLowerCase() == currentPlant,
      orElse: () => {},
    );

    if (matchedPlant.isEmpty) {
      return const SizedBox.shrink();
    }

    final varieties = matchedPlant['varieties'] as List<String>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rekomendasi varietas unggul:',
          style: TextStyle(color: AppTheme.inkTertiary, fontSize: 11.5),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: varieties.map((v) {
            final isSelected = _varietyController.text.trim() == v;
            return ActionChip(
              label: Text(v),
              backgroundColor: isSelected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.panelElevated,
              side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.borderQuiet),
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.accent : AppTheme.inkSecondary,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onPressed: () {
                setState(() => _varietyController.text = v);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Dashboard Budidaya Aktif (Setelah Disetting) ──
  Widget _buildConfiguredDashboard() {
    final plant = _currentGreenhouse.plantType ?? '-';
    final variety = _currentGreenhouse.plantVariety ?? '-';
    final soil = _currentGreenhouse.soilType ?? '-';
    final date = _currentGreenhouse.plantingDate;

    // Menghitung Hari Setelah Tanam (HST)
    int daysAfterPlanting = 0;
    if (date != null) {
      daysAfterPlanting = DateTime.now().difference(date).inDays;
      if (daysAfterPlanting < 0) daysAfterPlanting = 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Card Status Budidaya Utama ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AppTheme.panelElevated,
                AppTheme.panel,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.statusOk.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.statusOk, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'SIKLUS TANAM AKTIF',
                          style: TextStyle(
                            color: AppTheme.statusOk,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _populateControllers();
                        _isEditing = true;
                      });
                    },
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit', style: TextStyle(fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        _getPlantEmoji(plant),
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plant,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Varietas: $variety',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.layers_outlined, color: AppTheme.inkTertiary, size: 14),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                soil,
                                style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.borderQuiet, height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Umur Tanaman', style: AppTheme.caption),
                      const SizedBox(height: 3),
                      Text(
                        'Hari ke-$daysAfterPlanting (HST)',
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Tanggal Tanam', style: AppTheme.caption),
                      const SizedBox(height: 3),
                      Text(
                        date != null ? _formatShortDate(date) : '-',
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Card Status Perangkat IoT Greenhouse ──
        _buildIotStatusCard(),

        // ── Telemetri Real-Time Khusus Greenhouse Ini (Hanya Tampil Jika Terhubung IoT) ──
        if (_currentGreenhouse.hasIotDevice) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Telemetri Mikro Lahan', style: AppTheme.sectionTitle),
              if (_iotData != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.statusOk.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded, color: AppTheme.statusOk, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        'NODE ${_currentGreenhouse.iotDeviceId}',
                        style: const TextStyle(
                          color: AppTheme.statusOk,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Data sensor lingkungan real-time dari modul NodeMCU (${_currentGreenhouse.iotDeviceId}).',
            style: AppTheme.bodyMuted,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTelemetryMetric(
                  label: 'Suhu Udara',
                  value: _iotData?['suhu'] != null
                      ? '${_iotData!['suhu']!.toStringAsFixed(1)}°C'
                      : '--',
                  subtext: _iotData?['suhu'] != null
                      ? 'Sensor DHT22 Live'
                      : 'Menunggu data...',
                  icon: Icons.thermostat_rounded,
                  isGood: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTelemetryMetric(
                  label: 'Kelembapan Udara',
                  value: _iotData?['kelembapan'] != null
                      ? '${_iotData!['kelembapan']!.toStringAsFixed(1)}%'
                      : '--',
                  subtext: _iotData?['kelembapan'] != null
                      ? 'Sensor DHT22 Live'
                      : 'Menunggu data...',
                  icon: Icons.water_drop_rounded,
                  isGood: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTelemetryMetric(
            label: 'Intensitas Cahaya',
            value: _iotData?['cahaya'] != null
                ? '${_iotData!['cahaya']!.toStringAsFixed(0)} lx'
                : '--',
            subtext: _iotData?['cahaya'] != null
                ? 'Sensor Digital Light Meter BH1750 Live'
                : 'Menunggu data...',
            icon: Icons.wb_sunny_rounded,
            isGood: true,
          ),
          const SizedBox(height: 22),
        ],

        // ── Rekomendasi Agronomi Pintar ──
        const Text('Rekomendasi Agronomi Spesifik', style: AppTheme.sectionTitle),
        const SizedBox(height: 4),
        Text(
          'Panduan presisi untuk $plant ($variety) pada media $soil.',
          style: AppTheme.bodyMuted,
        ),
        const SizedBox(height: 12),
        _buildAgronomyGuideCard(plant, variety, soil),
        const SizedBox(height: 22),

        // ── Aksi Cepat & Navigasi Terkait ──
        const Text('Aksi & Jadwal Perawatan', style: AppTheme.sectionTitle),
        const SizedBox(height: 12),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildTelemetryMetric({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required bool isGood,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderQuiet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtext,
            style: const TextStyle(color: AppTheme.inkTertiary, fontSize: 10.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAgronomyGuideCard(String plant, String variety, String soil) {
    String guide = 'Pertahankan kelembapan media tanam secara berkala. Berikan nutrisi berimbang NPK sesuai fase vegetatif.';
    if (plant.toLowerCase().contains('tomat')) {
      guide = 'Tomat membutuhkan asupan kalsium nitrat untuk mencegah blossom end rot (busuk pantat buah). Pada media $soil, pastikan drainase lancar agar akar tidak busuk.';
    } else if (plant.toLowerCase().contains('melon')) {
      guide = 'Melon $variety sangat responsif terhadap pencahayaan tinggi. Jaga kelembapan media $soil stabil dan kurangi penyiraman saat mendekati fase pematangan buah untuk meningkatkan kadar gula (brix).';
    } else if (plant.toLowerCase().contains('cabai')) {
      guide = 'Pantau kelembapan tanah agar tidak terlalu basah guna mencegah layu fusarium. Gunakan perangkap kuning untuk mendeteksi kutu kebul atau thrips lebih awal.';
    } else if (plant.toLowerCase().contains('selada')) {
      guide = 'Selada sensitif terhadap suhu panas (bolting). Jaga sirkulasi udara dan pertahankan suhu di bawah 26°C dengan mist blower.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderQuiet),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.psychology_outlined, color: AppTheme.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catatan Budidaya Presisi',
                  style: TextStyle(
                    color: AppTheme.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  guide,
                  style: const TextStyle(
                    color: AppTheme.inkSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        ListTile(
          tileColor: AppTheme.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppTheme.borderQuiet),
          ),
          leading: const Icon(Icons.event_note_rounded, color: AppTheme.accent),
          title: const Text('Buka Jadwal Perawatan Tanaman', style: TextStyle(color: AppTheme.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: const Text('Jadwal pemupukan, semprot, dan panen', style: AppTheme.caption),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.inkTertiary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JadwalTanamPage()),
            );
          },
        ),
      ],
    );
  }

  String _getPlantEmoji(String plant) {
    final lower = plant.toLowerCase();
    if (lower.contains('tomat')) return '🍅';
    if (lower.contains('cabai') || lower.contains('cabe')) return '🌶️';
    if (lower.contains('melon')) return '🍈';
    if (lower.contains('selada')) return '🥬';
    if (lower.contains('stroberi') || lower.contains('strawberry')) return '🍓';
    if (lower.contains('terong')) return '🍆';
    if (lower.contains('timun')) return '🥒';
    if (lower.contains('bayam')) return '🌱';
    return '🌿';
  }

  String _formatFullDate(DateTime date) {
    try {
      return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date);
    } catch (_) {
      try {
        return DateFormat('EEEE, dd MMMM yyyy').format(date);
      } catch (_) {
        return '${date.day}/${date.month}/${date.year}';
      }
    }
  }

  String _formatShortDate(DateTime date) {
    try {
      return DateFormat('dd MMM yyyy', 'id_ID').format(date);
    } catch (_) {
      try {
        return DateFormat('dd MMM yyyy').format(date);
      } catch (_) {
        return '${date.day}/${date.month}/${date.year}';
      }
    }
  }
}
