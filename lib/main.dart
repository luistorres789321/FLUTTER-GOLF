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
  }

  Future<void> _saveUserInformation(
    _UserInformation information, {
    required bool isRegistered,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedUserInformationKey, information.toJsonString());
    await prefs.setBool(_savedUserRegisteredKey, isRegistered);

    if (!mounted) {
      return;
    }

    setState(() {
      _userInformation = information;
      _isUserRegistered = isRegistered;
      _isEditingUserInformation = false;
      _isUserInformationDismissed = false;
      _userRegistrationError = isRegistered
          ? null
          : _userRegistrationRequiredMessage;
    });
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

    final isRegistered = await _registerUserInBackend(information);
    await widget.onSave(information, isRegistered: isRegistered);

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

  Future<bool> _registerUserInBackend(_UserInformation information) async {
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
      final isRegistered = _backendResponseSaysOk(response);
      debugPrint('altaUsuario(${information.alias}): $response');
      return isRegistered;
    } catch (error) {
      debugPrint('altaUsuario(${information.alias}) fallo: $error');
      return false;
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
}

bool _backendResponseSaysYes(String response) {
  final rpta = _backendResponseValue(response);
  if (rpta == null) {
    throw FormatException('Respuesta no valida: $response');
  }

  return rpta == 'si' || rpta == 'sí';
}

bool _backendResponseSaysOk(String response) {
  return _backendResponseValue(response) == 'ok';
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
