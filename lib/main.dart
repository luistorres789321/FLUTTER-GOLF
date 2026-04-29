import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golf_scorecard_screen.dart';
import 'services/datos_servidor_service.dart';

void main() {
  runApp(const GolfScorecardApp());
}

class GolfScorecardApp extends StatelessWidget {
  const GolfScorecardApp({super.key, this.datosServidorService});

  final DatosServidorService? datosServidorService;

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
      home: GolfAppHome(datosServidorService: datosServidorService),
    );
  }
}

class GolfAppHome extends StatefulWidget {
  const GolfAppHome({super.key, this.datosServidorService});

  final DatosServidorService? datosServidorService;

  @override
  State<GolfAppHome> createState() => _GolfAppHomeState();
}

class _GolfAppHomeState extends State<GolfAppHome> {
  static const _savedUserInformationKey = 'saved_user_information_json';
  static const _savedUserRegisteredKey = 'saved_user_registered';
  static const _userRegistrationRequiredMessage =
      'es necesario Guardar los datos de usuario';
  static const _savedGameIdKey = 'saved_game_id';
  static const _savedFieldIdKey = 'saved_field_id';
  static const _savedPlayersKey = 'saved_players';
  static const _savedGameRowsKey = 'saved_game_rows_json';
  static const _defaultFieldId = '1';
  static const _defaultPlayers = '3';
  static const _jsonHoyosPollDelay = Duration(seconds: 5);

  late final DatosServidorService _datosServidorService;
  late final bool _ownsDatosServidorService;
  int _jsonHoyosPollingGeneration = 0;
  bool _isLoading = true;
  bool _isCreatingGame = false;
  String? _savedGameId;
  String _savedFieldId = _defaultFieldId;
  String _savedPlayers = _defaultPlayers;
  String _savedRowsJson = _createEmptyPlayRowsJson();
  String? _differentRemotePlayRowsJson;
  String? _creationError;
  String? _userRegistrationError;
  _GameSession? _activeSession;
  List<_CreatedGameInfo> _createdGames = const [];
  _UserInformation? _userInformation;
  bool _isUserRegistered = false;
  bool _isEditingUserInformation = false;
  bool _isUserInformationDismissed = false;

  @override
  void initState() {
    super.initState();
    _ownsDatosServidorService = widget.datosServidorService == null;
    _datosServidorService =
        widget.datosServidorService ?? DatosServidorService();
    _loadSavedGame();
  }

  @override
  void dispose() {
    _stopJsonHoyosPolling();
    if (_ownsDatosServidorService) {
      _datosServidorService.close();
    }
    super.dispose();
  }

  Future<void> _loadSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGameId = prefs.getString(_savedGameIdKey);
    final savedFieldId = prefs.getString(_savedFieldIdKey) ?? _defaultFieldId;
    final savedPlayers = prefs.getString(_savedPlayersKey) ?? _defaultPlayers;
    final savedRowsJson =
        prefs.getString(_savedGameRowsKey) ?? _createEmptyPlayRowsJson();
    final userInformation = _UserInformation.fromJsonString(
      prefs.getString(_savedUserInformationKey),
    );
    final isUserRegistered =
        userInformation != null &&
        (prefs.getBool(_savedUserRegisteredKey) ?? false);

    if (!mounted) {
      return;
    }

    setState(() {
      _savedGameId = savedGameId;
      _savedFieldId = savedFieldId;
      _savedPlayers = savedPlayers;
      _savedRowsJson = savedRowsJson;
      _userInformation = userInformation;
      _isUserRegistered = isUserRegistered;
      _userRegistrationError = isUserRegistered
          ? null
          : _userRegistrationRequiredMessage;
      _isLoading = false;
    });

    if (isUserRegistered && userInformation.idUsuario.isNotEmpty) {
      unawaited(_loadCreatedGames(userInformation.idUsuario));
    }
  }

  Future<void> _saveUserInformation(
    _UserInformation information, {
    required bool isRegistered,
    String idUsuario = '',
  }) async {
    final savedInformation = information.copyWith(idUsuario: idUsuario);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedUserInformationKey,
      savedInformation.toJsonString(),
    );
    await prefs.setBool(_savedUserRegisteredKey, isRegistered);

    if (!mounted) {
      return;
    }

    setState(() {
      _userInformation = savedInformation;
      _isUserRegistered = isRegistered;
      _isEditingUserInformation = false;
      _isUserInformationDismissed = false;
      _userRegistrationError = isRegistered
          ? null
          : _userRegistrationRequiredMessage;
    });

    if (isRegistered && savedInformation.idUsuario.isNotEmpty) {
      unawaited(_loadCreatedGames(savedInformation.idUsuario));
    } else {
      setState(() {
        _createdGames = const [];
      });
    }
  }

  Future<void> _loadCreatedGames(String idUsuario) async {
    try {
      final response = await _datosServidorService.obtenerPartidasCreadas(
        idUsuario,
      );
      final createdGames = _createdGamesFromResponse(response);
      if (!mounted || _userInformation?.idUsuario != idUsuario) {
        return;
      }

      setState(() {
        _createdGames = createdGames;
      });
    } catch (error) {
      debugPrint('obtener partidas creadas fallo: $error');
      if (!mounted || _userInformation?.idUsuario != idUsuario) {
        return;
      }

      setState(() {
        _createdGames = const [];
      });
    }
  }

  void _editUserInformation() {
    setState(() {
      _isEditingUserInformation = true;
      _isUserInformationDismissed = false;
      _userRegistrationError = null;
      _creationError = null;
    });
  }

  void _cancelUserInformationEditing() {
    setState(() {
      _isEditingUserInformation = false;
      if (_userInformation == null) {
        _isUserInformationDismissed = true;
        _userRegistrationError = _userRegistrationRequiredMessage;
      } else if (!_isUserRegistered) {
        _userRegistrationError = _userRegistrationRequiredMessage;
      }
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

  void _openReservationDaySelection() {
    final currentIdPartida = _activeSession?.idPartida ?? _savedGameId;
    final idPartida = currentIdPartida == null || currentIdPartida.isEmpty
        ? _generateGameId()
        : currentIdPartida;
    final idUsuario = _userInformation?.idUsuario ?? '';

    if (idUsuario.isEmpty) {
      setState(() {
        _creationError = 'No se pudo identificar el usuario para reservar.';
        _userRegistrationError = null;
      });
      return;
    }

    setState(() {
      _creationError = null;
      _userRegistrationError = null;
    });

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ReservationDayScreen(
          datosServidorService: _datosServidorService,
          fieldId: _savedFieldId,
          idPartida: idPartida,
          idUsuario: idUsuario,
        ),
      ),
    );
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

    final userInformation = _userInformation;
    final shouldShowUserInformation =
        !_isLoading &&
        (_isEditingUserInformation ||
            (userInformation == null && !_isUserInformationDismissed));
    if (shouldShowUserInformation) {
      return _UserInformationScreen(
        initialInformation: userInformation,
        datosServidorService: _datosServidorService,
        onSave: _saveUserInformation,
        onCancel: _cancelUserInformationEditing,
      );
    }

    final playerAlias = userInformation?.alias ?? 'Sin registrar';
    final canUseGameActions = userInformation != null && _isUserRegistered;

    return Scaffold(
      backgroundColor: const Color(0xFF0B241A),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF235C3D), Color(0xFF03110C)],
          ),
        ),
        child: SizedBox.expand(
          child: SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF6F2EA)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
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
                              const _GolfLogo(size: 112),
                              const SizedBox(height: 18),
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
                                    ? 'Jugador: $playerAlias\n '
                                    : 'Jugador: $playerAlias\nPartida guardada: $_savedGameId\nCampo: $_savedFieldId · Jugadores: $_savedPlayers',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF6C737D),
                                ),
                              ),
                              if (_userRegistrationError != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _userRegistrationError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF9D433D),
                                  ),
                                ),
                              ],
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
                              FilledButton.icon(
                                onPressed:
                                    _savedGameId == null || !canUseGameActions
                                    ? null
                                    : _recoverGame,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF567B37),
                                  disabledBackgroundColor: const Color(
                                    0xFFBBC5B0,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                icon: const Icon(Icons.restore),
                                label: const Text('Recuperar partida'),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _isCreatingGame || !canUseGameActions
                                    ? null
                                    : _startNewGame,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B432D),
                                  side: const BorderSide(
                                    color: Color(0xFF6B432D),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(
                                  _isCreatingGame
                                      ? 'Creando partida...'
                                      : 'Iniciar nueva partida',
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: canUseGameActions
                                    ? _openReservationDaySelection
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF567B37),
                                  side: const BorderSide(
                                    color: Color(0xFF567B37),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                icon: const Icon(Icons.event_available),
                                label: const Text('Reservar Partida'),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed:
                                    canUseGameActions &&
                                        _createdGames.isNotEmpty
                                    ? () {}
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF567B37),
                                  disabledForegroundColor: const Color(
                                    0xFF9AA092,
                                  ),
                                  side: BorderSide(
                                    color:
                                        canUseGameActions &&
                                            _createdGames.isNotEmpty
                                        ? const Color(0xFF567B37)
                                        : const Color(0xFFD8D2C7),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                icon: const Icon(Icons.event_note),
                                label: const Text('Partidas Pendientes'),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _editUserInformation,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF545B66),
                                  side: const BorderSide(
                                    color: Color(0xFF9AA092),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                icon: const Icon(Icons.person),
                                label: const Text('Mi Informacion'),
                              ),
                            ],
                          ),
                        ),
                      ),
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

