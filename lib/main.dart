import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  
  await _configureLocalTimeZone();
  
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      if (details.payload != null) {
        _handleAlarmNotification(details.payload!);
      }
    },
  );

  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    if (notificationAppLaunchDetails?.notificationResponse?.payload != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handleAlarmNotification(notificationAppLaunchDetails!.notificationResponse!.payload!);
      });
    }
  }

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'lumina_alarm_channel',
      'Lumina Alarms',
      description: 'Channel for Lumina Alarms',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    ));
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => AlarmProvider(),
      child: const MyApp(),
    ),
  );
}

void _handleAlarmNotification(String alarmId) {
  final context = navigatorKey.currentContext;
  if (context != null) {
    final provider = Provider.of<AlarmProvider>(context, listen: false);
    final alarm = provider.getAlarmById(alarmId);
    if (alarm != null) {
      // Avoid pushing multiple RingingScreens if one is already open
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => RingingScreen(alarm: alarm)),
        (route) => route.isFirst,
      );
    }
  }
}

Future<void> _configureLocalTimeZone() async {
  tz.initializeTimeZones();
  try {
    final dynamic timezoneResult = await FlutterTimezone.getLocalTimezone();
    String tzName;
    if (timezoneResult is String) {
      tzName = timezoneResult;
    } else {
      tzName = timezoneResult.toString();
      if (tzName.contains('TimezoneInfo(')) {
        final start = tzName.indexOf('TimezoneInfo(') + 'TimezoneInfo('.length;
        final end = tzName.indexOf(',', start);
        if (end != -1) {
          tzName = tzName.substring(start, end).trim();
        }
      }
    }
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (e) {
    debugPrint("Timezone detection error: $e");
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }
}

class Alarm {
  final String id;
  DateTime time;
  bool isEnabled;
  List<bool> days; 
  String label;
  String soundFileName;
  int snoozeCount;

  Alarm({
    required this.id,
    required this.time,
    this.isEnabled = true,
    required this.days,
    this.label = 'Alarm',
    this.soundFileName = 'classic_bell',
    this.snoozeCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'isEnabled': isEnabled,
        'days': days,
        'label': label,
        'soundFileName': soundFileName,
        'snoozeCount': snoozeCount,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'],
        time: DateTime.parse(json['time']),
        isEnabled: json['isEnabled'],
        days: List<bool>.from(json['days']),
        label: json['label'] ?? 'Alarm',
        soundFileName: json['soundFileName'] ?? 'classic_bell',
        snoozeCount: json['snoozeCount'] ?? 0,
      );
}

class AlarmProvider extends ChangeNotifier {
  List<Alarm> _alarms = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _volumeTimer;
  double _currentVolume = 0.0;

  AlarmProvider() {
    _loadAlarms();
  }

  List<Alarm> get alarms => _alarms;

  Alarm? getAlarmById(String id) {
    try {
      return _alarms.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alarmsJson = prefs.getString('alarms');
    if (alarmsJson != null) {
      final List<dynamic> decoded = jsonDecode(alarmsJson);
      _alarms = decoded.map((item) => Alarm.fromJson(item)).toList();
      notifyListeners();
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_alarms.map((a) => a.toJson()).toList());
    await prefs.setString('alarms', encoded);
  }

  void addAlarm(DateTime time, List<bool> days, String label, String sound) {
    final alarm = Alarm(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      time: time,
      days: days,
      label: label,
      soundFileName: sound,
    );
    _alarms.add(alarm);
    if (alarm.isEnabled) {
      _scheduleAlarm(alarm);
    }
    _saveAlarms();
    notifyListeners();
  }

  void updateAlarm(String id, DateTime time, List<bool> days, String label, String sound) {
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index != -1) {
      _cancelAlarm(_alarms[index]);
      _alarms[index].time = time;
      _alarms[index].days = days;
      _alarms[index].label = label;
      _alarms[index].soundFileName = sound;
      _alarms[index].isEnabled = true;
      _alarms[index].snoozeCount = 0;
      _scheduleAlarm(_alarms[index]);
      _saveAlarms();
      notifyListeners();
    }
  }

  void toggleAlarm(String id) {
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index != -1) {
      _alarms[index].isEnabled = !_alarms[index].isEnabled;
      if (_alarms[index].isEnabled) {
        _scheduleAlarm(_alarms[index]);
      } else {
        _cancelAlarm(_alarms[index]);
      }
      _saveAlarms();
      notifyListeners();
    }
  }

  void deleteAlarm(String id) {
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index != -1) {
      _cancelAlarm(_alarms[index]);
      _alarms.removeAt(index);
      _saveAlarms();
      notifyListeners();
    }
  }

  void snoozeAlarm(Alarm alarm) {
    final index = _alarms.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      _alarms[index].snoozeCount++;
      _alarms[index].time = DateTime.now().add(const Duration(minutes: 5));
      _scheduleAlarm(_alarms[index]);
      _saveAlarms();
      notifyListeners();
    }
  }

  void resetSnoozeCount(String id) {
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index != -1) {
      _alarms[index].snoozeCount = 0;
      _saveAlarms();
      notifyListeners();
    }
  }

  Future<void> _scheduleAlarm(Alarm alarm) async {
    final now = tz.TZDateTime.now(tz.local);
    for (int i = 0; i < 7; i++) {
      if (alarm.days[i]) {
        int targetWeekday = i + 1;
        var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, alarm.time.hour, alarm.time.minute);
        while (scheduledDate.isBefore(now) || scheduledDate.weekday != targetWeekday) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }
        int notificationId = (alarm.id.hashCode % 100000) * 10 + i;
        final String channelId = 'lumina_channel_${alarm.soundFileName}';
        final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
          channelId, 'Lumina Alarms',
          importance: Importance.max, priority: Priority.high, fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm, audioAttributesUsage: AudioAttributesUsage.alarm,
          playSound: true, sound: RawResourceAndroidNotificationSound(alarm.soundFileName),
          ongoing: true, autoCancel: false,
        );
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId, 'Lumina Alarm', alarm.label.isEmpty ? 'Time to wake up!' : alarm.label,
          scheduledDate, NotificationDetails(android: androidPlatformChannelSpecifics),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: alarm.id,
        );
      }
    }
  }

  Future<void> _cancelAlarm(Alarm alarm) async {
    for (int i = 0; i < 7; i++) {
      int notificationId = (alarm.id.hashCode % 100000) * 10 + i;
      await flutterLocalNotificationsPlugin.cancel(notificationId);
    }
  }

  void playPreview(String soundName) async {
    try {
      _volumeTimer?.cancel();
      await _audioPlayer.stop();
      if (soundName != 'default_alarm') {
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(AssetSource('audio/$soundName.mp3'));
      }
    } catch (e) {
      debugPrint("Error playing preview: $e");
    }
  }

  void playAlarm(String soundName) async {
    try {
      _volumeTimer?.cancel();
      await _audioPlayer.stop();
      _currentVolume = 0.0;
      await _audioPlayer.setVolume(_currentVolume);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      
      // Ensure the file exists or handle error
      await _audioPlayer.play(AssetSource('audio/$soundName.mp3'));
      
      _volumeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _currentVolume += 0.05; // Fade in over 20 seconds
        if (_currentVolume >= 1.0) {
          _currentVolume = 1.0;
          timer.cancel();
        }
        _audioPlayer.setVolume(_currentVolume);
      });
    } catch (e) {
      debugPrint("Error playing alarm: $e");
    }
  }

  void stopAlarm() {
    _volumeTimer?.cancel();
    _audioPlayer.stop();
  }

  void stopPreview() {
    stopAlarm();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina Alarm',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark, secondary: Colors.amber),
        useMaterial3: true,
      ),
      home: const AlarmHomeScreen(),
    );
  }
}

