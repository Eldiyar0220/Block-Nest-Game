/// How a run is dealt.
enum NestLevel {
  easy,
  medium,
  hard,
  fun;

  String get title => switch (this) {
    NestLevel.easy => 'Classic',
    NestLevel.medium => 'Normal',
    NestLevel.hard => 'Сложный',
    NestLevel.fun => 'FUN',
  };

  String get blurb => switch (this) {
    NestLevel.easy => 'Следующие фигуры видны. Запас без ограничений.',
    NestLevel.medium => 'Запас один раз. Бомбы приходят парами.',
    NestLevel.hard => 'Без запаса. Бомбы появляются часто.',
    NestLevel.fun => 'Молния копится. Потом сам выбираешь ряд.',
  };

  bool get hasBombs => bombPace != null;

  bool get isFun => this == NestLevel.fun;

  bool get showsNext => this == NestLevel.easy || this == NestLevel.fun;

  /// Hard has no spare pocket. Easy and FUN can use it freely, medium once.
  bool get hasHold => this != NestLevel.hard;

  bool get unlimitedHold => this == NestLevel.easy || this == NestLevel.fun;

  /// Medium plants a pair, then waits. Hard plants a bomb on every move.
  /// FUN leaves every cell free. A full lightning charge lets the player pick a row.
  BombPace? get bombPace => switch (this) {
    NestLevel.easy || NestLevel.fun => null,
    NestLevel.medium => const BombPace(opening: 2, wave: 2, every: 6, cap: 4),
    NestLevel.hard => const BombPace(opening: 3, wave: 1, every: 1, cap: 5),
  };
}

/// When bombs show up during a run.
class BombPace {
  const BombPace({
    required this.opening,
    required this.wave,
    required this.every,
    required this.cap,
  });

  /// Bombs already on the board when the run starts.
  final int opening;

  /// How many bombs one wave tries to plant.
  final int wave;

  /// A wave lands on every Nth placement that did not clear a line.
  final int every;

  /// Bombs already sitting on the board block further plants.
  final int cap;
}
