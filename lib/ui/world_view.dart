import 'dart:math' as math;

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
  });

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
  late final Camera3D _camera = Camera3D(target: Vector3.zero());

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
    _buildTerrain();
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

  void _buildTerrain() {
    for (var col = 0; col < Terrain.size; col++) {
      for (var row = 0; row < Terrain.size; row++) {
        final t = Terrain.at(col, row);
        final y = heightOf(t);
        final v = _hash(col * 71 + row * 13);

        Color top;
        switch (t) {
          case Tile.water:
            final k =
                math.sin((col + row) * 0.7 + state.tick * 0.06) * 0.5 + 0.5;
            top = Color.lerp(
                const Color(0xFF1C5670), const Color(0xFF2B7B93), k)!;
          case Tile.sand:
            top = Color.lerp(
                const Color(0xFFCDB183), const Color(0xFFE0C79C), v)!;
          case Tile.rock:
            top = Color.lerp(
                const Color(0xFF767A6D), const Color(0xFF8B907E), v)!;
          case Tile.grass:
          case Tile.trees:
            top = Color.lerp(
                const Color(0xFF52883F), const Color(0xFF6BA357), v)!;
        }

        final a = tileCorner(col, row, y);
        final b = tileCorner(col + 1, row, y);
        final c = tileCorner(col + 1, row + 1, y);
        final d = tileCorner(col, row + 1, y);
        _quad(a, b, c, d, _lit(top, Vector3(0, 1, 0)), cull: false);

        // Skirts wherever this tile stands above its neighbour: the cliff
        // faces that make the island look like a solid object.
        _skirt(col, row, y, 1, 0, top);
        _skirt(col, row, y, -1, 0, top);
        _skirt(col, row, y, 0, 1, top);
        _skirt(col, row, y, 0, -1, top);

        if (t == Tile.trees) _buildTrees(col, row, y);
        if (t == Tile.rock) _buildRock(col, row, y);
      }
    }
  }

  void _skirt(int col, int row, double y, int dc, int dr, Color top) {
    final ny = heightOf(Terrain.at(col + dc, row + dr));
    if (ny >= y - 1e-6) return;

    late Vector3 a, b;
    late Vector3 normal;
    if (dc == 1) {
      a = tileCorner(col + 1, row, y);
      b = tileCorner(col + 1, row + 1, y);
      normal = Vector3(1, 0, 0);
    } else if (dc == -1) {
      a = tileCorner(col, row + 1, y);
      b = tileCorner(col, row, y);
      normal = Vector3(-1, 0, 0);
    } else if (dr == 1) {
      a = tileCorner(col + 1, row + 1, y);
      b = tileCorner(col, row + 1, y);
      normal = Vector3(0, 0, 1);
    } else {
      a = tileCorner(col, row, y);
      b = tileCorner(col + 1, row, y);
      normal = Vector3(0, 0, -1);
    }

    final a2 = Vector3(a.x, ny, a.z);
    final b2 = Vector3(b.x, ny, b.z);
    final earth = Color.lerp(top, const Color(0xFF6A5236), 0.55)!;
    _quad(a, b, b2, a2, _lit(earth, normal), cull: false);
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

    final inset = 0.14;
    final min = tileCorner(col, row, y) + Vector3(inset, 0, inset);
    final max = tileCorner(col + f, row + f, y) - Vector3(inset, 0, inset);

    final dim = staffed ? 1.0 : 0.66;
    Color shade(Color c) => Color.lerp(const Color(0xFF33402C), c, dim)!;

    _box(
      Vector3(min.x, y, min.z),
      Vector3(max.x, y + style.height, max.z),
      shade(style.wall),
    );

    // A pitched roof sitting on the walls.
    _cone(
      Vector3((min.x + max.x) / 2, y + style.height, (min.z + max.z) / 2),
      (max.x - min.x) / 2 + 0.07,
      style.roofHeight,
      shade(style.roof),
    );

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
