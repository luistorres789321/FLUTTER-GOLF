import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_golf/services/datos_servidor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _frontNine = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const _backNine = [10, 11, 12, 13, 14, 15, 16, 17, 18];
const _summaryHeaders = ['TOTAL', 'HCP JUEGO', 'NETO'];
const _emptySummary = ['', '', ''];
const List<DeviceOrientation> _scorecardOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];
const List<DeviceOrientation> _scorecardLandscapeOrientations = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];
const List<DeviceOrientation> _scorecardPortraitOrientations = [
  DeviceOrientation.portraitUp,
];

Future<void> _allowScorecardOrientations() {
  return SystemChrome.setPreferredOrientations(_scorecardOrientations);
}

Future<void> _forceScorecardLandscapeOrientation() {
  return SystemChrome.setPreferredOrientations(_scorecardLandscapeOrientations);
}

Future<void> _lockScorecardPortraitOrientation() {
  return SystemChrome.setPreferredOrientations(_scorecardPortraitOrientations);
}

Future<void> _showSystemUi() {
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
}

const _playRowTemplate = _ScoreRowData(
  label: '',
  tone: _RowTone.mutedLabel,
  height: 50,
  frontValues: ['', '', '', '', '', '', '', '', ''],
  backValues: ['', '', '', '', '', '', '', '', ''],
  summaryValues: _emptySummary,
);

class GolfScorecardScreen extends StatefulWidget {
  const GolfScorecardScreen({
    super.key,
    required this.idPartida,
    required this.jugadores,
    required this.initialPlayRowsJson,
    required this.onExit,
    required this.onLeaveGame,
    required this.onDestroyGame,
    this.differentRemotePlayRowsJson,
    this.datosServidorService,
    this.onPlayRowsJsonChanged,
    this.onLeagueRoundChanged,
    this.onFinishGame,
    this.isReadOnly = false,
    this.leagueTitle = '',
    this.leagueRound = '',
    this.leagueRoundOptions = const [],
  });

  static const double _labelWidth = 180;
  static const double _holeWidth = 48;
  static const double _subtotalWidth = 64;
  static const double _foldWidth = 0;
  static const double _summaryWidth = 82;
  static const double _cardHorizontalPadding = 48;
  static const double _cardBorderWidth = 2;
  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(24, 28, 24, 24);
  static const double scorecardContentWidth =
      _labelWidth +
      (_holeWidth * 18) +
      (_subtotalWidth * 2) +
      _foldWidth +
      (_summaryWidth * 3);
  static const double scorecardWidth =
      scorecardContentWidth + _cardHorizontalPadding + _cardBorderWidth;
  static const double _cardMinWidth = scorecardWidth;
  static const double _cardMaxWidth = 1560;
  final String idPartida;
  final String jugadores;
  final String initialPlayRowsJson;
  final String? differentRemotePlayRowsJson;
  final DatosServidorService? datosServidorService;
  final ValueChanged<String>? onPlayRowsJsonChanged;
  final Future<void> Function(String leagueRound)? onLeagueRoundChanged;
  final Future<void> Function()? onFinishGame;
  final VoidCallback onExit;
  final Future<void> Function() onLeaveGame;
  final Future<void> Function() onDestroyGame;
  final bool isReadOnly;
  final String leagueTitle;
  final String leagueRound;
  final List<int> leagueRoundOptions;

  @override
  State<GolfScorecardScreen> createState() => _GolfScorecardScreenState();
}

class _GolfScorecardScreenState extends State<GolfScorecardScreen> {
  late final DatosServidorService _datosServidorService;
  late final bool _ownsDatosServidorService;
  late List<_ScoreRowData> _guideRows;
  late List<List<String>> _playRowValues;
  late List<String> _playRowUserIds;
  late List<String> _playRowPlayerLabels;
  late List<String> _playRowModifiedValues;
  late List<int> _playRowPairNumbers;
  Map<int, int> _playerPairColorIndexes = const {};
  int _nextPairColorIndex = 0;
  String? _leagueRoundOverride;
  String? _leagueRoundError;
  String? _loadError;
  String? _pairBackendResponse;
  String? _pairBackendUrl;
  int? _selectedGuideRowPairIndex;
  bool _isLeavingGame = false;
  bool _isDestroyingGame = false;
  bool _isFinishingGame = false;
  bool _isUpdatingLeagueRound = false;

  @override
  void initState() {
    super.initState();
    unawaited(_allowScorecardOrientations());
    _ownsDatosServidorService = widget.datosServidorService == null;
    _datosServidorService =
        widget.datosServidorService ?? DatosServidorService();
    _guideRows = _buildGuideRows();
    _playRowValues = _decodePlayRows(widget.initialPlayRowsJson);
    _playRowUserIds = _decodePlayRowUserIds(widget.initialPlayRowsJson);
    _playRowPlayerLabels = _decodePlayRowPlayerLabels(
      widget.initialPlayRowsJson,
    );
    _playRowModifiedValues = _decodePlayRowModifiedValues(
      widget.initialPlayRowsJson,
    );
    _playRowPairNumbers = _decodePlayRowPairNumbers(widget.initialPlayRowsJson);
    _playerPairColorIndexes = _pairColorIndexesFromPairNumbers(
      _playRowPairNumbers,
    );
    _nextPairColorIndex = _nextPairColorIndexFromPairNumbers(
      _playRowPairNumbers,
    );
    _loadConfiguration();
  }

  @override
  void didUpdateWidget(covariant GolfScorecardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leagueRound != oldWidget.leagueRound) {
      _leagueRoundOverride = null;
    }

