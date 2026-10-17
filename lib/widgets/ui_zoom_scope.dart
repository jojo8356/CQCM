import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ui_zoom_controller.dart';
import '../services/ui_zoom_store.dart';

/// Applique le zoom de l'interface à toute l'application.
///
/// Le contenu est mis en page dans un espace virtuel (fenêtre ÷ zoom) puis
/// agrandi à la taille réelle : la mise en page se réorganise, exactement
/// comme le zoom d'un navigateur. Un simple `Transform` agrandirait le rendu
/// sans refluer les écrans — le texte deviendrait flou et les boutons
/// sortiraient de la fenêtre.
///
/// À brancher dans `MaterialApp.builder`, pour couvrir aussi bien le menu que
/// les écrans empilés par le `Navigator` :
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => UiZoomScope(child: child),
///   ...
/// )
/// ```
class UiZoomScope extends StatefulWidget {
  const UiZoomScope({
    super.key,
    this.child,
    this.controller,
    this.persist = true,
  });

  /// Contenu de l'application (le `Navigator` fourni par `MaterialApp`).
  final Widget? child;

  /// Contrôleur partagé (tests, outils). Créé et possédé par le scope sinon.
  final UiZoomController? controller;

  /// Restaure le zoom au démarrage et l'enregistre à chaque changement.
  final bool persist;

  /// Seuil de déclenchement de la molette, en pixels logiques.
  ///
  /// Un cran de souris envoie environ 53 px, un pavé tactile beaucoup de
  /// petits événements : cumuler évite qu'un geste de pavé fasse dix crans de
  /// zoom d'un coup.
  static const double scrollThreshold = 30;

  @override
  State<UiZoomScope> createState() => _UiZoomScopeState();
}

class _UiZoomScopeState extends State<UiZoomScope> {
  late UiZoomController _controller;
  bool _ownsController = false;

  /// Vrai pendant la restauration : ne pas réécrire le fichier qu'on lit.
  bool _restoring = false;

  double _scrollRemainder = 0;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    if (widget.persist) {
      unawaited(_restore());
    }
  }

  @override
  void didUpdateWidget(covariant UiZoomScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach();
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach(UiZoomController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? UiZoomController();
    _controller.addListener(_onZoomChanged);
  }

  void _detach() {
    _controller.removeListener(_onZoomChanged);
    if (_ownsController) {
      _controller.dispose();
    }
  }

  Future<void> _restore() async {
    final saved = await UiZoomStore.loadZoom();
    if (!mounted || saved == null) {
      return;
    }
    _restoring = true;
    _controller.setZoom(saved);
    _restoring = false;
  }

  void _onZoomChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (widget.persist && !_restoring) {
      unawaited(UiZoomStore.saveZoom(_controller.zoom));
    }
  }

  /// Raccourcis clavier. Les variantes avec et sans Maj couvrent les deux
  /// dispositions : sur un clavier QWERTY, `+` s'obtient avec Maj, alors que
  /// sur un clavier AZERTY la touche `+` existe telle quelle.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.equal, control: true):
          _controller.zoomIn,
      const SingleActivator(
        LogicalKeyboardKey.equal,
        control: true,
        shift: true,
      ): _controller.zoomIn,
      const SingleActivator(LogicalKeyboardKey.add, control: true):
          _controller.zoomIn,
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
          _controller.zoomIn,
      const SingleActivator(LogicalKeyboardKey.minus, control: true):
          _controller.zoomOut,
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
          _controller.zoomOut,
      const SingleActivator(LogicalKeyboardKey.digit0, control: true):
          _controller.reset,
      const SingleActivator(LogicalKeyboardKey.numpad0, control: true):
          _controller.reset,
    };
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      // Molette seule : les listes défilent, rien d'autre.
      _scrollRemainder = 0;
      return;
    }
    _scrollRemainder += event.scrollDelta.dy;
    if (_scrollRemainder.abs() < UiZoomScope.scrollThreshold) {
      return;
    }
    // Vers le haut (delta négatif) : agrandir, comme dans un navigateur.
    final zoomIn = _scrollRemainder < 0;
    _scrollRemainder = 0;
    if (zoomIn) {
      _controller.zoomIn();
    } else {
      _controller.zoomOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final zoom = _controller.zoom;
    final content = widget.child ?? const SizedBox.shrink();

    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Listener(
        // `translucent` : les clics continuent d'atteindre les widgets enfants,
        // et la molette est vue même au-dessus d'une zone vide.
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handlePointerSignal,
        child: zoom == 1.0 ? content : _zoomed(media, zoom, content),
      ),
    );
  }

  Widget _zoomed(MediaQueryData media, double zoom, Widget child) {
    final logical = Size(media.size.width / zoom, media.size.height / zoom);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: logical.width,
        height: logical.height,
        child: MediaQuery(
          data: media.copyWith(
            size: logical,
            padding: media.padding / zoom,
            viewInsets: media.viewInsets / zoom,
            viewPadding: media.viewPadding / zoom,
          ),
          child: child,
        ),
      ),
    );
  }
}
