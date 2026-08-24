// lib/data/models/team.dart
//
// The team system's data shapes (EN-24 / EN-25 / EN-26 / KK-4).
//
// Every RPC in supabase/sql/v5_teams.sql answers with jsonb rather than a
// composite type, because a team screen needs the team, the roster, the rules
// and the caller's own place in all of it at once, and four round trips to
// draw one screen is four chances to show a half-built page. So these models
// parse maps, and every field defaults — a server that has not been migrated
// yet, or an older function signature, degrades to an empty team rather than
// to a crash.

class Team {
  final int id;
  final String name, tag, emblem, colour;
  final String? owner, description, myRole;
  final bool isOpen;
  final int memberLimit, memberCount, xp, level;

  const Team({
    required this.id,
    required this.name,
    this.tag = '',
    this.emblem = '🛡️',
    this.colour = '#7C5CFF',
    this.owner,
    this.description,
    this.myRole,
    this.isOpen = true,
    this.memberLimit = 20,
    this.memberCount = 0,
    this.xp = 0,
    this.level = 1,
  });

  static Team? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['id'] == null) return null;
    return Team(
      id:          (m['id'] as num).toInt(),
      name:        (m['name'] ?? '').toString(),
      tag:         (m['tag'] ?? '').toString(),
      emblem:      (m['emblem'] ?? '🛡️').toString(),
      colour:      (m['colour'] ?? '#7C5CFF').toString(),
      owner:       m['owner']?.toString(),
      description: m['description']?.toString(),
      myRole:      m['my_role']?.toString(),
      isOpen:      (m['is_open'] ?? true) as bool,
      memberLimit: ((m['member_limit'] ?? 20) as num).toInt(),
      memberCount: ((m['member_count'] ?? 0) as num).toInt(),
      xp:          ((m['xp'] ?? 0) as num).toInt(),
      level:       ((m['level'] ?? 1) as num).toInt(),
    );
  }

  bool get iAmOwner   => myRole == 'owner';
  bool get iAmOfficer => myRole == 'owner' || myRole == 'officer';
  bool get isFull     => memberCount >= memberLimit;
  String get handle   => tag.isEmpty ? name : '[$tag] $name';
}

/// One person on the roster, with both their lifetime contribution and the
/// only number the weekly bar is actually racing — what they put in this week.
class TeamMemberRow {
  final String userId, name, avatarEmoji, role;
  final int contributedXp, weekXp;
  /// True once this member has hit the per-member cap, so the UI can say why
  /// their bar stopped moving instead of looking broken (EN-25).
  final bool capped;

  const TeamMemberRow({
    required this.userId,
    required this.name,
    this.avatarEmoji = '🦊',
    this.role = 'member',
    this.contributedXp = 0,
    this.weekXp = 0,
    this.capped = false,
  });

  factory TeamMemberRow.fromMap(Map<String, dynamic> m) => TeamMemberRow(
    userId:        (m['user_id'] ?? '').toString(),
    name:          (m['name'] ??
                    m['display_name'] ??
                    m['username'] ?? '').toString(),
    avatarEmoji:   (m['avatar_emoji'] ?? '🦊').toString(),
    role:          (m['role'] ?? 'member').toString(),
    contributedXp: ((m['contributed_xp'] ?? 0) as num).toInt(),
    weekXp:        ((m['week_xp'] ?? m['xp'] ?? 0) as num).toInt(),
    capped:        (m['capped'] ?? false) as bool,
  );
}

/// The weekly team challenge (EN-25).
class TeamWeekly {
  final int teamId, goal, progress, capPerMember, contributors,
      minContributors, myXp, rewardXp;
  final bool claimed, canClaim;
  final List<TeamMemberRow> members;

  const TeamWeekly({
    required this.teamId,
    this.goal = 0,
    this.progress = 0,
    this.capPerMember = 0,
    this.contributors = 0,
    this.minContributors = 3,
    this.myXp = 0,
    this.rewardXp = 0,
    this.claimed = false,
    this.canClaim = false,
    this.members = const [],
  });

