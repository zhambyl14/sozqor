// lib/data/repos/teams_repo.dart
//
// The team system (EN-24 / EN-25 / EN-26 / KK-4), talking to the RPCs in
// supabase/sql/v5_teams.sql.
//
// Every rule that matters — the per-member contribution cap, the minimum
// number of distinct contributors, the per-player war match limit, the
// participation floor — lives in those functions and not here. A rule the
// client enforces is a rule anybody with a REST client ignores, and all four
// of them exist specifically to stop one strong player standing in for a
// whole team.
//
// That SQL is applied by hand, so until somebody runs it every call here fails
// with "Could not find the function". [TeamsUnavailable] names that case so a
// screen can say "the team system is not switched on yet" instead of showing a
// Postgres error to a learner.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/team.dart';
import '../supa.dart';

/// Thrown when the team RPCs are not on the server yet.
class TeamsUnavailable implements Exception {
  const TeamsUnavailable();
}

class TeamsRepo {
  /// PostgREST reports a function it cannot find as PGRST202, and a schema
  /// cache that has not reloaded as PGRST203. Both mean the same thing to a
  /// learner: this part of the app is not switched on.
  static bool _isMissing(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    if (code == 'PGRST202' || code == 'PGRST203' || code == '42883') return true;
    final m = e.message.toLowerCase();
    return m.contains('could not find the function') ||
        m.contains('does not exist');
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      if (_isMissing(e)) throw const TeamsUnavailable();
      rethrow;
    }
  }

  static Map<String, dynamic>? _obj(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final r in (v as List? ?? const []))
          Map<String, dynamic>.from(r as Map),
      ];

  // ── Membership ─────────────────────────────────────────
  /// The caller's team, or null if they are not in one.
  Future<Team?> myTeam() =>
      _guard(() async => Team.fromMap(_obj(await supa.rpc('my_team'))));

  Future<Team?> create({
    required String name,
    required String tag,
    required String emblem,
    required String colour,
  }) =>
      _guard(() async => Team.fromMap(_obj(await supa.rpc('create_team', params: {
            'p_name': name.trim(),
            'p_tag': tag.trim(),
            'p_emblem': emblem,
            'p_colour': colour,
          }))));

  Future<Team?> join(int teamId) =>
      _guard(() async => Team.fromMap(_obj(
          await supa.rpc('join_team', params: {'p_team': teamId}))));

  /// Browsing teams is not the same risk as browsing people: a team is a
  /// public banner somebody chose to fly, so an empty query legitimately
  /// means "show me what is open".
  Future<List<TeamBoardRow>> search(String query, {int limit = 20}) =>
      _guard(() async => _rows(await supa.rpc('search_teams', params: {
            'p_query': query.trim(),
            'p_limit': limit,
          })).map(TeamBoardRow.fromMap).toList());

  Future<List<TeamMemberRow>> roster(int teamId) =>
      _guard(() async => _rows(await supa.rpc('team_roster', params: {
            'p_team': teamId,
          })).map(TeamMemberRow.fromMap).toList());

  Future<String> leave() =>
      _guard(() async => (await supa.rpc('leave_team') ?? '').toString());

  Future<String> kick(String userId) =>
      _guard(() async =>
          (await supa.rpc('kick_member', params: {'p_user': userId}) ?? '')
              .toString());

  // ── Invitations ────────────────────────────────────────
  Future<String> invite(String userId) =>
      _guard(() async =>
          (await supa.rpc('invite_to_team', params: {'p_user': userId}) ?? '')
              .toString());

  Future<List<TeamInvite>> invites() =>
      _guard(() async =>
          _rows(await supa.rpc('my_team_invites')).map(TeamInvite.fromMap).toList());

  Future<String> respondToInvite(int id, {required bool accept}) =>
      _guard(() async => (await supa.rpc('respond_team_invite', params: {
            'p_id': id,
            'p_accept': accept,
          }) ?? '').toString());

  // ── Weekly challenge ───────────────────────────────────
  Future<TeamWeekly?> weekly() => _guard(
      () async => TeamWeekly.fromMap(_obj(await supa.rpc('team_weekly_state'))));

  Future<TeamWeekly?> claimWeekly() => _guard(
      () async => TeamWeekly.fromMap(_obj(await supa.rpc('claim_team_weekly'))));

  /// Rolls whatever XP the learner has earned elsewhere into this week's team
  /// total. The server treats the argument as an upper bound and counts what
  /// `xp_log` actually recorded, so calling it with a large number does not
  /// inflate anything — it is a nudge to sync, not a deposit.
  Future<int> contribute({int upTo = 0}) => _guard(() async =>
      ((await supa.rpc('contribute_team_xp', params: {'p_amount': upTo}) ?? 0)
              as num)
          .toInt());

  // ── War ────────────────────────────────────────────────
  Future<WarState?> war() =>
      _guard(() async => WarState.fromMap(_obj(await supa.rpc('war_state'))));

  Future<WarState?> findWar() => _guard(
      () async => WarState.fromMap(_obj(await supa.rpc('find_or_queue_war'))));

  /// Posts one round's score as damage. The server clamps it to what a real
  /// round can produce and refuses once the player has used their counted
  /// matches for the day.
  Future<WarState?> submitWarMatch(int warId, int score) =>
      _guard(() async => WarState.fromMap(_obj(
          await supa.rpc('submit_war_match', params: {
            'p_war': warId,
            'p_score': score,
          }))));

  // ── Boards ─────────────────────────────────────────────
  Future<List<TeamBoardRow>> board({int limit = 30}) =>
      _guard(() async => _rows(await supa.rpc('team_board', params: {
            'p_limit': limit,
          })).map(TeamBoardRow.fromMap).toList());
}
