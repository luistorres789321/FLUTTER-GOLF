import 'dart:math' as math;

import 'package:flutter/material.dart';

const _frontNine = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const _backNine = [10, 11, 12, 13, 14, 15, 16, 17, 18];
const _summaryHeaders = ['TOTAL', 'HCP JUEGO', 'NETO'];
const _emptySummary = ['', '', ''];

const _teeRows = [
  _ScoreRowData(
    label: 'AMARILLES',
    subtitle: 'Slope 140  |  V.C. 70,6',
    tone: _RowTone.yellow,
    frontValues: [
      '159',
      '349',
      '240',
      '321',
      '203',
      '487',
      '338',
      '306',
      '400',
    ],
    frontTotal: '2803',
    backValues: ['159', '349', '240', '321', '203', '487', '338', '306', '400'],
    backTotal: '2803',
    summaryValues: ['5606', '', ''],
  ),
  _ScoreRowData(
    label: 'ROJAS',
    subtitle: 'Slope 129  |  V.C. 71,2',
    tone: _RowTone.red,
    frontValues: [
      '137',
      '288',
      '196',
      '294',
      '165',
      '442',
      '295',
      '276',
      '310',
    ],
    frontTotal: '2403',
    backValues: ['137', '288', '196', '294', '165', '442', '295', '276', '310'],
    backTotal: '2403',
    summaryValues: ['4806', '', ''],
  ),
];

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

const _referenceRows = [
  _ScoreRowData(
    label: 'PAR',
    frontValues: ['3', '4', '4', '4', '3', '5', '4', '4', '4'],
    frontTotal: '35',
    backValues: ['3', '4', '4', '4', '3', '5', '4', '4', '4'],
    backTotal: '35',
    summaryValues: ['70', '', ''],
    valueWeight: FontWeight.w700,
  ),
  _ScoreRowData(
    label: 'P. HCP CABALLEROS',
    frontValues: ['13', '3', '15', '7', '17', '1', '9', '11', '5'],
    backValues: ['14', '4', '16', '8', '18', '2', '10', '12', '6'],
    summaryValues: _emptySummary,
    valueWeight: FontWeight.w700,
  ),
  _ScoreRowData(
    label: 'P. HCP DAMAS',
    frontValues: ['11', '5', '15', '9', '17', '1', '13', '7', '3'],
    backValues: ['12', '6', '16', '10', '18', '2', '14', '8', '4'],
    summaryValues: _emptySummary,
    valueWeight: FontWeight.w700,
  ),
];

const _formFields = [
  _FormFieldData(label: 'COMPETICION'),
  _FormFieldData(label: 'MODALIDAD'),
  _FormFieldData(label: 'FORMULA'),
  _FormFieldData(label: 'HOYO'),
  _FormFieldData(label: 'FECHA', secondLabel: 'HORA'),
  _FormFieldData(label: 'EQUIPO'),
];

const _preferenceColumns = [
  _PreferenceColumnData(
    title: 'CABALLEROS',
    items: ['AMARILLAS', 'ROJAS', 'STABLEFORD'],
  ),
  _PreferenceColumnData(
    title: 'DAMAS',
    items: ['AMARILLAS', 'ROJAS', 'MEDAL PLAY'],
  ),
];

class GolfScorecardScreen extends StatelessWidget {
  const GolfScorecardScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6B432D), Color(0xFF472819)],
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
                      .clamp(_cardMinWidth, _cardMaxWidth)
                      .toDouble();

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: cardWidth,
                          child: const _ScorecardCard(),
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
  const _ScorecardCard();

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
              children: const [
                _ScoreGrid(),
                SizedBox(height: 22),
                _LowerSection(),
                SizedBox(height: 18),
                _MarkerStrip(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreGrid extends StatelessWidget {
  const _ScoreGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GridHeaderRow(),
        ..._teeRows.map(_GridDataRow.new),
        ..._playRows.map(_GridDataRow.new),
        ..._referenceRows.map(_GridDataRow.new),
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
              child: _ValueText(value, weight: row.valueWeight),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: row.tone,
            child: _ValueText(row.frontTotal, weight: row.valueWeight),
          ),
          const _FoldCell(),
          for (final value in row.backValues)
            _GridCell.data(
              width: GolfScorecardScreen._holeWidth,
              tone: row.tone,
              child: _ValueText(value, weight: row.valueWeight),
            ),
          _GridCell.data(
            width: GolfScorecardScreen._subtotalWidth,
            tone: row.tone,
            child: _ValueText(row.backTotal, weight: row.valueWeight),
          ),
          for (final value in row.summaryValues)
            _GridCell.summary(
              width: GolfScorecardScreen._summaryWidth,
              child: _ValueText(value, weight: row.valueWeight),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: _SignaturesPanel()),
              SizedBox(width: 16),
              SizedBox(width: 260, child: _PreferencesPanel()),
            ],
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
          if (field.secondLabel != null) ...[
            const SizedBox(width: 14),
            Text(field.secondLabel!, style: textStyle),
            const SizedBox(width: 8),
            const Expanded(child: _LineField()),
          ],
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
      offset: const Offset(0, -3),
      child: Container(
        height: 18,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color.fromRGBO(115, 120, 131, 0.34),
              width: 2,
            ),
          ),
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
        : const Color(0xFF3F474F);
    final secondaryColor = row.tone == _RowTone.red
        ? const Color.fromRGBO(255, 247, 248, 0.88)
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
            fontSize: row.subtitle == null ? 14 : 15,
            fontWeight: row.subtitle == null
                ? FontWeight.w500
                : FontWeight.w700,
            fontStyle: row.subtitle == null
                ? FontStyle.italic
                : FontStyle.normal,
            color: primaryColor,
          ),
        ),
        if (row.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            row.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: secondaryColor),
          ),
        ],
      ],
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.value, {this.weight});

  final String value;
  final FontWeight? weight;

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
      style: TextStyle(fontWeight: weight),
    );
  }
}

class _ScoreRowData {
  const _ScoreRowData({
    required this.label,
    required this.frontValues,
    required this.backValues,
    this.subtitle,
    this.frontTotal = '',
    this.backTotal = '',
    this.summaryValues = _emptySummary,
    this.tone = _RowTone.base,
    this.height = 44,
    this.valueWeight,
  });

  final String label;
  final String? subtitle;
  final List<String> frontValues;
  final List<String> backValues;
  final String frontTotal;
  final String backTotal;
  final List<String> summaryValues;
  final _RowTone tone;
  final double height;
  final FontWeight? valueWeight;
}

class _FormFieldData {
  const _FormFieldData({required this.label, this.secondLabel});

  final String label;
  final String? secondLabel;
}

class _PreferenceColumnData {
  const _PreferenceColumnData({required this.title, required this.items});

  final String title;
  final List<String> items;
}

enum _RowTone { base, yellow, red, mutedLabel }

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
    case _RowTone.base:
    case _RowTone.mutedLabel:
      return const Color(0xFF56606C);
  }
}
