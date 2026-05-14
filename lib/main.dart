import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'golf_scorecard_screen.dart';
import 'services/datos_servidor_service.dart';

const _deviceIdKey = 'idDispositivo';
const _deviceIdLength = 32;
const _deviceIdAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _firebaseMessagingTokenKey = 'firebase_messaging_token';
const _firebaseMessagingTokenStatusKey = 'firebase_messaging_token_status';
const _firebaseMessagingTokenStatusPending = 'no enviada';
const _firebaseMessagingTokenStatusSent = 'enviada';
const _firebaseMessagingTokenStatusLegacyPending = 'no enviado';
const _firebaseMessagingTokenStatusLegacySent = 'enviado';
const _firebaseMessagingApnsTokenPollDelay = Duration(milliseconds: 500);
const _firebaseMessagingApnsTokenPollAttempts = 20;
bool _isSendingFirebaseMessagingToken = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureDeviceId();
  if (_supportsFirebaseMessaging) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    unawaited(_configureFirebaseMessaging());
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const GolfScorecardApp());
}

Future<String> _ensureDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final savedDeviceId = prefs.getString(_deviceIdKey)?.trim();
  if (savedDeviceId != null && savedDeviceId.isNotEmpty) {
    debugPrint('idDispositivo existente: $savedDeviceId');
    return savedDeviceId;
  }

  final deviceId = _generateDeviceId();
  await prefs.setString(_deviceIdKey, deviceId);
  debugPrint('idDispositivo generado: $deviceId');
  return deviceId;
}

String _generateDeviceId() {
  final random = Random.secure();
  return List.generate(
    _deviceIdLength,
    (_) => _deviceIdAlphabet[random.nextInt(_deviceIdAlphabet.length)],
  ).join();
}

bool get _supportsFirebaseMessaging {
  if (kIsWeb) {
    return false;
  }

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Firebase background message: ${message.messageId ?? 'sin id'}');
}

Future<void> _configureFirebaseMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      'Firebase notification permission: ${settings.authorizationStatus.name}',
    );

    await _storeFirebaseMessagingToken(
      await _loadFirebaseMessagingToken(messaging),
    );

    messaging.onTokenRefresh.listen((token) {
      unawaited(_storeFirebaseMessagingToken(token));
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        'Firebase foreground message: ${message.messageId ?? 'sin id'}',
      );
    });
  } catch (error) {
    debugPrint('Firebase messaging setup fallo: $error');
  }
}

Future<String?> _loadFirebaseMessagingToken(FirebaseMessaging messaging) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final apnsToken = await _waitForFirebaseApnsToken(messaging);
    if (apnsToken == null) {
      debugPrint('Firebase APNs token no disponible todavia.');
      return null;
    }
    debugPrint('Firebase APNs token disponible: $apnsToken');
  }

  return messaging.getToken();
}

Future<String?> _waitForFirebaseApnsToken(FirebaseMessaging messaging) async {
  for (
    var attempt = 0;
    attempt < _firebaseMessagingApnsTokenPollAttempts;
    attempt++
  ) {
    final token = await messaging.getAPNSToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }

    await Future<void>.delayed(_firebaseMessagingApnsTokenPollDelay);
  }

  return null;
}

