import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/vault_theme.dart';
import '../../state/vault_theme_store.dart';

VoidCallback? _closeActiveDesktopCard;
String? _activeDesktopCardRouteName;
int _activeDesktopCardToken = 0;
const double kDesktopOverlayBreakpoint = 680;
const double kDesktopWideShellBreakpoint = 1020;

bool useDesktopOverlayCards(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < kDesktopOverlayBreakpoint) return false;
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}

Future<T?> pushOrPresentDesktopCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
  double maxWidth = 660,
  double maxHeightFactor = 0.72,
}) {
  if (!useDesktopOverlayCards(context)) {
    return Navigator.of(
      context,
    ).push<T>(MaterialPageRoute(builder: builder, settings: settings));
  }

  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final rootContext = rootNavigator.context;
  final routeName = settings?.name?.trim() ?? '';
  final currentRouteName = (_activeDesktopCardRouteName ?? '').trim();
  if (routeName.isNotEmpty && currentRouteName == routeName) {
    return Future<T?>.value(null);
  }
  if (_closeActiveDesktopCard != null) {
    _closeActiveDesktopCard!.call();
  }

  final token = ++_activeDesktopCardToken;
  _activeDesktopCardRouteName = routeName.isEmpty ? null : routeName;
  _closeActiveDesktopCard = () {
    if (rootNavigator.mounted) {
      rootNavigator.pop();
    }
  };

  return showGeneralDialog<T>(
    context: rootContext,
    routeSettings: settings,
    barrierLabel: 'Close',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    pageBuilder: (dialogContext, _, __) {
      final theme =
          Theme.of(dialogContext).extension<VaultThemeColors>() ??
          VaultThemeStore.activePalette.colors;
      final media = MediaQuery.of(dialogContext);
      final width = media.size.width.clamp(0.0, maxWidth + 20).toDouble();
      final maxHeight = media.size.height * maxHeightFactor;

      return Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width - 12,
                  maxHeight: maxHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: builder(dialogContext),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  ).whenComplete(() {
    if (_activeDesktopCardToken == token) {
      _closeActiveDesktopCard = null;
      _activeDesktopCardRouteName = null;
    }
  });
}
