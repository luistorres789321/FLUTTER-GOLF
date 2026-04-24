import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golf_scorecard_screen.dart';
import 'services/datos_servidor_service.dart';

void main() {
  runApp(const GolfScorecardApp());
}

class GolfScorecardApp extends StatelessWidget {
  const GolfScorecardApp({super.key});

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFF545B66);

    return MaterialApp(
      title: 'Tarjeta de golf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Trebuchet MS',
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
        ),
      ),
      home: const GolfAppHome(),
    );
  }
}

class GolfAppHome extends StatefulWidget {
  const GolfAppHome({super.key});

  @override
  State<GolfAppHome> createState() => _GolfAppHomeState();
}

class _GolfAppHomeState extends State<GolfAppHome> {
  static const _savedGameIdKey = 'saved_game_id';
  static const _savedFieldIdKey = 'saved_field_id';
  static const _savedPlayersKey = 'saved_players';
  static const _savedGameRowsKey = 'saved_game_rows_json';
  static const _defaultFieldId = '1';
  static const _defaultPlayers = '3';
  static const _jsonHoyosPollDelay = Duration(seconds: 5);

  late final DatosServidorService _datosServidorService;
  int _jsonHoyosPollingGeneration = 0;
  bool _isLoading = true;
  bool _isCreatingGame = false;
  String? _savedGameId;
  String _savedFieldId = _defaultFieldId;
  String _savedPlayers = _defaultPlayers;
  String _savedRowsJson = _createEmptyPlayRowsJson();
  String? _differentRemotePlayRowsJson;
  String? _creationError;
  _GameSession? _activeSession;

  @override
  void initState() {
    super.initState();
    _datosServidorService = DatosServidorService();
    _loadSavedGame();
  }

  @override
  void dispose() {
    _stopJsonHoyosPolling();
    _datosServidorService.close();
    super.dispose();
  }

  Future<void> _loadSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGameId = prefs.getString(_savedGameIdKey);
    final savedFieldId = prefs.getString(_savedFieldIdKey) ?? _defaultFieldId;
    final savedPlayers = prefs.getString(_savedPlayersKey) ?? _defaultPlayers;
    final savedRowsJson =
        prefs.getString(_savedGameRowsKey) ?? _createEmptyPlayRowsJson();

    if (!mounted) {
      return;
    }