  static TeamWeekly? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['team_id'] == null) return null;
    return TeamWeekly(
      teamId:          (m['team_id'] as num).toInt(),
      goal:            ((m['goal'] ?? 0) as num).toInt(),
      progress:        ((m['progress'] ?? 0) as num).toInt(),
      capPerMember:    ((m['cap_per_member'] ?? 0) as num).toInt(),
      contributors:    ((m['contributors'] ?? 0) as num).toInt(),
      minContributors: ((m['min_contributors'] ?? 3) as num).toInt(),
      myXp:            ((m['my_xp'] ?? 0) as num).toInt(),
      rewardXp:        ((m['reward_xp'] ?? 0) as num).toInt(),
      claimed:         (m['claimed'] ?? false) as bool,
      canClaim:        (m['can_claim'] ?? false) as bool,
      members: [
        for (final r in (m['members'] as List? ?? const []))
          TeamMemberRow.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }

  double get ratio => goal == 0 ? 0 : (progress / goal).clamp(0.0, 1.0);
  /// The goal is met but not enough different people helped, which is the one
  /// state EN-25 exists to create and the one the UI must explain.
  bool get needsMorePeople =>
      progress >= goal && !claimed && contributors < minContributors;
}

/// One person's damage in a war.
class WarFighter {
  final String userId, name, avatarEmoji;
  final int damage, matches;
  final bool mine;

  const WarFighter({
    required this.userId,
    required this.name,
    this.avatarEmoji = '🦊',
    this.damage = 0,
    this.matches = 0,
    this.mine = false,
  });

  factory WarFighter.fromMap(Map<String, dynamic> m) => WarFighter(
    userId:      (m['user_id'] ?? '').toString(),
    name:        (m['name'] ?? '').toString(),
    avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
    damage:      ((m['damage'] ?? 0) as num).toInt(),
    matches:     ((m['matches'] ?? 0) as num).toInt(),
    mine:        (m['mine'] ?? false) as bool,
  );
}

/// A team-versus-team war (EN-26 / KK-4): one day, both sides hitting the
/// same boss, damage being match score.
class TeamWar {
  final int id;
  final String status;
  final int bossHp, myScore, oppScore, myEffective, oppEffective;
  final int myPlayers, oppPlayers, myMatches, matchesLeft;
  final bool isToday;
  final Team? myTeam, oppTeam;
  final int? winner;
  final List<WarFighter> top;

  const TeamWar({
    required this.id,
    this.status = 'running',
    this.bossHp = 3000,
    this.myScore = 0,
    this.oppScore = 0,
    this.myEffective = 0,
    this.oppEffective = 0,
    this.myPlayers = 0,
    this.oppPlayers = 0,
    this.myMatches = 0,
    this.matchesLeft = 0,
    this.isToday = true,
    this.myTeam,
    this.oppTeam,
    this.winner,
    this.top = const [],
  });

  static TeamWar? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['id'] == null) return null;
    return TeamWar(
      id:           (m['id'] as num).toInt(),
      status:       (m['status'] ?? 'running').toString(),
      bossHp:       ((m['boss_hp'] ?? 3000) as num).toInt(),
      myScore:      ((m['my_score'] ?? 0) as num).toInt(),
      oppScore:     ((m['opp_score'] ?? 0) as num).toInt(),
      myEffective:  ((m['my_effective'] ?? 0) as num).toInt(),
      oppEffective: ((m['opp_effective'] ?? 0) as num).toInt(),
      myPlayers:    ((m['my_players'] ?? 0) as num).toInt(),
      oppPlayers:   ((m['opp_players'] ?? 0) as num).toInt(),
      myMatches:    ((m['my_matches'] ?? 0) as num).toInt(),
      matchesLeft:  ((m['matches_left'] ?? 0) as num).toInt(),
      isToday:      (m['is_today'] ?? true) as bool,
      myTeam:  Team.fromMap(_map(m['my_team'])),
      oppTeam: Team.fromMap(_map(m['opp_team'])),
      winner:  m['winner'] == null ? null : (m['winner'] as num).toInt(),
      top: [
        for (final r in (m['top'] as List? ?? const []))
          WarFighter.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }

  bool get isFinished => status == 'finished';
  bool get iWon => isFinished && winner != null && winner == myTeam?.id;

  /// How much of the boss is left, as a fraction. Both sides hit the same
  /// creature, so the bar is their combined damage.
  double get bossRatio => bossHp == 0
      ? 0
      : ((myEffective + oppEffective) / bossHp).clamp(0.0, 1.0);
}

