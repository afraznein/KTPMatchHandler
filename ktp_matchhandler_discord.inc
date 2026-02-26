// KTP Discord Notifications Include
// Extracted from KTPMatchHandler.sma — Discord messaging, embeds, roster tracking, config loading.
// All functions here rely on globals declared in the main .sma (g_discord*, g_roster*, g_match*, etc.)

#if defined _ktp_matchhandler_discord_included
    #endinput
#endif
#define _ktp_matchhandler_discord_included

// ================= Discord Notifications =================
#if defined HAS_CURL
stock get_discord_channel_id(channelId[], maxlen) {
    // Get the appropriate Discord channel ID based on match type
    // 12man/draft/scrim do NOT fall back to default - they require explicit channel config
    channelId[0] = EOS;

    switch (g_matchType) {
        case MATCH_TYPE_12MAN: {
            // 12man requires explicit channel - no fallback
            if (g_discordChannelId12man[0]) {
                copy(channelId, maxlen, g_discordChannelId12man);
            }
            // If not configured, channelId stays empty → Discord will be skipped
        }
        case MATCH_TYPE_SCRIM: {
            // Scrim requires explicit channel - no fallback
            if (g_discordChannelIdScrim[0]) {
                copy(channelId, maxlen, g_discordChannelIdScrim);
            }
            // If not configured, channelId stays empty → Discord will be skipped
        }
        case MATCH_TYPE_DRAFT: {
            // Draft requires explicit channel - no fallback
            if (g_discordChannelIdDraft[0]) {
                copy(channelId, maxlen, g_discordChannelIdDraft);
            }
            // If not configured, channelId stays empty → Discord will be skipped
        }
        default: {
            // Competitive matches use default channel
            copy(channelId, maxlen, g_discordChannelId);
        }
    }

    // Debug: log channel routing for non-competitive match types
    // Helps diagnose misrouted Discord embeds
    if (_:g_matchType != _:MATCH_TYPE_COMPETITIVE) {
        log_ktp("event=DISCORD_CHANNEL_ROUTE match_type=%d channel=%s", _:g_matchType, channelId[0] ? channelId : "(empty)");
    }
}

stock send_discord_message(const message[]) {
    // Debug: Log that we're attempting to send
    log_ktp("event=DISCORD_SEND_ATTEMPT msg='%.64s...' disabled=%d", message, g_disableDiscord);

    // Skip Discord if disabled (scrim/12man mode)
    if (g_disableDiscord) {
        log_ktp("event=DISCORD_SKIPPED reason='disabled'");
        return;
    }

    // Get the appropriate channel ID for the current match type
    // NOTE: Using global buffers (g_discord*) to avoid AMX stack overflow (16KB limit)
    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));

    // Check if Discord is configured (from INI)
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) {
        // Discord not configured, log which field is missing
        log_ktp("event=DISCORD_NOT_CONFIGURED url=%d channel=%d auth=%d",
                g_discordRelayUrl[0] ? 1 : 0,
                g_discordChannelIdBuf[0] ? 1 : 0,
                g_discordAuthSecret[0] ? 1 : 0);
        return;
    }

    // Escape special characters for JSON (using global buffer)
    new msgLen = strlen(message);
    new j = 0;
    for (new i = 0; i < msgLen; i++) {
        // Ensure we have room for escape sequence (2 chars) + null terminator
        if (j >= charsmax(g_discordEscapedMsg) - 3) break;

        // Handle special characters that need escaping
        switch (message[i]) {
            case '"': { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = '"'; }  // 92 = backslash
            case 92: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 92; }    // backslash
            case 10: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 'n'; }   // newline
            case 13: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 'r'; }   // carriage return
            case 9: { g_discordEscapedMsg[j++] = 92; g_discordEscapedMsg[j++] = 't'; }    // tab
            default: {
                // Copy character as-is if printable, skip control chars
                if (message[i] >= 32) {
                    g_discordEscapedMsg[j++] = message[i];
                }
            }
        }
    }
    g_discordEscapedMsg[j] = EOS;

    // Build JSON payload (using global buffer)
    // Note: No code block wrapper - let Discord render markdown formatting
    formatex(g_discordPayload, charsmax(g_discordPayload),
        "{^"channelId^":^"%s^",^"content^":^"[KTP] %s^"}",
        g_discordChannelIdBuf, g_discordEscapedMsg);

    // Create cURL handle
    new CURL:curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_discordPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_CURL_SEND url='%s' channel='%s'", g_discordRelayUrl, g_discordChannelIdBuf);
        curl_easy_perform(curl, "discord_callback");
    } else {
        log_ktp("event=DISCORD_ERROR reason='curl_init_failed'");
    }
}

