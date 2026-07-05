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

private let ICLInlineContentErrorDomain: NSErrorDomain = "ICLInlineContentErrorDomain"

@objc final class ICLProcessMain: NSObject, ICLInlineContentServerProtocol, @unchecked Sendable {
	private let serviceConnection: NSXPCConnection

	@available(*, unavailable) override init() { fatalError() }

	@objc init(xpcConnection connection: NSXPCConnection) {
		serviceConnection = connection
		super.init()
		Logging.defaultSubsystem = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
	}

	// MARK: - Module Registry

	private static let moduleReferences: NSCache<NSString, ICLInlineContentModule> = NSCache()

	/* Modules dict is built once on first access (thread-safe via static let).
	 warmServiceByLoadingPluginsAtLocations: must be called before URL processing. */
	private static let modules: [String: [AnyClass]] = {
		let pluginModules: [AnyClass] = ICLPluginManager.sharedPluginManager().modules
		let allModules: [AnyClass] = pluginModules + [ICMAssessedMedia.self]

		var result: [String: [AnyClass]] = [:]
		for moduleClass in allModules {
			guard let cls = moduleClass as? ICLInlineContentModule.Type else { continue }
			let domains = cls.domains ?? []
			if domains.isEmpty {
				result["*", default: []].append(cls)
			} else {
				for domain in domains {
					result[domain, default: []].append(cls)
				}
			}
		}
		return result
	}()

	// MARK: - Process Management

	private static let pluginLoadLock = NSLock()
	private static var pluginsLoaded = false

	func warmServiceByLoadingPluginsAtLocations(_ pluginLocations: [URL]) {
		Self.pluginLoadLock.lock()
		defer { Self.pluginLoadLock.unlock() }
		guard !Self.pluginsLoaded else { return }
		Self.pluginsLoaded = true
		ICLPluginManager.sharedPluginManager().loadPlugins(atLocations: pluginLocations)
	}

	private static let defaultsLock = NSLock()
	private static var defaultsRegistered = false

	func warmServiceByRegisteringDefaults(_ defaults: [String: Any]) {
		Self.defaultsLock.lock()
		defer { Self.defaultsLock.unlock() }
		guard !Self.defaultsRegistered else { return }
		Self.defaultsRegistered = true
		UserDefaults.standard.register(defaults: defaults)
	}

	// MARK: - XPC Interface

	func processURL(_ url: URL, withUniqueIdentifier uniqueIdentifier: String, atLineNumber lineNumber: String, index: Int, inView viewIdentifier: String) {
		guard let payload = ICLPayloadMutable(url: url, withUniqueIdentifier: uniqueIdentifier, atLineNumber: lineNumber, index: index, inView: viewIdentifier) else { return }
		processPayload(payload)
	}

	func processPayload(_ payload: ICLPayload) {
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
		guard let cls = moduleClass as? ICLInlineContentModule.Type else { return false }

		if !cls.contentImageOrVideo && TPCPreferences.inlineMediaLimitToBasics() { return false }
		if !cls.contentIsFile && TPCPreferences.inlineMediaLimitToBasics() && TPCPreferences.inlineMediaLimitBasicsToFiles() { return false }
		if cls.contentNotSafeForWork && TPCPreferences.inlineMediaLimitNaughtyContent() { return false }
		if cls.contentUntrusted && TPCPreferences.inlineMediaLimitUnsafeContent() { return false }

		let url = payloadIn.url
		let actionBlock = cls.actionBlock(for: url)
		let action: Selector? = actionBlock == nil ? cls.action(for: url) : nil

		guard actionBlock != nil || action != nil else { return false }

		let module = cls.init(payload: payloadIn, inProcess: self)
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
		Self.moduleReferences.setObject(module, forKey: module.description as NSString)
	}

	private func removeReference(for module: ICLInlineContentModule) {
		Self.moduleReferences.removeObject(forKey: module.description as NSString)
	}

	// MARK: - XPC Connection

	private var remoteObjectProxy: (any ICLInlineContentClientProtocol)? {
		return serviceConnection.remoteObjectProxy as? any ICLInlineContentClientProtocol
	}
}
