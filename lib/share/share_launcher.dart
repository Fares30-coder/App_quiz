import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'share_content.dart';
import 'share_service.dart';

/// Bouton de partage : ancre iPad (zone du bouton), garde contre le double
/// appui, message en cas d'échec.
class ShareLauncher extends ConsumerStatefulWidget {
  const ShareLauncher({
    super.key,
    required this.content,
    required this.builder,
  });

  final ShareContent Function() content;

  /// [onPressed] est null pendant la préparation de l'image.
  final Widget Function(BuildContext context, VoidCallback? onPressed) builder;

  @override
  ConsumerState<ShareLauncher> createState() => _ShareLauncherState();
}

class _ShareLauncherState extends ConsumerState<ShareLauncher> {
  bool _busy = false;

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(shareServiceProvider)
          .share(widget.content(), origin: origin);
    } catch (e) {
      debugPrint('Partage impossible : $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Le partage n\'a pas fonctionné. Réessaie.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _busy ? null : _share);
}