const _userInformationFields = [
  _UserInformationField(key: 'alias', label: 'Alias', isRequired: true),
  _UserInformationField(key: 'nombre', label: 'Nombre', isRequired: true),
  _UserInformationField(key: 'apellidos', label: 'Apellidos', isRequired: true),
  _UserInformationField(key: 'direccion', label: 'Direccion'),
  _UserInformationField(
    key: 'cp',
    label: 'CP',
    keyboardType: TextInputType.number,
  ),
  _UserInformationField(key: 'poblacion', label: 'Poblacion'),
  _UserInformationField(key: 'provincia', label: 'Provincia'),
  _UserInformationField(
    key: 'telefono',
    label: 'Movil',
    keyboardType: TextInputType.phone,
    isRequired: true,
  ),
  _UserInformationField(
    key: 'mail',
    label: 'Mail',
    keyboardType: TextInputType.emailAddress,
    isRequired: true,
  ),
  _UserInformationField(
    key: 'numeroFederadoGolf',
    label: 'Numero Federado Golf',
    keyboardType: TextInputType.number,
  ),
];

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _digitsOnlyPattern = RegExp(r'^\d+$');
const _backendUniqueFieldKeys = {'alias', 'telefono', 'mail'};
const _logoGolfAsset = 'assets/images/logo-golf-transparent.png';
final _rptaPattern = RegExp(
  r'''['"]rpta['"]\s*:\s*['"]([^'"]+)['"]''',
  caseSensitive: false,
);

class _UserInformationField {
  const _UserInformationField({
    required this.key,
    required this.label,
    this.keyboardType = TextInputType.text,
    this.isRequired = false,
  });

  final String key;
  final String label;
  final TextInputType keyboardType;
  final bool isRequired;
}

class _GolfLogo extends StatelessWidget {
  const _GolfLogo({this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        _logoGolfAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Logo golf',
      ),
    );
  }
}

class _ReservationScreenFrame extends StatelessWidget {
  const _ReservationScreenFrame({
    required this.title,
    required this.children,
    this.maxWidth = 520,
  });

  final String title;
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B241A),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF235C3D), Color(0xFF03110C)],
          ),
        ),
        child: SizedBox.expand(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GolfLogo(size: 96),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF545B66),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReservationDayScreen extends StatefulWidget {
  const _ReservationDayScreen({
    required this.datosServidorService,
    required this.fieldId,
    required this.idPartida,
    required this.idUsuario,
  });

  final DatosServidorService datosServidorService;
  final String fieldId;
  final String idPartida;
  final String idUsuario;

  @override
  State<_ReservationDayScreen> createState() => _ReservationDayScreenState();
}

class _ReservationDayScreenState extends State<_ReservationDayScreen> {
  late final DateTime _today;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    _visibleMonth = DateTime(_today.year, _today.month);
  }

  bool get _canGoToPreviousMonth {
    final firstVisibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final currentMonth = DateTime(_today.year, _today.month);
    return firstVisibleMonth.isAfter(currentMonth);
  }

  void _goToPreviousMonth() {
    if (!_canGoToPreviousMonth) {
      return;
    }

    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  void _selectDay(DateTime day) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ReservationTimeScreen(
          selectedDay: day,
          agendaDay: _formatAgendaDay(day),
          datosServidorService: widget.datosServidorService,
          fieldId: widget.fieldId,
          idPartida: widget.idPartida,
          idUsuario: widget.idUsuario,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Selecciona el día',
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _canGoToPreviousMonth ? _goToPreviousMonth : null,
              tooltip: 'Mes anterior',
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _monthLabel(_visibleMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF545B66),
                ),
              ),
            ),
            IconButton(
              onPressed: _goToNextMonth,
              tooltip: 'Mes siguiente',
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ReservationMonthCalendar(
          visibleMonth: _visibleMonth,
          today: _today,
          onDaySelected: _selectDay,
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6B432D),
            side: const BorderSide(color: Color(0xFF6B432D)),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver'),
        ),
      ],
    );
  }
}

class _ReservationMonthCalendar extends StatelessWidget {
  const _ReservationMonthCalendar({
    required this.visibleMonth,
    required this.today,
    required this.onDaySelected,
  });

