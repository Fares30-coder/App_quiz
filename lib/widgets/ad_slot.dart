import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import '../ads/banner_ads.dart';
import '../theme/app_theme.dart';

/// Bannière adaptative ancrée (accueil, résultats ; jamais pendant un quiz).
///
/// Chargée seulement si [bannerAllowedProvider] est vrai (consentement + SDK
/// prêts, pas d'achat « sans pub ») ; libérée dès qu'il repasse à faux. Hauteur
/// réservée pendant le chargement ; rien du tout si la pub n'est pas chargée.
class AdSlot extends ConsumerStatefulWidget {
  const AdSlot({super.key});

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

  /// Incrémenté à chaque libération : un chargement commencé avant est ignoré.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(bannerAllowedProvider, (_, allowed) {
      allowed ? _load() : _release();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final resized = _width != null && width != _width;
    if (visible == _visible && !resized) return;
    _visible = visible;
    if (!visible || resized) _release(rebuild: false);
    if (visible) _load();
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
    final loader = ref.read(bannerLoaderProvider);
    final width = MediaQuery.sizeOf(context).width.truncate();
    _width = width;
    _loading = true;

    final size = await loader.anchoredSize(width);
    if (!_stillWanted(generation)) return;
    if (size == null) {
      _loading = false;
      return;
    }
    setState(() => _size = size);

    final banner = await loader.load(size);
    if (!_stillWanted(generation)) {
      banner?.dispose();
      return;
    }
    setState(() {
      _loading = false;
      _banner = banner;
      if (banner == null) _size = null;
    });
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
    final size = _size;
    if (size == null) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
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
    );
  }
}
