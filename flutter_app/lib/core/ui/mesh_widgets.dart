import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'mesh_theme.dart';
export 'mesh_theme.dart';

/// A shared, normalized damped spring for small interface transitions.
class MeshSpringCurve extends Curve {
  const MeshSpringCurve();
  @override
  double transformInternal(double t) {
    final spring = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 300, damping: 35),
      0,
      1,
      0,
    );
    return spring.x(t * .5) / spring.x(.5);
  }
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final bool blur;
  final EdgeInsetsGeometry padding;
  const GlassSurface(
      {super.key,
      required this.child,
      this.blur = false,
      this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [
                    Color.alphaBlend(MeshColors.blue.withValues(alpha: .24),
                            MeshColors.midnight)
                        .withValues(alpha: opaque ? 1 : .90),
                    Color.alphaBlend(MeshColors.navy.withValues(alpha: .42),
                            MeshColors.midnight)
                        .withValues(alpha: opaque ? 1 : .94)
                  ]
                : [
                    Colors.white.withValues(alpha: opaque ? 1 : .88),
                    Color.alphaBlend(MeshColors.blue.withValues(alpha: .08),
                            Colors.white)
                        .withValues(alpha: opaque ? 1 : .94)
                  ]),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
            color:
                dark ? MeshColors.blue.withValues(alpha: .35) : Colors.white),
      ),
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: blur && !opaque
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: surface)
            : surface);
  }
}

class MeshPage extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  const MeshPage(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.child,
      this.actions = const [],
      this.floatingActionButton});
  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: floatingActionButton,
        body: SafeArea(
            bottom: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(24, 18, 16, 20),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('OFFLINEMESH',
                                        style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 2.6,
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary)),
                                    const SizedBox(height: 8),
                                    Text(title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge),
                                    const SizedBox(height: 6),
                                    Text(subtitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ])),
                              ...actions,
                            ])),
                        Expanded(child: child),
                      ],
                    )))),
      );
}

class MeshSearch extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const MeshSearch({super.key, required this.hint, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
            hintText: hint, prefixIcon: const Icon(Icons.search_rounded)),
      ));
}

class MeshAvatar extends StatelessWidget {
  final String name;
  final double size;
  const MeshAvatar({super.key, required this.name, this.size = 52});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .35),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MeshColors.blue, MeshColors.navy])),
        child: Text(
            name.trim().isEmpty
                ? '?'
                : name.trim().characters.first.toUpperCase(),
            style: TextStyle(
                color: Colors.white,
                fontSize: size * .36,
                fontWeight: FontWeight.w600)),
      );
}

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyStateView(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.actionLabel,
      this.onAction});
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MeshColors.blue.withValues(alpha: .10)),
                child: Icon(icon,
                    size: 38, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall)),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: onAction, child: Text(actionLabel ?? 'Try again'))
            ],
          ])));
}

class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Loading',
      child: ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 18),
          itemBuilder: (_, __) => ExcludeSemantics(
                  child: GlassSurface(
                      child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: MeshColors.blue.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(18))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          height: 12,
                          width: 120,
                          color: MeshColors.blue.withValues(alpha: .12)),
                      const SizedBox(height: 10),
                      Container(
                          height: 8,
                          width: 170,
                          color: MeshColors.blue.withValues(alpha: .08)),
                    ])),
              ])))));
}

class GlassNavigationBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const GlassNavigationBar(
      {super.key, required this.index, required this.onChanged});
  static const labels = ['Chats', 'Friends', 'Notes', 'Files', 'Profile'];
  static const icons = [
    Icons.chat_bubble_outline_rounded,
    Icons.people_outline_rounded,
    Icons.lightbulb_outline_rounded,
    Icons.folder_outlined,
    Icons.person_outline_rounded
  ];
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: GlassSurface(
              blur: true,
              padding: const EdgeInsets.all(6),
              child: Row(
                  children: List.generate(
                      5,
                      (i) => Expanded(
                              child: Semantics(
                            selected: index == i,
                            button: true,
                            label: labels[i],
                            child: ExcludeSemantics(
                                child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                if (index != i) {
                                  HapticFeedback.selectionClick();
                                  onChanged(i);
                                }
                              },
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 500),
                                curve: const MeshSpringCurve(),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    color: index == i
                                        ? MeshColors.blue.withValues(alpha: .17)
                                        : Colors.transparent),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icons[i],
                                          color: index == i
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant),
                                      const SizedBox(height: 4),
                                      Text(labels[i],
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: index == i
                                                  ? FontWeight.w700
                                                  : FontWeight.w500))
                                    ]),
                              ),
                            )),
                          )))))));
}

/// Decorative sweep only: no dots or invented devices, and no animation at rest.
class DiscoveryRadar extends StatefulWidget {
  final bool scanning;
  const DiscoveryRadar({super.key, required this.scanning});
  @override
  State<DiscoveryRadar> createState() => _DiscoveryRadarState();
}

class _DiscoveryRadarState extends State<DiscoveryRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  void _sync() {
    if (widget.scanning &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DiscoveryRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: widget.scanning ? 'Discovery active' : 'Discovery idle',
      child: ExcludeSemantics(
          child: Container(
        height: 206,
        width: double.infinity,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MeshColors.midnight, MeshColors.navy])),
        child: RepaintBoundary(
            child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => CustomPaint(
                    painter: _RadarPainter(_controller.value, widget.scanning),
                    child: Center(
                        child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: MeshColors.blue.withValues(alpha: .22),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: .25))),
                            child: Icon(Icons.hub_outlined,
                                color: widget.scanning
                                    ? MeshColors.orange
                                    : Colors.white,
                                size: 30)))))),
      )));
}

class _RadarPainter extends CustomPainter {
  final double phase;
  final bool scanning;
  _RadarPainter(this.phase, this.scanning);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = MeshColors.blue.withValues(alpha: .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    for (final r in [64.0, 87.0, 112.0]) {
      canvas.drawCircle(center, r, paint);
    }
    if (scanning) {
      final angle = phase * math.pi * 2;
      canvas.drawLine(
          center,
          center + Offset(math.cos(angle), math.sin(angle)) * 99,
          Paint()
            ..color = MeshColors.blue
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      phase != old.phase || scanning != old.scanning;
}

