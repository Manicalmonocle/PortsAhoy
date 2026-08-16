import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'ui/game_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = GameController();
  await controller.load();
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
      case AppLifecycleState.resumed:
        widget.controller.setAway(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ports Ahoy!',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _PhoneFrame(child: GameScreen(controller: widget.controller)),
    );
  }
}
