import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3, Vector4;

import '../game_controller.dart';
import '../sim/buildings.dart';
import '../sim/game_state.dart';
import '../sim/terrain.dart';
import 'theme.dart';

/// The port as a real 3D scene.
///
/// Not isometric: there is an actual camera with a position, a look-at target
/// and a perspective frustum, and every polygon is projected through it. That
/// buys three things a 2:1 diamond grid cannot have — true perspective (near
/// things are bigger and the grid converges), a camera you can **orbit**, and
/// per-face lighting from a fixed sun.
///
/// It is still one `CustomPainter`: the geometry is small enough that
/// projecting and depth-sorting it by hand each frame is cheaper than pulling
/// in a 3D engine, and it runs identically on web and mobile.
class WorldView extends StatefulWidget {
  const WorldView({
    super.key,
    required this.controller,
    required this.onInspect,
    this.onTapEmpty,
    this.selected,
    this.fullBleed = false,
    this.initialCamera,
  });

  /// Where the camera starts. Null frames the whole island, which is what the
  /// game wants; the visual harness passes a close orbit so a single shed can
  /// be judged at a size where its details are visible.
  final Camera3D? initialCamera;

  final GameController controller;
  final void Function(int buildingIndex) onInspect;
  final VoidCallback? onTapEmpty;
  final int? selected;
  final bool fullBleed;

  @override
  State<WorldView> createState() => _WorldViewState();
}

/// Where the camera is and what it is looking at.
class Camera3D {
  Camera3D({
    required this.target,
    this.yaw = -0.78,
    this.pitch = 0.92,
    double? distance,
  }) : distance = distance ?? defaultDistance;

  /// Framed from the island rather than a magic number, so growing the map
  /// does not silently push the far edge off screen.
  static double get defaultDistance => Terrain.size * 0.92;

  /// Point on the ground the camera orbits.
  Vector3 target;

  /// Rotation about the vertical axis, in radians.
  double yaw;

  /// Tilt above the horizon. 0 is level, pi/2 is straight down.
  double pitch;

  double distance;


  static const double minPitch = 0.42;
  static const double maxPitch = 1.35;
  static const double minDistance = 7;
  static double get maxDistance => Terrain.size * 2.4;

  Vector3 get eye {
    final horizontal = math.cos(pitch) * distance;
    return Vector3(
      target.x + math.cos(yaw) * horizontal,
      target.y + math.sin(pitch) * distance,
      target.z + math.sin(yaw) * horizontal,
    );
  }

  /// Unit vector pointing right on screen, in world space — used to turn a
  /// finger drag into a movement across the ground.
  Vector3 get right => Vector3(-math.sin(yaw), 0, math.cos(yaw));

  /// Unit vector pointing "up the screen" along the ground.
  Vector3 get forward => Vector3(-math.cos(yaw), 0, -math.sin(yaw));

  Matrix4 viewProjection(Size size) {
    final aspect = size.width / math.max(size.height, 1);
    final projection = Matrix4.identity();
    _setPerspective(projection, 42 * math.pi / 180, aspect, 0.6, 400);
    final view = _lookAt(eye, target, Vector3(0, 1, 0));
    return projection * view;
  }

  static void _setPerspective(
      Matrix4 m, double fovY, double aspect, double near, double far) {
    final f = 1 / math.tan(fovY / 2);
    m.setZero();
    m.setEntry(0, 0, f / aspect);
    m.setEntry(1, 1, f);
    m.setEntry(2, 2, (far + near) / (near - far));
    m.setEntry(2, 3, 2 * far * near / (near - far));
    m.setEntry(3, 2, -1);
  }

  static Matrix4 _lookAt(Vector3 eye, Vector3 target, Vector3 up) {
    final f = (target - eye).normalized();
    final s = f.cross(up).normalized();
    final u = s.cross(f);
    final m = Matrix4.identity();
    m.setValues(
      s.x, u.x, -f.x, 0, //
      s.y, u.y, -f.y, 0, //
      s.z, u.z, -f.z, 0, //
      -s.dot(eye), -u.dot(eye), f.dot(eye), 1,
    );
    return m;
  }
}

/// A point projected to the screen, with the depth it landed at.
class Projected {
  const Projected(this.screen, this.depth, this.visible);
  final Offset screen;
  final double depth;
  final bool visible;
}

/// Turns world points into screen points, and screen points back into world
/// positions on the ground. Public so the projection can be tested directly.
class Projector {
  Projector(this.camera, this.size) : _vp = camera.viewProjection(size);

  final Camera3D camera;
  final Size size;
  final Matrix4 _vp;

  Projected project(Vector3 p) {
    final v = _vp.transform(Vector4(p.x, p.y, p.z, 1));
    if (v.w <= 0.01) return const Projected(Offset.zero, -1, false);
    final ndcX = v.x / v.w;
    final ndcY = v.y / v.w;
    return Projected(
      Offset((ndcX * 0.5 + 0.5) * size.width, (0.5 - ndcY * 0.5) * size.height),
      v.w,
      true,
    );
  }

  /// Where a screen point meets the ground plane at [groundY].
  Vector3? toGround(Offset screen, {double groundY = 0}) {
    final inv = Matrix4.inverted(_vp);
    final ndcX = (screen.dx / size.width) * 2 - 1;
    final ndcY = 1 - (screen.dy / size.height) * 2;

    Vector3 unproject(double z) {
      final v = inv.transform(Vector4(ndcX, ndcY, z, 1));
      return Vector3(v.x / v.w, v.y / v.w, v.z / v.w);
    }

    final near = unproject(-1);
    final far = unproject(1);
    final dir = far - near;
    if (dir.y.abs() < 1e-9) return null;
    final t = (groundY - near.y) / dir.y;
    if (t < 0) return null;
    return near + dir * t;
  }
}

// ---------------------------------------------------------------------------

/// One tile is one world unit.
const double kTile = 1.0;

/// Ground height by terrain, which is what makes the island read as a solid
/// object sitting in water rather than a texture painted on a plane.
double heightOf(Tile t) => switch (t) {
      Tile.water => -0.42,
      Tile.sand => 0.0,
      Tile.grass => 0.16,
      Tile.trees => 0.16,
      Tile.rock => 0.34,
    };

Vector3 tileCorner(num col, num row, double y) => Vector3(
      (col - Terrain.size / 2) * kTile,
      y,
      (row - Terrain.size / 2) * kTile,
    );

class _WorldViewState extends State<WorldView> {
  late final Camera3D _camera =
      widget.initialCamera ?? Camera3D(target: Vector3.zero());

  int? _dragging;
  Point? _dropAt;
  bool _dropValid = false;

  // Gesture bookkeeping.
  double _startDistance = 0;
  double _startYaw = 0;
  Offset _lastFocal = Offset.zero;
  Size _size = Size.zero;

  Projector get _proj => Projector(_camera, _size);

