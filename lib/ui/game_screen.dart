import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../audio/sound_engine.dart';
import '../audio/synth.dart';
import '../game/blast_game.dart';
import '../game/geometry.dart';
import '../game/level.dart';
import 'nest_theme.dart';
import 'piece_view.dart';

const _trayGap = 8.0;
const _trayPad = 6.0;
const _blocked = Color(0xFFE53935);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller, required this.sound});

  final AppController controller;
  final SoundEngine sound;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _boardKey = GlobalKey();
  final _holdKey = GlobalKey();

  late BlastGame _game;
  late final AnimationController _burst;
  late final AnimationController _praise;
  late final AnimationController _scoreTick;
  late final AnimationController _arrive;
  var _trayEpoch = 0;
  var _commitArmed = false;
  var _bestAtStart = 0;
  var _scoreFrom = 0;
  var _scoreTo = 0;
  String? _praiseWord;
  var _praiseLines = 0;
  var _praiseGain = 0;

  Point? _grab;
  Offset? _finger;
  double? _boardCell;

  @override
  void initState() {
    super.initState();
    _game = _createGame();
    _attach(_game);
    _bestAtStart = _game.best;
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _burst.addListener(() {
      if (mounted) setState(() {});
    });
    _burst.addStatusListener((status) {
      if (status == AnimationStatus.completed && _commitArmed) {
        _commitArmed = false;
        _game.commitBlast();
      }
    });
    _praise = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _praise.addListener(() {
      if (mounted) setState(() {});
    });
    _praise.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _praiseWord = null);
      }
    });
    _scoreTick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _scoreTick.addListener(() {
      if (mounted) setState(() {});
    });
    _arrive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..value = 1;
    _arrive.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onGame() {
    if (!mounted) return;
    if (_game.bursting.isNotEmpty && !_commitArmed) {
      _commitArmed = true;
      _burst.forward(from: 0);
      _showPraise();
    }
    _syncScore();
    _syncArrival();
    setState(() {});
  }

  void _syncArrival() {
    final epoch = _game.trayEpoch;
    if (epoch <= _trayEpoch) {
      _trayEpoch = epoch;
      return;
    }
    _trayEpoch = epoch;
    if (_game.level.showsNext) _arrive.forward(from: 0);
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
        widget.sound.play(_game.lastClear > 1 ? Sfx.victory : Sfx.complete);
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
    _burst.dispose();
    _praise.dispose();
    _scoreTick.dispose();
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = nestOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tray = [
      for (var slot = 0; slot < BlastGame.traySlots; slot++)
        if (_game.tray[slot] != null) slot,
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trayMaxH = (constraints.maxHeight * 0.28).clamp(
                96.0,
                210.0,
              );
              final pieces = [for (final slot in tray) _game.tray[slot]!];
              final hold = _game.level.hasHold;
              final trayCell = _trayCellSize(
                pieces,
                constraints.maxWidth - 32 - (hold ? 84 : 0),
                trayMaxH,
              );
              return Stack(
                key: _stackKey,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Column(
                      children: [
                        _header(colors, dark),
                        const SizedBox(height: 8),
                        _levels(colors),
                        const SizedBox(height: 8),
                        _score(colors),
                        const SizedBox(height: 10),
                        Expanded(child: _boardArea(colors)),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 88),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (hold) ...[
                                _holdPocket(colors),
                                const SizedBox(width: 8),
                              ],
                              Expanded(child: _tray(colors, tray, trayCell)),
                            ],
                          ),
                        ),
                        if (_game.level.showsNext) ...[
                          const SizedBox(height: 6),
                          _upcoming(colors),
                        ],
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
                  if (_praiseWord != null) _praiseOverlay(colors),
                  if (_floatPiece != null) _float(colors),
                  if (_game.gameOver) _gameOver(colors),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  BlastPiece? get _floatPiece {
    final slot = _game.draggingSlot;
    if (slot == null ||
        _finger == null ||
        _grab == null ||
        _boardCell == null) {
      return null;
    }
    return _game.tray[slot];
  }

  Widget _header(NestColors colors, bool dark) {
    return Row(
      children: [
        const _Mark(),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Block Nest',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
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
    final pace = widget.controller.level.bombPace;
    if (pace == null) {
      return '$turn\nЕсли фигуре нет места на поле, это проигрыш.';
    }
    final rhythm = pace.every == 1
        ? 'Бомбы появляются часто.'
        : 'Бомбы приходят парами и на время затихают.';
    return '$turn\n$rhythm Бомба взрывает соседние клетки. Нет места — проигрыш.';
  }

  Widget _levels(NestColors colors) {
    return Row(
      children: [
        for (var i = 0; i < NestLevel.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _levelChip(colors, NestLevel.values[i])),
        ],
      ],
    );
  }

  Widget _levelChip(NestColors colors, NestLevel level) {
    final selected = widget.controller.level == level;
    final background = selected ? colors.accent : colors.surface;
    final foreground = selected ? colors.onAccent : colors.text;
    return Tooltip(
      message: level.title,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('level-${level.name}'),
          borderRadius: BorderRadius.circular(12),
          onTap: selected ? null : () => _changeLevel(level),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? colors.accent : colors.line),
            ),
            child: Text(
              level.title,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _score(NestColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
        const Spacer(),
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
    );
  }

  Widget _boardArea(NestColors colors) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.clamp(0, 460).toDouble();
        final maxH = constraints.maxHeight;
        var cell = maxW / BlastGame.size;
        if (cell * BlastGame.size > maxH) cell = maxH / BlastGame.size;
        return Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  colors.accent.withValues(alpha: dark ? 0.16 : 0.09),
                  colors.bg.withValues(alpha: 0),
                ],
                radius: 0.85,
              ),
            ),
            child: _Board(
              key: _boardKey,
              game: _game,
              cell: cell,
              colors: colors,
              burst: Curves.easeIn.transform(_burst.value),
            ),
          ),
        );
      },
    );
  }

  Widget _holdPocket(NestColors colors) {
    final piece = _game.held;
    final ready = _game.canStore;
    final hot = _game.holdHot;
    final border = hot ? (ready ? colors.accent : colors.danger) : colors.line;
    final label = _game.level.unlimitedHold
        ? 'запас'
        : (ready ? 'запас 1' : 'запас');
    return GestureDetector(
      onTap: _game.recall,
      child: Container(
        key: _holdKey,
        width: 76,
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: hot ? 1.6 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (piece == null)
              SizedBox(
                height: 36,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 22,
                  color: ready
                      ? colors.muted
                      : colors.muted.withValues(alpha: 0.4),
                ),
              )
            else
              PieceView(
                cells: piece.cells,
                color: _game.isStuck(piece)
                    ? _blocked
                    : _colorFor(colors, piece.colorIndex),
                cellSize: 14,
              ),
            const SizedBox(height: 2),
            Text(
              label,
              key: const Key('hold'),
              style: TextStyle(
                color: ready
                    ? colors.muted
                    : colors.muted.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tray(NestColors colors, List<int> slots, double cell) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: _trayGap,
      runSpacing: _trayGap,
      children: [
        for (var order = 0; order < slots.length; order++)
          _arriving(
            order,
            _TrayPiece(
              key: ValueKey('tray-${slots[order]}'),
              piece: _game.tray[slots[order]]!,
              color: _game.isStuck(_game.tray[slots[order]]!)
                  ? _blocked
                  : _colorFor(colors, _game.tray[slots[order]]!.colorIndex),
              cell: cell,
              surface: colors.surface,
              line: colors.line,
              muted: colors.muted,
              faded: _game.draggingSlot == slots[order],
              onRotate: () => _game.rotate(slots[order]),
              onDragStart: (grab, global) =>
                  _startDrag(slots[order], grab, global),
              onDragUpdate: _moveDrag,
              onDragEnd: _endDrag,
              onDragCancel: _cancelDrag,
            ),
          ),
      ],
    );
  }

  Widget _upcoming(NestColors colors) {
    final pieces = [for (final piece in _game.upcoming) ?piece];
    if (pieces.isEmpty) return const SizedBox.shrink();
    var tallest = 1;
    for (final piece in pieces) {
      if (piece.shapeHeight > tallest) tallest = piece.shapeHeight;
    }
    final cell = (34 / tallest).clamp(10.0, 15.0);
    final shown = _arrive.value < 1
        ? const Interval(
            0.22,
            1,
            curve: Curves.easeOutCubic,
          ).transform(_arrive.value)
        : 1.0;
    final blur = 2.2 + (1 - shown) * 6;
    return Row(
      children: [
        Text(
          'дальше',
          style: TextStyle(
            color: colors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: Opacity(
                opacity: 0.8 * shown,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * shown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var slot = 0; slot < pieces.length; slot++)
                          Padding(
                            key: ValueKey('upcoming-$slot'),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: PieceView(
                              cells: pieces[slot].cells,
                              color: _colorFor(colors, pieces[slot].colorIndex),
                              cellSize: cell,
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
      ],
    );
  }

  Widget _arriving(int order, Widget child) {
    if (!_game.level.showsNext || _arrive.value >= 1) return child;
    const step = 0.12;
    final raw = Interval(
      order * step,
      0.58 + order * step,
      curve: Curves.easeOutCubic,
    ).transform(_arrive.value);
    final pop = Curves.easeOutBack.transform(raw);
    final blur = (1 - raw) * 3.4;
    Widget shown = Transform.translate(
      offset: Offset(0, (1 - raw) * 16),
      child: Transform.scale(
        scale: 0.78 + 0.22 * pop,
        alignment: Alignment.bottomCenter,
        child: Opacity(opacity: raw.clamp(0.0, 1.0), child: child),
      ),
    );
    if (blur > 0.2) {
      shown = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: shown,
      );
    }
    return IgnorePointer(ignoring: raw < 0.55, child: shown);
  }

  Color _colorFor(NestColors colors, int index) {
    return colors.blocks[index % colors.blocks.length];
  }

  Widget _float(NestColors colors) {
    final piece = _floatPiece!;
    final blocked = _game.hoverAnchor != null && !_game.hoverValid;
    final color = blocked ? _blocked : _colorFor(colors, piece.colorIndex);
    return Positioned(
      left: _finger!.dx - (_grab!.c + 0.5) * _boardCell!,
      top: _finger!.dy - (_grab!.r + 0.5) * _boardCell!,
      child: IgnorePointer(
        child: PieceView(
          cells: piece.cells,
          color: color,
          cellSize: _boardCell!,
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
    _stopMotion();
    _game.restart();
    _bestAtStart = _game.best;
  }

  Future<void> _changeLevel(NestLevel level) async {
    if (level == widget.controller.level) return;
    if (_game.score == 0) {
      _applyLevel(level);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = nestOf(context);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Сменить режим?',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Счёт обнулится.',
            style: TextStyle(color: colors.muted, fontSize: 16),
          ),
          actions: [
            TextButton(
              key: const Key('confirm-level-no'),
              onPressed: () => Navigator.pop(context, false),
              child: Text('Нет', style: TextStyle(color: colors.muted)),
            ),
            TextButton(
              key: const Key('confirm-level-yes'),
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
    if (confirmed != true || !mounted || level == widget.controller.level) {
      return;
    }
    _applyLevel(level);
  }

  void _applyLevel(NestLevel level) {
    widget.sound.play(Sfx.tap);
    _stopMotion();
    _detach(_game);
    _game = BlastGame(best: widget.controller.bestFor(level), level: level);
    _trayEpoch = _game.trayEpoch;
    _attach(_game);
    _bestAtStart = _game.best;
    _syncScore();
    widget.controller.setLevel(level);
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

  void _showPraise() {
    _praiseLines = _game.lastClear;
    _praiseWord = BlastGame.praiseFor(_praiseLines);
    _praiseGain =
        100 * _praiseLines * _praiseLines +
        BlastGame.bombScore * _game.lastBombs;
    _praise.forward(from: 0);
  }

  void _stopMotion() {
    _commitArmed = false;
    _burst.stop();
    _burst.value = 0;
    _praise.stop();
    _praise.value = 0;
    _praiseWord = null;
    _finger = null;
    _grab = null;
    _arrive.stop();
    _arrive.value = 1;
  }

  void _undo() {
    _stopMotion();
    _game.undo();
  }

  Widget _praiseOverlay(NestColors nestColors) {
    final t = _praise.value;
    final fade = _praiseFade(t);
    final rise = _praiseRise(t);
    final scale =
        0.94 + 0.06 * Curves.easeOutCubic.transform((t / 0.32).clamp(0, 1));
    final paint = _praiseColors(_praiseLines);
    final style = TextStyle(
      fontSize: _praiseLines >= 3 ? 48 : 42,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.4,
      height: 1,
    );
    final word = _praiseWord!;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(0, rise),
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          word,
                          style: style.copyWith(
                            color: paint.first.withValues(alpha: 0.45),
                            shadows: [
                              Shadow(color: paint.first, blurRadius: 22),
                              const Shadow(
                                color: Color(0xE6100C08),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: paint,
                            ).createShader(bounds);
                          },
                          child: Text(
                            word,
                            style: style.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '+$_praiseGain',
                      style: TextStyle(
                        color: paint.last,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        shadows: [
                          Shadow(
                            color: nestColors.bg.withValues(alpha: 0.85),
                            blurRadius: 8,
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
    );
  }

  void _startDrag(int slot, Point grab, Offset global) {
    final stack = _toStack(global);
    final cell = _readCell();
    if (stack == null || cell == null) return;
    _grab = grab;
    _finger = stack;
    _boardCell = cell;
    _game.beginDrag(slot);
  }

  void _moveDrag(Offset global) {
    if (_game.draggingSlot == null || _grab == null) return;
    final stack = _toStack(global);
    final board = _toBoard(global);
    final cell = _boardCell ?? _readCell();
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || board == null || cell == null || box == null) return;
    final overHold = _overHold(global);
    _game.setHoldHot(overHold);
    final inside =
        !overHold &&
        board.dx >= -cell * 0.45 &&
        board.dy >= -cell * 0.45 &&
        board.dx <= box.size.width + cell * 0.45 &&
        board.dy <= box.size.height + cell * 0.45;
    final col = (board.dx / cell).floor();
    final row = (board.dy / cell).floor();
    _game.hover(Point(row - _grab!.r, col - _grab!.c), active: inside);
    setState(() {
      _finger = stack;
      _boardCell = cell;
    });
  }

  void _endDrag() {
    if (_game.holdHot) {
      _game.storeDragged();
    } else {
      _game.drop();
    }
    setState(() {
      _finger = null;
      _grab = null;
    });
  }

  void _cancelDrag() {
    _game.cancelDrag();
    setState(() {
      _finger = null;
      _grab = null;
    });
  }

  bool _overHold(Offset global) {
    final box = _holdKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    return local.dx >= -8 &&
        local.dy >= -8 &&
        local.dx <= box.size.width + 8 &&
        local.dy <= box.size.height + 8;
  }

  Offset? _toStack(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  Offset? _toBoard(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  double? _readCell() {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.size.width / BlastGame.size;
  }

  double _praiseFade(double t) {
    if (t < 0.28) return Curves.easeOut.transform(t / 0.28);
    if (t < 0.62) return 1;
    return Curves.easeIn.transform((1 - (t - 0.62) / 0.38).clamp(0, 1));
  }

  double _praiseRise(double t) {
    if (t < 0.28) {
      return 18 * (1 - Curves.easeOutCubic.transform(t / 0.28));
    }
    if (t < 0.62) return 0;
    return -14 * Curves.easeInCubic.transform(((t - 0.62) / 0.38).clamp(0, 1));
  }

  List<Color> _praiseColors(int lines) {
    if (lines >= 3) {
      return const [
        Color(0xFFFF5C8A),
        Color(0xFFFFD84A),
        Color(0xFF5DFFB0),
        Color(0xFF73B6FF),
      ];
    }
    if (lines >= 2) {
      return const [Color(0xFFFFB03A), Color(0xFFFF4F88), Color(0xFFC86BFF)];
    }
    return const [Color(0xFFFFF06A), Color(0xFFFF8A1E)];
  }
}

double _trayCellSize(
  List<BlastPiece> pieces,
  double maxWidth,
  double maxHeight,
) {
  var cell = 22.0;
  if (pieces.isEmpty) return cell;
  while (cell > 12 && _trayHeight(pieces, cell, maxWidth) > maxHeight) {
    cell -= 0.5;
  }
  return cell;
}

double _trayHeight(List<BlastPiece> pieces, double cell, double maxWidth) {
  var x = 0.0;
  var rowH = 0.0;
  var total = 0.0;
  var wraps = 0;
  for (final piece in pieces) {
    final w = piece.shapeWidth * cell + _trayPad * 2;
    final h = piece.shapeHeight * cell + _trayPad * 2;
    if (x > 0 && x + w > maxWidth) {
      total += rowH;
      wraps++;
      x = 0;
      rowH = 0;
    }
    if (x > 0) x += _trayGap;
    x += w;
    if (h > rowH) rowH = h;
  }
  return total + rowH + wraps * _trayGap;
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    final colors = nestOf(context);
    Widget dot(Color color) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3.5),
        ),
      );
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        children: [
          Positioned(left: 8, top: 0, child: dot(colors.blocks[2])),
          Positioned(left: 0, top: 10, child: dot(colors.blocks[0])),
          Positioned(right: 0, top: 10, child: dot(colors.blocks[4])),
          Positioned(left: 8, top: 16, child: dot(colors.blocks[1])),
        ],
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    super.key,
    required this.game,
    required this.cell,
    required this.colors,
    required this.burst,
  });

  final BlastGame game;
  final double cell;
  final NestColors colors;
  final double burst;

  @override
  Widget build(BuildContext context) {
    final preview = game.clearPreview;
    final dragging = game.draggingSlot == null
        ? null
        : game.tray[game.draggingSlot!];
    return SizedBox(
      width: cell * BlastGame.size,
      height: cell * BlastGame.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var r = 0; r < BlastGame.size; r++)
            for (var c = 0; c < BlastGame.size; c++)
              _socket(r, c, preview.contains(Point(r, c))),
          for (var r = 0; r < BlastGame.size; r++)
            for (var c = 0; c < BlastGame.size; c++)
              if (game.board[r][c] != null)
                _filled(
                  r,
                  c,
                  game.board[r][c]!,
                  game.bursting.contains(Point(r, c)),
                ),
          for (final bomb in game.bombs)
            _bomb(bomb, game.bursting.contains(bomb)),
          if (dragging != null && game.hoverAnchor != null)
            for (final part in dragging.cells) _ghost(dragging, part),
        ],
      ),
    );
  }

  Widget _socket(int r, int c, bool armed) {
    return Positioned(
      left: CellMetrics.offset(c, cell),
      top: CellMetrics.offset(r, cell),
      width: CellMetrics.block(cell),
      height: CellMetrics.block(cell),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: armed ? colors.accent.withValues(alpha: 0.28) : colors.socket,
          borderRadius: BorderRadius.circular(CellMetrics.radius(cell)),
          border: Border.all(
            color: armed ? colors.accent.withValues(alpha: 0.8) : colors.line,
          ),
        ),
      ),
    );
  }

  Widget _filled(int r, int c, int colorIndex, bool exploding) {
    final color = colors.blocks[colorIndex % colors.blocks.length];
    final t = exploding ? burst : 0.0;
    final gem = BlockGem(color: color, radius: CellMetrics.radius(cell));
    return Positioned(
      left: CellMetrics.offset(c, cell),
      top: CellMetrics.offset(r, cell),
      width: CellMetrics.block(cell),
      height: CellMetrics.block(cell),
      child: exploding
          ? Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Transform.scale(
                scale: 1 + t * 0.85,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.55 * (1 - t)),
                        blurRadius: 16 * t + 4,
                        spreadRadius: 2 * t,
                      ),
                    ],
                  ),
                  child: gem,
                ),
              ),
            )
          : gem,
    );
  }

  Widget _bomb(Point bomb, bool exploding) {
    final t = exploding ? burst : 0.0;
    final gem = const BombGem();
    return Positioned(
      key: ValueKey('bomb-${bomb.r}-${bomb.c}'),
      left: CellMetrics.offset(bomb.c, cell),
      top: CellMetrics.offset(bomb.r, cell),
      width: CellMetrics.block(cell),
      height: CellMetrics.block(cell),
      child: exploding
          ? Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Transform.scale(scale: 1 + t * 1.15, child: gem),
            )
          : gem,
    );
  }

  Widget _ghost(BlastPiece piece, Point part) {
    final r = game.hoverAnchor!.r + part.r;
    final c = game.hoverAnchor!.c + part.c;
    if (r < 0 || c < 0 || r >= BlastGame.size || c >= BlastGame.size) {
      return const SizedBox.shrink();
    }
    final blocked = !game.hoverValid;
    return Positioned(
      left: CellMetrics.offset(c, cell),
      top: CellMetrics.offset(r, cell),
      width: CellMetrics.block(cell),
      height: CellMetrics.block(cell),
      child: BlockGem(
        color: blocked
            ? _blocked
            : colors.blocks[piece.colorIndex % colors.blocks.length],
        radius: CellMetrics.radius(cell),
        pale: !blocked,
      ),
    );
  }
}

class _TrayPiece extends StatelessWidget {
  const _TrayPiece({
    super.key,
    required this.piece,
    required this.color,
    required this.cell,
    required this.surface,
    required this.line,
    required this.muted,
    required this.faded,
    required this.onRotate,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final BlastPiece piece;
  final Color color;
  final double cell;
  final Color surface;
  final Color line;
  final Color muted;
  final bool faded;
  final VoidCallback onRotate;
  final void Function(Point grab, Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.28 : 1,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRotate,
          onPanStart: (details) {
            final col = ((details.localPosition.dx - _trayPad) / cell).floor();
            final row = ((details.localPosition.dy - _trayPad) / cell).floor();
            onDragStart(
              nearestCell(piece.cells, row, col),
              details.globalPosition,
            );
          },
          onPanUpdate: (details) => onDragUpdate(details.globalPosition),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragCancel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_trayPad),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PieceView(cells: piece.cells, color: color, cellSize: cell),
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Icon(
                      Icons.rotate_right_rounded,
                      size: 13,
                      color: muted,
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
}
