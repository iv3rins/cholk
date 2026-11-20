import 'dart:math' as math;
import 'dart:ui';

import 'package:forge2d/forge2d.dart';

enum LineFigure { coil, web, strands }

/// A hanging cord: [cord] runs from its fixed pin to the eye it carries, and
/// [body] is a second point held stiffly below the eye, so the hung piece turns
/// as one.
typedef LineStrand = ({List<Offset> cord, Offset body});

/// Positions live in one flat plane, independent of screen size and pixel ratio.
class LineSimulation {
  LineSimulation(
    this.figure, {
    List<LineStrand> strands = const [],
    this.bounds = const Rect.fromLTRB(-4.3, -3.05, 4.3, 3.05),
  }) {
    switch (figure) {
      case LineFigure.coil:
        _buildCoil();
      case LineFigure.web:
        _buildWeb();
      case LineFigure.strands:
        _buildStrands(strands);
    }
  }

  static const timeStep = 1 / 120;
  static const webSpokes = 12;
  static const webRings = 4;
  static const coilNodes = 49;

  final LineFigure figure;
  final Rect bounds;
  final _world = World();
  late final _ground = _world.createBody(BodyDef());
  final _nodes = <Body>[];
  final _rests = <Vector2>[];
  final _mobile = <int>[];
  final _strandBodies = <int>[];
  MouseJoint? _grab;
  Offset _grabOffset = Offset.zero;
  int? grabbedNode;

  int get focusNode => figure == LineFigure.coil ? coilNodes - 1 : 0;
  bool get dragging => _grab != null;
  int get nodeCount => _nodes.length;
  Offset position(int index) =>
      Offset(_nodes[index].position.x, _nodes[index].position.y);
  Offset rest(int index) => Offset(_rests[index].x, _rests[index].y);
  static int webNode(int ring, int spoke) =>
      1 + ring * webSpokes + spoke % webSpokes;

  /// Nodes of strand `s`: its pin is [strandStart], its eye is one before
  /// [strandBody].
  int strandStart(int strand) =>
      strand == 0 ? 0 : _strandBodies[strand - 1] + 1;
  int strandBody(int strand) => _strandBodies[strand];

  void _node(Vector2 position, {bool pinned = false}) {
    if (!pinned) _mobile.add(_nodes.length);
    _rests.add(position.clone());
    _nodes.add(
      _world.createBody(
        BodyDef(
          position: position,
          type: pinned ? BodyType.static : BodyType.dynamic,
          fixedRotation: true,
          linearDamping: 2.2,
          allowSleep: false,
        ),
      ),
    );
  }

  void _spring(int first, int second, double frequency, double damping) {
    final a = _nodes[first];
    final b = _nodes[second];
    final joint = DistanceJointDef<Body, Body>()
      ..initialize(a, b, a.position, b.position)
      ..frequencyHz = frequency
      ..dampingRatio = damping;
    _world.createJoint(DistanceJoint(joint));
  }

  void _buildCoil() {
    for (var i = 0; i < coilNodes; i++) {
      final t = i / (coilNodes - 1);
      final angle = -.84 * math.pi + t * 6.65 * math.pi;
      final radius = 2.8 - t * 2.54;
      _node(
        Vector2(radius * math.cos(angle) * 1.15, radius * math.sin(angle)),
        pinned: i == 0,
      );
      if (i > 0) _spring(i - 1, i, 11, .35);
      // A second span gives the strip bending stiffness without locking it rigid.
      if (i > 1) _spring(i - 2, i, 6, .38);
    }
  }