public discord_callback(CURL:curl, CURLcode:code) {
    log_ktp("event=DISCORD_CALLBACK code=%d", _:code);
    if (code != CURLE_OK) {
        new error[128];
        curl_easy_strerror(code, error, charsmax(error));
        log_ktp("event=DISCORD_ERROR curl_code=%d error='%s'", _:code, error);
    } else {
        new httpCode;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, httpCode);
        if (httpCode >= 200 && httpCode < 300) {
            log_ktp("event=DISCORD_SUCCESS http=%d", httpCode);
        } else {
            log_ktp("event=DISCORD_HTTP_ERROR http=%d", httpCode);
        }
    }
    curl_easy_cleanup(curl);
    // Note: g_curlHeaders is persistent — never free here (overlapping async requests)
}

// Discord embed colors
#define DISCORD_COLOR_RED       16711680    // 0xFF0000 - Errors, bans, cancellations
#define DISCORD_COLOR_ORANGE    16750848    // 0xFFA500 - Warnings, resets
#define DISCORD_COLOR_GREEN     65280       // 0x00FF00 - Success
#define DISCORD_COLOR_BLUE      3447003     // 0x3498DB - Info

// Global buffer for simple embed payloads
new g_simpleEmbedPayload[1024];
new g_simpleEmbedTitle[128];
new g_simpleEmbedDesc[512];

// Send a simple Discord embed (for one-off events like cancel/reset)
stock send_discord_simple_embed(const title[], const description[], color) {
#if defined HAS_CURL
    if (g_disableDiscord) return;
    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    // Escape title and description
    escape_for_json(title, g_simpleEmbedTitle, charsmax(g_simpleEmbedTitle));
    escape_for_json(description, g_simpleEmbedDesc, charsmax(g_simpleEmbedDesc));

    // Escape server hostname for footer (local buffer to avoid forward reference)
    new hostnameEscaped[128];
    escape_for_json(g_serverHostname, hostnameEscaped, charsmax(hostnameEscaped));

    // Build embed payload
    // {"channelId":"...","embeds":[{"title":"...","description":"...","color":...,"footer":{"text":"server - map"}}]}
    formatex(g_simpleEmbedPayload, charsmax(g_simpleEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"description^":^"%s^",^"color^":%d,^"footer^":{^"text^":^"%s - %s^"}}]}",
        g_discordChannelIdBuf, g_simpleEmbedTitle, g_simpleEmbedDesc, color, hostnameEscaped, g_currentMap);

    // Send via curl
    new CURL:curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_simpleEmbedPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_EMBED_SIMPLE_SEND title='%s'", title);
        curl_easy_perform(curl, "discord_callback");
    }
#endif
}

// Escape a string for JSON string value (handles quotes, backslashes, newlines)
stock escape_for_json(const input[], output[], maxlen) {
    new j = 0;
    new inputLen = strlen(input);
    for (new i = 0; i < inputLen && j < maxlen - 2; i++) {
        switch (input[i]) {
            case '"': { output[j++] = 92; output[j++] = '"'; }   // escape quote
            case 92:  { output[j++] = 92; output[j++] = 92; }    // escape backslash
            case 10:  { output[j++] = 92; output[j++] = 'n'; }   // escape newline
            case 13:  { } // skip carriage return
            default:  { output[j++] = input[i]; }
        }
    }
    output[j] = EOS;
}

// Global buffers for escaped roster strings (avoid stack overflow)
new g_rosterAlliesEscaped[768];
new g_rosterAxisEscaped[768];
new g_serverHostnameEscaped[128];

// Send raw JSON payload to Discord (for embeds)
stock send_discord_embed_raw(const payload[]) {
#if defined HAS_CURL
    if (g_disableDiscord) return;
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    new CURL:curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, payload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_EMBED_SEND");
        curl_easy_perform(curl, "discord_callback");
    }
#endif
}

// ================= Consolidated Match Embed System =================
// This system creates a single Discord embed at match start and edits it
// at key points: 1st half end, 2nd half start, and match end.