Future<void> _storeFirebaseMessagingToken(String? token) async {
  if (token == null || token.isEmpty) {
    debugPrint('Firebase FCM token no disponible todavia.');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final previousToken = prefs.getString(_firebaseMessagingTokenKey);
  final previousStatus = prefs.getString(_firebaseMessagingTokenStatusKey);
  final nextStatus =
      previousToken == token &&
          _isKnownFirebaseMessagingTokenStatus(previousStatus)
      ? _normalizeFirebaseMessagingTokenStatus(previousStatus!)
      : _firebaseMessagingTokenStatusPending;

  await prefs.setString(_firebaseMessagingTokenKey, token);
  await prefs.setString(_firebaseMessagingTokenStatusKey, nextStatus);
  debugPrint('Firebase FCM token guardado: $token ($nextStatus)');
  await _sendPendingFirebaseMessagingTokenIfNeeded(prefs);
}

bool _isKnownFirebaseMessagingTokenStatus(String? status) {
  return _isPendingFirebaseMessagingTokenStatus(status) ||
      _isSentFirebaseMessagingTokenStatus(status);
}

bool _isPendingFirebaseMessagingTokenStatus(String? status) {
  return status == _firebaseMessagingTokenStatusPending ||
      status == _firebaseMessagingTokenStatusLegacyPending;
}

bool _isSentFirebaseMessagingTokenStatus(String? status) {
  return status == _firebaseMessagingTokenStatusSent ||
      status == _firebaseMessagingTokenStatusLegacySent;
}

String _normalizeFirebaseMessagingTokenStatus(String status) {
  if (_isSentFirebaseMessagingTokenStatus(status)) {
    return _firebaseMessagingTokenStatusSent;
  }

  return _firebaseMessagingTokenStatusPending;
}

Future<void> _sendPendingFirebaseMessagingTokenIfNeeded(
  SharedPreferences prefs,
) async {
  if (_isSendingFirebaseMessagingToken) {
    return;
  }

  final deviceId = prefs.getString(_deviceIdKey)?.trim() ?? '';
  final token = prefs.getString(_firebaseMessagingTokenKey)?.trim() ?? '';
  final status = prefs.getString(_firebaseMessagingTokenStatusKey);
  if (deviceId.isEmpty || token.isEmpty) {
    debugPrint('Firebase FCM token pendiente sin idDispositivo o clave.');
    return;
  }

  if (!_isPendingFirebaseMessagingTokenStatus(status)) {
    return;
  }

  _isSendingFirebaseMessagingToken = true;
  final datosServidorService = DatosServidorService();
  try {
    final response = await datosServidorService.registraClaveFmc(
      idDispositivo: deviceId,
      clave: token,
    );
    if (_isOkServerResponse(response)) {
      final currentToken =
          prefs.getString(_firebaseMessagingTokenKey)?.trim() ?? '';
      if (currentToken == token) {
        await prefs.setString(
          _firebaseMessagingTokenStatusKey,
          _firebaseMessagingTokenStatusSent,
        );
        debugPrint('Firebase FCM token marcado como enviada.');
      } else {
        debugPrint('Firebase FCM token cambiado antes de marcar enviada.');
      }
    } else {
      debugPrint('registra_clave_FMC respuesta inesperada: $response');
    }
  } catch (error) {
    debugPrint('registra_clave_FMC fallo: $error');
  } finally {
    datosServidorService.close();
    _isSendingFirebaseMessagingToken = false;
  }
}

bool _isOkServerResponse(String response) {
  try {
    final decoded = jsonDecode(response);
    return decoded is Map && '${decoded['rpta'] ?? ''}'.trim() == 'ok';
  } catch (_) {
    return false;
  }
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

class _GolfAppHomeState extends State<GolfAppHome> with WidgetsBindingObserver {
  static const _savedUserInformationKey = 'saved_user_information_json';
  static const _savedUserRegisteredKey = 'saved_user_registered';
  static const _userRegistrationRequiredMessage =
      'es necesario Guardar los datos de usuario';
  static const _savedGameIdKey = 'saved_game_id';
  static const _savedFieldIdKey = 'saved_field_id';
  static const _savedPlayersKey = 'saved_players';
  static const _savedGameRowsKey = 'saved_game_rows_json';
  static const _invitationGameIdKey = 'invitation_game_id';
  static const _invitationGameCreatedAtKey = 'invitation_game_created_at';
  static const _defaultFieldId = '1';
  static const _jsonHoyosPollDelay = Duration(seconds: 5);
  static const _positionTransmissionDelay = Duration(seconds: 20);
  static const _pendingInvitationPollDelay = Duration(seconds: 6);
  static const _invitationGameLifetime = Duration(hours: 2);

  late final DatosServidorService _datosServidorService;
  late final bool _ownsDatosServidorService;
  int _jsonHoyosPollingGeneration = 0;
  Timer? _jsonHoyosPollingTimer;
  Timer? _positionTransmissionTimer;
  Timer? _pendingInvitationPollingTimer;
  Timer? _leagueButtonBlinkTimer;
  bool _isAppVisible = true;
  bool _isTransmittingPosition = false;
  bool _isCheckingPendingLeagueInvitations = false;
  bool _leagueButtonBlinkOn = false;
  bool _isLoading = true;
  String? _savedGameId;
  String _savedFieldId = _defaultFieldId;
  String? _differentRemotePlayRowsJson;
  String? _creationError;
  String? _userRegistrationError;
  _InitialGameState _initialGameState = const _InitialGameState();
  _PendingLeagueInvitations _pendingLeagueInvitations =
      const _PendingLeagueInvitations.empty();
  _GameSession? _activeSession;
  _UserInformation? _userInformation;
  bool _isUserRegistered = false;
  bool _isEditingUserInformation = false;
  bool _isUserInformationDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsDatosServidorService = widget.datosServidorService == null;
    _datosServidorService =
        widget.datosServidorService ?? DatosServidorService();
    _loadSavedGame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopJsonHoyosPolling();
    _stopPositionTransmission();
    _stopPendingInvitationPolling();
    _stopLeagueButtonBlink(updateState: false);
    if (_ownsDatosServidorService) {
      _datosServidorService.close();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppVisible = state == AppLifecycleState.resumed;
    if (_isAppVisible) {
      _startPositionTransmissionIfNeeded();
      _startPendingInvitationPollingIfNeeded();
      _syncLeagueButtonBlinkTimer();
    } else {
      _stopPositionTransmission();
      _stopPendingInvitationPolling();
      _stopLeagueButtonBlink();
    }
  }

  Future<void> _loadSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGameId = prefs.getString(_savedGameIdKey);
    final savedFieldId = prefs.getString(_savedFieldIdKey) ?? _defaultFieldId;
    await _validInvitationGameIdFromPrefs(prefs);
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
      _userInformation = userInformation;
      _isUserRegistered = isUserRegistered;
      _userRegistrationError = isUserRegistered
          ? null
          : _userRegistrationRequiredMessage;
      _isLoading = false;
    });

    if (isUserRegistered && userInformation.idUsuario.isNotEmpty) {
      unawaited(_loadInitialGameState(userInformation.idUsuario));
      _startPositionTransmissionIfNeeded();
      _startPendingInvitationPollingIfNeeded();
    }
  }

  Future<String?> _validInvitationGameIdFromPrefs(
    SharedPreferences prefs,
  ) async {
    final idPartida = prefs.getString(_invitationGameIdKey)?.trim();
    final createdAt = prefs.getInt(_invitationGameCreatedAtKey);
    if (idPartida == null || idPartida.isEmpty || createdAt == null) {
      await _clearInvitationGameId(prefs);
      return null;
    }

    final createdAtDate = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final isExpired =
        DateTime.now().difference(createdAtDate) >= _invitationGameLifetime;
    if (isExpired) {
      await _clearInvitationGameId(prefs);
      return null;
    }

    return idPartida;
  }

  Future<String?> _loadValidInvitationGameId() async {
    final savedGameId = _savedGameId?.trim();
    if (savedGameId != null && savedGameId.isNotEmpty) {
      return savedGameId;
    }

    final prefs = await SharedPreferences.getInstance();
    final persistedSavedGameId = prefs.getString(_savedGameIdKey)?.trim();
    if (persistedSavedGameId != null && persistedSavedGameId.isNotEmpty) {
      return persistedSavedGameId;
    }

    return _validInvitationGameIdFromPrefs(prefs);
  }

  Future<void> _storeInvitationGameId(String idPartida) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_invitationGameIdKey, idPartida);
    await prefs.setInt(
      _invitationGameCreatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _clearInvitationGameId(SharedPreferences prefs) async {
    await prefs.remove(_invitationGameIdKey);
    await prefs.remove(_invitationGameCreatedAtKey);
  }

  Future<void> _saveUserInformation(
    _UserInformation information, {
    required bool isRegistered,
    String idUsuario = '',
  }) async {
    final savedInformation = information.copyWith(idUsuario: idUsuario);
    final previousUserId = _userInformation?.idUsuario.trim() ?? '';
    final nextUserId = savedInformation.idUsuario.trim();
    final shouldResetPendingInvitations =
        !isRegistered || previousUserId != nextUserId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedUserInformationKey,
      savedInformation.toJsonString(),
    );
    await prefs.setBool(_savedUserRegisteredKey, isRegistered);

    if (!mounted) {
      return;
    }

    if (shouldResetPendingInvitations) {
      _stopPendingInvitationPolling();
      _stopLeagueButtonBlink(updateState: false);
    }

    setState(() {
      _userInformation = savedInformation;
      _isUserRegistered = isRegistered;
      _isEditingUserInformation = false;
      _isUserInformationDismissed = false;
      _userRegistrationError = isRegistered
          ? null
          : _userRegistrationRequiredMessage;
      if (shouldResetPendingInvitations) {
        _pendingLeagueInvitations = const _PendingLeagueInvitations.empty();
        _leagueButtonBlinkOn = false;
      }
    });

    if (isRegistered && savedInformation.idUsuario.isNotEmpty) {
      unawaited(_loadInitialGameState(savedInformation.idUsuario));
      _startPositionTransmissionIfNeeded();
      _startPendingInvitationPollingIfNeeded();
    } else {
      _stopPositionTransmission();
      _stopPendingInvitationPolling();
    }
  }

  Future<void> _loadInitialGameState(String idUsuario) async {
    try {
      final response = await _datosServidorService.obtenerEstadoInicial(
        idUsuario,
      );
      final initialGameState = _initialGameStateFromResponse(response);
      if (!mounted) {
        return;
      }

      setState(() {
        _initialGameState = initialGameState;
      });
    } catch (error) {
      debugPrint('obtener estado inicial fallo: $error');
    }
  }

  String get _positionTransmissionUserId {
    if (!_isUserRegistered) {
      return '';
    }

    return _userInformation?.idUsuario.trim() ?? '';
  }

  void _startPositionTransmissionIfNeeded() {
    if (!_isAppVisible ||
        _positionTransmissionTimer != null ||
        _positionTransmissionUserId.isEmpty) {
      return;
    }

    unawaited(_transmitCurrentPosition());
    _positionTransmissionTimer = Timer.periodic(_positionTransmissionDelay, (
      _,
    ) {
      unawaited(_transmitCurrentPosition());
    });
  }

  void _stopPositionTransmission() {
    _positionTransmissionTimer?.cancel();
    _positionTransmissionTimer = null;
  }

  String get _pendingInvitationUserId {
    if (!_isUserRegistered) {
      return '';
    }

    return _userInformation?.idUsuario.trim() ?? '';
  }

  void _startPendingInvitationPollingIfNeeded() {
    if (!_isAppVisible ||
        _pendingInvitationUserId.isEmpty ||
        _pendingInvitationPollingTimer != null ||
        _isCheckingPendingLeagueInvitations) {
      return;
    }

    unawaited(_checkPendingLeagueInvitations());
  }

  void _stopPendingInvitationPolling() {
    _pendingInvitationPollingTimer?.cancel();
    _pendingInvitationPollingTimer = null;
  }

  Future<void> _checkPendingLeagueInvitations() async {
    final idUsuario = _pendingInvitationUserId;
    if (!_isAppVisible || idUsuario.isEmpty) {
      return;
    }

    _stopPendingInvitationPolling();
    if (_isCheckingPendingLeagueInvitations) {
      return;
    }

    _isCheckingPendingLeagueInvitations = true;
    try {
      final response = await _datosServidorService.miraSiHayInvitacionPendiente(
        idUsuario,
      );
      final pendingInvitations = _pendingLeagueInvitationsFromResponse(
        response,
      );

      if (!mounted || _pendingInvitationUserId != idUsuario) {
        return;
      }

      _applyPendingLeagueInvitations(pendingInvitations);
    } catch (error) {
      debugPrint('miraSiHayInvitacionPendiente fallo: $error');
      if (error is DatosServidorException) {
        debugPrint('miraSiHayInvitacionPendiente backend body: ${error.body}');
      }
    } finally {
      _isCheckingPendingLeagueInvitations = false;
      if (mounted &&
          _isAppVisible &&
          _pendingInvitationUserId == idUsuario &&
          idUsuario.isNotEmpty) {
        _pendingInvitationPollingTimer = Timer(_pendingInvitationPollDelay, () {
          _pendingInvitationPollingTimer = null;
          unawaited(_checkPendingLeagueInvitations());
        });
      }
    }
  }

  void _applyPendingLeagueInvitations(
    _PendingLeagueInvitations pendingInvitations,
  ) {
    final hadPendingInvitations = _pendingLeagueInvitations.hasPending;
    setState(() {
      _pendingLeagueInvitations = pendingInvitations;
      if (!pendingInvitations.hasPending) {
        _leagueButtonBlinkOn = false;
      } else if (!hadPendingInvitations) {
        _leagueButtonBlinkOn = true;
      }
    });
    _syncLeagueButtonBlinkTimer();
  }

  void _refreshPendingLeagueInvitations() {
    _stopPendingInvitationPolling();
    unawaited(_checkPendingLeagueInvitations());
  }

  void _syncLeagueButtonBlinkTimer() {
    final shouldBlink = _isAppVisible && _pendingLeagueInvitations.hasPending;
    if (!shouldBlink) {
      _stopLeagueButtonBlink();
      return;
    }

    if (_leagueButtonBlinkTimer != null) {
      return;
    }

    _leagueButtonBlinkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isAppVisible || !_pendingLeagueInvitations.hasPending) {
        _stopLeagueButtonBlink();
        return;
      }

      setState(() {
        _leagueButtonBlinkOn = !_leagueButtonBlinkOn;
      });
    });
  }

  void _stopLeagueButtonBlink({bool updateState = true}) {
    _leagueButtonBlinkTimer?.cancel();
    _leagueButtonBlinkTimer = null;
    if (updateState && _leagueButtonBlinkOn && mounted) {
      setState(() {
        _leagueButtonBlinkOn = false;
      });
    } else {
      _leagueButtonBlinkOn = false;
    }
  }

  Future<void> _transmitCurrentPosition() async {
    final idUsuario = _positionTransmissionUserId;
    if (!_isAppVisible || idUsuario.isEmpty || _isTransmittingPosition) {
      return;
    }

    _isTransmittingPosition = true;
    try {
      final position = await _currentGolfPositionPayload();
      await _datosServidorService.transmitePosicionGolf(
        idUsuario: idUsuario,
        lat: position.lat,
        lon: position.lon,
        fecha: position.fecha,
        precision: position.precision,
      );
    } catch (error) {
      debugPrint('transmitePosicionGolf fallo: $error');
    } finally {
      _isTransmittingPosition = false;
    }
  }

  Future<_GolfPositionPayload> _currentGolfPositionPayload() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _GolfPositionPayload.unavailable(DateTime.now());
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _GolfPositionPayload.unavailable(DateTime.now());
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _GolfPositionPayload.fromPosition(position);
    } catch (error) {
      debugPrint('obtener posicion fallo: $error');
      return _GolfPositionPayload.unavailable(DateTime.now());
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
    if (_userInformation == null && !_isEditingUserInformation) {
      unawaited(SystemNavigator.pop());
      return;
    }

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

  Future<void> _openStartRoundOptions() async {
    final idUsuario = _userInformation?.idUsuario ?? '';
    if (idUsuario.isEmpty) {
      setState(() {
        _creationError = 'No se pudo identificar el usuario para iniciar.';
        _userRegistrationError = null;
      });
      return;
    }

    setState(() {
      _creationError = null;
      _userRegistrationError = null;
    });

    final session = await Navigator.of(context).push<_GameSession>(
      MaterialPageRoute<_GameSession>(
        builder: (context) => _InvitePlayersScreen(
          datosServidorService: _datosServidorService,
          fieldId: _savedFieldId,
          idUsuario: idUsuario,
          loadValidInvitationGameId: _loadValidInvitationGameId,
          generateIdPartida: _generateGameId,
          onInvitationGameCreated: _storeInvitationGameId,
          onInvitationAccepted: _saveAcceptedInvitationGameId,
        ),
      ),
    );
    if (!mounted || session == null) {
      return;
    }

    await _activateSession(session);
  }

  Future<void> _activateSession(_GameSession session) async {
    _stopJsonHoyosPolling();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedGameIdKey, session.idPartida);
    await prefs.setString(_savedFieldIdKey, session.idCampo);
    await prefs.setString(_savedPlayersKey, session.jugadores);
    await prefs.setString(_savedGameRowsKey, session.playRowsJson);

    if (!mounted) {
      return;
    }

    setState(() {
      _creationError = null;
      _differentRemotePlayRowsJson = null;
      _savedGameId = session.idPartida;
      _savedFieldId = session.idCampo;
      _activeSession = session;
    });
    _startJsonHoyosPolling();
  }

  Future<void> _saveAcceptedInvitationGameId(String idPartida) async {
    final acceptedIdPartida = idPartida.trim();
    if (acceptedIdPartida.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedGameIdKey, acceptedIdPartida);
    await prefs.remove(_savedPlayersKey);
    await prefs.remove(_savedGameRowsKey);
    await prefs.setString(_invitationGameIdKey, acceptedIdPartida);
    await prefs.setInt(
      _invitationGameCreatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _savedGameId = acceptedIdPartida;
    });
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

  void _openStatistics() {
    final userInformation = _userInformation;
    final idUsuario = userInformation?.idUsuario.trim() ?? '';
    if (userInformation == null || idUsuario.isEmpty) {
      setState(() {
        _creationError =
            'No se pudo identificar el usuario para ver estadisticas.';
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
        builder: (context) => _StatisticsScreen(
          datosServidorService: _datosServidorService,
          fieldId: _savedFieldId,
          idUsuario: idUsuario,
          alias: userInformation.alias,
        ),
      ),
    );
  }

  Future<void> _openLeagues() async {
    if (!_canCreateUserBoundAction()) {
      setState(() {
        _creationError =
            'No se pudo identificar el usuario para ver liguillas.';
        _userRegistrationError = null;
      });
      return;
    }

    setState(() {
      _creationError = null;
      _userRegistrationError = null;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _LeaguesScreen(
          datosServidorService: _datosServidorService,
          idUsuario: _userInformation!.idUsuario.trim(),
          pendingInvitationLeagueIds: _pendingLeagueInvitations.leagueIds,
          onInvitationDecisionChanged: _refreshPendingLeagueInvitations,
        ),
      ),
    );
    if (mounted) {
      _refreshPendingLeagueInvitations();
    }
  }

  bool _canCreateUserBoundAction() {
    final idUsuario = _userInformation?.idUsuario.trim() ?? '';
    return _isUserRegistered && idUsuario.isNotEmpty;
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
    _jsonHoyosPollingTimer?.cancel();
    unawaited(_pollJsonHoyos(generation));
  }

  void _stopJsonHoyosPolling() {
    _jsonHoyosPollingGeneration++;
    _jsonHoyosPollingTimer?.cancel();
    _jsonHoyosPollingTimer = null;
  }

  Future<void> _pollJsonHoyos(int generation) async {
    if (!mounted || generation != _jsonHoyosPollingGeneration) {
      return;
    }

    final session = _activeSession;
    if (session == null) {
      return;
    }

    String? playRowsResponse;
    try {
      playRowsResponse = await _datosServidorService.obtenerJsonHoyos(
        session.idCampo,
        session.idPartida,
      );

      if (!mounted || generation != _jsonHoyosPollingGeneration) {
        return;
      }

      await _applyRemotePlayRowsJson(session, playRowsResponse);
    } catch (error) {
      debugPrint('obtenerJsonHoyos error: $error');
    }

    try {
      final playersResponse = await _datosServidorService
          .obtenerJugadoresPartida(session.idPartida);

      if (!mounted || generation != _jsonHoyosPollingGeneration) {
        return;
      }

      await _applyRemotePlayers(
        session,
        playersResponse,
        remotePlayRowsResponse: playRowsResponse,
      );
    } catch (error) {
      debugPrint('obtenerJugadoresPartida polling error: $error');
    }

    if (!mounted || generation != _jsonHoyosPollingGeneration) {
      return;
    }

    _jsonHoyosPollingTimer?.cancel();
    _jsonHoyosPollingTimer = Timer(_jsonHoyosPollDelay, () {
      unawaited(_pollJsonHoyos(generation));
    });
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

  Future<void> _applyRemotePlayers(
    _GameSession requestedSession,
    String rawPlayersResponse, {
    String? remotePlayRowsResponse,
  }) async {
    final players = _invitedPlayersFromResponse(rawPlayersResponse);
    final session = _activeSession;
    if (session == null ||
        session.idCampo != requestedSession.idCampo ||
        session.idPartida != requestedSession.idPartida) {
      return;
    }

    final idUsuario = _userInformation?.idUsuario.trim() ?? '';
    final currentUserIsMissing =
        idUsuario.isNotEmpty &&
        !players.any((player) => player.idJugador.trim() == idUsuario);
    if (currentUserIsMissing) {
      debugPrint(
        'Usuario actual $idUsuario no encontrado en '
        'obtenerJugadoresPartida(${session.idPartida}); se cambia idPartida.',
      );
      await _replaceCurrentLocalGameId(
        requestedSession,
        reason: 'jugador ausente',
      );
      return;
    }

    if (players.isEmpty) {
      return;
    }

    final mergedPlayRowsJson = remotePlayRowsResponse == null
        ? session.playRowsJson
        : _mergeNewerPlayRowsJson(
                currentJson: session.playRowsJson,
                remoteResponse: remotePlayRowsResponse,
              ) ??
              session.playRowsJson;
    final existingRows =
        _decodePlayRowsPayload(mergedPlayRowsJson) ??
        _decodePlayRowsPayload(session.playRowsJson) ??
        const <Map<String, dynamic>>[];
    final refreshedSession = _GameSession(
      idPartida: session.idPartida,
      idCampo: session.idCampo,
      jugadores: players.length.toString(),
      playRowsJson: _createPlayRowsJsonForPlayers(
        players,
        existingRows: existingRows,
      ),
    );

    if (refreshedSession.jugadores == session.jugadores &&
        refreshedSession.playRowsJson == session.playRowsJson) {
      return;
    }

    await _saveSessionLocallyIfCurrent(requestedSession, refreshedSession);
    _setDifferentRemotePlayRowsJson(null);
  }

  Future<void> _leaveCurrentUserGame() async {
    final session = _activeSession;
    final idUsuario = _userInformation?.idUsuario.trim() ?? '';
    if (session == null || idUsuario.isEmpty) {
      throw StateError('No se pudo identificar la partida o el usuario.');
    }

    final response = await _datosServidorService.bajaJugadorPartida(
      idPartida: session.idPartida,
      idUsuario: idUsuario,
    );
    debugPrint(
      'bajaJugadorPartida(${session.idPartida}, $idUsuario): $response',
    );
    if (!_backendResponseIsOk(response)) {
      throw FormatException('Respuesta no valida: $response');
    }

    await _replaceCurrentLocalGameId(session, reason: 'baja');
  }

  Future<void> _replaceCurrentLocalGameId(
    _GameSession requestedSession, {
    required String reason,
  }) async {
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    _stopJsonHoyosPolling();
    final newIdPartida = _generateReplacementGameId(requestedSession.idPartida);
    try {
      final createResponse = await _datosServidorService.creaPartida(
        requestedSession.idCampo,
        newIdPartida,
      );
      debugPrint('creaPartida($newIdPartida) tras $reason: $createResponse');
    } catch (error) {
      debugPrint('creaPartida($newIdPartida) tras $reason fallo: $error');
    }

    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    await prefs.setString(_savedGameIdKey, newIdPartida);
    await prefs.setString(_savedFieldIdKey, requestedSession.idCampo);
    await prefs.remove(_savedPlayersKey);
    await prefs.remove(_savedGameRowsKey);
    await prefs.setString(_invitationGameIdKey, newIdPartida);
    await prefs.setInt(
      _invitationGameCreatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted || !_isCurrentSession(requestedSession)) {
      return;
    }

    setState(() {
      _savedGameId = newIdPartida;
      _savedFieldId = requestedSession.idCampo;
      _activeSession = null;
      _differentRemotePlayRowsJson = null;
      _creationError = null;
      _initialGameState = const _InitialGameState();
    });

    final idUsuario = _userInformation?.idUsuario;
    if (_isUserRegistered && idUsuario != null && idUsuario.isNotEmpty) {
      unawaited(_loadInitialGameState(idUsuario));
    }
  }

  Future<void> _destroyCurrentGame() async {
    final session = _activeSession;
    if (session == null) {
      throw StateError('No se pudo identificar la partida.');
    }

    final response = await _datosServidorService.destruyePartida(
      session.idPartida,
    );
    debugPrint('destruyePartida(${session.idPartida}): $response');
    if (!_backendResponseIsOk(response)) {
      throw FormatException('Respuesta no valida: $response');
    }

    await _clearDestroyedSession(session);
  }

  Future<void> _clearDestroyedSession(_GameSession requestedSession) async {
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    _stopJsonHoyosPolling();
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    await prefs.remove(_savedGameIdKey);
    await prefs.remove(_savedPlayersKey);
    await prefs.remove(_savedGameRowsKey);
    await _clearInvitationGameId(prefs);

    if (!mounted || !_isCurrentSession(requestedSession)) {
      return;
    }

    setState(() {
      _savedGameId = null;
      _activeSession = null;
      _differentRemotePlayRowsJson = null;
      _creationError = null;
      _initialGameState = const _InitialGameState();
    });

    final idUsuario = _userInformation?.idUsuario;
    if (_isUserRegistered && idUsuario != null && idUsuario.isNotEmpty) {
      unawaited(_loadInitialGameState(idUsuario));
    }
  }

  Future<void> _saveSessionLocallyIfCurrent(
    _GameSession requestedSession,
    _GameSession refreshedSession,
  ) async {
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentSession(requestedSession)) {
      return;
    }

    await prefs.setString(_savedGameIdKey, refreshedSession.idPartida);
    await prefs.setString(_savedFieldIdKey, refreshedSession.idCampo);
    await prefs.setString(_savedPlayersKey, refreshedSession.jugadores);
    await prefs.setString(_savedGameRowsKey, refreshedSession.playRowsJson);

    if (!mounted || !_isCurrentSession(requestedSession)) {
      return;
    }

    setState(() {
      _savedGameId = refreshedSession.idPartida;
      _savedFieldId = refreshedSession.idCampo;
      _activeSession = refreshedSession;
    });
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

  void _exitActiveSession() {
    if (_activeSession == null) {
      return;
    }

    _stopJsonHoyosPolling();
    setState(() {
      _activeSession = null;
      _differentRemotePlayRowsJson = null;
    });

    final idUsuario = _userInformation?.idUsuario;
    if (_isUserRegistered && idUsuario != null && idUsuario.isNotEmpty) {
      unawaited(_loadInitialGameState(idUsuario));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession case final session?) {
      return GolfScorecardScreen(
        idPartida: session.idPartida,
        jugadores: session.jugadores,
        initialPlayRowsJson: session.playRowsJson,
        differentRemotePlayRowsJson: _differentRemotePlayRowsJson,
        datosServidorService: _datosServidorService,
        onPlayRowsJsonChanged: _savePlayRowsJson,
        onLeaveGame: _leaveCurrentUserGame,
        onDestroyGame: _destroyCurrentGame,
        onExit: _exitActiveSession,
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
    final recoverableGameId = _savedGameId?.trim();
    final hasRecoverableGame =
        canUseGameActions &&
        recoverableGameId != null &&
        recoverableGameId.isNotEmpty;
    final primaryStartLabel = _initialGameState.startButtonLabel;
    final hasStartedGame = _initialGameState.hasStarted;

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
                              Column(
                                children: [
                                  Text(
                                    'Jugador: $playerAlias',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF4B525C),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (hasRecoverableGame)
                                    Text(
                                      'idPartida: $recoverableGameId',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9AA1AA),
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 15),
                                ],
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
                              if (hasStartedGame)
                                FilledButton.icon(
                                  onPressed: canUseGameActions
                                      ? _openStartRoundOptions
                                      : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF567B37),
                                    disabledBackgroundColor: const Color(
                                      0xFFBBC5B0,
                                    ),
                                    textStyle: _homeActionButtonTextStyle,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    minimumSize: const Size(0, 58),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow,
                                    size: _homeActionIconSize,
                                  ),
                                  label: Text(primaryStartLabel),
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: canUseGameActions
                                      ? _openStartRoundOptions
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B432D),
                                    side: const BorderSide(
                                      color: Color(0xFF6B432D),
                                    ),
                                    textStyle: _homeActionButtonTextStyle,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    minimumSize: const Size(0, 58),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow,
                                    size: _homeActionIconSize,
                                  ),
                                  label: Text(primaryStartLabel),
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
                                  textStyle: _homeActionButtonTextStyle,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  minimumSize: const Size(0, 58),
                                ),
                                icon: const Icon(
                                  Icons.event_available,
                                  size: _homeActionIconSize,
                                ),
                                label: const Text('Reservar Salida'),
                              ),
                              const SizedBox(height: 14),
                              _HomeLeaguesButton(
                                onPressed: canUseGameActions
                                    ? () => unawaited(_openLeagues())
                                    : null,
                                isBlinking:
                                    _pendingLeagueInvitations.hasPending,
                                isBlinkOn: _leagueButtonBlinkOn,
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: canUseGameActions
                                    ? _openStatistics
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF235C3D),
                                  side: const BorderSide(
                                    color: Color(0xFF235C3D),
                                  ),
                                  textStyle: _homeActionButtonTextStyle,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  minimumSize: const Size(0, 58),
                                ),
                                icon: const Icon(
                                  Icons.query_stats,
                                  size: _homeActionIconSize,
                                ),
                                label: const Text('Estadisticas'),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _editUserInformation,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF545B66),
                                  side: const BorderSide(
                                    color: Color(0xFF9AA092),
                                  ),
                                  textStyle: _homeActionButtonTextStyle,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  minimumSize: const Size(0, 58),
                                ),
                                icon: const Icon(
                                  Icons.person,
                                  size: _homeActionIconSize,
                                ),
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

  String _generateReplacementGameId(String previousIdPartida) {
    final previousId = previousIdPartida.trim();
    var newIdPartida = _generateGameId();
    var attempt = 0;
    while (attempt < 5 && newIdPartida == previousId) {
      newIdPartida = _generateGameId();
      attempt++;
    }

    if (newIdPartida == previousId && previousId.isNotEmpty) {
      final replacement = previousId.endsWith('A') ? 'B' : 'A';
      return '${previousId.substring(0, previousId.length - 1)}$replacement';
    }

    return newIdPartida;
  }
}

