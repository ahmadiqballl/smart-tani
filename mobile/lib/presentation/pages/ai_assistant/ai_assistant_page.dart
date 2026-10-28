import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import '../../../core/services/gemini_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_db/database_helper.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/custom_sub_app_bar.dart';
import '../game/edukasi_game_page.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isLoading = false;

  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text: 'Halo Petani! Saya Asisten Tani berbasis Google Gemini AI & Smart Agronomy Engine.\n\n'
          'Anda bisa bertanya dengan mengetik, merekam suara 🎙️, atau melampirkan foto tanaman 📸 untuk diagnosa otomatis bercak daun, hama, atau nutrisi.',
      isBot: true,
      time: 'Asisten AI',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initSpeechToText();
  }

  Future<void> _initSpeechToText() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (err) {
          debugPrint('STT error: $err');
          if (mounted) setState(() => _isListening = false);
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
  }

  /// Merekam Suara (Speech-To-Text Bahasa Indonesia)
  Future<void> _toggleVoiceRecording() async {
    if (_isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
      if (mounted) setState(() => _isListening = false);
      return;
    }

    try {
      if (!_speechAvailable) {
        _speechAvailable = await _speech.initialize(
          onStatus: (status) {
            if (status == 'notListening' || status == 'done') {
              if (mounted) setState(() => _isListening = false);
            }
          },
          onError: (err) {
            debugPrint('STT error: ${err.errorMsg}');
            if (mounted) setState(() => _isListening = false);
          },
        );
      }

      if (_speechAvailable) {
        setState(() => _isListening = true);
        await _speech.listen(
          onResult: (result) {
            if (mounted && result.recognizedWords.isNotEmpty) {
              setState(() {
                _promptController.text = result.recognizedWords;
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenFor: const Duration(seconds: 20),
            pauseFor: const Duration(seconds: 3),
            cancelOnError: true,
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Layanan suara belum siap/didukung di emulator ini. Silakan ketik pertanyaan Anda.'),
              backgroundColor: Color(0xFFE67E22),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('STT error: $e');
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mikrofon tidak tersedia di emulator. Silakan gunakan ketik teks.'),
            backgroundColor: Color(0xFFE67E22),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Memilih Foto Tanaman dari Kamera atau Galeri
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengambil gambar: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Bottom Sheet Pilihan Sumber Foto
  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textGrey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Lampirkan Foto Tanaman untuk AI',
                style: TextStyle(
                  color: AppTheme.creamWhite,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'AI akan menganalisis visual daun, hama, atau buah',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonLime.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppTheme.neonLime),
                ),
                title: const Text('Ambil Foto via Kamera', style: TextStyle(color: AppTheme.creamWhite, fontWeight: FontWeight.w700)),
                subtitle: const Text('Foto daun atau hama langsung di greenhouse', style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.amber),
                ),
                title: const Text('Pilih dari Galeri HP', style: TextStyle(color: AppTheme.creamWhite, fontWeight: FontWeight.w700)),
                subtitle: const Text('Gunakan foto tanaman yang sudah tersimpan', style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTokenExhaustedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
        ),
        title: const Row(
          children: [
            Icon(Icons.token_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Text(
              'Token Tani Habis!',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anda memerlukan minimal 1 Token Tani untuk setiap pertanyaan konsultasi ke Asisten AI Gemini.',
              style: TextStyle(color: AppTheme.creamWhite, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkForest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sports_esports_rounded, color: AppTheme.neonLime, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dapatkan token gratis dengan bermain Game Panen Melon 2D!',
                      style: TextStyle(color: AppTheme.pastelLime, fontSize: 11.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti Saja', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EdukasiGamePage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonLime,
              foregroundColor: AppTheme.darkForest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.sports_esports_rounded, size: 18),
            label: const Text('Main Game & Raih Token', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _askGemini([String? customPrompt]) async {
    String query = (customPrompt ?? _promptController.text).trim();
    if (query.isEmpty && _selectedImage == null) return;
    if (_isLoading) return;

    if (query.isEmpty && _selectedImage != null) {
      query = 'Tolong analisis foto tanaman ini: apakah ada indikasi hama, penyakit daun, atau kekurangan nutrisi? Berikan solusi penanganannya.';
    }

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final tokenBalance = user?.saldoToken ?? 0;

    // Cek saldo token (1 Token per pertanyaan)
    if (tokenBalance < 1) {
      _showTokenExhaustedDialog();
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    // Kurangi 1 Token Tani untuk konsultasi AI
    if (user?.id != null) {
      await DatabaseHelper.instance.deductRewardToken(user!.id!, 1);
      await auth.refreshUser();
    }

    final imageToSend = _selectedImage;
    List<int>? imageBytes;
    if (imageToSend != null) {
      try {
        imageBytes = await imageToSend.readAsBytes();
      } catch (e) {
        debugPrint('Failed to read image bytes: $e');
      }
    }

    setState(() {
      _messages.add(_ChatMessage(
        text: query,
        isBot: false,
        time: 'Anda',
        imagePath: imageToSend?.path,
      ));
      _isLoading = true;
      _selectedImage = null; // Clear attachment
    });
    _promptController.clear();
    _scrollToBottom();

    try {
      final result = await GeminiService.getTaniAdvice(
        query,
        imageBytes: imageBytes,
      );

      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: result,
            isBot: true,
            time: 'Asisten Tani (Gemini AI)',
          ));
        });
      }
    } catch (e) {
      debugPrint('[AiAssistantPage] Error asking Gemini: $e');
      if (mounted) {
        setState(() {
          _messages.add(const _ChatMessage(
            text: '⚠️ Terjadi gangguan koneksi jaringan saat menghubungi server AI. Menampilkan rekomendasi agronomi berbasis data internal.',
            isBot: true,
            time: 'Asisten Tani',
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppTheme.ground,
        child: SafeArea(
          child: Column(
            children: [
              CustomSubAppBar(
                title: 'Asisten Tani AI',
                subtitle: 'Didukung Google Gemini Vision & Suara',
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
                        '${context.watch<AuthProvider>().currentUser?.saldoToken ?? 0} Token',
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

              // Chat Messages View
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, idx) {
                    final msg = _messages[idx];
                    return Align(
                      alignment: msg.isBot
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.82,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: msg.isBot
                              ? AppTheme.cardSurface
                              : AppTheme.neonLime,
                          borderRadius: BorderRadius.circular(18).copyWith(
                            bottomLeft: msg.isBot
                                ? const Radius.circular(2)
                                : const Radius.circular(18),
                            bottomRight: !msg.isBot
                                ? const Radius.circular(2)
                                : const Radius.circular(18),
                          ),
                          border: msg.isBot
                              ? Border.all(
                                  color: AppTheme.emeraldGreen.withValues(alpha: 0.45),
                                  width: 1.1,
                                )
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  msg.isBot
                                      ? Icons.smart_toy_rounded
                                      : Icons.person_rounded,
                                  size: 13,
                                  color: msg.isBot
                                      ? AppTheme.neonLime
                                      : AppTheme.darkForest,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  msg.time,
                                  style: TextStyle(
                                    color: msg.isBot
                                        ? AppTheme.pastelLime.withValues(alpha: 0.75)
                                        : AppTheme.darkForest.withValues(alpha: 0.7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            // Jika ada lampiran foto dari pengguna
                            if (msg.imagePath != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(msg.imagePath!),
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            SelectableText(
                              msg.text,
                              style: TextStyle(
                                color: msg.isBot
                                    ? AppTheme.creamWhite
                                    : AppTheme.darkForest,
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: msg.isBot
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Loading Indicator
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.neonLime.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.neonLime,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Gemini AI sedang menganalisis foto & pertanyaan...',
                              style: TextStyle(color: AppTheme.pastelLime, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Listening Voice Status Indicator (FR-05)
              if (_isListening)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mic_rounded, color: Color(0xFFFF5252), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Mendengarkan suara Anda... (Bicara sekarang)',
                            style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            _speech.stop();
                            setState(() => _isListening = false);
                            _askGemini();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5252),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('Kirim', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // Preview Foto yang Terlampir
              if (_selectedImage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.darkForest,
                    border: Border(
                      top: BorderSide(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_selectedImage!, width: 48, height: 48, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Foto Tanaman Terlampir',
                              style: TextStyle(color: AppTheme.neonLime, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            Text(
                              'AI akan menganalisis visual tanaman ini saat Anda kirim.',
                              style: TextStyle(color: AppTheme.textGrey, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _selectedImage = null),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Hapus Foto',
                      ),
                    ],
                  ),
                ),

              // Info Biaya Token Tani
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.darkForest.withValues(alpha: 0.6),
                  border: Border(
                    top: BorderSide(color: AppTheme.emeraldGreen.withValues(alpha: 0.2)),
                    bottom: BorderSide(color: AppTheme.emeraldGreen.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.token_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'Biaya: 1 Token Tani / pertanyaan',
                      style: TextStyle(color: AppTheme.pastelLime, fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      'Sisa: ${context.watch<AuthProvider>().currentUser?.saldoToken ?? 0} Token',
                      style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              // Prompt Shortcut Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    _buildPromptChip('Daun melon bercak kuning, solusinya apa?'),
                    _buildPromptChip('Rekomendasi takaran pupuk AB Mix'),
                    _buildPromptChip('Cara basmi hama kutu kebul'),
                    _buildPromptChip('Berapa pH ideal tanaman melon?'),
                  ],
                ),
              ),

              // Input Bar (Kamera, Suara & Teks)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkForest,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Tombol Kamera / Galeri Foto
                    GestureDetector(
                      onTap: _showImageSourceSheet,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _selectedImage != null
                              ? AppTheme.neonLime
                              : AppTheme.emeraldGreen.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedImage != null
                                ? AppTheme.neonLime
                                : AppTheme.neonLime.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: _selectedImage != null
                              ? AppTheme.darkForest
                              : AppTheme.neonLime,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Tombol Input Suara Mikrofon (FR-05)
                    GestureDetector(
                      onTap: _toggleVoiceRecording,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? const Color(0xFFFF5252)
                              : AppTheme.emeraldGreen.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isListening
                                ? Colors.white
                                : AppTheme.neonLime.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening ? Colors.white : AppTheme.neonLime,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Kolom Input Teks
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.inputFill,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.5),
                          ),
                        ),
                        child: TextField(
                          controller: _promptController,
                          style: const TextStyle(color: AppTheme.creamWhite, fontSize: 13),
                          cursorColor: AppTheme.neonLime,
                          decoration: InputDecoration(
                            hintText: _selectedImage != null
                                ? 'Tanyakan foto ini (opsional)...'
                                : 'Ketik atau rekam suara...',
                            hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (val) => _askGemini(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Tombol Kirim
                    GestureDetector(
                      onTap: _isLoading ? null : () => _askGemini(),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: _isLoading
                              ? AppTheme.textGrey.withValues(alpha: 0.3)
                              : AppTheme.neonLime,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: AppTheme.darkForest,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptChip(String text) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _askGemini(text),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline_rounded, size: 12, color: AppTheme.neonLime),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(color: AppTheme.pastelLime, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isBot;
  final String time;
  final String? imagePath;

  const _ChatMessage({
    required this.text,
    required this.isBot,
    required this.time,
    this.imagePath,
  });
}