    setState(() {
      _savedGameId = savedGameId;
      _savedFieldId = savedFieldId;
      _savedPlayers = savedPlayers;
      _savedRowsJson = savedRowsJson;
      _isLoading = false;
    });
  }

  Future<void> _startNewGame() async {
    final newId = _generateGameId();
    const fieldId = _defaultFieldId;
    const players = _defaultPlayers;
    final newRowsJson = _createEmptyPlayRowsJson();

    setState(() {
      _isCreatingGame = true;
      _creationError = null;
    });

    try {
      await _datosServidorService.creaPartida(fieldId, newId, players);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedGameIdKey, newId);
      await prefs.setString(_savedFieldIdKey, fieldId);
      await prefs.setString(_savedPlayersKey, players);
      await prefs.setString(_savedGameRowsKey, newRowsJson);

      if (!mounted) {
        return;
      }

      setState(() {
        _isCreatingGame = false;
        _savedGameId = newId;
        _savedFieldId = fieldId;
        _savedPlayers = players;
        _savedRowsJson = newRowsJson;
        _differentRemotePlayRowsJson = null;
        _activeSession = _GameSession(
          idPartida: newId,
          idCampo: fieldId,
          jugadores: players,
          playRowsJson: newRowsJson,
        );
      });
      _startJsonHoyosPolling();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCreatingGame = false;
        _creationError = 'No se pudo crear la partida en el servidor.';
      });
    }
  }

  void _recoverGame() {
    final savedGameId = _savedGameId;
    if (savedGameId == null) {
      return;
    }

    setState(() {
      _creationError = null;
      _differentRemotePlayRowsJson = null;
      _activeSession = _GameSession(
        idPartida: savedGameId,
        idCampo: _savedFieldId,
        jugadores: _savedPlayers,
        playRowsJson: _savedRowsJson,
      );
    });
    _startJsonHoyosPolling();
  }

  Future<void> _savePlayRowsJson(String playRowsJson) async {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    _setDifferentRemotePlayRowsJson(null);
    await _savePlayRowsJsonLocally(session, playRowsJson);

    if (!mounted || !_isCurrentSession(session)) {
      return;
    }

    try {
      final respuesta = await _datosServidorService.anotaJsonHoyos(
        session.idCampo,
        session.idPartida,
        playRowsJson,
      );
      debugPrint('anotaJsonHoyos: $respuesta');
    } catch (error) {
      debugPrint('anotaJsonHoyos error: $error');
      // La tarjeta ya queda guardada en el dispositivo aunque falle el envio.
    }
  }

  Future<void> _savePlayRowsJsonLocally(
    _GameSession session,
    String playRowsJson,
  ) async {
    if (!_isCurrentSession(session)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentSession(session)) {
      return;
    }

    await prefs.setString(_savedGameIdKey, session.idPartida);
    await prefs.setString(_savedFieldIdKey, session.idCampo);
    await prefs.setString(_savedPlayersKey, session.jugadores);
    await prefs.setString(_savedGameRowsKey, playRowsJson);

    if (!mounted || !_isCurrentSession(session)) {
      return;
    }

    setState(() {
      _savedGameId = session.idPartida;
      _savedFieldId = session.idCampo;
      _savedPlayers = session.jugadores;
      _savedRowsJson = playRowsJson;
      _activeSession = _GameSession(
        idPartida: session.idPartida,
        idCampo: session.idCampo,
        jugadores: session.jugadores,
        playRowsJson: playRowsJson,
      );
    });
  }

  void _startJsonHoyosPolling() {
    if (_activeSession == null) {
      return;
    }

    final generation = ++_jsonHoyosPollingGeneration;
    unawaited(_pollJsonHoyos(generation));
  }

  void _stopJsonHoyosPolling() {
    _jsonHoyosPollingGeneration++;
  }

  Future<void> _pollJsonHoyos(int generation) async {
    while (mounted && generation == _jsonHoyosPollingGeneration) {
      final session = _activeSession;
      if (session == null) {
        return;
      }

      try {
        final respuesta = await _datosServidorService.obtenerJsonHoyos(
          session.idCampo,
          session.idPartida,
        );

        if (!mounted || generation != _jsonHoyosPollingGeneration) {
          return;
        }

        await _applyRemotePlayRowsJson(session, respuesta);
      } catch (error) {
        debugPrint('obtenerJsonHoyos error: $error');
      }

      if (!mounted || generation != _jsonHoyosPollingGeneration) {
        return;
      }

      await Future<void>.delayed(_jsonHoyosPollDelay);
    }
  }

  Future<void> _applyRemotePlayRowsJson(
    _GameSession requestedSession,
    String rawResponse,
  ) async {
    final session = _activeSession;
    if (session == null ||
        session.idCampo != requestedSession.idCampo ||
        session.idPartida != requestedSession.idPartida) {
      return;
    }

    final mergedJson = _mergeNewerPlayRowsJson(
      currentJson: session.playRowsJson,
      remoteResponse: rawResponse,
    );
    _setDifferentRemotePlayRowsJson(
      _differentPlayRowsJson(
        currentJson: session.playRowsJson,
        remoteResponse: rawResponse,
      ),
    );

    if (mergedJson == null || mergedJson == session.playRowsJson) {
      return;
    }

    await _savePlayRowsJsonLocally(session, mergedJson);
  }

  void _setDifferentRemotePlayRowsJson(String? playRowsJson) {
    if (!mounted || _differentRemotePlayRowsJson == playRowsJson) {
      return;
    }

    setState(() {
      _differentRemotePlayRowsJson = playRowsJson;
    });
  }

  bool _isCurrentSession(_GameSession session) {
    final activeSession = _activeSession;
    return activeSession != null &&
        activeSession.idCampo == session.idCampo &&
        activeSession.idPartida == session.idPartida;
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession case final session?) {
      return GolfScorecardScreen(
        idPartida: session.idPartida,
        jugadores: session.jugadores,
        initialPlayRowsJson: session.playRowsJson,
        differentRemotePlayRowsJson: _differentRemotePlayRowsJson,
        onPlayRowsJsonChanged: _savePlayRowsJson,
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6B432D), Color(0xFF472819)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: Color(0xFFF6F2EA))
                : Container(
                    width: 420,
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFAF8F3), Color(0xFFF6F2EA)],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(28, 14, 8, 0.26),
                          blurRadius: 50,
                          offset: Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Tarjeta de golf',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF545B66),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _savedGameId == null
                              ? 'No hay ninguna partida guardada en este dispositivo.'
                              : 'Partida guardada: $_savedGameId\nCampo: $_savedFieldId · Jugadores: $_savedPlayers',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6C737D),
                          ),
                        ),
                        if (_creationError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _creationError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9D433D),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        FilledButton(
                          onPressed: _savedGameId == null ? null : _recoverGame,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF567B37),
                            disabledBackgroundColor: const Color(0xFFBBC5B0),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: const Text('Recuperar partida'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: _isCreatingGame ? null : _startNewGame,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B432D),
                            side: const BorderSide(color: Color(0xFF6B432D)),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: Text(
                            _isCreatingGame
                                ? 'Creando partida...'
                                : 'Iniciar nueva partida',
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

  String _generateGameId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

String _createEmptyPlayRowsJson() {
  final data = List.generate(4, (rowIndex) {
    return <String, String>{
      'jugador': '${rowIndex + 1}',
      'modificado': '',
      for (var holeIndex = 0; holeIndex < 18; holeIndex++)
        'hoyo_${holeIndex + 1}': '',
    };
  });

  return jsonEncode(data);
}

String? _mergeNewerPlayRowsJson({
  required String currentJson,
  required String remoteResponse,
}) {
  final currentRows =
      _decodePlayRowsPayload(currentJson) ??
      _decodePlayRowsPayload(_createEmptyPlayRowsJson());
  final remoteRows = _decodePlayRowsPayload(remoteResponse);
  if (currentRows == null || remoteRows == null) {
    return null;
  }

  final remoteRowsByPlayer = <String, Map<String, dynamic>>{};
  for (var index = 0; index < remoteRows.length; index++) {
    remoteRowsByPlayer[_playRowPlayerId(remoteRows[index], index)] =
        remoteRows[index];
  }

  var hasChanges = false;
  final mergedRows = currentRows
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);

  for (var index = 0; index < mergedRows.length; index++) {
    final currentRow = mergedRows[index];
    final remoteRow = remoteRowsByPlayer[_playRowPlayerId(currentRow, index)];
    if (remoteRow == null) {
      continue;
    }

    final remoteModified = _modifiedTimestampValue(remoteRow['modificado']);
    final currentModified = _modifiedTimestampValue(currentRow['modificado']);
    if (!_jsonValuesAreEqual(currentRow, remoteRow) &&
        remoteModified > currentModified) {
      mergedRows[index] = Map<String, dynamic>.from(remoteRow);
      hasChanges = true;
    }
  }

  return hasChanges ? jsonEncode(mergedRows) : null;
}