  final DateTime visibleMonth;
  final DateTime today;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    const weekDays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    final daysInMonth = DateUtils.getDaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final leadingEmptyDays = firstDay.weekday - DateTime.monday;
    final itemCount = leadingEmptyDays + daysInMonth;

    return Column(
      children: [
        Row(
          children: [
            for (final dayName in weekDays)
              Expanded(
                child: Center(
                  child: Text(
                    dayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6C737D),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.05,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < leadingEmptyDays) {
              return const SizedBox.shrink();
            }

            final dayNumber = index - leadingEmptyDays + 1;
            final day = DateTime(
              visibleMonth.year,
              visibleMonth.month,
              dayNumber,
            );
            final isPast = day.isBefore(today);
            final isToday = _isSameDay(day, today);

            return TextButton(
              key: ValueKey('reservation_day_${_formatAgendaDay(day)}'),
              onPressed: isPast ? null : () => onDaySelected(day),
              style: TextButton.styleFrom(
                foregroundColor: isPast
                    ? const Color(0xFFB7B1A8)
                    : const Color(0xFF235C3D),
                disabledForegroundColor: const Color(0xFFB7B1A8),
                backgroundColor: isToday
                    ? const Color(0xFFE6EFE0)
                    : Colors.transparent,
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isToday
                        ? const Color(0xFF567B37)
                        : const Color(0xFFD8D2C7),
                  ),
                ),
              ),
              child: Text(
                '$dayNumber',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ReservationTimeScreen extends StatefulWidget {
  const _ReservationTimeScreen({
    required this.selectedDay,
    required this.agendaDay,
    required this.datosServidorService,
    required this.fieldId,
    required this.idPartida,
    required this.idUsuario,
  });

  final DateTime selectedDay;
  final String agendaDay;
  final DatosServidorService datosServidorService;
  final String fieldId;
  final String idPartida;
  final String idUsuario;

  @override
  State<_ReservationTimeScreen> createState() => _ReservationTimeScreenState();
}

class _ReservationTimeScreenState extends State<_ReservationTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _timeController = TextEditingController();
  List<_AgendaSlot> _occupiedSlots = const [];
  bool _isLoadingAgenda = true;
  int? _agendaLapsusMinutes;
  int? _agendaStartMinutes;
  int? _agendaEndMinutes;
  String? _agendaError;
  String? _timeAdjustmentError;
  String? _timeStatusMessage;
  String? _reservationError;
  bool _isReserving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAgenda());
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _loadAgenda() async {
    setState(() {
      _isLoadingAgenda = true;
      _agendaLapsusMinutes = null;
      _agendaStartMinutes = null;
      _agendaEndMinutes = null;
      _agendaError = null;
      _timeAdjustmentError = null;
      _timeStatusMessage = null;
      _reservationError = null;
    });

    try {
      final responses = await Future.wait([
        widget.datosServidorService.obtenerAgenda(widget.agendaDay),
        widget.datosServidorService.cojeConfiguracionCampos(
          widget.fieldId,
          'lapsus_agenda',
        ),
        widget.datosServidorService.cojeConfiguracionCampos(
          widget.fieldId,
          'agenda_desde',
        ),
        widget.datosServidorService.cojeConfiguracionCampos(
          widget.fieldId,
          'agenda_hasta',
        ),
      ]);
      final response = responses[0];
      final agendaLapsusMinutes = _parsePositiveMinutes(responses[1]);
      if (agendaLapsusMinutes == null) {
        throw FormatException('lapsus_agenda no valido: ${responses[1]}');
      }
      final agendaStartMinutes = _parseConfiguredTime(responses[2]);
      final agendaEndMinutes = _parseConfiguredTime(responses[3]);
      if (agendaStartMinutes == null ||
          agendaEndMinutes == null ||
          agendaStartMinutes >= agendaEndMinutes) {
        throw FormatException(
          'rango de agenda no valido: ${responses[2]} - ${responses[3]}',
        );
      }

      final slots = _agendaSlotsFromResponse(response).toList()
        ..sort((left, right) => left.desde.compareTo(right.desde));

      if (!mounted) {
        return;
      }

      setState(() {
        _occupiedSlots = slots;
        _agendaLapsusMinutes = agendaLapsusMinutes;
        _agendaStartMinutes = agendaStartMinutes;
        _agendaEndMinutes = agendaEndMinutes;
        _isLoadingAgenda = false;
      });
    } catch (error) {
      debugPrint('cargar agenda ${widget.agendaDay} fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingAgenda = false;
        _agendaLapsusMinutes = null;
        _agendaStartMinutes = null;
        _agendaEndMinutes = null;
        _agendaError = 'No se pudo cargar la agenda.';
      });
    }
  }

  void _checkTime() {
    final currentMinutes = _parseTimeInput(_timeController.text);
    String? adjustmentError;

    if (!_isLoadingAgenda && _agendaError == null && currentMinutes != null) {
      final adjustedMinutes = _nearestAvailableRoundedMinute(currentMinutes);
      if (adjustedMinutes == null) {
        adjustmentError = 'No hay una hora libre cercana';
      } else {
        _setTimeControllerMinutes(adjustedMinutes);
      }
    }

    setState(() {
      _timeAdjustmentError = adjustmentError;
      _timeStatusMessage = null;
    });

    final isAvailable = _formKey.currentState?.validate() ?? false;
    setState(() {
      _timeStatusMessage = isAvailable ? 'Hora disponible' : null;
      _reservationError = null;
    });
  }

  bool get _canReserve => _timeStatusMessage == 'Hora disponible';

  Future<void> _reserveTime() async {
    final isAvailable = _formKey.currentState?.validate() ?? false;
    final startMinutes = _parseTimeInput(_timeController.text);
    final agendaLapsusMinutes = _agendaLapsusMinutes;
    if (!isAvailable || startMinutes == null || agendaLapsusMinutes == null) {
      setState(() {
        _timeStatusMessage = null;
        _reservationError = null;
      });
      return;
    }

    final endMinutes = startMinutes + agendaLapsusMinutes;
    final desde = _formatCompactMinuteOfDay(startMinutes);
    final hasta = _formatCompactMinuteOfDay(endMinutes);

    setState(() {
      _isReserving = true;
      _reservationError = null;
    });

    try {
      final response = await widget.datosServidorService.insertarAgenda(
        dia: widget.agendaDay,
        desde: desde,
        hasta: hasta,
        idPartida: widget.idPartida,
        idUsuarioCreador: widget.idUsuario,
      );

      if (!_backendResponseIsOk(response)) {
        throw FormatException('Respuesta no valida: $response');
      }

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _ReservationSuccessScreen(
            selectedDay: widget.selectedDay,
            desde: desde,
            hasta: hasta,
          ),
        ),
      );
    } catch (error) {
      debugPrint('insertar agenda ${widget.agendaDay} fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _reservationError = 'No se pudo efectuar la reserva.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isReserving = false;
        });
      }
    }
  }

  String? _validateTime(String? rawValue) {
    if (_isLoadingAgenda) {
      return 'Agenda cargando';
    }

    if (_agendaError != null) {
      return 'Agenda no disponible';
    }

    final agendaLapsusMinutes = _agendaLapsusMinutes;
    if (agendaLapsusMinutes == null ||
        _agendaStartMinutes == null ||
        _agendaEndMinutes == null) {
      return 'Agenda no disponible';
    }

    if (_timeAdjustmentError != null) {
      return _timeAdjustmentError;
    }

    final minutes = _parseTimeInput(rawValue);
    if (minutes == null) {
      return 'Introduce una hora valida (HH:mm o HHmm)';
    }

    final endMinutes = minutes + agendaLapsusMinutes;
    if (!_rangeIsInsideAgenda(minutes, endMinutes)) {
      return 'Hora fuera de horario';
    }

    final occupiedSlot = _occupiedSlotForRange(minutes, endMinutes);
    if (occupiedSlot != null) {
      return 'Hora ocupada (${occupiedSlot.formattedRange})';
    }

    return null;
  }

  int? _nearestAvailableRoundedMinute(int inputMinutes) {
    final agendaLapsusMinutes = _agendaLapsusMinutes;
    final agendaStartMinutes = _agendaStartMinutes;
    final agendaEndMinutes = _agendaEndMinutes;
    if (agendaLapsusMinutes == null ||
        agendaStartMinutes == null ||
        agendaEndMinutes == null) {
      return null;
    }

    final candidates = <int>[];
    for (
      var candidate = agendaStartMinutes;
      candidate + agendaLapsusMinutes <= agendaEndMinutes;
      candidate += agendaLapsusMinutes
    ) {
      candidates.add(candidate);
    }

    candidates.sort((left, right) {
      final leftDistance = (left - inputMinutes).abs();
      final rightDistance = (right - inputMinutes).abs();
      if (leftDistance != rightDistance) {
        return leftDistance.compareTo(rightDistance);
      }

      return right.compareTo(left);
    });

    for (final candidate in candidates) {
      final candidateEnd = candidate + agendaLapsusMinutes;
      if (_occupiedSlotForRange(candidate, candidateEnd) != null) {
        continue;
      }

      return candidate;
    }

    return null;
  }

  void _setTimeControllerMinutes(int minutes) {
    final text = _formatMinuteOfDay(minutes);
    _timeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  bool _rangeIsInsideAgenda(int startMinutes, int endMinutes) {
    final agendaStartMinutes = _agendaStartMinutes;
    final agendaEndMinutes = _agendaEndMinutes;
    if (agendaStartMinutes == null || agendaEndMinutes == null) {
      return false;
    }

    return startMinutes >= agendaStartMinutes && endMinutes <= agendaEndMinutes;
  }

  _AgendaSlot? _occupiedSlotForRange(int startMinutes, int endMinutes) {
    for (final slot in _occupiedSlots) {
      if (slot.intersectsRange(startMinutes, endMinutes)) {
        return slot;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Reservar Partida',
      maxWidth: 620,
      children: [
        Text(
          _formatDisplayDate(widget.selectedDay),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Color(0xFF6C737D)),
        ),
        const SizedBox(height: 22),
        if (_isLoadingAgenda)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: CircularProgressIndicator(color: Color(0xFF567B37)),
            ),
          )
        else if (_agendaError != null) ...[
          Text(
            _agendaError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadAgenda,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF567B37),
              side: const BorderSide(color: Color(0xFF567B37)),
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ] else ...[
          const Text(
            'Disponibilidad',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF545B66),
            ),
          ),
          const SizedBox(height: 12),
          _AgendaAvailabilityBand(
            startMinutes: _agendaStartMinutes!,
            endMinutes: _agendaEndMinutes!,
            occupiedSlots: _occupiedSlots,
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _timeController,
              keyboardType: TextInputType.number,
              inputFormatters: const [_ReservationTimeInputFormatter()],
              onChanged: (_) {
                if (_timeStatusMessage == null &&
                    _timeAdjustmentError == null &&
                    _reservationError == null) {
                  return;
                }

                setState(() {
                  _timeAdjustmentError = null;
                  _timeStatusMessage = null;
                  _reservationError = null;
                });
              },
              validator: _validateTime,
              decoration: InputDecoration(
                labelText: 'Hora',
                filled: true,
                fillColor: const Color.fromRGBO(255, 255, 255, 0.72),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF567B37),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          if (_timeStatusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _timeStatusMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF567B37)),
            ),
          ],
          if (_reservationError != null) ...[
            const SizedBox(height: 12),
            Text(
              _reservationError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _isReserving
                ? null
                : _canReserve
                ? _reserveTime
                : _checkTime,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF567B37),
              disabledBackgroundColor: const Color(0xFFBBC5B0),
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: _isReserving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(_canReserve ? Icons.event_available : Icons.check),
            label: Text(
              _isReserving
                  ? 'Reservando...'
                  : _canReserve
                  ? 'Reservar'
                  : 'Comprobar ahora',
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6B432D),
            side: const BorderSide(color: Color(0xFF6B432D)),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver'),
        ),
      ],
    );
  }
}

