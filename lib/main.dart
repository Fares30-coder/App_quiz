import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/progress_repository.dart';
import 'engagement/progress_controller.dart';
import 'reminder/reminder_scheduler.dart';
import 'screens/consent_screen.dart';
import 'screens/shell_screen.dart';
import 'sound/sound_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Préchargement en arrière-plan : ne retarde pas le démarrage.
  final sounds = AudioplayersSoundService()..preload();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundServiceProvider.overrideWithValue(sounds),
      ],
      child: const QuizzeoApp(),
    ),
  );
}

class QuizzeoApp extends StatelessWidget {
  const QuizzeoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quizzéo',
      debugShowCheckedModeBanner: false,
      // Contenu 100 % français : menus et sélecteurs Material en français.
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const RootGate(),
    );
  }
}

/// Premier lancement (consentement puis objectif) ou accueil.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Programme le rappel au démarrage puis à chaque changement utile.
    ref.watch(reminderSchedulerProvider);
    final onboardingDone = ref.watch(
      progressControllerProvider.select((p) => p.onboardingDone),
    );
    return onboardingDone ? const ShellScreen() : const ConsentScreen();
  }
}
