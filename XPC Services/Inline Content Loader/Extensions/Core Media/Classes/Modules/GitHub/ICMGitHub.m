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

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	NSArray<NSString *> *components = [self _repositoryComponentsForURL:url];

	if (components == nil) {
		return nil;
	}

	NSString *owner = components[0];
	NSString *name = components[1];

	return [^(ICLInlineContentModule *module) {
		__weak ICMGitHub *moduleTyped = (id)module;

		[moduleTyped _loadRepositoryContentsForOwner:owner name:name];
	} copy];
}

+ (nullable NSArray<NSString *> *)_repositoryComponentsForURL:(NSURL *)url
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

	if (components.count != 2) {
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

	return @[owner, name];
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
