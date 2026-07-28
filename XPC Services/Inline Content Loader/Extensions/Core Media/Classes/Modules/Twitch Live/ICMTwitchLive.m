/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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
#import "ICMTwitchLive.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMTwitchLive

- (void)_loadContent
{
	NSURL *targetURL = self.payload.url;

	/* Twitch's real API requires an OAuth app token, so there's no
	 unauthenticated way to fetch channel/video metadata that way. Its
	 pages do render normal Open Graph tags server-side though (the same
	 tags Slack/Discord/etc. read for their own link previews), so this
	 reads those directly instead of embedding the (also now-broken, see
	 ICMYouTube.m) live/VOD player. */
	[ICLHelpers requestHTMLFromURL:targetURL completionBlock:^(NSString *_Nullable html) {
		if (html == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *title = [ICLHelpers openGraphContentForProperty:@"og:title" inHTML:html];

		if (title.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *imageURLString = [ICLHelpers openGraphContentForProperty:@"og:image" inHTML:html];

		NSURL *imageURL = nil;

		if (imageURLString.length > 0) {
			imageURL = [NSURL URLWithString:imageURLString];
		}

		[self performActionForCardWithTitle:title
										meta:nil
									imageURL:imageURL
									siteName:@"twitch.tv"
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	if ([self _URLIsChannelOrVideo:url] == NO) {
		return nil;
	}

	return [^(ICLInlineContentModule *module) {
		__weak ICMTwitchLive *moduleTyped = (id)module;

		[moduleTyped _loadContent];
	} copy];
}

+ (BOOL)_URLIsChannelOrVideo:(NSURL *)url
{
	NSString *urlPath = url.path.percentEncodedURLPath;

	if (urlPath.length <= 1) {
		return NO;
	}

	urlPath = [urlPath substringFromIndex:1]; // "/"

	/* These exceptions cover all domains */
	if ([urlPath isEqualToString:@"directory"] ||
		[urlPath hasPrefix:@"directory/"] ||
		[urlPath isEqualToString:@"store"] ||
		[urlPath hasPrefix:@"store/"])
	{
		return NO;
	}

	/* Match videos */
	if ([urlPath hasPrefix:@"videos/"]) {
		NSString *contentIdentifier = [[urlPath substringFromIndex:7] trimCharacters:@"/"];

		return (contentIdentifier.isNumericOnly);
	}

	/* Consider any other match a channel */
	NSString *contentIdentifier = [urlPath trimCharacters:@"/"];

	if (contentIdentifier.length < 4 || contentIdentifier.length > 25) {
		return NO;
	}

	return [contentIdentifier onlyContainsCharactersFromCharacterSet:
			[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"]];
}

+ (nullable NSArray<NSString *> *)domains
{
	static NSArray<NSString *> *domains = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		domains =
		@[
		  @"twitch.tv",
		  @"www.twitch.tv",
		  @"go.twitch.tv"
		];
	});

	return domains;
}

/* Shared with ICMTwitchClips: users think of "Twitch" as one service. */
+ (nullable NSString *)preferenceIdentifier
{
	return @"Twitch";
}

@end

NS_ASSUME_NONNULL_END
