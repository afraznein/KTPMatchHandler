// KTPMatchHandler public forwards.
// Include this in a consumer plugin so its public handlers are checked against
// the signatures KTPMatchHandler registers with CreateMultiForward. The
// MatchType tag is the consumer's own enum; the values are KTPMatchHandler's
// MATCH_TYPE_* (0 competitive, 1 scrim, 2 12man, 3 draft, 4 ktpOT, 5 draftOT).

#if defined _ktp_matchhandler_included
    #endinput
#endif
#define _ktp_matchhandler_included

// half: 1 = first, 2 = second, 101+ = overtime round.
forward ktp_match_start(const matchId[], const map[], MatchType:matchType, half);

// Side-to-team map, delivered before the matching ktp_match_start. matchType is a string here.
forward ktp_match_side_map(const matchId[], const map[], const matchType[], half, alliesSlot, axisSlot);

// Fires once at first-half end, before the changelevel.
forward ktp_half_end(const matchId[], const map[], MatchType:matchType, half, team1Score, team2Score);

// A match that finished (regulation, OT, or abandoned). Stats consumers treat it as a result.
forward ktp_match_end(const matchId[], const map[], MatchType:matchType, team1Score, team2Score);

// A match closed with no result: a second-half .cancel ("secondhalf_cancel")
// or a .forcereset ("forcereset"). Neither path fires ktp_match_end, so a
// consumer that only scores results can ignore this one.
forward ktp_match_aborted(const matchId[], const map[], MatchType:matchType, const reason[]);
