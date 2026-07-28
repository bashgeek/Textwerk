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
import os.log

private let ICLInlineContentErrorDomain: String = "ICLInlineContentErrorDomain"

/* Module classes may be Objective-C classes defined in a separately
 dlopen()'d plugin bundle. Calling their overridden class members through a
 Swift metatype (`someAnyClass as? ICLInlineContentModule.Type`, then
 `cls.someMember` / `cls.init(...)`, or dynamic-casting an instance back)
 crashes: Swift synthesizes "artificial subclass" metadata to represent a
 cross-image class in its type system, and several Swift runtime entry
 points (dynamic cast, required-init dispatch, closure-call thunks) don't
 reliably resolve that synthetic metadata back to the real Class. Every
 operation below is instead implemented in plain Objective-C
 (ICLCrossImageDispatch), which only ever sees a `Class`/`id` value and
 never asks Swift's type system to reason about it. */

private func classDomains(_ cls: AnyClass) -> [String]? {
	ICLCrossImageDispatch.domains(forModuleClass: cls)
}

private func classContentUntrusted(_ cls: AnyClass) -> Bool {
	ICLCrossImageDispatch.moduleClassContentUntrusted(cls)
}

private func classContentNotSafeForWork(_ cls: AnyClass) -> Bool {
	ICLCrossImageDispatch.moduleClassContentNotSafeForWork(cls)
}

private func classPreferenceIdentifier(_ cls: AnyClass) -> String {
	ICLCrossImageDispatch.preferenceIdentifier(forModuleClass: cls)
}

private func classActionBlock(_ cls: AnyClass, for url: URL) -> ICLInlineContentModuleActionBlock? {
	/* ICLCrossImageDispatch declares this `id`-returning (see its header for
	 why), so it comes back as a plain AnyObject holding a real Objective-C
	 block. Reinterpreting it as a @convention(block) closure is a safe,
	 ordinary reinterpret of a value already known to be a valid block --
	 not a dynamic cast -- and implicitly converts to the native Swift
	 closure type this function returns. */
	guard let raw = ICLCrossImageDispatch.actionBlock(forModuleClass: cls, url: url) else { return nil }
	typealias BlockType = @convention(block) (ICLInlineContentModule) -> Void
	return unsafeBitCast(raw as AnyObject, to: BlockType.self)
}

private func classAction(_ cls: AnyClass, for url: URL) -> Selector? {
	ICLCrossImageDispatch.actionSelector(forModuleClass: cls, url: url)
}

private func classInstantiate(_ cls: AnyClass, payload: ICLPayloadMutable, process: ICLProcessMain) -> ICLInlineContentModule? {
	/* Same `id`-return rationale as classActionBlock(_:for:) above. The
	 class was already established (in processPayload(_:using:)) to
	 conform to ICLInlineContentModule.Type, so an unchecked downcast here
	 is safe and avoids the runtime dynamic cast machinery entirely. */
	guard let raw = ICLCrossImageDispatch.instantiateModuleClass(cls, payload: payload, process: process) else { return nil }
	return unsafeDowncast(raw as AnyObject, to: ICLInlineContentModule.self)
}

@objc public final class ICLProcessMain: NSObject, ICLInlineContentServerProtocol, @unchecked Sendable {
	private let serviceConnection: NSXPCConnection

	@available(*, unavailable) override init() { fatalError() }

	@objc init(xpcConnection connection: NSXPCConnection) {
		serviceConnection = connection
		super.init()
		Logging.defaultSubsystem = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
	}

	// MARK: - Module Registry

	/* A module must stay alive for the whole duration of its (often async,
	 e.g. a network request) work -- NSCache is the wrong tool for that: it's
	 explicitly permitted to evict entries at any time under memory pressure,
	 which deallocates the module mid-flight and crashes whatever async
	 callback (URLSession delegate, completion handler) fires afterward on
	 the now-freed object. A plain dictionary, only ever removed from
	 explicitly in removeReference(for:), doesn't have that failure mode. */
	private static let moduleReferencesLock = NSLock()
	nonisolated(unsafe) private static var moduleReferences: [String: ICLInlineContentModule] = [:]

	/* Modules dict is built once on first access (thread-safe via static let).
	 warmServiceByLoadingPluginsAtLocations: must be called before URL processing. */
	private static let modules: [String: [AnyClass]] = {
		let pluginModules: [AnyClass] = ICLPluginManager.shared().modules
		let allModules: [AnyClass] = pluginModules + [ICMAssessedMedia.self]

		var result: [String: [AnyClass]] = [:]
		for moduleClass in allModules {
			guard moduleClass is ICLInlineContentModule.Type else { continue }
			let domains = classDomains(moduleClass) ?? []
			if domains.isEmpty {
				result["*", default: []].append(moduleClass)
			} else {
				for domain in domains {
					result[domain, default: []].append(moduleClass)
				}
			}
		}
		return result
	}()

	// MARK: - Process Management

	private static let pluginLoadLock = NSLock()
	nonisolated(unsafe) private static var pluginsLoaded = false

	public func warmServiceByLoadingPlugins(atLocations pluginLocations: [URL]) {
		Self.pluginLoadLock.lock()
		defer { Self.pluginLoadLock.unlock() }
		guard !Self.pluginsLoaded else { return }
		Self.pluginsLoaded = true
		ICLPluginManager.shared().loadPlugins(atLocations: pluginLocations)
	}

	private static let defaultsLock = NSLock()
	nonisolated(unsafe) private static var defaultsRegistered = false

