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
#import "ICMGiphy.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMGiphy

- (void)_loadEmbedContents
{
	NSURL *targetURL = self.payload.url;

	NSURLComponents *requestComponents = [NSURLComponents componentsWithString:@"https://giphy.com/services/oembed"];

	requestComponents.queryItems =
	@[
	  [NSURLQueryItem queryItemWithName:@"url" value:targetURL.absoluteString]
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

		NSString *title = data[@"title"];

		if ([title isKindOfClass:[NSString class]] == NO || title.length == 0) {
			title = @"GIF";
		}

		NSString *mediaURLString = data[@"url"];

		NSURL *mediaURL = nil;

		if ([mediaURLString isKindOfClass:[NSString class]]) {
			mediaURL = [NSURL URLWithString:mediaURLString];
		}

		if (mediaURL == nil) {
			[self notifyUnableToPresentCard];

			return;
		}

		[self performActionForCardWithTitle:title
										meta:nil
									imageURL:mediaURL
									siteName:@"giphy.com"
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	if ([self _URLIsGifPage:url] == NO) {
		return nil;
	}

	return [^(ICLInlineContentModule *module) {
		__weak ICMGiphy *moduleTyped = (id)module;

		[moduleTyped _loadEmbedContents];
	} copy];
}

+ (BOOL)_URLIsGifPage:(NSURL *)url
{
	NSString *urlPath = url.path.percentEncodedURLPath;

	if (urlPath.length <= 1) {
		return NO;
	}

	urlPath = [urlPath substringFromIndex:1]; // Leading "/"

	NSArray<NSString *> *components = [urlPath componentsSeparatedByString:@"/"];

	if (components.count != 2) {
		return NO;
	}

	if ([components[0] isEqualToString:@"gifs"] == NO) {
		return NO;
	}

	return (components[1].length > 0);
}

+ (nullable NSArray<NSString *> *)domains
{
	static NSArray<NSString *> *domains = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		domains =
		@[
		  @"giphy.com",
		  @"www.giphy.com"
		];
	});

	return domains;
}

@end

NS_ASSUME_NONNULL_END