// Save current roster to 1st half arrays for 2nd half comparison
stock save_first_half_roster() {
    g_firstHalfRosterAlliesCount = 0;
    g_firstHalfRosterAxisCount = 0;

    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        new authid[44];
        get_user_authid(id, authid, charsmax(authid));
        new teamId = get_user_team(id);

        if (teamId == 1 && g_firstHalfRosterAlliesCount < 16) {
            copy(g_firstHalfRosterAllies[g_firstHalfRosterAlliesCount], 43, authid);
            g_firstHalfRosterAlliesCount++;
        } else if (teamId == 2 && g_firstHalfRosterAxisCount < 16) {
            copy(g_firstHalfRosterAxis[g_firstHalfRosterAxisCount], 43, authid);
            g_firstHalfRosterAxisCount++;
        }
    }
    log_ktp("event=ROSTER_SAVED_1ST_HALF allies=%d axis=%d", g_firstHalfRosterAlliesCount, g_firstHalfRosterAxisCount);
}

// Check if a SteamID was in the 1st half roster for given team
// Note: In 2nd half, teams swap sides! So we check opposite array.
// team = current team (1=Allies, 2=Axis)
// Returns true if player was in 1st half
stock bool:was_in_first_half(const authid[], team) {
    // In 2nd half: current Allies were 1st half Axis, current Axis were 1st half Allies
    if (g_currentHalf == 2) {
        if (team == 1) {
            // Current Allies = was Axis in 1st half
            for (new i = 0; i < g_firstHalfRosterAxisCount; i++) {
                if (equal(authid, g_firstHalfRosterAxis[i])) return true;
            }
        } else if (team == 2) {
            // Current Axis = was Allies in 1st half
            for (new i = 0; i < g_firstHalfRosterAlliesCount; i++) {
                if (equal(authid, g_firstHalfRosterAllies[i])) return true;
            }
        }
    } else {
        // 1st half - check same team
        if (team == 1) {
            for (new i = 0; i < g_firstHalfRosterAlliesCount; i++) {
                if (equal(authid, g_firstHalfRosterAllies[i])) return true;
            }
        } else if (team == 2) {
            for (new i = 0; i < g_firstHalfRosterAxisCount; i++) {
                if (equal(authid, g_firstHalfRosterAxis[i])) return true;
            }
        }
    }
    return false;
}

// Build roster string with [2nd] tags for new players
stock build_roster_with_tags(output[], maxlen, team, &count) {
    output[0] = EOS;
    count = 0;

    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch");

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        new playerTeam = get_user_team(id);
        if (playerTeam != team) continue;

        new name[32], authid[44];
        get_user_name(id, name, charsmax(name));
        get_user_authid(id, authid, charsmax(authid));

        // Check if this is a new 2nd half player
        new entry[96];
        if (g_currentHalf == 2 && !was_in_first_half(authid, team)) {
            formatex(entry, charsmax(entry), "- %s [2nd] (%s)", name, authid);
        } else {
            formatex(entry, charsmax(entry), "- %s (%s)", name, authid);
        }

        // Add to roster
        new currentLen = strlen(output);
        new entryLen = strlen(entry);
        new requiredSpace = entryLen + (count > 0 ? 1 : 0);

        if (currentLen + requiredSpace < maxlen) {
            if (count > 0) {
                new sep[4];
                formatex(sep, charsmax(sep), "%c", 10);  // newline
                add(output, maxlen, sep);
            }
            add(output, maxlen, entry);
            count++;
        }
    }
}

// ================= Persistent Match Roster =================
// Tracks all players who participated in the match, even after they disconnect.
// This ensures Discord reports show all players, not just those connected at match end.

// Add a player to the persistent match roster (by team identity, not current side)
// team: 1 = Team 1, 2 = Team 2 (based on team identity, not Allies/Axis side)
// Returns true if added, false if already exists in EITHER roster or roster full
stock bool:add_to_match_roster(const name[], const authid[], team) {
    // Check if player is already in EITHER roster (prevents duplicates across teams)
    // This handles the case where a player hasn't switched sides yet after halftime
    for (new i = 0; i < g_matchRosterTeam1Count; i++) {
        if (contain(g_matchRosterTeam1[i], authid) != -1) {
            return false; // Already tracked in Team 1
        }
    }
    for (new i = 0; i < g_matchRosterTeam2Count; i++) {
        if (contain(g_matchRosterTeam2[i], authid) != -1) {
            return false; // Already tracked in Team 2
        }
    }

    // Build entry format: "name|steamid" (sanitize name to avoid delimiter collision)
    new safeName[32], entry[80];
    sanitize_name_for_localinfo(name, safeName, charsmax(safeName));
    formatex(entry, charsmax(entry), "%s|%s", safeName, authid);

    if (team == 1) {
        if (g_matchRosterTeam1Count >= MAX_ROSTER_ENTRIES) return false;
        copy(g_matchRosterTeam1[g_matchRosterTeam1Count], charsmax(g_matchRosterTeam1[]), entry);
        g_matchRosterTeam1Count++;
        return true;
    } else if (team == 2) {
        if (g_matchRosterTeam2Count >= MAX_ROSTER_ENTRIES) return false;
        copy(g_matchRosterTeam2[g_matchRosterTeam2Count], charsmax(g_matchRosterTeam2[]), entry);
        g_matchRosterTeam2Count++;
        return true;
    }
    return false;
}

