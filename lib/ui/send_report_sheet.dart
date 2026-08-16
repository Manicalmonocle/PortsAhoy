/// The consent sheet a player sees before a run report leaves the device.
///
/// WHY IT LOOKS LIKE THIS. This game's whole pitch is that it has no dark
/// patterns, so the one place it asks a player for something has to be the
/// cleanest screen in it. Three rules, and they are not decoration:
///
///   The payload is shown, in full, before it is sent. Not summarised, not
///   described — shown. Nobody has to take a claim about what is in it on
///   trust, and it is a better answer to "describe the data you collect" than
///   any paragraph.
///
///   Send, Copy instead and Not now carry equal weight. No pre-ticked box, no
///   greyed-out decline, no second ask on the next launch. A player who says
///   no has said no.
///
///   It is offered, never automatic. Silent upload of play data would be
///   telemetry, and shipping telemetry in a game sold on not doing this sort
///   of thing would be the exact bait-and-switch the project exists to avoid.
///
/// THE ONE TECHNICAL TRAP. On web, `launchUrl` is blocked by the popup blocker
/// unless it runs inside a real user gesture — and awaiting anything first
/// loses that gesture. So the sheet is opened first and the Send button inside
/// it is the gesture: [_send] is deliberately NOT async and calls launchUrl as
/// its first statement. Do not add an await above it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../report_endpoint.dart';
import 'theme.dart';

Future<void> showSendReportSheet(
  BuildContext context, {
  required String payload,
  required String readable,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.panel,
    isScrollControlled: true,
    builder: (_) => _SendReportSheet(payload: payload, readable: readable),
  );
}

class _SendReportSheet extends StatelessWidget {
  const _SendReportSheet({required this.payload, required this.readable});

  /// The PA1 run code — what actually travels.
  final String payload;

  /// The long human-readable report, for the clipboard route.
  final String readable;

  bool get _canSend => ReportEndpoint.url(payload) != null;

  void _send(BuildContext context) {
    // FIRST STATEMENT, AND NOT AWAITED. See the library comment above.
    final uri = ReportEndpoint.url(payload);
    if (uri != null) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tooLong = ReportEndpoint.configured && !_canSend;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            18, 16, 18, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send this run for review',
                style: TextStyle(
                    fontSize: 15,
                    color: Palette.brass,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // The payload itself, verbatim. A player can read every character
            // that would leave the device.
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Palette.deep,
                border: Border.all(color: Palette.line),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  payload,
                  style: const TextStyle(
                      fontSize: 9.5,
                      color: Palette.fog,
                      fontFamily: 'monospace',
                      height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              _canSend
                  ? 'Send opens ${ReportEndpoint.label} with the report above '
                      'already filled in — submit it there and it comes to me. '
                      'It carries the day-by-day numbers and nothing else: no '
                      'name, no email, no device id, no location. Nothing '
                      'leaves this device unless you tap Send, and the game '
                      'plays exactly the same if you never do.'
                  : tooLong
                      ? 'This run is unusually long, so it will not fit in a '
                          'link. Copy it instead and paste it wherever suits '
                          'you — nothing is lost that way.'
                      : 'No submission form is set up in this build yet. Copy '
                          'the report and paste it wherever suits you.',
              style: const TextStyle(
                  fontSize: 11.5, color: Palette.fog, height: 1.45),
            ),
            const SizedBox(height: 16),

            // Equal visual weight, deliberately. Declining must be exactly as
            // easy as accepting.
            Row(
              children: [
                if (_canSend) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _send(context),
                      style: _buttonStyle,
                      child: const Text('Send',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: readable));
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Palette.panel,
                          content: Text('Run report copied.',
                              style: TextStyle(color: Palette.fog)),
                        ),
                      );
                    },
                    style: _buttonStyle,
                    child: const Text('Copy instead',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: _buttonStyle,
                    child:
                        const Text('Not now', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _buttonStyle = OutlinedButton.styleFrom(
    foregroundColor: Palette.brass,
    side: const BorderSide(color: Palette.line),
    padding: const EdgeInsets.symmetric(vertical: 12),
  );
}
