import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_controller.dart';
import '../report_endpoint.dart';
import '../sim/game_state.dart';
import '../sim/run_code.dart';
import '../version.dart';
import 'send_report_sheet.dart';
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
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Nothing has happened yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.fog)),
          _ExportRow(controller: controller),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _ExportRow(controller: controller);
        final e = entries[i - 1];
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

/// Copy a compact trace of this run, for calibrating the balance bot.
///
/// The bot in `tool/balance_probe.dart` is the only thing that checks a balance
/// change against more than one opinion, and it has been wrong twice in ways
/// only real play caught. Guessing at how a person plays has not worked; this
/// hands over the actual numbers instead.
class _ExportRow extends StatelessWidget {
  const _ExportRow({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final journal = s.journal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ports Ahoy! $kAppVersion · ${journal.days.length} days, '
            '${journal.marks.length} milestones',
            style: const TextStyle(fontSize: 11, color: Palette.fog),
          ),
          const SizedBox(height: 8),
          // Wrap, not Row: a second button pushed this 5.9px past the edge of
          // an iPhone SE and 21px past a small Android. Buttons that can grow
          // in number or in label length do not belong on a fixed line.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final text = journal.report(
                    charters: s.charters.ids.join(', '),
                    difficulty: s.charters.difficulty,
                    won: s.lighthouseBuilt,
                    version: kAppVersion,
                  );
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Palette.panel,
                      content: Text(
                        'Run report copied — ${journal.days.length} days. '
                        'Paste it wherever it is useful.',
                        style: const TextStyle(color: Palette.fog),
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.brass,
                  side: const BorderSide(color: Palette.line),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.copy_all_outlined, size: 15),
                label: const Text('Copy run report',
                    style: TextStyle(fontSize: 11)),
              ),
              if (ReportEndpoint.configured)
                OutlinedButton.icon(
                  onPressed: () => showSendReportSheet(
                    context,
                    payload: RunCode.encode(
                      journal,
                      version: kAppVersion,
                      seed: s.rng.seed,
                      difficulty: s.charters.difficulty,
                      charters: s.charters.ids.toList(),
                      won: s.lighthouseBuilt,
                      maxChars: ReportEndpoint.maxPayload,
                    ),
                    readable: journal.report(
                      charters: s.charters.ids.join(', '),
                      difficulty: s.charters.difficulty,
                      won: s.lighthouseBuilt,
                      version: kAppVersion,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.brass,
                    side: const BorderSide(color: Palette.line),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.outbox_outlined, size: 15),
                  label: const Text('Send', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A day-by-day trace of this port — population, coin, sheds, food '
            'and hulls at sea — plus every build, hire and consignment. Used '
            'to make the balance bot play the way people actually do.',
            style: TextStyle(fontSize: 10.5, color: Palette.fog, height: 1.35),
          ),
          const Divider(height: 18, color: Palette.line),
        ],
      ),
    );
  }
}