// Clear the persistent match roster (call on match end/reset)
stock clear_match_roster() {
    for (new i = 0; i < MAX_ROSTER_ENTRIES; i++) {
        g_matchRosterTeam1[i][0] = EOS;
        g_matchRosterTeam2[i][0] = EOS;
    }
    g_matchRosterTeam1Count = 0;
    g_matchRosterTeam2Count = 0;
}

// Capture all current players to the persistent roster
// Call this at match start to get initial roster
stock capture_roster_snapshot() {
    new players[MAX_PLAYERS], pnum;
    get_players(players, pnum, "ch"); // connected, not HLTV

    for (new i = 0; i < pnum; i++) {
        new id = players[i];
        new name[32], authid[44];
        get_user_name(id, name, charsmax(name));
        get_user_authid(id, authid, charsmax(authid));
        new side = get_user_team(id); // 1=Allies, 2=Axis

        // Convert current side to team identity
        // In 1st half: Allies = Team 1, Axis = Team 2
        // In 2nd half: Allies = Team 2, Axis = Team 1
        new teamId;
        if (g_currentHalf == 2) {
            teamId = (side == 1) ? 2 : 1; // Swapped
        } else {
            teamId = side;
        }

        if (teamId == 1 || teamId == 2) {
            add_to_match_roster(name, authid, teamId);
        }
    }
    log_ktp("event=ROSTER_SNAPSHOT team1=%d team2=%d", g_matchRosterTeam1Count, g_matchRosterTeam2Count);
}

// Get player's team identity (1 or 2) based on roster lookup by SteamID
// Returns: 1 = Team 1, 2 = Team 2, 0 = not in roster
stock get_player_roster_team(id) {
    new authid[44];
    get_user_authid(id, authid, charsmax(authid));

    // Check Team 1 roster
    for (new i = 0; i < g_matchRosterTeam1Count; i++) {
        if (contain(g_matchRosterTeam1[i], authid) != -1) {
            return 1;
        }
    }
    // Check Team 2 roster
    for (new i = 0; i < g_matchRosterTeam2Count; i++) {
        if (contain(g_matchRosterTeam2[i], authid) != -1) {
            return 2;
        }
    }
    return 0;  // Not in roster
}

// Build roster string from stored data (not live players)
// team: 1 = Team 1, 2 = Team 2
stock build_roster_from_stored(output[], maxlen, team, &count) {
    output[0] = EOS;
    count = 0;

    new roster[MAX_ROSTER_ENTRIES][80];
    new rosterCount;

    if (team == 1) {
        rosterCount = g_matchRosterTeam1Count;
        for (new i = 0; i < rosterCount; i++) {
            copy(roster[i], charsmax(roster[]), g_matchRosterTeam1[i]);
        }
    } else {
        rosterCount = g_matchRosterTeam2Count;
        for (new i = 0; i < rosterCount; i++) {
            copy(roster[i], charsmax(roster[]), g_matchRosterTeam2[i]);
        }
    }

    for (new i = 0; i < rosterCount; i++) {
        // Parse "name|steamid"
        new name[32], authid[44];
        new pipePos = contain(roster[i], "|");
        if (pipePos > 0) {
            copy(name, min(pipePos, charsmax(name)), roster[i]);
            copy(authid, charsmax(authid), roster[i][pipePos + 1]);
        } else {
            continue;
        }

        new entry[96];
        formatex(entry, charsmax(entry), "- %s (%s)", name, authid);

        new currentLen = strlen(output);
        new entryLen = strlen(entry);
        new requiredSpace = entryLen + (count > 0 ? 1 : 0);

        if (currentLen + requiredSpace < maxlen) {
            if (count > 0) {
                new sep[4];
                formatex(sep, charsmax(sep), "%c", 10); // newline
                add(output, maxlen, sep);
            }
            add(output, maxlen, entry);
            count++;
        }
    }
}

