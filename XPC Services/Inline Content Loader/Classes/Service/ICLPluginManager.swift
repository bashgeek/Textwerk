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

/* TODO: Entitlements do not allow access to plugins outside app in Standard Release */

import Foundation

@objc protocol ICLPluginProtocol: NSObjectProtocol {
	static var modules: [AnyClass] { get }
}

@objc(ICLPluginManager)
final class ICLPluginManager: NSObject, @unchecked Sendable {

	// MARK: - Singleton

	// ObjC name is 'sharedPluginManager' — Swift strips "ICLPluginManager" prefix → "shared()"
	@objc(sharedPluginManager)
	static func shared() -> ICLPluginManager {
		struct Static {
			static let instance = ICLPluginManager()
		}
		return Static.instance
	}

	// MARK: - State

	private var pluginsLoaded: Bool = false
	private var loadedPlugins: [Bundle] = []
	private var loadedModules: [AnyClass]? = nil

	// MARK: - Bundled Plugins URL

	private var bundledPluginsURL: URL? {
		return Bundle.main.url(forResource: "Extensions", withExtension: nil)
	}

	// MARK: - Loading

	@objc(loadPluginsAtLocations:)
	func loadPlugins(atLocations pluginLocations: [URL]) {
		precondition(!pluginsLoaded, "Plugins already loaded")

		var locations = pluginLocations
		if let bundled = bundledPluginsURL {
			locations.append(bundled)
		}

		var allPlugins: [Bundle] = []

		for location in locations {
			if let plugins = loadPlugins(atPath: location.path) {
				allPlugins.append(contentsOf: plugins)
			}
		}

		loadedPlugins = allPlugins
		pluginsLoaded = true
		populateModules()
	}

	private func loadPlugins(atPath pluginsPath: String) -> [Bundle]? {
		var plugins: [Bundle] = []

		let listedFiles: [String]
		do {
			listedFiles = try FileManager.default.contentsOfDirectory(atPath: pluginsPath)
		} catch {
			Logging.defaultSubsystem?.error("Failed to list plugins: \(error.localizedDescription, privacy: .public)")
			return nil
		}

		for file in listedFiles {
			guard file.hasSuffix(".mediaPlugin") else { continue }

			let filePath = (pluginsPath as NSString).appendingPathComponent(file)
			if let bundle = loadPlugin(atPath: filePath) {
				plugins.append(bundle)
			}
		}

		return plugins
	}

	private func loadPlugin(atPath pluginPath: String) -> Bundle? {
		guard let bundle = Bundle(path: pluginPath) else {
			return nil
		}

		guard let principalClass = bundle.principalClass else {
			Logging.defaultSubsystem?.error("Failed to load bundle '\(bundle.bundleURL.standardized.path, privacy: .public)' because of NULL principal class")
			return nil
		}

		guard principalClass.conforms(to: ICLPluginProtocol.self) else {
			Logging.defaultSubsystem?.error("Failed to load bundle '\(bundle.bundleURL.standardized.path, privacy: .public)' because it does not conform to the ICLPluginProtocol protocol")
			return nil
		}

		return bundle
	}

	private func populateModules() {
		guard !loadedPlugins.isEmpty else {
			Logging.defaultSubsystem?.info("No plugins to load modules from")
			return
		}

		var allModules: [AnyClass] = []

		for plugin in loadedPlugins {
			let pluginModules = populateModules(forPlugin: plugin)
			allModules.append(contentsOf: pluginModules)
		}

		loadedModules = allModules
	}

	private func populateModules(forPlugin plugin: Bundle) -> [AnyClass] {
		// We have already proven in loadPlugin(atPath:) that the plugin
		// conforms to ICLPluginProtocol, so no additional validation needed.
		guard let principalClass = plugin.principalClass as? ICLPluginProtocol.Type else {
			return []
		}
		return principalClass.modules
	}

	// MARK: - Public API

	@objc var modules: [AnyClass] {
		return loadedModules ?? []
	}
}
