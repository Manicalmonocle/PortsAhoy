/// How often the world is redrawn, and the player's say in it.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rates a player can pick. Asked for in play: "a setting that lets us
/// choose frame rate 30 (low), 60 (medium), 90 (high)".
enum FrameRate {
  low(30, 'Low'),
  medium(60, 'Medium'),
  high(90, 'High');

  const FrameRate(this.fps, this.label);
  final int fps;
  final String label;
}

class DisplaySettings {
  DisplaySettings._();

  static const String _key = 'frame_rate';

  /// What the player picked, or null if they never have.
  ///
  /// NULL IS NOT THE SAME AS MEDIUM. Left alone, the game runs at sixty and
  /// drops itself to thirty on a device that cannot draw a frame comfortably
  /// inside that; a player who picks a rate gets exactly that rate, because
  /// they asked for it and a setting that quietly overrules itself is worse
  /// than no setting.
  static final ValueNotifier<FrameRate?> chosen = ValueNotifier(null);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fps = prefs.getInt(_key);
      chosen.value = FrameRate.values.where((r) => r.fps == fps).firstOrNull;
    } catch (_) {}
  }

  static Future<void> choose(FrameRate rate) async {
    chosen.value = rate;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, rate.fps);
    } catch (_) {}
  }
}

/// Decides, on each screen refresh, whether the world should repaint.
///
/// TWO WAYS THIS WENT WRONG FIRST, both found by simulating against real
/// refresh timing rather than by reading the code:
///
///  1. "Has a whole frame's gap passed?" Frames arrive on the screen's refresh,
///     and thirty a second on a 60Hz screen is exactly two refreshes — so the
///     answer was decided by a microsecond of jitter, and whenever it was no,
///     the frame waited a third refresh. The game meant to run at 30 and ran
///     at 23.5 on a 60Hz screen and 26 on a 120Hz one, unevenly.
///  2. Calling a frame due half a refresh early fixes that for whole ratios,
///     and overshoots the rest: ninety on a 120Hz screen became 120, because
///     every refresh was "nearly" a frame's gap.
///
/// So the leftover time is CARRIED FORWARD rather than thrown away. Ninety on
/// a 120Hz screen paints three refreshes in four, sixty paints every second,
/// thirty every fourth — all exact, all even. A rate above the screen's own
/// runs at the screen's rate: there is nothing faster to show.
class FrameGate {
  double _due = 0;
  double _vsync = 1 / 60;

  /// Called on every refresh with the seconds since the last one; true when
  /// this refresh should paint at [fps].
  bool due(double dt, int fps) {
    final gap = 1 / fps;
    if (dt > 0) _vsync = _vsync * 0.9 + dt * 0.1;
    _due += dt;
    if (_due >= gap - _vsync / 2) {
      // Bounded, so a long stall cannot bank a burst of catch-up frames.
      _due = (_due - gap).clamp(-gap, gap);
      return true;
    }
    return false;
  }
}