class _AgendaAvailabilityBand extends StatelessWidget {
  const _AgendaAvailabilityBand({
    required this.startMinutes,
    required this.endMinutes,
    required this.occupiedSlots,
  });

  static const _freeColor = Color(0xFF6FA34B);
  static const _occupiedColor = Color(0xFFC9554E);

  final int startMinutes;
  final int endMinutes;
  final List<_AgendaSlot> occupiedSlots;

  @override
  Widget build(BuildContext context) {
    final segments = _agendaBandSegments(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      occupiedSlots: occupiedSlots,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatMinuteOfDay(startMinutes),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6C737D)),
            ),
            Text(
              _formatMinuteOfDay(endMinutes),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6C737D)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8D2C7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final segment in segments)
                Expanded(
                  flex: segment.durationMinutes,
                  child: segment.isOccupied
                      ? _bandSegmentBox(segment)
                      : Tooltip(
                          message:
                              'libre de ${_formatMinuteOfDay(segment.startMinutes)} '
                              'a ${_formatMinuteOfDay(segment.endMinutes)}',
                          triggerMode: TooltipTriggerMode.tap,
                          waitDuration: const Duration(milliseconds: 350),
                          showDuration: const Duration(seconds: 3),
                          child: _bandSegmentBox(segment),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(_freeColor, 'Libre'),
            const SizedBox(width: 16),
            _legendItem(_occupiedColor, 'Ocupado'),
          ],
        ),
      ],
    );
  }

  Widget _bandSegmentBox(_AgendaBandSegment segment) {
    return DecoratedBox(
      key: ValueKey(segment.key),
      decoration: BoxDecoration(
        color: segment.isOccupied ? _occupiedColor : _freeColor,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6C737D)),
        ),
      ],
    );
  }
}