    if (widget.initialPlayRowsJson != oldWidget.initialPlayRowsJson) {
      _playRowValues = _decodePlayRows(widget.initialPlayRowsJson);
      _playRowUserIds = _decodePlayRowUserIds(widget.initialPlayRowsJson);
      _playRowPlayerLabels = _decodePlayRowPlayerLabels(
        widget.initialPlayRowsJson,
      );
      _playRowModifiedValues = _decodePlayRowModifiedValues(
        widget.initialPlayRowsJson,
      );
      _playRowPairNumbers = _decodePlayRowPairNumbers(
        widget.initialPlayRowsJson,
      );
      _playerPairColorIndexes = _pairColorIndexesFromPairNumbers(
        _playRowPairNumbers,
      );
      _nextPairColorIndex = _nextPairColorIndexFromPairNumbers(
        _playRowPairNumbers,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_lockScorecardPortraitOrientation());
    if (_ownsDatosServidorService) {
      _datosServidorService.close();
    }
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    try {
      final response = await _datosServidorService.cojeConfiguracionCampos(
        '1',
        'configuracion_tarjeta',
      );
      final configuration = _ScorecardConfiguration.fromBackendResponse(
        response,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _guideRows = configuration.toGuideRows();
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'No se pudo cargar la configuracion del campo.';
      });
    }
  }

  void _toggleGuideRowPair(int pairIndex) {
    setState(() {
      _selectedGuideRowPairIndex = _selectedGuideRowPairIndex == null
          ? pairIndex
          : null;
    });
  }

  Future<void> _showLeaveGameConfirmation() async {
    final confirmed = await _showScorecardConfirmationDialog(
      message:
          'Seguro que te das de baja de la partida ? Si lo haces se acabará la partida para ti',
      confirmLabel: 'Si, dame de baja',
    );
    if (confirmed != true || _isLeavingGame) {
      return;
    }

    setState(() {
      _isLeavingGame = true;
      _loadError = null;
    });

    try {
      await widget.onLeaveGame();
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = null;
      });
    } catch (error) {
      debugPrint('bajaJugadorPartida error: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'No se pudo dar de baja al jugador.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLeavingGame = false;
        });
      }
    }
  }

  Future<void> _showDestroyCardConfirmation() async {
    final confirmed = await _showScorecardConfirmationDialog(
      message:
          'Seguro que destruyes la tarjeta ? Si lo haces se acabará la partida para todos los jugadores',
      confirmLabel: 'Si, destruyela',
    );
    if (confirmed != true || _isDestroyingGame) {
      return;
    }

    setState(() {
      _isDestroyingGame = true;
      _loadError = null;
    });

    try {
      await widget.onDestroyGame();
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = null;
      });
    } catch (error) {
      debugPrint('destruyePartida error: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'No se pudo destruir la tarjeta.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDestroyingGame = false;
        });
      }
    }
  }

  Future<void> _finishGame() async {
    final onFinishGame = widget.onFinishGame;
    if (onFinishGame == null || _isFinishingGame) {
      return;
    }

    setState(() {
      _isFinishingGame = true;
      _loadError = null;
    });

    try {
      await onFinishGame();
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = null;
      });
    } catch (error) {
      debugPrint('terminar partida local error: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'No se pudo terminar la partida.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFinishingGame = false;
        });
      }
    }
  }

  Future<bool?> _showScorecardConfirmationDialog({
    required String message,
    required String confirmLabel,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar accion'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPairDialog() async {
    final result = await showDialog<_PairDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _PairPlayersDialog(
          players: _scorecardPlayers,
          pairColorIndexes: _playerPairColorIndexes,
          nextPairColorIndex: _nextPairColorIndex,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final pairJson = _pairsJson(result.pairColorIndexes);
    final pairBackendUrl = _datosServidorService
        .establecerParejasUri(idPartida: widget.idPartida, json: pairJson)
        .toString();
    await _storePairBackendDebugInfo(url: pairBackendUrl);

    try {
      final response = await _datosServidorService.establecerParejas(
        idPartida: widget.idPartida,
        json: pairJson,
      );
      await _storePairBackendDebugInfo(url: pairBackendUrl, response: response);

      if (!mounted) {
        return;
      }

      if (!_scorecardBackendResponseIsOk(response)) {
        setState(() {
          _loadError = 'No se pudieron establecer las parejas.';
          _pairBackendResponse = response;
          _pairBackendUrl = pairBackendUrl;
        });
        await _showPairBackendResponseDialog(response);
        return;
      }

      setState(() {
        _applyPairDialogResult(result);
        _pairBackendResponse = response;
        _pairBackendUrl = pairBackendUrl;
        _loadError = null;
      });
      widget.onPlayRowsJsonChanged?.call(_playRowsJsonString);
    } catch (error) {
      debugPrint('establecerParejas error: $error');
      await _storePairBackendDebugInfo(
        url: pairBackendUrl,
        response: 'ERROR: $error',
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'No se pudieron establecer las parejas.';
        _pairBackendResponse = 'ERROR: $error';
        _pairBackendUrl = pairBackendUrl;
      });
    }
  }

  Future<void> _openFullscreenScorecard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _FullscreenScorecardScreen(
          guideRows: _guideRows,
          playRowValues: _playRowValues,
          playRowLabels: _playRowPlayerLabels,
          playRowPairNumbers: _playRowPairNumbers,
          idPartida: widget.idPartida,
          jugadores: widget.jugadores,
          leagueTitle: widget.leagueTitle,
          leagueRound: _leagueRoundOverride ?? widget.leagueRound,
          leagueRoundOptions: widget.leagueRoundOptions,
          leagueRoundError: _leagueRoundError,
          isLeagueRoundUpdating: _isUpdatingLeagueRound,
          onLeagueRoundChanged: widget.onLeagueRoundChanged == null
              ? null
              : _updateLeagueRound,
          loadError: _loadError,
          onPlayValueChanged: _updatePlayValue,
          selectedGuideRowPairIndex: _selectedGuideRowPairIndex,
          onGuideRowPairToggled: _toggleGuideRowPair,
          isEditable: !widget.isReadOnly,
        ),
      ),
    );

    if (mounted) {
      unawaited(_allowScorecardOrientations());
      unawaited(_showSystemUi());
    }
  }

  void _applyPairDialogResult(_PairDialogResult result) {
    final pairNumbers = _pairNumbersFromPairColorIndexes(
      result.pairColorIndexes,
      _playRowValues.length,
    );
    final rowOrder = _rowOrderByPairNumbers(pairNumbers);

    _playRowValues = _reorderedList(_playRowValues, rowOrder);
    _playRowUserIds = _reorderedList(_playRowUserIds, rowOrder);
    _playRowPlayerLabels = _reorderedList(_playRowPlayerLabels, rowOrder);
    _playRowModifiedValues = _reorderedList(_playRowModifiedValues, rowOrder);
    _playRowPairNumbers = _reorderedList(pairNumbers, rowOrder);
    _playerPairColorIndexes = _pairColorIndexesFromPairNumbers(
      _playRowPairNumbers,
    );
    _nextPairColorIndex = _nextPairColorIndexFromPairNumbers(
      _playRowPairNumbers,
    );
  }

  Future<void> _storePairBackendDebugInfo({
    required String url,
    String? response,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_establecer_parejas_url', url);
      if (response != null) {
        await prefs.setString('last_establecer_parejas_response', response);
      }
    } catch (error) {
      debugPrint('guardar url establecerParejas error: $error');
    }
  }

  Future<void> _showPairBackendResponseDialog(String response) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Respuesta backend'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(child: SelectableText(response)),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  List<_PairPlayer> get _scorecardPlayers {
    return List.generate(_playRowValues.length, (rowIndex) {
      final label = rowIndex < _playRowPlayerLabels.length
          ? _playRowPlayerLabels[rowIndex].trim()
          : '';
      final userId = rowIndex < _playRowUserIds.length
          ? _playRowUserIds[rowIndex].trim()
          : '';
      return _PairPlayer(
        rowIndex: rowIndex,
        userId: userId,
        label: label.isEmpty ? 'Jugador ${rowIndex + 1}' : label,
      );
    }, growable: false);
  }

  String _pairsJson(Map<int, int> pairColorIndexes) {
    final playersByRowIndex = {
      for (final player in _scorecardPlayers) player.rowIndex: player,
    };
    final groupedPlayers = <int, List<_PairPlayer>>{};
    for (final entry in pairColorIndexes.entries) {
      final player = playersByRowIndex[entry.key];
      if (player == null) {
        continue;
      }
      groupedPlayers
          .putIfAbsent(entry.value, () => <_PairPlayer>[])
          .add(player);
    }

    final groupedEntries =
        groupedPlayers.entries
            .where((entry) => entry.value.length == 2)
            .toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
    final pairs = <Map<String, Object>>[
      for (var index = 0; index < groupedEntries.length; index++)
        {
          'pareja': index + 1,
          'idUsuario1': groupedEntries[index].value[0].userId,
          'idUsuario2': groupedEntries[index].value[1].userId,
        },
    ];

    return jsonEncode(pairs);
  }

  void _updatePlayValue(int rowIndex, int holeIndex, String value) {
    setState(() {
      _playRowValues[rowIndex][holeIndex] = value;
      _playRowModifiedValues[rowIndex] = _formatModifiedTimestamp(
        DateTime.now(),
      );
    });
    widget.onPlayRowsJsonChanged?.call(_playRowsJsonString);
  }

  Future<void> _updateLeagueRound(String leagueRound) async {
    final onLeagueRoundChanged = widget.onLeagueRoundChanged;
    final trimmedRound = leagueRound.trim();
    if (trimmedRound.isEmpty ||
        onLeagueRoundChanged == null ||
        _isUpdatingLeagueRound ||
        widget.isReadOnly) {
      return;
    }

    final currentRound = (_leagueRoundOverride ?? widget.leagueRound).trim();
    if (trimmedRound == currentRound) {
      return;
    }

    setState(() {
      _isUpdatingLeagueRound = true;
      _leagueRoundError = null;
    });

    try {
      await onLeagueRoundChanged(trimmedRound);
      if (!mounted) {
        return;
      }

      setState(() {
        _leagueRoundOverride = trimmedRound;
        _leagueRoundError = null;
      });
    } catch (error) {
      debugPrint('actualizaJornadaPartida error: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _leagueRoundError = 'No se pudo actualizar la jornada.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLeagueRound = false;
        });
      }
    }
  }

  String get _playRowsJsonString {
    final data = List.generate(_playRowValues.length, (rowIndex) {
      final userId = rowIndex < _playRowUserIds.length
          ? _playRowUserIds[rowIndex]
          : '';
      final playerLabel = rowIndex < _playRowPlayerLabels.length
          ? _playRowPlayerLabels[rowIndex]
          : '';
      final modified = rowIndex < _playRowModifiedValues.length
          ? _playRowModifiedValues[rowIndex]
          : '';
      final pairNumber = rowIndex < _playRowPairNumbers.length
          ? _playRowPairNumbers[rowIndex]
          : 0;
      final values = _normalizedPlayValues(_playRowValues[rowIndex]);

      return <String, String>{
        if (userId.isNotEmpty) 'idUsuario': userId,
        'jugador': playerLabel.isEmpty ? '${rowIndex + 1}' : playerLabel,
        if (pairNumber > 0) 'pareja': '$pairNumber',
        'modificado': modified,
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': values[holeIndex],
      };
    });

    return jsonEncode(data);
  }

  @override
  Widget build(BuildContext context) {
    final canLeaveGame =
        !widget.isReadOnly && _playRowValues.length > 1 && !_isLeavingGame;
    final canFinishGame =
        !widget.isReadOnly &&
        widget.onFinishGame != null &&
        _allPlayerHoleValuesAreComplete(_playRowValues);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF173F2D), Color(0xFF0B241A)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -180,
              left: -120,
              child: IgnorePointer(
                child: Container(
                  width: 520,
                  height: 520,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color.fromRGBO(188, 135, 97, 0.28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth < 980
                      ? 16.0
                      : 32.0;
                  final availableWidth = math.max(
                    0.0,
                    constraints.maxWidth - (horizontalPadding * 2),
                  );
                  final cardWidth = availableWidth
                      .clamp(
                        GolfScorecardScreen._cardMinWidth,
                        GolfScorecardScreen._cardMaxWidth,
                      )
                      .toDouble();

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: widget.onExit,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFF6F2EA),
                                    backgroundColor: const Color.fromRGBO(
                                      11,
                                      36,
                                      26,
                                      0.32,
                                    ),
                                    side: const BorderSide(
                                      color: Color(0xFFF6F2EA),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Salir'),
                                ),
                                if (canFinishGame) ...[
                                  const SizedBox(width: 10),
                                  _FinishGameButton(
                                    onPressed: _isFinishingGame
                                        ? null
                                        : _finishGame,
                                  ),
                                ],
                                const Spacer(),
                                _FullscreenScorecardIcon(
                                  onPressed: _openFullscreenScorecard,
                                ),
                                const SizedBox(width: 10),
                                _PairPlayersIcon(onPressed: _openPairDialog),
                              ],
                            ),
                            if (!widget.isReadOnly) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: availableWidth,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canLeaveGame) ...[
                                        Flexible(
                                          child: OutlinedButton.icon(
                                            onPressed:
                                                _showLeaveGameConfirmation,
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFF6F2EA,
                                              ),
                                              backgroundColor:
                                                  const Color.fromRGBO(
                                                    107,
                                                    67,
                                                    45,
                                                    0.28,
                                                  ),
                                              side: const BorderSide(
                                                color: Color(0xFFF6F2EA),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                              textStyle: const TextStyle(
                                                fontSize: 13,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            icon: const Icon(
                                              Icons.person_remove,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'Darme de baja',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Flexible(
                                        child: OutlinedButton.icon(
                                          onPressed: _isDestroyingGame
                                              ? null
                                              : _showDestroyCardConfirmation,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFFF6F2EA,
                                            ),
                                            backgroundColor:
                                                const Color.fromRGBO(
                                                  139,
                                                  58,
                                                  52,
                                                  0.32,
                                                ),
                                            side: const BorderSide(
                                              color: Color(0xFFF6F2EA),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_forever,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Destruir tarjeta',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: cardWidth,
                              child: _ScorecardCard(
                                guideRows: _guideRows,
                                playRowValues: _playRowValues,
                                playRowLabels: _playRowPlayerLabels,
                                playRowPairNumbers: _playRowPairNumbers,
                                idPartida: widget.idPartida,
                                jugadores: widget.jugadores,
                                leagueTitle: widget.leagueTitle,
                                leagueRound:
                                    _leagueRoundOverride ?? widget.leagueRound,
                                leagueRoundOptions: widget.leagueRoundOptions,
                                leagueRoundError: _leagueRoundError,
                                isLeagueRoundUpdating: _isUpdatingLeagueRound,
                                onLeagueRoundChanged:
                                    widget.onLeagueRoundChanged == null
                                    ? null
                                    : _updateLeagueRound,
                                loadError: _loadError,
                                pairBackendResponse: _pairBackendResponse,
                                pairBackendUrl: _pairBackendUrl,
                                onPlayValueChanged: _updatePlayValue,
                                selectedGuideRowPairIndex:
                                    _selectedGuideRowPairIndex,
                                onGuideRowPairToggled: _toggleGuideRowPair,
                                isEditable: !widget.isReadOnly,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenScorecardIcon extends StatelessWidget {
  const _FullscreenScorecardIcon({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pantalla completa',
      child: IconButton.filledTonal(
        key: const ValueKey('scorecard_fullscreen_icon'),
        onPressed: onPressed,
        icon: const Icon(Icons.fullscreen),
        color: const Color(0xFFF6F2EA),
        style: IconButton.styleFrom(
          backgroundColor: const Color.fromRGBO(246, 242, 234, 0.18),
          fixedSize: const Size(48, 48),
          side: const BorderSide(color: Color.fromRGBO(246, 242, 234, 0.70)),
        ),
      ),
    );
  }
}

class _FinishGameButton extends StatelessWidget {
  const _FinishGameButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const ValueKey('scorecard_finish_game_button'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFFFFF8F4),
        backgroundColor: const Color(0xFF9D433D),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.flag, size: 18),
      label: const Text(
        'Terminar',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

class _PairPlayersIcon extends StatelessWidget {
  const _PairPlayersIcon({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pareja',
      child: InkWell(
        key: const ValueKey('scorecard_pair_icon'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 66,
          height: 48,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(246, 242, 234, 0.20),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF6F2EA)),
          ),
          child: const Stack(
            children: [
              Positioned(
                left: 9,
                top: 10,
                child: Icon(Icons.person, color: Color(0xFFF6F2EA), size: 28),
              ),
              Positioned(
                right: 9,
                top: 10,
                child: Icon(Icons.person, color: Color(0xFFD7E7CF), size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairPlayersDialog extends StatefulWidget {
  const _PairPlayersDialog({
    required this.players,
    required this.pairColorIndexes,
    required this.nextPairColorIndex,
  });

  final List<_PairPlayer> players;
  final Map<int, int> pairColorIndexes;
  final int nextPairColorIndex;

  @override
  State<_PairPlayersDialog> createState() => _PairPlayersDialogState();
}

class _PairPlayersDialogState extends State<_PairPlayersDialog> {
  late Map<int, int> _pairColorIndexes;
  late int _nextPairColorIndex;
  final List<int> _selectedRowIndexes = <int>[];

  @override
  void initState() {
    super.initState();
    _pairColorIndexes = Map<int, int>.of(widget.pairColorIndexes);
    _nextPairColorIndex = widget.nextPairColorIndex;
    _pairRemainingPlayersIfExactlyTwo();
  }

  void _togglePlayer(int rowIndex) {
    setState(() {
      if (_selectedRowIndexes.remove(rowIndex)) {
        return;
      }

      if (_selectedRowIndexes.length == 2) {
        _selectedRowIndexes.removeAt(0);
      }
      _selectedRowIndexes.add(rowIndex);
    });
  }

  void _createPair() {
    if (_selectedRowIndexes.length != 2) {
      return;
    }

    setState(() {
      final selected = _selectedRowIndexes.toList(growable: false);
      for (final rowIndex in selected) {
        final previousColorIndex = _pairColorIndexes[rowIndex];
        if (previousColorIndex == null) {
          continue;
        }
        _pairColorIndexes.removeWhere(
          (_, colorIndex) => colorIndex == previousColorIndex,
        );
      }

      final pairColorIndex = _nextPairColorIndex++;
      for (final rowIndex in selected) {
        _pairColorIndexes[rowIndex] = pairColorIndex;
      }
      _selectedRowIndexes.clear();
      _pairRemainingPlayersIfExactlyTwo();
    });
  }

  void _pairRemainingPlayersIfExactlyTwo() {
    final unpairedPlayers = [
      for (final player in widget.players)
        if (!_pairColorIndexes.containsKey(player.rowIndex)) player,
    ];
    if (unpairedPlayers.length != 2) {
      return;
    }

    final pairColorIndex = _nextPairColorIndex++;
    for (final player in unpairedPlayers) {
      _pairColorIndexes[player.rowIndex] = pairColorIndex;
    }
    _selectedRowIndexes.removeWhere(
      (rowIndex) => _pairColorIndexes.containsKey(rowIndex),
    );
  }

  void _finish() {
    Navigator.of(context).pop(
      _PairDialogResult(
        pairColorIndexes: Map<int, int>.unmodifiable(_pairColorIndexes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Cancelar'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Haz click sobre los jugadores, y pulsa Crear Pareja',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: widget.players.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Sin jugadores'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.players.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final player = widget.players[index];
                    return _PairPlayerTile(
                      player: player,
                      isSelected: _selectedRowIndexes.contains(player.rowIndex),
                      pairColorIndex: _pairColorIndexes[player.rowIndex],
                      onTap: () => _togglePlayer(player.rowIndex),
                    );
                  },
                ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _selectedRowIndexes.length == 2 ? _createPair : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF567B37),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.group_add),
                label: const Text('Crea Pareja'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _finish,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF567B37),
                  side: const BorderSide(color: Color(0xFF567B37)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.check),
                label: const Text('Hecho'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PairPlayerTile extends StatelessWidget {
  const _PairPlayerTile({
    required this.player,
    required this.isSelected,
    required this.pairColorIndex,
    required this.onTap,
  });

  final _PairPlayer player;
  final bool isSelected;
  final int? pairColorIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pairColorIndex = this.pairColorIndex;
    final pairColor = pairColorIndex == null
        ? const Color(0xFFFFFFFF)
        : _pairColorForIndex(pairColorIndex);
    final borderColor = isSelected
        ? const Color(0xFF235C3D)
        : pairColorIndex == null
        ? const Color(0xFFD8D2C7)
        : _pairBorderColorForIndex(pairColorIndex);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEAF2E4) : pairColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.person,
                color: isSelected
                    ? const Color(0xFF235C3D)
                    : const Color(0xFF567B37),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  player.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF545B66),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairPlayer {
  const _PairPlayer({
    required this.rowIndex,
    required this.userId,
    required this.label,
  });

  final int rowIndex;
  final String userId;
  final String label;
}

class _PairDialogResult {
  const _PairDialogResult({required this.pairColorIndexes});

  final Map<int, int> pairColorIndexes;
}

class _FullscreenScorecardScreen extends StatefulWidget {
  const _FullscreenScorecardScreen({
    required this.guideRows,
    required this.playRowValues,
    required this.playRowLabels,
    required this.playRowPairNumbers,
    required this.idPartida,
    required this.jugadores,
    required this.leagueTitle,
    required this.leagueRound,
    required this.leagueRoundOptions,
    required this.leagueRoundError,
    required this.isLeagueRoundUpdating,
    required this.onLeagueRoundChanged,
    required this.loadError,
    required this.onPlayValueChanged,
    required this.selectedGuideRowPairIndex,
    required this.onGuideRowPairToggled,
    required this.isEditable,
  });

  final List<_ScoreRowData> guideRows;
  final List<List<String>> playRowValues;
  final List<String> playRowLabels;
  final List<int> playRowPairNumbers;
  final String idPartida;
  final String jugadores;
  final String leagueTitle;
  final String leagueRound;
  final List<int> leagueRoundOptions;
  final String? leagueRoundError;
  final bool isLeagueRoundUpdating;
  final FutureOr<void> Function(String)? onLeagueRoundChanged;
  final String? loadError;
  final void Function(int rowIndex, int holeIndex, String value)
  onPlayValueChanged;
  final int? selectedGuideRowPairIndex;
  final ValueChanged<int> onGuideRowPairToggled;
  final bool isEditable;

  @override
  State<_FullscreenScorecardScreen> createState() =>
      _FullscreenScorecardScreenState();
}

class _FullscreenScorecardScreenState
    extends State<_FullscreenScorecardScreen> {
  late int? _selectedGuideRowPairIndex;
  late String _leagueRound;
  bool _isLeagueRoundUpdating = false;

  @override
  void initState() {
    super.initState();
    _selectedGuideRowPairIndex = widget.selectedGuideRowPairIndex;
    _leagueRound = widget.leagueRound;
    _isLeagueRoundUpdating = widget.isLeagueRoundUpdating;
    unawaited(_forceScorecardLandscapeOrientation());
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(_allowScorecardOrientations());
    unawaited(_showSystemUi());
    super.dispose();
  }

  void _updatePlayValue(int rowIndex, int holeIndex, String value) {
    widget.onPlayValueChanged(rowIndex, holeIndex, value);
    setState(() {});
  }

  void _toggleGuideRowPair(int pairIndex) {
    widget.onGuideRowPairToggled(pairIndex);
    setState(() {
      _selectedGuideRowPairIndex = _selectedGuideRowPairIndex == null
          ? pairIndex
          : null;
    });
  }

  Future<void> _changeLeagueRound(String value) async {
    final onLeagueRoundChanged = widget.onLeagueRoundChanged;
    if (onLeagueRoundChanged == null || _isLeagueRoundUpdating) {
      return;
    }

    setState(() {
      _isLeagueRoundUpdating = true;
    });

    try {
      await onLeagueRoundChanged(value);
      if (mounted) {
        setState(() {
          _leagueRound = value;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeagueRoundUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071911),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(8),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: GolfScorecardScreen.scorecardWidth,
                    child: _ScorecardCard(
                      guideRows: widget.guideRows,
                      playRowValues: widget.playRowValues,
                      playRowLabels: widget.playRowLabels,
                      playRowPairNumbers: widget.playRowPairNumbers,
                      idPartida: widget.idPartida,
                      jugadores: widget.jugadores,
                      leagueTitle: widget.leagueTitle,
                      leagueRound: _leagueRound,
                      leagueRoundOptions: widget.leagueRoundOptions,
                      leagueRoundError: widget.leagueRoundError,
                      isLeagueRoundUpdating: _isLeagueRoundUpdating,
                      onLeagueRoundChanged: widget.onLeagueRoundChanged == null
                          ? null
                          : _changeLeagueRound,
                      loadError: widget.loadError,
                      pairBackendResponse: null,
                      pairBackendUrl: null,
                      onPlayValueChanged: _updatePlayValue,
                      selectedGuideRowPairIndex: _selectedGuideRowPairIndex,
                      onGuideRowPairToggled: _toggleGuideRowPair,
                      isEditable: widget.isEditable,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: SafeArea(
              child: IconButton.filled(
                key: const ValueKey('scorecard_fullscreen_exit_icon'),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Salir de pantalla completa',
                icon: const Icon(Icons.close_fullscreen),
                color: const Color(0xFFF6F2EA),
                style: IconButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(7, 25, 17, 0.76),
                  fixedSize: const Size(48, 48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorecardCard extends StatelessWidget {
  const _ScorecardCard({
    required this.guideRows,
    required this.playRowValues,
    required this.playRowLabels,
    required this.playRowPairNumbers,
    required this.idPartida,
    required this.jugadores,
    required this.leagueTitle,
    required this.leagueRound,
    required this.leagueRoundOptions,
    required this.leagueRoundError,
    required this.isLeagueRoundUpdating,
    required this.onLeagueRoundChanged,
    required this.loadError,
    required this.pairBackendResponse,
    required this.pairBackendUrl,
    required this.onPlayValueChanged,
    required this.selectedGuideRowPairIndex,
    required this.onGuideRowPairToggled,
    required this.isEditable,
  });

  final List<_ScoreRowData> guideRows;
  final List<List<String>> playRowValues;
  final List<String> playRowLabels;
  final List<int> playRowPairNumbers;
  final String idPartida;
  final String jugadores;
  final String leagueTitle;
  final String leagueRound;
  final List<int> leagueRoundOptions;
  final String? leagueRoundError;
  final bool isLeagueRoundUpdating;
  final FutureOr<void> Function(String)? onLeagueRoundChanged;
  final String? loadError;
  final String? pairBackendResponse;
  final String? pairBackendUrl;
  final void Function(int rowIndex, int holeIndex, String value)
  onPlayValueChanged;
  final int? selectedGuideRowPairIndex;
  final ValueChanged<int> onGuideRowPairToggled;
  final bool isEditable;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: GolfScorecardScreen.scorecardWidth,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color.fromRGBO(92, 68, 47, 0.18)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(28, 14, 8, 0.30),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAF8F3), Color(0xFFF6F2EA)],
        ),
      ),
      child: Padding(
        padding: GolfScorecardScreen._cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leagueTitle.trim().isNotEmpty ||
                leagueRound.trim().isNotEmpty) ...[
              _ScorecardLeagueHeader(
                title: leagueTitle,
                round: leagueRound,
                roundOptions: leagueRoundOptions,
                isUpdatingRound: isLeagueRoundUpdating,
                onRoundChanged: onLeagueRoundChanged,
              ),
              if (leagueRoundError != null) ...[
                const SizedBox(height: 8),
                Text(
                  leagueRoundError!,
                  style: const TextStyle(
                    color: Color(0xFF9D433D),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
            ],
            _ScoreGrid(
              guideRows: guideRows,
              playRowValues: playRowValues,
              playRowLabels: playRowLabels,
              playRowPairNumbers: playRowPairNumbers,
              onPlayValueChanged: onPlayValueChanged,
              selectedGuideRowPairIndex: selectedGuideRowPairIndex,
              onGuideRowPairToggled: onGuideRowPairToggled,
              isEditable: isEditable,
            ),
            if (loadError != null) ...[
              const SizedBox(height: 10),
              Text(
                loadError!,
                style: const TextStyle(color: Color(0xFF9D433D), fontSize: 13),
              ),
            ],
            if (pairBackendResponse != null || pairBackendUrl != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2E4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8FAF73)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pairBackendUrl != null) ...[
                      const Text(
                        'URL establecerParejas',
                        style: TextStyle(
                          color: Color(0xFF235C3D),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        pairBackendUrl!,
                        style: const TextStyle(
                          color: Color(0xFF2F3933),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: pairBackendUrl!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('URL copiada')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copiar URL'),
                        ),
                      ),
                    ],
                    if (pairBackendResponse != null) ...[
                      if (pairBackendUrl != null) const SizedBox(height: 12),
                      const Text(
                        'Respuesta cruda establecerParejas',
                        style: TextStyle(
                          color: Color(0xFF235C3D),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        pairBackendResponse!,
                        style: const TextStyle(
                          color: Color(0xFF2F3933),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Jugadores: $jugadores',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF545B66),
              ),
            ),
            const SizedBox(height: 18),
            const _MarkerStrip(),
          ],
        ),
      ),
    );
  }
}

class _ScorecardLeagueHeader extends StatelessWidget {
  const _ScorecardLeagueHeader({
    required this.title,
    required this.round,
    required this.roundOptions,
    required this.isUpdatingRound,
    required this.onRoundChanged,
  });

  final String title;
  final String round;
  final List<int> roundOptions;
  final bool isUpdatingRound;
  final ValueChanged<String>? onRoundChanged;

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title.trim();
    final trimmedRound = round.trim();
    final titleLabel = trimmedTitle.isEmpty ? 'Liguilla' : trimmedTitle;
    final headerLabel = trimmedRound.isEmpty
        ? titleLabel
        : '$titleLabel - jornada: $trimmedRound';
    final normalizedRoundOptions = _normalizedRoundOptions(
      roundOptions,
      currentRound: trimmedRound,
    );
    final canChangeRound =
        trimmedRound.isNotEmpty &&
        normalizedRoundOptions.isNotEmpty &&
        onRoundChanged != null &&
        !isUpdatingRound;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2E4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC7D8B8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFF567B37), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: canChangeRound
                ? PopupMenuButton<int>(
                    tooltip: 'Cambiar jornada',
                    onSelected: (value) => onRoundChanged?.call('$value'),
                    itemBuilder: (context) {
                      return [
                        for (final round in normalizedRoundOptions)
                          PopupMenuItem<int>(
                            value: round,
                            child: Text('jornada $round'),
                          ),
                      ];
                    },
                    child: _LeagueRoundButtonLabel(
                      label: headerLabel,
                      isUpdating: isUpdatingRound,
                      showDropdown: true,
                    ),
                  )
                : _LeagueRoundButtonLabel(
                    label: headerLabel,
                    isUpdating: isUpdatingRound,
                    showDropdown: false,
                  ),
          ),
        ],
      ),
    );
  }
}

class _LeagueRoundButtonLabel extends StatelessWidget {
  const _LeagueRoundButtonLabel({
    required this.label,
    required this.isUpdating,
    required this.showDropdown,
  });

  final String label;
  final bool isUpdating;
  final bool showDropdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC7D8B8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF545B66),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUpdating)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF567B37),
              ),
            )
          else if (showDropdown)
            const Icon(
              Icons.arrow_drop_down,
              color: Color(0xFF567B37),
              size: 22,
            ),
        ],
      ),
    );
  }
}

List<int> _normalizedRoundOptions(
  List<int> options, {
  required String currentRound,
}) {
  final parsedCurrentRound = int.tryParse(currentRound);
  final values = <int>{
    for (final option in options)
      if (option > 0) option,
    ?parsedCurrentRound,
  }.toList()..sort();
  values.removeWhere((value) => value <= 0);
  return values;
}

class _ScoreGrid extends StatelessWidget {
  const _ScoreGrid({
    required this.guideRows,
    required this.playRowValues,
    required this.playRowLabels,
    required this.playRowPairNumbers,
    required this.onPlayValueChanged,
    required this.selectedGuideRowPairIndex,
    required this.onGuideRowPairToggled,
    required this.isEditable,
  });

  final List<_ScoreRowData> guideRows;
  final List<List<String>> playRowValues;
  final List<String> playRowLabels;
  final List<int> playRowPairNumbers;
  final void Function(int rowIndex, int holeIndex, String value)
  onPlayValueChanged;
  final int? selectedGuideRowPairIndex;
  final ValueChanged<int> onGuideRowPairToggled;
  final bool isEditable;

  @override
  Widget build(BuildContext context) {
    final handicapValues = _handicapValuesFromGuideRows(guideRows);
    final visibleGuideRows = _visibleGuideRows(
      guideRows,
      selectedGuideRowPairIndex,
    );

    return Column(
      children: [
        const _GridHeaderRow(),
        ...visibleGuideRows.map((row) {
          final pairIndex = _guideRowPairIndexForLabel(row.label);
          return _GridDataRow(
            row: row,
            onLabelTap: pairIndex == null
                ? null
                : () => onGuideRowPairToggled(pairIndex),
          );
        }),
        ...playRowValues.asMap().entries.map((entry) {
          final rowIndex = entry.key;
          return _GridPlayRow(
            row: _playRowTemplate,
            rowIndex: rowIndex,
            values: entry.value,
            playerLabel: rowIndex < playRowLabels.length
                ? playRowLabels[rowIndex]
                : '${rowIndex + 1}',
            pairNumber: rowIndex < playRowPairNumbers.length
                ? playRowPairNumbers[rowIndex]
                : 0,
            handicapValues: handicapValues,
            isEditable: isEditable,
            onValueChanged: onPlayValueChanged,
          );
        }),
      ],
    );
  }
}

class _GridHeaderRow extends StatelessWidget {
  const _GridHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _GridCell.header(
                width: GolfScorecardScreen._labelWidth,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Text('FORAT'),
              ),
              for (final hole in _frontNine)
                _GridCell.header(
                  width: GolfScorecardScreen._holeWidth,
                  child: Text('$hole'),
                ),
              _GridCell.header(
                width: GolfScorecardScreen._subtotalWidth,
                child: const SizedBox.shrink(),
              ),
              const _FoldCell(),
              for (final hole in _backNine)
                _GridCell.header(
                  width: GolfScorecardScreen._holeWidth,
                  child: Text('$hole'),
                ),
              _GridCell.header(
                width: GolfScorecardScreen._subtotalWidth,
                child: const SizedBox.shrink(),
              ),
              for (final header in _summaryHeaders)
                _GridCell.header(
                  width: GolfScorecardScreen._summaryWidth,
                  child: Text(
                    header,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF5F7F0),
                      height: 1.1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridDataRow extends StatelessWidget {
  const _GridDataRow({required this.row, required this.onLabelTap});

  final _ScoreRowData row;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: row.height,
      child: Row(
        children: [
          _GridCell.data(
            width: GolfScorecardScreen._labelWidth,
            tone: row.tone,
            decoration: _guideLabelReliefDecoration(row.tone),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            isLabel: true,
            child: _GuideRowLabelTapTarget(
              onTap: onLabelTap,
              child: _RowLabel(row: row),
            ),
          ),
          for (final value in row.frontValues)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: row.tone,
              child: _ValueText(value),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: row.tone,
            child: _ValueText(row.frontTotal),
          ),
          const _FoldCell(),
          for (final value in row.backValues)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: row.tone,
              child: _ValueText(value),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: row.tone,
            child: _ValueText(row.backTotal),
          ),
          for (final value in row.summaryValues)
            _GridCell.summary(
              width: GolfScorecardScreen._summaryWidth,
              child: _ValueText(value),
            ),
        ],
      ),
    );
  }
}

class _GridPlayRow extends StatelessWidget {
  const _GridPlayRow({
    required this.row,
    required this.rowIndex,
    required this.values,
    required this.playerLabel,
    required this.pairNumber,
    required this.handicapValues,
    required this.isEditable,
    required this.onValueChanged,
  });

  final _ScoreRowData row;
  final int rowIndex;
  final List<String> values;
  final String playerLabel;
  final int pairNumber;
  final List<String> handicapValues;
  final bool isEditable;
  final void Function(int rowIndex, int holeIndex, String value) onValueChanged;

  @override
  Widget build(BuildContext context) {
    final frontValues = values.take(9).toList(growable: false);
    final backValues = values.skip(9).take(9).toList(growable: false);
    final frontTotal = _sumScoreValues(frontValues);
    final backTotal = _sumScoreValues(backValues);
    final roundTotal = _sumScoreValues(values);
    final tone = row.tone;

    return SizedBox(
      height: row.height,
      child: Row(
        children: [
          _GridCell.data(
            width: GolfScorecardScreen._labelWidth,
            tone: tone,
            decoration: _playerPairLabelDecoration(pairNumber),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            isLabel: true,
            child: _PlayRowLabel(label: playerLabel, isEditable: isEditable),
          ),
          for (final entry in frontValues.asMap().entries)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: tone,
              decoration: _scoreCellDecoration(
                tone,
                _scoreCellResult(
                  entry.value,
                  _holeValue(handicapValues, entry.key),
                ),
              ),
              child: isEditable
                  ? _NumericGridInput(
                      initialValue: entry.value,
                      enabled: true,
                      onChanged: (value) =>
                          onValueChanged(rowIndex, entry.key, value),
                    )
                  : _ValueText(entry.value),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: tone,
            child: _ValueText(frontTotal),
          ),
          const _FoldCell(),
          for (final entry in backValues.asMap().entries)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: tone,
              decoration: _scoreCellDecoration(
                tone,
                _scoreCellResult(
                  entry.value,
                  _holeValue(handicapValues, entry.key + 9),
                ),
              ),
              child: isEditable
                  ? _NumericGridInput(
                      initialValue: entry.value,
                      enabled: true,
                      onChanged: (value) =>
                          onValueChanged(rowIndex, entry.key + 9, value),
                    )
                  : _ValueText(entry.value),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: tone,
            child: _ValueText(backTotal),
          ),
          _GridCell.summary(
            width: GolfScorecardScreen._summaryWidth,
            child: _ValueText(roundTotal),
          ),
          for (var index = 1; index < _summaryHeaders.length; index++)
            _GridCell.summary(
              width: GolfScorecardScreen._summaryWidth,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

List<String> _handicapValuesFromGuideRows(List<_ScoreRowData> guideRows) {
  for (final row in guideRows) {
    if (row.label.trim().toLowerCase() != 'handicap') {
      continue;
    }

    return [...row.frontValues, ...row.backValues];
  }

  return const [];
}

const _guideRowLabelPairs = [
  ['metres', 'handicap'],
  ['metres eppa', 'handicap eppa'],
  ['metres blanc', 'handicap blanc'],
];

List<_ScoreRowData> _visibleGuideRows(
  List<_ScoreRowData> guideRows,
  int? selectedPairIndex,
) {
  if (selectedPairIndex == null) {
    return guideRows;
  }

  final rows = guideRows
      .where(
        (row) => _guideRowPairIndexForLabel(row.label) == selectedPairIndex,
      )
      .toList(growable: false);
  return rows.isEmpty ? guideRows : rows;
}

int? _guideRowPairIndexForLabel(String label) {
  final normalizedLabel = _normalizedGuideRowLabel(label);
  for (var index = 0; index < _guideRowLabelPairs.length; index++) {
    if (_guideRowLabelPairs[index].contains(normalizedLabel)) {
      return index;
    }
  }

  return null;
}

String _normalizedGuideRowLabel(String label) {
  return label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

Map<int, int> _pairColorIndexesFromPairNumbers(List<int> pairNumbers) {
  return {
    for (final entry in pairNumbers.asMap().entries)
      if (entry.value > 0) entry.key: entry.value - 1,
  };
}

int _nextPairColorIndexFromPairNumbers(List<int> pairNumbers) {
  return pairNumbers.fold(0, (maxPair, pairNumber) {
    return pairNumber > maxPair ? pairNumber : maxPair;
  });
}

List<int> _pairNumbersFromPairColorIndexes(
  Map<int, int> pairColorIndexes,
  int playerCount,
) {
  final colorIndexes = <int>{};
  for (final colorIndex in pairColorIndexes.values) {
    colorIndexes.add(colorIndex);
  }
  final orderedColorIndexes = colorIndexes.toList(growable: false)..sort();
  final pairNumberByColorIndex = {
    for (var index = 0; index < orderedColorIndexes.length; index++)
      orderedColorIndexes[index]: index + 1,
  };

  return List.generate(playerCount, (rowIndex) {
    final colorIndex = pairColorIndexes[rowIndex];
    if (colorIndex == null) {
      return 0;
    }

    return pairNumberByColorIndex[colorIndex] ?? 0;
  }, growable: false);
}

List<int> _rowOrderByPairNumbers(List<int> pairNumbers) {
  final rowOrder = List.generate(pairNumbers.length, (index) => index);
  if (!pairNumbers.any((pairNumber) => pairNumber > 0)) {
    return rowOrder;
  }

  rowOrder.sort((a, b) {
    final aPair = pairNumbers[a];
    final bPair = pairNumbers[b];
    final aSortPair = aPair > 0 ? aPair : 1 << 30;
    final bSortPair = bPair > 0 ? bPair : 1 << 30;
    final pairComparison = aSortPair.compareTo(bSortPair);
    return pairComparison == 0 ? a.compareTo(b) : pairComparison;
  });
  return rowOrder;
}

List<T> _reorderedList<T>(List<T> values, List<int> rowOrder) {
  return [
    for (final rowIndex in rowOrder)
      if (rowIndex >= 0 && rowIndex < values.length) values[rowIndex],
  ];
}

Color _pairColorForIndex(int index) {
  final hue = (index * 67) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.58, 0.84).toColor();
}

Color _pairBorderColorForIndex(int index) {
  final hue = (index * 67) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.54, 0.54).toColor();
}

BoxDecoration? _playerPairLabelDecoration(int pairNumber) {
  if (pairNumber <= 0) {
    return null;
  }

  final hue = ((pairNumber - 1) * 67) % 360;
  return BoxDecoration(
    color: HSLColor.fromAHSL(1, hue.toDouble(), 0.44, 0.92).toColor(),
    border: Border.fromBorderSide(_borderSide),
  );
}

String _holeValue(List<String> values, int holeIndex) {
  return holeIndex < values.length ? values[holeIndex] : '';
}

String _sumScoreValues(Iterable<String> values) {
  var total = 0;
  var hasValue = false;

  for (final value in values) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      continue;
    }

    total += parsed;
    hasValue = true;
  }

  return hasValue ? '$total' : '';
}

class _MarkerStrip extends StatelessWidget {
  const _MarkerStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          _MarkerCell.label(
            width: GolfScorecardScreen._labelWidth,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: const Text('marcador'),
          ),
          for (final _ in _frontNine)
            _MarkerCell.play(
              width: GolfScorecardScreen._holeWidth,
              child: const SizedBox.shrink(),
            ),
          _MarkerCell.total(
            width: GolfScorecardScreen._subtotalWidth,
            child: const SizedBox.shrink(),
          ),
          const _FoldCell(markerMode: true),
          for (final _ in _backNine)
            _MarkerCell.play(
              width: GolfScorecardScreen._holeWidth,
              child: const SizedBox.shrink(),
            ),
          _MarkerCell.total(
            width: GolfScorecardScreen._subtotalWidth,
            child: const SizedBox.shrink(),
          ),
          for (final _ in _summaryHeaders)
            _MarkerCell.summary(
              width: GolfScorecardScreen._summaryWidth,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell._({
    required this.width,
    required this.decoration,
    required this.defaultStyle,
    required this.child,
    this.alignment = Alignment.center,
    this.padding = EdgeInsets.zero,
  });

  factory _GridCell.header({
    required double width,
    required Widget child,
    Alignment alignment = Alignment.center,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return _GridCell._(
      width: width,
      decoration: _headerDecoration,
      defaultStyle: const TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: Color(0xFFF5F7F0),
      ),
      alignment: alignment,
      padding: padding,
      child: child,
    );
  }

  factory _GridCell.data({
    required double width,
    required Widget child,
    required _RowTone tone,
    BoxDecoration? decoration,
    Alignment alignment = Alignment.center,
    EdgeInsets padding = EdgeInsets.zero,
    bool isLabel = false,
  }) {
    return _GridCell._(
      width: width,
      decoration: decoration ?? _dataDecoration(tone, isLabel: isLabel),
      defaultStyle: TextStyle(
        fontSize: isLabel ? 15 : 14,
        color: _toneTextColor(tone),
      ),
      alignment: alignment,
      padding: padding,
      child: child,
    );
  }

  factory _GridCell.summary({required double width, required Widget child}) {
    return _GridCell._(
      width: width,
      decoration: _summaryDecoration,
      defaultStyle: const TextStyle(fontSize: 14, color: Color(0xFF56606C)),
      child: child,
    );
  }

  final double width;
  final BoxDecoration decoration;
  final TextStyle defaultStyle;
  final Widget child;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      decoration: decoration,
      alignment: alignment,
      padding: padding,
      child: DefaultTextStyle(
        style: defaultStyle,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        child: child,
      ),
    );
  }
}

class _MarkerCell extends StatelessWidget {
  const _MarkerCell._({
    required this.width,
    required this.decoration,
    required this.defaultStyle,
    required this.child,
    this.alignment = Alignment.center,
    this.padding = EdgeInsets.zero,
  });

  factory _MarkerCell.label({
    required double width,
    required Widget child,
    Alignment alignment = Alignment.center,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return _MarkerCell._(
      width: width,
      decoration: _markerPlayDecoration,
      defaultStyle: const TextStyle(
        fontSize: 21,
        fontStyle: FontStyle.italic,
        color: Color(0xFF49504D),
      ),
      alignment: alignment,
      padding: padding,
      child: child,
    );
  }

  factory _MarkerCell.play({required double width, required Widget child}) {
    return _MarkerCell._(
      width: width,
      decoration: _markerPlayDecoration,
      defaultStyle: const TextStyle(fontSize: 14),
      child: child,
    );
  }

  factory _MarkerCell.total({required double width, required Widget child}) {
    return _MarkerCell._(
      width: width,
      decoration: _markerTotalDecoration,
      defaultStyle: const TextStyle(fontSize: 14),
      child: child,
    );
  }

  factory _MarkerCell.summary({required double width, required Widget child}) {
    return _MarkerCell._(
      width: width,
      decoration: _markerSummaryDecoration,
      defaultStyle: const TextStyle(fontSize: 14),
      child: child,
    );
  }

  final double width;
  final BoxDecoration decoration;
  final TextStyle defaultStyle;
  final Widget child;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      decoration: decoration,
      alignment: alignment,
      padding: padding,
      child: DefaultTextStyle(
        style: defaultStyle,
        overflow: TextOverflow.ellipsis,
        child: child,
      ),
    );
  }
}

class _FoldCell extends StatelessWidget {
  const _FoldCell({this.markerMode = false});

  final bool markerMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: GolfScorecardScreen._foldWidth,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.fromRGBO(255, 255, 255, 0.22),
            Color.fromRGBO(255, 255, 255, 0.96),
            Color.fromRGBO(209, 212, 218, 0.82),
            Color.fromRGBO(255, 255, 255, 0.96),
            Color.fromRGBO(255, 255, 255, 0.22),
          ],
          stops: [0.0, 0.46, 0.5, 0.54, 1.0],
        ),
      ),
      child: markerMode ? const SizedBox.expand() : null,
    );
  }
}

