import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../backend/auth_service.dart';
import '../backend/supabase_provider.dart';
import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../leaderboard/leaderboard_controller.dart';
import '../models/weekly_leaderboard.dart';
import '../theme/app_theme.dart';

/// Classement hebdo global (maquette classement.html), alimenté par la RPC
/// `weekly_leaderboard`. Mode local ou hors ligne : un message, jamais de
/// faux classement. Pas de pub sur cet écran.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(backendAvailableProvider);
    final userId = ref.watch(authUserIdProvider);
    final async = ref.watch(leaderboardProvider);
    final board = async.valueOrNull;
    final now = ref.watch(clockProvider)();

    Future<void> refresh() => ref.read(leaderboardProvider.notifier).refresh();

    final Widget body;
    if (!online) {
      body = const _Message(
        icon: Icons.cloud_off_outlined,
        title: 'Classement indisponible',
        text: 'Cette version de l\'app fonctionne en mode local : '
            'le classement en ligne n\'est pas disponible. '
            'Tes XP restent enregistrées sur ce téléphone.',
      );
    } else if (userId == null) {
      body = _Message(
        icon: Icons.wifi_off_outlined,
        title: 'Pas encore connecté',
        text: 'Le classement s\'affichera dès que l\'app sera connectée '
            'à Internet.',
        action: 'Réessayer',
        onAction: () =>
            unawaited(ref.read(authServiceProvider)?.ensureSignedIn()),
      );
    } else if (board == null && async.hasError) {
      body = _Refreshable(
        onRefresh: refresh,
        child: _Message(
          icon: Icons.wifi_off_outlined,
          title: 'Classement indisponible',
          text: 'Impossible de charger le classement. '
              'Vérifie ta connexion puis réessaie.',
          action: 'Réessayer',
          onAction: () => unawaited(refresh()),
        ),
      );
    } else if (board == null) {
      body = const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Chargement'),
      );
    } else {
      body = _Refreshable(
        onRefresh: refresh,
        scrollable: true,
        child: _Board(board: board, offline: async.hasError),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Classement', style: context.text.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('Global · XP gagnée cette semaine',
                    style: context.text.bodyMedium),
                if (board != null) ...[
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatWeekRange(board.weekStart, board.weekEnd),
                          style: context.text.bodyMedium,
                        ),
                      ),
                      Text(
                        formatTimeLeft(board.endsAt, now),
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: body),
          if (board != null) _MyPosition(board: board),
        ],
      ),
    );
  }
}

/// Tirer pour rafraîchir, même quand le contenu est court.
class _Refreshable extends StatelessWidget {
  const _Refreshable({
    required this.onRefresh,
    required this.child,
    this.scrollable = false,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// [child] défile déjà (liste du classement).
  final bool scrollable;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: scrollable
            ? child
            : LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(child: child),
                  ),
                ),
              ),
      );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: context.colors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.l),
            Text(title,
                textAlign: TextAlign.center, style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.s),
            Text(text,
                textAlign: TextAlign.center, style: context.text.bodyMedium),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      );
}

class _Board extends StatelessWidget {
  const _Board({required this.board, required this.offline});