class _AgendaBandSegment {
  const _AgendaBandSegment({
    required this.startMinutes,
    required this.endMinutes,
    required this.isOccupied,
  });

  final int startMinutes;
  final int endMinutes;
  final bool isOccupied;

  int get durationMinutes => endMinutes - startMinutes;

  String get key {
    final kind = isOccupied ? 'occupied' : 'free';
    return 'agenda_band_${kind}_${_formatCompactMinuteOfDay(startMinutes)}'
        '_${_formatCompactMinuteOfDay(endMinutes)}';
  }
}

class _ReservationSuccessScreen extends StatelessWidget {
  const _ReservationSuccessScreen({
    required this.selectedDay,
    required this.desde,
    required this.hasta,
  });

  final DateTime selectedDay;
  final String desde;
  final String hasta;

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Reserva efectuada',
      children: [
        const Icon(Icons.event_available, color: Color(0xFF567B37), size: 56),
        const SizedBox(height: 12),
        Text(
          '${_formatDisplayDate(selectedDay)}\n${_formatCompactTime(desde)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF545B66),
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF567B37),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.check),
          label: const Text('Entendido'),
        ),
      ],
    );
  }
}

class _UserInformationScreen extends StatefulWidget {
  const _UserInformationScreen({
    required this.initialInformation,
    required this.datosServidorService,
    required this.onSave,
    this.onCancel,
  });

  final _UserInformation? initialInformation;
  final DatosServidorService datosServidorService;
  final Future<void> Function(
    _UserInformation information, {
    required bool isRegistered,
    String idUsuario,
  })
  onSave;
  final VoidCallback? onCancel;

  @override
  State<_UserInformationScreen> createState() => _UserInformationScreenState();
}

