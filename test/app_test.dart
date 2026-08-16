import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/sim/profile.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/resources.dart';
import 'package:ports_ahoy/ui/theme.dart';
import 'package:ports_ahoy/ui/world_view.dart';
import 'package:ports_ahoy/version.dart';
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
  final controller = GameController(seedOverride: 20260815);
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

    testWidgets('the banner states what the event does, on the smallest phone',
        (tester) async {
      // Reported from play: "what does north easterly event mean? it is very
      // vague". It showed a line of flavour and a countdown. The effects are
      // now spelled out, which makes the banner taller — so it has to be
      // checked at the tightest viewport, not just the roomy one.
      final c = await pumpGame(tester, size: const Size(360, 640));
      c.act((s) {
        s.events.active.add(ActiveEvent(
          defId: 'north_easterly',
          omenTick: s.tick,
          startTick: s.tick,
          endTick: s.tick + 500,
        ));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the taller banner must still fit a 360x640 handset');

      expect(find.textContaining('Fishing Wharf works at 30%'), findsOneWidget,
          reason: 'the player has to know which shed is hurt, and by how much');
      expect(find.textContaining('consignments sail as normal'), findsOneWidget,
          reason: 'and that their own hulls are not stuck in port');

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

  // A version string that silently lies is worse than none: a bug report
  // stamped with the wrong build sends you looking in the wrong place. The
  // player runs the web build and the APK side by side, and the web one
  // updates itself while the APK does not — so the two genuinely do drift.
  test('the version in the app matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(declared, isNotNull, reason: 'pubspec has no version: line');
    expect(kAppVersion, declared!.group(1),
        reason: 'lib/version.dart is stale — run '
            '`dart run tool/stamp_version.dart`');
  });

  group('the game saves itself', () {
    // THE TEST ABOVE IS WHY THIS ONE EXISTS. It calls save() by hand, so it
    // passed for the entire life of the project while GameController.save()
    // had no caller anywhere in lib/ — no lifecycle observer, no timer, no
    // button. Every run lived in RAM and died with the process. A test that
    // invokes the mechanism proves the mechanism works; only a test that
    // refuses to invoke it proves the game uses it.
    testWidgets('a run is written without anyone calling save', (tester) async {
      final c = await pumpGame(tester);
      c.setSpeed(4);
      // Frame by frame: the controller's clock is a 100ms periodic timer, and
      // one long pump does not fire it repeatedly.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      c.setSpeed(0);
      await tester.pumpAndSettle();

      expect(c.state.tick, greaterThan(0), reason: 'the clock must have run');

      final reloaded = GameController(seedOverride: 20260815);
      await reloaded.load();
      reloaded.setSpeed(0);
      addTearDown(reloaded.dispose);

      // Not the live tick: autosave is throttled on wall-clock time and this
      // whole test runs in a few milliseconds, so exactly one write lands. The
      // point is that a write happened at all without anyone asking — a fresh,
      // never-saved game reloads at tick 0.
      expect(reloaded.state.tick, greaterThan(0),
          reason: 'playing the game must persist it, unprompted');

      await closeGame(tester);
    });

    testWidgets('a run begun from a cold launch carries the charters',
        (tester) async {
      // load()'s no-save path used to call GameState.newGame() with no
      // charters at all, while startNewRun() passed them — so the two ways
      // into a run disagreed. A player who set two hardships and relaunched
      // was quietly given an easy run and, on winning, a record filed under
      // "No hardship".
      SharedPreferences.setMockInitialValues({
        'ports_ahoy_profile': jsonEncode({
          'owned': ['hard_weather', 'bitter_seas'],
          'active': ['hard_weather', 'bitter_seas'],
          'runs': <dynamic>[],
          'pending': <String>[],
        }),
      });

      final c = GameController(seedOverride: 20260815);
      await c.load();
      c.setSpeed(0);
      addTearDown(c.dispose);

      expect(c.state.charters.ids, containsAll(['hard_weather', 'bitter_seas']),
          reason: 'a cold launch must begin the run the player selected');
      expect(c.state.charters.difficulty, 4,
          reason: 'and it must be recorded at the difficulty they chose');
    });

    testWidgets('every victory in a session is recorded, not just the first',
        (tester) async {
      final c = await pumpGame(tester);

      // Win once.
      c.state.lighthouseBuilt = true;
      await c.recordVictory();
      expect(c.profile.runs, hasLength(1));
      await c.chooseCharter(c.profile.pendingChoice.first);

      // Sail again, and win again in the same sitting.
      await c.startNewRun();
      c.setSpeed(0); // startNewRun un-pauses; keep the clock out of the test
      expect(c.state.victoryRecorded, isFalse,
          reason: 'a new port has not won anything yet');
      c.state.lighthouseBuilt = true;
      await c.recordVictory();

      expect(c.profile.runs, hasLength(2),
          reason: 'the second run of a session must be filed too');

      await closeGame(tester);
    });

    testWidgets('the port does not work while you are not playing',
      (tester) async {
    // The whole premise is that putting the phone down costs nothing. A world
    // that advances in your absence makes closing the app consequential: the
    // town eats, wages fall due, and a run left overnight was found starved.
    SharedPreferences.setMockInitialValues({});
    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(1);
    addTearDown(c.dispose);

    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pump();

    // Running: the clock moves.
    await tester.pump(const Duration(seconds: 3));
    final whileWatching = c.state.tick;
    expect(whileWatching, greaterThan(0),
        reason: 'the sim should advance while the app is on screen');

    // Away: it must not.
    c.setAway(true);
    await tester.pump(const Duration(seconds: 5));
    expect(c.state.tick, whileWatching,
        reason: 'the port kept working with the app in the background');

    // Back: it resumes, without having caught anything up.
    c.setAway(false);
    await tester.pump(const Duration(seconds: 3));
    expect(c.state.tick, greaterThan(whileWatching));

    c.setSpeed(0); // leave no periodic timer running past the test
    await tester.pump();
    await closeGame(tester);
  });

  testWidgets('reopening a save does not run the clock forward',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = GameController(seedOverride: 20260815);
    await first.load();
    first.setSpeed(1);
    await tester.pumpWidget(PortsAhoyApp(controller: first));
    await tester.pump(const Duration(seconds: 3));
    await first.saveNow();
    final leftAt = first.state.tick;
    first.setSpeed(0);
    await tester.pump();
    first.dispose();
    await closeGame(tester);

    // A save written "a long time ago" must reopen exactly where it was.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ports_ahoy_saved_at_ms',
        DateTime.now().millisecondsSinceEpoch - const Duration(days: 3).inMilliseconds);

    final second = GameController(seedOverride: 20260815);
    await second.load();
    second.setSpeed(0);
    addTearDown(second.dispose);
    expect(second.state.tick, leftAt,
        reason: 'three days away must not advance the port by a single hour');
    expect(second.lastCatchUpTicks, 0);
  });

  testWidgets('suspending the app writes the port immediately',
        (tester) async {
      final c = await pumpGame(tester);
      await tester.pump();
      c.state.coin = 4321;

      // What Android does when the player switches away.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      final reloaded = GameController(seedOverride: 20260815);
      await reloaded.load();
      reloaded.setSpeed(0);
      addTearDown(reloaded.dispose);

      expect(reloaded.state.coin, 4321,
          reason: 'backgrounding the app must not cost the player their port');

      await closeGame(tester);
    });
  });
  _abandonTests();
}