	public func warmService(byRegisteringDefaults defaults: [String: Any]) {
		Self.defaultsLock.lock()
		defer { Self.defaultsLock.unlock() }
		guard !Self.defaultsRegistered else { return }
		Self.defaultsRegistered = true
		UserDefaults.standard.register(defaults: defaults)
	}

	/* Unlike the warm-up methods above, this is called repeatedly -- once
	 when the app establishes the connection, then again every time one of
	 the preferences it covers changes -- since this service has no other
	 way to see the app's live preference values (see
	 TPCPreferences.setInlineMediaRemoteDefaults(_:) for why). */
	public func updateInlineMediaPreferences(_ preferences: [String: Any]) {
		TPCPreferences.setInlineMediaRemoteDefaults(preferences)
	}

	// MARK: - XPC Interface

	public func processURL(_ url: URL, withUniqueIdentifier uniqueIdentifier: String, atLineNumber lineNumber: String, index: UInt, inView viewIdentifier: String) {
		guard let payload = ICLPayloadMutable(url: url, withUniqueIdentifier: uniqueIdentifier, atLineNumber: lineNumber, index: index, inView: viewIdentifier) else { return }
		processPayload(payload)
	}

	public func processPayload(_ payload: ICLPayload) {
		guard let scheme = payload.url.scheme,
			  (scheme == "http" || scheme == "https") else { return }

		/* ObjC original always used mutableCopy since payloadIn was always nil
		   when the isKindOfClass check ran. Preserving the same behavior. */
		let payloadIn = payload.mutableCopy() as! ICLPayloadMutable

		let host = payloadIn.url.host ?? ""
		if processModules(for: host, with: payloadIn) { return }
		_ = processModules(for: "*", with: payloadIn)
	}

	@discardableResult
	private func processModules(for domain: String, with payloadIn: ICLPayloadMutable) -> Bool {
		guard let modules = Self.modules[domain] else { return false }
		for moduleClass in modules {
			if processPayload(payloadIn, using: moduleClass) { return true }
		}
		return false
	}

	private func processPayload(_ payloadIn: ICLPayloadMutable, using moduleClass: AnyClass) -> Bool {
		guard moduleClass is ICLInlineContentModule.Type else { return false }

		if !TPCPreferences.inlineMediaProviderEnabled(classPreferenceIdentifier(moduleClass)) { return false }
		if classContentNotSafeForWork(moduleClass) && TPCPreferences.inlineMediaLimitNaughtyContent() { return false }
		if classContentUntrusted(moduleClass) && TPCPreferences.inlineMediaLimitUnsafeContent() { return false }

		let url = payloadIn.url
		let actionBlock = classActionBlock(moduleClass, for: url)
		let action: Selector? = actionBlock == nil ? classAction(moduleClass, for: url) : nil

		guard actionBlock != nil || action != nil else { return false }

		guard let module = classInstantiate(moduleClass, payload: payloadIn, process: self) else { return false }
		addReference(for: module)

		if let actionBlock = actionBlock {
			actionBlock(module)
		} else if let action = action {
			_ = module.perform(action)
		}
		return true
	}

	// MARK: - Module State

	@objc func _finalizeModule(_ module: ICLInlineContentModule, withError inError: Error?) {
		let payload = module.payload.copy() as! ICLPayload
		removeReference(for: module)

		var finalError: Error? = inError

		if payload.html.isEmpty && payload.scriptResources.isEmpty {
			finalError = NSError(domain: ICLInlineContentErrorDomain, code: 1001, userInfo: [
				NSLocalizedDescriptionKey: "-[ICLPayload scriptResources] must contain at least one path if -[ICLPayload html] is empty"
			])
		} else if payload.html.isEmpty && (payload.entrypoint?.isEmpty ?? true) {
			finalError = NSError(domain: ICLInlineContentErrorDomain, code: 1002, userInfo: [
				NSLocalizedDescriptionKey: "-[ICLPayload html] and -[ICLPayload entrypoint] cannot both be empty"
			])
		}

		if let error = finalError {
			remoteObjectProxy?.processingPayload(payload, failedWithError: error as NSError)
		} else {
			remoteObjectProxy?.processingPayloadSucceeded(payload)
		}
	}

	@objc func _cancelModule(_ module: ICLInlineContentModule) {
		removeReference(for: module)
	}

	@objc func _deferModule(_ module: ICLInlineContentModule, asType type: ICLMediaType, performCheck: Bool) {
		switch type {
		case .image:
			let imageModule = ICMInlineImage(deferredModule: module)
			addReference(for: imageModule)
			imageModule.performAction(withImageCheck: performCheck)
		case .video:
			let videoModule = ICMInlineVideo(deferredModule: module)
			addReference(for: videoModule)
			videoModule.performAction(withVideoCheck: performCheck)
		case .videoGif:
			let gifModule = ICMInlineGifVideo(deferredModule: module)
			addReference(for: gifModule)
			gifModule.performAction(withVideoCheck: performCheck)
		default:
			Logging.defaultSubsystem?.error("Unexpected media type: \(type.rawValue)")
		}
	}

	// MARK: - Memory

	private func addReference(for module: ICLInlineContentModule) {
		Self.moduleReferencesLock.lock()
		defer { Self.moduleReferencesLock.unlock() }
		Self.moduleReferences[module.description] = module
	}

	private func removeReference(for module: ICLInlineContentModule) {
		Self.moduleReferencesLock.lock()
		defer { Self.moduleReferencesLock.unlock() }
		Self.moduleReferences.removeValue(forKey: module.description)
	}

	// MARK: - XPC Connection

	private var remoteObjectProxy: (any ICLInlineContentClientProtocol)? {
		return serviceConnection.remoteObjectProxy as? any ICLInlineContentClientProtocol
	}
}