class _UserInformationScreenState extends State<_UserInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverValidationErrors = <String, String>{};
  late final Map<String, GlobalKey<FormFieldState<String>>> _fieldKeys;
  late final Map<String, FocusNode> _focusNodes;
  late final Map<String, TextEditingController> _controllers;
  bool _isSaving = false;
  String? _serverValidationError;

  @override
  void initState() {
    super.initState();
    _fieldKeys = {
      for (final field in _userInformationFields)
        field.key: GlobalKey<FormFieldState<String>>(),
    };
    _focusNodes = {
      for (final field in _userInformationFields) field.key: FocusNode(),
    };
    _controllers = {
      for (final field in _userInformationFields)
        field.key: TextEditingController(
          text: widget.initialInformation?.valueFor(field.key) ?? '',
        ),
    };

    for (final fieldKey in _backendUniqueFieldKeys) {
      _focusNodes[fieldKey]?.addListener(() {
        if (_focusNodes[fieldKey]?.hasFocus ?? true) {
          return;
        }

        unawaited(_validateBackendFieldOnBlur(fieldKey));
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _serverValidationErrors.clear();
      _serverValidationError = null;
    });

    final hasLocalErrors = !_formKey.currentState!.validate();
    final information = _currentInformation;
    final backendFieldsToValidate = _backendFieldsWithoutLocalErrors();

    if (backendFieldsToValidate.isEmpty) {
      if (hasLocalErrors) {
        _scrollToFirstInvalidField();
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    Map<String, String> backendErrors;
    try {
      backendErrors = await _validateUniqueBackendFields(
        information,
        backendFieldsToValidate,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _serverValidationError =
            'No se pudo validar Alias, Mail y Movil en el servidor.';
        _isSaving = false;
      });
      _showServerValidationSnackBar(_serverValidationError!);
      return;
    }

    if (!mounted) {
      return;
    }

    if (hasLocalErrors || backendErrors.isNotEmpty) {
      final message = backendErrors.values.join('\n');
      setState(() {
        _serverValidationErrors.addAll(backendErrors);
        _serverValidationError = message.isEmpty ? null : message;
        _isSaving = false;
      });
      _formKey.currentState!.validate();
      if (message.isNotEmpty) {
        _showServerValidationSnackBar(message);
      }
      _scrollToFirstInvalidField();
      return;
    }

    final registration = await _registerUserInBackend(information);
    await widget.onSave(
      information,
      isRegistered: registration.isRegistered,
      idUsuario: registration.idUsuario,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });
  }

  _UserInformation get _currentInformation {
    return _UserInformation(
      alias: _text('alias'),
      nombre: _text('nombre'),
      apellidos: _text('apellidos'),
      direccion: _text('direccion'),
      cp: _text('cp'),
      poblacion: _text('poblacion'),
      provincia: _text('provincia'),
      telefono: _text('telefono'),
      mail: _text('mail'),
      numeroFederadoGolf: _text('numeroFederadoGolf'),
    );
  }

  String _text(String key) => _controllers[key]!.text.trim();

  void _clearServerValidationError(String key) {
    final hadFieldError = _serverValidationErrors.containsKey(key);
    if (!_serverValidationErrors.containsKey(key) &&
        _serverValidationError == null) {
      return;
    }

    setState(() {
      _serverValidationErrors.remove(key);
      _serverValidationError = _serverValidationSummary();
    });

    if (hadFieldError) {
      _fieldKeys[key]?.currentState?.validate();
    }
  }

  Set<String> _backendFieldsWithoutLocalErrors() {
    return {
      for (final field in _userInformationFields)
        if (_backendUniqueFieldKeys.contains(field.key) &&
            _localValidationError(field, _controllers[field.key]?.text) == null)
          field.key,
    };
  }

  Future<void> _validateBackendFieldOnBlur(String key) async {
    if (!_backendUniqueFieldKeys.contains(key) || _isSaving) {
      return;
    }

    final field = _fieldForKey(key);
    final initialText = _text(key);
    final fieldState = _fieldKeys[key]?.currentState;

    if (_localValidationError(field, initialText) != null) {
      fieldState?.validate();
      return;
    }

    try {
      final backendErrors = await _validateUniqueBackendFields(
        _currentInformation,
        {key},
      );
      if (!mounted || _text(key) != initialText) {
        return;
      }

      setState(() {
        final error = backendErrors[key];
        if (error == null) {
          _serverValidationErrors.remove(key);
        } else {
          _serverValidationErrors[key] = error;
        }
        _serverValidationError = _serverValidationSummary();
      });
      _fieldKeys[key]?.currentState?.validate();
    } catch (error) {
      debugPrint('No se pudo validar $key al perder foco: $error');
    }
  }

  _UserInformationField _fieldForKey(String key) {
    return _userInformationFields.firstWhere((field) => field.key == key);
  }

  String? _serverValidationSummary() {
    return _serverValidationErrors.isEmpty
        ? null
        : _serverValidationErrors.values.join('\n');
  }

  Future<Map<String, String>> _validateUniqueBackendFields(
    _UserInformation information,
    Set<String> fieldKeys,
  ) async {
    final errors = <String, String>{};
    final checks = <Future<void>>[];

    if (fieldKeys.contains('alias')) {
      checks.add(() async {
        final response = await widget.datosServidorService.yaExisteAlias(
          information.alias,
        );
        final exists = _backendResponseSaysYes(response);
        debugPrint('yaExisteAlias(${information.alias}): $response');
        if (exists) {
          errors['alias'] = 'Alias ya existe';
        }
      }());
    }

    if (fieldKeys.contains('telefono')) {
      checks.add(() async {
        final response = await widget.datosServidorService.yaExisteMovil(
          information.telefono,
        );
        final exists = _backendResponseSaysYes(response);
        debugPrint('yaExisteMovil(${information.telefono}): $response');
        if (exists) {
          errors['telefono'] = 'Movil ya existe';
        }
      }());
    }

    if (fieldKeys.contains('mail')) {
      checks.add(() async {
        final response = await widget.datosServidorService.yaExisteMail(
          information.mail,
        );
        final exists = _backendResponseSaysYes(response);
        debugPrint('yaExisteMail(${information.mail}): $response');
        if (exists) {
          errors['mail'] = 'Mail ya existe';
        }
      }());
    }

    await Future.wait(checks);
    return errors;
  }

  Future<_UserRegistrationResult> _registerUserInBackend(
    _UserInformation information,
  ) async {
    try {
      final response = await widget.datosServidorService.altaUsuario(
        information.alias,
        information.nombre,
        information.apellidos,
        information.direccion,
        information.cp,
        information.poblacion,
        information.provincia,
        information.telefono,
        information.mail,
        information.numeroFederadoGolf,
      );
      final registration = _userRegistrationResultFromBackend(response);
      debugPrint('altaUsuario(${information.alias}): $response');
      return registration;
    } catch (error) {
      debugPrint('altaUsuario(${information.alias}) fallo: $error');
      return const _UserRegistrationResult(isRegistered: false);
    }
  }

  void _showServerValidationSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToFirstInvalidField([Iterable<String>? candidateKeys]) {
    final keys =
        candidateKeys ?? _userInformationFields.map((field) => field.key);
    String? firstInvalidKey;

    for (final key in keys) {
      final field = _userInformationFields.firstWhere(
        (field) => field.key == key,
      );
      if (_validateField(field, _controllers[key]?.text) != null) {
        firstInvalidKey = key;
        break;
      }
    }

    if (firstInvalidKey == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final fieldContext = _fieldKeys[firstInvalidKey]?.currentContext;
      if (fieldContext == null) {
        return;
      }

      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.12,
      );
    });
  }

  String? _validateField(_UserInformationField field, String? value) {
    final serverError = _serverValidationErrors[field.key];
    if (serverError != null) {
      return serverError;
    }

    return _localValidationError(field, value);
  }

  String? _localValidationError(_UserInformationField field, String? value) {
    final text = value?.trim() ?? '';

    if (field.isRequired && text.isEmpty) {
      return 'Campo obligatorio';
    }

    if (field.key == 'telefono' &&
        text.isNotEmpty &&
        !_digitsOnlyPattern.hasMatch(text)) {
      return 'Movil no valido';
    }

    if (field.key == 'telefono' && text.isNotEmpty && text.length < 6) {
      return 'Movil debe tener al menos 6 digitos';
    }

    if (field.key == 'mail' &&
        text.isNotEmpty &&
        !_emailPattern.hasMatch(text)) {
      return 'Mail no valido';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialInformation != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B241A),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF235C3D), Color(0xFF03110C)],
          ),
        ),
        child: SizedBox.expand(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _GolfLogo(size: 104),
                          const SizedBox(height: 16),
                          Text(
                            isEditing ? 'Mi Informacion' : 'Alta de usuario',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF545B66),
                            ),
                          ),
                          const SizedBox(height: 24),
                          for (final field in _userInformationFields) ...[
                            TextFormField(
                              key: _fieldKeys[field.key],
                              controller: _controllers[field.key],
                              focusNode: _focusNodes[field.key],
                              keyboardType: field.keyboardType,
                              inputFormatters: field.key == 'telefono'
                                  ? [FilteringTextInputFormatter.digitsOnly]
                                  : null,
                              onChanged: (_) =>
                                  _clearServerValidationError(field.key),
                              textInputAction:
                                  field == _userInformationFields.last
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              enabled: !_isSaving,
                              validator: (value) =>
                                  _validateField(field, value),
                              decoration: InputDecoration(
                                labelText: field.label,
                                filled: true,
                                fillColor: const Color.fromRGBO(
                                  255,
                                  255,
                                  255,
                                  0.72,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD8D2C7),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF567B37),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          const SizedBox(height: 10),
                          if (_serverValidationError != null) ...[
                            Text(
                              _serverValidationError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF9D433D),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: _isSaving ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF567B37),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            icon: const Icon(Icons.save),
                            label: Text(
                              _isSaving
                                  ? 'Guardando...'
                                  : 'Guardar informacion',
                            ),
                          ),
                          if (widget.onCancel != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _isSaving ? null : widget.onCancel,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF6B432D),
                                side: const BorderSide(
                                  color: Color(0xFF6B432D),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                              ),
                              icon: const Icon(Icons.close),
                              label: const Text('Cancelar'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserInformation {
  const _UserInformation({
    this.idUsuario = '',
    required this.alias,
    required this.nombre,
    required this.apellidos,
    required this.direccion,
    required this.cp,
    required this.poblacion,
    required this.provincia,
    required this.telefono,
    required this.mail,
    required this.numeroFederadoGolf,
  });

  final String idUsuario;
  final String alias;
  final String nombre;
  final String apellidos;
  final String direccion;
  final String cp;
  final String poblacion;
  final String provincia;
  final String telefono;
  final String mail;
  final String numeroFederadoGolf;

  static _UserInformation? fromJsonString(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return null;
      }

      final map = _stringKeyedMap(decoded);
      return _fromMap(map);
    } catch (_) {
      return null;
    }
  }

  static _UserInformation? _fromMap(Map<String, dynamic> map) {
    final information = _UserInformation(
      idUsuario: _requiredValue(map, 'idUsuario'),
      alias: _requiredValue(map, 'alias'),
      nombre: _requiredValue(map, 'nombre'),
      apellidos: _requiredValue(map, 'apellidos'),
      direccion: _requiredValue(map, 'direccion'),
      cp: _requiredValue(map, 'cp'),
      poblacion: _requiredValue(map, 'poblacion'),
      provincia: _requiredValue(map, 'provincia'),
      telefono: _requiredValue(map, 'telefono'),
      mail: _requiredValue(map, 'mail'),
      numeroFederadoGolf: _requiredValue(map, 'numeroFederadoGolf'),
    );

    return information.hasRequiredValues ? information : null;
  }

  static String _requiredValue(Map<String, dynamic> map, String key) {
    return '${map[key] ?? ''}'.trim();
  }

  bool get hasRequiredValues {
    return _userInformationFields
        .where((field) => field.isRequired)
        .every((field) => valueFor(field.key).isNotEmpty);
  }

  String valueFor(String key) {
    return switch (key) {
      'alias' => alias,
      'idUsuario' => idUsuario,
      'nombre' => nombre,
      'apellidos' => apellidos,
      'direccion' => direccion,
      'cp' => cp,
      'poblacion' => poblacion,
      'provincia' => provincia,
      'telefono' => telefono,
      'mail' => mail,
      'numeroFederadoGolf' => numeroFederadoGolf,
      _ => '',
    };
  }

  String toJsonString() => jsonEncode(toJson());

  Map<String, String> toJson() {
    return {
      'idUsuario': idUsuario,
      'alias': alias,
      'nombre': nombre,
      'apellidos': apellidos,
      'direccion': direccion,
      'cp': cp,
      'poblacion': poblacion,
      'provincia': provincia,
      'telefono': telefono,
      'mail': mail,
      'numeroFederadoGolf': numeroFederadoGolf,
    };
  }

  _UserInformation copyWith({String? idUsuario}) {
    return _UserInformation(
      idUsuario: idUsuario ?? this.idUsuario,
      alias: alias,
      nombre: nombre,
      apellidos: apellidos,
      direccion: direccion,
      cp: cp,
      poblacion: poblacion,
      provincia: provincia,
      telefono: telefono,
      mail: mail,
      numeroFederadoGolf: numeroFederadoGolf,
    );
  }
}

