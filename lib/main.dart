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

class PortsAhoyApp extends StatelessWidget {
  const PortsAhoyApp({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ports Ahoy!',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _PhoneFrame(child: GameScreen(controller: controller)),
    );
  }
}
