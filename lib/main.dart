import 'package:flutter/material.dart';

import 'golf_scorecard_screen.dart';

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
      home: const GolfScorecardScreen(),
    );
  }
}
