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
#import "ICMBandcamp.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICMBandcamp

- (void)_loadEmbedContents
{
	NSURL *targetURL = self.payload.url;

	/* Bandcamp's oEmbed endpoint (bandcamp.com/oembed) returns a bare 404
	 page for every request tried here, JSON or not -- seemingly dead or
	 gated on something this isn't providing. Its own pages do carry
	 normal Open Graph tags server-side though (the same tags Slack/
	 Discord/etc. read for their own link previews), so this reads those
	 directly instead. */
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
									siteName:@"bandcamp.com"
								   targetURL:targetURL];
	}];
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSParameterAssert(url != nil);

	if ([self _URLIsEmbeddable:url] == NO) {
		return nil;
	}

	return [^(ICLInlineContentModule *module) {
		__weak ICMBandcamp *moduleTyped = (id)module;

		[moduleTyped _loadEmbedContents];
	} copy];
}

+ (BOOL)_URLIsEmbeddable:(NSURL *)url
{
	NSString *host = url.host.lowercaseString;

	if (host == nil) {
		return NO;
	}

	if ([host isEqualToString:@"bandcamp.com"] || [host isEqualToString:@"www.bandcamp.com"]) {
		return NO; // Marketing site, not an artist subdomain
	}

	if ([host isDomainOrSubdomain:@"bandcamp.com"] == NO) {
		return NO;
	}

	NSString *urlPath = url.path.percentEncodedURLPath;

	if (urlPath.length <= 1) {
		return NO;
	}

	urlPath = [urlPath substringFromIndex:1]; // Leading "/"

	NSArray<NSString *> *components = [urlPath componentsSeparatedByString:@"/"];

	if (components.count < 2) {
		return NO;
	}

	return ([components[0] isEqualToString:@"track"] || [components[0] isEqualToString:@"album"]);
}

@end

NS_ASSUME_NONNULL_END
