import 'package:flutter/material.dart';

import '../../models/vault_theme.dart';
import 'desktop_overlay_card.dart';
import '../../state/vault_theme_store.dart';

VaultThemeColors settingsTheme(BuildContext context) {
  return Theme.of(context).extension<VaultThemeColors>() ??
      VaultThemeStore.activePalette.colors;
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color ?? theme.header,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.25,
        fontSize: 12.0,
      ),
    );
  }
}

class SettingsScreenScaffold extends StatelessWidget {
  const SettingsScreenScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.centerTitle = false,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    if (!useDesktopOverlayCards(context)) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          centerTitle: centerTitle,
          backgroundColor: theme.backgroundAlt,
          foregroundColor: theme.header,
          surfaceTintColor: Colors.transparent,
          actions: actions,
        ),
        body: body,
      );
    }

    return Material(
      color: theme.backgroundAlt,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 7),
            decoration: BoxDecoration(
              color: theme.backgroundAlt,
              border: Border(
                bottom: BorderSide(color: theme.border.withValues(alpha: 0.92)),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (centerTitle)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 44),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: theme.header,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          fontSize: 15.8,
                        ),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        textAlign: TextAlign.left,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: theme.header,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          fontSize: 15.8,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...actions,
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: theme.textSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class SettingsFooter extends StatelessWidget {
  const SettingsFooter({
    super.key,
    this.appName = 'The Vault',
    this.brand = 'The Conquerors Court',
  });

  final String appName;
  final String brand;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Column(
      children: [
        Text(
          appName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: theme.header,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.22,
            fontSize: 12.2,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 15, color: theme.textSoft),
            const SizedBox(width: 6),
            Text(
              'End-to-End Encrypted',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textSoft,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                fontSize: 10.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          brand,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: theme.textSoft.withValues(alpha: 0.88),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
            fontSize: 9.8,
          ),
        ),
      ],
    );
  }
}

class _SettingsShell extends StatelessWidget {
  const _SettingsShell({
    required this.child,
    this.padding = const EdgeInsets.all(0),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}

class SettingsInset extends StatelessWidget {
  const SettingsInset({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return _SettingsShell(padding: padding ?? EdgeInsets.zero, child: child);
  }
}

class SettingsPageBody extends StatelessWidget {
  const SettingsPageBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 16),
    this.maxWidth = 560,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth = constraints.maxWidth < maxWidth
            ? constraints.maxWidth
            : maxWidth;
        final useDesktopShell =
            !useDesktopOverlayCards(context) &&
            constraints.maxWidth >= maxWidth + 140;
        final listView = ListView(
          padding: useDesktopShell
              ? const EdgeInsets.fromLTRB(16, 16, 16, 18)
              : padding,
          children: children,
        );

        final content = Padding(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 420 ? 8 : 0,
            0,
            constraints.maxWidth >= 420 ? 8 : 0,
            0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveWidth),
            child: useDesktopShell
                ? Container(
                    margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          theme.surface.withValues(alpha: 0.97),
                          theme.backgroundAlt.withValues(alpha: 0.97),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: theme.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: listView,
                    ),
                  )
                : listView,
          ),
        );

        return Align(alignment: Alignment.topCenter, child: content);
      },
    );
  }
}

class SettingsPill extends StatelessWidget {
  const SettingsPill({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    final fill = color ?? theme.accent;
    final foreground =
        ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : const Color(0xFF14091D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return _SettingsShell(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.surface,
              theme.backgroundAlt.withValues(alpha: 0.92),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: children),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Divider(height: 1, color: theme.border, indent: 14, endIndent: 14);
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.iconFill,
    this.iconBorder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? iconFill;
  final Color? iconBorder;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      minVerticalPadding: 4,
      visualDensity: const VisualDensity(horizontal: -0.6, vertical: -0.8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconFill ?? theme.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: iconBorder ?? theme.border),
        ),
        child: Icon(icon, color: iconColor ?? theme.accent, size: 17),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: theme.text,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          fontSize: 13.4,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: theme.textSoft, height: 1.24, fontSize: 11.2),
      ),
      trailing:
          trailing ?? Icon(Icons.chevron_right_rounded, color: theme.textSoft),
      onTap: onTap,
    );
  }
}

class SettingsHeroCard extends StatelessWidget {
  const SettingsHeroCard({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
  });

  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return _SettingsShell(
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [theme.backgroundAlt, theme.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: theme.border),
          boxShadow: [
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: theme.header,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                fontSize: 15.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: theme.textSoft,
                height: 1.28,
                fontSize: 10.0,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(height: 6),
              Center(child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border),
            ),
            child: Icon(icon, color: theme.accent, size: 17),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: theme.text,
              fontWeight: FontWeight.w800,
              fontSize: 13.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: theme.textSoft,
              height: 1.35,
              fontSize: 10.9,
            ),
          ),
        ],
      ),
    );
  }
}
