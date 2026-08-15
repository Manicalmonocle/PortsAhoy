import 'package:flutter/material.dart';

import '../sim/events.dart';
import '../sim/game_state.dart';
import 'theme.dart';

/// What the world is doing to you right now, and what it is about to do.
///
/// Omens are rendered as prominently as the events themselves: the whole point
/// of forewarning is that you get to act on it, and a warning nobody notices is
/// the same as no warning.
class EventBanner extends StatelessWidget {
  const EventBanner({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final live = state.events.live(state.tick).toList();
    final omens = state.events.omens(state.tick).toList();
    if (live.isEmpty && omens.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        ...live.map((e) => _EventCard(state: state, event: e, omen: false)),
        ...omens.map((e) => _EventCard(state: state, event: e, omen: true)),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.state,
    required this.event,
    required this.omen,
  });

  final GameState state;
  final ActiveEvent event;
  final bool omen;

  @override
  Widget build(BuildContext context) {
    final def = event.def;
    final boon = def.severity == EventSeverity.boon;
    final accent = boon
        ? Palette.moss
        : (omen ? Palette.lamp : Palette.rust);

    final hours =
        omen ? event.startTick - state.tick : event.endTick - state.tick;
    final days = (hours / Balance.ticksPerDay).ceil();

    var body = omen ? def.omenLine : def.blurb;
    if (def.targetsAGood && event.target != null) {
      body = '$body (${event.target!.label})';
    }

    return Card(
      color: accent.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(def.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          omen ? 'Expected: ${def.name}' : def.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        omen
                            ? 'in ${hours}h'
                            : '~$days ${days == 1 ? "day" : "days"} left',
                        style: TextStyle(
                            fontSize: 10,
                            color: Palette.fog.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 11, color: Palette.fog, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
