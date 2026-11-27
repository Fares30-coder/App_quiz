import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pending_offline_day_repository.dart';
import '../data/pending_quiz_repository.dart';
import '../engagement/progress_controller.dart';
import 'auth_service.dart';
import 'supabase_provider.dart';

/// Suppression du compte (T13, App Store 5.1.1(v) et Google Play).
///
/// 1. Compte serveur, s'il y a une session : `delete_account()` supprime
///    l'utilisateur et ses données (cascade, voir
///    `supabase/migrations/*_delete_account.sql`). En cas d'échec (hors
///    ligne…), l'exception remonte et rien n'est effacé en local.
/// 2. Session locale (Keychain / Keystore) et files d'attente.
/// 3. Progression locale : l'app repart au premier lancement ; un nouveau
///    compte anonyme sera créé en arrière-plan.
class AccountDeletion {
  AccountDeletion({
    required Future<void> Function() deleteRemote,
    required Future<void> Function() clearLocal,
  })  : _deleteRemote = deleteRemote,
        _clearLocal = clearLocal;

  final Future<void> Function() _deleteRemote;
  final Future<void> Function() _clearLocal;

  Future<void> deleteAccount() async {
    await _deleteRemote();
    await _clearLocal();
  }
}

final accountDeletionProvider = Provider<AccountDeletion>((ref) {
  return AccountDeletion(
    deleteRemote: () async {
      final client = ref.read(supabaseClientProvider);
      // Mode local, ou aucun compte créé (jamais connecté) : rien sur le
      // serveur.
      if (client == null || client.auth.currentSession == null) return;
      await client.rpc<void>('delete_account');
    },
    clearLocal: () async {
      await ref.read(authServiceProvider)?.purgeLocalSession();
      await ref.read(pendingQuizRepositoryProvider).clear();
      await ref.read(pendingOfflineDayRepositoryProvider).clear();
      ref.read(progressControllerProvider.notifier).reset();
    },
  );
});
