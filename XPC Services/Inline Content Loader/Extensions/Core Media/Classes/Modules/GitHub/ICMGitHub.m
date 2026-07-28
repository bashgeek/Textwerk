/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
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

#import "ICLHelpers.h"
#import "ICMGitHub.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMGitHub

- (void)_loadRepositoryContentsForOwner:(NSString *)owner name:(NSString *)name
{
	NSURL *targetURL = self.payload.url;

	NSString *apiAddress = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@", owner, name];

	NSURL *apiURL = [NSURL URLWithString:apiAddress];

	if (apiURL == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	[ICLHelpers requestJSONDataFromURL:apiURL completionBlock:^(BOOL success, NSDictionary<NSString *, id> *_Nullable data) {
		if (success == NO || data == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *fullName = data[@"full_name"];

		if ([fullName isKindOfClass:[NSString class]] == NO || fullName.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *language = data[@"language"];

		if ([language isKindOfClass:[NSString class]] == NO) {
			language = nil;
		}

		NSNumber *starCount = data[@"stargazers_count"];

		if ([starCount isKindOfClass:[NSNumber class]] == NO) {
			starCount = nil;
		}

		NSMutableArray<NSString *> *metaComponents = [NSMutableArray array];

		if (starCount != nil) {
			[metaComponents addObject:[NSString stringWithFormat:@"★ %@", starCount]];
		}

		if (language.length > 0) {
			[metaComponents addObject:language];
		}

		NSString *meta = nil;

		if (metaComponents.count > 0) {
			meta = [metaComponents componentsJoinedByString:@" · "];
		}

		NSDictionary *owner = data[@"owner"];

		NSString *avatarURLString = nil;

		if ([owner isKindOfClass:[NSDictionary class]]) {
			avatarURLString = owner[@"avatar_url"];
		}

		NSURL *avatarURL = nil;

		if ([avatarURLString isKindOfClass:[NSString class]]) {
			avatarURL = [NSURL URLWithString:avatarURLString];
		}

		[self performActionForCardWithTitle:fullName
										meta:meta
									imageURL:avatarURL
									siteName:@"github.com"
								   targetURL:targetURL];
	}];
}

- (void)_loadPullRequestForOwner:(NSString *)owner name:(NSString *)name number:(NSString *)number
{
	[self _loadIssueOrPullRequestForOwner:owner
									  name:name
									number:number
								  resource:@"pulls"
									 label:@"pull request"];
}

- (void)_loadIssueForOwner:(NSString *)owner name:(NSString *)name number:(NSString *)number
{
	[self _loadIssueOrPullRequestForOwner:owner
									  name:name
									number:number
								  resource:@"issues"
									 label:@"issue"];
}

- (void)_loadIssueOrPullRequestForOwner:(NSString *)owner
									name:(NSString *)name
								  number:(NSString *)number
								resource:(NSString *)resource
								   label:(NSString *)label
{
	NSURL *targetURL = self.payload.url;

	NSString *apiAddress = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/%@/%@", owner, name, resource, number];

	NSURL *apiURL = [NSURL URLWithString:apiAddress];

	if (apiURL == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	[ICLHelpers requestJSONDataFromURL:apiURL completionBlock:^(BOOL success, NSDictionary<NSString *, id> *_Nullable data) {
		if (success == NO || data == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *itemTitle = data[@"title"];

		if ([itemTitle isKindOfClass:[NSString class]] == NO || itemTitle.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *state = data[@"state"];

		NSString *statusLabel = @"Open";

		if ([data[@"merged"] isKindOfClass:[NSNumber class]] && [data[@"merged"] boolValue]) {
			statusLabel = @"Merged";
		} else if ([state isEqualToString:@"closed"]) {
			statusLabel = @"Closed";
		}

		NSDictionary *user = data[@"user"];

		NSString *authorLogin = nil;

		if ([user isKindOfClass:[NSDictionary class]]) {
			authorLogin = user[@"login"];
		}

		NSMutableArray<NSString *> *metaComponents = [NSMutableArray arrayWithObject:statusLabel];

		if ([authorLogin isKindOfClass:[NSString class]] && authorLogin.length > 0) {
			[metaComponents addObject:[NSString stringWithFormat:@"by %@", authorLogin]];
		}

		NSString *meta = [metaComponents componentsJoinedByString:@" · "];

		NSString *avatarURLString = nil;

		if ([user isKindOfClass:[NSDictionary class]]) {
			avatarURLString = user[@"avatar_url"];
		}

		NSURL *avatarURL = nil;

		if ([avatarURLString isKindOfClass:[NSString class]]) {
			avatarURL = [NSURL URLWithString:avatarURLString];
		}

		NSString *siteName = [NSString stringWithFormat:@"%@/%@#%@", owner, name, number];

		[self performActionForCardWithTitle:itemTitle
										meta:meta
									imageURL:avatarURL
									siteName:siteName
								   targetURL:targetURL];
	}];
}

- (void)_loadCommitForOwner:(NSString *)owner name:(NSString *)name sha:(NSString *)sha
{
	NSURL *targetURL = self.payload.url;

	NSString *apiAddress = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/%@", owner, name, sha];

	NSURL *apiURL = [NSURL URLWithString:apiAddress];

	if (apiURL == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	[ICLHelpers requestJSONDataFromURL:apiURL completionBlock:^(BOOL success, NSDictionary<NSString *, id> *_Nullable data) {
		if (success == NO || data == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSDictionary *commit = data[@"commit"];

		NSString *message = nil;

		if ([commit isKindOfClass:[NSDictionary class]]) {
			message = commit[@"message"];
		}

		if ([message isKindOfClass:[NSString class]] == NO || message.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		/* Commit messages are typically a short summary line, a blank line,
		 then an optional longer body. Only the summary belongs in a card. */
		NSString *title = [message componentsSeparatedByString:@"\n"].firstObject;

		if (title.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSDictionary *user = data[@"author"];

		NSString *authorName = nil;

		if ([user isKindOfClass:[NSDictionary class]]) {
			authorName = user[@"login"];
		}

		if (authorName.length == 0 && [commit isKindOfClass:[NSDictionary class]]) {
			NSDictionary *commitAuthor = commit[@"author"];

			if ([commitAuthor isKindOfClass:[NSDictionary class]]) {
				authorName = commitAuthor[@"name"];
			}
		}

		NSString *meta = nil;

		if ([authorName isKindOfClass:[NSString class]] && authorName.length > 0) {
			meta = authorName;
		}

		NSString *avatarURLString = nil;

		if ([user isKindOfClass:[NSDictionary class]]) {
			avatarURLString = user[@"avatar_url"];
		}

		NSURL *avatarURL = nil;

		if ([avatarURLString isKindOfClass:[NSString class]]) {
			avatarURL = [NSURL URLWithString:avatarURLString];
		}

		NSString *shortSHA = sha;

		if (shortSHA.length > 7) {
			shortSHA = [shortSHA substringToIndex:7];
		}

		NSString *siteName = [NSString stringWithFormat:@"%@/%@@%@", owner, name, shortSHA];

		[self performActionForCardWithTitle:title
										meta:meta
									imageURL:avatarURL
									siteName:siteName
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	NSArray<NSString *> *pathComponents = [self _pathComponentsForURL:url];

	if (pathComponents == nil) {
		return nil;
	}

	NSString *owner = pathComponents[0];
	NSString *name = pathComponents[1];

	if (pathComponents.count == 2) {
		return [^(ICLInlineContentModule *module) {
			__weak ICMGitHub *moduleTyped = (id)module;

			[moduleTyped _loadRepositoryContentsForOwner:owner name:name];
		} copy];
	}

	if (pathComponents.count == 4) {
		NSString *resourceType = pathComponents[2];
		NSString *resourceValue = pathComponents[3];

		if (resourceValue.length == 0) {
			return nil;
		}

		if ([resourceType isEqualToString:@"pull"]) {
			return [^(ICLInlineContentModule *module) {
				__weak ICMGitHub *moduleTyped = (id)module;

				[moduleTyped _loadPullRequestForOwner:owner name:name number:resourceValue];
			} copy];
		}

		if ([resourceType isEqualToString:@"issues"]) {
			return [^(ICLInlineContentModule *module) {
				__weak ICMGitHub *moduleTyped = (id)module;

				[moduleTyped _loadIssueForOwner:owner name:name number:resourceValue];
			} copy];
		}

		if ([resourceType isEqualToString:@"commit"]) {
			return [^(ICLInlineContentModule *module) {
				__weak ICMGitHub *moduleTyped = (id)module;

				[moduleTyped _loadCommitForOwner:owner name:name sha:resourceValue];
			} copy];
		}
	}

	return nil;
}

/* Returns the URL's path split into components (e.g. ["owner", "repo"] or
 ["owner", "repo", "pull", "2"]), after validating that at least an
 owner/repo pair is present and the owner isn't one of GitHub's reserved,
 non-user top-level paths (like "settings" or "marketplace"). Callers
 decide what to do with additional components beyond the first two. */
+ (nullable NSArray<NSString *> *)_pathComponentsForURL:(NSURL *)url
{
	NSString *urlPath = url.path.percentEncodedURLPath;

	if (urlPath.length <= 1) {
		return nil;
	}

	urlPath = [urlPath substringFromIndex:1]; // Leading "/"

	if ([urlPath hasSuffix:@"/"]) {
		urlPath = [urlPath substringToIndex:(urlPath.length - 1)];
	}

	NSArray<NSString *> *components = [urlPath componentsSeparatedByString:@"/"];

	if (components.count < 2) {
		return nil;
	}

	NSString *owner = components[0];
	NSString *name = components[1];

	if (owner.length == 0 || name.length == 0) {
		return nil;
	}

	if ([self _ownerIsReserved:owner]) {
		return nil;
	}

	return components;
}

+ (BOOL)_ownerIsReserved:(NSString *)owner
{
	static NSSet<NSString *> *reservedOwners = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		reservedOwners =
		[NSSet setWithArray:
		 @[
		   @"about", @"apps", @"codespaces", @"collections", @"customer-stories",
		   @"events", @"explore", @"features", @"join", @"login", @"marketplace",
		   @"notifications", @"orgs", @"pricing", @"security", @"settings",
		   @"sponsors", @"topics", @"trending"
		 ]];
	});

	return [reservedOwners containsObject:owner.lowercaseString];
}

+ (nullable NSArray<NSString *> *)domains
{
	static NSArray<NSString *> *domains = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		domains =
		@[
		  @"github.com",
		  @"www.github.com"
		];
	});

	return domains;
}

@end

NS_ASSUME_NONNULL_END
