import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Classement hebdo (maquette classement.html). Étape 1 : données FICTIVES.
// TODO(etape-2): brancher sur le back-end (classement amis / global, fin de semaine réelle).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _friends = true;

  static const _fake = [
    ('Camille', 63),
    ('Yanis', 58),
    ('Inès', 55),
    ('Hugo', 52),
    ('Sofia', 49),
    ('Nathan', 47),
    ('Jade', 44),
    ('Mehdi', 43),
    ('Lou', 41),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Classement', style: context.text.headlineMedium),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.outline, width: 2),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    children: [
                      _Segment(
                        label: 'Amis',
                        icon: Icons.group_outlined,
                        selected: _friends,
                        onTap: () => setState(() => _friends = true),
                      ),
                      _Segment(
                        label: 'Global',
                        selected: !_friends,
                        onTap: () => setState(() => _friends = false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Expanded(
                        child: Text('Semaine du 23 au 29 nov.',
                            style: context.text.bodyMedium)),
                    Text('Fin dans 4 j 6 h',
                        style: context.text.bodyMedium?.copyWith(
                            color: c.onSurface, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              children: [
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Podium(rank: 2, name: _fake[1].$1, points: _fake[1].$2),
                    const SizedBox(width: 10),
                    _Podium(rank: 1, name: _fake[0].$1, points: _fake[0].$2),
                    const SizedBox(width: 10),
                    _Podium(rank: 3, name: _fake[2].$1, points: _fake[2].$2),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
                Card(
                  child: Column(
                    children: [
                      for (var i = 3; i < _fake.length; i++) ...[
                        if (i > 3) const Divider(height: 1),
                        _Row(
                            rank: i + 1,
                            name: _fake[i].$1,
                            points: _fake[i].$2),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),
                  child: Text('Les données affichées sont fictives.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: c.primaryContainer,
              border: Border.all(color: c.primary, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: const _Row(rank: 12, name: 'Toi', points: 38, me: true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.surface : c.onSurface;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.onSurface : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                      style: context.text.titleSmall?.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _initials(String name) =>
    name.length < 2 ? name.toUpperCase() : name.substring(0, 2).toUpperCase();

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
  const _Podium({required this.rank, required this.name, required this.points});

  final int rank;
  final String name;
  final int points;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (double height, Color bg, Color fg) = switch (rank) {
      1 => (84, c.tertiary, c.onTertiary),
      2 => (62, c.surfaceContainer, c.onSurface),
      _ => (46, c.primaryContainer, c.onPrimaryContainer),
    };
    final size = rank == 1 ? 68.0 : 56.0;
    return Expanded(
      child: Semantics(
        label: '$rank. $name, $points points',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Container(
                decoration: rank == 1
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.tertiary, width: 4),
                      )
                    : null,
                child: _Avatar(label: _initials(name), size: size),
              ),
              const SizedBox(height: 6),
              Text(name,
                  style: context.text.labelMedium?.copyWith(height: 1.2)),
              Text('$points pts', style: context.text.bodySmall),
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
                child: Text('$rank',
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
    required this.points,
    this.me = false,
  });

  final int rank;
  final String name;
  final int points;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = me ? c.onPrimaryContainer : c.onSurface;
    return Semantics(
      label: me
          ? 'Ta position : ${rank}e, $points points'
          : '$rank. $name, $points points',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: me ? 60 : 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('$rank',
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
                  child: Text(name,
                      style: context.text.titleSmall?.copyWith(color: fg)),
                ),
                Text.rich(TextSpan(
                  style: context.text.bodyMedium
                      ?.copyWith(color: me ? fg : c.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: '$points',
                      style: TextStyle(
                        fontFamily: AppFonts.titre,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: fg,
                      ),
                    ),
                    const TextSpan(text: ' pts'),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
