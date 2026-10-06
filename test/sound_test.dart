// Sound, tested the only way it can be here: by what the game ASKS to hear.
//
// Nobody writing these could listen to the result, so these tests pin down
// the part that does not need ears — that the right sound is asked for at the
// right moment, that nothing is asked for at the wrong one, and that the
// player's two controls over it (the first touch, and mute) are obeyed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ports_ahoy/audio/sound_board.dart';
import 'package:ports_ahoy/audio/sound_director.dart';
import 'package:ports_ahoy/game_controller.dart';
import 'package:ports_ahoy/main.dart';
import 'package:ports_ahoy/sim/buildings.dart';
import 'package:ports_ahoy/sim/events.dart';
import 'package:ports_ahoy/sim/market.dart';
import 'package:ports_ahoy/sim/trade.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes down everything it is asked to do, and makes no noise.
class Recorder implements SoundBackend {
  final List<Sfx> played = [];
  final List<int> variants = [];
  final Map<Bed, double> beds = {};
  int pauses = 0;

  @override
  Future<void> play(Sfx sfx, double volume, {int variant = 0}) async {
    played.add(sfx);
    variants.add(variant);
  }
  @override
  Future<void> startBed(Bed bed, double volume) async => beds[bed] = volume;
  @override
  Future<void> setBed(Bed bed, double volume) async => beds[bed] = volume;
  @override
  Future<void> pauseAll() async => pauses++;
  @override
  Future<void> resumeAll() async {}
}