const _homeActionButtonTextStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w800,
);
const _homeActionIconSize = 28.0;

class _HomeLeaguesButton extends StatelessWidget {
  const _HomeLeaguesButton({
    required this.onPressed,
    required this.isBlinking,
    required this.isBlinkOn,
  });

  final VoidCallback? onPressed;
  final bool isBlinking;
  final bool isBlinkOn;

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF6B432D);
    final foregroundColor = isBlinking && isBlinkOn
        ? Colors.white
        : accentColor;
    final backgroundColor = isBlinking && isBlinkOn
        ? accentColor
        : Colors.transparent;

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        side: const BorderSide(color: accentColor),
        textStyle: _homeActionButtonTextStyle,
        padding: const EdgeInsets.symmetric(vertical: 20),
        minimumSize: const Size(0, 58),
      ),
      icon: const Icon(Icons.emoji_events, size: _homeActionIconSize),
      label: const Text('Liguillas'),
    );
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

class _TopLeftBackButton extends StatelessWidget {
  const _TopLeftBackButton({required this.onPressed, this.label = 'Volver'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6B432D),
          side: const BorderSide(color: Color(0xFF6B432D)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        icon: const Icon(Icons.arrow_back),
        label: Text(label),
      ),
    );
  }
}

class _ReservationScreenFrame extends StatelessWidget {
  const _ReservationScreenFrame({
    required this.title,
    required this.children,
    this.maxWidth = 520,
    this.showBackButton = false,
    this.backLabel = 'Volver',
    this.onBack,
  });

  final String title;
  final List<Widget> children;
  final double maxWidth;
  final bool showBackButton;
  final String backLabel;
  final VoidCallback? onBack;

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
                        if (showBackButton) ...[
                          _TopLeftBackButton(
                            onPressed:
                                onBack ?? () => Navigator.of(context).pop(),
                            label: backLabel,
                          ),
                          const SizedBox(height: 10),
                        ],
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

class _StatisticsScreen extends StatefulWidget {
  const _StatisticsScreen({
    required this.datosServidorService,
    required this.fieldId,
    required this.idUsuario,
    required this.alias,
  });

  final DatosServidorService datosServidorService;
  final String fieldId;
  final String idUsuario;
  final String alias;

  @override
  State<_StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<_StatisticsScreen> {
  bool _isLoading = true;
  String? _error;
  List<_StatisticsRound> _rounds = const [];
  List<String> _handicapValues = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatistics());
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final responses = await Future.wait([
        widget.datosServidorService.obtenerTodasLasPartidas(widget.idUsuario),
        widget.datosServidorService.cojeConfiguracionCampos(
          widget.fieldId,
          'configuracion_tarjeta',
        ),
      ]);
      final rounds = _statisticsRoundsFromResponse(
        responses[0],
        idUsuario: widget.idUsuario,
        alias: widget.alias,
      )..sort((left, right) => right.sortValue.compareTo(left.sortValue));
      final handicapValues = _statisticsHandicapValuesFromResponse(
        responses[1],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _rounds = rounds;
        _handicapValues = handicapValues;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('obtener estadisticas fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = 'No se pudieron cargar las estadisticas.';
      });
    }
  }

  void _openRoundScorecard(_StatisticsRound round) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GolfScorecardScreen(
          idPartida: round.idPartida.isEmpty
              ? round.dateLabel
              : round.idPartida,
          jugadores: round.jugadores,
          initialPlayRowsJson: round.playRowsJson,
          datosServidorService: widget.datosServidorService,
          onExit: () => Navigator.of(context).pop(),
          onLeaveGame: () async {},
          onDestroyGame: () async {},
          isReadOnly: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Estadisticas',
      maxWidth: 980,
      showBackButton: true,
      backLabel: 'Salir',
      children: [
        if (_isLoading)
          const SizedBox(
            height: 190,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF567B37)),
            ),
          )
        else if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loadStatistics,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF567B37),
              side: const BorderSide(color: Color(0xFF567B37)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ] else if (_rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 42),
            child: Text(
              'No hay partidas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Color(0xFF6C737D)),
            ),
          )
        else
          _StatisticsTable(
            rounds: _rounds,
            handicapValues: _handicapValues,
            onViewRound: _openRoundScorecard,
          ),
      ],
    );
  }
}

class _StatisticsTable extends StatelessWidget {
  const _StatisticsTable({
    required this.rounds,
    required this.handicapValues,
    required this.onViewRound,
  });

  static const _actionWidth = 50.0;
  static const _dateWidth = 104.0;
  static const _differenceWidth = 72.0;
  static const _holeWidth = 38.0;
  static const _rowHeight = 44.0;
  static const _gridWidth =
      _actionWidth + _dateWidth + _differenceWidth + (_holeWidth * 18);

  final List<_StatisticsRound> rounds;
  final List<String> handicapValues;
  final ValueChanged<_StatisticsRound> onViewRound;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.54),
          border: Border.all(color: const Color.fromRGBO(128, 134, 144, 0.24)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _gridWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StatisticsHeaderRow(),
                for (final round in rounds)
                  _StatisticsDataRow(
                    round: round,
                    handicapValues: handicapValues,
                    onViewRound: onViewRound,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatisticsHeaderRow extends StatelessWidget {
  const _StatisticsHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2F5A44), Color(0xFF264836)],
        ),
      ),
      child: Row(
        children: [
          const _StatisticsHeaderCell(
            width: _StatisticsTable._actionWidth,
            label: '',
          ),
          _StatisticsHeaderCell(
            width: _StatisticsTable._dateWidth,
            label: 'Fecha',
            alignment: Alignment.centerLeft,
          ),
          const _StatisticsHeaderCell(
            width: _StatisticsTable._differenceWidth,
            label: 'Dif. HCP',
          ),
          for (var hole = 1; hole <= 18; hole++)
            _StatisticsHeaderCell(
              width: _StatisticsTable._holeWidth,
              label: '$hole',
            ),
        ],
      ),
    );
  }
}

class _StatisticsHeaderCell extends StatelessWidget {
  const _StatisticsHeaderCell({
    required this.width,
    required this.label,
    this.alignment = Alignment.center,
  });

  final double width;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF5F7F0),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatisticsDataRow extends StatelessWidget {
  const _StatisticsDataRow({
    required this.round,
    required this.handicapValues,
    required this.onViewRound,
  });

  final _StatisticsRound round;
  final List<String> handicapValues;
  final ValueChanged<_StatisticsRound> onViewRound;

  @override
  Widget build(BuildContext context) {
    final effectiveHandicapValues = round.handicapValues.isEmpty
        ? handicapValues
        : round.handicapValues;
    final handicapDifference = _statisticsHandicapDifference(
      round.holeValues,
      effectiveHandicapValues,
    );

    return SizedBox(
      height: _StatisticsTable._rowHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color.fromRGBO(128, 134, 144, 0.20)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _StatisticsTable._actionWidth,
              child: IconButton(
                onPressed: () => onViewRound(round),
                tooltip: 'Ver tarjeta',
                icon: const Icon(Icons.visibility, size: 20),
                color: const Color(0xFF235C3D),
                visualDensity: VisualDensity.compact,
              ),
            ),
            SizedBox(
              width: _StatisticsTable._dateWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  round.dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF545B66),
                  ),
                ),
              ),
            ),
            _StatisticsDifferenceCell(value: handicapDifference),
            for (var index = 0; index < 18; index++)
              _StatisticsScoreCell(
                value: round.holeValues[index],
                handicapValue: _statisticsHoleValue(
                  effectiveHandicapValues,
                  index,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsDifferenceCell extends StatelessWidget {
  const _StatisticsDifferenceCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final result = _statisticsDifferenceResult(value);

    return SizedBox(
      width: _StatisticsTable._differenceWidth,
      child: Center(
        child: Container(
          width: 58,
          height: 32,
          decoration: BoxDecoration(
            color: result == null
                ? const Color.fromRGBO(255, 255, 255, 0.84)
                : _statisticsScoreCellColor(result),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color.fromRGBO(128, 134, 144, 0.30),
            ),
          ),
          alignment: Alignment.center,
          child: value.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF545B66),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatisticsScoreCell extends StatelessWidget {
  const _StatisticsScoreCell({
    required this.value,
    required this.handicapValue,
  });

  final String value;
  final String handicapValue;

  @override
  Widget build(BuildContext context) {
    final result = _statisticsCellResult(value, handicapValue);
    final hasValue = value.trim().isNotEmpty;

    return SizedBox(
      width: _StatisticsTable._holeWidth,
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: result == null
                ? const Color.fromRGBO(255, 255, 255, 0.84)
                : _statisticsScoreCellColor(result),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color.fromRGBO(128, 134, 144, 0.30),
            ),
          ),
          alignment: Alignment.center,
          child: hasValue
              ? Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF545B66),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ReceiveInvitationScreen extends StatefulWidget {
  const _ReceiveInvitationScreen({
    required this.datosServidorService,
    required this.idPartidaInvitado,
    required this.idUsuarioInvitado,
    required this.onInvitationAccepted,
  });

  final DatosServidorService datosServidorService;
  final String idPartidaInvitado;
  final String idUsuarioInvitado;
  final Future<void> Function(String idPartida) onInvitationAccepted;

  @override
  State<_ReceiveInvitationScreen> createState() =>
      _ReceiveInvitationScreenState();
}

class _ReceiveInvitationScreenState extends State<_ReceiveInvitationScreen> {
  late final MobileScannerController _scannerController;
  String? _scannedValue;
  String? _error;
  String? _errorDetails;
  bool _isAcceptingInvitation = false;
  bool _isInvitationConfirmed = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    final value = capture.barcodes
        .map((barcode) => (barcode.rawValue ?? barcode.displayValue)?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (value == null || _isAcceptingInvitation || _isInvitationConfirmed) {
      return;
    }

    setState(() {
      _scannedValue = value;
      _error = null;
      _errorDetails = null;
      _isAcceptingInvitation = true;
    });

    unawaited(_scannerController.stop());
    unawaited(_acceptInvitation(value));
  }

  Future<void> _acceptInvitation(String scannedInvitation) async {
    final invitationData = _invitationDataFromQr(scannedInvitation);
    if (invitationData == null) {
      debugPrint('QR invitacion no valido: $scannedInvitation');
      _showAcceptInvitationError(
        'QR leido: "$scannedInvitation". Formato esperado: idPartida,idUsuario',
      );
      return;
    }

    final requestDetails =
        'idPartida_anfitrion=${invitationData.idPartidaAnfitrion}\n'
        'idPartida_invitado=${widget.idPartidaInvitado}\n'
        'idUsuario_anfitrion=${invitationData.idUsuarioAnfitrion}\n'
        'idUsuario_invitado=${widget.idUsuarioInvitado}';

    try {
      debugPrint(
        'aceptaInvitacion request: '
        'idPartida_anfitrion=${invitationData.idPartidaAnfitrion}, '
        'idPartida_invitado=${widget.idPartidaInvitado}, '
        'idUsuario_anfitrion=${invitationData.idUsuarioAnfitrion}, '
        'idUsuario_invitado=${widget.idUsuarioInvitado}',
      );
      final response = await widget.datosServidorService.aceptaInvitacion(
        idPartidaAnfitrion: invitationData.idPartidaAnfitrion,
        idPartidaInvitado: widget.idPartidaInvitado,
        idUsuarioAnfitrion: invitationData.idUsuarioAnfitrion,
        idUsuarioInvitado: widget.idUsuarioInvitado,
      );
      debugPrint('aceptaInvitacion response: $response');

      if (!_backendResponseIsOk(response)) {
        debugPrint('aceptaInvitacion respuesta no ok: $response');
        _showAcceptInvitationError('$requestDetails\nBackend: $response');
        return;
      }

      final playersResponse = await widget.datosServidorService
          .obtenerJugadoresPartida(invitationData.idPartidaAnfitrion);
      debugPrint(
        'obtenerJugadoresPartida(${invitationData.idPartidaAnfitrion}) '
        'tras aceptar: $playersResponse',
      );
      final players = _invitedPlayersFromResponse(playersResponse);
      final invitedUserId = widget.idUsuarioInvitado.trim();
      final isInvitedUserRegistered = players.any(
        (player) => player.idJugador.trim() == invitedUserId,
      );
      if (!isInvitedUserRegistered) {
        _showAcceptInvitationError(
          '$requestDetails\n'
          'acepta_invitacion: $response\n'
          'obtenerJugadoresPartida(${invitationData.idPartidaAnfitrion}): '
          '$playersResponse',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      await widget.onInvitationAccepted(invitationData.idPartidaAnfitrion);

      if (!mounted) {
        return;
      }

      setState(() {
        _scannedValue = invitationData.idPartidaAnfitrion;
        _errorDetails = null;
        _isAcceptingInvitation = false;
        _isInvitationConfirmed = true;
      });

      unawaited(SystemSound.play(SystemSoundType.click));
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_returnToPlayersAfterConfirmation());
    } catch (error) {
      debugPrint('aceptaInvitacion error: $error');
      if (!mounted) {
        return;
      }

      final details = switch (error) {
        DatosServidorException() => 'HTTP ${error.statusCode}: ${error.body}',
        _ => '$error',
      };
      _showAcceptInvitationError('$requestDetails\n$details');
    }
  }

  void _showAcceptInvitationError(
    String details, {
    String message = 'No se pudo aceptar la invitacion.',
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      _scannedValue = null;
      _isAcceptingInvitation = false;
      _error = message;
      _errorDetails = details;
    });
    unawaited(_scannerController.start());
  }

  Future<void> _returnToPlayersAfterConfirmation() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(_scannedValue);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _ReservationScreenFrame(
          title: 'Recibir la invitacion',
          showBackButton: true,
          children: [
            const Text(
              'escanea el QR de la invitacion',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF545B66),
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9D433D),
                ),
              ),
              if (_errorDetails != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _errorDetails!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9D433D),
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 340,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleDetection,
                  errorBuilder: (context, error) {
                    return const ColoredBox(
                      color: Color(0xFF1E2D28),
                      child: Center(
                        child: Icon(
                          Icons.videocam_off,
                          color: Color(0xFFF6F2EA),
                          size: 42,
                        ),
                      ),
                    );
                  },
                  placeholderBuilder: (context) {
                    return const ColoredBox(
                      color: Color(0xFF1E2D28),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF6F2EA),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        if (_isAcceptingInvitation)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: const Color.fromRGBO(3, 17, 12, 0.78),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F2EA),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.28),
                          blurRadius: 30,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 42,
                        vertical: 34,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF567B37)),
                          SizedBox(height: 18),
                          Text(
                            'Aceptando invitacion',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF567B37),
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
        if (_isInvitationConfirmed)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: const Color.fromRGBO(3, 17, 12, 0.78),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F2EA),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.28),
                          blurRadius: 30,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 42,
                        vertical: 34,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFF567B37),
                            size: 104,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'invitado',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF567B37),
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
}

class _InvitationQrData {
  const _InvitationQrData({
    required this.idPartidaAnfitrion,
    required this.idUsuarioAnfitrion,
  });

  final String idPartidaAnfitrion;
  final String idUsuarioAnfitrion;
}

_InvitationQrData? _invitationDataFromQr(String qrData) {
  final parts = qrData.split(',').map((part) => part.trim()).toList();
  if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return null;
  }

  return _InvitationQrData(
    idPartidaAnfitrion: parts[0],
    idUsuarioAnfitrion: parts[1],
  );
}

