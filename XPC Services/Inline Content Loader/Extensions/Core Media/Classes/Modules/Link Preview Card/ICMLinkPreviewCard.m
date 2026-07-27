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
#import "ICMLinkPreviewCard.h"

#import <GRMustache/GRMustache.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ICMLinkPreviewCard

- (void)performActionForCardWithTitle:(NSString *)title
								  meta:(nullable NSString *)meta
							  imageURL:(nullable NSURL *)imageURL
							  siteName:(nullable NSString *)siteName
							 targetURL:(NSURL *)targetURL
{
	NSParameterAssert(title != nil);
	NSParameterAssert(targetURL != nil);

	if ([self.class _URLIsSafeToRender:targetURL] == NO) {
		[self notifyUnableToPresentCard];

		return;
	}

	if (imageURL != nil && [self.class _URLIsSafeToRender:imageURL] == NO) {
		imageURL = nil;
	}

	GRMustacheTemplate *cardTemplate = [self _cardTemplate];

	if (cardTemplate == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	NSMutableArray<NSString *> *subtitleComponents = [NSMutableArray array];

	if (siteName.length > 0) {
		[subtitleComponents addObject:siteName];
	}

	if (meta.length > 0) {
		[subtitleComponents addObject:meta];
	}

	NSMutableDictionary<NSString *, id> *templateAttributes = [NSMutableDictionary dictionary];

	templateAttributes[@"title"] = title;
	templateAttributes[@"targetURL"] = targetURL.absoluteString;

	if (subtitleComponents.count > 0) {
		templateAttributes[@"subtitle"] = [subtitleComponents componentsJoinedByString:@" · "];
	}

	if (imageURL != nil) {
		templateAttributes[@"imageURL"] = imageURL.absoluteString;
	}

	NSError *templateRenderError = nil;

	NSString *html = [cardTemplate renderObject:templateAttributes error:&templateRenderError];

	if (html == nil) {
		[self notifyUnableToPresentCard];

		return;
	}

	[self performActionForHTML:html];
}

- (void)notifyUnableToPresentCard
{
	[self notifyUnableToPresentHTML];
}

#pragma mark -
#pragma mark Utilities

+ (BOOL)_URLIsSafeToRender:(NSURL *)url
{
	NSString *scheme = url.scheme.lowercaseString;

	return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
}

- (nullable GRMustacheTemplate *)_cardTemplate
{
	static GRMustacheTemplate *template = nil;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSURL *templateURL = [NSBundleForClass() URLForResource:@"ICMLinkPreviewCard" withExtension:@"mustache"];

		if (templateURL == nil) {
			return;
		}

		NSError *templateLoadError = nil;

		template = [GRMustacheTemplate templateFromContentsOfURL:templateURL error:&templateLoadError];
	});

	return template;
}

- (nullable NSArray<NSURL *> *)styleResources
{
	NSURL *cssURL = [NSBundleForClass() URLForResource:@"ICMLinkPreviewCard" withExtension:@"css"];

	if (cssURL == nil) {
		return [super styleResources];
	}

	return [[super styleResources] arrayByAddingObject:cssURL];
}

- (void)finalizePreflight
{
	self.payload.classAttribute = @"inlineLinkPreviewCard";
}

@end

NS_ASSUME_NONNULL_END