// Save roster to localinfo (for map change persistence)
// Format: "name|sid;name|sid;..." (semicolon separates entries)
stock save_roster_to_localinfo() {
    new buf[1024];

    // Save Team 1 roster
    buf[0] = EOS;
    for (new i = 0; i < g_matchRosterTeam1Count; i++) {
        if (i > 0) add(buf, charsmax(buf), ";");
        add(buf, charsmax(buf), g_matchRosterTeam1[i]);
    }
    set_localinfo(LOCALINFO_ROSTER1, buf);

    // Save Team 2 roster
    buf[0] = EOS;
    for (new i = 0; i < g_matchRosterTeam2Count; i++) {
        if (i > 0) add(buf, charsmax(buf), ";");
        add(buf, charsmax(buf), g_matchRosterTeam2[i]);
    }
    set_localinfo(LOCALINFO_ROSTER2, buf);

    log_ktp("event=ROSTER_SAVED_LOCALINFO team1=%d team2=%d", g_matchRosterTeam1Count, g_matchRosterTeam2Count);
}

// Restore roster from localinfo (after map change)
stock restore_roster_from_localinfo() {
    new buf[1024];

    // Restore Team 1 roster
    get_localinfo(LOCALINFO_ROSTER1, buf, charsmax(buf));
    if (buf[0]) {
        g_matchRosterTeam1Count = 0;
        new entry[80], pos = 0, bufLen = strlen(buf);
        while (pos < bufLen && g_matchRosterTeam1Count < MAX_ROSTER_ENTRIES) {
            // Find next semicolon or end of string
            new endPos = pos;
            while (buf[endPos] && buf[endPos] != ';') endPos++;

            // Extract entry
            new len = endPos - pos;
            if (len > 0 && len < sizeof(entry)) {
                copy(entry, len, buf[pos]);
                entry[len] = EOS;
                copy(g_matchRosterTeam1[g_matchRosterTeam1Count], charsmax(g_matchRosterTeam1[]), entry);
                g_matchRosterTeam1Count++;
            }

            pos = endPos + 1;
            if (!buf[endPos]) break;
        }
    }

    // Restore Team 2 roster
    get_localinfo(LOCALINFO_ROSTER2, buf, charsmax(buf));
    if (buf[0]) {
        g_matchRosterTeam2Count = 0;
        new entry[80], pos = 0, bufLen = strlen(buf);
        while (pos < bufLen && g_matchRosterTeam2Count < MAX_ROSTER_ENTRIES) {
            new endPos = pos;
            while (buf[endPos] && buf[endPos] != ';') endPos++;

            new len = endPos - pos;
            if (len > 0 && len < sizeof(entry)) {
                copy(entry, len, buf[pos]);
                entry[len] = EOS;
                copy(g_matchRosterTeam2[g_matchRosterTeam2Count], charsmax(g_matchRosterTeam2[]), entry);
                g_matchRosterTeam2Count++;
            }

            pos = endPos + 1;
            if (!buf[endPos]) break;
        }
    }

    log_ktp("event=ROSTER_RESTORED_LOCALINFO team1=%d team2=%d", g_matchRosterTeam1Count, g_matchRosterTeam2Count);
}

// Build the scores section for the embed
new g_embedScoresField[256];
stock build_scores_field() {
    g_embedScoresField[0] = EOS;

    if (g_currentHalf == 1) {
        // 1st half in progress - just show current score
        formatex(g_embedScoresField, charsmax(g_embedScoresField),
            "**In Progress**^n%s %d - %d %s",
            g_team1Name, g_matchScore[1], g_matchScore[2], g_team2Name);
    } else if (g_currentHalf == 2) {
        // 2nd half - show 1st half + current 2nd half
        // Teams swapped sides: Team 1 is now Axis, Team 2 is now Allies
        // g_matchScore contains the CURRENT scoreboard (includes restored 1st half scores)
        //
        // Scoreboard restoration puts:
        //   Allies (Team 2's side now) = Team 2's 1st half score (g_firstHalfScore[2])
        //   Axis (Team 1's side now) = Team 1's 1st half score (g_firstHalfScore[1])
        //
        // So 2nd half scores are:
        //   Team 1's 2nd half = Current Axis (g_matchScore[2]) - Team 1's 1st half
        //   Team 2's 2nd half = Current Allies (g_matchScore[1]) - Team 2's 1st half
        new team1SecondHalf = g_matchScore[2] - g_firstHalfScore[1];
        new team2SecondHalf = g_matchScore[1] - g_firstHalfScore[2];

        // Clamp to 0 in case of any weirdness
        if (team1SecondHalf < 0) team1SecondHalf = 0;
        if (team2SecondHalf < 0) team2SecondHalf = 0;

        // Total = 1st half + 2nd half
        new team1Total = g_firstHalfScore[1] + team1SecondHalf;
        new team2Total = g_firstHalfScore[2] + team2SecondHalf;

        formatex(g_embedScoresField, charsmax(g_embedScoresField),
            "**1st Half:** %s %d - %d %s^n**2nd Half:** %d - %d^n**Total:** %d - %d",
            g_team1Name, g_firstHalfScore[1], g_firstHalfScore[2], g_team2Name,
            team1SecondHalf, team2SecondHalf,
            team1Total, team2Total);
    }
}