class _InvitePlayersScreen extends StatefulWidget {
  const _InvitePlayersScreen({
    required this.datosServidorService,
    required this.fieldId,
    required this.idUsuario,
    required this.loadValidInvitationGameId,
    required this.generateIdPartida,
    required this.onInvitationGameCreated,
    required this.onInvitationAccepted,
  });

  final DatosServidorService datosServidorService;
  final String fieldId;
  final String idUsuario;
  final Future<String?> Function() loadValidInvitationGameId;
  final String Function() generateIdPartida;
  final Future<void> Function(String idPartida) onInvitationGameCreated;
  final Future<void> Function(String idPartida) onInvitationAccepted;

  @override
  State<_InvitePlayersScreen> createState() => _InvitePlayersScreenState();
}

class _InvitePlayersScreenState extends State<_InvitePlayersScreen> {
  static const _playersRefreshDelay = Duration(seconds: 5);

  Timer? _playersRefreshTimer;
  int _playersRefreshGeneration = 0;
  bool _isLoading = true;
  bool _isShowingQr = false;
  bool _isStartingGame = false;
  final Set<String> _deletingPlayerIds = <String>{};
  String? _idPartida;
  String? _error;
  List<_InvitedPlayer> _players = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlayersOrCreateGame());
  }

  @override
  void dispose() {
    _stopPlayersRefreshPolling();
    super.dispose();
  }

  Future<void> _loadPlayersOrCreateGame() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final invitationGameId = await widget.loadValidInvitationGameId();
      final validInvitationGameId = invitationGameId?.trim();
      final hasValidInvitationGame =
          validInvitationGameId != null && validInvitationGameId.isNotEmpty;
      var idPartida = hasValidInvitationGame
          ? validInvitationGameId
          : widget.generateIdPartida();
      final playersResponse = await _fetchPlayersResponse(idPartida);
      var players = playersResponse.players;

      if (!hasValidInvitationGame) {
        final createResponse = await widget.datosServidorService.creaPartida(
          widget.fieldId,
          idPartida,
        );
        debugPrint('creaPartida($idPartida): $createResponse');
        await widget.onInvitationGameCreated(idPartida);
      }

      if (!mounted) {
        return;
      }

      if (playersResponse.hasExpiredStarted) {
        await _resetCurrentUserInvitationGame(
          previousIdPartida: idPartida,
          reason: 'partida caducada',
        );
        _startPlayersRefreshPolling();
        return;
      }

      if (playersResponse.hasStarted) {
        _openScorecardForPlayers(idPartida: idPartida, players: players);
        return;
      }

      if (await _resetCurrentUserGameIfMissing(players, idPartida: idPartida)) {
        _startPlayersRefreshPolling();
        return;
      }

      setState(() {
        _idPartida = idPartida;
        _players = players;
        _isLoading = false;
      });
      _startPlayersRefreshPolling();
    } catch (error) {
      debugPrint('preparar invitacion jugadores fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = 'No se pudo preparar la invitacion de jugadores.';
      });
    }
  }

  Future<_InvitedPlayersResponse> _fetchPlayersResponse(
    String idPartida,
  ) async {
    final response = await widget.datosServidorService.obtenerJugadoresPartida(
      idPartida,
    );
    debugPrint('obtenerJugadoresPartida($idPartida): $response');
    return _invitedPlayersResponseFromResponse(response);
  }

  Future<List<_InvitedPlayer>> _fetchPlayers(String idPartida) async {
    final response = await _fetchPlayersResponse(idPartida);
    return response.players;
  }

  void _startPlayersRefreshPolling() {
    final generation = ++_playersRefreshGeneration;
    _scheduleNextPlayersRefresh(generation);
  }

  void _stopPlayersRefreshPolling() {
    _playersRefreshGeneration++;
    _playersRefreshTimer?.cancel();
    _playersRefreshTimer = null;
  }

  void _scheduleNextPlayersRefresh(int generation) {
    _playersRefreshTimer?.cancel();
    if (!mounted ||
        generation != _playersRefreshGeneration ||
        (_idPartida?.trim().isEmpty ?? true)) {
      return;
    }

    _playersRefreshTimer = Timer(_playersRefreshDelay, () {
      unawaited(_refreshPlayers(pollingGeneration: generation));
    });
  }

  void _refreshPlayersAndContinuePolling() {
    final generation = ++_playersRefreshGeneration;
    _playersRefreshTimer?.cancel();
    unawaited(_refreshPlayers(pollingGeneration: generation));
  }

  Future<void> _refreshPlayers({int? pollingGeneration}) async {
    final idPartida = _idPartida;
    if (idPartida == null || idPartida.isEmpty) {
      return;
    }

    try {
      final playersResponse = await _fetchPlayersResponse(idPartida);
      final players = playersResponse.players;
      if (!mounted) {
        return;
      }

      if (playersResponse.hasExpiredStarted) {
        await _resetCurrentUserInvitationGame(
          previousIdPartida: idPartida,
          reason: 'partida caducada',
        );
        return;
      }

      if (playersResponse.hasStarted) {
        _openScorecardForPlayers(idPartida: idPartida, players: players);
        return;
      }

      if (await _resetCurrentUserGameIfMissing(players, idPartida: idPartida)) {
        return;
      }

      setState(() {
        _players = players;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo actualizar la lista de jugadores.';
      });
    } finally {
      if (pollingGeneration != null &&
          mounted &&
          pollingGeneration == _playersRefreshGeneration) {
        _scheduleNextPlayersRefresh(pollingGeneration);
      }
    }
  }

  void _showQr() {
    if (_idPartida == null) {
      return;
    }

    setState(() {
      _isShowingQr = true;
    });
  }

  void _hideQr() {
    setState(() {
      _isShowingQr = false;
    });
    _refreshPlayersAndContinuePolling();
  }

  Future<void> _openInvitationScanner() async {
    final idPartida = _idPartida;
    if (idPartida == null || idPartida.isEmpty) {
      return;
    }

    final acceptedIdPartida = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (context) => _ReceiveInvitationScreen(
          datosServidorService: widget.datosServidorService,
          idPartidaInvitado: idPartida,
          idUsuarioInvitado: widget.idUsuario,
          onInvitationAccepted: widget.onInvitationAccepted,
        ),
      ),
    );
    if (!mounted) {
      return;
    }

    final hostIdPartida = acceptedIdPartida?.trim();
    if (hostIdPartida == null || hostIdPartida.isEmpty) {
      _refreshPlayersAndContinuePolling();
      return;
    }

    setState(() {
      _idPartida = hostIdPartida;
      _players = const [];
      _error = null;
    });

    _refreshPlayersAndContinuePolling();
  }

  bool _isCurrentUser(_InvitedPlayer player) {
    return player.idJugador.trim() == widget.idUsuario.trim();
  }

  bool _playersContainCurrentUser(List<_InvitedPlayer> players) {
    return players.any(_isCurrentUser);
  }

  Future<bool> _resetCurrentUserGameIfMissing(
    List<_InvitedPlayer> players, {
    required String idPartida,
  }) async {
    if (players.isEmpty || _playersContainCurrentUser(players)) {
      return false;
    }

    debugPrint(
      'Usuario actual ${widget.idUsuario} no encontrado en '
      'obtenerJugadoresPartida($idPartida); se genera idPartida.',
    );
    await _resetCurrentUserInvitationGame(previousIdPartida: idPartida);
    return true;
  }

  void _openScorecardForPlayers({
    required String idPartida,
    required List<_InvitedPlayer> players,
  }) {
    _stopPlayersRefreshPolling();
    Navigator.of(context).pop(
      _GameSession(
        idPartida: idPartida,
        idCampo: widget.fieldId,
        jugadores: players.length.toString(),
        playRowsJson: _createPlayRowsJsonForPlayers(players),
      ),
    );
  }

  Future<void> _confirmAndRemovePlayer(_InvitedPlayer player) async {
    final idUsuario = player.idJugador.trim();
    if (idUsuario.isEmpty) {
      return;
    }

    final isCurrentUser = _isCurrentUser(player);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(
            isCurrentUser
                ? 'te vas a salir de la Partida, seguro ?'
                : 'Vas a eliminar a ${player.displayName}, seguro ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Si'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _removePlayer(player);
  }

  Future<void> _removePlayer(_InvitedPlayer player) async {
    final idPartida = _idPartida?.trim() ?? '';
    final idUsuario = player.idJugador.trim();
    if (idPartida.isEmpty || idUsuario.isEmpty) {
      return;
    }

    final isCurrentUser = _isCurrentUser(player);
    _stopPlayersRefreshPolling();
    setState(() {
      _deletingPlayerIds.add(idUsuario);
      _error = null;
    });

    try {
      final response = await widget.datosServidorService.quitaJugadorPartida(
        idPartida: idPartida,
        idUsuario: idUsuario,
      );
      debugPrint(
        'quitaJugadorPartida(idPartida: $idPartida, idUsuario: $idUsuario): '
        '$response',
      );
      if (!_backendResponseIsOk(response)) {
        throw FormatException('Respuesta no valida: $response');
      }

      if (isCurrentUser) {
        await _resetCurrentUserInvitationGame(previousIdPartida: idPartida);
      } else {
        await _refreshPlayers();
      }
    } catch (error) {
      debugPrint('quitaJugadorPartida fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo eliminar el jugador.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingPlayerIds.remove(idUsuario);
        });
        _startPlayersRefreshPolling();
      }
    }
  }

  Future<void> _resetCurrentUserInvitationGame({
    String? previousIdPartida,
    String reason = 'salir',
  }) async {
    final previousId = previousIdPartida?.trim() ?? '';
    var newIdPartida = widget.generateIdPartida();
    var attempt = 0;
    while (attempt < 5 && newIdPartida == previousId) {
      newIdPartida = widget.generateIdPartida();
      attempt++;
    }
    if (newIdPartida == previousId && newIdPartida.isNotEmpty) {
      final replacement = newIdPartida.endsWith('A') ? 'B' : 'A';
      newIdPartida =
          '${newIdPartida.substring(0, newIdPartida.length - 1)}$replacement';
    }

    final createResponse = await widget.datosServidorService.creaPartida(
      widget.fieldId,
      newIdPartida,
    );
    debugPrint('creaPartida($newIdPartida) tras $reason: $createResponse');
    await widget.onInvitationGameCreated(newIdPartida);
    await widget.onInvitationAccepted(newIdPartida);

    final players = await _fetchPlayers(newIdPartida);
    if (!mounted) {
      return;
    }

    setState(() {
      _idPartida = newIdPartida;
      _players = players;
      _isLoading = false;
      _error = null;
    });
  }

  Future<void> _startGame() async {
    final idPartida = _idPartida?.trim() ?? '';
    if (idPartida.isEmpty || _players.isEmpty || _isStartingGame) {
      return;
    }

    _stopPlayersRefreshPolling();
    setState(() {
      _isStartingGame = true;
      _error = null;
    });

    try {
      final response = await widget.datosServidorService.empezarPartida(
        idPartida,
      );
      debugPrint('empezarPartida($idPartida): $response');
      if (!_backendResponseIsOk(response)) {
        throw FormatException('Respuesta no valida: $response');
      }

      if (!mounted) {
        return;
      }

      _openScorecardForPlayers(idPartida: idPartida, players: _players);
    } catch (error) {
      debugPrint('empezarPartida fallo: $error');
      if (await _openScorecardIfGameStarted(idPartida)) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo empezar la partida.';
      });
      _startPlayersRefreshPolling();
    } finally {
      if (mounted) {
        setState(() {
          _isStartingGame = false;
        });
      }
    }
  }

  Future<bool> _openScorecardIfGameStarted(String idPartida) async {
    try {
      final playersResponse = await _fetchPlayersResponse(idPartida);
      if (!mounted) {
        return true;
      }

      if (playersResponse.hasExpiredStarted) {
        await _resetCurrentUserInvitationGame(
          previousIdPartida: idPartida,
          reason: 'partida caducada',
        );
        _startPlayersRefreshPolling();
        return true;
      }

      if (!playersResponse.hasStarted) {
        return false;
      }

      _openScorecardForPlayers(
        idPartida: idPartida,
        players: playersResponse.players,
      );
      return true;
    } catch (error) {
      debugPrint('comprobar partida empezada fallo: $error');
      return false;
    }
  }

  String get _invitationQrData {
    final idPartida = _idPartida?.trim() ?? '';
    if (idPartida.isEmpty) {
      return '';
    }

    return '$idPartida,${widget.idUsuario.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Jugadores',
      showBackButton: true,
      onBack: _isShowingQr ? _hideQr : () => Navigator.of(context).pop(),
      children: _isShowingQr ? _buildQrChildren() : _buildPlayerListChildren(),
    );
  }

  List<Widget> _buildPlayerListChildren() {
    if (_isLoading) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: CircularProgressIndicator(color: Color(0xFF567B37)),
          ),
        ),
      ];
    }

    return [
      if (_error != null) ...[
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
        ),
        const SizedBox(height: 16),
      ],
      for (final player in _players) ...[
        _InvitedPlayerTile(
          player: player,
          isDeleting: _deletingPlayerIds.contains(player.idJugador.trim()),
          onDelete: player.idJugador.trim().isEmpty
              ? null
              : () => unawaited(_confirmAndRemovePlayer(player)),
        ),
        const SizedBox(height: 10),
      ],
      if (_players.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Sin jugadores',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Color(0xFF6C737D)),
          ),
        ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _idPartida == null ? null : _showQr,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF567B37),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Invitar a jugadores'),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: _idPartida == null ? null : _openInvitationScanner,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF567B37),
          side: const BorderSide(color: Color(0xFF567B37)),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Recibir la invitacion'),
      ),
      if (_players.isNotEmpty) ...[
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _isStartingGame ? null : () => unawaited(_startGame()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B3A34),
            disabledBackgroundColor: const Color(0xFFC7A09C),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: _isStartingGame
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sports_golf),
          label: Text(_isStartingGame ? 'Empezando...' : 'Empezar la Partida'),
        ),
      ],
    ];
  }

  List<Widget> _buildQrChildren() {
    return [
      Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: QrImageView(
              data: _invitationQrData,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      SelectableText(
        _invitationQrData,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF545B66)),
      ),
    ];
  }
}

class _InvitedPlayerTile extends StatelessWidget {
  const _InvitedPlayerTile({
    required this.player,
    required this.isDeleting,
    required this.onDelete,
  });

  final _InvitedPlayer player;
  final bool isDeleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECE1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D2C7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFF567B37)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              player.displayName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF545B66),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            height: 42,
            child: isDeleting
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF9D433D),
                    ),
                  )
                : IconButton(
                    onPressed: onDelete,
                    tooltip: 'Eliminar',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFF9D433D),
                    ),
                  ),
          ),
        ],
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
      showBackButton: true,
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
      title: 'Reservar Salida',
      maxWidth: 620,
      showBackButton: true,
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
      showBackButton: true,
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

class _LeaguesScreen extends StatefulWidget {
  const _LeaguesScreen({
    required this.datosServidorService,
    required this.idUsuario,
    required this.pendingInvitationLeagueIds,
    required this.onInvitationDecisionChanged,
  });

  final DatosServidorService datosServidorService;
  final String idUsuario;
  final Set<String> pendingInvitationLeagueIds;
  final VoidCallback onInvitationDecisionChanged;

  @override
  State<_LeaguesScreen> createState() => _LeaguesScreenState();
}

class _LeaguesScreenState extends State<_LeaguesScreen> {
  Timer? _pendingLeaguePulseTimer;
  late final Set<String> _pendingInvitationLeagueIds;
  bool _isLoading = true;
  bool _pendingLeaguePulseOn = false;
  String? _error;
  List<_LeagueSummary> _leagues = const [];
  String? _decidingLeagueId;

  @override
  void initState() {
    super.initState();
    _pendingInvitationLeagueIds = Set<String>.of(
      widget.pendingInvitationLeagueIds,
    );
    unawaited(_loadLeagues());
  }

  @override
  void dispose() {
    _pendingLeaguePulseTimer?.cancel();
    super.dispose();
  }

  bool _shouldPulseLeague(_LeagueSummary league) {
    return league.isPending ||
        _pendingInvitationLeagueIds.contains(league.idLiguilla);
  }

  void _syncPendingLeaguePulseTimer() {
    final shouldPulse = _leagues.any(_shouldPulseLeague);
    if (!shouldPulse) {
      _pendingLeaguePulseTimer?.cancel();
      _pendingLeaguePulseTimer = null;
      if (_pendingLeaguePulseOn) {
        setState(() {
          _pendingLeaguePulseOn = false;
        });
      }
      return;
    }

    if (_pendingLeaguePulseTimer != null) {
      return;
    }

    setState(() {
      _pendingLeaguePulseOn = true;
    });
    _pendingLeaguePulseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_leagues.any(_shouldPulseLeague)) {
        _pendingLeaguePulseTimer?.cancel();
        _pendingLeaguePulseTimer = null;
        return;
      }