  final WeeklyLeaderboard board;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = board.entries;
    final podium = entries.length >= 3 ? entries.sublist(0, 3) : const [];
    final rest = entries.sublist(podium.length);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      children: [
        if (offline)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.m),
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: c.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off_outlined, color: c.onSurfaceVariant),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(
                    'Hors ligne : ce classement n\'est peut-être pas à jour.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (entries.isEmpty)
          const _Message(
            icon: Icons.emoji_events_outlined,
            title: 'Personne n\'a encore d\'XP cette semaine',
            text: 'Joue un quiz pour ouvrir le classement !',
          ),
        if (podium.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Podium(place: 2, entry: podium[1]),
              const SizedBox(width: 10),
              _Podium(place: 1, entry: podium[0]),
              const SizedBox(width: 10),
              _Podium(place: 3, entry: podium[2]),
            ],
          ),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.only(top: podium.isEmpty ? AppSpacing.l : 0),
            child: Column(
              children: [
                for (var i = 0; i < rest.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _Row(
                    rank: '${rest[i].rank}',
                    name: rest[i].isMe ? 'Toi' : rest[i].displayName,
                    xp: rest[i].xp,
                    me: rest[i].isMe,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// Ligne « Toi » épinglée en bas, même hors du top.
class _MyPosition extends StatelessWidget {
  const _MyPosition({required this.board});

  final WeeklyLeaderboard board;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rank = board.myRank;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        border: Border.all(color: c.primary, width: 2),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: _Row(
        rank: rank == null ? '–' : '$rank',
        name: 'Toi',
        subtitle: rank == null
            ? 'Joue un quiz pour entrer au classement'
            : board.myName,
        xp: board.myXp,
        me: true,
        pinned: true,
      ),
    );
  }
}

String _initials(String name) {
  final letters = name.trim();
  return letters.length < 2
      ? letters.toUpperCase()
      : letters.substring(0, 2).toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, this.size = 40, this.bg, this.fg});

  final String label;
  final double size;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ?? context.colors.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.titre,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.33,
            color: fg ?? context.colors.onSurface,
          ),
        ),
      );
}

class _Podium extends StatelessWidget {
  const _Podium({required this.place, required this.entry});

  /// Marche du podium (1 à 3) ; le rang affiché vient du serveur (ex-aequo).
  final int place;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (double height, Color bg, Color fg) = switch (place) {
      1 => (84, c.tertiary, c.onTertiary),
      2 => (62, c.surfaceContainer, c.onSurface),
      _ => (46, c.primaryContainer, c.onPrimaryContainer),
    };
    final size = place == 1 ? 68.0 : 56.0;
    final name = entry.isMe ? 'Toi' : entry.displayName;
    return Expanded(
      child: Semantics(
        label: entry.isMe
            ? 'Ta position : ${entry.rank}e, ${entry.xp} XP'
            : '${entry.rank}. $name, ${entry.xp} XP',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Container(
                decoration: place == 1
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.tertiary, width: 4),
                      )
                    : null,
                child: _Avatar(
                  label: entry.isMe ? 'TOI' : _initials(name),
                  size: size,
                  bg: entry.isMe ? c.primary : null,
                  fg: entry.isMe ? c.onPrimary : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(height: 1.2)),
              Text('${entry.xp} XP', style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.s),
              Container(
                height: height,
                width: double.infinity,
                padding: const EdgeInsets.only(top: 8),
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Text('${entry.rank}',
                    style: TextStyle(
                      fontFamily: AppFonts.titre,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1,
                      color: fg,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rank,
    required this.name,
    required this.xp,
    this.subtitle,
    this.me = false,
    this.pinned = false,
  });

  final String rank;
  final String name;
  final String? subtitle;
  final int xp;
  final bool me;

  /// Ligne épinglée (déjà sur fond teinté).
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = me ? c.onPrimaryContainer : c.onSurface;
    final row = Semantics(
      label: me
          ? (rank == '–'
              ? 'Ta position : pas encore classé, $xp XP'
              : 'Ta position : ${rank}e, $xp XP')
          : '$rank. $name, $xp XP',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: me ? 60 : 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(rank,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppFonts.titre,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: me ? fg : c.onSurfaceVariant,
                      )),
                ),
                const SizedBox(width: AppSpacing.m),
                _Avatar(
                  label: me ? 'TOI' : _initials(name),
                  bg: me ? c.primary : null,
                  fg: me ? c.onPrimary : null,
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(color: fg)),
                      if (subtitle != null)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                                color: me ? fg : c.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text.rich(TextSpan(
                  style: context.text.bodyMedium
                      ?.copyWith(color: me ? fg : c.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: '$xp',
                      style: TextStyle(
                        fontFamily: AppFonts.titre,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: fg,
                      ),
                    ),
                    const TextSpan(text: ' XP'),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
    // Ligne du joueur dans la liste : mise en évidence comme la ligne épinglée.
    return me && !pinned
        ? ColoredBox(color: c.primaryContainer, child: row)
        : row;
  }
}