class _GuideRowLabelTapTarget extends StatelessWidget {
  const _GuideRowLabelTapTarget({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox.expand(
      child: Align(alignment: Alignment.centerLeft, child: child),
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.row});

  final _ScoreRowData row;

  @override
  Widget build(BuildContext context) {
    final primaryColor = row.tone == _RowTone.red
        ? const Color(0xFFFFF7F8)
        : const Color(0xFF5F5737);

    if (row.label.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
            color: primaryColor,
          ),
        ),
      ],
    );
  }
}

class _PlayRowLabel extends StatelessWidget {
  const _PlayRowLabel({required this.label, required this.isEditable});

  final String label;
  final bool isEditable;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: isEditable ? const Color(0xFF4F5B43) : const Color(0xFF8D928B),
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      value,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _NumericGridInput extends StatefulWidget {
  const _NumericGridInput({
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
  });

  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_NumericGridInput> createState() => _NumericGridInputState();
}

class _NumericGridInputState extends State<_NumericGridInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_selectValueOnFocus);
  }

  @override
  void didUpdateWidget(covariant _NumericGridInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_selectValueOnFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _selectValueOnFocus() {
    if (!_focusNode.hasFocus || !widget.enabled) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus || !widget.enabled) {
        return;
      }

      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      enabled: widget.enabled,
      readOnly: !widget.enabled,
      showCursor: widget.enabled,
      enableSuggestions: false,
      autocorrect: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: widget.enabled
            ? const Color(0xFF545B66)
            : const Color.fromRGBO(84, 91, 102, 0.42),
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      onChanged: widget.onChanged,
      onTapOutside: (_) => _focusNode.unfocus(),
    );
  }
}

