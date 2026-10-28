import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  factory NotificationService() => instance;
  NotificationService._init();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Notifikasi diklik: ${response.payload}');
        },
      );

      // Request permission on Android 13+
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('Gagal inisialisasi NotificationService: $e');
    }
  }

  /// FR-12: Menampilkan Notifikasi Lokal saat ambang sensor terlampaui
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'tanigreen_sensor_channel',
      'Peringatan Sensor Greenhouse',
      channelDescription:
          'Notifikasi lokal jika suhu, kelembapan, atau jadwal perawatan memerlukan perhatian.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }

  /// FR-12: Menampilkan notifikasi popup pantauan suhu, kelembapan udara & cahaya IoT terkini
  Future<void> showTelemetryNotification({
    required String greenhouseName,
    required double suhu,
    double? kelembapanUdara,
    double? lembapUdara,
    required double cahaya,
    double? lembapTanah,
    String? status,
  }) async {
    await init();

    final double actualLembap = kelembapanUdara ?? lembapUdara ?? 70.0;
    final bool isHighTemp = suhu > 33.0;
    final bool isLowHumidity = actualLembap < 45.0;
    final bool isWarning = isHighTemp || isLowHumidity;

    final String title = isWarning
        ? '⚠️ [PERINGATAN IOT] $greenhouseName'
        : '🌡️ [Pantauan Lingkungan IoT] $greenhouseName';

    String advice = 'Kondisi mikroklimat tanaman terpantau optimal dan aman.';
    if (isHighTemp) {
      advice = 'Perhatian: Suhu tinggi (${suhu.toStringAsFixed(1)}°C). Pastikan sirkulasi kipas/ventilasi berjalan.';
    } else if (isLowHumidity) {
      advice = 'Perhatian: Kelembapan udara rendah (${actualLembap.toStringAsFixed(0)}%). Disarankan pengabutan/misting.';
    }

    final String body =
        'Suhu: ${suhu.toStringAsFixed(1)}°C • Lembap: ${actualLembap.toStringAsFixed(0)}% • Cahaya: ${cahaya.toInt()} lx\n$advice';

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_tani_telemetry_channel',
      'Smart Tani Monitoring & Pengingat IoT',
      channelDescription: 'Notifikasi popup berkala telemetri suhu, kelembapan udara, dan cahaya IoT',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.status,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _plugin.show(
        DateTime.now().millisecond + 100,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error show telemetry notification: $e');
    }
  }

  /// FR-12: Mengaktifkan Pengingat Berkala Otomatis (Periodic Background Notification)
  Future<void> startPeriodicTelemetryReminder({
    String title = '🌿 [Pengingat Berkala] Smart Greenhouse',
    String body = '🌡️ Suhu Saat Ini: 28.5°C | Lembap: 70% | Kondisi Optimal',
  }) async {
    await init();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_tani_periodic_channel',
      'Smart Tani Pengingat Otomatis',
      channelDescription: 'Pengingat berkala otomatis kondisi greenhouse saat aplikasi ditutup',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _plugin.periodicallyShow(
        8888,
        title,
        body,
        RepeatInterval.hourly,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Error starting periodic notification: $e');
    }
  }

  /// Mematikan pengingat berkala otomatis
  Future<void> stopPeriodicTelemetryReminder() async {
    await init();
    try {
      await _plugin.cancel(8888);
    } catch (e) {
      debugPrint('Error canceling periodic notification: $e');
    }
  }

  /// Menjadwalkan notifikasi berkala otomatis pantauan IoT (tiap X menit: 5, 10, 15, 30, 60 mnt)
  Future<void> schedulePeriodicTelemetryNotifications({
    required String greenhouseName,
    required int intervalMinutes,
    required double suhu,
    required double kelembapanUdara,
    required double cahaya,
  }) async {
    await init();
    await cancelPeriodicTelemetryNotifications();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_tani_telemetry_channel',
      'Smart Tani Monitoring & Pengingat IoT',
      channelDescription: 'Notifikasi popup berkala telemetri suhu, kelembapan udara, dan cahaya IoT',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.status,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final now = DateTime.now();
    // Jadwalkan untuk 24 jam ke depan sesuai interval
    final int repeatCount = (24 * 60 ~/ intervalMinutes).clamp(1, 48);

    for (int i = 1; i <= repeatCount; i++) {
      final scheduledTime = now.add(Duration(minutes: i * intervalMinutes));
      final tzScheduled = tz.TZDateTime.from(scheduledTime, tz.local);
      final int notifId = 700000 + i;

      try {
        await _plugin.zonedSchedule(
          notifId,
          '🌡️ [Pantauan Berkala IoT] $greenhouseName',
          'Suhu: ${suhu.toStringAsFixed(1)}°C • Lembap: ${kelembapanUdara.toStringAsFixed(0)}% • Cahaya: ${cahaya.toInt()} lx\nKondisi mikroklimat lahan greenhouse Anda saat ini.',
          tzScheduled,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('Error scheduling periodic telemetry item $i: $e');
      }
    }
  }

  /// Membatalkan notifikasi telemetri berkala
  Future<void> cancelPeriodicTelemetryNotifications() async {
    await init();
    for (int i = 1; i <= 50; i++) {
      try {
        await _plugin.cancel(700000 + i);
      } catch (_) {}
    }
  }

  /// FR-12: Menjadwalkan pengingat jadwal tanam:
  /// 1. Peringatan H-30 Menit sebelum task dimulai (Heads-up popup banner)
  /// 2. Notifikasi saat waktu eksekusi tepat tiba
  Future<void> schedulePlantReminderNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await init();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'smart_tani_schedule_channel',
      'Jadwal Tanam & Perawatan',
      channelDescription: 'Pengingat waktu penyiraman, pemupukan, dan panen tanaman',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.reminder,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final now = DateTime.now();
    final h30Date = scheduledDate.subtract(const Duration(minutes: 30));
    final int h30Id = id + 500000;

    String formatTime(DateTime dt) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    // 1. Jadwalkan Pengingat H-30 Menit (Pop-up 30 Menit Sebelum Task Dimulai)
    if (h30Date.isAfter(now)) {
      try {
        final tzH30 = tz.TZDateTime.from(h30Date, tz.local);
        await _plugin.zonedSchedule(
          h30Id,
          '⏳ [Pengingat H-30 Menit] $title',
          '$body\nTask akan dimulai pukul ${formatTime(scheduledDate)} WIB (30 menit lagi). Siapkan peralatan Anda!',
          tzH30,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('Error scheduling H-30 notification: $e');
      }
    } else if (scheduledDate.isAfter(now)) {
      // Jika waktu tinggal kurang dari 30 menit dari sekarang
      final diffMinutes = scheduledDate.difference(now).inMinutes;
      try {
        await _plugin.show(
          h30Id,
          '⏳ [Segera Dimulai] $title',
          '$body\nTask akan dimulai dalam $diffMinutes menit lagi (Pukul ${formatTime(scheduledDate)} WIB).',
          notificationDetails,
        );
      } catch (_) {}
    }

    // 2. Jadwalkan Notifikasi Saat Waktu Eksekusi Tiba
    if (scheduledDate.isAfter(now)) {
      try {
        final tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
        await _plugin.zonedSchedule(
          id,
          '⏰ [Waktunya Eksekusi] $title',
          '$body\nWaktu jadwal telah tiba! Silakan lakukan perawatan sekarang.',
          tzScheduled,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('Error scheduling exact notification: $e');
      }
    }
  }

  /// Membatalkan pengingat jadwal (membatalkan id utama dan id H-30)
  Future<void> cancelNotification(int id) async {
    await init();
    try {
      await _plugin.cancel(id);
      await _plugin.cancel(id + 500000);
    } catch (e) {
      debugPrint('Error canceling notification $id: $e');
    }
  }
}