void _abandonTests() {
  // THE RULE: a run in progress cannot be put down and picked over.
  //
  // "Set sail anew" keeps the whole collection, so while it was available at
  // any moment, abandoning a run was free — quit on day 4, quit again, until
  // the charters and the weather look kind. That is a reroll, and every record
  // after it means nothing because it was drawn rather than played. It now
  // waits for the light to be lit, which is the only moment "keep what you
  // have earned" was ever meant to describe.
  testWidgets('a run in progress cannot be restarted with the collection kept',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ports_ahoy_profile': jsonEncode({
        'owned': ['poor_soil', 'a_full_purse'],
        'active': <String>[],
        'runs': <Map<String, dynamic>>[],
        'pending': <String>[],
      }),
    });

    // Tall enough that the whole panel is laid out at once: a ListView builds
    // lazily, so "not on screen" and "not offered" are indistinguishable to a
    // finder unless everything fits.
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(0);
    addTearDown(c.dispose);

    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pump();
    await openPanel(tester, 'Voyage');
    await tester.pumpAndSettle();

    // Mid-run: no free restart, but the costly exit is there.
    expect(c.state.lighthouseBuilt, isFalse);
    expect(find.textContaining('Set sail anew'), findsNothing,
        reason: 'a free restart mid-run is a reroll');
    expect(find.text('Give up the venture'), findsOneWidget,
        reason: 'leaving early must still be possible, at a cost');

    // Finished: the roguelite loop needs its way onward, or a win strands you
    // with a charter you can never sail under.
    c.state.lighthouseBuilt = true;
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('Set sail anew'), findsOneWidget,
        reason: 'after the light is lit, starting the next run must be offered');

    await closeGame(tester);
  });

  testWidgets('giving up the venture destroys the collection too',
      (tester) async {
    // The escape hatch for a run no play can recover from — the case that
    // prompted it was a browser tab left open across an update, found on day
    // 1000-odd with no coin. The cost is total on purpose: a cheap quit is a
    // reroll, and a rerollable roguelite has meaningless records.
    SharedPreferences.setMockInitialValues({});
    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(0);
    addTearDown(c.dispose);

    c.profile.owned.addAll(['poor_soil', 'a_full_purse']);
    c.profile.active.add('poor_soil');
    c.profile.runs.add(RunRecord(
        days: 94, difficulty: 1, population: 42, charterIds: const ['poor_soil']));
    await c.saveProfile();

    // A run well underway, in the state the button exists to escape.
    for (var i = 0; i < 24 * 5; i++) {
      c.state.step();
    }
    expect(c.state.day, greaterThan(1));

    await c.abandonEverything();
    c.setSpeed(0); // the fresh run starts its clock; stop it for the test

    expect(c.profile.owned, isEmpty, reason: 'charters must not survive');
    expect(c.profile.active, isEmpty);
    expect(c.profile.runs, isEmpty, reason: 'records must not survive');
    expect(c.profile.wins, 0);
    expect(c.state.day, 1, reason: 'the new run starts from the first day');
    expect(c.state.charters.ids, isEmpty);

    // And it must survive a reload — a wipe that comes back on next launch
    // would be worse than no wipe at all.
    final reopened = GameController(seedOverride: 20260815);
    await reopened.load();
    reopened.setSpeed(0);
    addTearDown(reopened.dispose);
    expect(reopened.profile.owned, isEmpty);
    expect(reopened.profile.runs, isEmpty);
    expect(reopened.state.day, 1);
  });
}