// Callback for Discord embed with response capture (C++ module buffers body automatically)
public discord_embed_callback(CURL:curl, CURLcode:code) {
    if (code == CURLE_OK) {
        curl_get_response_body(curl, g_discordResponseBuf, charsmax(g_discordResponseBuf));

        // Parse message ID from JSON response: {"id":"1234567890",...}
        new idStart = contain(g_discordResponseBuf, "^"id^":^"");
        if (idStart != -1) {
            idStart += 6;  // Skip past "id":"
            new idEnd = idStart;
            while (g_discordResponseBuf[idEnd] && g_discordResponseBuf[idEnd] != '"' && idEnd < idStart + 30) {
                idEnd++;
            }
            new idLen = idEnd - idStart;
            if (idLen > 0 && idLen < charsmax(g_discordMatchMsgId)) {
                for (new i = 0; i < idLen; i++) {
                    g_discordMatchMsgId[i] = g_discordResponseBuf[idStart + i];
                }
                g_discordMatchMsgId[idLen] = EOS;

                // Store in localinfo for 2nd half
                set_localinfo(LOCALINFO_DISCORD_MSG, g_discordMatchMsgId);
                copy(g_discordMatchChannelId, charsmax(g_discordMatchChannelId), g_discordChannelIdBuf);
                set_localinfo(LOCALINFO_DISCORD_CHAN, g_discordMatchChannelId);

                log_ktp("event=DISCORD_MSG_ID_CAPTURED id=%s channel=%s", g_discordMatchMsgId, g_discordMatchChannelId);
            } else {
                log_ktp("event=DISCORD_MSG_ID_PARSE_FAILED idLen=%d response='%.100s'", idLen, g_discordResponseBuf);
            }
        } else {
            log_ktp("event=DISCORD_MSG_ID_NOT_FOUND response='%.100s'", g_discordResponseBuf);
        }
        new httpCode;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, httpCode);
        if (httpCode >= 200 && httpCode < 300) {
            log_ktp("event=DISCORD_EMBED_SUCCESS http=%d", httpCode);
        } else {
            log_ktp("event=DISCORD_EMBED_HTTP_ERROR http=%d response='%.100s'", httpCode, g_discordResponseBuf);
        }
    } else {
        new error[128];
        curl_easy_strerror(code, error, charsmax(error));
        log_ktp("event=DISCORD_EMBED_ERROR code=%d error='%s'", _:code, error);
    }

    curl_easy_cleanup(curl);
    // Note: g_curlHeaders is persistent — never free here (overlapping async requests)
}

// Send match embed and capture message ID for later editing
stock send_match_embed_create() {
    if (g_disableDiscord) return;

    // Get channel ID
    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    // Build rosters
    new alliesCount = 0, axisCount = 0;
    build_roster_with_tags(g_rosterAllies, charsmax(g_rosterAllies), 1, alliesCount);
    build_roster_with_tags(g_rosterAxis, charsmax(g_rosterAxis), 2, axisCount);

    // Escape for JSON
    escape_for_json(g_rosterAllies[0] ? g_rosterAllies : "No players", g_rosterAlliesEscaped, charsmax(g_rosterAlliesEscaped));
    escape_for_json(g_rosterAxis[0] ? g_rosterAxis : "No players", g_rosterAxisEscaped, charsmax(g_rosterAxisEscaped));
    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    // Build title
    new dateStr[16];
    get_time("%m/%d/%Y", dateStr, charsmax(dateStr));
    new embedTitle[128];
    formatex(embedTitle, charsmax(embedTitle), "%s %s vs %s", dateStr, g_team1Name, g_team2Name);
    new embedTitleEscaped[160];
    escape_for_json(embedTitle, embedTitleEscaped, charsmax(embedTitleEscaped));

    // Build embed JSON - initial version at match start
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"color^":3447003,^"fields^":[{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Status^",^"value^":^"1st Half - Match Live^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Map: %s | Server: %s^"}}]}",
        g_discordChannelIdBuf,
        embedTitleEscaped,
        g_team1Name, alliesCount, g_rosterAlliesEscaped,
        g_team2Name, axisCount, g_rosterAxisEscaped,
        g_matchId, g_matchMap, g_serverHostnameEscaped);

    // Send with response capture (C++ module auto-buffers when no WRITEFUNCTION set)
    new CURL:curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, g_discordRelayUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_rosterEmbedPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_MATCH_EMBED_CREATE");
        curl_easy_perform(curl, "discord_embed_callback");
    }

    // Save roster for 2nd half comparison
    save_first_half_roster();
}

