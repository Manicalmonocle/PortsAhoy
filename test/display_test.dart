// How often the world repaints, checked against simulated screens.
//
// Both faults this guards against were found the same way — by simulating a
// real refresh clock, microsecond timing and jitter included — and neither
// was visible by reading the code. The first ran a "30fps" world at 23.5 on a
// 60Hz screen, alternating two and three refreshes apart; the second turned a
// 90fps choice into 120 on a 120Hz phone.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/ui/display_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paints per second, and the refreshes between each, for [fps] on an [hz]
/// screen whose refreshes land with up to 0.2ms of jitter.
({double fps, List<int> spacing}) simulate(double hz, int fps) {
  final gate = FrameGate();
  final rnd = Random(7);
  const seconds = 20;
  var last = 0, lastPaint = 0, paints = 0;
  final spacing = <int>[];
  for (var i = 1; i <= hz * seconds; i++) {
    final t = (i * 1e6 / hz + (rnd.nextDouble() - 0.5) * 400).round();
    final dt = (t - last) / 1e6;
    last = t;
    if (gate.due(dt, fps)) {
      paints++;
      spacing.add(i - lastPaint);
      lastPaint = i;
    }
  }
  return (fps: paints / seconds, spacing: spacing.skip(5).toList());
}

void main() {
  group('the frame gate', () {
    test('every rate is delivered exactly, on every common screen', () {
      for (final hz in [60.0, 90.0, 120.0, 144.0]) {
        for (final r in FrameRate.values) {
          final want = min(r.fps.toDouble(), hz);
          expect(simulate(hz, r.fps).fps, closeTo(want, 0.5),
              reason: '${r.fps}fps on a ${hz.toInt()}Hz screen');
        }
      }
    });

    test('a whole ratio is perfectly even, not two-then-three', () {
      // The first fault: 30 on a 60Hz screen ran 2,3,2,2,3 refreshes apart.
      expect(simulate(60, 30).spacing.toSet(), {2});
      expect(simulate(120, 30).spacing.toSet(), {4});
      expect(simulate(120, 60).spacing.toSet(), {2});
    });

    test('ninety on a 120Hz phone is ninety, not every refresh', () {
      // The second fault. Three refreshes in four, as evenly as that goes.
      final r = simulate(120, 90);
      expect(r.fps, closeTo(90, 0.5));
      expect(r.spacing.toSet(), {1, 2});
    });
  });

  group('the setting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => DisplaySettings.chosen.value = null);

    test('is unset until the player picks, and then remembered', () async {
      await DisplaySettings.load();
      expect(DisplaySettings.chosen.value, isNull,
          reason: 'unset is the default that may drop itself to 30');
      await DisplaySettings.choose(FrameRate.high);
      DisplaySettings.chosen.value = null;
      await DisplaySettings.load();
      expect(DisplaySettings.chosen.value, FrameRate.high);
    });

    testWidgets('can be picked from the Log panel', (tester) async {
      final c = GameController(seedOverride: 20260815);
      await c.load();
      c.setSpeed(0);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(PortsAhoyApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log').last);
      await tester.pumpAndSettle();

      for (final r in FrameRate.values) {
        expect(find.text('${r.label} ${r.fps}'), findsOneWidget);
      }
      ChoiceChip chip(FrameRate r) =>
          tester.widget<ChoiceChip>(find.ancestor(
              of: find.text('${r.label} ${r.fps}'),
              matching: find.byType(ChoiceChip)));
      expect(chip(FrameRate.medium).selected, isTrue,
          reason: 'the default shows as Medium');

      await tester.tap(find.text('High 90'));
      await tester.pumpAndSettle();
      expect(chip(FrameRate.high).selected, isTrue);
      expect(chip(FrameRate.medium).selected, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('frame_rate'), 90);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
