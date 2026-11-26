import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../widgets/share_card.dart';
import 'share_content.dart';

/// Rend [ShareCard] hors écran (arbre de rendu séparé, jamais affiché) et
/// renvoie le PNG 1080×1920.
Future<Uint8List> renderShareImage(ShareContent content) async {
  final image = await renderWidgetOffscreen(
    ShareCard(content: content),
    size: ShareCard.size,
    pixelRatio: ShareCard.pixelRatio,
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Encodage PNG impossible');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Construit [child] dans un arbre indépendant de l'écran, à la taille
/// logique [size], puis le capture à [pixelRatio].
/// Thème clair et texte non agrandi : l'image est identique sur tous les
/// appareils.
Future<ui.Image> renderWidgetOffscreen(
  Widget child, {
  required Size size,
  required double pixelRatio,
}) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(child: boundary),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final focusManager = FocusManager();
  final buildOwner = BuildOwner(focusManager: focusManager);
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: pixelRatio,
        textScaler: TextScaler.noScaling,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: AppTheme.light,
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: AppFonts.texte),
            child: child,
          ),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);

  try {
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    return await boundary.toImage(pixelRatio: pixelRatio);
  } finally {
    // Démonte l'arbre pour libérer les ressources.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(buildOwner, root);
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner
      ..rootNode = null
      ..dispose();
    focusManager.dispose();
  }
}
