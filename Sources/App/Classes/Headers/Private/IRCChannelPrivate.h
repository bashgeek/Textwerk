/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "IRCChannel.h"
#import "IRCChannelMemberListPrivate.h"
#import "TVCLogController.h"

NS_ASSUME_NONNULL_BEGIN

@class TVCLogLine;

@interface IRCChannel () <IRCChannelMemberListPrivatePrototype>
@property (nonatomic, assign, readwrite) IRCChannelStatus status;
@property (nonatomic, assign) BOOL sentInitialWhoRequest;

/* Set once at least one WHOX reply (RPL_WHOSPCRPL) has actually come back
 for this channel - not merely requested. Until then, every member's
 IRCUser.account is nil simply because we haven't heard back yet, not
 because they're confirmed unauthenticated; the member list uses this to
 avoid flagging everyone as "not logged in" while a large channel list
 (e.g. ~100 channels through a bouncer) is still working through the
 request queue. Not persisted - only reflects the current session. */
@property (nonatomic, assign) BOOL receivedWhoxAccountData;
@property (nonatomic, assign) BOOL channelModesReceived;
@property (nonatomic, assign) BOOL channelNamesReceived;
@property (nonatomic, assign, readwrite) BOOL errorOnLastJoinAttempt;

/* Set when this private message query was created because the other
 user messaged us first, rather than by our own action (e.g. /query,
 double-clicking a nickname). Not persisted — only reflects the state
 of the current session. Used to show a one-time "who is this" banner. */
@property (nonatomic, assign) BOOL queryInitiatedByRemoteUser;
@property (nonatomic, copy, nullable) NSString *queryInitiatorHostmaskAddress;

/* The IRCv3 "msgid" of the most recent message seen in this channel, used
 to fill in gaps with CHATHISTORY LATEST on reconnect. Not persisted across
 app restarts — only covers gaps within the current run of the app. */
@property (nonatomic, copy, nullable) NSString *lastSeenMessageId;

/* The most recent draft/read-marker timestamp known for this channel,
 either sent by us when the user reads it or received from another client
 sharing the same bouncer/connection. Stored as the raw ISO 8601 wire
 value — nothing currently needs to parse it into an NSDate. */
@property (nonatomic, copy, nullable) NSString *lastReadMarkerTimestamp;

/* Nicknames currently signaling draft/typing "active" for this channel,
 mapped to the time that signal expires. Not persisted - purely a live
 session concept. Expiration (rather than trusting a "done"/"paused" to
 always arrive) matches the IRCv3 spec's guidance that a typing signal
 should be assumed stale after a few seconds without a refresh, since
 the other client could disconnect or crash without ever sending "done". */
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSDate *> *typingUserExpirationDates;

/* Throttles our own outgoing draft/typing "active" notifications for this
 channel to roughly once per few seconds, per the spec's rate-limiting
 recommendation, instead of firing on every keystroke. */
@property (nonatomic, strong, nullable) NSDate *lastOutgoingTypingActiveSentAt;

/* Marks nickname as actively typing in this channel, refreshing its
 expiration. Returns YES if this changed the set of currently-typing
 users (i.e. the caller should refresh any visible indicator). */
- (BOOL)markNicknameAsTyping:(NSString *)nickname;

/* Clears nickname's typing status immediately (draft/typing "done" or
 "paused"). Returns YES if this changed the set of currently-typing users. */
- (BOOL)clearTypingStatusForNickname:(NSString *)nickname;

/* Returns the nicknames currently signaling as typing, purging any whose
 expiration has passed. Order is not guaranteed. */
- (NSArray<NSString *> *)currentlyTypingNicknames;

- (instancetype)initWithConfig:(IRCChannelConfig *)config NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithConfigDictionary:(NSDictionary<NSString *, id> *)dic;

- (void)updateConfig:(IRCChannelConfig *)config;
- (void)updateConfig:(IRCChannelConfig *)config fireChangedNotification:(BOOL)fireChangedNotification;
- (void)updateConfig:(IRCChannelConfig *)config fireChangedNotification:(BOOL)fireChangedNotification updateStoredChannelList:(BOOL)updateStoredChannelList;

- (NSDictionary<NSString *, id> *)configurationDictionary;

- (void)writeToLogLineToLogFile:(TVCLogLine *)logLine;
- (void)logFileWriteSessionBegin;
- (void)logFileWriteSessionEnd;

- (void)print:(TVCLogLine *)logLine;
- (void)print:(TVCLogLine *)logLine completionBlock:(nullable TVCLogControllerPrintOperationCompletionBlock)completionBlock;

- (void)reopenLogFileIfNeeded;
- (void)closeLogFile;
@end

NS_ASSUME_NONNULL_END