class _ScoreRowData {
  const _ScoreRowData({
    required this.label,
    required this.frontValues,
    required this.backValues,
    this.frontTotal = '',
    this.backTotal = '',
    this.summaryValues = _emptySummary,
    this.tone = _RowTone.base,
    this.height = 44,
  });

  final String label;
  final List<String> frontValues;
  final List<String> backValues;
  final String frontTotal;
  final String backTotal;
  final List<String> summaryValues;
  final _RowTone tone;
  final double height;
}

class _ScorecardConfiguration {
  const _ScorecardConfiguration({required this.holes});

  final List<_HoleConfiguration> holes;

  factory _ScorecardConfiguration.fromBackendResponse(String rawResponse) {
    final valor = _extractValor(rawResponse);

    final decodedValor = jsonDecode(valor);
    if (decodedValor is! List) {
      throw const FormatException('El valor de configuracion no es una lista.');
    }

    return _ScorecardConfiguration(
      holes: decodedValor
          .whereType<Map<String, dynamic>>()
          .map(_HoleConfiguration.fromJson)
          .toList(),
    );
  }

  static String _extractValor(String rawResponse) {
    try {
      final decodedResponse = jsonDecode(rawResponse);
      if (decodedResponse is! Map<String, dynamic>) {
        throw const FormatException('La respuesta del backend no es valida.');
      }

      final valor = decodedResponse['valor'];
      if (valor is! String) {
        throw const FormatException('La configuracion recibida no es valida.');
      }

      return valor;
    } on FormatException {
      final trimmedResponse = rawResponse.trim();
      final match = RegExp(
        r'^\{"rpta":"[^"]*","valor":"(.*)"\}$',
        dotAll: true,
      ).firstMatch(trimmedResponse);

      if (match == null) {
        rethrow;
      }

      return match.group(1) ?? '';
    }
  }

