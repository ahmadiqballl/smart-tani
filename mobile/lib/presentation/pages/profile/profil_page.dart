import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/greenhouse_model.dart';
import '../../../services/greenhouse_service.dart';
import '../../../views/add_greenhouse_sheet.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/smart_tani_logo.dart';
import '../auth/login_page.dart';
import '../blockchain/blockchain_page.dart';
import '../greenhouse/greenhouse_accumulation_map_page.dart';
import '../greenhouse/greenhouse_detail_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  final GreenhouseService _greenhouseService = GreenhouseService();
  final MapController _miniMapController = MapController();

  List<GreenhouseModel> _userGreenhouses = [];
  bool _isLoadingGh = true;

  @override
  void initState() {
    super.initState();
    _loadUserGreenhouses();
  }

  Future<void> _loadUserGreenhouses() async {
    setState(() => _isLoadingGh = true);
    try {
      final list = await _greenhouseService.fetchGreenhouses();
      if (mounted) {
        setState(() {
          _userGreenhouses = list;
          _isLoadingGh = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGh = false);
      }
    }
  }

  double get _totalArea =>
      _userGreenhouses.fold<double>(0.0, (acc, gh) => acc + gh.area);

  LatLng get _centerPoint {
    if (_userGreenhouses.isEmpty) return const LatLng(-7.7828, 110.3670);
    double latSum = 0;
    double lngSum = 0;
    int count = 0;
    for (final gh in _userGreenhouses) {
      if (gh.latitude != 0.0 && gh.longitude != 0.0) {
        latSum += gh.latitude;
        lngSum += gh.longitude;
        count++;
      }
    }
    if (count == 0) return const LatLng(-7.7828, 110.3670);
    return LatLng(latSum / count, lngSum / count);
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
          'Apakah Anda yakin ingin menghapus "${gh.name}"?\nData greenhouse, konfigurasi budidaya, dan sensor IoT akan dihapus permanen.',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              content: Text(
                'Greenhouse "${gh.name}" berhasil dihapus.',
                style: const TextStyle(color: AppTheme.ink),
              ),
            ),
          );
          _loadUserGreenhouses();
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

  /// FR-05: Ganti foto profil dari Kamera atau Galeri
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final auth = context.read<AuthProvider>();
        await auth.updatePhoto(picked.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Foto profil berhasil diperbarui!',
                style: TextStyle(color: AppTheme.darkForest, fontWeight: FontWeight.w700),
              ),
              backgroundColor: AppTheme.neonLime,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: const Color(0xFFE74C3C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ganti Foto Profil',
                style: TextStyle(
                  color: AppTheme.creamWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pilih sumber foto untuk profil petani Anda',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.darkForest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.camera_alt_rounded, color: AppTheme.neonLime, size: 28),
                            SizedBox(height: 8),
                            Text(
                              'Kamera',
                              style: TextStyle(
                                color: AppTheme.creamWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.darkForest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.photo_library_rounded, color: AppTheme.neonLime, size: 28),
                            SizedBox(height: 8),
                            Text(
                              'Galeri',
                              style: TextStyle(
                                color: AppTheme.creamWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.ground,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header Bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profil Akun',
                          style: TextStyle(
                            color: AppTheme.creamWhite,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Identitas Petani & Manajemen Greenhouse',
                          style: TextStyle(
                            color: AppTheme.pastelLime.withValues(alpha: 0.75),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const SmartTaniLogo(
                      size: 34,
                    ),
                  ],
                ),
              ),

              // ── Content ──
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    children: [
                      // ── Profile Card dengan Foto & Tombol Edit ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                            width: 1.2,
                          ),

                        ),
                        child: Column(
                          children: [
                            // Avatar Foto / Inisial
                            Stack(
                              children: [
                                Container(
                                  width: 86,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    color: AppTheme.panelElevated,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: AppTheme.neonLime.withValues(alpha: 0.7),
                                      width: 2,
                                    ),

                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: user?.fotoPath != null &&
                                          File(user!.fotoPath!).existsSync()
                                      ? Image.file(
                                          File(user.fotoPath!),
                                          fit: BoxFit.cover,
                                        )
                                      : Center(
                                          child: Text(
                                            (user?.nama.isNotEmpty == true)
                                                ? user!.nama[0].toUpperCase()
                                                : 'P',
                                            style: const TextStyle(
                                              color: AppTheme.neonLime,
                                              fontSize: 38,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: _showImagePickerSheet,
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: const BoxDecoration(
                                        color: AppTheme.neonLime,
                                        shape: BoxShape.circle,

                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        color: AppTheme.darkForest,
                                        size: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              user?.nama ?? 'Petani Smart Tani',
                              style: const TextStyle(
                                color: AppTheme.creamWhite,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? 'petani@tanigreen.id',
                              style: const TextStyle(
                                color: AppTheme.textGrey,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.neonLime.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.neonLime.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_user_rounded,
                                      color: AppTheme.neonLime, size: 14),
                                  SizedBox(width: 5),
                                  Text(
                                    'Petani Riset Terverifikasi',
                                    style: TextStyle(
                                      color: AppTheme.neonLime,
                                      fontWeight: FontWeight.w700,
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

                      // ── Saldo Token Reward Card (FR-13) ──
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const BlockchainPage()),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.token_rounded,
                                  color: Colors.amber,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Saldo Token Reward Tani',
                                      style: TextStyle(
                                        color: AppTheme.textGrey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${user?.saldoToken ?? 0} Token Tani',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    const Text(
                                      'Gunakan untuk konsultasi Asisten AI Gemini (1 Token / tanya)',
                                      style: TextStyle(
                                        color: AppTheme.pastelLime,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppTheme.textGrey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── PETA AKUMULASI GREENHOUSE ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.map_rounded,
                                        color: AppTheme.neonLime, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Peta Akumulasi Greenhouse',
                                      style: TextStyle(
                                        color: AppTheme.creamWhite,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => GreenhouseAccumulationMapPage(
                                          initialGreenhouses: _userGreenhouses,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.fullscreen_rounded,
                                      size: 16, color: AppTheme.neonLime),
                                  label: const Text(
                                    'Layar Penuh',
                                    style: TextStyle(
                                      color: AppTheme.neonLime,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Ringkasan Akumulasi Lahan
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.darkForest,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.emeraldGreen.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Total Unit',
                                          style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_userGreenhouses.length} Unit',
                                          style: const TextStyle(
                                            color: AppTheme.neonLime,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.darkForest,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.emeraldGreen.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Akumulasi Luas',
                                          style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_totalArea.toStringAsFixed(0)} m²',
                                          style: const TextStyle(
                                            color: Colors.amber,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Mini Interactive Map Preview
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                height: 160,
                                width: double.infinity,
                                child: Stack(
                                  children: [
                                    FlutterMap(
                                      mapController: _miniMapController,
                                      options: MapOptions(
                                        initialCenter: _centerPoint,
                                        initialZoom: 13.0,
                                        interactionOptions: const InteractionOptions(
                                          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                                        ),
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.tanigreen.mobile',
                                        ),
                                        MarkerLayer(
                                          markers: _userGreenhouses.map((gh) {
                                            final lat = gh.latitude != 0.0 ? gh.latitude : -7.7828;
                                            final lng = gh.longitude != 0.0 ? gh.longitude : 110.3670;
                                            return Marker(
                                              point: LatLng(lat, lng),
                                              width: 32,
                                              height: 32,
                                              child: const Icon(
                                                Icons.location_on_rounded,
                                                color: AppTheme.neonLime,
                                                size: 30,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => GreenhouseAccumulationMapPage(
                                                  initialGreenhouses: _userGreenhouses,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.darkForest.withValues(alpha: 0.9),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.neonLime.withValues(alpha: 0.6)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.open_in_new_rounded, size: 13, color: AppTheme.neonLime),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Buka Peta Detail',
                                                  style: TextStyle(
                                                    color: AppTheme.creamWhite,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── DAFTAR GREENHOUSE MILIK PENGGUNA ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.roofing_rounded,
                                        color: AppTheme.neonLime, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Daftar Greenhouse Saya',
                                      style: TextStyle(
                                        color: AppTheme.creamWhite,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.textGrey),
                                      tooltip: 'Segarkan data',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _loadUserGreenhouses,
                                    ),
                                    const SizedBox(width: 4),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final result = await AddGreenhouseSheet.show(context);
                                        if (result == true) {
                                          _loadUserGreenhouses();
                                        }
                                      },
                                      icon: const Icon(Icons.add_rounded, size: 14),
                                      label: const Text('Tambah'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.neonLime,
                                        foregroundColor: AppTheme.darkForest,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_isLoadingGh)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.neonLime,
                                  ),
                                ),
                              )
                            else if (_userGreenhouses.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkForest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        color: AppTheme.textGrey, size: 24),
                                    SizedBox(height: 8),
                                    Text(
                                      'Belum ada greenhouse terdaftar.',
                                      style: TextStyle(
                                          color: AppTheme.creamWhite, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Tekan tombol "+ Tambah" di atas untuk mendaftarkan unit greenhouse pertama Anda.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _userGreenhouses.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (ctx, idx) {
                                  final gh = _userGreenhouses[idx];
                                  final variety = gh.plantVariety?.isNotEmpty == true
                                      ? gh.plantVariety!
                                      : (gh.plantType?.isNotEmpty == true ? gh.plantType! : 'Belum Dikonfigurasi');

                                  return InkWell(
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => GreenhouseDetailPage(greenhouse: gh),
                                        ),
                                      );
                                      _loadUserGreenhouses();
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppTheme.darkForest,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppTheme.neonLime.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.roofing_rounded,
                                              color: AppTheme.neonLime,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  gh.name,
                                                  style: const TextStyle(
                                                    color: AppTheme.creamWhite,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Tanaman: $variety • Luas: ${gh.area.toStringAsFixed(0)} m²',
                                                  style: const TextStyle(
                                                    color: AppTheme.textGrey,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                                                          ? Icons.wifi_rounded
                                                          : Icons.wifi_off_rounded,
                                                      size: 12,
                                                      color: (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                                                          ? const Color(0xFF2ECC71)
                                                          : Colors.orange,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                                                          ? 'IoT: ${gh.iotDeviceId}'
                                                          : 'IoT Belum Terhubung',
                                                      style: TextStyle(
                                                        color: (gh.iotDeviceId != null && gh.iotDeviceId!.isNotEmpty)
                                                            ? const Color(0xFF2ECC71)
                                                            : Colors.orange,
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded,
                                                color: Color(0xFFFF5252), size: 20),
                                            tooltip: 'Hapus Greenhouse',
                                            onPressed: () => _confirmDeleteGreenhouse(gh),
                                          ),
                                          const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 14,
                                            color: AppTheme.textGrey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Security & Biometric Status (FR-01, FR-02) ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.fingerprint_rounded,
                                  color: AppTheme.neonLime,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Autentikasi Biometrik',
                                        style: TextStyle(
                                          color: AppTheme.creamWhite,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'Login cepat sidik jari / Face Unlock',
                                        style: TextStyle(
                                          color: AppTheme.textGrey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: user?.biometrikAktif ?? false,
                                  activeThumbColor: AppTheme.neonLime,
                                  activeTrackColor: AppTheme.neonLime.withValues(alpha: 0.4),
                                  onChanged: (val) async {
                                    final success = await authProvider.setBiometricEnabled(val);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? (val
                                                    ? 'Autentikasi biometrik berhasil diaktifkan.'
                                                    : 'Autentikasi biometrik dinonaktifkan.')
                                                : 'Gagal memperbarui status biometrik.',
                                            style: const TextStyle(
                                              color: AppTheme.darkForest,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          backgroundColor: AppTheme.neonLime,
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const Divider(
                              color: Color(0xFF143B31),
                              height: 24,
                            ),
                            const Row(
                              children: [
                                Icon(
                                  Icons.security_rounded,
                                  color: AppTheme.pastelLime,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Keamanan Sandi Enkripsi Custom',
                                        style: TextStyle(
                                          color: AppTheme.creamWhite,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'Salt kustom + permutasi acak lokal',
                                        style: TextStyle(
                                          color: AppTheme.textGrey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.neonLime,
                                  size: 18,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Logout Button ──
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppTheme.cardSurface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                                  ),
                                ),
                                title: const Text(
                                  'Konfirmasi Keluar',
                                  style: TextStyle(color: AppTheme.creamWhite),
                                ),
                                content: const Text(
                                  'Apakah Anda yakin ingin keluar dari akun Smart Tani ini?',
                                  style: TextStyle(color: AppTheme.textGrey),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Batal',
                                        style: TextStyle(color: AppTheme.textGrey)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE74C3C),
                                    ),
                                    child: const Text('Keluar',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true && context.mounted) {
                              await authProvider.logout();
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginPage()),
                                  (route) => false,
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFE74C3C).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFFFF6B6B),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 20),
                          label: const Text(
                            'Keluar dari Akun',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
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
}