      setState(() {
        _pendingLeaguePulseOn = !_pendingLeaguePulseOn;
      });
    });
  }

  Future<void> _loadLeagues() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.datosServidorService.obtenerLiguillas(
        widget.idUsuario,
      );
      final leagues = _leaguesFromResponse(
        response,
      ).where((league) => league.isVisibleFor(widget.idUsuario)).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _leagues = leagues;
        _isLoading = false;
      });
      _syncPendingLeaguePulseTimer();
    } catch (error) {
      debugPrint('obtenerLiguillas fallo: $error');
      if (error is DatosServidorException) {
        debugPrint('obtenerLiguillas backend body: ${error.body}');
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = 'No se pudieron cargar las liguillas.';
      });
    }
  }

  Future<void> _openCreateLeague() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => _CreateLeagueScreen(
          datosServidorService: widget.datosServidorService,
          idUsuario: widget.idUsuario,
        ),
      ),
    );
    if (!mounted || created != true) {
      return;
    }

    _showLeagueSnackBar('Liguilla creada ok');
    await _loadLeagues();
  }

  Future<void> _confirmLeaveAcceptedLeague(_LeagueSummary league) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Seguro que te das de baja de la liguilla ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Si'),
            ),
          ],
        );
      },
    );

    if (shouldLeave != true) {
      return;
    }

    await _sendParticipationDecision(league, 'N');
  }

  void _openLeagueParticipants(_LeagueSummary league) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _LeagueParticipantsScreen(
          datosServidorService: widget.datosServidorService,
          league: league,
        ),
      ),
    );
  }

  Future<void> _openLeagueInvitation(_LeagueSummary league) async {
    final invited = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => _LeagueInvitationScreen(
          datosServidorService: widget.datosServidorService,
          league: league,
          idUsuario: widget.idUsuario,
        ),
      ),
    );
    if (!mounted || invited != true) {
      return;
    }

    _showLeagueSnackBar('Invitación ok');
  }

  Future<void> _sendParticipationDecision(
    _LeagueSummary league,
    String decision,
  ) async {
    setState(() {
      _decidingLeagueId = league.idLiguilla;
      _error = null;
    });

    try {
      final response = await widget.datosServidorService.decisionParticipacion(
        idLiguilla: league.idLiguilla,
        idUsuario: widget.idUsuario,
        decision: decision,
      );
      debugPrint('decisionParticipacion: $response');
      if (!_backendResponseIsOk(response)) {
        throw FormatException('Respuesta no valida: $response');
      }

      if (!mounted) {
        return;
      }

      _showLeagueSnackBar(
        decision == 'S'
            ? 'Apuntado ok a la liguilla'
            : 'Dado de baja de la liguilla',
      );
      await _loadLeagues();
      if (!mounted) {
        return;
      }
      _applyParticipationDecisionLocally(league, decision);
      widget.onInvitationDecisionChanged();
    } catch (error) {
      debugPrint('decisionParticipacion fallo: $error');
      if (error is DatosServidorException) {
        debugPrint('decisionParticipacion backend body: ${error.body}');
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo registrar la decision.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _decidingLeagueId = null;
        });
      }
    }
  }

  void _applyParticipationDecisionLocally(
    _LeagueSummary league,
    String decision,
  ) {
    final leagueIndex = _leagues.indexWhere(
      (item) => item.idLiguilla == league.idLiguilla,
    );
    if (leagueIndex == -1) {
      return;
    }

    final updatedLeagues = List<_LeagueSummary>.of(_leagues);
    final updatedLeague = updatedLeagues[leagueIndex].copyWith(
      pendienteDecidir: 'N',
      fechaRechazo: decision == 'N' ? 'S' : '',
    );

    setState(() {
      _pendingInvitationLeagueIds.remove(league.idLiguilla);
      if (updatedLeague.isVisibleFor(widget.idUsuario)) {
        updatedLeagues[leagueIndex] = updatedLeague;
        _leagues = updatedLeagues;
      } else {
        _leagues = [
          for (final item in updatedLeagues)
            if (item.idLiguilla != league.idLiguilla) item,
        ];
      }
    });
    _syncPendingLeaguePulseTimer();
  }

  void _showLeagueSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF235C3D),
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Liguillas',
      maxWidth: 680,
      showBackButton: true,
      backLabel: 'Salir',
      children: [
        OutlinedButton.icon(
          onPressed: _openCreateLeague,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6B432D),
            side: const BorderSide(color: Color(0xFF6B432D)),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Crea Liguilla'),
        ),
        const SizedBox(height: 18),
        if (_isLoading)
          const SizedBox(
            height: 170,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF567B37)),
            ),
          )
        else if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loadLeagues,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF567B37),
              side: const BorderSide(color: Color(0xFF567B37)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ] else if (_leagues.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Text(
              'No hay liguillas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Color(0xFF6C737D)),
            ),
          )
        else
          for (final league in _leagues) ...[
            _LeagueListItem(
              league: league,
              isDeciding: _decidingLeagueId == league.idLiguilla,
              shouldPulse: _shouldPulseLeague(league),
              pulseOn: _pendingLeaguePulseOn,
              canInvite: league.canBeInvitedBy(widget.idUsuario),
              onAcceptInvitation: () => _sendParticipationDecision(league, 'S'),
              onRejectInvitation: () => _sendParticipationDecision(league, 'N'),
              onLeaveAcceptedLeague: () => _confirmLeaveAcceptedLeague(league),
              onRejoinLeague: () => _sendParticipationDecision(league, 'S'),
              onViewParticipants: () => _openLeagueParticipants(league),
              onInvite: () => _openLeagueInvitation(league),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _LeagueListItem extends StatelessWidget {
  const _LeagueListItem({
    required this.league,
    required this.isDeciding,
    required this.shouldPulse,
    required this.pulseOn,
    required this.canInvite,
    required this.onAcceptInvitation,
    required this.onRejectInvitation,
    required this.onLeaveAcceptedLeague,
    required this.onRejoinLeague,
    required this.onViewParticipants,
    required this.onInvite,
  });

  final _LeagueSummary league;
  final bool isDeciding;
  final bool shouldPulse;
  final bool pulseOn;
  final bool canInvite;
  final VoidCallback onAcceptInvitation;
  final VoidCallback onRejectInvitation;
  final VoidCallback onLeaveAcceptedLeague;
  final VoidCallback onRejoinLeague;
  final VoidCallback onViewParticipants;
  final VoidCallback onInvite;

  void _showLeagueInformation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _LeagueInformationDialog(league: league),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creator = league.alias.isEmpty ? 'Usuario' : league.alias;
    final statusLabels = league.statusLabelsWithoutPending;

    final backgroundColor = shouldPulse && pulseOn
        ? const Color(0xFFFFDADA)
        : const Color.fromRGBO(255, 255, 255, 0.78);

    return AnimatedContainer(
      key: ValueKey('league_item_${league.idLiguilla}'),
      duration: const Duration(seconds: 1),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D2C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeagueTitleLabel(
            title: league.titulo,
            emptyTitle: 'Liguilla sin titulo',
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Creada por $creator',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6C737D),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _LeagueInformationButton(
                onPressed: () => _showLeagueInformation(context),
              ),
            ],
          ),
          if (league.movil.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Movil: ${league.movil}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF6C737D)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeagueParticipantsButton(onPressed: onViewParticipants),
                  if (league.isRejected) ...[
                    const SizedBox(height: 8),
                    _LeagueRejoinButton(
                      isLoading: isDeciding,
                      onPressed: onRejoinLeague,
                    ),
                  ],
                ],
              ),
              if (canInvite) _LeagueInviteButton(onPressed: onInvite),
              if (league.isPending) ...[
                _LeagueAcceptInvitationButton(
                  isLoading: isDeciding,
                  onPressed: onAcceptInvitation,
                ),
                _LeagueRejectInvitationButton(
                  isLoading: isDeciding,
                  onPressed: onRejectInvitation,
                ),
              ],
              if (!league.isRejected)
                for (final label in statusLabels)
                  _LeagueStatusPill(label: label),
              if (league.isAccepted)
                _LeagueLeaveButton(
                  isLoading: isDeciding,
                  onPressed: onLeaveAcceptedLeague,
                ),
            ],
          ),
          if (league.isRejected && statusLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(child: _LeagueStatusPill(label: statusLabels.first)),
          ],
        ],
      ),
    );
  }
}

class _LeagueInformationButton extends StatelessWidget {
  const _LeagueInformationButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Información de liguilla',
      icon: const Icon(Icons.info_outline, size: 20),
      color: const Color(0xFF567B37),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
    );
  }
}

class _LeagueInformationDialog extends StatelessWidget {
  const _LeagueInformationDialog({required this.league});

  final _LeagueSummary league;

  @override
  Widget build(BuildContext context) {
    final informationItems = _leagueInformationItems(league);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF567B37)),
          SizedBox(width: 10),
          Expanded(child: Text('Información de liguilla')),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < informationItems.length; index++) ...[
                _LeagueInformationRow(item: informationItems[index]),
                if (index != informationItems.length - 1)
                  const Divider(height: 18, color: Color(0xFFE4DDD3)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _LeagueInformationRow extends StatelessWidget {
  const _LeagueInformationRow({required this.item});

  final _LeagueInformationItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6C737D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF545B66),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeagueInformationItem {
  const _LeagueInformationItem({required this.label, required this.value});

  final String label;
  final String value;
}

List<_LeagueInformationItem> _leagueInformationItems(_LeagueSummary league) {
  return [
    _LeagueInformationItem(
      label: 'Titulo',
      value: _leagueTextValue(league.titulo, emptyLabel: 'Sin titulo'),
    ),
    _LeagueInformationItem(
      label: 'Jornadas',
      value: _leagueNumberValue(league.jornadas),
    ),
    _LeagueInformationItem(
      label: 'Minimo jugadores por jornada',
      value: _leagueNumberValue(league.minimoJugadoresJornada),
    ),
    _LeagueInformationItem(
      label: 'Participacion minima jugador',
      value: _leagueNumberValue(league.participacionMinimaJugador),
    ),
    _LeagueInformationItem(
      label: 'Los jugadores pueden invitar',
      value: _leagueYesNoValue(league.puedenInvitar),
    ),
    _LeagueInformationItem(
      label: 'Aplicar handicap en partidas',
      value: _leagueYesNoValue(league.aplicarHandicapPartidas),
    ),
  ];
}

String _leagueTextValue(String value, {String emptyLabel = 'Sin dato'}) {
  final trimmedValue = value.trim();
  return trimmedValue.isEmpty ? emptyLabel : trimmedValue;
}

String _leagueNumberValue(String value) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty) {
    return 'Sin dato';
  }

  return trimmedValue == '-1' ? 'Indefinido' : trimmedValue;
}

String _leaguePlainNumberValue(String value) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty) {
    return '';
  }

  final number = double.tryParse(trimmedValue);
  if (number != null && number == number.roundToDouble()) {
    return number.toInt().toString();
  }

  return trimmedValue;
}

String _leagueYesNoValue(String value) {
  final normalizedValue = value.trim().toUpperCase();
  if (normalizedValue == '1' ||
      normalizedValue == 'S' ||
      normalizedValue == 'SI' ||
      normalizedValue == 'SÍ' ||
      normalizedValue == 'TRUE') {
    return 'Si';
  }

  if (normalizedValue == '0' ||
      normalizedValue == 'N' ||
      normalizedValue == 'NO' ||
      normalizedValue == 'FALSE') {
    return 'No';
  }

  return 'Sin dato';
}

class _LeagueStatusPill extends StatelessWidget {
  const _LeagueStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1DDC3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF486536),
          ),
        ),
      ),
    );
  }
}

class _LeagueTitleLabel extends StatelessWidget {
  const _LeagueTitleLabel({
    required this.title,
    required this.emptyTitle,
    this.textAlign = TextAlign.left,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final String title;
  final String emptyTitle;
  final TextAlign textAlign;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title.trim().isEmpty ? emptyTitle : title.trim();

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.emoji_events, color: Color(0xFFB9834F), size: 21),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            effectiveTitle,
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF545B66),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeagueParticipantsButton extends StatelessWidget {
  const _LeagueParticipantsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF235C3D),
        side: const BorderSide(color: Color(0xFF8AA879)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.groups, size: 17),
      label: const Text(
        'Participantes',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LeagueInviteButton extends StatelessWidget {
  const _LeagueInviteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF567B37),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.person_add, size: 17),
      label: const Text(
        'Invitar',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LeagueRejoinButton extends StatelessWidget {
  const _LeagueRejoinButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF235C3D),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: isLoading
          ? const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.replay, size: 15),
      label: const Text(
        'Reapuntarse a la liguilla',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LeagueLeaveButton extends StatelessWidget {
  const _LeagueLeaveButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6C737D),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: isLoading
          ? const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout, size: 15),
      label: const Text(
        'Darse de baja',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LeagueAcceptInvitationButton extends StatelessWidget {
  const _LeagueAcceptInvitationButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF235C3D),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check, size: 20),
      label: const Text(
        'Aceptar invitación',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LeagueRejectInvitationButton extends StatelessWidget {
  const _LeagueRejectInvitationButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF9D433D),
        side: const BorderSide(color: Color(0xFFC77A72)),
        backgroundColor: const Color(0xFFFFF1EF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.close, size: 20),
      label: const Text(
        'Rechazar invitación',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LeagueParticipantsScreen extends StatefulWidget {
  const _LeagueParticipantsScreen({
    required this.datosServidorService,
    required this.league,
  });

  final DatosServidorService datosServidorService;
  final _LeagueSummary league;

  @override
  State<_LeagueParticipantsScreen> createState() =>
      _LeagueParticipantsScreenState();
}

class _LeagueParticipantsScreenState extends State<_LeagueParticipantsScreen> {
  bool _isLoading = true;
  String? _error;
  List<_LeagueParticipant> _participants = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadParticipants());
  }

  Future<void> _loadParticipants() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.datosServidorService
          .obtenerInvitadosLiguilla(widget.league.idLiguilla);
      final participants = _leagueParticipantsFromResponse(response);

      if (!mounted) {
        return;
      }

      setState(() {
        _participants = participants;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('obtenerInvitadosLiguilla fallo: $error');
      if (error is DatosServidorException) {
        debugPrint('obtenerInvitadosLiguilla backend body: ${error.body}');
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = 'No se pudieron cargar los participantes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagueTitle = widget.league.titulo.trim();
    final showInitialHandicap =
        _leagueYesNoValue(widget.league.aplicarHandicapPartidas) == 'Si';

    return _ReservationScreenFrame(
      title: 'Participantes',
      maxWidth: 680,
      showBackButton: true,
      backLabel: 'Volver',
      children: [
        if (leagueTitle.isNotEmpty) ...[
          _LeagueTitleLabel(
            title: leagueTitle,
            emptyTitle: 'Liguilla',
            textAlign: TextAlign.center,
            mainAxisAlignment: MainAxisAlignment.center,
          ),
          const SizedBox(height: 18),
        ],
        if (_isLoading)
          const SizedBox(
            height: 170,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF567B37)),
            ),
          )
        else if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loadParticipants,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF567B37),
              side: const BorderSide(color: Color(0xFF567B37)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ] else if (_participants.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Text(
              'No hay participantes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Color(0xFF6C737D)),
            ),
          )
        else
          for (final participant in _participants) ...[
            _LeagueParticipantItem(
              participant: participant,
              showInitialHandicap: showInitialHandicap,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _LeagueParticipantItem extends StatelessWidget {
  const _LeagueParticipantItem({
    required this.participant,
    required this.showInitialHandicap,
  });

  final _LeagueParticipant participant;
  final bool showInitialHandicap;

  @override
  Widget build(BuildContext context) {
    final initialHandicap = _leaguePlainNumberValue(
      participant.handicapInicial,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D2C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            participant.alias.isEmpty ? 'Sin alias' : participant.alias,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF545B66),
            ),
          ),
          if (participant.movil.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Movil: ${participant.movil}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF6C737D)),
            ),
          ],
          if (showInitialHandicap && initialHandicap.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Handicap inicial: $initialHandicap',
              style: const TextStyle(fontSize: 14, color: Color(0xFF6C737D)),
            ),
          ],
          const SizedBox(height: 10),
          _LeagueParticipantStatusLabel(participant: participant),
        ],
      ),
    );
  }
}

class _LeagueParticipantStatusLabel extends StatelessWidget {
  const _LeagueParticipantStatusLabel({required this.participant});

  final _LeagueParticipant participant;

