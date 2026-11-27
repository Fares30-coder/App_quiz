import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Emplacement de la bannière ancrée (accueil, résultats), 60 dp réservés.
///
/// Étape 1 : aucune vraie pub. Le cadre n'est visible qu'en debug pour
/// vérifier la mise en page ; en release il ne prend aucune place.
// TODO(etape-3): remplacer par une BannerAd adaptative AdMob (ID de test en dev),
// seulement si `adsReadyProvider` (lib/ads/consent_service.dart) et pas d'achat « sans pub ».
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        border: Border(top: BorderSide(color: c.outlineVariant)),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 320,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: c.outline, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child:
                Text('Bannière (emplacement)', style: context.text.bodySmall),
          ),
          Positioned(
            left: 8,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceContainerLowest,
                border: Border.all(color: c.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Annonce',
                  style: context.text.labelSmall
                      ?.copyWith(height: 1, color: c.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
