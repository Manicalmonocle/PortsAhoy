import 'package:flutter/material.dart';

import 'audio/audioplayers_backend.dart';
import 'audio/sound_board.dart';
import 'audio/sound_director.dart';
import 'game_controller.dart';
import 'ui/game_screen.dart';
import 'ui/theme.dart';
import 'ui/world_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = GameController();
  await controller.load();
  // The world moves on its own clock in the app, and on the tick in a test.
  // Set here, and only here, so every test keeps a fixed frame.
  WorldView.live = true;
  // Sound, likewise, only from here. A device or browser that cannot make a
  // single player gets a silent game rather than no game.
  try {
    await SoundBoard.instance.init(await AudioplayersBackend.create());
  } catch (e) {
    debugPrint('sound unavailable: $e');
  }
  runApp(PortsAhoyApp(controller: controller));
}

/// The game is designed for a phone. On a wide screen — a desktop browser —
/// it is letterboxed into a phone-shaped column rather than stretched, so what
/// you test on a PC is what you get on a handset.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  /// Widest the game is allowed to get before it stops being a phone layout.
  static const double maxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width <= maxWidth) return child;

    final height =
        size.height.clamp(0.0, maxWidth * 2.05);
    return ColoredBox(
      color: const Color(0xFF0A1219),
      child: Center(
        child: SizedBox(
          width: maxWidth,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PortsAhoyApp extends StatefulWidget {
  const PortsAhoyApp({super.key, required this.controller});

  final GameController controller;

  @override
  State<PortsAhoyApp> createState() => _PortsAhoyAppState();
}

class _PortsAhoyAppState extends State<PortsAhoyApp>
    with WidgetsBindingObserver {
  /// Only when main() switched sound on: the director runs a timer, and a
  /// widget test has no business owning one.
  SoundDirector? _sound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (SoundBoard.instance.enabled) {
      _sound = SoundDirector(widget.controller);
    }
  }

  @override
  void dispose() {
    _sound?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Write the port the moment the app stops being in front of the player.
  ///
  /// The controller autosaves every few seconds while the clock runs, but a
  /// port that is paused, or one the player just spent a minute reorganising
  /// without the clock ticking, would otherwise sit unsaved. On the web this
  /// also fires when the tab is hidden, which is the closest thing a browser
  /// gives you to "closing".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Stop the clock BEFORE writing, so what is saved is the port as the
        // player left it rather than a few ticks further on.
        widget.controller.setAway(true);
        widget.controller.saveNow();
        SoundBoard.instance.setAway(true);
      case AppLifecycleState.resumed:
        widget.controller.setAway(false);
        SoundBoard.instance.setAway(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ports Ahoy!',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // The first touch anywhere unlocks sound — a browser will not play a
      // note before one. Listener rather than a gesture detector, so it sees
      // the touch without competing for it.
      home: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => SoundBoard.instance.unlock(),
        child: _PhoneFrame(child: GameScreen(controller: widget.controller)),
      ),
    );
  }
}
