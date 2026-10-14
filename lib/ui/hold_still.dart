/// A panel that holds still while the player is touching it.
///
/// Reported from play: "screens jump around at every tick making buying /
/// selling aggravating" — and then, "even scrolling through sheds and build
/// menu jumps around". Every panel is rebuilt from the game's state on every
/// tick, and a rebuild that adds or removes a line moves everything below it.
/// Measured on the Sheds panel, a carting run emptied every yard at once and
/// twenty entries moved together, by up to 190 pixels, mid-scroll.
///
/// So while the player has touched, dragged or scrolled a panel in the last
/// [hold], the game's own ticks do not rebuild it. The player's OWN actions —
/// adding a hand, collecting a yard, raising a shed — still show at once:
/// [GameController.actions] counts them, and a new one refreshes the panel
/// whatever the hold. When the player lets go, the panel catches up in one
/// move, while nobody is aiming at it.
///
/// Safe because the game, not the panel, decides what an action does: a
/// button left showing for a moment after it stopped applying calls the game,
/// which refuses it. The Quay has its own, finer hold (see MarketTab), because
/// there a ship can sail out from under a button.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../game_controller.dart';

class HoldStill extends StatefulWidget {
  const HoldStill({super.key, required this.controller, required this.child});

  final GameController controller;
  final Widget child;

  /// How long a panel holds still after the player last touched it.
  static const Duration hold = Duration(milliseconds: 2500);

  /// The wall clock the hold is measured on. A test sets its own.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @override
  State<HoldStill> createState() => _HoldStillState();
}

class _HoldStillState extends State<HoldStill> {
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _release;
  Widget? _shown;
  int _actions = -1;

  bool get _holding =>
      HoldStill.now().difference(_lastTouch) < HoldStill.hold;

  void _touched(PointerEvent _) {
    _lastTouch = HoldStill.now();
    _release?.cancel();
    // Catch up once the hold lapses, even on a paused port that never ticks.
    _release = Timer(HoldStill.hold, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acted = widget.controller.actions;
    if (!_holding || _shown == null || acted != _actions) {
      _shown = widget.child;
      _actions = acted;
    }
    // Every way a player moves a list: a finger, a mouse wheel — the run that
    // prompted this was on a PC — and a trackpad.
    return Listener(
      onPointerDown: _touched,
      onPointerMove: _touched,
      onPointerSignal: _touched,
      onPointerPanZoomStart: _touched,
      onPointerPanZoomUpdate: _touched,
      child: _shown,
    );
  }
}
