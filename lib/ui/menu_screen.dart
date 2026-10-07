import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../audio/sound_engine.dart';
import '../game/level.dart';
import 'game_screen.dart';
import 'nest_theme.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.controller, required this.sound});

  final AppController controller;
  final SoundEngine sound;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sky = dark
        ? const [Color(0xFF24315F), Color(0xFF12182C)]
        : const [Color(0xFF4C9BFF), Color(0xFF1E5FE0)];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: sky.last,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: sky,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      _roundButton(
                        key: const Key('sound-button'),
                        tooltip: 'Звук',
                        onPressed: () {
                          final turningOn = !controller.soundOn;
                          controller.toggleSound();
                          if (turningOn) sound.play(Sfx.toggle);
                        },
                        icon: controller.soundOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                      ),
                      const SizedBox(width: 8),
                      _roundButton(
                        key: const Key('theme-button'),
                        tooltip: 'Тема',
                        onPressed: () {
                          controller.toggleTheme(Theme.of(context).brightness);
                          sound.play(Sfx.toggle);
                        },
                        icon: dark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const _Logo(),
                  const SizedBox(height: 14),
                  const _Wordmark(),
                  const SizedBox(height: 8),
                  Text(
                    'собери ряд',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  for (final level in NestLevel.values) _mode(context, level),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    required Key key,
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
        fixedSize: const Size(42, 42),
      ),
      icon: Icon(icon, size: 22),
    );
  }

  Widget _mode(BuildContext context, NestLevel level) {
    final best = controller.bestFor(level);
    final look = _look(level);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: look.lip,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Material(
            color: look.face,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: Key('level-${level.name}'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => _play(context, level),
              child: SizedBox(
                height: best > 0 ? 72 : 62,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Icon(look.icon, color: Colors.white, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              level.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (best > 0)
                              Text(
                                'рекорд $best',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context, NestLevel level) {
    sound.play(Sfx.tap);
    controller.setLevel(level);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondary) {
          return GameScreen(controller: controller, sound: sound);
        },
      ),
    );
  }
}

class _Look {
  const _Look(this.face, this.lip, this.icon);

  final Color face;
  final Color lip;
  final IconData icon;
}

_Look _look(NestLevel level) {
  return switch (level) {
    NestLevel.easy => const _Look(
      Color(0xFF2ED573),
      Color(0xFF149A52),
      Icons.all_inclusive_rounded,
    ),
    NestLevel.medium => const _Look(
      Color(0xFF4C8DFF),
      Color(0xFF2458C8),
      Icons.grid_view_rounded,
    ),
    NestLevel.hard => const _Look(
      Color(0xFFFF6B6B),
      Color(0xFFD23E3E),
      Icons.local_fire_department_rounded,
    ),
    NestLevel.fun => const _Look(
      Color(0xFFFF9F1C),
      Color(0xFFD97A00),
      Icons.auto_awesome_rounded,
    ),
  };
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  static const _title = 'Block Nest';
  static const _ink = <Color>[
    Color(0xFFFFB703),
    Color(0xFFFF5D5D),
    Color(0xFFFFD60A),
    Color(0xFF7CFFB2),
    Color(0xFFC77DFF),
    Color(0xFFFFFFFF),
    Color(0xFF7CFFB2),
    Color(0xFFFF8FAB),
    Color(0xFFFFD60A),
    Color(0xFFFF9F1C),
  ];

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < _title.length; i++)
            TextSpan(
              text: _title[i],
              style: TextStyle(
                color: _ink[i],
                fontSize: 46,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -1.2,
                shadows: const [
                  Shadow(color: Color(0x66000000), offset: Offset(0, 4)),
                ],
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final colors = nestOf(context);
    Widget gem(Color color, double size) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), offset: Offset(0, 4)),
          ],
        ),
      );
    }

    return SizedBox(
      width: 92,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, child: gem(colors.blocks[2], 30)),
          Positioned(left: 8, top: 28, child: gem(colors.blocks[0], 30)),
          Positioned(right: 8, top: 28, child: gem(colors.blocks[4], 30)),
          Positioned(top: 46, child: gem(colors.blocks[1], 30)),
        ],
      ),
    );
  }
}
