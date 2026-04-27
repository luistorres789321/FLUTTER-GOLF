import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_golf/services/datos_servidor_service.dart';

const _frontNine = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const _backNine = [10, 11, 12, 13, 14, 15, 16, 17, 18];
const _summaryHeaders = ['TOTAL', 'HCP JUEGO', 'NETO'];
const _emptySummary = ['', '', ''];

const _playRows = [
  _ScoreRowData(
    label: '',
    tone: _RowTone.mutedLabel,
    height: 50,
    frontValues: ['', '', '', '', '', '', '', '', ''],
    backValues: ['', '', '', '', '', '', '', '', ''],
    summaryValues: _emptySummary,
  ),
  _ScoreRowData(
    label: '',
    tone: _RowTone.mutedLabel,
    height: 50,
    frontValues: ['', '', '', '', '', '', '', '', ''],
    backValues: ['', '', '', '', '', '', '', '', ''],
    summaryValues: _emptySummary,
  ),
  _ScoreRowData(
    label: '',
    tone: _RowTone.mutedLabel,
    height: 50,
    frontValues: ['', '', '', '', '', '', '', '', ''],
    backValues: ['', '', '', '', '', '', '', '', ''],
    summaryValues: _emptySummary,
  ),
  _ScoreRowData(
    label: '',
    tone: _RowTone.mutedLabel,
    height: 50,
    frontValues: ['', '', '', '', '', '', '', '', ''],
    backValues: ['', '', '', '', '', '', '', '', ''],
    summaryValues: _emptySummary,
  ),
];

const _formFields = [
  _FormFieldData(label: 'COMPETICION'),
  _FormFieldData(label: 'MODALIDAD'),
  _FormFieldData(label: 'FORMULA'),
  _FormFieldData(label: 'HOYO'),
  _FormFieldData(label: 'FECHA'),
  _FormFieldData(label: 'EQUIPO'),
];

const _preferenceColumns = [
  _PreferenceColumnData(
    title: 'CABALLEROS',
    items: ['metres', 'metres EPPA', 'STABLEFORD'],
  ),
  _PreferenceColumnData(
    title: 'DAMAS',
    items: ['metres', 'metres EPPA', 'MEDAL PLAY'],
  ),
];

class GolfScorecardScreen extends StatefulWidget {
  const GolfScorecardScreen({
    super.key,
    required this.idPartida,
    required this.jugadores,
    required this.initialPlayRowsJson,
    this.differentRemotePlayRowsJson,
    this.onPlayRowsJsonChanged,
  });

  static const double _labelWidth = 180;
  static const double _holeWidth = 48;
  static const double _subtotalWidth = 64;
  static const double _foldWidth = 18;
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
  final ValueChanged<String>? onPlayRowsJsonChanged;

  @override
  State<GolfScorecardScreen> createState() => _GolfScorecardScreenState();
}

class _GolfScorecardScreenState extends State<GolfScorecardScreen> {
  late final DatosServidorService _datosServidorService;
  late List<_ScoreRowData> _guideRows;
  late List<List<String>> _playRowValues;
  late List<String> _playRowModifiedValues;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _datosServidorService = DatosServidorService();
    _guideRows = _buildGuideRows();
    _playRowValues = _decodePlayRows(widget.initialPlayRowsJson);
    _playRowModifiedValues = _decodePlayRowModifiedValues(
      widget.initialPlayRowsJson,
    );
    _loadConfiguration();
  }

  @override
  void didUpdateWidget(covariant GolfScorecardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPlayRowsJson == oldWidget.initialPlayRowsJson) {
      return;
    }

    _playRowValues = _decodePlayRows(widget.initialPlayRowsJson);
    _playRowModifiedValues = _decodePlayRowModifiedValues(
      widget.initialPlayRowsJson,
    );
  }

  @override
  void dispose() {
    _datosServidorService.close();
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

  void _updatePlayValue(int rowIndex, int holeIndex, String value) {
    setState(() {
      _playRowValues[rowIndex][holeIndex] = value;
      _playRowModifiedValues[rowIndex] = _formatModifiedTimestamp(
        DateTime.now(),
      );
    });
    widget.onPlayRowsJsonChanged?.call(_playRowsJsonString);
  }

  String get _playRowsJsonString {
    final data = List.generate(_playRowValues.length, (rowIndex) {
      return <String, String>{
        'jugador': '${rowIndex + 1}',
        'modificado': _playRowModifiedValues[rowIndex],
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': _playRowValues[rowIndex][holeIndex],
      };
    });

    return jsonEncode(data);
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: cardWidth,
                          child: _ScorecardCard(
                            guideRows: _guideRows,
                            playRowValues: _playRowValues,
                            idPartida: widget.idPartida,
                            jugadores: widget.jugadores,
                            loadError: _loadError,
                            onPlayValueChanged: _updatePlayValue,
                            playRowsJsonString: _playRowsJsonString,
                            differentRemotePlayRowsJson:
                                widget.differentRemotePlayRowsJson,
                          ),
                        ),
                      ),
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

