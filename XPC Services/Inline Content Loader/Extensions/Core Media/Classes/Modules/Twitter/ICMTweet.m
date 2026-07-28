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
#import "ICMTweet.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMTweet

- (void)_loadTweetContents
{
	NSURL *targetURL = self.payload.url;

	NSString *tweetAddress = self.payload.address;

	NSURLComponents *requestComponents = [NSURLComponents componentsWithString:@"https://publish.twitter.com/oembed"];

	requestComponents.queryItems =
	@[
	  [NSURLQueryItem queryItemWithName:@"dnt" value:@"true"], /* DO NOT TRACK */
	  [NSURLQueryItem queryItemWithName:@"omit_script" value:@"true"],
	  [NSURLQueryItem queryItemWithName:@"url" value:tweetAddress]
	];

	NSURL *requestURL = requestComponents.URL;

	if (requestURL == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	[ICLHelpers requestJSONDataFromURL:requestURL completionBlock:^(BOOL success, NSDictionary<NSString *, id> *_Nullable data) {
		if (success == NO || data == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		/* The oEmbed response has no plain-text field for the tweet body --
		 it's embedded as markup (hashtags/links/media) inside "html"'s
		 first <p> tag, which this pulls out and strips down to text. */
		NSString *embedHTML = data[@"html"];

		NSString *tweetText = nil;

		if ([embedHTML isKindOfClass:[NSString class]]) {
			tweetText = [ICLHelpers firstParagraphPlainTextFromHTML:embedHTML];
		}

		if (tweetText.length == 0) {
			[self notifyUnableToPresentCard];

			return;
		}

		NSString *authorName = data[@"author_name"];

		if ([authorName isKindOfClass:[NSString class]] == NO || authorName.length == 0) {
			authorName = @"x.com";
		}

		[self performActionForCardWithTitle:tweetText
										meta:nil
									imageURL:nil
									siteName:authorName
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	if ([self _URLIsTweet:url] == NO) {
		return nil;
	}

	return [^(ICLInlineContentModule *module) {
		__weak ICMTweet *moduleTyped = (id)module;

		[moduleTyped _loadTweetContents];
	} copy];
}

+ (BOOL)_URLIsTweet:(NSURL *)url
{
	NSString *urlPath = url.path.percentEncodedURLPath;

	if (urlPath.length <= 1) {
		return NO;
	}

	urlPath = [urlPath substringFromIndex:1]; // "/"

	NSArray<NSString *> *components = [urlPath componentsSeparatedByString:@"/"];

	if (components.count < 3) {
		return NO;
	}

	if ([components[1] isEqualToString:@"status"] == NO) {
		return NO;
	}

	if (components[2].isNumericOnly == NO) {
		return NO;
	}

	return YES;
}

+ (nullable NSArray<NSString *> *)domains
{
	static NSArray<NSString *> *domains = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		domains =
		@[
		  @"twitter.com",
		  @"www.twitter.com",
		  @"mobile.twitter.com",
		  @"x.com",
		  @"www.x.com"
		];
	});

	return domains;
}

@end

NS_ASSUME_NONNULL_END