  List<_ScoreRowData> toGuideRows() {
    return [
      _rowFromMetric(
        label: 'metres',
        tone: _RowTone.yellow,
        includeTotals: true,
        selector: (hole) => hole.metres,
      ),
      _rowFromMetric(
        label: 'handicap',
        tone: _RowTone.lightYellow,
        selector: (hole) => hole.handicap,
      ),
      _rowFromMetric(
        label: 'metres EPPA',
        tone: _RowTone.red,
        includeTotals: true,
        selector: (hole) => hole.metresEppa,
      ),
      _rowFromMetric(
        label: 'handicap EPPA',
        tone: _RowTone.lightRed,
        selector: (hole) => hole.handicapEppa,
      ),
      _rowFromMetric(
        label: 'metres BLANC',
        tone: _RowTone.lightGray,
        includeTotals: true,
        selector: (hole) => hole.metresBlanc,
      ),
      _rowFromMetric(
        label: 'handicap BLANC',
        selector: (hole) => hole.handicapBlanc,
      ),
    ];
  }

  _ScoreRowData _rowFromMetric({
    required String label,
    _RowTone tone = _RowTone.base,
    bool includeTotals = false,
    required String Function(_HoleConfiguration hole) selector,
  }) {
    final valuesByHole = <int, String>{
      for (final hole in holes) hole.hoyo: selector(hole),
    };

    final frontValues = _frontNine
        .map((hole) => valuesByHole[hole] ?? '')
        .toList(growable: false);
    final backValues = _backNine
        .map((hole) => valuesByHole[hole] ?? '')
        .toList(growable: false);

    return _ScoreRowData(
      label: label,
      tone: tone,
      frontValues: frontValues,
      backValues: backValues,
      frontTotal: includeTotals ? _sumValues(frontValues) : '',
      backTotal: includeTotals ? _sumValues(backValues) : '',
      summaryValues: _emptySummary,
    );
  }

