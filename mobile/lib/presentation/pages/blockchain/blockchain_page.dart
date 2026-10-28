import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_db/database_helper.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/custom_sub_app_bar.dart';

class BlockchainPage extends StatefulWidget {
  const BlockchainPage({super.key});

  @override
  State<BlockchainPage> createState() => _BlockchainPageState();
}

class _BlockchainPageState extends State<BlockchainPage> {
  List<Map<String, dynamic>> _blocks = [];
  bool _isLoading = true;
  bool _isVerifying = false;
  bool? _isChainValid;
  final Set<int> _expandedBlockIndices = {};
  bool _showExplanation = true;

  @override
  void initState() {
    super.initState();
    _loadBlockchain();
  }

  Future<void> _loadBlockchain() async {
    final logs = await DatabaseHelper.instance.getAllBlokLogs();
    if (logs.isEmpty) {
      // Inisialisasi Genesis Block sesuai FR-13
      const genesisData = 'Awal Mula Tanam (Genesis) - Inisialisasi Smart Greenhouse & Bibit Melon';
      const prevHash = '0000000000000000000000000000000000000000000000000000000000000000';
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final genesisHash = sha256.convert(utf8.encode('$genesisData$prevHash$timestamp')).toString();

      await DatabaseHelper.instance.insertBlokLog({
        'log_id': 0,
        'data_log': genesisData,
        'hash': genesisHash,
        'hash_sebelumnya': prevHash,
        'timestamp': timestamp,
      });

      final refreshed = await DatabaseHelper.instance.getAllBlokLogs();
      if (mounted) {
        setState(() {
          _blocks = refreshed;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _blocks = logs;
          _isLoading = false;
        });
      }
    }
  }

