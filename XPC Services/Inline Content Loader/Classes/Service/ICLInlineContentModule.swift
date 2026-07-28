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

import Foundation

public typealias ICLInlineContentModuleActionBlock = (ICLInlineContentModule) -> Void

@objc(ICLInlineContentModule)
open class ICLInlineContentModule: NSObject, @unchecked Sendable {

	// MARK: - Stored Properties

	private var _process: ICLProcessMain?

	@objc public let payload: ICLPayloadMutable

	private var _moduleFinalized: Bool = false

	// MARK: - Designated Initializers

	@available(*, unavailable)
	override public init() { fatalError("Use designated initializer") }

	@objc(initWithPayload:inProcess:)
	public required init(payload: ICLPayloadMutable, inProcess process: ICLProcessMain) {
		self.payload = payload
		self._process = process
		super.init()
		mergePropertiesIntoPayload()
	}

	@objc(initWithDeferredModule:)
	public required init(deferredModule module: ICLInlineContentModule) {
		self.payload = ICLPayloadMutable(deferredPayload: module.payload)
		self._process = module._process
		super.init()
		mergePropertiesIntoPayload()
	}

	// MARK: - Setup

	private func mergePropertiesIntoPayload() {
		if let scriptResources = scriptResources {
			payload.scriptResources = scriptResources
		}
		if let styleResources = styleResources {
			payload.styleResources = styleResources
		}
		if let entrypoint = entrypoint {
			payload.entrypoint = entrypoint
		}
	}

	// MARK: - Class Properties (override in subclasses)

	/* These members are declared `dynamic` (forcing Objective-C message
	 dispatch instead of Swift's vtable dispatch) because they are overridden
	 by Objective-C classes defined in separately-compiled plugin bundles
	 loaded at runtime via dlopen(). Swift's vtable for `open` members isn't
	 reliably patched for such cross-image overrides, which previously
	 crashed (EXC_BAD_ACCESS at a null vtable slot) the first time a plugin
	 module's overridden member was accessed. */

	@objc dynamic open class var domains: [String]? {
		return nil
	}

	/* Identifies this module in the per-provider "InlineMediaProviderEnabled"
	 preference (see TPCPreferences.inlineMediaProviderEnabled(_:)). Returning
	 nil (the default) falls back to the class's own name; a module only
	 needs to override this when it wants to share one user-facing toggle
	 with another class -- e.g. ICMTwitchClips and ICMTwitchLive both return
	 "Twitch", since a user thinks of that as a single service, not two. */
	@objc dynamic open class var preferenceIdentifier: String? {
		return nil
	}

	@objc(actionBlockForURL:)
	dynamic open class func actionBlock(for url: URL) -> ICLInlineContentModuleActionBlock? {
		return nil
	}

	@objc(actionForURL:)
	dynamic open class func action(for url: URL) -> Selector? {
		return nil
	}

	@objc dynamic open class var contentUntrusted: Bool { false }
	@objc dynamic open class var contentNotSafeForWork: Bool { false }

	// MARK: - Resources (override in subclasses)

	@objc dynamic open var styleResources: [URL]? { return nil }
	@objc dynamic open var scriptResources: [URL]? { return nil }
	@objc dynamic open var entrypoint: String? { return nil }

	// MARK: - Template

	@objc dynamic open var templateURL: URL? { return nil }

	@objc dynamic open var template: GRMustacheTemplate? {
		guard let url = templateURL, url.isFileURL else { return nil }
		var tmpl: GRMustacheTemplate? = nil
		do {
			tmpl = try GRMustacheTemplate(fromContentsOf: url)
		} catch {
			Logging.defaultSubsystem?.error("Failed to load template '\(url.standardized.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
		}
		return tmpl
	}
}

// MARK: - Completion

extension ICLInlineContentModule {

	private func finalizeAll() {
		_moduleFinalized = true
		_process = nil
	}

	/* Called on a module instance well after the synchronous call that
	 created it -- typically from an async network completion handler, on a
	 background queue. By then `self`'s only remaining static type
	 information is this base class; if `self`'s actual class is a
	 cross-image plugin subclass, non-`dynamic` calls on it (which Swift may
	 still route through its own vtable indirection even for non-`open`
	 members) hit the same crash as the metatype-mediated operations
	 documented in ICLProcessMain.swift. Marking them `dynamic` forces
	 ordinary Objective-C message dispatch instead. */

	@objc dynamic override public func finalize() {
		finalizeWithError(nil)
	}

	@objc dynamic public func finalizeWithError(_ error: Error?) {
		assert(!_moduleFinalized, "Module already finalized")
		finalizePreflight()
		_process?._finalizeModule(self, withError: error)
		finalizeAll()
	}

	@objc dynamic public func cancel() {
		assert(!_moduleFinalized, "Module already cancelled")
		finalizePreflight()
		_process?._cancelModule(self)
		finalizeAll()
	}

	@objc(isTypeDeferrable:)
	public class func isTypeDeferrable(_ type: ICLMediaType) -> Bool {
		return type == .image || type == .video || type == .videoGif
	}

	@objc dynamic public func deferAsType(_ type: ICLMediaType) {
		deferAsType(type, performCheck: true)
	}

	@objc dynamic public func deferAsType(_ type: ICLMediaType, performCheck: Bool) {
		assert(!_moduleFinalized, "Module already deferred")
		finalizePreflight()
		_process?._deferModule(self, asType: type, performCheck: performCheck)
		finalizeAll()
	}
}

// MARK: - Completion (Private)

extension ICLInlineContentModule {
	@objc dynamic open func finalizePreflight() {
		// Default implementation is empty; subclasses may override.
	}
}
