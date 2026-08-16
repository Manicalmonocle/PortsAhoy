// The consent flow is a promise, so it is tested like one.
//
// The claim this game makes is that nothing about a player's run leaves their
// device unless they choose to send it. That is a behaviour, not a statement of
// intent, and the way it breaks is quiet: a refactor that launches on the first
// tap, or a sheet that loses its decline button, would ship looking fine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/report_endpoint.dart';
import 'package:ports_ahoy/ui/send_report_sheet.dart';

const _payload = 'PA1~1.0.9-10~abc~0~~0~5~0~1~Mb7.far~D5.7w.3.2.1q.0';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSendReportSheet(context,
              payload: _payload, readable: 'the long readable report'),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet shows the exact payload before anything is sent',
      (tester) async {
    await _open(tester);

    // Shown in full, not summarised. A player can read every character that
    // would leave the device.
    expect(find.text(_payload), findsOneWidget);
  });

  testWidgets('declining is exactly as available as accepting', (tester) async {
    await _open(tester);

    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Copy instead'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    // Equal weight is the anti-dark-pattern commitment: same widget type, so
    // one cannot quietly become a primary button while the others fade.
    final buttons = tester
        .widgetList<OutlinedButton>(find.byType(OutlinedButton))
        .toList();
    expect(buttons.length, 3);
    for (final b in buttons) {
      expect(b.onPressed, isNotNull, reason: 'no option may be disabled');
    }
  });

  testWidgets('Not now closes without sending', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(_payload), findsNothing);
  });

  testWidgets('the payload is never the readable report', (tester) async {
    await _open(tester);
    // The readable report is prose and would not survive a URL; only the
    // compact code travels. If these were ever swapped, the send would fail
    // silently on the tester's phone and the run would be lost.
    expect(find.text('the long readable report'), findsNothing);
  });

  test('the shipped build has a destination that is actually reachable', () {
    // Guards the half-configured state: a form id set without an entry id, or
    // the reverse, would put a Send button on screen that opens a broken page.
    if (ReportEndpoint.destination != ReportDestination.none) {
      expect(ReportEndpoint.configured, isTrue,
          reason: 'ReportEndpoint.destination is set but not fully configured');
      expect(ReportEndpoint.url(_payload), isNotNull);
    }
  });
}
