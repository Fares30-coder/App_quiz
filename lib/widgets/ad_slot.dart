import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import '../ads/banner_ads.dart';
import '../ads/consent_service.dart';
import '../theme/app_theme.dart';

/// Bannière adaptative ancrée (accueil, résultats ; jamais pendant un quiz).
///
/// Chargée seulement si [bannerAllowedProvider] est vrai (consentement + SDK
/// prêts, pas d'achat « sans pub ») ; libérée dès qu'il repasse à faux. Hauteur
/// réservée pendant le chargement ; rien du tout si la pub n'est pas chargée.
/// Rechargée aussi après « Gérer mes choix de confidentialité ».
class AdSlot extends ConsumerStatefulWidget {
  const AdSlot({super.key, this.padding = EdgeInsets.zero});

  /// Marge fixe autour de la bannière, seulement quand elle est affichée :
  /// écart minimal avec les boutons et la barre de navigation (règle AdMob
  /// sur les clics accidentels).
  final EdgeInsets padding;

  @override
  ConsumerState<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends ConsumerState<AdSlot> {
  LoadedBanner? _banner;
  AdSize? _size;
  bool _loading = false;

  /// Faux si l'écran est caché : onglet inactif, ou route du quiz par-dessus
  /// l'accueil. La bannière est alors libérée (jamais de pub pendant un quiz).
  bool _visible = false;

  /// Largeur utilisée pour le dernier chargement : si elle change (rotation),
  /// la bannière est libérée et rechargée à la bonne taille.
  int? _width;

  /// Largeur réellement disponible (LayoutBuilder, hors bords non sûrs).
  /// `null` avant la première mise en page : rien n'est chargé avant.
  int? _availableWidth;

  /// Incrémenté à chaque libération : un chargement commencé avant est ignoré.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(bannerAllowedProvider, (_, allowed) {
      allowed ? _load() : _release();
    });
    // Choix de confidentialité modifiés : nouvelle requête avec le nouveau
    // consentement.
    ref.listenManual<int>(consentChoicesVersionProvider, (_, __) {
      _release();
      _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) _release(rebuild: false);
    if (visible) _load();
  }

  /// Appelé après la mise en page quand la largeur disponible change.
  void _onWidth(int width) {
    if (!mounted || width != _availableWidth) return;
    if (_width != null && _width != width) _release();
    _load();
  }

  bool _stillWanted(int generation) =>
      mounted &&
      generation == _generation &&
      _visible &&
      ref.read(bannerAllowedProvider);

  /// `bannerAllowedProvider` relu juste avant chaque chargement. Aucun
  /// `setState` avant le premier `await` : appelable depuis
  /// `didChangeDependencies`.
  Future<void> _load() async {
    if (!mounted || _banner != null || _loading) return;
    final generation = _generation;
    if (!_stillWanted(generation)) return;
    final width = _availableWidth;
    if (width == null || width <= 0) return;
    final loader = ref.read(bannerLoaderProvider);
    _width = width;
    _loading = true;

    try {
      final size = await loader.anchoredSize(width);
      if (!_stillWanted(generation) || size == null) return;
      setState(() => _size = size);

      final banner = await loader.load(size);
      if (!_stillWanted(generation)) {
        banner?.dispose();
        return;
      }
      setState(() {
        _banner = banner;
        if (banner == null) _size = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Bannière indisponible : $e');
      if (mounted && generation == _generation) setState(() => _size = null);
    } finally {
      // Sinon, un nouveau chargement (génération suivante) est peut-être en
      // cours : ne pas toucher à son état.
      if (generation == _generation) _loading = false;
    }
  }

  void _release({bool rebuild = true}) {
    _generation++;
    _loading = false;
    _width = null;
    final banner = _banner;
    _banner = null;
    _size = null;
    banner?.dispose();
    if (rebuild && mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final max = constraints.maxWidth;
        final width =
            (max.isFinite ? max : MediaQuery.sizeOf(context).width).truncate();
        if (width != _availableWidth) {
          _availableWidth = width;
          WidgetsBinding.instance.addPostFrameCallback((_) => _onWidth(width));
        }
        return _buildBanner(context);
      }),
    );
  }

  Widget _buildBanner(BuildContext context) {
    final size = _size;
    if (size == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: widget.padding,
      child: Container(
        key: const Key('ad-slot'),
        // + 1 : bordure du haut (Container la déduit de la place du contenu).
        height: size.height + 1,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          border: Border(top: BorderSide(color: c.outlineVariant)),
        ),
        child: _banner == null
            ? null
            : SizedBox(
                width: size.width.toDouble(),
                height: size.height.toDouble(),
                child: _banner!.view,
              ),
      ),
    );
  }
}