bool _backendResponseSaysYes(String response) {
  final rpta = _backendResponseValue(response);
  if (rpta == null) {
    throw FormatException('Respuesta no valida: $response');
  }

  return rpta == 'si' || rpta == 'sí';
}

bool _backendResponseIsOk(String response) {
  return _backendResponseValue(response) == 'ok';
}

_UserRegistrationResult _userRegistrationResultFromBackend(String response) {
  final rpta = _backendResponseValue(response);
  if (rpta != 'ok') {
    return const _UserRegistrationResult(isRegistered: false);
  }

  return _UserRegistrationResult(
    isRegistered: true,
    idUsuario: _backendResponseField(response, 'idUsuario') ?? '',
  );
}

class _UserRegistrationResult {
  const _UserRegistrationResult({
    required this.isRegistered,
    this.idUsuario = '',
  });

  final bool isRegistered;
  final String idUsuario;
}

String? _backendResponseValue(String response) {
  final trimmedResponse = response.trim();
  if (trimmedResponse.isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(trimmedResponse);
    if (decoded is Map) {
      final value = decoded['rpta'];
      if (value != null) {
        return '$value'.trim().toLowerCase();
      }
    }
  } catch (_) {
    // El backend historicamente devuelve algunas respuestas con comillas simples.
  }

  final lowerResponse = trimmedResponse.toLowerCase();
  if (lowerResponse == 'si' ||
      lowerResponse == 'sí' ||
      lowerResponse == 'no' ||
      lowerResponse == 'ok') {
    return lowerResponse;
  }

  return _rptaPattern
      .firstMatch(trimmedResponse)
      ?.group(1)
      ?.trim()
      .toLowerCase();
}

