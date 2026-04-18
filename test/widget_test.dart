import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:beautiful_alarm_clock/main.dart';

void main() {
  testWidgets('App starts and shows home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => AlarmProvider(),
        child: const MyApp(),
      ),
    );
    
    expect(find.byType(AlarmHomeScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  test('AlarmProvider adds and deletes alarms', () {
    final provider = AlarmProvider();
    final initialCount = provider.alarms.length;
    
    provider.addAlarm(
      DateTime.now(), 
      List.generate(7, (index) => true),
      'Test Alarm',
      'classic_bell'
    );
    expect(provider.alarms.length, initialCount + 1);
    
    final idToDelete = provider.alarms.last.id;
    provider.deleteAlarm(idToDelete);
    expect(provider.alarms.length, initialCount);
  });
}