String? _differentPlayRowsJson({
  required String currentJson,
  required String remoteResponse,
}) {
  final currentRows = _decodePlayRowsPayload(currentJson);
  final remoteRows = _decodePlayRowsPayload(remoteResponse);
  if (currentRows == null || remoteRows == null) {
    return null;
  }

  return _jsonValuesAreEqual(currentRows, remoteRows)
      ? null
      : jsonEncode(remoteRows);
}

List<Map<String, dynamic>>? _decodePlayRowsPayload(Object? payload) {
  return _decodePlayRowsPayloadValue(payload, 0);
}

List<Map<String, dynamic>>? _decodePlayRowsPayloadValue(
  Object? payload,
  int depth,
) {
  if (depth > 4) {
    return null;
  }

  if (payload is String) {
    final trimmedPayload = payload.trim();
    if (trimmedPayload.isEmpty) {
      return null;
    }

    final wrappedJsonHoyos = _extractWrappedPlayRowsJson(trimmedPayload);
    if (wrappedJsonHoyos != null) {
      return _decodePlayRowsPayloadValue(wrappedJsonHoyos, depth + 1);
    }

    try {
      return _decodePlayRowsPayloadValue(jsonDecode(trimmedPayload), depth + 1);
    } catch (_) {
      return null;
    }
  }

  if (payload is List) {
    return payload.whereType<Map>().map(_stringKeyedMap).toList();
  }

  if (payload is Map) {
    final map = _stringKeyedMap(payload);
    for (final key in const [
      'json_hoyos',
      'jsonHoyos',
      'valor',
      'json',
      'data',
    ]) {
      if (!map.containsKey(key)) {
        continue;
      }

      final rows = _decodePlayRowsPayloadValue(map[key], depth + 1);
      if (rows != null) {
        return rows;
      }
    }
  }

  return null;
}

String? _extractWrappedPlayRowsJson(String rawResponse) {
  final match = RegExp(
    r'^\{"rpta":"[^"]*","json_hoyos":"(.*)"\}$',
    dotAll: true,
  ).firstMatch(rawResponse);

  return match?.group(1);
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry('$key', value));
}

String _playRowPlayerId(Map<String, dynamic> row, int fallbackIndex) {
  final player = row['jugador'];
  return player == null ? '${fallbackIndex + 1}' : '$player';
}

int _modifiedTimestampValue(Object? value) {
  return int.tryParse('${value ?? ''}') ?? -1;
}

bool _jsonValuesAreEqual(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }

    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonValuesAreEqual(entry.value, right[entry.key])) {
        return false;
      }
    }

    return true;
  }

  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (!_jsonValuesAreEqual(left[index], right[index])) {
        return false;
      }
    }

    return true;
  }

  return left == right;
}

class _GameSession {
  const _GameSession({
    required this.idPartida,
    required this.idCampo,
    required this.jugadores,
    required this.playRowsJson,
  });

  final String idPartida;
  final String idCampo;
  final String jugadores;
  final String playRowsJson;
}