  void _buildWeb() {
    _node(Vector2.zero());
    for (var ring = 0; ring <= webRings; ring++) {
      final radius = const [.18, .36, .58, .8, 1.0][ring];
      for (var spoke = 0; spoke < webSpokes; spoke++) {
        final angle = -.5 * math.pi + spoke * math.pi * 2 / webSpokes;
        final x = 3.55 * (1 + .065 * math.sin(3 * angle + .6));
        final y = 2.85 * (1 + .055 * math.cos(5 * angle));
        final index = webNode(ring, spoke);
        _node(
          Vector2(radius * x * math.cos(angle), radius * y * math.sin(angle)),
          pinned: ring == webRings,
        );
        _spring(ring == 0 ? 0 : webNode(ring - 1, spoke), index, 9, .28);
        if (ring == webRings) continue;
        if (spoke > 0) _spring(index - 1, index, 6, .32);
        if (spoke == webSpokes - 1) _spring(index, webNode(ring, 0), 6, .32);
      }
    }
  }

  void _buildStrands(List<LineStrand> strands) {
    for (final strand in strands) {
      final start = _nodes.length;
      for (var i = 0; i < strand.cord.length; i++) {
        final p = strand.cord[i];
        _node(Vector2(p.dx, p.dy), pinned: i == 0);
        if (i > 0) _spring(start + i - 1, start + i, 11, .35);
        if (i > 1) _spring(start + i - 2, start + i, 6, .38);
      }
      final eye = _nodes.length - 1;
      _node(Vector2(strand.body.dx, strand.body.dy));
      _spring(eye, eye + 1, 14, .7);
      // Bracing from the cord keeps the hung piece from spinning on its eye.
      _spring(eye - 1, eye + 1, 8, .5);
      _strandBodies.add(eye + 1);
    }
  }

  int? _nearestNode(Offset point, double radius) {
    var nearest = -1;
    var distance = radius * radius;
    for (final index in _mobile) {
      final candidate = (point - position(index)).distanceSquared;
      if (candidate < distance) {
        distance = candidate;
        nearest = index;
      }
    }
    return nearest < 0 ? null : nearest;
  }

  bool canGrab(Offset point, double radius) =>
      !dragging && _nearestNode(point, radius) != null;

  bool grab(Offset point, double radius) {
    if (dragging) return false;
    final nearest = _nearestNode(point, radius);
    if (nearest == null) return false;
    final body = _nodes[nearest];
    _grabOffset = position(nearest) - point;
    final definition = MouseJointDef<Body, Body>()
      ..bodyA = _ground
      ..bodyB = body
      ..target.setFrom(body.position)
      ..maxForce = 320
      ..frequencyHz = 6
      ..dampingRatio = .74;
    final joint = MouseJoint(definition);
    _world.createJoint(joint);
    _grab = joint;
    grabbedNode = nearest;
    return true;
  }

  void move(Offset point) {
    final target = point + _grabOffset;
    _grab?.setTarget(
      Vector2(
        target.dx.clamp(bounds.left, bounds.right),
        target.dy.clamp(bounds.top, bounds.bottom),
      ),
    );
  }

  void release() {
    if (_grab case final joint?) _world.destroyJoint(joint);
    _grab = null;
    _grabOffset = Offset.zero;
    grabbedNode = null;
  }

  void tug() => push(focusNode, const Offset(9, -5));

  void push(int index, Offset impulse) =>
      _nodes[index].applyLinearImpulse(Vector2(impulse.dx, impulse.dy));

  void setGravity(Offset gravity) =>
      _world.gravity.setValues(gravity.dx, gravity.dy);

  void step() {
    // A flat spiral has a preferred curvature, and a hung cord a resting drape.
    // A weak return force models that memory while the distance joints carry
    // tension between nodes.
    final memory = switch (figure) {
      LineFigure.coil => 33.0,
      LineFigure.strands => 30.0,
      LineFigure.web => 0.0,
    };
    if (memory > 0) {
      for (final i in _mobile) {
        _nodes[i].applyForce((_rests[i] - _nodes[i].position)..scale(memory));
      }
    }
    _world.stepDt(timeStep);
  }

  bool get moving =>
      _mobile.any((i) => _nodes[i].linearVelocity.length2 > .0016);
}