String? _backendResponseField(String response, String key) {
  final trimmedResponse = response.trim();
  if (trimmedResponse.isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(trimmedResponse);
    if (decoded is Map) {
      final value = decoded[key];
      if (value != null) {
        return '$value'.trim();
      }
    }
  } catch (_) {
    // El backend historicamente devuelve algunas respuestas con comillas simples.
  }

  return RegExp(
    '''['"]${RegExp.escape(key)}['"]\\s*:\\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  ).firstMatch(trimmedResponse)?.group(1)?.trim();
}

class _ReservationTimeInputFormatter extends TextInputFormatter {
  const _ReservationTimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length <= 4 ? digits : digits.substring(0, 4);
    final formatted = _formatTimeInputDigits(limitedDigits);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _formatTimeInputDigits(String digits) {
  if (digits.length <= 2) {
    return digits;
  }

  final hourDigits = digits.substring(0, digits.length - 2);
  final minuteDigits = digits.substring(digits.length - 2);
  return '$hourDigits:$minuteDigits';
}

const _spanishMonthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _monthLabel(DateTime day) {
  return '${_spanishMonthNames[day.month - 1]} ${day.year}';
}

String _formatAgendaDay(DateTime day) {
  return '${_twoDigits(day.year % 100)}'
      '${_twoDigits(day.month)}'
      '${_twoDigits(day.day)}';
}

String _formatDisplayDate(DateTime day) {
  return '${_twoDigits(day.day)}/${_twoDigits(day.month)}/${day.year}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

List<_AgendaSlot> _agendaSlotsFromResponse(String response) {
  final rows = _decodeAgendaRows(response, 0) ?? const [];
  return [for (final row in rows) ?_AgendaSlot.fromMap(row)];
}

List<_CreatedGameInfo> _createdGamesFromResponse(String response) {
  final rows = _decodeMapRows(response, 0) ?? const [];
  return [for (final row in rows) ?_CreatedGameInfo.fromMap(row)];
}

List<Map<String, dynamic>>? _decodeAgendaRows(Object? payload, int depth) {
  return _decodeMapRows(payload, depth);
}

List<Map<String, dynamic>>? _decodeMapRows(Object? payload, int depth) {
  if (depth > 4) {
    return null;
  }

  if (payload is String) {
    final trimmedPayload = payload.trim();
    if (trimmedPayload.isEmpty) {
      return const [];
    }

    final decoded = _decodeJsonLikePayload(trimmedPayload);
    return decoded == null ? null : _decodeMapRows(decoded, depth + 1);
  }

  if (payload is List) {
    return payload.whereType<Map>().map(_stringKeyedMap).toList();
  }

  if (payload is Map) {
    final map = _stringKeyedMap(payload);
    for (final key in const ['agenda', 'data', 'valor', 'json']) {
      if (!map.containsKey(key)) {
        continue;
      }

      final rows = _decodeMapRows(map[key], depth + 1);
      if (rows != null) {
        return rows;
      }
    }
  }

  return null;
}

Object? _decodeJsonLikePayload(String rawPayload) {
  try {
    return jsonDecode(rawPayload);
  } catch (_) {
    // La agenda del backend puede llegar como JSON con comillas simples.
  }

  try {
    return jsonDecode(rawPayload.replaceAll("'", '"'));
  } catch (_) {
    return null;
  }
}

int? _parseTimeInput(String? rawValue) {
  final value = rawValue?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }

  final colonMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (colonMatch != null) {
    return _minutesFromHourMinute(colonMatch.group(1)!, colonMatch.group(2)!);
  }

  final digitsMatch = RegExp(r'^\d{3,4}$').firstMatch(value);
  if (digitsMatch == null) {
    return null;
  }

  final hourText = value.substring(0, value.length - 2);
  final minuteText = value.substring(value.length - 2);
  return _minutesFromHourMinute(hourText, minuteText);
}

int? _minutesFromCompactTime(String value) {
  if (!RegExp(r'^\d{4}$').hasMatch(value)) {
    return null;
  }

  return _minutesFromHourMinute(value.substring(0, 2), value.substring(2));
}

int? _minutesFromHourMinute(String hourText, String minuteText) {
  final hour = int.tryParse(hourText);
  final minute = int.tryParse(minuteText);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

int? _parsePositiveMinutes(String rawValue) {
  final directValue = int.tryParse(rawValue.trim());
  if (directValue != null && directValue > 0) {
    return directValue;
  }

  final decodedValue = _decodeJsonLikePayload(rawValue.trim());
  if (decodedValue is num && decodedValue > 0) {
    return decodedValue.toInt();
  }

  if (decodedValue is String) {
    final value = int.tryParse(decodedValue.trim());
    if (value != null && value > 0) {
      return value;
    }
  }

  if (decodedValue is Map) {
    final map = _stringKeyedMap(decodedValue);
    for (final key in const ['lapsus_agenda', 'valor', 'rpta']) {
      final value = int.tryParse('${map[key] ?? ''}'.trim());
      if (value != null && value > 0) {
        return value;
      }
    }
  }

  return null;
}

int? _parseConfiguredTime(String rawValue) {
  final trimmedValue = rawValue.trim();
  final directValue = _parseTimeInput(trimmedValue);
  if (directValue != null) {
    return directValue;
  }

  final decodedValue = _decodeJsonLikePayload(trimmedValue);
  if (decodedValue is String) {
    return _parseTimeInput(decodedValue);
  }

  if (decodedValue is Map) {
    final map = _stringKeyedMap(decodedValue);
    for (final key in const ['agenda_desde', 'agenda_hasta', 'valor', 'rpta']) {
      final value = _parseTimeInput('${map[key] ?? ''}'.trim());
      if (value != null) {
        return value;
      }
    }
  }

  return null;
}

String _formatCompactTime(String value) {
  if (value.length != 4) {
    return value;
  }

  return '${value.substring(0, 2)}:${value.substring(2)}';
}

String _formatMinuteOfDay(int minutes) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  return '${_twoDigits(hour)}:${_twoDigits(minute)}';
}

String _formatCompactMinuteOfDay(int minutes) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  return '${_twoDigits(hour)}${_twoDigits(minute)}';
}

List<_AgendaBandSegment> _agendaBandSegments({
  required int startMinutes,
  required int endMinutes,
  required List<_AgendaSlot> occupiedSlots,
}) {
  if (startMinutes >= endMinutes) {
    return const [];
  }

  final occupiedSegments = <_AgendaBandSegment>[];
  for (final slot in occupiedSlots) {
    final clippedStart = max(startMinutes, slot.startMinutes);
    final clippedEnd = min(endMinutes, slot.endMinutes);
    if (clippedEnd <= clippedStart) {
      continue;
    }

    occupiedSegments.add(
      _AgendaBandSegment(
        startMinutes: clippedStart,
        endMinutes: clippedEnd,
        isOccupied: true,
      ),
    );
  }

  occupiedSegments.sort(
    (left, right) => left.startMinutes.compareTo(right.startMinutes),
  );

  final mergedOccupiedSegments = <_AgendaBandSegment>[];
  for (final segment in occupiedSegments) {
    if (mergedOccupiedSegments.isEmpty ||
        segment.startMinutes > mergedOccupiedSegments.last.endMinutes) {
      mergedOccupiedSegments.add(segment);
      continue;
    }

    final last = mergedOccupiedSegments.last;
    if (segment.endMinutes > last.endMinutes) {
      mergedOccupiedSegments[mergedOccupiedSegments.length -
          1] = _AgendaBandSegment(
        startMinutes: last.startMinutes,
        endMinutes: segment.endMinutes,
        isOccupied: true,
      );
    }
  }

  final segments = <_AgendaBandSegment>[];
  var cursor = startMinutes;
  for (final occupiedSegment in mergedOccupiedSegments) {
    if (cursor < occupiedSegment.startMinutes) {
      segments.add(
        _AgendaBandSegment(
          startMinutes: cursor,
          endMinutes: occupiedSegment.startMinutes,
          isOccupied: false,
        ),
      );
    }

    segments.add(occupiedSegment);
    cursor = occupiedSegment.endMinutes;
  }

  if (cursor < endMinutes) {
    segments.add(
      _AgendaBandSegment(
        startMinutes: cursor,
        endMinutes: endMinutes,
        isOccupied: false,
      ),
    );
  }

  return segments;
}

class _AgendaSlot {
  const _AgendaSlot({
    required this.desde,
    required this.hasta,
    required this.startMinutes,
    required this.endMinutes,
    required this.idPartida,
  });

  final String desde;
  final String hasta;
  final int startMinutes;
  final int endMinutes;
  final String idPartida;

  static _AgendaSlot? fromMap(Map<String, dynamic> map) {
    final desde = '${map['desde'] ?? ''}'.trim();
    final hasta = '${map['hasta'] ?? ''}'.trim();
    final startMinutes = _minutesFromCompactTime(desde);
    final endMinutes = _minutesFromCompactTime(hasta);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      return null;
    }

    return _AgendaSlot(
      desde: desde,
      hasta: hasta,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      idPartida: '${map['idPartida'] ?? ''}'.trim(),
    );
  }

  bool intersectsRange(int rangeStartMinutes, int rangeEndMinutes) {
    return rangeStartMinutes < endMinutes && rangeEndMinutes > startMinutes;
  }

  String get formattedRange {
    return '${_formatCompactTime(desde)} - ${_formatCompactTime(hasta)}';
  }

  String get label {
    return idPartida.isEmpty ? formattedRange : '$formattedRange · $idPartida';
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

class _CreatedGameInfo {
  const _CreatedGameInfo({
    required this.idPartida,
    required this.esCreador,
    required this.dia,
    required this.hora,
    required this.idUsuarioCreador,
    required this.aliasCreador,
    required this.movilCreador,
  });

  final String idPartida;
  final String esCreador;
  final String dia;
  final String hora;
  final String idUsuarioCreador;
  final String aliasCreador;
  final String movilCreador;

  static _CreatedGameInfo? fromMap(Map<String, dynamic> map) {
    final idPartida = '${map['idPartida'] ?? ''}'.trim();
    if (idPartida.isEmpty) {
      return null;
    }

    return _CreatedGameInfo(
      idPartida: idPartida,
      esCreador: '${map['es_creador'] ?? ''}'.trim(),
      dia: '${map['dia'] ?? ''}'.trim(),
      hora: '${map['hora'] ?? ''}'.trim(),
      idUsuarioCreador: '${map['idUsuarioCreador'] ?? ''}'.trim(),
      aliasCreador: '${map['aliasCreador'] ?? ''}'.trim(),
      movilCreador: '${map['movilCreador'] ?? ''}'.trim(),
    );
  }
}
