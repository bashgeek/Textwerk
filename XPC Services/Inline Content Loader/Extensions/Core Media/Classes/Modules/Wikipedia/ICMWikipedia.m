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
#import "ICMWikipedia.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMWikipedia

- (void)_loadArticleContentsForHost:(NSString *)host encodedTitle:(NSString *)encodedTitle
{
	NSURL *targetURL = self.payload.url;

	NSString *apiAddress = [NSString stringWithFormat:@"https://%@/api/rest_v1/page/summary/%@", host, encodedTitle];

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

		NSString *title = data[@"title"];

		if ([title isKindOfClass:[NSString class]] == NO || title.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *meta = data[@"description"];

		if ([meta isKindOfClass:[NSString class]] == NO || meta.length == 0) {
			meta = data[@"extract"];

			if ([meta isKindOfClass:[NSString class]] == NO) {
				meta = nil;
			}
		}

		NSDictionary *thumbnail = data[@"thumbnail"];

		NSString *thumbnailURLString = nil;

		if ([thumbnail isKindOfClass:[NSDictionary class]]) {
			thumbnailURLString = thumbnail[@"source"];
		}

		NSURL *thumbnailURL = nil;

		if ([thumbnailURLString isKindOfClass:[NSString class]]) {
			thumbnailURL = [NSURL URLWithString:thumbnailURLString];
		}

		[self performActionForCardWithTitle:title
										meta:meta
									imageURL:thumbnailURL
									siteName:host
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	NSString *host = [self _articleHostForURL:url];

	if (host == nil) {
		return nil;
	}

	NSString *encodedTitle = [self _articleTitleForURL:url];

	if (encodedTitle == nil) {
		return nil;
	}

	return [^(ICLInlineContentModule *module) {
		__weak ICMWikipedia *moduleTyped = (id)module;

		[moduleTyped _loadArticleContentsForHost:host encodedTitle:encodedTitle];
	} copy];
}

+ (nullable NSString *)_articleHostForURL:(NSURL *)url
{
	NSString *host = url.host.lowercaseString;

	if (host == nil) {
		return nil;
	}

	if ([host isDomainOrSubdomain:@"wikipedia.org"] == NO) {
		return nil;
	}

	if ([host isEqualToString:@"www.wikipedia.org"]) {
		return nil; // Portal page, not a language edition
	}

	NSArray<NSString *> *hostComponents = [host componentsSeparatedByString:@"."];

	if (hostComponents.count != 3) {
		return nil; // Expect exactly "<lang>.wikipedia.org"
	}

	return host;
}

+ (nullable NSString *)_articleTitleForURL:(NSURL *)url
{
	NSString *urlPath = url.path.percentEncodedURLPath;

	NSString *prefix = @"/wiki/";

	if ([urlPath hasPrefix:prefix] == NO || urlPath.length <= prefix.length) {
		return nil;
	}

	NSString *encodedTitle = [urlPath substringFromIndex:prefix.length];

	NSString *decodedTitle = encodedTitle.stringByRemovingPercentEncoding;

	if (decodedTitle == nil) {
		return nil;
	}

	if ([self _titleIsInReservedNamespace:decodedTitle]) {
		return nil;
	}

	return encodedTitle;
}

+ (BOOL)_titleIsInReservedNamespace:(NSString *)title
{
	NSRange colonRange = [title rangeOfString:@":"];

	if (colonRange.location == NSNotFound) {
		return NO;
	}

	NSString *namespaceCandidate = [title substringToIndex:colonRange.location].lowercaseString;

	static NSSet<NSString *> *reservedNamespaces = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		reservedNamespaces =
		[NSSet setWithArray:
		 @[
		   @"special", @"file", @"category", @"talk", @"user", @"wikipedia",
		   @"help", @"portal", @"template", @"mediawiki", @"draft", @"module"
		 ]];
	});

	return [reservedNamespaces containsObject:namespaceCandidate];
}

@end

NS_ASSUME_NONNULL_END