/// Everything the war screen needs, including the case where there is no war.
class WarState {
  final bool canStart;
  final TeamWar? war;
  final Team? team;
  final int matchLimit, minPlayers, minTeamForWar, bossHp, matchMaxDamage;

  const WarState({
    this.canStart = false,
    this.war,
    this.team,
    this.matchLimit = 3,
    this.minPlayers = 3,
    this.minTeamForWar = 3,
    this.bossHp = 3000,
    this.matchMaxDamage = 400,
  });

  static WarState? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final r = _map(m['rules']) ?? const <String, dynamic>{};
    int ruleInt(String k, int fallback) =>
        r[k] == null ? fallback : (r[k] as num).toInt();
    return WarState(
      canStart:       (m['can_start'] ?? false) as bool,
      war:            TeamWar.fromMap(_map(m['war'])),
      team:           Team.fromMap(_map(m['team'])),
      matchLimit:     ruleInt('war_match_limit', 3),
      minPlayers:     ruleInt('war_min_players', 3),
      minTeamForWar:  ruleInt('min_team_for_war', 3),
      bossHp:         ruleInt('war_boss_hp', 3000),
      matchMaxDamage: ruleInt('war_match_max_damage', 400),
    );
  }
}

/// One row of the teams leaderboard.
class TeamBoardRow {
  final int id, memberCount, weekXp, xp, level, rank;
  final String name, tag, emblem, colour;

  const TeamBoardRow({
    required this.id,
    required this.name,
    this.tag = '',
    this.emblem = '🛡️',
    this.colour = '#7C5CFF',
    this.memberCount = 0,
    this.weekXp = 0,
    this.xp = 0,
    this.level = 1,
    this.rank = 0,
  });

  factory TeamBoardRow.fromMap(Map<String, dynamic> m) => TeamBoardRow(
    id:          ((m['id'] ?? 0) as num).toInt(),
    name:        (m['name'] ?? '').toString(),
    tag:         (m['tag'] ?? '').toString(),
    emblem:      (m['emblem'] ?? '🛡️').toString(),
    colour:      (m['colour'] ?? '#7C5CFF').toString(),
    memberCount: ((m['member_count'] ?? 0) as num).toInt(),
    weekXp:      ((m['week_xp'] ?? 0) as num).toInt(),
    xp:          ((m['xp'] ?? 0) as num).toInt(),
    level:       ((m['level'] ?? 1) as num).toInt(),
    rank:        ((m['rank'] ?? 0) as num).toInt(),
  );
}

/// An invitation to join a team.
class TeamInvite {
  final int id, teamId, memberCount;
  final String name, tag, emblem, colour, invitedByName;

  const TeamInvite({
    required this.id,
    required this.teamId,
    required this.name,
    this.tag = '',
    this.emblem = '🛡️',
    this.colour = '#7C5CFF',
    this.memberCount = 0,
    this.invitedByName = '',
  });

  factory TeamInvite.fromMap(Map<String, dynamic> m) => TeamInvite(
    id:            ((m['id'] ?? 0) as num).toInt(),
    teamId:        ((m['team_id'] ?? 0) as num).toInt(),
    name:          (m['name'] ?? '').toString(),
    tag:           (m['tag'] ?? '').toString(),
    emblem:        (m['emblem'] ?? '🛡️').toString(),
    colour:        (m['colour'] ?? '#7C5CFF').toString(),
    memberCount:   ((m['member_count'] ?? 0) as num).toInt(),
    invitedByName: (m['invited_by_name'] ?? '').toString(),
  );
}

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;