  @override
  Widget build(BuildContext context) {
    final color = participant.hasRejected
        ? const Color(0xFF9D433D)
        : participant.isPending
        ? const Color(0xFF8A6B2F)
        : const Color(0xFF486536);
    final icon = participant.hasRejected
        ? Icons.cancel_outlined
        : participant.isPending
        ? Icons.schedule
        : Icons.check_circle_outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          participant.statusLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _LeagueInvitationScreen extends StatefulWidget {
  const _LeagueInvitationScreen({
    required this.datosServidorService,
    required this.league,
    required this.idUsuario,
  });

  final DatosServidorService datosServidorService;
  final _LeagueSummary league;
  final String idUsuario;

  @override
  State<_LeagueInvitationScreen> createState() =>
      _LeagueInvitationScreenState();
}

class _LeagueInvitationScreenState extends State<_LeagueInvitationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  bool _isSending = false;
  String? _inviteError;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _submitInvitation() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSending = true;
      _inviteError = null;
    });

    try {
      final response = await widget.datosServidorService.enviaInvitacion(
        idLiguilla: widget.league.idLiguilla,
        movil: _mobileController.text.trim(),
        invitadorPor: widget.idUsuario,
      );
      debugPrint('enviaInvitacion: $response');
      if (!_backendResponseIsOk(response)) {
        if (!mounted) {
          return;
        }

        setState(() {
          _inviteError = _backendResponseMessage(response);
          _isSending = false;
        });
        return;
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('enviaInvitacion fallo: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        final backendBody = error is DatosServidorException
            ? error.body.trim()
            : '';
        _inviteError = backendBody.isNotEmpty
            ? _backendResponseMessage(backendBody)
            : error.toString();
        _isSending = false;
      });
    }
  }

  String? _requiredMobile(String? value) {
    return (value?.trim().isEmpty ?? true) ? 'Campo obligatorio' : null;
  }

  @override
  Widget build(BuildContext context) {
    final leagueTitle = widget.league.titulo.trim();

    return _ReservationScreenFrame(
      title: 'Invitacion',
      maxWidth: 560,
      showBackButton: true,
      backLabel: 'Cancelar',
      children: [
        if (leagueTitle.isNotEmpty) ...[
          _LeagueTitleLabel(
            title: leagueTitle,
            emptyTitle: 'Liguilla',
            textAlign: TextAlign.center,
            mainAxisAlignment: MainAxisAlignment.center,
          ),
          const SizedBox(height: 18),
        ],
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(11),
            ],
            validator: _requiredMobile,
            decoration: InputDecoration(
              labelText: 'Movil',
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
        if (_inviteError != null) ...[
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 170),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1EF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0A39E)),
            ),
            child: SingleChildScrollView(
              child: Text(
                _inviteError!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9D433D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _isSending ? null : _submitInvitation,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF567B37),
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: _isSending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send),
          label: Text(_isSending ? 'Invitando...' : 'Invitar'),
        ),
      ],
    );
  }
}

class _CreateLeagueScreen extends StatefulWidget {
  const _CreateLeagueScreen({
    required this.datosServidorService,
    required this.idUsuario,
  });

  final DatosServidorService datosServidorService;
  final String idUsuario;

  @override
  State<_CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends State<_CreateLeagueScreen> {
  static const _applyHandicapHelpTitle = 'Aplicar handicap en las partidas';
  static const _applyHandicapHelpMessage =
      'Partiendo del handicap inicial de cada jugador, se irá '
      'modificando segun los resultados de cada partida jugada '
      '(Se debe introducir handicap inicial por jugador)';

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _roundsController = TextEditingController();
  final _minimumPlayersController = TextEditingController();
  final _minimumPlayerParticipationController = TextEditingController();
  final _invitationMessageController = TextEditingController();
  bool _roundsAreUndefined = false;
  bool _minimumPlayersAreUndefined = false;
  bool _playersCanInvite = true;
  bool _hostParticipates = true;
  bool _applyHandicapInMatches = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void dispose() {
    _titleController.dispose();
    _roundsController.dispose();
    _minimumPlayersController.dispose();
    _minimumPlayerParticipationController.dispose();
    _invitationMessageController.dispose();
    super.dispose();
  }

  Future<void> _saveLeague() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    var shouldResetSaving = true;
    try {
      final response = await widget.datosServidorService.crearLiguilla(
        idUsuario: widget.idUsuario,
        titulo: _titleController.text.trim(),
        jornadas: _roundsAreUndefined ? '-1' : _roundsController.text.trim(),
        minimoJugadoresJornada: _minimumPlayersAreUndefined
            ? '-1'
            : _minimumPlayersController.text.trim(),
        participacionMinimaJugador: _minimumPlayerParticipationController.text
            .trim(),
        puedenInvitar: _playersCanInvite ? '1' : '0',
        participaAnfitrion: _hostParticipates ? 'S' : 'N',
        aplicarHandicapPartidas: _applyHandicapInMatches ? '1' : '0',
        mensajeInvitacion: _invitationMessageController.text.trim(),
      );
      debugPrint('crearLiguilla: $response');
      if (!_backendResponseIsOk(response)) {
        throw FormatException('Respuesta no valida: $response');
      }

      if (!mounted) {
        return;
      }

      shouldResetSaving = false;
      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('crearLiguilla fallo: $error');
      if (error is DatosServidorException) {
        debugPrint('crearLiguilla backend body: ${error.body}');
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _saveError = 'No se pudo crear la liguilla.';
      });
    } finally {
      if (mounted && shouldResetSaving) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showHelp(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  Widget _helpButton({required String title, required String message}) {
    return IconButton(
      onPressed: () => _showHelp(title, message),
      tooltip: 'Ayuda',
      icon: const Text(
        '?',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String helpTitle,
    required String helpMessage,
  }) {
    return InputDecoration(
      labelText: label,
      suffixIcon: _helpButton(title: helpTitle, message: helpMessage),
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.72),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF567B37), width: 2),
      ),
    );
  }

  String? _requiredText(String? value) {
    return (value?.trim().isEmpty ?? true) ? 'Campo obligatorio' : null;
  }

  String? _oneOrTwoDigitNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Campo obligatorio';
    }

    final number = int.tryParse(text);
    if (number == null || number < 1 || number > 99) {
      return 'Debe estar entre 1 y 99';
    }

    return null;
  }

  String? _minimumPlayerParticipation(String? value) {
    final numberError = _oneOrTwoDigitNumber(value);
    if (numberError != null || _roundsAreUndefined) {
      return numberError;
    }

    final minimumParticipation = int.tryParse(value?.trim() ?? '');
    final rounds = int.tryParse(_roundsController.text.trim());
    if (minimumParticipation == null || rounds == null) {
      return null;
    }

    if (minimumParticipation > rounds) {
      return 'Debe ser menor o igual que Jornadas';
    }

    return null;
  }

  Widget _undefinedToggle({
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Indefinido'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReservationScreenFrame(
      title: 'Crear Liguilla',
      maxWidth: 620,
      showBackButton: true,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                inputFormatters: const [_UpperCaseTextInputFormatter()],
                validator: _requiredText,
                decoration: _inputDecoration(
                  label: 'Titulo de liguilla',
                  helpTitle: 'Titulo de liguilla',
                  helpMessage:
                      'Es el nombre con el que los jugadores reconocerán la liguilla. '
                      'Conviene que sea corto y claro.',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _roundsController,
                enabled: !_roundsAreUndefined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _roundsAreUndefined ? null : _oneOrTwoDigitNumber,
                decoration: _inputDecoration(
                  label: 'Jornadas',
                  helpTitle: 'Jornadas',
                  helpMessage:
                      'Indica cuántas jornadas tendrá la liguilla. Si aún no hay '
                      'un final previsto, marca Indefinido.',
                ),
              ),
              _undefinedToggle(
                value: _roundsAreUndefined,
                onChanged: (value) {
                  setState(() {
                    _roundsAreUndefined = value ?? false;
                    if (_roundsAreUndefined) {
                      _roundsController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _minimumPlayersController,
                enabled: !_minimumPlayersAreUndefined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _minimumPlayersAreUndefined
                    ? null
                    : _oneOrTwoDigitNumber,
                decoration: _inputDecoration(
                  label: 'Minimo jugadores por jornada',
                  helpTitle: 'Minimo jugadores por jornada',
                  helpMessage:
                      'Define cuántos jugadores deben participar como mínimo para '
                      'que una jornada compute en la liguilla. Si no quieres fijar '
                      'ese límite, marca Indefinido.',
                ),
              ),
              _undefinedToggle(
                value: _minimumPlayersAreUndefined,
                onChanged: (value) {
                  setState(() {
                    _minimumPlayersAreUndefined = value ?? false;
                    if (_minimumPlayersAreUndefined) {
                      _minimumPlayersController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _minimumPlayerParticipationController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _minimumPlayerParticipation,
                decoration: _inputDecoration(
                  label: 'Participacion en jornadas minima jugador',
                  helpTitle: 'Participacion en jornadas minima jugador',
                  helpMessage:
                      'Indica en cuántas jornadas como mínimo debe participar '
                      'cada jugador para que su clasificación cuente en la liguilla.',
                ),
              ),
              const SizedBox(height: 16),
              _LeagueChoiceField(
                label: 'Los jugadores pueden invitar a otros',
                value: _playersCanInvite,
                onChanged: (value) {
                  setState(() {
                    _playersCanInvite = value;
                  });
                },
                helpButton: _helpButton(
                  title: 'Los jugadores pueden invitar a otros',
                  message:
                      'Si está en Sí, los jugadores podrán invitar a otros. '
                      'Si está en No, solo podrá añadir jugadores quien organice.',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _invitationMessageController,
                validator: _requiredText,
                minLines: 3,
                maxLines: 5,
                decoration: _inputDecoration(
                  label: 'Mensaje invitacion',
                  helpTitle: 'Mensaje invitacion',
                  helpMessage:
                      'Texto que se usará como base para invitar por WhatsApp. '
                      'Puedes incluir el tono, reglas o indicaciones de la liguilla.',
                ),
              ),
              const SizedBox(height: 16),
              _LeagueChoiceField(
                label: '¿ Participas tu en el torneo ?',
                value: _hostParticipates,
                onChanged: (value) {
                  setState(() {
                    _hostParticipates = value;
                  });
                },
                helpButton: _helpButton(
                  title: '¿ Participas tu en el torneo ?',
                  message:
                      'Marca Sí si además de organizar la liguilla también vas '
                      'a jugarla. Marca No si solo la estás creando para otros jugadores.',
                ),
              ),
              const SizedBox(height: 16),
              _LeagueChoiceField(
                label: _applyHandicapHelpTitle,
                value: _applyHandicapInMatches,
                onChanged: (value) {
                  setState(() {
                    _applyHandicapInMatches = value;
                  });
                  if (value) {
                    _showHelp(
                      _applyHandicapHelpTitle,
                      _applyHandicapHelpMessage,
                    );
                  }
                },
                helpButton: _helpButton(
                  title: _applyHandicapHelpTitle,
                  message: _applyHandicapHelpMessage,
                ),
              ),
            ],
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 14),
          Text(
            _saveError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9D433D)),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B432D),
                  side: const BorderSide(color: Color(0xFF6B432D)),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveLeague,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF567B37),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LeagueChoiceField extends StatelessWidget {
  const _LeagueChoiceField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.helpButton,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget helpButton;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: helpButton,
        filled: true,
        fillColor: const Color.fromRGBO(255, 255, 255, 0.72),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Si')),
            ButtonSegment(value: false, label: Text('No')),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
          showSelectedIcon: false,
        ),
      ),
    );
  }
}

class _UpperCaseTextInputFormatter extends TextInputFormatter {
  const _UpperCaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
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

    final registration = await _saveUserInBackend(information);
    if (!mounted) {
      return;
    }
    if (registration == null) {
      setState(() {
        _isSaving = false;
      });
      return;
    }

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
      idUsuario: widget.initialInformation?.idUsuario ?? '',
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
            field.key != 'telefono' &&
            _localValidationError(field, _controllers[field.key]?.text) == null)
          field.key,
    };
  }

  Future<void> _validateBackendFieldOnBlur(String key) async {
    if (!_backendUniqueFieldKeys.contains(key) || _isSaving) {
      return;
    }
    if (key == 'telefono') {
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

  Future<_UserRegistrationResult?> _saveUserInBackend(
    _UserInformation information,
  ) async {
    var operation = 'altaUsuario';
    try {
      final editUserId = await _userIdForMobileBeforeSave(information);
      if (editUserId == null) {
        return null;
      }

      if (editUserId.isNotEmpty) {
        operation = 'editaUsuario';
        final response = await widget.datosServidorService.editaUsuario(
          editUserId,
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
        debugPrint('editaUsuario(${information.alias}): $response');
        return _UserRegistrationResult(
          isRegistered: _backendResponseIsOk(response),
          idUsuario: editUserId,
        );
      }

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
      debugPrint('$operation(${information.alias}) fallo: $error');
      return _UserRegistrationResult(
        isRegistered: false,
        idUsuario: information.idUsuario.trim(),
      );
    }
  }

  Future<String?> _userIdForMobileBeforeSave(
    _UserInformation information,
  ) async {
    final currentUserId = information.idUsuario.trim();
    final response = await widget.datosServidorService.yaExisteMovilUsuario(
      information.telefono,
    );
    debugPrint('yaExisteMovilUsuario(${information.telefono}): $response');

    final exists = _backendResponseSaysYes(response);
    if (!exists) {
      return currentUserId;
    }

    final backendUserId = _backendResponseField(response, 'idUsuario') ?? '';
    if (backendUserId.isEmpty || backendUserId == currentUserId) {
      return currentUserId;
    }

    final confirmed = await _showOverwriteMobileUserDialog();
    if (!mounted || confirmed != true) {
      return null;
    }

    return backendUserId;
  }

  Future<bool?> _showOverwriteMobileUserDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          content: const Text(
            'este movil ya existe, se sobreescribiran los datos de usuario',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancela'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Adelante'),
            ),
          ],
        );
      },
    );
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
                          if (widget.onCancel != null) ...[
                            _TopLeftBackButton(
                              onPressed: _isSaving ? null : widget.onCancel,
                            ),
                            const SizedBox(height: 10),
                          ],
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

