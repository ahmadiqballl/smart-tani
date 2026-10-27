import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/greenhouse_model.dart';
import '../../../services/greenhouse_service.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/smart_tani_logo.dart';
import '../greenhouse/greenhouse_detail_page.dart';
import '../greenhouse/greenhouse_map_page.dart';
import '../iot/iot_monitor_page.dart';
import '../iot/iot_monitoring_page.dart';
import '../ai_assistant/ai_assistant_page.dart';
import '../schedule/jadwal_tanam_page.dart';
import '../variety_plant/varietas_tanaman_page.dart';
import '../blockchain/blockchain_page.dart';
import '../game/edukasi_game_page.dart';
import '../search/pencarian_page.dart';
import '../../../views/add_greenhouse_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GreenhouseService _greenhouseService = GreenhouseService();

  List<GreenhouseModel> _greenhouses = [];
  bool _isLoadingGreenhouses = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadGreenhouses();
  }

  Future<void> _loadGreenhouses() async {
    setState(() => _isLoadingGreenhouses = true);
    try {
      final list = await _greenhouseService.fetchGreenhouses();
      if (mounted) {
        setState(() {
          _greenhouses = list;
          _isLoadingGreenhouses = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetch greenhouses: $e');
      if (mounted) setState(() => _isLoadingGreenhouses = false);
    }
  }

  Future<void> _openAddGreenhouse(BuildContext context) async {
    final result = await AddGreenhouseSheet.show(context);
    if (result == true) {
      _loadGreenhouses();
    }
  }

  Future<void> _confirmDeleteGreenhouse(GreenhouseModel gh) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.statusAlert, size: 24),
            SizedBox(width: 10),
            Text('Hapus Greenhouse?', style: TextStyle(color: AppTheme.ink, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${gh.name}"?\n\nData greenhouse, konfigurasi budidaya, dan sensor IoT akan dihapus permanen.',
          style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 13, height: 1.4),
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
            ),
            child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && gh.id != null) {
      try {
        await _greenhouseService.deleteGreenhouse(gh.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.panelElevated,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.statusOk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Greenhouse "${gh.name}" berhasil dihapus.',
                      style: const TextStyle(color: AppTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
          );
          _loadGreenhouses();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus greenhouse: $e'),
              backgroundColor: AppTheme.statusAlert,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      backgroundColor: AppTheme.ground,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Header (Brand & Operator Aktif) ──
              _buildHeader(context, user?.nama ?? 'Petani Unggul'),
              const SizedBox(height: 18),

              // ── Fitur Utama Paling Atas: Tambah Greenhouse (Firebase + OSM) ──
              _buildAddGreenhouseCard(context),
              const SizedBox(height: 20),

              // ── Fitur Baru: Daftar Unit Greenhouse (Maksimal 2, Expandable, Per-Greenhouse Config) ──
              _buildGreenhouseListSection(context),
              const SizedBox(height: 24),

              // ── 3. Operasi & Kontrol Lahan ──
              const Text(
                'Operasi & Kontrol Lahan',
                style: AppTheme.sectionTitle,
              ),
              const SizedBox(height: 6),
              const Text(
                'Alat presisi pemantauan lapangan, kalender perawatan, dan aktuator.',
                style: AppTheme.bodyMuted,
              ),
              const SizedBox(height: 14),
              _buildOperationsSection(context),
              const SizedBox(height: 28),

              // ── 4. Katalog & Ketertelusuran ──
              const Text(
                'Katalog & Ketertelusuran',
                style: AppTheme.sectionTitle,
              ),
              const SizedBox(height: 6),
              const Text(
                'Basis data agronomi, log panen terverifikasi, dan modul edukasi.',
                style: AppTheme.bodyMuted,
              ),
              const SizedBox(height: 14),
              _buildRecordsSection(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header Lahan ──
  Widget _buildHeader(BuildContext context, String name) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TaniGreen Agronomy Console',
                    style: AppTheme.caption,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: AppTheme.headline.copyWith(fontSize: 22),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        const SmartTaniLogo(
          size: 38,
        ),
      ],
    );
  }

  // ── Fitur Tambah Greenhouse (Firebase Firestore & OpenStreetMap) ──
  Widget _buildAddGreenhouseCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.panelElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openAddGreenhouse(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.add_home_work_rounded,
                        color: AppTheme.accent,
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'FITUR BARU',
                                  style: TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '• Cloud Firestore',
                                style: TextStyle(
                                  color: AppTheme.inkSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Tambah Greenhouse',
                            style: TextStyle(
                              color: AppTheme.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Daftarkan greenhouse baru dengan ukuran luas kuadrat dan penentuan titik koordinat langsung pada peta OpenStreetMap.',
                  style: TextStyle(
                    color: AppTheme.inkSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderQuiet),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.map_rounded,
                              size: 14,
                              color: AppTheme.accent,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Pin Peta OSM • Luas (m²)',
                                style: TextStyle(
                                  color: AppTheme.inkTertiary,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () => _openAddGreenhouse(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'Tambah',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.ground,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Daftar Unit Greenhouse Terdaftar (Maksimal 2, Expandable & Navigasi ke Detail) ──
  Widget _buildGreenhouseListSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Unit Greenhouse Anda',
              style: AppTheme.sectionTitle,
            ),
            Row(
              children: [
                if (_greenhouses.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_greenhouses.length} Unit',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.inkTertiary),
                  tooltip: 'Segarkan data',
                  onPressed: _loadGreenhouses,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 3),
        const Text(
          'Daftar unit yang tersimpan di Firebase. Ketuk unit untuk menyetting tanaman, varietas, dan jenis tanah.',
          style: AppTheme.bodyMuted,
        ),
        const SizedBox(height: 12),

        if (_isLoadingGreenhouses)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderQuiet),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          )
        else if (_greenhouses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderQuiet),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.home_work_outlined,
                  size: 36,
                  color: AppTheme.inkTertiary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Belum Ada Greenhouse Terdaftar',
                  style: TextStyle(
                    color: AppTheme.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tekan tombol "+ Tambah" di atas untuk mendaftarkan unit greenhouse pertama Anda.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
              ],
            ),
          )
        else ...[
          // Tampilkan maksimal 2 item jika belum di-expand
          ...(_isExpanded ? _greenhouses : _greenhouses.take(2)).map((gh) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildGreenhouseItemCard(gh),
            );
          }),

          // Tombol Show More / Show Less jika lebih dari 2 item
          if (_greenhouses.length > 2)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.accent,
                  size: 20,
                ),
                label: Text(
                  _isExpanded
                      ? 'Tampilkan Lebih Sedikit'
                      : 'Lihat Semua (${_greenhouses.length} Greenhouse)',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildGreenhouseItemCard(GreenhouseModel gh) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GreenhouseDetailPage(greenhouse: gh),
          ),
        );
        _loadGreenhouses();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: gh.isConfigured
                ? AppTheme.accent.withValues(alpha: 0.4)
                : AppTheme.borderQuiet,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: gh.isConfigured
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : AppTheme.panelElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: gh.isConfigured
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : AppTheme.borderQuiet,
                ),
              ),
              child: Center(
                child: Text(
                  gh.isConfigured ? _getPlantEmoji(gh.plantType ?? '') : '🏠',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          gh.name,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.panelElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${gh.area.toStringAsFixed(0)} m²',
                          style: const TextStyle(
                            color: AppTheme.inkSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: AppTheme.inkTertiary, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: AppTheme.panelElevated,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (val) {
                          if (val == 'delete') {
                            _confirmDeleteGreenhouse(gh);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'delete',
                            height: 36,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: AppTheme.statusAlert, size: 16),
                                SizedBox(width: 8),
                                Text('Hapus', style: TextStyle(color: AppTheme.statusAlert, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Badge status konfigurasi tanaman
                  if (gh.isConfigured) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.statusOk.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${gh.plantType} - ${gh.plantVariety}',
                            style: const TextStyle(
                              color: AppTheme.statusOk,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '• ${gh.soilType}',
                          style: const TextStyle(
                            color: AppTheme.inkTertiary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, color: Colors.amber, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Perlu Pengaturan Tanaman & Tanah',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.inkTertiary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
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

  // ── Modul Operasi Presisi ──
  Widget _buildOperationsSection(BuildContext context) {
    return Column(
      children: [
        _buildActionTile(
          context: context,
          icon: Icons.explore_outlined,
          title: 'Pemetaan Greenhouse & Kompas',
          description: 'Streaming live GPS lahan dan orientasi kompas hardware ke unit greenhouse.',
          badgeText: 'GPS & Sensor',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GreenhouseMapPage()),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionTile(
          context: context,
          icon: Icons.event_note_outlined,
          title: 'Jadwal Perawatan & Notifikasi',
          description: 'Pengingat otomatis pemupukan NPK, irigasi, dan kalender rotasi panen.',
          badgeText: 'Pengingat Lokal',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const JadwalTanamPage()),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionTile(
          context: context,
          icon: Icons.sensors_outlined,
          title: 'Telemetri & Aktuator IoT',
          description: 'Status instrumen aktuator, pompa irigasi otomatis, dan mist blower.',
          badgeText: 'Aktuator',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IoTMonitorPage()),
          ),
        ),
        const SizedBox(height: 10),
        _buildActionTile(
          context: context,
          icon: Icons.psychology_outlined,
          title: 'Asisten Agronomi & Suara',
          description: 'Konsultasi diagnosis hama, daun menguning, dan nutrisi via AI & suara.',
          badgeText: 'Gemini AI',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiAssistantPage()),
          ),
        ),
      ],
    );
  }

  // ── Modul Katalog & Ketertelusuran ──
  Widget _buildRecordsSection(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCompactCard(
                context: context,
                icon: Icons.spa_outlined,
                title: 'Varietas Tanaman',
                subtitle: 'Katalog bibit & siklus tanam',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VarietasTanamanPage()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildCompactCard(
                context: context,
                icon: Icons.search_outlined,
                title: 'Pencarian Tanaman',
                subtitle: 'Filter agronomis & hama',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PencarianPage()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildCompactCard(
                context: context,
                icon: Icons.verified_outlined,
                title: 'Paspor Panen Digital',
                subtitle: 'Sertifikat keterlacakan panen',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockchainPage()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildCompactCard(
                context: context,
                icon: Icons.sports_esports_outlined,
                title: 'Simulasi Edukasi',
                subtitle: 'Gamifikasi panen & kuis',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EdukasiGamePage()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IotMonitoringPage(
                greenhouse: const {
                  'id': 1,
                  'nama_greenhouse': 'Greenhouse Utama (A)',
                  'biaya_operasional_idr': 1500000.0,
                  'batas_suhu_maks': 35.0,
                  'batas_lembap_min': 40.0,
                },
                userId: context.read<AuthProvider>().currentUser?.id ?? 1,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonLime.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.public_rounded, color: AppTheme.neonLime, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kalkulator Valuasi & Potensi Ekspor (FR-06)',
                        style: TextStyle(color: AppTheme.creamWhite, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Simulasi nilai panen lokal vs ekspor (USD/EUR/GBP Live)',
                        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textGrey, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderQuiet,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.panelElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.borderQuiet,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.panelElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            color: AppTheme.inkSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.inkTertiary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.borderQuiet,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.panelElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.borderQuiet,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: AppTheme.ink,
                size: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTheme.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