class AlarmHomeScreen extends StatefulWidget {
  const AlarmHomeScreen({super.key});
  @override
  State<AlarmHomeScreen> createState() => _AlarmHomeScreenState();
}

class _AlarmHomeScreenState extends State<AlarmHomeScreen> with WidgetsBindingObserver {
  late Timer _timer;
  late DateTime _currentTime;
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    _requestPermissions();
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', 
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (err) => debugPrint('Ad failed to load: $err'),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      Provider.of<AlarmProvider>(context, listen: false).stopPreview();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.black87, Colors.deepPurple.withOpacity(0.3)]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(icon: const Icon(Icons.nightlight_round, color: Colors.amber), 
                               onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NightstandScreen()))),
                    const Icon(Icons.alarm_on_rounded, size: 40, color: Colors.amber),
                    const SizedBox(width: 48), // Spacer for balance
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    Text(DateFormat('HH:mm:ss').format(_currentTime), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w200, color: Colors.white)),
                    Text(DateFormat('EEE, d MMM').format(_currentTime), style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.6), letterSpacing: 2)),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<AlarmProvider>(
                  builder: (context, provider, child) {
                    if (provider.alarms.isEmpty) return const Center(child: Text("No alarms set"));
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: provider.alarms.length,
                      itemBuilder: (context, index) => AlarmCard(alarm: provider.alarms[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        onPressed: () => _addAlarm(context),
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }

  void _addAlarm(BuildContext context, {Alarm? alarm}) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => AddAlarmSheet(alarmToEdit: alarm));
  }
}

