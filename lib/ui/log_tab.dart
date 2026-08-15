import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/game_state.dart';
import 'theme.dart';

class LogTab extends StatelessWidget {
  const LogTab({super.key, required this.controller});

  final GameController controller;

  static const Map<LogKind, Color> _colors = {
    LogKind.info: Palette.fog,
    LogKind.good: Palette.moss,
    LogKind.warn: Palette.lamp,
    LogKind.bad: Palette.rust,
  };

  @override
  Widget build(BuildContext context) {
    final entries = controller.state.logEntries;

    if (entries.isEmpty) {
      return const Center(
        child: Text('Nothing has happened yet.',
            style: TextStyle(color: Palette.fog)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final day = e.tick ~/ Balance.ticksPerDay + 1;
        final hour = e.tick % Balance.ticksPerDay;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  'D$day ${hour.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                      fontSize: 10,
                      color: Palette.fog.withValues(alpha: 0.55),
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              Expanded(
                child: Text(
                  e.text,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _colors[e.kind] ?? Palette.fog),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