  static String _sumValues(List<String> values) {
    var total = 0;
    var hasValue = false;

    for (final value in values) {
      final parsed = int.tryParse(value);
      if (parsed == null) {
        continue;
      }
      total += parsed;
      hasValue = true;
    }

    return hasValue ? '$total' : '';
  }
}

class _HoleConfiguration {
  const _HoleConfiguration({
    required this.hoyo,
    required this.metres,
    required this.handicap,
    required this.metresEppa,
    required this.handicapEppa,
    required this.metresBlanc,
    required this.handicapBlanc,
  });

  final int hoyo;
  final String metres;
  final String handicap;
  final String metresEppa;
  final String handicapEppa;
  final String metresBlanc;
  final String handicapBlanc;

  factory _HoleConfiguration.fromJson(Map<String, dynamic> json) {
    return _HoleConfiguration(
      hoyo: int.tryParse('${json['hoyo'] ?? ''}') ?? 0,
      metres: '${json['metros'] ?? ''}',
      handicap: '${json['handicap'] ?? ''}',
      metresEppa: '${json['metros_EPPA'] ?? ''}',
      handicapEppa: '${json['handicap_EPPA'] ?? json['hadicap_EPPA'] ?? ''}',
      metresBlanc: '${json['metros_BLANC'] ?? ''}',
      handicapBlanc: '${json['handicap_BLANC'] ?? ''}',
    );
  }
}