void main() {
  final board = SoundBoard.instance;
  late Recorder rec;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    board.reset();
    rec = Recorder();
  });
  tearDown(board.reset);

  group('the sound files', () {
    test('every sound the game asks for exists, and is bundled', () {
      for (final s in Sfx.values) {
        for (var i = 0; i < s.variants; i++) {
          expect(File('assets/${s.assetFor(i)}').existsSync(), isTrue,
              reason: '${s.assetFor(i)} is played but missing');
        }
      }
      for (final b in Bed.values) {
        expect(File('assets/${b.asset}').existsSync(), isTrue,
            reason: '${b.asset} is looped but missing');
      }
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('- assets/sounds/'),
          reason: 'a sound on disk but not in pubspec is not in the app');
    });
  });

  group('the board', () {
    test('plays nothing until main() switches it on', () {
      // Every widget test runs the app this way, and none of them may reach
      // for an audio plugin.
      board.unlock();
      board.play(Sfx.bell);
      expect(board.enabled, isFalse);
    });

    test('plays nothing before the first touch', () async {
      await board.init(rec);
      board.play(Sfx.bell);
      expect(rec.played, isEmpty,
          reason: 'a browser refuses audio before an interaction');
      board.unlock();
      board.play(Sfx.bell);
      expect(rec.played, [Sfx.bell]);
    });

    test('the first touch starts the sea, the wind and the rain', () async {
      await board.init(rec);
      board.unlock();
      await pumpEventQueue();
      expect(rec.beds.keys.toSet(), Bed.values.toSet());
    });

    test('mute silences everything, and is remembered', () async {
      await board.init(rec);
      board.unlock();
      await board.toggleMute();
      board.play(Sfx.cannon);
      expect(rec.played, isEmpty);
      expect(rec.pauses, greaterThan(0), reason: 'the ambience stops too');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound_muted'), isTrue);

      // And a fresh launch reads it back.
      board.reset();
      await board.init(Recorder());
      expect(board.muted.value, isTrue);
    });

    test('the same sound cannot machine-gun', () async {
      await board.init(rec);
      board.unlock();
      // Selling ten lots in under a second should sound like trade, not a
      // slot machine paying out.
      board.play(Sfx.coins, nowMs: 1000);
      board.play(Sfx.coins, nowMs: 1050);
      board.play(Sfx.coins, nowMs: 1100);
      expect(rec.played, [Sfx.coins]);
      board.play(Sfx.coins, nowMs: 1000 + Sfx.coins.minGapMs);
      expect(rec.played, [Sfx.coins, Sfx.coins]);
      // A different sound is not held back by it.
      board.play(Sfx.bell, nowMs: 1001);
      expect(rec.played.last, Sfx.bell);
    });

    test('a gull is never the same call twice running', () async {
      // The first gull was one recording played every time, and the
      // repetition was half of why it sounded wrong.
      await board.init(rec);
      board.unlock();
      var now = 0;
      board.clock = () => now;
      for (var i = 0; i < 40; i++) {
        board.play(Sfx.gull);
        now += Sfx.gull.minGapMs;
      }
      expect(rec.variants.toSet(), {0, 1, 2}, reason: 'all three get used');
      for (var i = 1; i < rec.variants.length; i++) {
        expect(rec.variants[i], isNot(rec.variants[i - 1]));
      }
    });

    test('nothing plays while the app is in the background', () async {
      await board.init(rec);
      board.unlock();
      board.setAway(true);
      board.play(Sfx.bell);
      expect(rec.played, isEmpty);
      board.setAway(false);
      board.play(Sfx.bell);
      expect(rec.played, [Sfx.bell]);
    });
  });

  group('the director', () {
    late GameController c;
    late SoundDirector d;

    Future<void> start() async {
      c = GameController(seedOverride: 20260815);
      await c.load();
      c.setSpeed(0);
      await board.init(rec);
      board.unlock();
      d = SoundDirector(c);
    }

    tearDown(() {
      d.dispose();
      c.dispose();
    });

    test('a shed going up is a hammer', () async {
      await start();
      c.act((g) => g.buildings.add(Building(defId: 'house')
        ..col = 3
        ..row = 3));
      expect(rec.played, contains(Sfx.hammer));
    });

    test('a hull leaving rings the bell, and one coming home pays', () async {
      await start();
      final v = Voyage(
          destinationId: 'ostmark',
          cargo: const {},
          departTick: c.state.tick,
          returnTick: c.state.tick + 72,
          quotedCoin: 300);
      var now = 1000;
      board.clock = () => now;
      c.act((g) => g.voyages.add(v));
      expect(rec.played, [Sfx.bell]);
      rec.played.clear();
      now += 3 * 60 * 1000; // she is three days out; minutes, on the clock
      c.act((g) => g.voyages.remove(v));
      expect(rec.played, containsAll([Sfx.bell, Sfx.coins]));
    });

    test('a trader standing in rings the bell', () async {
      await start();
      c.act((g) => g.market.ships.add(Ship(
          name: 'Test', departTick: 99999, offers: const [])));
      expect(rec.played, contains(Sfx.bell));
    });

    test('the cutter alongside sounds the alarm, once', () async {
      await start();
      c.act((g) => g.cutterInspectTick = g.tick + 20);
      c.act((_) {});
      c.act((_) {});
      expect(rec.played.where((s) => s == Sfx.alarm), hasLength(1));
    });

    test('the light lit is the chime', () async {
      await start();
      c.act((g) => g.lighthouseBuilt = true);
      expect(rec.played, contains(Sfx.chime));
    });

    test('loading a port plays nothing for what was already in it', () async {
      await start();
      // A port with sheds, ships and a hull at sea arrives all at once on a
      // load. Without the guard it would hammer, ring and pay for all of it.
      c.state.buildings.add(Building(defId: 'house')
        ..col = 3
        ..row = 3);
      await c.startNewRun();
      expect(rec.played, isEmpty);
    });

    test('the wind is loud in a gale and the rain only falls in a storm',
        () async {
      await start();
      for (var i = 0; i < 60; i++) {
        d.tick();
      }
      final calmWind = rec.beds[Bed.wind]!;
      expect(rec.beds[Bed.rain], lessThan(0.01));

      c.state.events.active.add(ActiveEvent(
          defId: 'north_easterly',
          omenTick: c.state.tick - 40,
          startTick: c.state.tick - 20,
          endTick: c.state.tick + 200));
      for (var i = 0; i < 60; i++) {
        d.tick();
      }
      expect(rec.beds[Bed.wind], greaterThan(calmWind * 2));
      expect(rec.beds[Bed.rain], greaterThan(0.3));
    });
  });

  testWidgets('the speaker button mutes, and says so', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = GameController(seedOverride: 20260815);
    await c.load();
    c.setSpeed(0);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(PortsAhoyApp(controller: c));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget,
        reason: 'sound is on until the player says otherwise');
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sound_muted'), isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