  /// FR-13: Verifikasi Integritas Rantai Hash ("Bukti Log Tidak Bisa Dimanipulasi")
  Future<void> _verifyChainIntegrity() async {
    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 600));

    bool valid = true;
    for (int i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final dataLog = block['data_log'] as String;
      final prevHash = block['hash_sebelumnya'] as String;
      final timestamp = block['timestamp'] as String;
      final currentHash = block['hash'] as String;

      // Hitung ulang hash: SHA-256(data log + hash_sebelumnya + timestamp)
      final expectedHash = sha256.convert(utf8.encode('$dataLog$prevHash$timestamp')).toString();

      if (currentHash != expectedHash) {
        valid = false;
        break;
      }

      // Validasi keterkaitan rantai dengan blok sebelumnya
      if (i > 0) {
        final previousBlock = _blocks[i - 1];
        if (prevHash != previousBlock['hash']) {
          valid = false;
          break;
        }
      }
    }

    if (mounted) {
      setState(() {
        _isVerifying = false;
        _isChainValid = valid;
      });
    }
  }

  /// FR-13: Catat Log Perawatan Baru & Buat Hash Block Baru + Reward Token
  Future<void> _showAddLogDialog() async {
    final textCtrl = TextEditingController();
    final actionOptions = [
      'Pemberian Nutrisi AB Mix Melon (EC 2.2 mS/cm)',
      'Polinasi Bunga Betina Melon Inthanon',
      'Penyemprotan Biopestisida Nabati Daun Nimba',
      'Penyiraman Otomatis & Cek Tingkat Kelembapan',
      'Pembersihan Filter Irigasi Tetes Drip Sistem',
      'Pemangkasan Tunas Air & Daun Kuning',
      'Pengecekan Sensor Suhu & Kelembapan ESP32',
    ];
    String selectedAction = actionOptions.first;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: AppTheme.emeraldGreen.withValues(alpha: 0.5)),
          ),
          title: const Row(
            children: [
              Icon(Icons.add_task_rounded, color: AppTheme.neonLime, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Catat Perawatan Tanaman',
                  style: TextStyle(
                    color: AppTheme.creamWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkForest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_rounded, color: AppTheme.neonLime, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Catatan ini langsung disegel permanen dengan kriptografi SHA-256 & memberi Anda +5 Token Tani.',
                          style: TextStyle(color: AppTheme.pastelLime, fontSize: 11.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Jenis Tindakan Perawatan:',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkForest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.4)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedAction,
                      isExpanded: true,
                      dropdownColor: AppTheme.cardSurface,
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.neonLime),
                      style: const TextStyle(color: AppTheme.creamWhite, fontSize: 12.5),
                      items: actionOptions.map((opt) {
                        return DropdownMenuItem<String>(
                          value: opt,
                          child: Text(opt, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedAction = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Catatan Tambahan (Dosis / Kondisi Tanaman):',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: textCtrl,
                  style: const TextStyle(color: AppTheme.creamWhite, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Misal: Daun hijau segar, daun ke-12 dipangkas rapi.',
                    hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.darkForest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.emeraldGreen.withValues(alpha: 0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.neonLime),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonLime,
                foregroundColor: AppTheme.darkForest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Segel Catatan (+5 Token)', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id ?? 1;

      final lastBlock = await DatabaseHelper.instance.getLastBlokLog();
      final prevHash = lastBlock?['hash'] ?? '0000000000000000000000000000000000000000000000000000000000000000';
      final additionalNote = textCtrl.text.trim();
      final logText = additionalNote.isEmpty ? selectedAction : '$selectedAction. $additionalNote';
      final timestamp = DateTime.now().toUtc().toIso8601String();

      // Formula FR-13: hash = SHA-256(data log + hash_sebelumnya + timestamp)
      final newHash = sha256.convert(utf8.encode('$logText$prevHash$timestamp')).toString();

      await DatabaseHelper.instance.insertBlokLog({
        'log_id': (_blocks.length),
        'data_log': logText,
        'hash': newHash,
        'hash_sebelumnya': prevHash,
        'timestamp': timestamp,
      });

      await DatabaseHelper.instance.addRewardToken(userId, 5);
      await auth.refreshUser();

      await _loadBlockchain();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.verified_rounded, color: AppTheme.darkForest, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Catatan perawatan berhasil disegel sah! +5 Token Tani reward masuk ke akun Anda.',
                    style: TextStyle(color: AppTheme.darkForest, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.neonLime,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Menampilkan modal Paspor Sertifikat Keterlacakan (Traceability Passport)
  void _showCertificateModal() {
    final lastBlock = _blocks.isNotEmpty ? _blocks.last : null;
    final lastHash = lastBlock?['hash'] as String? ?? 'N/A';
    final shortHash = lastHash.length > 16
        ? '${lastHash.substring(0, 8)}...${lastHash.substring(lastHash.length - 8)}'
        : lastHash;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textGrey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 18),

            // Header Sertifikat
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.neonLime.withValues(alpha: 0.15),
                border: Border.all(color: AppTheme.neonLime.withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: AppTheme.neonLime, size: 36),
            ),
            const SizedBox(height: 12),
            const Text(
              'PASPOR PANEN DIGITAL',
              style: TextStyle(
                color: AppTheme.neonLime,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const Text(
              'Sertifikat Keterlacakan Perawatan Tanaman (Traceability)',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Kartu Ringkasan Sertifikat
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkForest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  _buildCertRow(Icons.eco_rounded, 'Komoditas', 'Melon Inthanon RZ F1 (Greenhouse)'),
                  const Divider(color: AppTheme.cardSurface, height: 20),
                  _buildCertRow(Icons.history_edu_rounded, 'Total Tindakan Perawatan', '${_blocks.length} Aktivitas Tersegel'),
                  const Divider(color: AppTheme.cardSurface, height: 20),
                  _buildCertRow(
                    Icons.verified_rounded,
                    'Status Keaslian Data',
                    _isChainValid == true ? 'Terverifikasi 100% Sah' : 'Terlindungi Kriptografi SHA-256',
                    valColor: const Color(0xFF2ECC71),
                  ),
                  const Divider(color: AppTheme.cardSurface, height: 20),
                  _buildCertRow(Icons.fingerprint_rounded, 'Segel Terakhir (Hash)', shortHash),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Simulasi QR / Barcode Cap Jaminan
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, color: Colors.amber, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Jaminan Mutu untuk Pembeli & Ekspor',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Data perawatan tidak dapat dimanipulasi mundur, menjadi bukti nyata kualitas hasil panen.',
                          style: TextStyle(color: AppTheme.creamWhite, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonLime,
                  foregroundColor: AppTheme.darkForest,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Tutup Paspor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertRow(IconData icon, String label, String value, {Color? valColor}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.pastelLime, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11.5)),
        ),
        Text(
          value,
          style: TextStyle(
            color: valColor ?? AppTheme.creamWhite,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  IconData _getActionIcon(String data) {
    final lower = data.toLowerCase();
    if (lower.contains('nutrisi') || lower.contains('ab mix') || lower.contains('pupuk')) {
      return Icons.science_rounded;
    } else if (lower.contains('polinasi') || lower.contains('bunga')) {
      return Icons.local_florist_rounded;
    } else if (lower.contains('pestisida') || lower.contains('nimba') || lower.contains('hama')) {
      return Icons.shield_rounded;
    } else if (lower.contains('siram') || lower.contains('irigasi') || lower.contains('lembab')) {
      return Icons.water_drop_rounded;
    } else if (lower.contains('sensor') || lower.contains('esp32') || lower.contains('suhu')) {
      return Icons.sensors_rounded;
    } else if (lower.contains('pangkas') || lower.contains('tunas')) {
      return Icons.content_cut_rounded;
    }
    return Icons.eco_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.ground,
        child: SafeArea(
          child: Column(
            children: [
              CustomSubAppBar(
                title: 'Paspor Panen & Catatan Tersegel',
                subtitle: 'Riwayat Perawatan Anti-Manipulasi (Blockchain Traceability)',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.token_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${user?.saldoToken ?? 0} Token',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Kartu Edukasi Ramah Awam (Bisa disembunyikan/ditampilkan)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.help_outline_rounded, color: AppTheme.neonLime, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Bagaimana Cara Kerjanya?',
                                style: TextStyle(
                                  color: AppTheme.creamWhite,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _showExplanation = !_showExplanation),
                            child: Text(
                              _showExplanation ? 'Sembunyikan' : 'Pelajari',
                              style: const TextStyle(color: AppTheme.pastelLime, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      if (_showExplanation) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Setiap Anda mencatat perawatan (pupuk, siram, semprot), sistem menyegelnya dengan kode digital SHA-256 yang saling mengunci ke catatan sebelumnya. Catatan ini tidak bisa diedit atau dihapus mundur, menjadi bukti otentik perawatan tanaman saat panen dijual ke pembeli/ekspor.',
                          style: TextStyle(color: AppTheme.textGrey, fontSize: 11.5, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Tombol Aksi Utama
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: _showAddLogDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.neonLime,
                                foregroundColor: AppTheme.darkForest,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.add_task_rounded, size: 17),
                              label: const Text(
                                '+ Catat Rawat',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: _isVerifying ? null : _verifyChainIntegrity,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cardSurface,
                                foregroundColor: AppTheme.neonLime,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: AppTheme.neonLime.withValues(alpha: 0.5)),
                                ),
                              ),
                              icon: _isVerifying
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neonLime),
                                    )
                                  : const Icon(Icons.verified_rounded, size: 16),
                              label: const Text(
                                'Uji Keaslian',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _showCertificateModal,
                            tooltip: 'Lihat Paspor Panen',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.amber.withValues(alpha: 0.15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                              ),
                            ),
                            icon: const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 20),
                          ),
                        ],
                      ),

                      // Banner Hasil Verifikasi
                      if (_isChainValid != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isChainValid!
                                ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                                : const Color(0xFFE74C3C).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isChainValid! ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isChainValid! ? Icons.check_circle_rounded : Icons.error_rounded,
                                color: _isChainValid! ? const Color(0xFF2ECC71) : const Color(0xFFFF6B6B),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isChainValid!
                                      ? 'Semua Catatan 100% Asli & Utuh! Tidak ada manipulasi riwayat.'
                                      : 'Peringatan! Terdeteksi ketidakcocokan kode rantai log.',
                                  style: TextStyle(
                                    color: _isChainValid! ? const Color(0xFF2ECC71) : const Color(0xFFFF6B6B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Header Daftar Log
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Riwayat Perawatan Terkunci',
                      style: TextStyle(
                        color: AppTheme.creamWhite,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${_blocks.length} Tindakan Terdaftar',
                      style: const TextStyle(color: AppTheme.pastelLime, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              // Rantai Blok Vertikal
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.neonLime))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                        itemCount: _blocks.length,
                        separatorBuilder: (_, __) => Center(
                          child: Container(
                            height: 18,
                            width: 2,
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        itemBuilder: (ctx, idx) {
                          final block = _blocks[idx];
                          final id = block['id'];
                          final data = block['data_log'] as String? ?? '';
                          final hash = block['hash'] as String? ?? '';
                          final prevHash = block['hash_sebelumnya'] as String? ?? '';
                          final time = block['timestamp'] as String? ?? '';
                          final isGenesis = idx == 0;
                          final isExpanded = _expandedBlockIndices.contains(idx);

                          return Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: AppTheme.cardSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isGenesis
                                    ? Colors.amber.withValues(alpha: 0.5)
                                    : AppTheme.emeraldGreen.withValues(alpha: 0.35),
                                width: isGenesis ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: isGenesis
                                            ? Colors.amber.withValues(alpha: 0.15)
                                            : AppTheme.neonLime.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        isGenesis ? Icons.wb_sunny_rounded : _getActionIcon(data),
                                        color: isGenesis ? Colors.amber : AppTheme.neonLime,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                isGenesis ? 'Catatan Awal (Genesis)' : 'Catatan Rawat #$id',
                                                style: TextStyle(
                                                  color: isGenesis ? Colors.amber : AppTheme.creamWhite,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.lock_rounded, color: Color(0xFF2ECC71), size: 10),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'Tersegel',
                                                      style: TextStyle(
                                                        color: Color(0xFF2ECC71),
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            time.length >= 16 ? time.substring(0, 16).replaceAll('T', ' ') : time,
                                            style: const TextStyle(color: AppTheme.textGrey, fontSize: 10.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  data,
                                  style: const TextStyle(
                                    color: AppTheme.creamWhite,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Toggle Bukti Kriptografi (Agar orang awam tidak pusing, tapi dosen tetap bisa uji FR-13)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedBlockIndices.remove(idx);
                                      } else {
                                        _expandedBlockIndices.add(idx);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                          color: AppTheme.pastelLime,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isExpanded ? 'Sembunyikan Kode Kriptografi' : 'Periksa Bukti Kode Hash SHA-256',
                                          style: const TextStyle(
                                            color: AppTheme.pastelLime,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                if (isExpanded) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.darkForest,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Hash Sebelumnya (Prev):',
                                          style: TextStyle(color: AppTheme.textGrey, fontSize: 9.5),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          prevHash,
                                          style: TextStyle(
                                            color: AppTheme.textGrey.withValues(alpha: 0.8),
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Hash Blok Ini (Current SHA-256):',
                                          style: TextStyle(color: AppTheme.neonLime, fontSize: 9.5, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hash,
                                          style: const TextStyle(
                                            color: AppTheme.neonLime,
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