List<_ScoreRowData> _buildGuideRows() {
  return const [
    _ScoreRowData(
      label: 'metres',
      tone: _RowTone.yellow,
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'handicap',
      tone: _RowTone.lightYellow,
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'metres EPPA',
      tone: _RowTone.red,
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'handicap EPPA',
      tone: _RowTone.lightRed,
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'metres BLANC',
      tone: _RowTone.lightGray,
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'handicap BLANC',
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
  ];
}

List<List<String>> _decodePlayRows(String rawJson) {
  return _decodePlayRowStates(
    rawJson,
  ).map((row) => row.values).toList(growable: false);
}

List<String> _decodePlayRowUserIds(String rawJson) {
  return _decodePlayRowStates(
    rawJson,
  ).map((row) => row.userId).toList(growable: false);
}

List<String> _decodePlayRowPlayerLabels(String rawJson) {
  return _decodePlayRowStates(
    rawJson,
  ).map((row) => row.playerLabel).toList(growable: false);
}

List<String> _decodePlayRowModifiedValues(String rawJson) {
  return _decodePlayRowStates(
    rawJson,
  ).map((row) => row.modified).toList(growable: false);
}

List<int> _decodePlayRowPairNumbers(String rawJson) {
  return _decodePlayRowStates(
    rawJson,
  ).map((row) => row.pairNumber).toList(growable: false);
}

List<_DecodedPlayRow> _decodePlayRowStates(String rawJson) {
  final decoded = _decodePlayRowsList(rawJson);
  if (decoded == null) {
    return const [];
  }

  final rows = <_DecodedPlayRow>[];
  for (var rowIndex = 0; rowIndex < decoded.length; rowIndex++) {
    final row = decoded[rowIndex];
    if (row is! Map) {
      continue;
    }

    final userId = '${row['idUsuario'] ?? row['idJugador'] ?? ''}'.trim();
    final rawPlayerLabel = '${row['jugador'] ?? ''}'.trim();
    final pairNumber = _intFromJsonLikeValue(row['pareja']) ?? 0;
    final values = List.generate(18, (holeIndex) {
      final value = row['hoyo_${holeIndex + 1}'];
      return value == null ? '' : '$value';
    }, growable: false);
    final hasScores = values.any((value) => value.trim().isNotEmpty);
    final hasPlayer =
        userId.isNotEmpty ||
        (rawPlayerLabel.isNotEmpty &&
            !_isPlaceholderPlayerLabel(rawPlayerLabel, rowIndex));

    if (!hasPlayer && !hasScores) {
      continue;
    }

    rows.add(
      _DecodedPlayRow(
        userId: userId,
        playerLabel: rawPlayerLabel.isEmpty
            ? '${rows.length + 1}'
            : rawPlayerLabel,
        modified: '${row['modificado'] ?? ''}',
        pairNumber: pairNumber,
        values: values,
      ),
    );
  }

  return _orderedDecodedPlayRows(rows);
}

int? _intFromJsonLikeValue(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse('${value ?? ''}'.trim());
}

List<_DecodedPlayRow> _orderedDecodedPlayRows(List<_DecodedPlayRow> rows) {
  if (!rows.any((row) => row.pairNumber > 0)) {
    return rows;
  }

  final indexedRows = rows.indexed.toList(growable: false);
  indexedRows.sort((a, b) {
    final aPair = a.$2.pairNumber;
    final bPair = b.$2.pairNumber;
    final aSortPair = aPair > 0 ? aPair : 1 << 30;
    final bSortPair = bPair > 0 ? bPair : 1 << 30;
    final pairComparison = aSortPair.compareTo(bSortPair);
    return pairComparison == 0 ? a.$1.compareTo(b.$1) : pairComparison;
  });

  return [for (final indexedRow in indexedRows) indexedRow.$2];
}

bool _isPlaceholderPlayerLabel(String label, int rowIndex) {
  return label.trim() == '${rowIndex + 1}';
}

bool _allPlayerHoleValuesAreComplete(List<List<String>> playRowValues) {
  if (playRowValues.isEmpty) {
    return false;
  }

  return playRowValues.every((values) {
    return _normalizedPlayValues(
      values,
    ).every((value) => value.trim().isNotEmpty);
  });
}

List<String> _normalizedPlayValues(List<String> values) {
  return List.generate(
    18,
    (index) => index < values.length ? values[index] : '',
    growable: false,
  );
}

List<dynamic>? _decodePlayRowsList(String rawJson) {
  final decoded = _decodeJsonLikePayload(rawJson.trim());
  return decoded is List ? decoded : null;
}

Object? _decodeJsonLikePayload(String rawPayload) {
  if (rawPayload.isEmpty) {
    return null;
  }

  try {
    return jsonDecode(rawPayload);
  } catch (_) {
    // Algunas respuestas antiguas del backend llegan con comillas simples.
  }

  try {
    return jsonDecode(rawPayload.replaceAll("'", '"'));
  } catch (_) {
    return null;
  }
}

bool _scorecardBackendResponseIsOk(String response) {
  final trimmedResponse = response.trim();
  if (trimmedResponse.toLowerCase() == 'ok') {
    return true;
  }

  final decoded = _decodeJsonLikePayload(trimmedResponse);
  if (decoded is Map) {
    final value = decoded['rpta'] ?? decoded['rtpta'];
    return '$value'.trim().toLowerCase() == 'ok';
  }

  return false;
}

String _formatModifiedTimestamp(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${twoDigits(dateTime.year % 100)}'
      '${twoDigits(dateTime.month)}'
      '${twoDigits(dateTime.day)}'
      '${twoDigits(dateTime.hour)}'
      '${twoDigits(dateTime.minute)}'
      '${twoDigits(dateTime.second)}';
}

class _DecodedPlayRow {
  const _DecodedPlayRow({
    required this.userId,
    required this.playerLabel,
    required this.modified,
    required this.pairNumber,
    required this.values,
  });

  final String userId;
  final String playerLabel;
  final String modified;
  final int pairNumber;
  final List<String> values;
}

enum _RowTone {
  base,
  yellow,
  lightYellow,
  red,
  lightRed,
  lightGray,
  mutedLabel,
  disabledPlay,
}

const _borderSide = BorderSide(
  color: Color.fromRGBO(88, 95, 102, 0.34),
  width: 0.7,
);

const _headerDecoration = BoxDecoration(
  border: Border.fromBorderSide(_borderSide),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2F5A44), Color(0xFF264836)],
  ),
);

