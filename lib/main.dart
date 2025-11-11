import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'data/word_levels.dart';

void main() {
  runApp(const TypingWordsGame());
}

class TypingWordsGame extends StatelessWidget {
  const TypingWordsGame({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blueGrey,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF10141A),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Typing Words Game',
      theme: theme,
      home: const TypingGamePage(),
    );
  }
}

enum GameStatus { idle, running, victory, gameOver }

class GameLevel {
  const GameLevel({
    required this.level,
    required this.words,
    required this.fallDuration,
  });

  final int level;
  final List<String> words;
  final Duration fallDuration;
}

class ActiveWord {
  ActiveWord({
    required this.text,
    required this.spawnedAt,
    required this.fallDuration,
    required this.xFraction,
  });

  final String text;
  final DateTime spawnedAt;
  final Duration fallDuration;
  final double xFraction;
}

class TypingGamePage extends StatefulWidget {
  const TypingGamePage({super.key});

  @override
  State<TypingGamePage> createState() => _TypingGamePageState();
}

class _TypingGamePageState extends State<TypingGamePage>
    with SingleTickerProviderStateMixin {
  static const int _maxHp = 100;
  static const int _hpPenalty = 10;
  static const int _maxActiveWords = 5;
  static const Duration _spawnInterval = Duration(seconds: 2);
  static const double _redLineOffset = 50;

  final List<GameLevel> _levels = const [
    GameLevel(
      level: 1,
      fallDuration: Duration(seconds: 15),
      words: level1Words,
    ),
    GameLevel(
      level: 2,
      fallDuration: Duration(seconds: 14),
      words: level2Words,
    ),
    GameLevel(
      level: 3,
      fallDuration: Duration(seconds: 13),
      words: level3Words,
    ),
    GameLevel(
      level: 4,
      fallDuration: Duration(seconds: 12),
      words: level4Words,
    ),
    GameLevel(
      level: 5,
      fallDuration: Duration(seconds: 11),
      words: level5Words,
    ),
  ];

  final List<ActiveWord> _activeWords = [];
  final math.Random _random = math.Random();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  late final FlutterTts _tts;

  late final Ticker _ticker;

  GameStatus _status = GameStatus.idle;
  int _currentLevelIndex = 0;
  int _nextWordInLevel = 0;
  int _hp = _maxHp;
  DateTime? _gameStartTime;
  DateTime _lastTick = DateTime.now();
  DateTime? _lastSpawnTime;
  Duration _elapsed = Duration.zero;
  Duration? _completionTime;
  bool _suppressInputChanges = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    _tts = FlutterTts();
    _initializeTts();
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    _ticker.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleTick(Duration elapsed) {
    if (_status != GameStatus.running || _gameStartTime == null) {
      return;
    }

    final now = DateTime.now();
    setState(() {
      _lastTick = now;
      _elapsed = now.difference(_gameStartTime!);

      final expiredCount = _removeExpiredWords(now);
      if (_hp <= 0) {
        _hp = 0;
        _status = GameStatus.gameOver;
        _ticker.stop();
        return;
      }

      if (_status != GameStatus.running) {
        return;
      }

      if (expiredCount > 0) {
        for (int i = 0; i < expiredCount; i++) {
          _spawnWordNow(now);
        }
      }

      _maybeSpawnPeriodic(now);
      _checkVictory();
    });
  }

  int _removeExpiredWords(DateTime now) {
    if (_activeWords.isEmpty) {
      return 0;
    }

    final List<ActiveWord> expired = [];
    for (final word in _activeWords) {
      final elapsed = now.difference(word.spawnedAt);
      if (elapsed >= word.fallDuration) {
        expired.add(word);
      }
    }

    if (expired.isEmpty) {
      return 0;
    }

    for (final word in expired) {
      _activeWords.remove(word);
    }

    final loss = expired.length * _hpPenalty;
    _hp = math.max(0, _hp - loss);
    return expired.length;
  }

  void _maybeSpawnPeriodic(DateTime now) {
    if (_activeWords.length >= _maxActiveWords) {
      return;
    }
    if (!_hasPendingWordsToSpawn()) {
      return;
    }
    if (_lastSpawnTime == null ||
        now.difference(_lastSpawnTime!) >= _spawnInterval) {
      _spawnWordNow(now);
    }
  }

  bool _hasPendingWordsToSpawn() {
    if (_currentLevelIndex >= _levels.length) {
      return false;
    }
    final bool hasCurrent =
        _nextWordInLevel < _levels[_currentLevelIndex].words.length;
    if (_currentLevelIndex < _levels.length - 1) {
      return true;
    }
    return hasCurrent;
  }

  bool _spawnWordNow(DateTime now) {
    if (_activeWords.length >= _maxActiveWords) {
      return false;
    }

    while (_currentLevelIndex < _levels.length) {
      final level = _levels[_currentLevelIndex];
      if (_nextWordInLevel >= level.words.length) {
        if (_currentLevelIndex < _levels.length - 1) {
          _currentLevelIndex++;
          _nextWordInLevel = 0;
          continue;
        }
        return false;
      }

      final text = level.words[_nextWordInLevel];
      _nextWordInLevel++;

      final word = ActiveWord(
        text: text,
        spawnedAt: now,
        fallDuration: level.fallDuration,
        xFraction: 0.1 + _random.nextDouble() * 0.8,
      );
      _activeWords.add(word);
      _lastSpawnTime = now;

      if (_nextWordInLevel >= level.words.length &&
          _currentLevelIndex < _levels.length - 1) {
        _currentLevelIndex++;
        _nextWordInLevel = 0;
      }

      return true;
    }

    return false;
  }

  void _checkVictory() {
    if (_status != GameStatus.running) {
      return;
    }
    if (!_hasPendingWordsToSpawn() && _activeWords.isEmpty) {
      _status = GameStatus.victory;
      _completionTime = _elapsed;
      _ticker.stop();
    }
  }

  void _startGame() {
    final startTime = DateTime.now();
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _status = GameStatus.running;
      _hp = _maxHp;
      _currentLevelIndex = 0;
      _nextWordInLevel = 0;
      _activeWords.clear();
      _gameStartTime = startTime;
      _elapsed = Duration.zero;
      _completionTime = null;
      _lastTick = startTime;
      _lastSpawnTime = null;
      _spawnWordNow(startTime);
    });

    _clearInput();
    _focusInputField();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _status == GameStatus.running) {
        _focusInputField();
      }
    });

    _ticker.start();
  }

  void _processSubmission() {
    final rawInput = _inputController.text.trim().toLowerCase();
    _clearInput();
    _focusInputField();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _status == GameStatus.running) {
        _focusInputField();
      }
    });

    if (_status != GameStatus.running || rawInput.isEmpty) {
      return;
    }

    final now = DateTime.now();
    String? matchedWord;
    setState(() {
      final index = _activeWords.indexWhere(
        (word) => word.text == rawInput.trim(),
      );
      if (index != -1) {
        matchedWord = _activeWords[index].text;
        _activeWords.removeAt(index);
        _spawnWordNow(now);
        _checkVictory();
      }
    });
    if (matchedWord != null) {
      unawaited(_speakWord(matchedWord!));
    }
  }

  void _clearInput() {
    _suppressInputChanges = true;
    _inputController.clear();
    _suppressInputChanges = false;
  }

  void _focusInputField() {
    if (!_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
    }
  }

  void _handleInputChanged(String value) {
    if (_suppressInputChanges) {
      return;
    }
    if (value.endsWith(' ') || value.contains('\n')) {
      _processSubmission();
    }
  }

  Future<void> _initializeTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.6);
      await _tts.setPitch(1.1);
    } catch (_) {
      // Ignore initialization errors; speech is a bonus feature.
    }
  }

  Future<void> _speakWord(String word) async {
    if (word.isEmpty) {
      return;
    }
    try {
      await _tts.stop();
      await _tts.speak(word);
    } catch (_) {
      // Ignore TTS errors so gameplay is uninterrupted.
    }
  }

  Color _levelColor(int level) {
    switch (level) {
      case 1:
        return Colors.white;
      case 2:
        return Colors.lightBlueAccent;
      case 3:
        return Colors.redAccent;
      case 4:
        return Colors.greenAccent;
      case 5:
        return Colors.cyanAccent;
      default:
        return Colors.white;
    }
  }

  String _formatDuration(Duration duration) {
    final totalMilliseconds = duration.inMilliseconds;
    final minutes = (totalMilliseconds ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((totalMilliseconds % 60000) ~/ 1000).toString().padLeft(
      2,
      '0',
    );
    final millis = (totalMilliseconds % 1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$millis';
  }

  @override
  Widget build(BuildContext context) {
    final level = _levels[_currentLevelIndex];
    final color = _levelColor(level.level);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: _focusInputField,
          behavior: HitTestBehavior.opaque,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final redLineY = math.max(
                0.0,
                constraints.maxHeight - _redLineOffset,
              );
              final targetAlignY = (redLineY / constraints.maxHeight) * 2 - 1;

              return Stack(
                children: [
                  _buildGameField(constraints, targetAlignY),
                  _buildRedLine(redLineY),
                  _buildHud(level.level, color),
                  _buildInputBar(),
                  if (_status != GameStatus.running) _buildOverlay(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGameField(BoxConstraints constraints, double targetAlignY) {
    final widgets = <Widget>[];
    for (final word in _activeWords) {
      final progress = _wordProgress(word, _lastTick);
      final alignY = _lerp(-1, targetAlignY, progress);
      final alignX = -1 + word.xFraction * 2;

      widgets.add(
        Align(
          alignment: Alignment(alignX, alignY),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              word.text,
              style: const TextStyle(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(child: Stack(children: widgets));
  }

  Widget _buildRedLine(double top) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Container(height: 4, color: Colors.redAccent),
    );
  }

  Widget _buildHud(int levelNumber, Color levelColor) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Level $levelNumber',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(
                  _status == GameStatus.victory && _completionTime != null
                      ? _completionTime!
                      : _elapsed,
                ),
                style: TextStyle(
                  fontSize: 18,
                  color: levelColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'HP',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _hp / _maxHp,
                    minHeight: 12,
                    color: Colors.redAccent,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_hp / $_maxHp',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: _redLineOffset,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: const Color(0xFF111820),
        child: Center(
          child: TextField(
            controller: _inputController,
            focusNode: _inputFocusNode,
            enabled: _status == GameStatus.running,
            autofocus: _status == GameStatus.running,
            onChanged: _handleInputChanged,
            onSubmitted: (_) => _processSubmission(),
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            cursorColor: Colors.cyanAccent,
            decoration: InputDecoration(
              hintText: _status == GameStatus.running
                  ? 'Type the word and press space/enter'
                  : 'Press Start to begin',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1D2833),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.cyanAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    String title;
    String? subtitle;
    switch (_status) {
      case GameStatus.idle:
        title = 'Typing Words Game';
        subtitle = 'Press start to begin';
        break;
      case GameStatus.gameOver:
        title = 'Game Over';
        subtitle = 'HP depleted. Try again!';
        break;
      case GameStatus.victory:
        title = 'Victory!';
        final completion = _completionTime != null
            ? _formatDuration(_completionTime!)
            : '--';
        subtitle = 'Time: $completion  |  HP: $_hp';
        break;
      case GameStatus.running:
        title = '';
        break;
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 18, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text('START'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _wordProgress(ActiveWord word, DateTime now) {
    final elapsed = now.difference(word.spawnedAt);
    final duration = word.fallDuration.inMilliseconds;
    if (duration <= 0) {
      return 1;
    }
    return (elapsed.inMilliseconds / duration).clamp(0.0, 1.0);
  }

  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