class NightstandScreen extends StatefulWidget {
  const NightstandScreen({super.key});
  @override
  State<NightstandScreen> createState() => _NightstandScreenState();
}

class _NightstandScreenState extends State<NightstandScreen> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _timer.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(DateFormat('HH:mm').format(_now), style: TextStyle(fontSize: 120, fontWeight: FontWeight.w100, color: Colors.white.withOpacity(0.4))),
              Text(DateFormat('EEE, d MMM').format(_now), style: TextStyle(fontSize: 24, color: Colors.white.withOpacity(0.2))),
            ],
          ),
        ),
      ),
    );
  }
}

class AddAlarmSheet extends StatefulWidget {
  final Alarm? alarmToEdit;
  const AddAlarmSheet({super.key, this.alarmToEdit});
  @override
  State<AddAlarmSheet> createState() => _AddAlarmSheetState();
}

class _AddAlarmSheetState extends State<AddAlarmSheet> {
  late TimeOfDay _selectedTime;
  late List<bool> _selectedDays;
  late TextEditingController _labelController;
  late String _selectedSound;
  String? _currentlyPlaying;
  final List<String> _ringtones = ['classic_bell', 'digital_beep', 'gentle_sunrise', 'forest_birds', 'ocean_waves', 'morning_piano', 'energetic_beat', 'soft_chime', 'vintage_clock', 'futuristic_alarm'];

  @override
  void initState() {
    super.initState();
    if (widget.alarmToEdit != null) {
      _selectedTime = TimeOfDay.fromDateTime(widget.alarmToEdit!.time);
      _selectedDays = List.from(widget.alarmToEdit!.days);
      _labelController = TextEditingController(text: widget.alarmToEdit!.label);
      _selectedSound = widget.alarmToEdit!.soundFileName;
    } else {
      _selectedTime = TimeOfDay.now();
      _selectedDays = List.generate(7, (index) => true);
      _labelController = TextEditingController(text: 'Alarm');
      _selectedSound = 'classic_bell';
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _stopAndClearPreview() {
    Provider.of<AlarmProvider>(context, listen: false).stopPreview();
    if (mounted) setState(() => _currentlyPlaying = null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) => _stopAndClearPreview(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.alarmToEdit != null ? "Edit Alarm" : "Set Alarm", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (_currentlyPlaying != null) IconButton(icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 32), onPressed: _stopAndClearPreview),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _selectedTime);
                if (picked != null) setState(() => _selectedTime = picked);
              }, child: Text(_selectedTime.format(context), style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w200))),
              const SizedBox(height: 16),
              TextField(controller: _labelController, decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (i) {
                final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                return InkWell(onTap: () => setState(() => _selectedDays[i] = !_selectedDays[i]),
                  child: Container(width: 40, height: 40, decoration: BoxDecoration(color: _selectedDays[i] ? Colors.deepPurple : Colors.white10, shape: BoxShape.circle),
                    alignment: Alignment.center, child: Text(days[i])));
              })),
              const SizedBox(height: 24),
              Container(height: 200, decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(12)),
                child: ListView.builder(itemCount: _ringtones.length, itemBuilder: (context, i) {
                  final sound = _ringtones[i];
                  final isPlaying = _currentlyPlaying == sound;
                  return ListTile(dense: true, title: Text(sound.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: _selectedSound == sound ? Colors.amber : Colors.white)),
                    leading: Radio<String>(value: sound, groupValue: _selectedSound, onChanged: (v) => setState(() => _selectedSound = v!)),
                    trailing: IconButton(icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow), onPressed: () {
                      if (isPlaying) { _stopAndClearPreview(); } else {
                        Provider.of<AlarmProvider>(context, listen: false).playPreview(sound);
                        setState(() => _currentlyPlaying = sound);
                      }
                    }));
                })),
              const SizedBox(height: 24),
              ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: Colors.deepPurple),
                onPressed: () {
                  final now = DateTime.now();
                  DateTime alarmTime = DateTime(now.year, now.month, now.day, _selectedTime.hour, _selectedTime.minute);
                  if (alarmTime.isBefore(now)) alarmTime = alarmTime.add(const Duration(days: 1));
                  if (widget.alarmToEdit != null) { Provider.of<AlarmProvider>(context, listen: false).updateAlarm(widget.alarmToEdit!.id, alarmTime, _selectedDays, _labelController.text, _selectedSound); }
                  else { Provider.of<AlarmProvider>(context, listen: false).addAlarm(alarmTime, _selectedDays, _labelController.text, _selectedSound); }
                  Navigator.pop(context);
                }, child: Text(widget.alarmToEdit != null ? "UPDATE" : "SAVE", style: const TextStyle(color: Colors.white, fontSize: 18))),
            ],
          ),
        ),
      ),
    );
  }
}