class _ScorecardCard extends StatelessWidget {
  const _ScorecardCard({
    required this.guideRows,
    required this.playRowValues,
    required this.idPartida,
    required this.jugadores,
    required this.loadError,
    required this.onPlayValueChanged,
    required this.playRowsJsonString,
    required this.differentRemotePlayRowsJson,
  });

  final List<_ScoreRowData> guideRows;
  final List<List<String>> playRowValues;
  final String idPartida;
  final String jugadores;
  final String? loadError;
  final void Function(int rowIndex, int holeIndex, String value)
  onPlayValueChanged;
  final String playRowsJsonString;
  final String? differentRemotePlayRowsJson;

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
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                child: Container(
                  width: 20,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Color.fromRGBO(215, 217, 223, 0.84),
                        Color.fromRGBO(255, 255, 255, 0.98),
                        Color.fromRGBO(215, 217, 223, 0.84),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.18, 0.5, 0.82, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: GolfScorecardScreen._cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScoreGrid(
                  guideRows: guideRows,
                  playRowValues: playRowValues,
                  jugadores: jugadores,
                  onPlayValueChanged: onPlayValueChanged,
                ),
                if (loadError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    loadError!,
                    style: const TextStyle(
                      color: Color(0xFF9D433D),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'idPartida: $idPartida · Jugadores: $jugadores',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF545B66),
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  playRowsJsonString,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF545B66),
                  ),
                ),
                if (differentRemotePlayRowsJson != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    differentRemotePlayRowsJson!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A1E1E),
                    ),
                  ),
                ],
                SizedBox(height: 22),
                const _LowerSection(),
                const SizedBox(height: 18),
                const _MarkerStrip(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreGrid extends StatelessWidget {
  const _ScoreGrid({
    required this.guideRows,
    required this.playRowValues,
    required this.jugadores,
    required this.onPlayValueChanged,
  });

  final List<_ScoreRowData> guideRows;
  final List<List<String>> playRowValues;
  final String jugadores;
  final void Function(int rowIndex, int holeIndex, String value)
  onPlayValueChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _GridHeaderRow(),
        ...guideRows.map(_GridDataRow.new),
        ..._playRows.asMap().entries.map(
          (entry) => _GridPlayRow(
            row: entry.value,
            rowIndex: entry.key,
            values: playRowValues[entry.key],
            isEditable: entry.key < (int.tryParse(jugadores) ?? 0).clamp(0, 4),
            onValueChanged: onPlayValueChanged,
          ),
        ),
      ],
    );
  }
}

class _GridHeaderRow extends StatelessWidget {
  const _GridHeaderRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

class _GridDataRow extends StatelessWidget {
  const _GridDataRow(this.row);

