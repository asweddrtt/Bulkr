import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the app shows when it could not start.
///
/// Startup awaits three things before `runApp`: translations, Supabase, and
/// Firebase. If any of them throws or simply never returns, `runApp` is never
/// reached and the app is a white rectangle — alive, drawing nothing, with no
/// crash report because nothing crashed. That is close to undiagnosable on a
/// device you cannot attach a debugger to, which is most devices.
///
/// So this exists instead. It names the step and prints the error, and it can
/// copy both to the clipboard so they can be pasted into a bug report.
///
/// Deliberately built out of nothing: no easy_localization, because
/// localisation is one of the things that can fail; no ScreenUtil, because it
/// has not been initialised yet; no GoogleFonts, because it fetches over the
/// network and the network may be exactly what is wrong. Material defaults
/// only, so this screen cannot fail for the same reason the app did.
class StartupFailureScreen extends StatelessWidget {
  const StartupFailureScreen({
    super.key,
    required this.step,
    required this.error,
    this.stackTrace,
  });

  /// Which of the three steps was in flight.
  final String step;

  final Object error;
  final StackTrace? stackTrace;

  /// The whole app, for the case where there is no app.
  static Widget app({
    required String step,
    required Object error,
    StackTrace? stackTrace,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StartupFailureScreen(
        step: step,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  String get _report => 'Bulkr failed to start.\n'
      'Step: $step\n'
      'Error: $error\n'
      '${stackTrace ?? ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 16),
              const Text(
                'Bulkr could not start',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'It got as far as: $step',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: SelectableText(
                      _report,
                      style: const TextStyle(
                        color: Color(0xFFBDBDBD),
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _report));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                  child: const Text('Copy the details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