  /// The tile under a screen point, or null if it missed the island.
  Point? _tileAt(Offset screen) {
    final hit = _proj.toGround(screen, groundY: heightOf(Tile.grass));
    if (hit == null) return null;
    final col = (hit.x / kTile + Terrain.size / 2).floor();
    final row = (hit.z / kTile + Terrain.size / 2).floor();
    if (col < 0 || row < 0 || col >= Terrain.size || row >= Terrain.size) {
      return null;
    }
    return Point(col, row);
  }

  int? _buildingAt(Offset screen) {
    final t = _tileAt(screen);
    if (t == null) return null;
    final state = widget.controller.state;
    final b = state.buildingAt(t.x, t.y);
    if (b == null) return null;
    return state.buildings.indexOf(b);
  }

  void _onTapUp(TapUpDetails d) {
    final i = _buildingAt(d.localPosition);
    if (i == null) {
      widget.onTapEmpty?.call();
      return;
    }
    widget.onInspect(i);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final i = _buildingAt(d.localPosition);
    if (i == null) return;
    final b = widget.controller.state.buildings[i];
    setState(() {
      _dragging = i;
      _dropAt = Point(b.col, b.row);
      _dropValid = true;
    });
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final i = _dragging;
    if (i == null) return;
    final t = _tileAt(d.localPosition);
    if (t == null) return;

    final state = widget.controller.state;
    final b = state.buildings[i];
    final f = b.def.footprint;
    final col = t.x - (f - 1) ~/ 2;
    final row = t.y - (f - 1) ~/ 2;

    setState(() {
      _dropAt = Point(col, row);
      _dropValid = state.canPlaceAt(b.def, col, row, ignore: b);
    });
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    final i = _dragging;
    final drop = _dropAt;
    if (i != null && drop != null && _dropValid) {
      widget.controller
          .act((s) => s.moveBuilding(s.buildings[i], drop.x, drop.y));
    }
    setState(() {
      _dragging = null;
      _dropAt = null;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startDistance = _camera.distance;
    _startYaw = _camera.yaw;
    _lastFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_dragging != null) return; // a shed is in hand; leave the camera alone

    setState(() {
      if (d.pointerCount >= 2) {
        _camera.distance = (_startDistance / d.scale)
            .clamp(Camera3D.minDistance, Camera3D.maxDistance);
        // Two-finger twist orbits the camera — the clearest proof it is 3D.
        _camera.yaw = _startYaw + d.rotation;
      }

      // Drag the ground under the finger.
      final delta = d.localFocalPoint - _lastFocal;
      _lastFocal = d.localFocalPoint;
      final scale = _camera.distance / math.max(_size.height, 1) * 1.6;
      _camera.target += _camera.right * (-delta.dx * scale) +
          _camera.forward * (delta.dy * scale);
      _clampTarget();
    });
  }

  void _clampTarget() {
    const half = Terrain.size * kTile / 2 + 3;
    _camera.target.x = _camera.target.x.clamp(-half, half);
    _camera.target.z = _camera.target.z.clamp(-half, half);
  }

  void _orbit(double by) => setState(() => _camera.yaw += by);
  void _tilt(double by) => setState(() =>
      _camera.pitch = (_camera.pitch + by).clamp(Camera3D.minPitch, Camera3D.maxPitch));
  void _zoom(double by) => setState(() => _camera.distance =
      (_camera.distance * by).clamp(Camera3D.minDistance, Camera3D.maxDistance));

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.fullBleed
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      height: widget.fullBleed ? null : 380,
      decoration: BoxDecoration(
        color: const Color(0xFF0F3346),
        borderRadius: widget.fullBleed ? null : BorderRadius.circular(14),
        border: widget.fullBleed ? null : Border.all(color: Palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          // Clear the dock and whatever system bar sits under it.
          final safeBottom = widget.fullBleed
              ? MediaQuery.viewPaddingOf(context).bottom + kDockHeight
              : 0.0;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onLongPressStart: _onLongPressStart,
                  onLongPressMoveUpdate: _onLongPressMove,
                  onLongPressEnd: _onLongPressEnd,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: CustomPaint(
                    painter: _ScenePainter(
                      state: widget.controller.state,
                      camera: _camera,
                      dragging: _dragging,
                      dropAt: _dropAt,
                      dropValid: _dropValid,
                      selected: widget.selected,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                // Stop well short of the right edge: the Collect button lives
                // there and the hint was disappearing underneath it.
                width: constraints.maxWidth * 0.56,
                bottom: (widget.fullBleed ? 8 : 8) + safeBottom,
                child: Text(
                  _dragging != null
                      ? (_dropValid ? 'Release to place' : 'Cannot build here')
                      : 'Tap to manage · hold to move · twist to turn',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _dragging != null
                        ? (_dropValid ? Palette.moss : Palette.rust)
                        : Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: (widget.fullBleed ? 74 : 8) + safeBottom,
                child: Column(
                  children: [
                    Row(
                      children: [
                        _MapButton(
                            icon: Icons.rotate_left,
                            onTap: () => _orbit(-math.pi / 8)),
                        const SizedBox(width: 6),
                        _MapButton(
                            icon: Icons.rotate_right,
                            onTap: () => _orbit(math.pi / 8)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Deliberately not a plain chevron: that is the panel
                        // close affordance, and two meanings for one glyph is
                        // a coin-toss for the player.
                        _MapButton(
                            icon: Icons.keyboard_double_arrow_up,
                            onTap: () => _tilt(0.12)),
                        const SizedBox(width: 6),
                        _MapButton(
                            icon: Icons.keyboard_double_arrow_down,
                            onTap: () => _tilt(-0.12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _MapButton(
                            icon: Icons.remove, onTap: () => _zoom(1.25)),
                        const SizedBox(width: 6),
                        _MapButton(icon: Icons.add, onTap: () => _zoom(0.8)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A tiny integer point.
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      );
}

// ---------------------------------------------------------------------------

/// One polygon queued for drawing, with the depth it sorts at.
class _Face {
  _Face(this.depth, this.points, this.colour, {this.stroke});
  final double depth;
  final List<Offset> points;
  final Color colour;
  final Color? stroke;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.state,
    required this.camera,
    required this.dragging,
    required this.dropAt,
    required this.dropValid,
    required this.selected,
  });

  final GameState state;
  final Camera3D camera;
  final int? dragging;
  final Point? dropAt;
  final bool dropValid;
  final int? selected;

  /// A fixed sun, so every face has a stable brightness and the scene reads as
  /// lit rather than merely coloured.
  static final Vector3 _sun = Vector3(-0.45, 0.82, -0.35).normalized();

  static double _hash(int n, [int salt = 0]) {
    final x = math.sin((n + 1) * 12.9898 + salt * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  late Projector _p;
  final List<_Face> _queue = [];

  @override
  void paint(Canvas canvas, Size size) {
    _p = Projector(camera, size);
    _queue.clear();

    _paintSky(canvas, size);
    // The ground is a single smooth mesh, drawn straight to the canvas before
    // the depth-sorted props that stand on it.
    _paintTerrainMesh(canvas);
    _buildScatter();
    _buildBuildings();
    _buildDropHint();

    // Painter's algorithm: far polygons first.
    _queue.sort((a, b) => b.depth.compareTo(a.depth));
    for (final f in _queue) {
      if (f.points.length < 3) continue;
      final path = Path()..addPolygon(f.points, true);
      canvas.drawPath(path, Paint()..color = f.colour);
      if (f.stroke != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = f.stroke!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    _paintOverlays(canvas);
  }

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF23566B), Color(0xFF0E2C3B)],
        ).createShader(Offset.zero & size),
    );
  }

  /// Shade a colour by how squarely a face meets the sun.
  Color _lit(Color base, Vector3 normal) {
    final lambert = normal.dot(_sun).clamp(-1.0, 1.0);
    final k = 0.52 + 0.48 * ((lambert + 1) / 2);
    return Color.from(
      alpha: base.a,
      red: (base.r * k).clamp(0.0, 1.0),
      green: (base.g * k).clamp(0.0, 1.0),
      blue: (base.b * k).clamp(0.0, 1.0),
    );
  }

  void _quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color colour,
      {Color? stroke, bool cull = true}) {
    final pa = _p.project(a);
    final pb = _p.project(b);
    final pc = _p.project(c);
    final pd = _p.project(d);
    if (!pa.visible || !pb.visible || !pc.visible || !pd.visible) return;

    final pts = [pa.screen, pb.screen, pc.screen, pd.screen];
    if (cull) {
      // Signed area: drop polygons facing away from the camera.
      var area = 0.0;
      for (var i = 0; i < 4; i++) {
        final p1 = pts[i];
        final p2 = pts[(i + 1) % 4];
        area += p1.dx * p2.dy - p2.dx * p1.dy;
      }
      if (area >= 0) return;
    }
    final depth = (pa.depth + pb.depth + pc.depth + pd.depth) / 4;
    _queue.add(_Face(depth, pts, colour, stroke: stroke));
  }

  // ---- Terrain ----------------------------------------------------------

  /// A gentle sum-of-sines swell at a world position, so the whole sea moves
  /// as one surface instead of a grid of flat diamonds.
  double _waveY(double x, double z, int tick) {
    final t = tick * 0.18;
    return math.sin(x * 0.9 + t) * 0.045 +
        math.sin(z * 0.7 - t * 0.8) * 0.045 +
        math.sin((x + z) * 0.5 + t * 1.3) * 0.03;
  }

  /// The base colour of a single tile, before blending. Kept narrow-range so
  /// neighbours are close; the smoothing happens by averaging across the four
  /// tiles that meet at a vertex, not by per-tile randomness.
  Color _tileColour(Tile t, int col, int row) {
    final n = math.sin(col * 0.55 + row * 0.3) * 0.5 +
        math.sin(col * 0.2 - row * 0.65) * 0.5;
    final k = (n * 0.5 + 0.5).clamp(0.0, 1.0);
    return switch (t) {
      Tile.water =>
        Color.lerp(const Color(0xFF175066), const Color(0xFF236F8A), k)!,
      Tile.sand => Color.lerp(const Color(0xFFCDB183), const Color(0xFFE0C79C), k)!,
      Tile.rock => Color.lerp(const Color(0xFF767A6D), const Color(0xFF8B907E), k)!,
      _ => Color.lerp(const Color(0xFF578F3E), const Color(0xFF669A4C), k)!,
    };
  }

  /// The height at a grid VERTEX: the average of the four tiles meeting there.
  /// This is what rounds the coastline — a vertex where grass meets water sits
  /// halfway, so the beach slopes down into the sea instead of dropping off a
  /// cliff. Water gets its swell added on top.
  double _vertexHeight(int vc, int vr, int tick) {
    var sum = 0.0, wave = 0.0, waterN = 0;
    for (final d in const [[-1, -1], [0, -1], [-1, 0], [0, 0]]) {
      final tile = Terrain.at(vc + d[0], vr + d[1]);
      sum += heightOf(tile);
      if (tile == Tile.water) waterN++;
    }
    final y = sum / 4;
    if (waterN > 0) {
      final wp = tileCorner(vc, vr, 0);
      // Ripple only where there is actually water, easing out toward the shore.
      wave = _waveY(wp.x, wp.z, tick) * (waterN / 4);
    }
    return y + wave;
  }

  /// The blended colour at a grid vertex: the average of the four tiles meeting
  /// there. This is what dissolves the checkerboard and the hard sand/grass
  /// line into a smooth transition.
  Color _vertexColour(int vc, int vr) {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final d in const [[-1, -1], [0, -1], [-1, 0], [0, 0]]) {
      final tile = Terrain.at(vc + d[0], vr + d[1]);
      final c = _tileColour(tile, vc + d[0], vr + d[1]);
      r += c.r;
      g += c.g;
      b += c.b;
    }
    return Color.from(alpha: 1, red: r / 4, green: g / 4, blue: b / 4);
  }

  /// The island and sea as one smooth Gouraud-shaded mesh.
  ///
  /// WHY THIS IS NOT IN THE FACE QUEUE. Every other polygon is a flat colour,
  /// drawn as a filled path and depth-sorted by hand. The terrain used to be
  /// too — one flat diamond per tile — which is exactly what read as blocky:
  /// hard seams between tiles, a stair-stepped coast, a checkerboard of greens.
  /// Blending needs per-vertex colour interpolated ACROSS each triangle, which
  /// a filled path cannot do; `drawVertices` interpolates in hardware. So the
  /// ground is drawn first as one mesh, and the props (buildings, trees) sort
  /// among themselves on top of it — safe because the island is nearly flat,
  /// so terrain never occludes a prop standing on it.
  void _paintTerrainMesh(Canvas canvas) {
    final tick = state.tick;
    const n = Terrain.size;

    // Per-vertex world height, screen position and lit colour.
    final h = List.generate(n + 1, (vc) =>
        List.generate(n + 1, (vr) => _vertexHeight(vc, vr, tick)));

    final screen = List.generate(n + 1, (vc) => List<Offset?>.filled(n + 1, null));
    final colour = List.generate(n + 1, (vc) => List<Color>.filled(n + 1, const Color(0xFF000000)));
    for (var vc = 0; vc <= n; vc++) {
      for (var vr = 0; vr <= n; vr++) {
        final p = _p.project(tileCorner(vc, vr, h[vc][vr]));
        screen[vc][vr] = p.visible ? p.screen : null;
        // Normal from the height gradient, for smooth (per-vertex) lighting.
        final hx = h[(vc + 1).clamp(0, n)][vr] - h[(vc - 1).clamp(0, n)][vr];
        final hz = h[vc][(vr + 1).clamp(0, n)] - h[vc][(vr - 1).clamp(0, n)];
        final normal = Vector3(-hx, 2 * kTile, -hz)..normalize();
        colour[vc][vr] = _lit(_vertexColour(vc, vr), normal);
      }
    }

    final positions = <Offset>[];
    final colors = <Color>[];
    void tri(int ac, int ar, int bc, int br, int cc, int cr) {
      final pa = screen[ac][ar], pb = screen[bc][br], pc = screen[cc][cr];
      if (pa == null || pb == null || pc == null) return;
      positions..add(pa)..add(pb)..add(pc);
      colors..add(colour[ac][ar])..add(colour[bc][br])..add(colour[cc][cr]);
    }

    for (var vc = 0; vc < n; vc++) {
      for (var vr = 0; vr < n; vr++) {
        tri(vc, vr, vc + 1, vr, vc + 1, vr + 1);
        tri(vc, vr, vc + 1, vr + 1, vc, vr + 1);
      }
    }

    if (positions.isEmpty) return;
    final verts = ui.Vertices(ui.VertexMode.triangles, positions, colors: colors);
    // modulate against white so the vertex colours show through unchanged.
    canvas.drawVertices(verts, BlendMode.modulate,
        Paint()..color = const Color(0xFFFFFFFF));
  }

  /// Trees, rocks and other ground scatter, still flat-shaded in the queue.
  void _buildScatter() {
    for (var col = 0; col < Terrain.size; col++) {
      for (var row = 0; row < Terrain.size; row++) {
        final t = Terrain.at(col, row);
        final y = _vertexHeight(col, row, 0) + 0.02;
        if (t == Tile.trees) _buildTrees(col, row, y);
        if (t == Tile.rock) _buildRock(col, row, y);
      }
    }
  }


  void _buildTrees(int col, int row, double y) {
    final v = _hash(col * 17 + row * 91, 3);
    for (var i = 0; i < 2; i++) {
      final cx = (col - Terrain.size / 2 + 0.3 + i * 0.4) * kTile;
      final cz = (row - Terrain.size / 2 + 0.35 + v * 0.3) * kTile;
      final s = 0.34 + _hash(col * 7 + row * 3 + i, 4) * 0.16;
      _cone(Vector3(cx, y, cz), s, s * 3.4, const Color(0xFF2F5A32));
      _box(
        Vector3(cx - 0.05, y, cz - 0.05),
        Vector3(cx + 0.05, y + s * 1.1, cz + 0.05),
        const Color(0xFF4A3826),
      );
    }
  }

  void _buildRock(int col, int row, double y) {
    final cx = (col - Terrain.size / 2 + 0.5) * kTile;
    final cz = (row - Terrain.size / 2 + 0.5) * kTile;
    _box(
      Vector3(cx - 0.30, y, cz - 0.26),
      Vector3(cx + 0.30, y + 0.34, cz + 0.26),
      const Color(0xFF7B8073),
    );
  }

  /// An axis-aligned box, drawn as six culled and lit quads.
  void _box(Vector3 min, Vector3 max, Color base, {Color? topColour}) {
    final c000 = Vector3(min.x, min.y, min.z);
    final c100 = Vector3(max.x, min.y, min.z);
    final c101 = Vector3(max.x, min.y, max.z);
    final c001 = Vector3(min.x, min.y, max.z);
    final c010 = Vector3(min.x, max.y, min.z);
    final c110 = Vector3(max.x, max.y, min.z);
    final c111 = Vector3(max.x, max.y, max.z);
    final c011 = Vector3(min.x, max.y, max.z);

    _quad(c010, c110, c111, c011, _lit(topColour ?? base, Vector3(0, 1, 0)),
        cull: false);
    _quad(c000, c100, c110, c010, _lit(base, Vector3(0, 0, -1)), cull: false);
    _quad(c101, c001, c011, c111, _lit(base, Vector3(0, 0, 1)), cull: false);
    _quad(c100, c101, c111, c110, _lit(base, Vector3(1, 0, 0)), cull: false);
    _quad(c001, c000, c010, c011, _lit(base, Vector3(-1, 0, 0)), cull: false);
  }

  /// A four-sided pyramid — used for roofs and treetops.
  void _cone(Vector3 base, double radius, double height, Color colour) {
    final apex = Vector3(base.x, base.y + height, base.z);
    final corners = [
      Vector3(base.x - radius, base.y + height * 0.28, base.z - radius),
      Vector3(base.x + radius, base.y + height * 0.28, base.z - radius),
      Vector3(base.x + radius, base.y + height * 0.28, base.z + radius),
      Vector3(base.x - radius, base.y + height * 0.28, base.z + radius),
    ];
    const normals = [
      [0.0, 0.4, -1.0],
      [1.0, 0.4, 0.0],
      [0.0, 0.4, 1.0],
      [-1.0, 0.4, 0.0],
    ];
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final n = Vector3(normals[i][0], normals[i][1], normals[i][2]).normalized();
      final pa = _p.project(a);
      final pb = _p.project(b);
      final pc = _p.project(apex);
      if (!pa.visible || !pb.visible || !pc.visible) continue;
      final depth = (pa.depth + pb.depth + pc.depth) / 3;
      _queue.add(_Face(depth, [pa.screen, pb.screen, pc.screen], _lit(colour, n)));
    }
  }

  // ---- Buildings ---------------------------------------------------------

  void _buildBuildings() {
    for (var i = 0; i < state.buildings.length; i++) {
      final b = state.buildings[i];
      if (!b.isPlaced) continue;
      if (i == dragging) continue;
      _buildShed(b, b.col, b.row, i);
    }
    final d = dragging;
    final at = dropAt;
    if (d != null && at != null) {
      _buildShed(state.buildings[d], at.x, at.y, d);
    }
  }


  // ---- Shape vocabulary for the sheds ------------------------------------
  //
  // Every building used to be one _box and one _cone, in a different brown.
  // Seventeen sheds, one silhouette: a farm, a smithy and a mine were the
  // same pyramid-roofed cube, and the only way to tell them apart was the
  // label. These few primitives are enough to give each its own outline —
  // a ridge instead of a point, a chimney, a jetty, a wheel, a crop row —
  // and they stay in the same flat-lit low-poly language as everything else,
  // so the orbit camera keeps working from any angle.

  /// A lit, depth-sorted polygon. The normal is taken from the winding
  /// unless [awayFrom] is given, in which case it is flipped to face away from
  /// that point — which is what a wall or a roof slope always wants.
  void _poly(List<Vector3> pts, Color base, {Vector3? awayFrom}) {
    var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]);
    if (n.length2 == 0) return;
    n.normalize();
    if (awayFrom != null) {
      final centroid = pts.fold(Vector3.zero(), (a, b) => a + b) / pts.length.toDouble();
      if (n.dot(centroid - awayFrom) < 0) n = -n;
    }
    final screen = <Offset>[];
    var depth = 0.0;
    for (final p in pts) {
      final pr = _p.project(p);
      if (!pr.visible) return;
      screen.add(pr.screen);
      depth += pr.depth;
    }
    _queue.add(_Face(depth / pts.length, screen, _lit(base, n)));
  }

  /// Walls plus a ridged roof, the shape a shed actually has.
  void _gable(Vector3 min, Vector3 max, double wallH, double ridgeH,
      Color wall, Color roof, {bool alongX = true, double overhang = 0.08}) {
    _box(min, Vector3(max.x, min.y + wallH, max.z), wall);
    final y0 = min.y + wallH;
    final top = y0 + ridgeH;
    final cx = (min.x + max.x) / 2, cz = (min.z + max.z) / 2;
    final centre = Vector3(cx, y0, cz);
    final o = overhang;
    // The gable ends sit a hair inside the roof line. Depth-sorting by
    // centroid can put a far gable in front of a near slope, and then its
    // point shows through the roof; tucking it under makes the order moot.
    final gt = top - 0.03;
    if (alongX) {
      _poly([Vector3(min.x - o, y0, min.z - o), Vector3(max.x + o, y0, min.z - o),
        Vector3(max.x + o, top, cz), Vector3(min.x - o, top, cz)], roof, awayFrom: centre);
      _poly([Vector3(min.x - o, y0, max.z + o), Vector3(max.x + o, y0, max.z + o),
        Vector3(max.x + o, top, cz), Vector3(min.x - o, top, cz)], roof, awayFrom: centre);
      _poly([Vector3(min.x, y0, min.z), Vector3(min.x, y0, max.z), Vector3(min.x, gt, cz)],
          wall, awayFrom: centre);
      _poly([Vector3(max.x, y0, min.z), Vector3(max.x, y0, max.z), Vector3(max.x, gt, cz)],
          wall, awayFrom: centre);
    } else {
      _poly([Vector3(min.x - o, y0, min.z - o), Vector3(min.x - o, y0, max.z + o),
        Vector3(cx, top, max.z + o), Vector3(cx, top, min.z - o)], roof, awayFrom: centre);
      _poly([Vector3(max.x + o, y0, min.z - o), Vector3(max.x + o, y0, max.z + o),
        Vector3(cx, top, max.z + o), Vector3(cx, top, min.z - o)], roof, awayFrom: centre);
      _poly([Vector3(min.x, y0, min.z), Vector3(max.x, y0, min.z), Vector3(cx, gt, min.z)],
          wall, awayFrom: centre);
      _poly([Vector3(min.x, y0, max.z), Vector3(max.x, y0, max.z), Vector3(cx, gt, max.z)],
          wall, awayFrom: centre);
    }
  }

  /// A thin upright post.
  void _pole(double x, double z, double y0, double h, double t, Color c) =>
      _box(Vector3(x - t, y0, z - t), Vector3(x + t, y0 + h, z + t), c);

  /// A flat lying block: a plank, a crate, a crop row, a jetty.
  void _slab(double x0, double z0, double x1, double z1, double y0, double h,
          Color c, {Color? top}) =>
      _box(Vector3(x0, y0, z0), Vector3(x1, y0 + h, z1), c, topColour: top);

  /// A barrel: a squat block with a darker band, which at this size reads.
  void _barrel(double x, double z, double y0, Color c) {
    const r = 0.11;
    _box(Vector3(x - r, y0, z - r), Vector3(x + r, y0 + 0.22, z + r), c,
        topColour: Color.lerp(c, Colors.black, 0.35));
    _box(Vector3(x - r - 0.01, y0 + 0.08, z - r - 0.01),
        Vector3(x + r + 0.01, y0 + 0.12, z + r + 0.01),
        Color.lerp(c, Colors.black, 0.45)!);
  }

  /// Rising smoke: a few soft squares, offset and thinned by the tick so a
  /// working chimney visibly works. Tick-driven, like the water, so a paused
  /// port is genuinely still.
  void _smoke(double x, double y0, double z, int tick) {
    for (var i = 0; i < 4; i++) {
      final t = ((tick * 0.15) + i * 0.25) % 1.0;
      final y = y0 + t * 0.9;
      final r = 0.06 + t * 0.09;
      final drift = math.sin((tick + i * 7) * 0.2) * 0.05 + t * 0.12;
      final a = (1 - t) * 0.5;
      // A small cube rather than a screen-space blob: it lives in the world,
      // so it is the right size at every distance and from every angle the
      // camera can be turned to, and it depth-sorts with the chimney.
      _box(Vector3(x + drift - r, y - r, z - r), Vector3(x + drift + r, y + r, z + r),
          Color.fromRGBO(222, 222, 228, a));
    }
  }

  /// A low-poly tree: a trunk and two stacked cones.
  void _tree(double x, double z, double y0, double h, Color leaf, Color trunk) {
    _pole(x, z, y0, h * 0.35, 0.05, trunk);
    _cone(Vector3(x, y0 + h * 0.25, z), h * 0.34, h * 0.55, leaf);
    _cone(Vector3(x, y0 + h * 0.55, z), h * 0.24, h * 0.45, leaf);
  }

  /// Four blades turning about a horizontal axle along z. Windmill sails, or
  /// the spokes of a wheel — the same thing at two sizes.
  void _blades(double x, double y, double z, double r, double w, Color c,
      double angle) {
    for (var i = 0; i < 4; i++) {
      final a = angle + i * math.pi / 2;
      final dx = math.cos(a), dy = math.sin(a);
      final px = -dy * w, py = dx * w; // perpendicular, for blade width
      _poly([
        Vector3(x + px * 0.3, y + py * 0.3, z),
        Vector3(x + dx * r + px, y + dy * r + py, z),
        Vector3(x + dx * r - px, y + dy * r - py, z),
        Vector3(x - px * 0.3, y - py * 0.3, z),
      ], c, awayFrom: Vector3(x, y, z - 1));
    }
  }

  double _groundUnder(int col, int row, int f) {
    var y = -1.0;
    for (var c = col; c < col + f; c++) {
      for (var r = row; r < row + f; r++) {
        final h = heightOf(Terrain.at(c, r));
        if (h > y) y = h;
      }
    }
    return y;
  }

  void _buildShed(Building b, int col, int row, int index) {
    final def = b.def;
    final f = def.footprint;
    final style = _styleFor(def.id);
    final staffed = b.workers > 0;
    final y = _groundUnder(col, row, f);

    const inset = 0.14;
    final min = tileCorner(col, row, y) + Vector3(inset, 0, inset);
    final max = tileCorner(col + f, row + f, y) - Vector3(inset, 0, inset);

    // Unstaffed sheds sit dim and, where they have one, cold: no smoke, no
    // turning wheel. The scene should tell you what is working.
    final dim = staffed ? 1.0 : 0.66;
    Color sh(Color c) => Color.lerp(const Color(0xFF33402C), c, dim)!;

    final wall = sh(style.wall), roof = sh(style.roof);
    final cx = (min.x + max.x) / 2, cz = (min.z + max.z) / 2;
    final w = max.x - min.x, d = max.z - min.z;
    final tick = state.tick;
    const timber = Color(0xFF6B4E2E);
    const dark = Color(0xFF2A2420);
    const leaf = Color(0xFF3F6B3A);
    final crate = sh(const Color(0xFF9C7B4F));

    switch (def.id) {
      case 'house':
        _gable(min, max, 0.5, 0.42, wall, roof);
        _pole(max.x - 0.22, cz - 0.2, y + 0.5, 0.42, 0.06, sh(dark));
        // A door on the sunward face.
        _poly([Vector3(cx - 0.12, y, min.z - 0.001), Vector3(cx + 0.12, y, min.z - 0.001),
          Vector3(cx + 0.12, y + 0.32, min.z - 0.001), Vector3(cx - 0.12, y + 0.32, min.z - 0.001)],
          dark, awayFrom: Vector3(cx, y, cz));

      case 'farm':
        // A small farmhouse in one corner, and the rest of the plot in rows.
        _gable(Vector3(min.x, y, min.z), Vector3(min.x + 0.62, y, min.z + 0.62),
            0.4, 0.34, wall, roof);
        for (var i = 0; i < 5; i++) {
          final z0 = min.z + 0.05 + i * (d - 0.1) / 5;
          final g = i.isEven ? const Color(0xFF6E9A3E) : const Color(0xFF86AC4A);
          _slab(min.x + 0.75, z0 + 0.03, max.x - 0.05, z0 + (d - 0.1) / 5 - 0.06,
              y, 0.09, sh(const Color(0xFF7C5A32)), top: sh(g));
        }

      case 'flax_field':
        // Flax flowers blue. Rows and nothing else — it is a field.
        for (var i = 0; i < 6; i++) {
          final z0 = min.z + 0.03 + i * (d - 0.06) / 6;
          final blue = i.isEven ? const Color(0xFF6F8FB0) : const Color(0xFF7FA0C0);
          _slab(min.x + 0.04, z0 + 0.02, max.x - 0.04, z0 + (d - 0.06) / 6 - 0.05,
              y, 0.11, sh(const Color(0xFF5E7A3A)), top: sh(blue));
        }

      case 'forest_camp':
        _tree(min.x + 0.4, min.z + 0.45, y, 1.05, sh(leaf), sh(timber));
        _tree(max.x - 0.38, min.z + 0.5, y, 0.9, sh(leaf), sh(timber));
        // A lean-to: a slab roof on two posts.
        _pole(min.x + 0.35, max.z - 0.3, y, 0.42, 0.04, sh(timber));
        _pole(min.x + 0.95, max.z - 0.3, y, 0.42, 0.04, sh(timber));
        _poly([Vector3(min.x + 0.25, y + 0.42, max.z - 0.2),
          Vector3(min.x + 1.05, y + 0.42, max.z - 0.2),
          Vector3(min.x + 1.05, y + 0.28, max.z - 0.8),
          Vector3(min.x + 0.25, y + 0.28, max.z - 0.8)], roof, awayFrom: Vector3(cx, y, cz));
        // A log pile.
        for (var i = 0; i < 3; i++) {
          _slab(max.x - 0.55, max.z - 0.62 + i * 0.02, max.x - 0.08,
              max.z - 0.5 + i * 0.02, y + i * 0.11, 0.1, sh(timber));
        }

      case 'fishing_wharf':
        _gable(Vector3(min.x, y, min.z), Vector3(min.x + 0.8, y, min.z + 0.7),
            0.4, 0.32, wall, roof);
        // A jetty running out past the plot, and a boat alongside it.
        _slab(cx - 0.12, min.z + 0.9, cx + 0.12, max.z + 0.55, y + 0.05, 0.06, sh(timber));
        for (final zz in [min.z + 1.0, max.z + 0.4]) {
          _pole(cx - 0.12, zz, y, 0.22, 0.03, sh(timber));
          _pole(cx + 0.12, zz, y, 0.22, 0.03, sh(timber));
        }
        _slab(cx + 0.2, max.z - 0.1, cx + 0.5, max.z + 0.5, y + 0.02, 0.12,
            sh(const Color(0xFF4E3B2A)), top: sh(const Color(0xFF8A6E4E)));
        _pole(cx + 0.35, max.z + 0.2, y + 0.14, 0.6, 0.02, sh(timber));

      case 'mine':
        // A spoil heap, and the adit cut into it with a timber frame.
        _cone(Vector3(cx + 0.15, y, cz + 0.1), 0.72, 0.62, sh(const Color(0xFF6E665A)));
        _box(Vector3(min.x + 0.1, y, min.z + 0.05), Vector3(min.x + 0.62, y + 0.4, min.z + 0.45), dark);
        _pole(min.x + 0.1, min.z + 0.03, y, 0.44, 0.04, sh(timber));
        _pole(min.x + 0.62, min.z + 0.03, y, 0.44, 0.04, sh(timber));
        _slab(min.x + 0.04, min.z - 0.02, min.x + 0.68, min.z + 0.08, y + 0.42, 0.07, sh(timber));

      case 'sawmill':
        _gable(Vector3(min.x, y, min.z), Vector3(max.x - 0.55, y, max.z), 0.62, 0.42, wall, roof);
        // A wheel turning beside the wall when hands are on it.
        final angle = staffed ? tick * 0.35 : 0.0;
        _blades(max.x - 0.32, y + 0.42, cz, 0.38, 0.045, sh(timber), angle);
        _pole(max.x - 0.32, cz - 0.42, y, 0.42, 0.03, sh(timber));
        _pole(max.x - 0.32, cz + 0.42, y, 0.42, 0.03, sh(timber));
        for (var i = 0; i < 3; i++) {
          _slab(min.x + 0.1 + i * 0.03, max.z + 0.05, min.x + 0.7 - i * 0.03,
              max.z + 0.17, y + i * 0.11, 0.1, sh(timber));
        }

      case 'ropewalk':
        // Long and low, because a ropewalk is a corridor you walk rope down.
        _gable(Vector3(min.x, y, cz - 0.24), Vector3(max.x, y, cz + 0.24), 0.36, 0.3,
            wall, roof, overhang: 0.06);
        for (var i = 0; i < 3; i++) {
          _pole(min.x + 0.25 + i * (w - 0.5) / 2, cz + 0.5, y, 0.3, 0.025, sh(timber));
        }
        _slab(min.x + 0.22, cz + 0.49, max.x - 0.22, cz + 0.51, y + 0.28, 0.02,
            sh(const Color(0xFFB8A070)));

      case 'cooperage':
        _gable(Vector3(min.x, y, min.z), Vector3(max.x - 0.5, y, max.z), 0.55, 0.42, wall, roof);
        final oak = sh(const Color(0xFF8A6238));
        _barrel(max.x - 0.24, min.z + 0.3, y, oak);
        _barrel(max.x - 0.24, min.z + 0.62, y, oak);
        _barrel(max.x - 0.24, min.z + 0.94, y, oak);
        _barrel(max.x - 0.24, min.z + 0.46, y + 0.22, oak);

      case 'weaver':
        _gable(Vector3(min.x, y, min.z + 0.5), Vector3(max.x, y, max.z), 0.55, 0.42,
            wall, roof, alongX: true);
        // Cloth drying on a line out front.
        _pole(min.x + 0.15, min.z + 0.2, y, 0.62, 0.03, sh(timber));
        _pole(max.x - 0.15, min.z + 0.2, y, 0.62, 0.03, sh(timber));
        for (var i = 0; i < 3; i++) {
          final x0 = min.x + 0.28 + i * 0.48;
          _poly([Vector3(x0, y + 0.6, min.z + 0.2), Vector3(x0 + 0.34, y + 0.6, min.z + 0.2),
            Vector3(x0 + 0.34, y + 0.22, min.z + 0.2), Vector3(x0, y + 0.22, min.z + 0.2)],
            sh(const Color(0xFFE6DCC3)), awayFrom: Vector3(cx, y, cz + 1));
        }

      case 'smithy':
        _gable(min, max, 0.6, 0.4, wall, roof);
        _pole(max.x - 0.25, max.z - 0.28, y + 0.6, 0.62, 0.09, sh(const Color(0xFF3C3430)));
        if (staffed) _smoke(max.x - 0.25, y + 1.24, max.z - 0.28, tick);
        // An anvil on a stump by the door.
        _pole(min.x - 0.1, cz, y, 0.22, 0.09, sh(timber));
        _slab(min.x - 0.28, cz - 0.07, min.x + 0.08, cz + 0.07, y + 0.22, 0.09, dark);

      case 'warehouse':
        // Tall, flat-roofed, a wide door, and crates that did not fit inside.
        _box(Vector3(min.x, y, min.z), Vector3(max.x, y + 0.95, max.z), wall,
            topColour: roof);
        _slab(min.x - 0.05, min.z - 0.05, max.x + 0.05, max.z + 0.05, y + 0.95, 0.07, roof);
        _poly([Vector3(cx - 0.3, y, min.z - 0.001), Vector3(cx + 0.3, y, min.z - 0.001),
          Vector3(cx + 0.3, y + 0.55, min.z - 0.001), Vector3(cx - 0.3, y + 0.55, min.z - 0.001)],
          dark, awayFrom: Vector3(cx, y, cz));
        _slab(max.x + 0.08, cz - 0.3, max.x + 0.38, cz, y, 0.28, crate);
        _slab(max.x + 0.08, cz + 0.06, max.x + 0.38, cz + 0.36, y, 0.28, crate);
        _slab(max.x + 0.12, cz - 0.26, max.x + 0.34, cz - 0.04, y + 0.28, 0.24, crate);

      case 'import_berth':
        // A crane over a platform: the coin goes out, the cargo comes in.
        _slab(min.x, min.z, max.x, max.z, y, 0.08, sh(const Color(0xFF7A6A52)));
        _pole(min.x + 0.4, cz, y + 0.08, 1.15, 0.07, sh(timber));
        _slab(min.x + 0.33, cz - 0.05, max.x + 0.35, cz + 0.05, y + 1.1, 0.09, sh(timber));
        _pole(max.x + 0.25, cz, y + 0.5, 0.6, 0.012, dark);
        _slab(max.x + 0.1, cz - 0.15, max.x + 0.4, cz + 0.15, y + 0.28, 0.24, crate);
        _slab(min.x + 0.85, min.z + 0.15, min.x + 1.15, min.z + 0.45, y + 0.08, 0.26, crate);

      case 'distillery':
        _gable(Vector3(min.x, y, min.z), Vector3(max.x - 0.6, y, max.z), 0.6, 0.4, wall, roof);
        // A copper still and its pipe, out where it can vent.
        final copper = sh(const Color(0xFFB87333));
        _box(Vector3(max.x - 0.5, y, cz - 0.22), Vector3(max.x - 0.06, y + 0.42, cz + 0.22), copper);
        _cone(Vector3(max.x - 0.28, y + 0.42, cz), 0.24, 0.34, copper);
        _pole(max.x - 0.12, cz + 0.3, y + 0.3, 0.55, 0.025, sh(const Color(0xFF8A5A2A)));
        if (staffed) _smoke(max.x - 0.12, y + 0.85, cz + 0.3, tick + 9);
        _barrel(max.x - 0.24, max.z - 0.14, y, sh(const Color(0xFF8A6238)));

      case 'powder_mill':
        // A windmill: the one thing on the island that moves when it works.
        final tower = sh(const Color(0xFF8F8478));
        _box(Vector3(cx - 0.32, y, cz - 0.32), Vector3(cx + 0.32, y + 0.55, cz + 0.32), tower);
        _box(Vector3(cx - 0.24, y + 0.55, cz - 0.24), Vector3(cx + 0.24, y + 1.05, cz + 0.24), tower);
        _cone(Vector3(cx, y + 1.05, cz), 0.3, 0.32, roof);
        final angle = staffed ? tick * 0.3 : 0.6;
        _blades(cx, y + 1.0, cz - 0.3, 0.62, 0.08, sh(const Color(0xFFE2D6BC)), angle);
        _pole(cx, cz - 0.3, y + 0.96, 0.08, 0.05, dark);

      case 'bonded_cellar':
        // Dug into a mound. All you see is the door.
        _cone(Vector3(cx, y - 0.05, cz), 0.85, 0.5, sh(const Color(0xFF5F7F3C)));
        _box(Vector3(cx - 0.22, y, min.z + 0.02), Vector3(cx + 0.22, y + 0.34, min.z + 0.34), dark);
        _slab(cx - 0.28, min.z - 0.02, cx + 0.28, min.z + 0.08, y + 0.32, 0.07, sh(timber));
        _barrel(cx + 0.5, min.z + 0.2, y, sh(const Color(0xFF8A6238)));

      case 'privateer_berth':
        _gable(Vector3(min.x, y, min.z), Vector3(min.x + 0.75, y, min.z + 0.7), 0.42, 0.32, wall, roof);
        // A hull at the quay, a mast, and the black pennant.
        _slab(cx - 0.05, min.z + 0.8, cx + 0.6, max.z + 0.35, y + 0.02, 0.16,
            sh(const Color(0xFF3A2C22)), top: sh(const Color(0xFF7A604A)));
        _pole(cx + 0.28, cz + 0.4, y + 0.18, 1.1, 0.025, sh(timber));
        final flap = math.sin(tick * 0.4) * 0.05;
        _poly([Vector3(cx + 0.28, y + 1.26, cz + 0.4), Vector3(cx + 0.28 + 0.34, y + 1.16 + flap, cz + 0.4),
          Vector3(cx + 0.28, y + 1.06, cz + 0.4)], const Color(0xFF15120F), awayFrom: Vector3(cx, y, cz - 1));

      default:
        _gable(min, max, style.height * 0.75, style.roofHeight * 0.7, wall, roof);
    }

    if (index == selected) {
      final ring = Colors.white.withValues(alpha: 0.9);
      _quad(
        tileCorner(col, row, y + 0.02),
        tileCorner(col + f, row, y + 0.02),
        tileCorner(col + f, row + f, y + 0.02),
        tileCorner(col, row + f, y + 0.02),
        Palette.brass.withValues(alpha: 0.25),
        stroke: ring,
        cull: false,
      );
    }
  }

  void _buildDropHint() {
    final d = dragging;
    final at = dropAt;
    if (d == null || at == null) return;
    final f = state.buildings[d].def.footprint;
    final colour = dropValid ? Palette.moss : Palette.rust;

    for (var c = at.x; c < at.x + f; c++) {
      for (var r = at.y; r < at.y + f; r++) {
        final y = heightOf(Terrain.at(c, r)) + 0.03;
        _quad(
          tileCorner(c, r, y),
          tileCorner(c + 1, r, y),
          tileCorner(c + 1, r + 1, y),
          tileCorner(c, r + 1, y),
          colour.withValues(alpha: 0.45),
          stroke: colour,
          cull: false,
        );
      }
    }
  }

  // ---- Screen-space overlays --------------------------------------------

  /// Pips, bars and collect bubbles are drawn flat, after the scene, so they
  /// stay legible at any camera angle.
  void _paintOverlays(Canvas canvas) {
    for (var i = 0; i < state.buildings.length; i++) {
      final b = state.buildings[i];
      if (!b.isPlaced) continue;
      final def = b.def;
      final f = def.footprint;
      final col = (i == dragging && dropAt != null) ? dropAt!.x : b.col;
      final row = (i == dragging && dropAt != null) ? dropAt!.y : b.row;

      final style = _styleFor(def.id);
      final y = _groundUnder(col, row, f) + style.height + style.roofHeight;
      final head = _p.project(tileCorner(col + f / 2, row + f / 2, y));
      if (!head.visible) continue;

      // Scale badges with distance so far sheds do not shout.
      final k = (Camera3D.defaultDistance / math.max(head.depth, 1))
          .clamp(0.45, 1.4);
      final origin = head.screen.translate(0, -14 * k);

      final staffed = b.workers > 0;
      final starved = staffed && b.lastEfficiency < 0.95;

      if (def.isStaffable) {
        final n = def.maxWorkers;
        for (var p = 0; p < n; p++) {
          final px = origin.dx - (n - 1) * 5.0 * k + p * 10 * k;
          canvas.drawCircle(
            Offset(px, origin.dy),
            3.8 * k,
            Paint()
              ..color = p < b.workers
                  ? (starved ? Palette.rust : Palette.brass)
                  : Colors.black.withValues(alpha: 0.40),
          );
        }
      }

      if (staffed) {
        final barW = 38.0 * k;
        final rect =
            Rect.fromLTWH(origin.dx - barW / 2, origin.dy + 7 * k, barW, 3.5 * k);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(2 * k)),
          Paint()..color = Colors.black.withValues(alpha: 0.45),
        );
        final fill = (b.lastEfficiency * b.eventThrottle).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(rect.left, rect.top, barW * fill, 3.5 * k),
              Radius.circular(2 * k)),
          Paint()
            ..color = starved
                ? Palette.rust
                : (b.eventThrottle < 1.0 ? Palette.lamp : Palette.moss),
        );
      }

      if (b.hasCollectableOutput) {
        final full = b.holdFullness >= 0.999;
        final bob = full ? 0.0 : math.sin(state.tick * 0.25) * 3.0 * k;
        final c = Offset(origin.dx, origin.dy - 24 * k + bob);
        final r = 11 * k;
        canvas.drawCircle(c.translate(0, 2 * k), r,
            Paint()..color = Colors.black.withValues(alpha: 0.30));
        canvas.drawCircle(
            c, r, Paint()..color = full ? Palette.lamp : Palette.brass);
        final p = Paint()
          ..color = Palette.deep
          ..strokeWidth = 2.3 * k
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(c.translate(0, -4.5 * k), c.translate(0, 2.5 * k), p);
        canvas.drawLine(c.translate(-3.5 * k, -0.5 * k), c.translate(0, 3.5 * k), p);
        canvas.drawLine(c.translate(3.5 * k, -0.5 * k), c.translate(0, 3.5 * k), p);
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}

class _Style {
  const _Style(this.wall, this.roof, {this.height = 0.8, this.roofHeight = 0.62});
  final Color wall;
  final Color roof;
  final double height;
  final double roofHeight;
}

_Style _styleFor(String id) => switch (id) {
      'forest_camp' => const _Style(Color(0xFF8A7150), Color(0xFF4A5C36)),
      'fishing_wharf' => const _Style(Color(0xFF7D7963), Color(0xFF44564F)),
      'farm' => const _Style(Color(0xFFBB9B66), Color(0xFF9A5236)),
      'flax_field' =>
        const _Style(Color(0xFF9DA06B), Color(0xFF6B7842), height: 0.3, roofHeight: 0.26),
      'mine' => const _Style(Color(0xFF77705F), Color(0xFF413C33)),
      'sawmill' => const _Style(Color(0xFF9A7C52), Color(0xFF5A4630)),
      'ropewalk' => const _Style(Color(0xFFA79468), Color(0xFF5C5136)),
      'cooperage' => const _Style(Color(0xFF9B7649), Color(0xFF57402A)),
      'weaver' => const _Style(Color(0xFFAFA283), Color(0xFF6B5B44)),
      'smithy' => const _Style(Color(0xFF7A6D62), Color(0xFF43372F)),
      'house' =>
        const _Style(Color(0xFFC3AA7E), Color(0xFF9A5236), height: 0.66),
      'warehouse' =>
        const _Style(Color(0xFF8D7F5F), Color(0xFF4E4634), height: 1.05, roofHeight: 0.5),
      'import_berth' => const _Style(Color(0xFF77857F), Color(0xFF3E4C4A)),
      'distillery' => const _Style(Color(0xFF8C765D), Color(0xFF4B3A2C)),
      'powder_mill' => const _Style(Color(0xFF776960), Color(0xFF3A322D)),
      'bonded_cellar' =>
        const _Style(Color(0xFF69645A), Color(0xFF38352F), height: 0.38, roofHeight: 0.24),
      'privateer_berth' => const _Style(Color(0xFF645760), Color(0xFF33292D)),
      _ => const _Style(Color(0xFF8D7F5F), Color(0xFF4E4634)),
    };
