import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Simple stack-based orientation locking.
///
/// Flutter sets preferred orientations at the app level, so screens that need a
/// different policy should push their desired orientations and pop on dispose.
class OrientationLock {
  OrientationLock._();

  static final List<List<DeviceOrientation>> _stack =
      <List<DeviceOrientation>>[];

  static const List<DeviceOrientation> portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  /// Use for chat/media screens that should support landscape.
  static const List<DeviceOrientation> chatAndMedia = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static Future<void> push(List<DeviceOrientation> orientations) async {
    _stack.add(List<DeviceOrientation>.unmodifiable(orientations));
    await _apply(_stack.last);
  }

  static Future<void> pop() async {
    if (_stack.isNotEmpty) {
      _stack.removeLast();
    }
    await _apply(_stack.isEmpty ? portraitOnly : _stack.last);
  }

  static Future<void> _apply(List<DeviceOrientation> orientations) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {}
  }
}

class OrientationLockScope extends StatefulWidget {
  const OrientationLockScope({
    super.key,
    required this.orientations,
    required this.child,
  });

  final List<DeviceOrientation> orientations;
  final Widget child;

  @override
  State<OrientationLockScope> createState() => _OrientationLockScopeState();
}

class _OrientationLockScopeState extends State<OrientationLockScope> {
  @override
  void initState() {
    super.initState();
    unawaited(OrientationLock.push(widget.orientations));
  }

  @override
  void dispose() {
    unawaited(OrientationLock.pop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
