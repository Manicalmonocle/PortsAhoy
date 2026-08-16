import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/ui/theme.dart';
import 'package:ports_ahoy/ui/world_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the app with an empty save and the clock paused, so assertions are
/// not racing the simulation.
Future<GameController> pumpGame(WidgetTester tester,
    {Size? size, double navBar = 0}) async {
  // Test at a real phone viewport rather than the 800x600 default: panels are
  // sized as a fraction of screen height, so a short window hides content that
  // is perfectly visible on a handset.
  tester.view.physicalSize = size ?? const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  if (navBar > 0) {
    // A three-button navigation bar, which eats the bottom of the window.
    tester.view.viewPadding = FakeViewPadding(bottom: navBar);
    tester.view.padding = FakeViewPadding(bottom: navBar);
  }
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final controller = GameController();
  await controller.load();
  controller.setSpeed(0);
  addTearDown(controller.dispose);

  await tester.pumpWidget(PortsAhoyApp(controller: controller));
  await tester.pump();
  return controller;
}

Future<void> closeGame(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Open one of the dock panels.
Future<void> openPanel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Scroll a panel until [target] is built. Panels are ListViews, which only
/// build what is on screen, so anything below the fold is not in the tree yet.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView).last,
    const Offset(0, -120),
    maxIteration: 30,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the base is the screen', () {
    testWidgets('boots straight into the harbour, with no tabs', (tester) async {
      await pumpGame(tester);

      expect(find.byType(WorldView), findsOneWidget);
      expect(find.byType(TabBar), findsNothing,
          reason: 'a base-builder has a HUD over a base, not tabs');

      for (final label in ['Build', 'Quay', 'Sheds', 'Log']) {
        expect(find.text(label), findsOneWidget);
      }

      await closeGame(tester);
    });

    testWidgets('the HUD shows coin, hands and the day', (tester) async {
      final c = await pumpGame(tester);

      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('${c.state.idleWorkers}/${c.state.population}'),
          findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await closeGame(tester);
    });

    testWidgets('the speed control cycles through every step, never gated',
        (tester) async {
      final c = await pumpGame(tester);
      // Half speed exists so a player can slow down as well as speed up.
      expect(GameController.speeds, contains(0.5));

      // pumpGame leaves the clock paused, so the cycle starts from 0.
      for (final expected in [0.5, 1.0, 2.0, 4.0, 0.0]) {
        await tester.tap(
            find.text(c.speed == 0 ? 'Paused' : '${fmtSpeed(c.speed)}x'));
        await tester.pump();
        expect(c.speed, expected);
      }
      await closeGame(tester);
    });
  });

  group('panels', () {
    testWidgets('the Sheds panel exposes every worker control', (tester) async {
      final c = await pumpGame(tester);
      await openPanel(tester, 'Sheds');

      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
      expect(find.text('Forest Camp'), findsWidgets);
      expect(c.state.buildings.first.workers, 2);

      await closeGame(tester);
    });

    testWidgets('staffing from the Sheds panel puts a hand to work',
        (tester) async {
      final c = await pumpGame(tester);
      await openPanel(tester, 'Sheds');
      final before = c.state.buildings.first.workers;

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pump();

      expect(c.state.buildings.first.workers, before + 1);
      expect(c.state.idleWorkers, 0);

      await closeGame(tester);
    });

    testWidgets('the + control disables once every hand is working',
        (tester) async {
      final c = await pumpGame(tester);
      await openPanel(tester, 'Sheds');

      // Five hands, four posted: exactly one spare to place.
      expect(c.state.idleWorkers, 1);
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pump();
      expect(c.state.idleWorkers, 0);

      // With nobody spare, every + control is now disabled.
      final before = c.state.assignedWorkers;
      await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
      await tester.pump();
      expect(c.state.assignedWorkers, before);

      await closeGame(tester);
    });

    testWidgets('the Build panel offers the lighthouse and the sheds',
        (tester) async {
      await pumpGame(tester);
      await openPanel(tester, 'Build');

      expect(find.text('The Saltwind Light'), findsOneWidget);
      await scrollTo(tester, find.text('Forest Camp').first);
      expect(find.text('Forest Camp'), findsWidgets);

      await closeGame(tester);
    });

    testWidgets('building a shed spends coin and puts it on the map',
        (tester) async {
      final c = await pumpGame(tester);
      final coinBefore = c.state.coin;
      final countBefore = c.state.buildings.length;

      await openPanel(tester, 'Build');
      await scrollTo(tester, find.text('Forest Camp').first);

      final card = find.ancestor(
        of: find.text('Forest Camp').first,
        matching: find.byType(Card),
      );
      final button =
          find.descendant(of: card, matching: find.text('Build')).first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();

      expect(c.state.buildings.length, countBefore + 1);
      expect(c.state.coin, lessThan(coinBefore));
      expect(c.state.buildings.last.isPlaced, isTrue,
          reason: 'a new shed lands on the map immediately');

      await closeGame(tester);
    });

    testWidgets('the Quay panel renders whatever is in port', (tester) async {
      final c = await pumpGame(tester);
      await openPanel(tester, 'Quay');

      if (c.state.market.ships.isEmpty) {
        expect(find.textContaining('No ships at the quay'), findsOneWidget);
      } else {
        expect(find.text('All'), findsWidgets);
      }

      await closeGame(tester);
    });

    testWidgets('a panel closes again', (tester) async {
      await pumpGame(tester);
      await openPanel(tester, 'Log');
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

      await closeGame(tester);
    });
  });

  group('collecting', () {
    testWidgets('the collect button appears only when a yard has something',
        (tester) async {
      final c = await pumpGame(tester);
      expect(find.textContaining('Collect'), findsNothing);

      c.act((s) {
        for (var i = 0; i < 40; i++) {
          s.step();
        }
      });
      await tester.pump();

      expect(c.state.hasAnythingToCollect, isTrue);
      expect(find.textContaining('Collect'), findsOneWidget);

      await closeGame(tester);
    });

    testWidgets('collecting moves the yards into the stores', (tester) async {
      final c = await pumpGame(tester);
      c.act((s) {
        for (var i = 0; i < 40; i++) {
          s.step();
        }
      });
      await tester.pump();

      final before = c.state.stock[Resource.timber];
      await tester.tap(find.textContaining('Collect'));
      await tester.pump();

      expect(c.state.stock[Resource.timber], greaterThan(before));
      expect(c.state.hasAnythingToCollect, isFalse);
      expect(find.textContaining('Collect'), findsNothing);

      await closeGame(tester);
    });
  });

  group('phone viewports', () {
    const sizes = <String, Size>{
      'iPhone SE': Size(375, 667),
      'iPhone 15': Size(393, 852),
      'Pixel 7': Size(412, 915),
      'small android': Size(360, 640),
    };

    sizes.forEach((name, size) {
      testWidgets('$name renders the base and every panel', (tester) async {
        final c = await pumpGame(tester, size: size);
        // Give it some state so the HUD, banners and collect button all show.
        for (var i = 0; i < 40; i++) {
          c.state.step();
        }
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'base on $name');

        for (final panel in ['Build', 'Quay', 'Trade', 'Sheds', 'Voyage', 'Log']) {
          await openPanel(tester, panel);
          expect(tester.takeException(), isNull,
              reason: '$panel overflowed on $name');
          await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
          await tester.pumpAndSettle();
        }

        await closeGame(tester);
      });
    });

    testWidgets('a three-button nav bar never swallows the bottom of a panel',
        (tester) async {
      // Reported from a Pixel 9 Pro: the last row of the Build panel was
      // rendering underneath the system navigation buttons.
      const navBar = 48.0;
      await pumpGame(tester, size: const Size(412, 915), navBar: navBar);

      for (final panel in ['Build', 'Quay', 'Trade', 'Sheds', 'Voyage', 'Log']) {
        await openPanel(tester, panel);
        expect(tester.takeException(), isNull, reason: '$panel overflowed');

        // The scrollable must stop short of the navigation bar.
        final box = tester.renderObject<RenderBox>(find.byType(ListView).last);
        final bottom =
            box.localToGlobal(Offset(0, box.size.height)).dy;
        expect(bottom, lessThanOrEqualTo(915 - navBar + 0.5),
            reason: '$panel runs under the navigation bar');

        await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
        await tester.pumpAndSettle();
      }

      await closeGame(tester);
    });

    // The charter panel only shows its interesting half once you own charters,
    // so the viewport sweep above never reaches it on a fresh profile. This
    // seeds a profile that has won a run and is sailing under a hardship, which
    // is the state that renders the "This voyage" card and the whole toggle
    // list at once — the tallest this panel ever gets.
    testWidgets('the charter panel fits a phone once charters are owned',
        (tester) async {
      for (final size in const [Size(360, 640), Size(412, 915)]) {
        SharedPreferences.setMockInitialValues({
          'ports_ahoy_profile': jsonEncode({
            'owned': [
              'hard_weather',
              'bitter_seas',
              'rich_contracts',
              'deep_cellars',
              'a_full_purse',
            ],
            'active': ['hard_weather', 'rich_contracts'],
            'runs': [
              {
                'days': 122,
                'difficulty': 2,
                'population': 39,
                'charters': ['hard_weather'],
              },
            ],
            'pending': <String>[],
          }),
        });

        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final c = GameController();
        await c.load();
        c.setSpeed(0);
        addTearDown(c.dispose);

        await tester.pumpWidget(PortsAhoyApp(controller: c));
        await tester.pump();

        await openPanel(tester, 'Voyage');
        expect(tester.takeException(), isNull,
            reason: 'the charter panel overflowed at $size');

        // The card naming the run in force has to be there, or the panel is
        // back to describing only the run you are not playing.
        expect(find.text('This voyage'), findsOneWidget,
            reason: 'the run in progress must say what it is settled under');

        await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'scrolling the charter panel overflowed at $size');

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });

    testWidgets('nothing floating is hidden behind the dock', (tester) async {
      // Reported from a Pixel 9 Pro: the Collect button and the map's hint
      // line were tucked underneath the dock, half-visible.
      const navBar = 48.0;
      final c = await pumpGame(tester, size: const Size(412, 915), navBar: navBar);
      c.act((s) {
        for (var i = 0; i < 60; i++) {
          s.step();
        }
      });
      await tester.pumpAndSettle();

      // Top edge of the dock, in screen coordinates.
      final dockTop = tester
          .getTopLeft(find.ancestor(
            of: find.text('Build'),
            matching: find.byType(SafeArea),
          ).last)
          .dy;

      final collect = find.textContaining('Collect');
      expect(collect, findsOneWidget, reason: 'expected something to collect');
      expect(tester.getBottomLeft(collect).dy, lessThanOrEqualTo(dockTop),
          reason: 'the Collect button must sit clear of the dock');

      final hint = find.textContaining('Tap to manage');
      expect(tester.getBottomLeft(hint).dy, lessThanOrEqualTo(dockTop),
          reason: 'the map hint must sit clear of the dock');

      await closeGame(tester);
    });

    testWidgets('the event banner never covers the resource chips',
        (tester) async {
      // Reported from a Pixel: the banner was pinned at a guessed top offset
      // and landed on the stores row, making it unreadable.
      const statusBar = 52.0;
      final c = await pumpGame(tester, size: const Size(412, 915));
      tester.view.viewPadding =
          FakeViewPadding(top: statusBar, bottom: 48);
      tester.view.padding = FakeViewPadding(top: statusBar, bottom: 48);

      // Force an event to be on screen.
      c.act((s) {
        s.events.active.add(ActiveEvent(
          defId: 'privateer_scare',
          omenTick: s.tick,
          startTick: s.tick,
          endTick: s.tick + 500,
        ));
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Privateers'), findsWidgets,
          reason: 'the banner should be showing');

      // The chips row must sit entirely above the banner.
      final chipBottom = tester
          .getBottomLeft(find.byIcon(Icons.inventory_2_outlined))
          .dy;
      final bannerTop =
          tester.getTopLeft(find.textContaining('Privateers').first).dy;
      expect(bannerTop, greaterThanOrEqualTo(chipBottom),
          reason: 'the banner must not cover the stores row');

      await closeGame(tester);
    });

    testWidgets('the dock itself clears the nav bar', (tester) async {
      const navBar = 48.0;
      await pumpGame(tester, size: const Size(412, 915), navBar: navBar);

      final dock = find.text('Build');
      final box = tester.renderObject<RenderBox>(dock);
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      expect(bottom, lessThan(915 - navBar),
          reason: 'the dock labels must sit above the navigation buttons');

      await closeGame(tester);
    });

    testWidgets('survives a large platform text scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpGame(tester);
      expect(tester.takeException(), isNull);

      await closeGame(tester);
    });
  });

  testWidgets('a fresh game persists and reloads', (tester) async {
    final c = await pumpGame(tester);
    c.state.coin = 1234;
    await c.save();

    final reloaded = GameController();
    await reloaded.load();
    reloaded.setSpeed(0);
    addTearDown(reloaded.dispose);

    expect(reloaded.state.coin, 1234);

    await closeGame(tester);
  });
}
