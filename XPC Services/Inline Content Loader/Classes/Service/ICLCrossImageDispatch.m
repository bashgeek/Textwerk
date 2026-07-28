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

#import "ICLCrossImageDispatch.h"
#import "ICLInlineContentModulePrivate.h"
#import "ICLPayloadPrivate.h"
#import "ICLProcessMainPrivate.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ICLCrossImageDispatch

+ (nullable NSArray<NSString *> *)domainsForModuleClass:(Class)moduleClass
{
	if ([moduleClass respondsToSelector:@selector(domains)] == NO) {
		return nil;
	}

	return [moduleClass domains];
}

+ (BOOL)moduleClassContentUntrusted:(Class)moduleClass
{
	if ([moduleClass respondsToSelector:@selector(contentUntrusted)] == NO) {
		return NO;
	}

	return [moduleClass contentUntrusted];
}

+ (BOOL)moduleClassContentNotSafeForWork:(Class)moduleClass
{
	if ([moduleClass respondsToSelector:@selector(contentNotSafeForWork)] == NO) {
		return NO;
	}

	return [moduleClass contentNotSafeForWork];
}

+ (NSString *)preferenceIdentifierForModuleClass:(Class)moduleClass
{
	NSString *identifier = nil;

	if ([moduleClass respondsToSelector:@selector(preferenceIdentifier)]) {
		identifier = [moduleClass preferenceIdentifier];
	}

	if (identifier.length == 0) {
		identifier = NSStringFromClass(moduleClass);
	}

	return identifier;
}

+ (nullable id)actionBlockForModuleClass:(Class)moduleClass url:(NSURL *)url
{
	if ([moduleClass respondsToSelector:@selector(actionBlockForURL:)] == NO) {
		return nil;
	}

	return [moduleClass actionBlockForURL:url];
}

+ (nullable SEL)actionSelectorForModuleClass:(Class)moduleClass url:(NSURL *)url
{
	if ([moduleClass respondsToSelector:@selector(actionForURL:)] == NO) {
		return NULL;
	}

	return [moduleClass actionForURL:url];
}

+ (nullable id)instantiateModuleClass:(Class)moduleClass payload:(ICLPayloadMutable *)payload process:(ICLProcessMain *)process
{
	if ([moduleClass isSubclassOfClass:[ICLInlineContentModule class]] == NO) {
		return nil;
	}

	return [[moduleClass alloc] initWithPayload:payload inProcess:process];
}

@end

NS_ASSUME_NONNULL_END