// Edit the existing match embed with updated info
stock send_match_embed_update(const status[]) {
    if (g_disableDiscord) return;
    if (!g_discordMatchMsgId[0]) {
        log_ktp("event=DISCORD_EDIT_SKIP reason=no_msg_id");
        return;
    }

    // Get channel ID (use stored channel or current)
    new channelId[64];
    if (g_discordMatchChannelId[0]) {
        copy(channelId, charsmax(channelId), g_discordMatchChannelId);
    } else {
        get_discord_channel_id(channelId, charsmax(channelId));
    }

    if (!g_discordRelayUrl[0] || !channelId[0] || !g_discordAuthSecret[0]) return;

    // Build rosters - prefer stored roster (survives disconnects), fall back to live players
    new team1Count = 0, team2Count = 0;

    // Try stored roster first (by team identity)
    build_roster_from_stored(g_rosterAllies, charsmax(g_rosterAllies), 1, team1Count);
    build_roster_from_stored(g_rosterAxis, charsmax(g_rosterAxis), 2, team2Count);

    // Fall back to live players if stored roster is empty
    if (team1Count == 0 && team2Count == 0) {
        // No stored roster, use live players with [2nd] tags
        new alliesCount = 0, axisCount = 0;
        build_roster_with_tags(g_rosterAllies, charsmax(g_rosterAllies), 1, alliesCount);
        build_roster_with_tags(g_rosterAxis, charsmax(g_rosterAxis), 2, axisCount);
        team1Count = alliesCount;
        team2Count = axisCount;
    }

    escape_for_json(g_rosterAllies[0] ? g_rosterAllies : "No players", g_rosterAlliesEscaped, charsmax(g_rosterAlliesEscaped));
    escape_for_json(g_rosterAxis[0] ? g_rosterAxis : "No players", g_rosterAxisEscaped, charsmax(g_rosterAxisEscaped));
    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    // Build title
    new dateStr[16];
    get_time("%m/%d/%Y", dateStr, charsmax(dateStr));
    new embedTitle[128];
    formatex(embedTitle, charsmax(embedTitle), "%s %s vs %s", dateStr, g_team1Name, g_team2Name);
    new embedTitleEscaped[160];
    escape_for_json(embedTitle, embedTitleEscaped, charsmax(embedTitleEscaped));

    // Build scores field
    build_scores_field();
    new scoresEscaped[300];
    escape_for_json(g_embedScoresField, scoresEscaped, charsmax(scoresEscaped));

    // Escape status
    new statusEscaped[128];
    escape_for_json(status, statusEscaped, charsmax(statusEscaped));

    // Build edit URL (replace /reply with /edit in relay URL)
    new editUrl[256];
    copy(editUrl, charsmax(editUrl), g_discordRelayUrl);
    replace_string(editUrl, charsmax(editUrl), "/reply", "/edit");

    // Build edit payload with messageId
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"messageId^":^"%s^",^"embeds^":[{^"title^":^"%s^",^"color^":3447003,^"fields^":[{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"%s (%d)^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Scores^",^"value^":^"%s^",^"inline^":false},{^"name^":^"Status^",^"value^":^"%s^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Map: %s | Server: %s^"}}]}",
        channelId,
        g_discordMatchMsgId,
        embedTitleEscaped,
        g_team1Name, team1Count, g_rosterAlliesEscaped,
        g_team2Name, team2Count, g_rosterAxisEscaped,
        scoresEscaped,
        statusEscaped,
        g_matchId, g_matchMap, g_serverHostnameEscaped);

    // Send edit request
    new CURL:curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, editUrl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, g_curlHeaders);
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, g_rosterEmbedPayload);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5);

        log_ktp("event=DISCORD_MATCH_EMBED_UPDATE status='%s' msg_id=%s", status, g_discordMatchMsgId);
        curl_easy_perform(curl, "discord_callback");
    }
}

