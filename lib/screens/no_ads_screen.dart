import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// « Supprimer les pubs » (maquette sans-pub.html). Étape 1 : visuel seulement.
// TODO(etape-3): brancher StoreKit / Play Billing (ou RevenueCat), afficher le
// prix localisé renvoyé par le store (jamais codé en dur), gérer la restauration.
class NoAdsScreen extends StatelessWidget {
  const NoAdsScreen({super.key});

  void _soon(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\'achat sera bientôt disponible.')),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 52,
        actions: [
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.s),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          children: [
            Center(
              child: SizedBox(
                width: 106,
                height: 106,
                child: Stack(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text('é',
                          style: TextStyle(
                            fontFamily: AppFonts.titre,
                            fontWeight: FontWeight.w800,
                            fontSize: 64,
                            height: 1,
                            color: c.onPrimary,
                          )),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.tertiary,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.surface, width: 4),
                        ),
                        child: Icon(Icons.block, size: 22, color: c.onTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Joue sans pub',
                textAlign: TextAlign.center,
                style: context.text.headlineMedium),
            const SizedBox(height: 6),
            Text('Un seul achat, et les pubs disparaissent.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(fontSize: 16)),
            const SizedBox(height: AppSpacing.xl),
            const _Benefit(
              icon: Icons.block,
              title: 'Plus aucune bannière',
              text: 'Ni sur l\'accueil, ni sur les résultats.',
            ),
            const _Benefit(
              icon: Icons.pause_circle_outline,
              title: 'Plus de pub entre deux quiz',
              text: 'Tu enchaînes les parties sans coupure.',
            ),
            const _Benefit(
              icon: Icons.lock_open,
              title: 'Le même contenu pour tous',
              text: 'Rien n\'est bloqué : le gratuit reste complet.',
            ),
            const _Benefit(
              icon: Icons.favorite_border,
              title: 'Tu soutiens un dev indépendant',
              text: 'Quizzéo est fait par une seule personne.',
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: c.surfaceContainerLowest,
                border: Border.all(color: c.primary, width: 2),
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Achat unique', style: context.text.titleMedium),
                        Text('Pas d\'abonnement, rien à renouveler',
                            style: context.text.bodyMedium),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('X,XX €',
                          style: TextStyle(
                            fontFamily: AppFonts.titre,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                            height: 1,
                            color: c.onSurface,
                          )),
                      const SizedBox(height: 4),
                      Text('prix à définir',
                          style: context.text.labelSmall?.copyWith(
                              color: context.quizColors.primaryText)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            FilledButton(
              onPressed: () => _soon(context),
              child: const Text('Supprimer les pubs'),
            ),
            TextButton.icon(
              onPressed: () => _soon(context),
              icon: const Icon(Icons.restore),
              label: const Text('Restaurer un achat'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                'Paiement via ton compte App Store ou Google Play. L\'achat est valable sur tes appareils connectés au même compte (Apple ou Google, pas entre les deux).',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
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
