import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AlarmProvider(),
      child: const MyApp(),
    ),
  );
}

class Alarm {
  final String id;
  DateTime time;
  bool isEnabled;
  List<bool> days; // Mon-Sun

  Alarm({
    required this.id,
    required this.time,
    this.isEnabled = true,
    required this.days,
  });
}

class AlarmProvider extends ChangeNotifier {
  final List<Alarm> _alarms = [
    Alarm(
      id: '1',
      time: DateTime.now().add(const Duration(hours: 1)),
      days: List.generate(7, (index) => true),
    ),
  ];

  List<Alarm> get alarms => _alarms;

  void addAlarm(DateTime time, List<bool> days) {
    _alarms.add(Alarm(
      id: DateTime.now().toString(),
      time: time,
      days: days,
    ));
    notifyListeners();
  }

  void toggleAlarm(String id) {
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index != -1) {
      _alarms[index].isEnabled = !_alarms[index].isEnabled;
      notifyListeners();
    }
  }

  void deleteAlarm(String id) {
    _alarms.removeWhere((a) => a.id == id);
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beautiful Alarm Clock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          secondary: Colors.amber,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
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

class _AlarmHomeScreenState extends State<AlarmHomeScreen> {
  late Timer _timer;
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black87,
              Colors.deepPurple.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  children: [
                    Text(
                      DateFormat('HH:mm:ss').format(_currentTime),
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      DateFormat('EEE, d MMM').format(_currentTime),
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withOpacity(0.6),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<AlarmProvider>(
                  builder: (context, provider, child) {
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: provider.alarms.length,
                      itemBuilder: (context, index) {
                        final alarm = provider.alarms[index];
                        return AlarmCard(alarm: alarm);
                      },
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
        onPressed: () => _selectTime(context),
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final now = DateTime.now();
      final alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      if (context.mounted) {
        Provider.of<AlarmProvider>(context, listen: false).addAlarm(
          alarmTime,
          List.generate(7, (index) => true),
        );
      }
    }
  }
}

class AlarmCard extends StatelessWidget {
  final Alarm alarm;

  const AlarmCard({super.key, required this.alarm});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(alarm.time);
    final periodStr = DateFormat('a').format(alarm.time);

    return Dismissible(
      key: Key(alarm.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        Provider.of<AlarmProvider>(context, listen: false).deleteAlarm(alarm.id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete, color: Colors.redAccent),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: alarm.isEnabled ? Colors.white : Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      periodStr,
                      style: TextStyle(
                        fontSize: 16,
                        color: alarm.isEnabled ? Colors.white70 : Colors.white24,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: alarm.isEnabled,
                  onChanged: (value) {
                    Provider.of<AlarmProvider>(context, listen: false)
                        .toggleAlarm(alarm.id);
                  },
                  activeColor: Colors.amber,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                final isActive = alarm.days[index];
                return Text(
                  days[index],
                  style: TextStyle(
                    color: isActive
                        ? (alarm.isEnabled ? Colors.amber : Colors.amber.withOpacity(0.3))
                        : Colors.white24,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