const _summaryDecoration = BoxDecoration(
  border: Border.fromBorderSide(_borderSide),
  color: Color.fromRGBO(255, 255, 255, 0.90),
);

const _markerPlayDecoration = BoxDecoration(
  border: Border.fromBorderSide(_borderSide),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE2EBA3), Color(0xFFDAE68F)],
  ),
);

const _markerTotalDecoration = BoxDecoration(
  border: Border.fromBorderSide(_borderSide),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFCADBDD), Color(0xFFBFD2D3)],
  ),
);

const _markerSummaryDecoration = BoxDecoration(
  border: Border.fromBorderSide(_borderSide),
  color: Color.fromRGBO(255, 255, 255, 0.92),
);

BoxDecoration _dataDecoration(_RowTone tone, {required bool isLabel}) {
  switch (tone) {
    case _RowTone.yellow:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE7D665), Color(0xFFDECA58)],
        ),
      );
    case _RowTone.lightYellow:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        color: Color(0xFFFFF8D6),
      );
    case _RowTone.red:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCD6474), Color(0xFFBB4D5D)],
        ),
      );
    case _RowTone.lightRed:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        color: Color(0xFFFFE8EC),
      );
    case _RowTone.lightGray:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        color: Color(0xFFF0F2F3),
      );
    case _RowTone.mutedLabel:
      return BoxDecoration(
        border: const Border.fromBorderSide(_borderSide),
        color: isLabel
            ? const Color.fromRGBO(224, 230, 229, 0.72)
            : const Color.fromRGBO(255, 255, 255, 0.80),
      );
    case _RowTone.disabledPlay:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        color: Color.fromRGBO(226, 228, 232, 0.92),
      );
    case _RowTone.base:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        color: Color.fromRGBO(255, 255, 255, 0.80),
      );
  }
}

BoxDecoration _guideLabelReliefDecoration(_RowTone tone) {
  return BoxDecoration(
    border: const Border.fromBorderSide(_borderSide),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _guideLabelReliefColors(tone),
    ),
    boxShadow: const [
      BoxShadow(
        color: Color.fromRGBO(255, 255, 255, 0.72),
        offset: Offset(-1.2, -1.2),
        blurRadius: 1.4,
      ),
      BoxShadow(
        color: Color.fromRGBO(31, 24, 19, 0.24),
        offset: Offset(1.5, 1.6),
        blurRadius: 2.4,
      ),
    ],
  );
}

List<Color> _guideLabelReliefColors(_RowTone tone) {
  switch (tone) {
    case _RowTone.yellow:
      return const [Color(0xFFF0E282), Color(0xFFD1BC43)];
    case _RowTone.lightYellow:
      return const [Color(0xFFFFFDF0), Color(0xFFFFEDAA)];
    case _RowTone.red:
      return const [Color(0xFFD97987), Color(0xFFB13F4F)];
    case _RowTone.lightRed:
      return const [Color(0xFFFFF8FA), Color(0xFFFFCED8)];
    case _RowTone.lightGray:
      return const [Color(0xFFFFFFFF), Color(0xFFDDE2E5)];
    case _RowTone.mutedLabel:
      return const [Color(0xFFF1F5F4), Color(0xFFD1DBD9)];
    case _RowTone.disabledPlay:
      return const [Color(0xFFF1F3F5), Color(0xFFD4D8DE)];
    case _RowTone.base:
      return const [Color(0xFFFFFFFF), Color(0xFFE8ECEC)];
  }
}

Color _toneTextColor(_RowTone tone) {
  switch (tone) {
    case _RowTone.yellow:
      return const Color(0xFF5F5737);
    case _RowTone.red:
      return const Color(0xFFFFF7F8);
    case _RowTone.disabledPlay:
      return const Color.fromRGBO(84, 91, 102, 0.52);
    case _RowTone.lightYellow:
    case _RowTone.lightRed:
    case _RowTone.lightGray:
    case _RowTone.base:
    case _RowTone.mutedLabel:
      return const Color(0xFF56606C);
  }
}

BoxDecoration _scoreCellDecoration(_RowTone tone, _ScoreCellResult? result) {
  if (result == null || tone == _RowTone.disabledPlay) {
    return _dataDecoration(tone, isLabel: false);
  }

  return BoxDecoration(
    border: const Border.fromBorderSide(_borderSide),
    color: _scoreCellColor(result),
  );
}

Color _scoreCellColor(_ScoreCellResult result) {
  switch (result) {
    case _ScoreCellResult.underHandicap:
      return const Color(0xFFE1F3DA);
    case _ScoreCellResult.equalHandicap:
      return const Color(0xFFFFFBE8);
    case _ScoreCellResult.oneOverHandicap:
      return const Color(0xFFDCEEFF);
    case _ScoreCellResult.overOneOverHandicap:
      return const Color(0xFFBFD9F2);
  }
}

_ScoreCellResult? _scoreCellResult(String scoreValue, String handicapValue) {
  final score = int.tryParse(scoreValue.trim());
  final handicap = int.tryParse(handicapValue.trim());
  if (score == null || handicap == null) {
    return null;
  }

  if (score < handicap) {
    return _ScoreCellResult.underHandicap;
  }

  if (score == handicap) {
    return _ScoreCellResult.equalHandicap;
  }

  if (score == handicap + 1) {
    return _ScoreCellResult.oneOverHandicap;
  }

  return _ScoreCellResult.overOneOverHandicap;
}

enum _ScoreCellResult {
  underHandicap,
  equalHandicap,
  oneOverHandicap,
  overOneOverHandicap,
}