  final _ScoreRowData row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: row.height,
      child: Row(
        children: [
          _GridCell.data(
            width: GolfScorecardScreen._labelWidth,
            tone: row.tone,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            isLabel: true,
            child: _RowLabel(row: row),
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
    required this.isEditable,
    required this.onValueChanged,
  });

  final _ScoreRowData row;
  final int rowIndex;
  final List<String> values;
  final bool isEditable;
  final void Function(int rowIndex, int holeIndex, String value) onValueChanged;

  @override
  Widget build(BuildContext context) {
    final frontValues = values.take(9).toList(growable: false);
    final backValues = values.skip(9).take(9).toList(growable: false);
    final tone = isEditable ? row.tone : _RowTone.disabledPlay;

    return SizedBox(
      height: row.height,
      child: Row(
        children: [
          _GridCell.data(
            width: GolfScorecardScreen._labelWidth,
            tone: tone,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            isLabel: true,
            child: _RowLabel(row: row),
          ),
          for (final entry in frontValues.asMap().entries)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: tone,
              child: _NumericGridInput(
                initialValue: entry.value,
                enabled: isEditable,
                onChanged: (value) =>
                    onValueChanged(rowIndex, entry.key, value),
              ),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: tone,
            child: const SizedBox.shrink(),
          ),
          const _FoldCell(),
          for (final entry in backValues.asMap().entries)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: tone,
              child: _NumericGridInput(
                initialValue: entry.value,
                enabled: isEditable,
                onChanged: (value) =>
                    onValueChanged(rowIndex, entry.key + 9, value),
              ),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: tone,
            child: const SizedBox.shrink(),
          ),
          for (final _ in _summaryHeaders)
            _GridCell.summary(
              width: GolfScorecardScreen._summaryWidth,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _LowerSection extends StatelessWidget {
  const _LowerSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Column(
              children: _formFields.map((field) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FormLineRow(field: field),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(child: _SignaturesPanel()),
                SizedBox(width: 16),
                SizedBox(width: 260, child: _PreferencesPanel()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FormLineRow extends StatelessWidget {
  const _FormLineRow({required this.field});

  final _FormFieldData field;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontSize: 15,
      letterSpacing: 0.3,
      color: Color(0xFF545B66),
    );

    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(field.label, style: textStyle),
          const SizedBox(width: 8),
          const Expanded(child: _LineField()),
        ],
      ),
    );
  }
}

class _LineField extends StatelessWidget {
  const _LineField();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -4),
      child: SizedBox(
        height: 18,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentCount = (constraints.maxWidth / 8).floor().clamp(
              1,
              300,
            );

            return Row(
              children: List.generate(segmentCount, (index) {
                return Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      color: const Color.fromRGBO(115, 120, 131, 0.34),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _SignaturesPanel extends StatelessWidget {
  const _SignaturesPanel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'Signatures',
            style: TextStyle(fontSize: 26, color: Color(0xFF555D69)),
          ),
          SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                'JUGADOR',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 0.6,
                  color: Color(0xFF555D69),
                ),
              ),
              Text(
                'MARCADOR',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 0.6,
                  color: Color(0xFF555D69),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: const Color.fromRGBO(255, 255, 255, 0.84),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(128, 134, 144, 0.34),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFB7C849), Color(0xFF9AAE34)],
              ),
            ),
            child: const Text(
              'PREFERENCIES DE PAS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Color(0xFFF5F8EF),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _preferenceColumns.asMap().entries.map((entry) {
              final index = entry.key;
              final column = entry.value;

              return Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    border: index == 0
                        ? null
                        : const Border(
                            left: BorderSide(
                              color: Color.fromRGBO(128, 134, 144, 0.28),
                            ),
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        column.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF565D68),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...column.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            item,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF565D68),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
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
    Alignment alignment = Alignment.center,
    EdgeInsets padding = EdgeInsets.zero,
    bool isLabel = false,
  }) {
    return _GridCell._(
      width: width,
      decoration: _dataDecoration(tone, isLabel: isLabel),
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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
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
        fontSize: 15,
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
        LengthLimitingTextInputFormatter(3),
      ],
      onChanged: widget.onChanged,
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
      _rowFromMetric(label: 'handicap', selector: (hole) => hole.handicap),
      _rowFromMetric(
        label: 'metres EPPA',
        tone: _RowTone.red,
        includeTotals: true,
        selector: (hole) => hole.metresEppa,
      ),
      _rowFromMetric(
        label: 'handicap EPPA',
        selector: (hole) => hole.handicapEppa,
      ),
      _rowFromMetric(
        label: 'metres BLANC',
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
      frontValues: ['', '', '', '', '', '', '', '', ''],
      backValues: ['', '', '', '', '', '', '', '', ''],
      summaryValues: _emptySummary,
    ),
    _ScoreRowData(
      label: 'metres BLANC',
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
  final emptyRows = List.generate(4, (_) => List.filled(18, ''));

  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      return emptyRows;
    }

    for (
      var rowIndex = 0;
      rowIndex < 4 && rowIndex < decoded.length;
      rowIndex++
    ) {
      final row = decoded[rowIndex];
      if (row is! Map) {
        continue;
      }
      for (var holeIndex = 0; holeIndex < 18; holeIndex++) {
        final value = row['hoyo_${holeIndex + 1}'];
        emptyRows[rowIndex][holeIndex] = value == null ? '' : '$value';
      }
    }
  } catch (_) {
    return emptyRows;
  }

  return emptyRows;
}

List<String> _decodePlayRowModifiedValues(String rawJson) {
  final modifiedValues = List.filled(4, '');

  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) {
      return modifiedValues;
    }

    for (
      var rowIndex = 0;
      rowIndex < 4 && rowIndex < decoded.length;
      rowIndex++
    ) {
      final row = decoded[rowIndex];
      if (row is! Map) {
        continue;
      }

      final value = row['modificado'];
      modifiedValues[rowIndex] = value == null ? '' : '$value';
    }
  } catch (_) {
    return modifiedValues;
  }

  return modifiedValues;
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

class _FormFieldData {
  const _FormFieldData({required this.label});

  final String label;
}

class _PreferenceColumnData {
  const _PreferenceColumnData({required this.title, required this.items});

  final String title;
  final List<String> items;
}

enum _RowTone { base, yellow, red, mutedLabel, disabledPlay }

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
    case _RowTone.red:
      return const BoxDecoration(
        border: Border.fromBorderSide(_borderSide),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCD6474), Color(0xFFBB4D5D)],
        ),
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

Color _toneTextColor(_RowTone tone) {
  switch (tone) {
    case _RowTone.yellow:
      return const Color(0xFF5F5737);
    case _RowTone.red:
      return const Color(0xFFFFF7F8);
    case _RowTone.disabledPlay:
      return const Color.fromRGBO(84, 91, 102, 0.52);
    case _RowTone.base:
    case _RowTone.mutedLabel:
      return const Color(0xFF56606C);
  }
}