String _backendResponseMessage(String response) {
  final rpta = _backendResponseField(response, 'rpta');
  if (rpta != null && rpta.isNotEmpty) {
    final normalizedRpta = rpta.toLowerCase();
    if (normalizedRpta != 'ok' && normalizedRpta != 'ko') {
      return rpta;
    }
  }

  for (final key in const ['mensaje', 'msg', 'error', 'descripcion']) {
    final value = _backendResponseField(response, key);
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  if (rpta != null && rpta.isNotEmpty) {
    return rpta;
  }

  final trimmedResponse = response.trim();
  return trimmedResponse.isEmpty
      ? 'Respuesta vacia del backend.'
      : trimmedResponse;
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

class _PendingLeagueInvitations {
  const _PendingLeagueInvitations({
    required this.invitations,
    required this.leagues,
  });

  const _PendingLeagueInvitations.empty() : invitations = 0, leagues = const [];

  final int invitations;
  final List<_PendingLeagueInvitationSummary> leagues;

  bool get hasPending => invitations > 0;

  Set<String> get leagueIds => {
    for (final league in leagues)
      if (league.idLiguilla.isNotEmpty) league.idLiguilla,
  };

  static _PendingLeagueInvitations fromPayload(Object? payload) {
    if (payload is List && payload.isNotEmpty) {
      return fromPayload(payload.first);
    }

    if (payload is! Map) {
      return const _PendingLeagueInvitations.empty();
    }

    final map = _stringKeyedMap(payload);
    final leaguesPayload = map['liguillas'];
    final leagueRows = _decodeMapRows(leaguesPayload, 0) ?? const [];
    final leagues = [
      for (final row in leagueRows)
        ?_PendingLeagueInvitationSummary.fromMap(row),
    ];
    final invitationCount = _intFromBackendValue(map['invitaciones']);

    return _PendingLeagueInvitations(
      invitations: invitationCount ?? leagues.length,
      leagues: leagues,
    );
  }
}

class _PendingLeagueInvitationSummary {
  const _PendingLeagueInvitationSummary({
    required this.idLiguilla,
    required this.titulo,
    required this.aliasCreador,
    required this.movilCreador,
  });

  final String idLiguilla;
  final String titulo;
  final String aliasCreador;
  final String movilCreador;

  static _PendingLeagueInvitationSummary? fromMap(Map<String, dynamic> map) {
    final idLiguilla = '${map['idLiguilla'] ?? ''}'.trim();
    final titulo = '${map['titulo'] ?? ''}'.trim();
    if (idLiguilla.isEmpty && titulo.isEmpty) {
      return null;
    }

    return _PendingLeagueInvitationSummary(
      idLiguilla: idLiguilla,
      titulo: titulo,
      aliasCreador: '${map['alias_creador'] ?? map['alias'] ?? ''}'.trim(),
      movilCreador: '${map['movil_creador'] ?? map['movil'] ?? ''}'.trim(),
    );
  }
}

_PendingLeagueInvitations _pendingLeagueInvitationsFromResponse(
  String response,
) {
  final trimmedResponse = response.trim();
  final decoded =
      _decodeJsonLikePayload(trimmedResponse) ??
      _decodeBracketWrappedMapPayload(trimmedResponse);
  return _PendingLeagueInvitations.fromPayload(decoded);
}

class _LeagueSummary {
  const _LeagueSummary({
    required this.idLiguilla,
    required this.titulo,
    required this.alias,
    required this.movil,
    required this.pendienteDecidir,
    required this.acabada,
    required this.fechaRechazo,
    required this.puedenInvitar,
    required this.creador,
    required this.invitadoPor,
    required this.jornadas,
    required this.minimoJugadoresJornada,
    required this.participacionMinimaJugador,
    required this.participaAnfitrion,
    required this.aplicarHandicapPartidas,
  });

  final String idLiguilla;
  final String titulo;
  final String alias;
  final String movil;
  final String pendienteDecidir;
  final String acabada;
  final String fechaRechazo;
  final String puedenInvitar;
  final String creador;
  final String invitadoPor;
  final String jornadas;
  final String minimoJugadoresJornada;
  final String participacionMinimaJugador;
  final String participaAnfitrion;
  final String aplicarHandicapPartidas;

  bool get isPending => pendienteDecidir.trim().toUpperCase() == 'S';
  bool get isFinished => acabada.trim().isNotEmpty;
  bool get isRejected => _backendDateLikeValueIsSet(fechaRechazo);

  bool get isAccepted => !isPending && !isRejected && !isFinished;
  bool get isActive => !isRejected && !isFinished;
  bool get playersCanInvite => puedenInvitar.trim() == '1';

  bool canBeInvitedBy(String idUsuario) {
    return !isPending &&
        !isRejected &&
        isActive &&
        (playersCanInvite || creador.trim() == idUsuario.trim());
  }

  bool isVisibleFor(String idUsuario) {
    final currentUserId = idUsuario.trim();
    return !isRejected ||
        (currentUserId.isNotEmpty && invitadoPor.trim() == currentUserId);
  }

  _LeagueSummary copyWith({
    String? pendienteDecidir,
    String? acabada,
    String? fechaRechazo,
  }) {
    return _LeagueSummary(
      idLiguilla: idLiguilla,
      titulo: titulo,
      alias: alias,
      movil: movil,
      pendienteDecidir: pendienteDecidir ?? this.pendienteDecidir,
      acabada: acabada ?? this.acabada,
      fechaRechazo: fechaRechazo ?? this.fechaRechazo,
      puedenInvitar: puedenInvitar,
      creador: creador,
      invitadoPor: invitadoPor,
      jornadas: jornadas,
      minimoJugadoresJornada: minimoJugadoresJornada,
      participacionMinimaJugador: participacionMinimaJugador,
      participaAnfitrion: participaAnfitrion,
      aplicarHandicapPartidas: aplicarHandicapPartidas,
    );
  }

  List<String> get statusLabelsWithoutPending {
    final rejectedAt = fechaRechazo.trim();
    return [
      if (isRejected)
        rejectedAt.toUpperCase() == 'S'
            ? 'Rechazada'
            : 'Rechazada ${_statisticsDateLabel(rejectedAt)}'
      else if (isFinished)
        'Acabada ${_statisticsDateLabel(acabada)}',
    ];
  }

  static _LeagueSummary? fromMap(Map<String, dynamic> map) {
    final idLiguilla = '${map['idLiguilla'] ?? ''}'.trim();
    final titulo = '${map['titulo'] ?? ''}'.trim();
    if (idLiguilla.isEmpty && titulo.isEmpty) {
      return null;
    }

    return _LeagueSummary(
      idLiguilla: idLiguilla,
      titulo: titulo,
      alias: '${map['alias'] ?? ''}'.trim(),
      movil: '${map['movil'] ?? ''}'.trim(),
      pendienteDecidir: '${map['pendiente_decidir'] ?? ''}'.trim(),
      acabada: '${map['acabada'] ?? ''}'.trim(),
      fechaRechazo: '${map['fecha_rechazo'] ?? map['rechazada'] ?? ''}'.trim(),
      puedenInvitar: '${map['pueden_invitar'] ?? ''}'.trim(),
      creador: '${map['creador'] ?? ''}'.trim(),
      invitadoPor: '${map['invitado_por'] ?? map['invitador_por'] ?? ''}'
          .trim(),
      jornadas: '${map['jornadas'] ?? ''}'.trim(),
      minimoJugadoresJornada: '${map['minimo_jugadores_jornada'] ?? ''}'.trim(),
      participacionMinimaJugador:
          '${map['participacion_minima_jugador'] ?? map['paticipacion_minima_jugador'] ?? ''}'
              .trim(),
      participaAnfitrion: '${map['participa_anfitrion'] ?? ''}'.trim(),
      aplicarHandicapPartidas: '${map['aplicar_handicap_partidas'] ?? ''}'
          .trim(),
    );
  }
}

List<_LeagueSummary> _leaguesFromResponse(String response) {
  final rows = _decodeMapRows(response, 0) ?? const [];
  return [for (final row in rows) ?_LeagueSummary.fromMap(row)];
}

class _LeagueParticipant {
  const _LeagueParticipant({
    required this.idUsuario,
    required this.alias,
    required this.movil,
    required this.fechaAceptacion,
    required this.fechaRechazo,
    required this.pendienteDecidir,
    required this.handicapInicial,
  });

  final String idUsuario;
  final String alias;
  final String movil;
  final String fechaAceptacion;
  final String fechaRechazo;
  final String pendienteDecidir;
  final String handicapInicial;

  bool get isPending => pendienteDecidir.trim().toUpperCase() == 'S';
  bool get hasAccepted => _backendDateLikeValueIsSet(fechaAceptacion);
  bool get hasRejected => _backendDateLikeValueIsSet(fechaRechazo);

  String get statusLabel {
    if (isPending) {
      return 'Pendiente de decidir';
    }

    if (hasRejected) {
      return 'No participa';
    }

    if (hasAccepted) {
      return 'Participa';
    }

    return 'Sin decision';
  }

  static _LeagueParticipant? fromMap(Map<String, dynamic> map) {
    final alias = '${map['alias'] ?? ''}'.trim();
    final idUsuario = '${map['idUsuario'] ?? ''}'.trim();
    if (alias.isEmpty && idUsuario.isEmpty) {
      return null;
    }

    return _LeagueParticipant(
      idUsuario: idUsuario,
      alias: alias,
      movil: '${map['movil'] ?? ''}'.trim(),
      fechaAceptacion: '${map['fecha_aceptacion'] ?? ''}'.trim(),
      fechaRechazo: '${map['fecha_rechazo'] ?? ''}'.trim(),
      pendienteDecidir: '${map['pendiente_decidir'] ?? ''}'.trim(),
      handicapInicial: '${map['handicap_inicial'] ?? ''}'.trim(),
    );
  }
}

List<_LeagueParticipant> _leagueParticipantsFromResponse(String response) {
  final rows = _decodeMapRows(response, 0) ?? const [];
  return [for (final row in rows) ?_LeagueParticipant.fromMap(row)];
}

bool _backendDateLikeValueIsSet(String value) {
  final normalized = value.trim().toUpperCase();
  return normalized.isNotEmpty && normalized != 'N';
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

bool _backendDateIsBeforeToday(String value) {
  final date = _parseBackendDate(value);
  if (date == null) {
    return false;
  }

  return _dateOnly(date).isBefore(_dateOnly(DateTime.now()));
}

DateTime? _parseBackendDate(String value) {
  final digits = value.trim().replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6) {
    return null;
  }

  final hasFullYear = digits.length >= 8 && digits.startsWith('20');
  final yearText = hasFullYear
      ? digits.substring(0, 4)
      : digits.substring(0, 2);
  final monthStart = hasFullYear ? 4 : 2;
  final year = int.tryParse(yearText);
  final month = int.tryParse(digits.substring(monthStart, monthStart + 2));
  final day = int.tryParse(digits.substring(monthStart + 2, monthStart + 4));
  if (year == null || month == null || day == null) {
    return null;
  }

  final fullYear = hasFullYear ? year : 2000 + year;
  final parsed = DateTime(fullYear, month, day);
  if (parsed.year != fullYear || parsed.month != month || parsed.day != day) {
    return null;
  }

  return parsed;
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

String _formatGolfPositionDate(DateTime value) {
  final localValue = value.toLocal();
  return '${_twoDigits(localValue.year % 100)}'
      '${_twoDigits(localValue.month)}'
      '${_twoDigits(localValue.day)}'
      '${_twoDigits(localValue.hour)}'
      '${_twoDigits(localValue.minute)}'
      '${_twoDigits(localValue.second)}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

List<_AgendaSlot> _agendaSlotsFromResponse(String response) {
  final rows = _decodeAgendaRows(response, 0) ?? const [];
  return [for (final row in rows) ?_AgendaSlot.fromMap(row)];
}

List<_InvitedPlayer> _invitedPlayersFromResponse(String response) {
  return _invitedPlayersFromPayload(response);
}

_InitialGameState _initialGameStateFromResponse(String response) {
  final decoded = _decodeJsonLikePayload(response.trim());
  if (decoded is! Map) {
    return const _InitialGameState();
  }

  return _InitialGameState.fromMap(_stringKeyedMap(decoded));
}

_InvitedPlayersResponse _invitedPlayersResponseFromResponse(String response) {
  final decoded = _decodeJsonLikePayload(response.trim()) ?? response;
  var empezada = '';
  if (decoded is Map) {
    final map = _stringKeyedMap(decoded);
    empezada = '${map['empezada'] ?? ''}'.trim();
  }

  return _InvitedPlayersResponse(
    empezada: empezada,
    players: _invitedPlayersFromPayload(decoded),
  );
}

List<_InvitedPlayer> _invitedPlayersFromPayload(Object? payload) {
  final rows = _decodeMapRows(payload, 0) ?? const [];
  return [for (final row in rows) ?_InvitedPlayer.fromMap(row)];
}

List<_StatisticsRound> _statisticsRoundsFromResponse(
  String response, {
  required String idUsuario,
  required String alias,
}) {
  final decoded = _decodeJsonLikePayload(response.trim()) ?? response;
  final payloads = _statisticsRoundPayloads(decoded, 0);

  return [
    for (final payload in payloads)
      ?_StatisticsRound.fromPayload(
        payload,
        idUsuario: idUsuario,
        alias: alias,
      ),
  ];
}

List<Object?> _statisticsRoundPayloads(Object? payload, int depth) {
  if (depth > 4 || payload == null) {
    return const [];
  }

  if (payload is String) {
    final decoded = _decodeJsonLikePayload(payload.trim());
    return decoded == null
        ? <Object?>[payload]
        : _statisticsRoundPayloads(decoded, depth + 1);
  }

  if (payload is List) {
    return payload.cast<Object?>();
  }

  if (payload is Map) {
    final map = _stringKeyedMap(payload);
    for (final key in const ['partidas', 'partida', 'data', 'valor', 'json']) {
      if (!map.containsKey(key)) {
        continue;
      }

      final nestedPayloads = _statisticsRoundPayloads(map[key], depth + 1);
      if (nestedPayloads.isNotEmpty) {
        return nestedPayloads;
      }
    }

    return [map];
  }

  return const [];
}

List<String> _statisticsHandicapValuesFromResponse(String response) {
  final decoded = _decodeJsonLikePayload(response.trim()) ?? response;
  final values = _statisticsHandicapValuesFromPayload(decoded);
  if (values.isNotEmpty) {
    return values;
  }

  final valor = _extractWrappedBackendField(response, 'valor');
  return valor == null ? const [] : _statisticsHandicapValuesFromPayload(valor);
}

List<String> _statisticsHandicapValuesFromPayload(Object? payload) {
  return _statisticsHandicapValuesFromPayloadValue(payload, 0);
}

List<String> _statisticsHandicapValuesFromPayloadValue(
  Object? payload,
  int depth,
) {
  if (depth > 5 || payload == null) {
    return const [];
  }

  if (payload is String) {
    final trimmedPayload = payload.trim();
    if (trimmedPayload.isEmpty) {
      return const [];
    }

    for (final fieldName in const [
      'configuracion_tarjeta',
      'configuracionTarjeta',
      'valor',
    ]) {
      final wrappedField = _extractWrappedBackendField(
        trimmedPayload,
        fieldName,
      );
      if (wrappedField == null) {
        continue;
      }

      final values = _statisticsHandicapValuesFromPayloadValue(
        wrappedField,
        depth + 1,
      );
      if (values.isNotEmpty) {
        return values;
      }
    }

    final decoded = _decodeJsonLikePayload(trimmedPayload);
    return decoded == null
        ? const []
        : _statisticsHandicapValuesFromPayloadValue(decoded, depth + 1);
  }

  if (payload is List) {
    final rows = payload.whereType<Map>().map(_stringKeyedMap).toList();
    final values = _statisticsHandicapValuesFromRows(rows);
    if (values.isNotEmpty) {
      return values;
    }

    for (final item in payload) {
      final nestedValues = _statisticsHandicapValuesFromPayloadValue(
        item,
        depth + 1,
      );
      if (nestedValues.isNotEmpty) {
        return nestedValues;
      }
    }
  }

  if (payload is Map) {
    final map = _stringKeyedMap(payload);
    final values = _statisticsHandicapValuesFromRows([map]);
    if (values.isNotEmpty) {
      return values;
    }

    for (final key in const [
      'configuracion_tarjeta',
      'configuracionTarjeta',
      'configuracion_tarjeta_json',
      'configuracionTarjetaJson',
      'configuracion',
      'valor',
      'json',
      'data',
    ]) {
      if (!map.containsKey(key)) {
        continue;
      }

      final nestedValues = _statisticsHandicapValuesFromPayloadValue(
        map[key],
        depth + 1,
      );
      if (nestedValues.isNotEmpty) {
        return nestedValues;
      }
    }
  }

  return const [];
}

List<String> _statisticsHandicapValuesFromRows(
  List<Map<String, dynamic>> rows,
) {
  final holeRows = [
    for (final entry in rows.asMap().entries)
      if (_statisticsHandicapValue(entry.value).isNotEmpty)
        _IndexedStatisticsHoleConfiguration(
          index: entry.key,
          hole: _statisticsHoleNumber(entry.value, entry.key),
          handicap: _statisticsHandicapValue(entry.value),
        ),
  ];
  if (holeRows.isEmpty) {
    return const [];
  }

  holeRows.sort((left, right) {
    if (left.hole == right.hole) {
      return left.index.compareTo(right.index);
    }

    return left.hole.compareTo(right.hole);
  });

  return [for (final row in holeRows.take(18)) row.handicap];
}

String _statisticsHandicapValue(Map<String, dynamic> row) {
  for (final key in const [
    'handicap',
    'hcp',
    'HCP',
    'handicap_hoyo',
    'handicapHoyo',
  ]) {
    final value = '${row[key] ?? ''}'.trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

int _statisticsHoleNumber(Map<String, dynamic> row, int fallbackIndex) {
  for (final key in const ['hoyo', 'hole', 'numero_hoyo', 'numeroHoyo']) {
    final value = int.tryParse('${row[key] ?? ''}'.trim());
    if (value != null && value > 0) {
      return value;
    }
  }

  return fallbackIndex + 1;
}

String? _extractWrappedBackendField(String rawResponse, String fieldName) {
  final decoded = _decodeJsonLikePayload(rawResponse.trim());
  if (decoded is Map) {
    final map = _stringKeyedMap(decoded);
    final value = map[fieldName];
    if (value != null) {
      return value is String ? value : jsonEncode(value);
    }
  }

  return _extractMalformedBackendStringField(rawResponse, fieldName);
}

String? _extractMalformedBackendStringField(
  String rawResponse,
  String fieldName,
) {
  final trimmedResponse = rawResponse.trim();
  final fieldMatch = RegExp(
    '"${RegExp.escape(fieldName)}"\\s*:\\s*"',
  ).firstMatch(trimmedResponse);
  if (fieldMatch == null) {
    return null;
  }

  final valueStart = fieldMatch.end;
  for (var index = valueStart; index < trimmedResponse.length; index++) {
    if (trimmedResponse.codeUnitAt(index) != 0x22) {
      continue;
    }

    if (index > valueStart && trimmedResponse.codeUnitAt(index - 1) == 0x5C) {
      continue;
    }

    final tail = trimmedResponse.substring(index + 1);
    final isFieldBoundary = RegExp(
      r'^\s*(?:,\s*"[^"]+"\s*:|\}\s*$)',
      dotAll: true,
    ).hasMatch(tail);
    if (isFieldBoundary) {
      return trimmedResponse.substring(valueStart, index);
    }
  }

  return null;
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
    for (final key in const [
      'agenda',
      'jugadores',
      'liguillas',
      'data',
      'valor',
      'json',
    ]) {
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

Object? _decodeBracketWrappedMapPayload(String rawPayload) {
  final trimmedPayload = rawPayload.trim();
  if (trimmedPayload.length < 2 ||
      !trimmedPayload.startsWith('[') ||
      !trimmedPayload.endsWith(']')) {
    return null;
  }

  final innerPayload = trimmedPayload.substring(1, trimmedPayload.length - 1);
  if (innerPayload.trimLeft().startsWith('{')) {
    return null;
  }

  return _decodeJsonLikePayload('{$innerPayload}');
}

int? _intFromBackendValue(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse('${value ?? ''}'.trim());
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

class _GolfPositionPayload {
  const _GolfPositionPayload({
    required this.lat,
    required this.lon,
    required this.fecha,
    required this.precision,
  });

  factory _GolfPositionPayload.fromPosition(Position position) {
    return _GolfPositionPayload(
      lat: position.latitude.toStringAsFixed(7),
      lon: position.longitude.toStringAsFixed(7),
      fecha: _formatGolfPositionDate(position.timestamp),
      precision: position.accuracy.toStringAsFixed(1),
    );
  }

  factory _GolfPositionPayload.unavailable(DateTime fecha) {
    return _GolfPositionPayload(
      lat: '0',
      lon: '0',
      fecha: _formatGolfPositionDate(fecha),
      precision: '0',
    );
  }

  final String lat;
  final String lon;
  final String fecha;
  final String precision;
}

class _StatisticsRound {
  const _StatisticsRound({
    required this.idPartida,
    required this.dateLabel,
    required this.sortValue,
    required this.holeValues,
    required this.handicapValues,
    required this.jugadores,
    required this.playRowsJson,
  });

  final String idPartida;
  final String dateLabel;
  final int sortValue;
  final List<String> holeValues;
  final List<String> handicapValues;
  final String jugadores;
  final String playRowsJson;

  static _StatisticsRound? fromPayload(
    Object? payload, {
    required String idUsuario,
    required String alias,
  }) {
    final rows = _statisticsPlayRowsFromPayload(payload);
    if (rows.isEmpty) {
      return null;
    }

    final userRow =
        rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row != null && _statisticsRowBelongsToUser(row, idUsuario),
          orElse: () => null,
        ) ??
        rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row != null && _statisticsRowBelongsToAlias(row, alias),
          orElse: () => null,
        ) ??
        (rows.length == 1 ? rows.first : null);
    if (userRow == null) {
      return null;
    }

    final holeValues = [
      for (var index = 1; index <= 18; index++)
        '${userRow['hoyo_$index'] ?? ''}'.trim(),
    ];
    if (holeValues.every((value) => value.isEmpty)) {
      return null;
    }

    final rawDate =
        _statisticsDateValue(payload) ?? _statisticsDateValue(userRow) ?? '';

    return _StatisticsRound(
      idPartida: _statisticsGameIdValue(payload),
      dateLabel: _statisticsDateLabel(rawDate),
      sortValue: _statisticsDateSortValue(rawDate),
      holeValues: holeValues,
      handicapValues: _statisticsHandicapValuesFromPayload(payload),
      jugadores: rows.length.toString(),
      playRowsJson: jsonEncode(rows),
    );
  }
}

List<Map<String, dynamic>> _statisticsPlayRowsFromPayload(Object? payload) {
  final decodedRows = _decodePlayRowsPayload(payload);
  if (decodedRows != null && decodedRows.isNotEmpty) {
    return decodedRows;
  }

  if (payload is String) {
    final decoded = _decodeJsonLikePayload(payload.trim());
    return decoded == null ? const [] : _statisticsPlayRowsFromPayload(decoded);
  }

  if (payload is Map) {
    final map = _stringKeyedMap(payload);
    for (final key in const [
      'json_partida',
      'jsonPartida',
      'json_hoyos',
      'jsonHoyos',
      'partida',
      'jugadores',
      'rows',
      'data',
      'valor',
      'json',
    ]) {
      if (!map.containsKey(key)) {
        continue;
      }

      final rows = _statisticsPlayRowsFromPayload(map[key]);
      if (rows.isNotEmpty) {
        return rows;
      }
    }

    if (_statisticsMapLooksLikePlayRow(map)) {
      return [map];
    }
  }

  return const [];
}

bool _statisticsMapLooksLikePlayRow(Map<String, dynamic> map) {
  return map.keys.any((key) => RegExp(r'^hoyo_\d+$').hasMatch(key));
}

bool _statisticsRowBelongsToUser(Map<String, dynamic> row, String idUsuario) {
  final rowUserId = '${row['idUsuario'] ?? row['idJugador'] ?? ''}'.trim();
  return rowUserId.isNotEmpty && rowUserId == idUsuario.trim();
}

bool _statisticsRowBelongsToAlias(Map<String, dynamic> row, String alias) {
  final rowAlias =
      '${row['jugador'] ?? row['alias'] ?? row['allias'] ?? row['Alias'] ?? ''}'
          .trim();
  return rowAlias.isNotEmpty && rowAlias == alias.trim();
}

String _statisticsGameIdValue(Object? payload) {
  if (payload is String) {
    final decoded = _decodeJsonLikePayload(payload.trim());
    return decoded == null ? '' : _statisticsGameIdValue(decoded);
  }

  if (payload is! Map) {
    return '';
  }

  final map = _stringKeyedMap(payload);
  for (final key in const [
    'idPartida',
    'id_partida',
    'idpartida',
    'partida_id',
  ]) {
    final value = '${map[key] ?? ''}'.trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

String? _statisticsDateValue(Object? payload) {
  if (payload is String) {
    final decoded = _decodeJsonLikePayload(payload.trim());
    return decoded == null ? null : _statisticsDateValue(decoded);
  }

  if (payload is! Map) {
    return null;
  }

  final map = _stringKeyedMap(payload);
  for (final key in const [
    'dia',
    'fecha',
    'fecha_partida',
    'fechaPartida',
    'dia_partida',
    'diaPartida',
    'empezada',
    'modificado',
    'ultima_modificacion',
  ]) {
    final value = '${map[key] ?? ''}'.trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

String _statisticsDateLabel(String rawDate) {
  final trimmedDate = rawDate.trim();
  final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmedDate);
  if (isoMatch != null) {
    return '${isoMatch.group(3)}/${isoMatch.group(2)}/${isoMatch.group(1)}';
  }

  final digits = trimmedDate.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 8 && digits.startsWith('20')) {
    return '${digits.substring(6, 8)}/${digits.substring(4, 6)}/'
        '${digits.substring(0, 4)}';
  }

  if (RegExp(r'^\d{6,14}$').hasMatch(digits)) {
    final year = 2000 + int.parse(digits.substring(0, 2));
    final month = digits.substring(2, 4);
    final day = digits.substring(4, 6);
    return '$day/$month/$year';
  }

  return trimmedDate.isEmpty ? 'Sin fecha' : trimmedDate;
}

int _statisticsDateSortValue(String rawDate) {
  final trimmedDate = rawDate.trim();
  final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmedDate);
  if (isoMatch != null) {
    return int.tryParse(
          '${isoMatch.group(1)}${isoMatch.group(2)}${isoMatch.group(3)}000000',
        ) ??
        0;
  }

  final digits = trimmedDate.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 8 && digits.startsWith('20')) {
    return int.tryParse('${digits}000000') ?? 0;
  }

  if (RegExp(r'^\d{6,14}$').hasMatch(digits)) {
    final padded = digits.padRight(12, '0');
    return int.tryParse('20$padded') ?? 0;
  }

  return 0;
}

String _statisticsHoleValue(List<String> values, int holeIndex) {
  return holeIndex < values.length ? values[holeIndex] : '';
}

String _statisticsHandicapDifference(
  List<String> scoreValues,
  List<String> handicapValues,
) {
  var total = 0;
  var hasValue = false;

  for (var index = 0; index < 18; index++) {
    final score = int.tryParse(_statisticsHoleValue(scoreValues, index).trim());
    final handicap = int.tryParse(
      _statisticsHoleValue(handicapValues, index).trim(),
    );
    if (score == null || handicap == null) {
      continue;
    }

    total += score - handicap;
    hasValue = true;
  }

  if (!hasValue) {
    return '';
  }

  return total > 0 ? '+$total' : '$total';
}

_StatisticsCellResult? _statisticsDifferenceResult(String value) {
  final difference = int.tryParse(value.trim());
  if (difference == null) {
    return null;
  }

  if (difference < 0) {
    return _StatisticsCellResult.underHandicap;
  }

  if (difference == 0) {
    return _StatisticsCellResult.equalHandicap;
  }

  if (difference == 1) {
    return _StatisticsCellResult.oneOverHandicap;
  }

  return _StatisticsCellResult.overOneOverHandicap;
}

_StatisticsCellResult? _statisticsCellResult(
  String scoreValue,
  String handicapValue,
) {
  final score = int.tryParse(scoreValue.trim());
  final handicap = int.tryParse(handicapValue.trim());
  if (score == null || handicap == null) {
    return null;
  }

  if (score < handicap) {
    return _StatisticsCellResult.underHandicap;
  }

  if (score == handicap) {
    return _StatisticsCellResult.equalHandicap;
  }

  if (score == handicap + 1) {
    return _StatisticsCellResult.oneOverHandicap;
  }

  return _StatisticsCellResult.overOneOverHandicap;
}

Color _statisticsScoreCellColor(_StatisticsCellResult result) {
  switch (result) {
    case _StatisticsCellResult.underHandicap:
      return const Color(0xFFE1F3DA);
    case _StatisticsCellResult.equalHandicap:
      return const Color(0xFFFFFBE8);
    case _StatisticsCellResult.oneOverHandicap:
      return const Color(0xFFDCEEFF);
    case _StatisticsCellResult.overOneOverHandicap:
      return const Color(0xFFBFD9F2);
  }
}

enum _StatisticsCellResult {
  underHandicap,
  equalHandicap,
  oneOverHandicap,
  overOneOverHandicap,
}

String _createPlayRowsJsonForPlayers(
  List<_InvitedPlayer> players, {
  List<Map<String, dynamic>> existingRows = const [],
}) {
  final existingRowsByPlayerId = <String, Map<String, dynamic>>{};
  final existingRowsByPlayerLabel = <String, Map<String, dynamic>>{};
  for (var index = 0; index < existingRows.length; index++) {
    final row = existingRows[index];
    final idUsuario = '${row['idUsuario'] ?? row['idJugador'] ?? ''}'.trim();
    if (idUsuario.isNotEmpty) {
      existingRowsByPlayerId[idUsuario] = row;
    }

    final playerLabel = '${row['jugador'] ?? ''}'.trim();
    if (playerLabel.isNotEmpty && playerLabel != '${index + 1}') {
      existingRowsByPlayerLabel[playerLabel] = row;
    }
  }

  final data = List.generate(players.length, (rowIndex) {
    final player = players[rowIndex];
    final existingRow =
        existingRowsByPlayerId[player.idJugador.trim()] ??
        existingRowsByPlayerLabel[player.displayName];
    return <String, String>{
      if (player.idJugador.trim().isNotEmpty)
        'idUsuario': player.idJugador.trim(),
      'jugador': player.displayName,
      'modificado': '${existingRow?['modificado'] ?? ''}',
      for (var holeIndex = 0; holeIndex < 18; holeIndex++)
        'hoyo_${holeIndex + 1}':
            '${existingRow?['hoyo_${holeIndex + 1}'] ?? ''}',
    };
  });

  return jsonEncode(data);
}

String? _mergeNewerPlayRowsJson({
  required String currentJson,
  required String remoteResponse,
}) {
  final currentRows =
      _decodePlayRowsPayload(currentJson) ?? const <Map<String, dynamic>>[];
  final remoteRows = _decodePlayRowsPayload(remoteResponse);
  if (remoteRows == null) {
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
      .toList(growable: true);
  final mergedRowIds = <String>{
    for (var index = 0; index < mergedRows.length; index++)
      _playRowPlayerId(mergedRows[index], index),
  };

  for (var index = 0; index < mergedRows.length; index++) {
    final currentRow = mergedRows[index];
    final rowId = _playRowPlayerId(currentRow, index);
    final remoteRow = remoteRowsByPlayer[rowId];
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

  for (var index = 0; index < remoteRows.length; index++) {
    final remoteRow = remoteRows[index];
    final rowId = _playRowPlayerId(remoteRow, index);
    if (mergedRowIds.contains(rowId) ||
        !_playRowHasPlayerOrAnnotations(remoteRow, index)) {
      continue;
    }

    mergedRows.add(Map<String, dynamic>.from(remoteRow));
    mergedRowIds.add(rowId);
    hasChanges = true;
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
      'json_partida',
      'jsonPartida',
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
  final decoded = _decodeJsonLikePayload(rawResponse.trim());
  if (decoded is Map) {
    final map = _stringKeyedMap(decoded);
    final value = map['json_hoyos'] ?? map['jsonHoyos'];
    if (value != null) {
      return value is String ? value : jsonEncode(value);
    }
  }

  return _extractMalformedBackendStringField(rawResponse, 'json_hoyos');
}

class _IndexedStatisticsHoleConfiguration {
  const _IndexedStatisticsHoleConfiguration({
    required this.index,
    required this.hole,
    required this.handicap,
  });

  final int index;
  final int hole;
  final String handicap;
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry('$key', value));
}

String _playRowPlayerId(Map<String, dynamic> row, int fallbackIndex) {
  final idUsuario = row['idUsuario'] ?? row['idJugador'];
  if (idUsuario != null && '$idUsuario'.trim().isNotEmpty) {
    return '$idUsuario'.trim();
  }

  final player = row['jugador'];
  return player == null ? '${fallbackIndex + 1}' : '$player';
}

bool _playRowHasPlayerOrAnnotations(
  Map<String, dynamic> row,
  int fallbackIndex,
) {
  final idUsuario = row['idUsuario'] ?? row['idJugador'];
  if (idUsuario != null && '$idUsuario'.trim().isNotEmpty) {
    return true;
  }

  final player = '${row['jugador'] ?? ''}'.trim();
  if (player.isNotEmpty && player != '${fallbackIndex + 1}') {
    return true;
  }

  for (var holeIndex = 0; holeIndex < 18; holeIndex++) {
    final value = row['hoyo_${holeIndex + 1}'];
    if (value != null && '$value'.trim().isNotEmpty) {
      return true;
    }
  }

  return false;
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

class _InvitedPlayer {
  const _InvitedPlayer({
    required this.idJugador,
    required this.alias,
    required this.esCreador,
  });

  final String idJugador;
  final String alias;
  final String esCreador;

  bool get isCreator => esCreador.toUpperCase() == 'S';

  String get displayName {
    if (alias.isNotEmpty) {
      return alias;
    }

    return idJugador.isEmpty ? 'Jugador' : idJugador;
  }

  static _InvitedPlayer? fromMap(Map<String, dynamic> map) {
    final idJugador = '${map['idJugador'] ?? map['idUsuario'] ?? ''}'.trim();
    final alias = '${map['allias'] ?? map['alias'] ?? map['Alias'] ?? ''}'
        .trim();
    final esCreador = '${map['es_creador'] ?? ''}'.trim();
    if (idJugador.isEmpty && alias.isEmpty) {
      return null;
    }

    return _InvitedPlayer(
      idJugador: idJugador,
      alias: alias,
      esCreador: esCreador,
    );
  }
}

class _InvitedPlayersResponse {
  const _InvitedPlayersResponse({
    required this.empezada,
    required this.players,
  });

  final String empezada;
  final List<_InvitedPlayer> players;

  bool get hasExpiredStarted => _backendDateIsBeforeToday(empezada);

  bool get hasStarted => empezada.trim().isNotEmpty && !hasExpiredStarted;
}

class _InitialGameState {
  const _InitialGameState({this.empezada = '', this.ultimaModificacion = ''});

  final String empezada;
  final String ultimaModificacion;

  bool get hasExpiredStarted => _backendDateIsBeforeToday(empezada);

  bool get hasStarted => empezada.trim().isNotEmpty && !hasExpiredStarted;

  bool get hasModification => ultimaModificacion.trim().isNotEmpty;

  String get startButtonLabel {
    if (!hasStarted) {
      return 'Iniciar Salida';
    }

    return hasModification ? 'Continuar Partida' : 'Iniciar Partida';
  }

  static _InitialGameState fromMap(Map<String, dynamic> map) {
    return _InitialGameState(
      empezada: '${map['empezada'] ?? ''}'.trim(),
      ultimaModificacion: '${map['ultima_modificacion'] ?? ''}'.trim(),
    );
  }
}
