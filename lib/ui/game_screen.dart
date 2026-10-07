import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../audio/sound_engine.dart';
import '../game/blast_game.dart';
import '../play/nest_stage.dart';
import 'nest_theme.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller, required this.sound});

  final AppController controller;
  final SoundEngine sound;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late BlastGame _game;
  late final NestStage _stage;
  late final AnimationController _scoreTick;
  var _bestAtStart = 0;
  var _scoreFrom = 0;
  var _scoreTo = 0;
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    _game = _createGame();
    _stage = NestStage(rules: _game);
    _attach(_game);
    _bestAtStart = _game.best;
    _scoreTick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scoreTick.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onGame() {
    if (!mounted) return;
    _syncScore();
    setState(() {});
  }

  void _handleEvent(BlastEvent event) {
    final soundOn = widget.controller.soundOn;
    switch (event) {
      case BlastEvent.pickup:
        widget.sound.play(Sfx.pickup);
      case BlastEvent.place:
        widget.sound.play(Sfx.place);
        if (soundOn) _haptic(HapticFeedback.lightImpact());
      case BlastEvent.reject:
        widget.sound.play(Sfx.reject);
      case BlastEvent.rotate:
        widget.sound.play(Sfx.rotate);
      case BlastEvent.hold:
        widget.sound.play(Sfx.lift);
      case BlastEvent.blast:
        widget.sound.play(Sfx.boom);
        widget.sound.play(
          _game.combo >= 2 || _game.lastClear > 1 ? Sfx.victory : Sfx.complete,
        );
        if (soundOn) {
          _haptic(
            _game.lastBombs > 0
                ? HapticFeedback.heavyImpact()
                : HapticFeedback.mediumImpact(),
          );
        }
      case BlastEvent.gameOver:
        if (_beatRecord) {
          widget.sound.play(Sfx.victory);
        } else {
          widget.sound.play(Sfx.reject);
        }
        if (soundOn) _haptic(HapticFeedback.heavyImpact());
      case BlastEvent.undo:
        widget.sound.play(Sfx.tap);
    }
  }

  void _haptic(Future<void> feedback) {
    unawaited(
      feedback.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  void dispose() {
    _detach(_game);
    _scoreTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = nestOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    _stage.colors = colors;
    _stage.dark = dark;

    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: colors.bg,
          body: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    children: [
                      _header(colors, dark),
                      const SizedBox(height: 8),
                      _score(colors),
                      const SizedBox(height: 10),
                      Expanded(
                        child: GameWidget(
                          key: const Key('playfield'),
                          game: _stage,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_game.gameOver) _gameOver(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(NestColors colors, bool dark) {
    return Row(
      children: [
        IconButton(
          key: const Key('menu-button'),
          tooltip: 'Меню',
          visualDensity: VisualDensity.compact,
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Block Nest',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              Text(
                widget.controller.level.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('sound-button'),
          tooltip: 'Звук',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final turningOn = !widget.controller.soundOn;
            widget.controller.toggleSound();
            if (turningOn) widget.sound.play(Sfx.toggle);
          },
          icon: Icon(
            widget.controller.soundOn
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
          ),
        ),
        IconButton(
          key: const Key('theme-button'),
          tooltip: 'Тема',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            widget.controller.toggleTheme(Theme.of(context).brightness);
            widget.sound.play(Sfx.toggle);
          },
          icon: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
        ),
        IconButton(
          key: const Key('undo-button'),
          tooltip: 'Назад',
          visualDensity: VisualDensity.compact,
          onPressed: _game.canUndo ? _undo : null,
          icon: Badge(
            isLabelVisible: _game.undosLeft > 0,
            label: Text('${_game.undosLeft}'),
            child: const Icon(Icons.undo_rounded),
          ),
        ),
        IconButton(
          tooltip: 'Заново',
          visualDensity: VisualDensity.compact,
          onPressed: _restart,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  String get _hint {
    const turn = 'Нажми — поворот. Заполни ряд или столбец — блоки исчезнут.';
    final level = widget.controller.level;
    if (level.isFun) {
      if (_game.lightningReady) {
        return 'Молния готова. Нажми ряд, который снести.';
      }
      return '$turn\nМолния копится. Когда заполнится — выбери ряд.';
    }
    final pace = level.bombPace;
    if (pace == null) {
      return '$turn\nЕсли фигуре нет места на поле, это проигрыш.';
    }
    final rhythm = pace.every == 1
        ? 'Бомбы появляются часто.'
        : 'Бомбы приходят парами и на время затихают.';
    return '$turn\n$rhythm Бомба взрывает соседние клетки. Нет места — проигрыш.';
  }

  Widget _score(NestColors colors) {
    final ticking = _scoreTick.isAnimating;
    final t = _scoreTick.value.clamp(0.0, 1.0);
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              if (ticking)
                Positioned(
                  left: 6,
                  top: 2,
                  child: Opacity(
                    opacity: (1 - t) * 0.9,
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3E7BFF).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              Text(
                '$_shownScore',
                key: const Key('score'),
                style: TextStyle(
                  color: colors.text,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (widget.controller.level.isFun) _lightning(colors),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'рекорд ${_game.best}',
              style: TextStyle(
                color: colors.muted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lightning(NestColors colors) {
    final ready = _game.lightningReady;
    final filled = (_game.lightning / BlastGame.lightningNeed).clamp(0.0, 1.0);
    const armed = Color(0xFF3EC8FF);
    final bolt = ready ? armed : colors.muted;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
      child: SizedBox(
        width: 86,
        height: 18,
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: bolt),
            const SizedBox(width: 3),
            if (ready)
              const Text(
                'молния',
                style: TextStyle(
                  color: armed,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              )
            else
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.line),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: filled,
                          child: ColoredBox(color: bolt),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gameOver(NestColors colors) {
    return Positioned.fill(
      child: ColoredBox(
        color: colors.bg.withValues(alpha: 0.78),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _beatRecord ? 'Новый рекорд!' : 'Проиграли',
                    key: const Key('result-title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _beatRecord ? colors.accent : colors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _beatRecord ? _recordPraise : 'Фигуре нет места на поле',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_shownScore',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'рекорд ${_game.best}',
                    style: TextStyle(color: colors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  if (_game.canUndo)
                    TextButton(
                      key: const Key('undo-loss'),
                      onPressed: _undo,
                      child: Text('Назад · ${_game.undosLeft}'),
                    ),
                  if (_game.canUndo) const SizedBox(height: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      minimumSize: const Size(180, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _restart,
                    child: const Text('Ещё раз'),
                  ),
                  TextButton(
                    key: const Key('back-menu'),
                    onPressed: _leave,
                    child: Text(
                      'В меню',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _beatRecord => _game.score > _bestAtStart;

  String get _recordPraise {
    if (_bestAtStart <= 0) return 'Поздравляем! Это твой первый рекорд';
    return 'Поздравляем! Прошлый рекорд был $_bestAtStart';
  }

  int get _shownScore {
    if (_scoreFrom == _scoreTo) return _scoreTo;
    final t = Curves.easeOutCubic.transform(_scoreTick.value);
    return (_scoreFrom + (_scoreTo - _scoreFrom) * t).round();
  }

  void _syncScore() {
    final next = _game.score;
    final shown = _shownScore;
    if (next == _scoreTo && (next <= shown || !_scoreTick.isAnimating)) return;
    if (next <= shown) {
      _scoreTick.stop();
      _scoreFrom = next;
      _scoreTo = next;
      return;
    }
    _scoreFrom = shown;
    _scoreTo = next;
    _scoreTick.forward(from: 0);
  }

  void _restart() {
    widget.sound.play(Sfx.tap);
    _stage.stopMotion();
    _game.restart();
    _bestAtStart = _game.best;
  }

  bool get _canLeave => _leaving || _game.score == 0 || _game.gameOver;

  Future<void> _leave() async {
    if (_game.score > 0 && !_game.gameOver) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final colors = nestOf(context);
          return AlertDialog(
            backgroundColor: colors.surface,
            title: Text(
              'Выйти в меню?',
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
            ),
            content: Text(
              'Счёт обнулится.',
              style: TextStyle(color: colors.muted, fontSize: 16),
            ),
            actions: [
              TextButton(
                key: const Key('confirm-leave-no'),
                onPressed: () => Navigator.pop(context, false),
                child: Text('Нет', style: TextStyle(color: colors.muted)),
              ),
              TextButton(
                key: const Key('confirm-leave-yes'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Да',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
      setState(() => _leaving = true);
      widget.sound.play(Sfx.tap);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    widget.sound.play(Sfx.tap);
    Navigator.pop(context);
  }

  BlastGame _createGame() {
    final level = widget.controller.level;
    return BlastGame(best: widget.controller.bestFor(level), level: level);
  }

  void _attach(BlastGame game) {
    game.addListener(_onGame);
    game.onEvent = _handleEvent;
    game.onBest = widget.controller.setBest;
  }

  void _detach(BlastGame game) {
    game.onEvent = null;
    game.onBest = null;
    game.removeListener(_onGame);
    game.dispose();
  }

  void _undo() {
    _stage.stopMotion();
    _game.undo();
  }
}
