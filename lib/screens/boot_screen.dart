import 'package:flutter/material.dart';

/// The first thing drawn, before anything can go wrong.
///
/// Painted immediately at the top of `main`, before translations, Supabase or
/// Firebase are touched. Two reasons, and the second is why it exists at all:
///
/// It removes the white flash. Until something calls `runApp`, iOS keeps
/// showing the launch storyboard and Android its splash — both light, both
/// jarring in front of a black app.
///
/// And it makes a hung launch legible. A Flutter app that shows white is
/// showing the *native* launch screen, because nothing in this app is white:
/// the theme is black, the splash is #121212, and so is the failure screen. So
/// if this never appears, the problem is below Dart — the engine, the scene,
/// the bundle — and no amount of error handling inside `main` would ever have
/// caught it. If it does appear and then nothing follows, the problem is
/// above, in whatever was being awaited. One screen, and the search space
/// halves.
///
/// Material defaults only: no ScreenUtil, no GoogleFonts, no localisation.
/// Every one of those is something that has to be set up, and this has to work
/// before any of it.
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  /// The whole app, for the moment before there is one.
  static Widget app() => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BootScreen(),
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'BULKR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB6FF3B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
