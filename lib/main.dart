import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads/banner_ads.dart';
import 'ads/consent_service.dart';
import 'ads/interstitial_ads.dart';
import 'ads/rewarded_ads.dart';
import 'backend/auth_service.dart';
import 'backend/backend_config.dart';
import 'backend/secure_session_storage.dart';
import 'backend/supabase_provider.dart';
import 'data/progress_repository.dart';
import 'engagement/progress_controller.dart';
import 'engagement/progress_sync.dart';
import 'reminder/reminder_scheduler.dart';
import 'screens/consent_screen.dart';
import 'screens/shell_screen.dart';
import 'sound/sound_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Build store (REQUIRE_REAL_AD_UNITS=true) : échoue tout de suite sans vrai
  // ID de bloc, plutôt qu'au premier affichage de pub.
  bannerAdUnitId();
  interstitialAdUnitId();
  rewardedAdUnitId();
  // Supabase : lecture locale seulement (pas d'attente réseau) ; `null` sans
  // config/dev.json → mode 100 % local. Session dans le stockage sécurisé.
  const backend = BackendConfig.fromEnvironment();
  final sessionStorage = SecureSessionStorage.forUrl(backend.url);
  final (prefs, supabase) = await (
    SharedPreferences.getInstance(),
    initBackend(backend, sessionStorage: sessionStorage),
  ).wait;
  // Préchargement en arrière-plan : ne retarde pas le démarrage.
  final sounds = AudioplayersSoundService()..preload();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundServiceProvider.overrideWithValue(sounds),
        supabaseClientProvider.overrideWithValue(supabase),
        sessionStorageProvider.overrideWithValue(sessionStorage),
        // Pubs : rien n'est appelé avant le consentement (ConsentController).
        adsPlatformProvider.overrideWithValue(GoogleAdsPlatform()),
        // Bannières : chargées seulement si `bannerAllowedProvider` (AdSlot).
        bannerLoaderProvider.overrideWithValue(const GoogleBannerLoader()),
        // Interstitiel : préchargé seulement si `interstitialAllowedProvider`.
        interstitialLoaderProvider
            .overrideWithValue(const GoogleInterstitialLoader()),
        // Pub récompensée (gel) : chargée seulement à l'ouverture de l'offre.
        rewardedLoaderProvider.overrideWithValue(const GoogleRewardedLoader()),
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
    // Connexion anonyme en arrière-plan (rien en mode local, jamais bloquant).
    ref.watch(authServiceProvider);
    // Sync de la progression (après connexion, au premier plan ; rien en local).
    ref.watch(progressSyncProvider);
    final onboardingDone = ref.watch(
      progressControllerProvider.select((p) => p.onboardingDone),
    );
    // Consentement UMP à chaque lancement ; au premier, il est demandé par
    // l'écran de consentement (après l'explication).
    if (onboardingDone) ref.watch(consentStartupProvider);
    // Interstitiel préchargé dès que les pubs sont autorisées (entre deux quiz).
    ref.watch(interstitialControllerProvider);
    return onboardingDone ? const ShellScreen() : const ConsentScreen();
  }
}
