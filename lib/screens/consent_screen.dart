import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../ads/consent_service.dart';
import '../legal/legal_links.dart';
import '../theme/app_theme.dart';
import 'goal_screen.dart';

/// Premier lancement : explication avant le formulaire de consentement (maquette consentement.html).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _busy = false;

  /// Formulaire UMP (et ATT sur iOS) si nécessaire, puis objectif du jour.
  /// Hors ligne ou en erreur : on continue sans pub, nouvel essai au prochain
  /// lancement.
  Future<void> _continue() async {
    setState(() => _busy = true);
    await ref.read(consentControllerProvider.notifier).gather();
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => const GoalScreen(onboarding: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
                children: [
                  const SizedBox(height: 28),
                  const Center(child: _AppMark()),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Avant de jouer',
                      textAlign: TextAlign.center,
                      style: context.text.headlineMedium),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Quizzéo est gratuit grâce à la pub. Selon ton pays, tu peux choisir comment elle utilise tes données.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const _Point(
                    icon: Icons.lock_open_outlined,
                    title: 'Tout le contenu est gratuit',
                    text:
                        'Les pubs financent l\'app. Jamais pendant une question.',
                  ),
                  const _Point(
                    icon: Icons.lock_outline,
                    title: 'Ton choix, si on te le demande',
                    text:
                        'Pubs personnalisées ou non : le jeu reste exactement le même.',
                  ),
                  const _Point(
                    icon: Icons.tune,
                    title: 'Modifiable à tout moment',
                    text:
                        'Dans Profil si ton choix est demandé ; sur iPhone, aussi dans Réglages > Confidentialité > Suivi.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, AppSpacing.m, AppSpacing.screen, 0),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _continue,
                    child: const Text('Continuer'),
                  ),
                  TextButton(
                    onPressed: () =>
                        openLegalLink(context, ref, LegalLinks.privacy),
                    child: const Text('Politique de confidentialité'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      'Si la loi de ton pays l\'exige, Google te demandera ton choix. Sur iPhone, iOS peut aussi te demander l\'autorisation de suivi.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall
                          ?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carré corail avec le « é » blanc (symbole de l'app).
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          'é',
          style: TextStyle(
            fontFamily: AppFonts.titre,
            fontWeight: FontWeight.w800,
            fontSize: 64,
            height: 1,
            color: context.colors.onPrimary,
          ),
        ),
      );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: c.secondary),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                Text(text, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
