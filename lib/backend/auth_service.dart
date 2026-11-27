import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/pending_offline_day_repository.dart';
import '../data/pending_quiz_repository.dart';
import 'supabase_provider.dart';

/// Connexion anonyme Supabase, toujours en arrière-plan.
///
/// Une session existante (restaurée du stockage sécurisé) est réutilisée ;
/// sinon un compte anonyme est créé. Hors ligne ou en cas d'erreur, l'app
/// reste jouable en local et une nouvelle tentative a lieu au retour au
/// premier plan (au plus une fois par [retryDelay]) ou au prochain lancement.
class AuthService {
  AuthService(
    this._auth, {
    LocalStorage? sessionStorage,
    Future<void> Function()? clearLocalData,
    this.retryDelay = const Duration(minutes: 1),
  })  : _sessionStorage = sessionStorage,
        _clearLocalData = clearLocalData;

  final GoTrueClient _auth;
  final LocalStorage? _sessionStorage;

  /// Données locales liées au compte à effacer à la purge (files des quiz
  /// et des journées hors ligne non envoyés).
  final Future<void> Function()? _clearLocalData;
  final Duration retryDelay;

  Future<void>? _pending;
  DateTime? _lastFailure;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<AuthState>? _debugSubscription;

  /// Identifiant de l'utilisateur connecté, ou `null`.
  String? get userId => _auth.currentUser?.id;

  /// Lance la connexion sans l'attendre et la retente au premier plan.
  void start() {
    unawaited(ensureSignedIn());
    _lifecycle ??= AppLifecycleListener(
      onResume: () => unawaited(ensureSignedIn()),
    );
    if (kDebugMode) {
      String? lastId;
      _debugSubscription ??= _auth.onAuthStateChange.listen(
        (state) {
          final id = state.session?.user.id;
          if (id != lastId) debugPrint('Auth : utilisateur ${id ?? 'aucun'}');
          lastId = id;
        },
        onError: (Object _) {},
      );
    }
  }

  /// Garantit une session (existante ou anonyme). Ne lève jamais d'erreur.
  Future<void> ensureSignedIn() =>
      _pending ??= _signInIfNeeded().whenComplete(() => _pending = null);

  Future<void> _signInIfNeeded() async {
    if (_auth.currentSession != null) return;
    final lastFailure = _lastFailure;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < retryDelay) {
      return;
    }
    try {
      await _auth.signInAnonymously();
      _lastFailure = null;
    } catch (e) {
      _lastFailure = DateTime.now();
      _logError('connexion anonyme impossible, mode local', e);
    }
  }

  /// Purge locale : déconnexion et effacement de la session du stockage
  /// sécurisé, puis des données locales du compte (quiz en attente).
  /// Appelée par `AccountDeletion` après la suppression côté serveur.
  Future<void> purgeLocalSession() async {
    try {
      // Efface la session en mémoire avant l'appel réseau (qui peut échouer).
      await _auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      _logError('déconnexion serveur impossible', e);
    }
    try {
      await _sessionStorage?.removePersistedSession();
    } catch (e) {
      _logError('effacement de la session impossible', e);
    }
    try {
      await _clearLocalData?.call();
    } catch (e) {
      _logError('effacement des données locales impossible', e);
    }
  }

  void dispose() {
    _lifecycle?.dispose();
    unawaited(_debugSubscription?.cancel());
  }
}

/// Jamais de jeton : message d'erreur d'auth ou type d'erreur seulement.
void _logError(String message, Object error) {
  if (!kDebugMode) return;
  final detail = [
    error.runtimeType,
    if (error is AuthException) ...[error.statusCode, error.code],
  ].whereType<Object>().join(' ');
  debugPrint('Auth : $message ($detail)');
}

/// Stockage de la session (sécurisé), fourni dans `main()`.
final sessionStorageProvider = Provider<LocalStorage?>((ref) => null);

/// Service d'auth, `null` en mode 100 % local. Sa création lance la
/// connexion en arrière-plan (lu par `RootGate` au premier affichage).
final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final service = AuthService(
    client.auth,
    sessionStorage: ref.watch(sessionStorageProvider),
    // Lu seulement à la purge : quiz et journées hors ligne en attente du
    // compte effacé.
    clearLocalData: () async {
      await ref.read(pendingQuizRepositoryProvider).clear();
      await ref.read(pendingOfflineDayRepositoryProvider).clear();
    },
  )..start();
  ref.onDispose(service.dispose);
  return service;
});

/// Utilisateur Supabase courant (suit `onAuthStateChange`), `null` en mode
/// local ou sans session.
final authUserProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return Stream.value(null);
  return client.auth.onAuthStateChange
      .map((state) => state.session?.user)
      // Erreurs de rafraîchissement hors ligne : on garde l'état précédent.
      .handleError((Object _) {});
});

/// Identifiant de l'utilisateur, `null` en mode local ou sans session.
final authUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authUserProvider).valueOrNull?.id,
);