// Send disconnect auto-pause as an embed (matches roster format)
stock send_discord_disconnect_embed(const playerName[], const playerId[], team) {
    if (g_disableDiscord) return;

    get_discord_channel_id(g_discordChannelIdBuf, charsmax(g_discordChannelIdBuf));
    if (!g_discordRelayUrl[0] || !g_discordChannelIdBuf[0] || !g_discordAuthSecret[0]) return;

    escape_for_json(g_serverHostname, g_serverHostnameEscaped, charsmax(g_serverHostnameEscaped));

    new teamName[32];
    copy(teamName, charsmax(teamName), g_teamName[team]);
    new teamNameEscaped[48];
    escape_for_json(teamName, teamNameEscaped, charsmax(teamNameEscaped));

    new playerNameEscaped[48];
    escape_for_json(playerName, playerNameEscaped, charsmax(playerNameEscaped));

    // Orange color for warning
    formatex(g_rosterEmbedPayload, charsmax(g_rosterEmbedPayload),
        "{^"channelId^":^"%s^",^"embeds^":[{^"title^":^"⚠️ Player Disconnected^",^"color^":15105570,^"fields^":[{^"name^":^"Player^",^"value^":^"%s (%s)^",^"inline^":true},{^"name^":^"Team^",^"value^":^"%s^",^"inline^":true},{^"name^":^"Status^",^"value^":^"Auto Tech Pause - Awaiting reconnect^",^"inline^":false}],^"footer^":{^"text^":^"Match: %s | Map: %s | Server: %s^"}}]}",
        g_discordChannelIdBuf,
        playerNameEscaped, playerId,
        teamNameEscaped,
        g_matchId, g_matchMap, g_serverHostnameEscaped);

    send_discord_embed_raw(g_rosterEmbedPayload);
    log_ktp("event=DISCORD_DISCONNECT_EMBED player='%s' team=%d", playerName, team);
}

// ================= End Consolidated Match Embed System =================

#else
// Stub function when cURL not available
stock send_discord_message(const message[]) {
    #pragma unused message
    // cURL not available, skip
}
#endif

// ================= Discord Config INI =================
stock load_discord_config() {
    // Reset to defaults
    g_discordRelayUrl[0] = EOS;
    g_discordChannelId[0] = EOS;
    g_discordChannelId12man[0] = EOS;
    g_discordChannelIdScrim[0] = EOS;
    g_discordChannelIdDraft[0] = EOS;
    g_discordAuthSecret[0] = EOS;

    new path[192];
    get_pcvar_string(g_cvarDiscordIniPath, path, charsmax(path));
    if (!path[0]) {
        // Use get_configsdir() for proper path resolution
        new configsDir[128];
        get_configsdir(configsDir, charsmax(configsDir));
        formatex(path, charsmax(path), "%s/discord.ini", configsDir);
    }

    new fp = fopen(path, "rt");
    if (!fp) {
        log_ktp("event=DISCORD_CONFIG_LOAD status=skip reason='file_not_found' path='%s'", path);
        return;
    }

    new line[256], key[64], val[192];
    new loaded = 0;

    while (!feof(fp)) {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        new eq = contain(line, "=");
        if (eq <= 0) continue;

        copy(key, min(eq, charsmax(key)), line);
        trim(key);
        strtolower_inplace(key);

        copy(val, charsmax(val), line[eq + 1]);
        trim(val);

        if (!key[0] || !val[0]) continue;

        // Parse Discord config keys
        if (equal(key, "discord_relay_url")) {
            copy(g_discordRelayUrl, charsmax(g_discordRelayUrl), val);
            loaded++;
        } else if (equal(key, "discord_channel_id")) {
            copy(g_discordChannelId, charsmax(g_discordChannelId), val);
            loaded++;
        } else if (equal(key, "discord_channel_id_12man")) {
            copy(g_discordChannelId12man, charsmax(g_discordChannelId12man), val);
            loaded++;
        } else if (equal(key, "discord_channel_id_scrim")) {
            copy(g_discordChannelIdScrim, charsmax(g_discordChannelIdScrim), val);
            loaded++;
        } else if (equal(key, "discord_channel_id_draft")) {
            copy(g_discordChannelIdDraft, charsmax(g_discordChannelIdDraft), val);
            loaded++;
        } else if (equal(key, "discord_auth_secret")) {
            copy(g_discordAuthSecret, charsmax(g_discordAuthSecret), val);
            loaded++;
        }
    }
    fclose(fp);

    log_ktp("event=DISCORD_CONFIG_LOAD status=ok loaded=%d path='%s'", loaded, path);
}