class RingingScreen extends StatefulWidget {
  final Alarm alarm;
  const RingingScreen({super.key, required this.alarm});
  @override
  State<RingingScreen> createState() => _RingingScreenState();
}

class _RingingScreenState extends State<RingingScreen> {
  double _shakeIntensity = 0;
  StreamSubscription? _accelerometerSubscription;
  bool _isDismissed = false;
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    _startListening();
    Provider.of<AlarmProvider>(context, listen: false).playAlarm(widget.alarm.soundFileName);
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (err) => debugPrint('Ad failed to load: $err'),
      ),
    );
  }

  void _snoozeWithPenalty() {
    final provider = Provider.of<AlarmProvider>(context, listen: false);
    provider.stopAlarm();
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          provider.snoozeAlarm(widget.alarm);
          Navigator.of(context).pop();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          provider.snoozeAlarm(widget.alarm);
          Navigator.of(context).pop();
        },
      );
      _interstitialAd!.show();
    } else {
      provider.snoozeAlarm(widget.alarm);
      Navigator.of(context).pop();
    }
  }

  void _startListening() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (_isDismissed) return;
      double accel = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (accel > 15) setState(() => _shakeIntensity = math.min(1.0, _shakeIntensity + (accel - 10) / 100));
      if (_shakeIntensity >= 1.0) _dismissAlarm();
    });
  }

  void _dismissAlarm() {
    if (_isDismissed) return;
    setState(() => _isDismissed = true);
    _accelerometerSubscription?.cancel();
    final provider = Provider.of<AlarmProvider>(context, listen: false);
    provider.stopPreview();
    provider.resetSnoozeCount(widget.alarm.id);
    Navigator.of(context).pop('dismiss');
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(width: double.infinity, decoration: BoxDecoration(gradient: RadialGradient(colors: [Colors.deepPurple.withOpacity(0.5), Colors.black], radius: 1.5)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.alarm, size: 100, color: Colors.amber),
          const SizedBox(height: 40),
          Text("${widget.alarm.time.hour.toString().padLeft(2, '0')}:${widget.alarm.time.minute.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(widget.alarm.label, style: const TextStyle(fontSize: 24, color: Colors.white70)),
          const SizedBox(height: 60),
          const Text("SHAKE TO WAKE", style: TextStyle(color: Colors.amber, letterSpacing: 4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(width: 250, height: 20, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: _shakeIntensity, backgroundColor: Colors.transparent, valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber)))),
          const SizedBox(height: 100),
          ElevatedButton(onPressed: _snoozeWithPenalty, style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, minimumSize: const Size(200, 50)),
            child: const Text("SNOOZE (AD PENALTY)", style: TextStyle(color: Colors.white))),
        ]),
      ),
    );
  }
}

class AlarmCard extends StatelessWidget {
  final Alarm alarm;
  const AlarmCard({super.key, required this.alarm});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(alarm.time);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(timeStr, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: alarm.isEnabled ? Colors.white : Colors.white38)),
              Switch(value: alarm.isEnabled, onChanged: (v) => Provider.of<AlarmProvider>(context, listen: false).toggleAlarm(alarm.id), activeColor: Colors.amber),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(alarm.label, style: const TextStyle(color: Colors.white60)),
              if (alarm.snoozeCount > 0) Text("Snoozed ${alarm.snoozeCount} times", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (i) {
            final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
            return Text(days[i], style: TextStyle(color: alarm.days[i] ? (alarm.isEnabled ? Colors.amber : Colors.amber.withOpacity(0.3)) : Colors.white24, fontWeight: alarm.days[i] ? FontWeight.bold : FontWeight.normal));
          })),
        ],
      ),
    );
  }
}
