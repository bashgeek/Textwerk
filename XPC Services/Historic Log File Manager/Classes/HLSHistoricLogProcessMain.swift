/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
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

import CoreData
import Foundation
import os.log

private enum UniqueIdentifierFetchType {
	case before
	case after
}

@objc(HLSHistoricLogProcessMain)
final class HLSHistoricLogProcessMain: NSObject, HLSHistoricLogServerProtocol, @unchecked Sendable {
	private let serviceConnection: NSXPCConnection
	private var isPerformingSave = false
	private var managedObjectContext: NSManagedObjectContext?
	private var managedObjectModel: NSManagedObjectModel?
	private var persistentStoreCoordinator: NSPersistentStoreCoordinator?
	private var databasePath = ""
	private var databaseDirectory = ""
	private var contextObjects: [String: HLSHistoricLogViewContext] = [:]
	private let contextObjectsLock = NSLock()
	private var maximumLineCount: UInt = 100
	private var saveTimer: DispatchSourceTimer?

	/* The host app calls -openDatabase asynchronously and, without waiting
	 for its completion block, may immediately follow up with other calls
	 (fetch, save, write, etc.) on this same connection. XPC does not
	 guarantee those calls are processed strictly after -openDatabase
	 returns, so callers that touch the Core Data stack wait on this group
	 first to avoid racing the database's setup. */
	private let databaseOpenGroup = DispatchGroup()
	private var hasLeftDatabaseOpenGroup = false
	private let databaseOpenGroupLock = NSLock()

	init(connection: NSXPCConnection) {
		serviceConnection = connection
		super.init()
		Logging.defaultSubsystem = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
		databaseOpenGroup.enter()
	}

	// MARK: - Database path management

	private func resetDatabaseFilename() {
		let filename = "logControllerHistoricLog_\(UUID().uuidString).sqlite"
		UserDefaults.standard.set(filename, forKey: "TVCLogControllerHistoricLogFileSavePath_v3")
	}

	private func databaseSaveFilename() -> String {
		if let filename = UserDefaults.standard.string(forKey: "TVCLogControllerHistoricLogFileSavePath_v3") {
			return filename
		}
		resetDatabaseFilename()
		return UserDefaults.standard.string(forKey: "TVCLogControllerHistoricLogFileSavePath_v3")!
	}

	private func setDatabasePath() {
		databasePath = (databaseDirectory as NSString).appendingPathComponent(databaseSaveFilename())
	}

	private func setDatabasePath(inDirectory directory: String) {
		/* The directory suggested by the host app may live outside of this
		 process's sandbox container (e.g. a shared group container this
		 process has no entitlement to write to). Always store the database
		 inside this process's own container instead, which is guaranteed
		 to be writable regardless of what the host app passes in. */
		let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
		let sandboxSafeDirectory = cachesURL?.path ?? directory

		try? FileManager.default.createDirectory(atPath: sandboxSafeDirectory, withIntermediateDirectories: true)

		databaseDirectory = sandboxSafeDirectory
		setDatabasePath()
	}

	private func resetDatabasePath() {
		resetDatabaseFilename()
		setDatabasePath()
	}

	// MARK: - HLSHistoricLogServerProtocol

	func openDatabase(inDirectory directory: String, withCompletionBlock completionBlock: (@Sendable (Bool) -> Void)?) {
		setDatabasePath(inDirectory: directory)

		Logging.defaultSubsystem?.info("Opening database at path: \((self.databasePath as NSString).standardizingPath)")

		let success = createBaseModel()

		signalDatabaseOpenGroupIfNeeded()

		completionBlock?(success)

		guard success else { return }

		rescheduleSave()
	}

	private func signalDatabaseOpenGroupIfNeeded() {
		databaseOpenGroupLock.lock()
		defer { databaseOpenGroupLock.unlock() }

		guard hasLeftDatabaseOpenGroup == false else { return }
		hasLeftDatabaseOpenGroup = true
		databaseOpenGroup.leave()
	}

	func openDatabase(inDirectory directory: String) async -> Bool {
		await withCheckedContinuation { continuation in
			openDatabase(inDirectory: directory, withCompletionBlock: { result in continuation.resume(returning: result) })
		}
	}

	func setMaximumLineCount(_ count: UInt) {
		precondition(count > 0)
		maximumLineCount = count
	}

	func forgetView(_ viewId: String) {
		Logging.defaultSubsystem?.debug("Forgetting view: \(viewId, privacy: .public)")

		let viewContext = context(forView: viewId)

		viewContext.performAndWait {
			cancelResize(in: viewContext)

			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				fetchLimit: 0, limitToDate: nil, resultType: .managedObjectResultType)

			_ = self.deleteData(in: viewContext, fetchRequest: fetchRequest, performOnQueue: false)

			viewContext.reset()
		}

		guard let parent = managedObjectContext else { return }

		parent.performAndWait {
			self.contextObjects.removeValue(forKey: viewId)
		}
	}

	func resetData(forView viewId: String) {
		Logging.defaultSubsystem?.debug("Resetting the contents of view: \(viewId, privacy: .public)")

		let viewContext = context(forView: viewId)

		viewContext.performAndWait {
			cancelResize(in: viewContext)

			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				fetchLimit: 0, limitToDate: nil, resultType: .managedObjectResultType)

			_ = self.deleteData(in: viewContext, fetchRequest: fetchRequest, performOnQueue: false)

			viewContext.reset()
		}
	}

	func writeLogLine(_ logLine: TVCLogLineXPC) {
		let viewContext = context(forView: logLine.viewIdentifier)

		viewContext.performAndWait {
			guard let entity = NSEntityDescription.entity(forEntityName: "LogLine2", in: viewContext) else { return }

			let newEntry = NSManagedObject(entity: entity, insertInto: viewContext)

			let newestIdentifier = self.incrementNewestIdentifier(in: viewContext)

			newEntry.setValue(NSNumber(value: newestIdentifier), forKey: "entryIdentifier")
			newEntry.setValue(NSNumber(value: Date().timeIntervalSince1970), forKey: "entryCreationDate")
			newEntry.setValue(logLine.viewIdentifier, forKey: "logLineViewIdentifier")
			newEntry.setValue(logLine.data, forKey: "logLineData")
			newEntry.setValue(logLine.uniqueIdentifier, forKey: "logLineUniqueIdentifier")
			newEntry.setValue(NSNumber(value: logLine.sessionIdentifier), forKey: "sessionIdentifier")

			self.scheduleResize(in: viewContext)
		}
	}

	func saveData(completionBlock: (@Sendable () -> Void)?) {
		databaseOpenGroup.wait()

		guard !isPerformingSave else { return }
		isPerformingSave = true

		guard let context = managedObjectContext else {
			isPerformingSave = false
			return
		}

		context.perform {
			Logging.defaultSubsystem?.debug("Performing save")

			self.rescheduleSave()

			for (_, viewContext) in self.contextObjects {
				context.performAndWait {
					self.quickSave(viewContext)
				}
			}

			self.quickSave(context)

			self.isPerformingSave = false

			completionBlock?()
		}
	}

	func saveData() async {
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			saveData(completionBlock: { continuation.resume() })
		}
	}

	func fetchEntries(forView viewId: String, ascending: Bool, fetchLimit: UInt,
	                  limitTo limitToDate: Date?, withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		let viewContext = context(forView: viewId)

		let entries: [TVCLogLineXPC] = viewContext.performAndWait {
			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				ascending: ascending, fetchLimit: fetchLimit,
				limitToDate: limitToDate, resultType: .managedObjectResultType)

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject] else {
				return []
			}

			Logging.defaultSubsystem?.debug("\(fetchedObjects.count, privacy: .public) results fetched for view \(viewId, privacy: .public)")

			return self.xpcObjects(from: fetchedObjects)
		}
		completionBlock(entries)
	}

	func fetchEntries(forView viewId: String, withUniqueIdentifier uniqueId: String,
	                  beforeFetchLimit fetchLimitBefore: UInt, afterFetchLimit fetchLimitAfter: UInt,
	                  limitTo limitToDate: Date?, withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		let viewContext = context(forView: viewId)

		let entries: [TVCLogLineXPC] = viewContext.performAndWait {
			let firstEntryId = self.identifier(in: viewContext, forUniqueIdentifier: uniqueId, performOnQueue: false)

			guard firstEntryId != UInt.max else { return [] }

			let lowestEntryId = Int(firstEntryId) - Int(fetchLimitBefore)
			let highestEntryId = Int(firstEntryId) + Int(fetchLimitAfter)

			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				ascending: true, fetchLimit: 0,
				lowestEntryIdentifier: lowestEntryId,
				highestEntryIdentifier: highestEntryId,
				limitToDate: limitToDate, resultType: .managedObjectResultType)

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject] else { return [] }

			Logging.defaultSubsystem?.debug("\(fetchedObjects.count, privacy: .public) results fetched for view \(viewId, privacy: .public)")

			return self.xpcObjects(from: fetchedObjects)
		}
		completionBlock(entries)
	}

	func fetchEntries(forView viewId: String, beforeUniqueIdentifier uniqueId: String,
	                  fetchLimit: UInt, limitTo limitToDate: Date?,
	                  withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		fetchEntries(forView: viewId, withUniqueIdentifier: uniqueId,
			fetchType: .before, fetchLimit: fetchLimit,
			limitToDate: limitToDate, withCompletionBlock: completionBlock)
	}

	func fetchEntries(forView viewId: String, afterUniqueIdentifier uniqueId: String,
	                  fetchLimit: UInt, limitTo limitToDate: Date?,
	                  withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		fetchEntries(forView: viewId, withUniqueIdentifier: uniqueId,
			fetchType: .after, fetchLimit: fetchLimit,
			limitToDate: limitToDate, withCompletionBlock: completionBlock)
	}

	func fetchEntries(forView viewId: String, afterUniqueIdentifier uniqueIdAfter: String,
	                  beforeUniqueIdentifier uniqueIdBefore: String, fetchLimit: UInt,
	                  withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		let viewContext = context(forView: viewId)

		let entries: [TVCLogLineXPC] = viewContext.performAndWait {
			let firstEntryId = self.identifier(in: viewContext, forUniqueIdentifier: uniqueIdAfter, performOnQueue: false)
			let secondEntryId = self.identifier(in: viewContext, forUniqueIdentifier: uniqueIdBefore, performOnQueue: false)

			guard firstEntryId != UInt.max, secondEntryId != UInt.max else { return [] }

			let lowestEntryId = Int(firstEntryId) + 1
			let highestEntryId = Int(secondEntryId) - 1

			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				ascending: true, fetchLimit: fetchLimit,
				lowestEntryIdentifier: lowestEntryId,
				highestEntryIdentifier: highestEntryId,
				limitToDate: nil, resultType: .managedObjectResultType)

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject] else { return [] }

			Logging.defaultSubsystem?.debug("\(fetchedObjects.count, privacy: .public) results fetched for view \(viewId, privacy: .public)")

			return self.xpcObjects(from: fetchedObjects)
		}
		completionBlock(entries)
	}

	// MARK: - Private fetch helpers

	private func fetchEntries(forView viewId: String, withUniqueIdentifier uniqueId: String,
	                          fetchType: UniqueIdentifierFetchType, fetchLimit: UInt,
	                          limitToDate: Date?, withCompletionBlock completionBlock: ([TVCLogLineXPC]) -> Void) {
		precondition(fetchLimit > 0)

		let viewContext = context(forView: viewId)

		let entries: [TVCLogLineXPC] = viewContext.performAndWait {
			let firstEntryId = self.identifier(in: viewContext, forUniqueIdentifier: uniqueId, performOnQueue: false)

			guard firstEntryId != UInt.max else { return [] }

			let lowestEntryId: Int
			let highestEntryId: Int

			switch fetchType {
			case .before:
				lowestEntryId = Int(firstEntryId) - Int(fetchLimit)
				highestEntryId = Int(firstEntryId) - 1
			case .after:
				lowestEntryId = Int(firstEntryId) + 1
				highestEntryId = Int(firstEntryId) + Int(fetchLimit)
			}

			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				ascending: true, fetchLimit: fetchLimit,
				lowestEntryIdentifier: lowestEntryId,
				highestEntryIdentifier: highestEntryId,
				limitToDate: limitToDate, resultType: .managedObjectResultType)

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject] else { return [] }

			Logging.defaultSubsystem?.debug("\(fetchedObjects.count, privacy: .public) results fetched for view \(viewId, privacy: .public)")

			return self.xpcObjects(from: fetchedObjects)
		}
		completionBlock(entries)
	}

	private func fetchRequest(forView viewId: String, fetchLimit: UInt,
	                          limitToDate: Date?, resultType: NSFetchRequestResultType) -> NSFetchRequest<NSFetchRequestResult> {
		return fetchRequest(forView: viewId, ascending: true, fetchLimit: fetchLimit,
			lowestEntryIdentifier: 0, highestEntryIdentifier: Int.max,
			limitToDate: limitToDate, resultType: resultType)
	}

	private func fetchRequest(forView viewId: String, ascending: Bool, fetchLimit: UInt,
	                          limitToDate: Date?, resultType: NSFetchRequestResultType) -> NSFetchRequest<NSFetchRequestResult> {
		return fetchRequest(forView: viewId, ascending: ascending, fetchLimit: fetchLimit,
			lowestEntryIdentifier: 0, highestEntryIdentifier: Int.max,
			limitToDate: limitToDate, resultType: resultType)
	}

	private func fetchRequest(forView viewId: String, ascending: Bool, fetchLimit: UInt,
	                          lowestEntryIdentifier: Int, highestEntryIdentifier: Int,
	                          limitToDate: Date?, resultType: NSFetchRequestResultType) -> NSFetchRequest<NSFetchRequestResult> {
		guard let model = managedObjectModel else {
			fatalError("Managed object model not initialized")
		}

		let limitDate = limitToDate ?? Date.distantFuture

		let substitutionVariables: [String: Any] = [
			"view_id": viewId,
			"entry_id_lowest": NSNumber(value: lowestEntryIdentifier),
			"entry_id_highest": NSNumber(value: highestEntryIdentifier),
			"creation_date": NSNumber(value: limitDate.timeIntervalSince1970)
		]

		guard let fetchRequest = model.fetchRequestFromTemplate(withName: "GenericConditional",
		                                                        substitutionVariables: substitutionVariables) else {
			fatalError("Fetch request template 'GenericConditional' not found")
		}

		if fetchLimit > 0 {
			fetchRequest.fetchLimit = Int(fetchLimit)
		}

		fetchRequest.includesPendingChanges = true
		fetchRequest.includesPropertyValues = true
		fetchRequest.returnsObjectsAsFaults = false
		fetchRequest.resultType = resultType
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "entryCreationDate", ascending: ascending)]

		return fetchRequest
	}

	private func xpcObjects(from managedObjects: [NSManagedObject]) -> [TVCLogLineXPC] {
		return managedObjects.map { TVCLogLineXPC(managedObject: $0) }
	}

	// MARK: - Core Data stack

	private func createBaseModel() -> Bool {
		return createBaseModel(recursionDepth: 0)
	}

	private func createBaseModel(recursionDepth: Int) -> Bool {
		guard let modelURL = Bundle.main.url(forResource: "HistoricLogFileStorageModel", withExtension: "momd"),
		      let model = NSManagedObjectModel(contentsOf: modelURL) else {
			return false
		}

		let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

		let pragmaOptions: [String: Any] = [
			"synchronous": "NORMAL",
			"journal_mode": "WAL"
		]

		let storeOptions: [String: Any] = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
			NSSQLitePragmasOption: pragmaOptions
		]

		let storeURL = URL(fileURLWithPath: databasePath)

		do {
			try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
				configurationName: nil, at: storeURL, options: storeOptions)
		} catch {
			Logging.defaultSubsystem?.error("Error Creating Persistent Store: \(error.localizedDescription, privacy: .public)")

			if recursionDepth == 0 {
				Logging.defaultSubsystem?.info("Attempting to create a new persistent store")
				resetDatabasePath()
				return createBaseModel(recursionDepth: 1)
			}

			return false
		}

		let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		context.persistentStoreCoordinator = coordinator
		context.retainsRegisteredObjects = true
		context.undoManager = nil

		managedObjectContext = context
		managedObjectModel = model
		persistentStoreCoordinator = coordinator

		return true
	}

	// MARK: - Save timer

	private func rescheduleSave() {
		saveTimer?.cancel()

		let interval: TimeInterval = 60 * 2 // 2 minutes

		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + interval, repeating: interval)
		timer.setEventHandler { [weak self] in
			self?.saveData(completionBlock: nil)
		}
		timer.resume()
		saveTimer = timer
	}

	private func quickSave(_ context: NSManagedObjectContext) {
		guard context.hasChanges else { return }

		do {
			try context.save()
		} catch {
			Logging.defaultSubsystem?.error("Failed to perform save: \(error.localizedDescription, privacy: .public)")
		}

		context.reset()
	}

	// MARK: - Resize logic

	private func cancelResize(in viewContext: HLSHistoricLogViewContext) {
		viewContext.hls_resizeTimer?.cancel()
		viewContext.hls_resizeTimer = nil
	}

	private func scheduleResize(in viewContext: HLSHistoricLogViewContext) {
		guard viewContext.hls_resizeTimer == nil else { return }
		guard viewContext.hls_totalLineCount >= maximumLineCount else { return }

		let viewId = viewContext.hls_viewId
		let interval = TimeInterval(UInt32.random(in: 0..<(60 * 30)))

		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + interval)
		timer.setEventHandler { [weak self] in
			self?.resizeView(viewId)
		}
		timer.resume()
		viewContext.hls_resizeTimer = timer

		Logging.defaultSubsystem?.debug("Scheduled to resize \(viewId, privacy: .public) in \(interval, privacy: .public) seconds")
	}

	private func resizeView(_ viewId: String) {
		let viewContext = context(forView: viewId)

		viewContext.perform {
			self.resizeViewContext(viewContext)
		}
	}

	private func resizeViewContext(_ viewContext: HLSHistoricLogViewContext) {
		Logging.defaultSubsystem?.debug("Resizing view \(viewContext.hls_viewId, privacy: .public)")

		viewContext.hls_resizeTimer = nil

		guard let model = managedObjectModel else { return }

		let lowestIdentifier = Int(viewContext.hls_newestIdentifier) - Int(maximumLineCount)

		let substitutionVariables: [String: Any] = [
			"view_id": viewContext.hls_viewId,
			"entry_id_lowest": NSNumber(value: lowestIdentifier)
		]

		guard let fetchRequest = model.fetchRequestFromTemplate(withName: "Truncate",
		                                                        substitutionVariables: substitutionVariables) else {
			return
		}

		fetchRequest.includesPendingChanges = true
		fetchRequest.includesPropertyValues = true
		fetchRequest.returnsObjectsAsFaults = false

		let rowsDeleted = deleteData(in: viewContext, fetchRequest: fetchRequest, performOnQueue: false)

		viewContext.hls_totalLineCount -= rowsDeleted
	}

	// MARK: - Delete logic

	private func deleteData(in viewContext: HLSHistoricLogViewContext, fetchRequest: NSFetchRequest<NSFetchRequestResult>,
	                        performOnQueue: Bool) -> UInt {
		var rowsDeleted: UInt = 0

		let block = {
			rowsDeleted = self.deleteDataByEnumeration(fetchRequest: fetchRequest, viewContext: viewContext)
		}

		if performOnQueue {
			viewContext.performAndWait(block)
		} else {
			block()
		}

		Logging.defaultSubsystem?.debug("Deleted \(rowsDeleted, privacy: .public) rows in \(viewContext.hls_viewId, privacy: .public)")

		return rowsDeleted
	}

	private func deleteDataByEnumeration(fetchRequest: NSFetchRequest<NSFetchRequestResult>,
	                                     viewContext: HLSHistoricLogViewContext) -> UInt {
		guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject],
		      !fetchedObjects.isEmpty else {
			return 0
		}

		var uniqueIdentifiers: [String] = []

		for object in fetchedObjects {
			if let uniqueId = object.value(forKey: "logLineUniqueIdentifier") as? String {
				uniqueIdentifiers.append(uniqueId)
			}
			viewContext.delete(object)
		}

		quickSave(viewContext)

		notifyClientOfDeletedIdentifiers(uniqueIdentifiers, in: viewContext)

		return UInt(fetchedObjects.count)
	}

	private func notifyClientOfDeletedIdentifiers(_ identifiers: [String],
	                                              in viewContext: HLSHistoricLogViewContext) {
		remoteObjectProxy?.willDeleteUniqueIdentifiers(identifiers, inView: viewContext.hls_viewId)
	}

	// MARK: - Context management

	private func context(forView viewId: String) -> HLSHistoricLogViewContext {
		databaseOpenGroup.wait()

		contextObjectsLock.lock()
		defer { contextObjectsLock.unlock() }

		if let existing = contextObjects[viewId] {
			return existing
		}

		guard let parentContext = managedObjectContext else {
			fatalError("Database not opened before accessing view context")
		}

		let viewContext = HLSHistoricLogViewContext(concurrencyType: .privateQueueConcurrencyType)
		viewContext.parent = parentContext
		viewContext.retainsRegisteredObjects = true
		viewContext.undoManager = nil
		viewContext.hls_viewId = viewId
		viewContext.hls_totalLineCount = lineCount(in: viewContext, performOnQueue: true)
		viewContext.hls_newestIdentifier = newestIdentifier(in: viewContext, performOnQueue: true)

		Logging.defaultSubsystem?.debug("Context created for \(viewContext.hls_viewId, privacy: .public) - Line count: \(viewContext.hls_totalLineCount, privacy: .public), Newest identifier: \(viewContext.hls_newestIdentifier, privacy: .public)")

		parentContext.performAndWait {
			self.contextObjects[viewId] = viewContext
		}

		return viewContext
	}

	private func incrementNewestIdentifier(in viewContext: HLSHistoricLogViewContext) -> UInt {
		viewContext.hls_totalLineCount += 1
		viewContext.hls_newestIdentifier += 1
		return viewContext.hls_newestIdentifier
	}

	private func newestIdentifier(in viewContext: HLSHistoricLogViewContext, performOnQueue: Bool) -> UInt {
		var result: UInt = 0

		let block = {
			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				ascending: false, fetchLimit: 1,
				limitToDate: nil, resultType: .managedObjectResultType)

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject],
			      let first = fetchedObjects.first else { return }

			result = (first.value(forKey: "entryIdentifier") as? NSNumber)?.uintValue ?? 0
		}

		if performOnQueue {
			viewContext.performAndWait(block)
		} else {
			block()
		}

		return result
	}

	private func lineCount(in viewContext: HLSHistoricLogViewContext, performOnQueue: Bool) -> UInt {
		var result: UInt = 0

		let block = {
			let fetchRequest = self.fetchRequest(forView: viewContext.hls_viewId,
				fetchLimit: 0, limitToDate: nil, resultType: .countResultType)

			let count = (try? viewContext.count(for: fetchRequest)) ?? 0

			result = count == NSNotFound ? 0 : UInt(count)
		}

		if performOnQueue {
			viewContext.performAndWait(block)
		} else {
			block()
		}

		return result
	}

	private func identifier(in viewContext: HLSHistoricLogViewContext,
	                        forUniqueIdentifier uniqueIdentifier: String,
	                        performOnQueue: Bool) -> UInt {
		guard let model = managedObjectModel else { return UInt.max }

		var result: UInt = UInt.max

		let block = {
			let substitutionVariables: [String: Any] = [
				"view_id": viewContext.hls_viewId,
				"unique_id": uniqueIdentifier
			]

			guard let fetchRequest = model.fetchRequestFromTemplate(
				withName: "UniqueIdToEntryId",
				substitutionVariables: substitutionVariables) else { return }

			fetchRequest.includesPendingChanges = true
			fetchRequest.includesPropertyValues = true
			fetchRequest.returnsObjectsAsFaults = false

			guard let fetchedObjects = try? viewContext.fetch(fetchRequest) as? [NSManagedObject],
			      let first = fetchedObjects.first else { return }

			result = (first.value(forKey: "entryIdentifier") as? NSNumber)?.uintValue ?? UInt.max
		}

		if performOnQueue {
			viewContext.performAndWait(block)
		} else {
			block()
		}

		return result
	}

	// MARK: - XPC connection

	private var remoteObjectProxy: (any HLSHistoricLogClientProtocol)? {
		return serviceConnection.remoteObjectProxy as? any HLSHistoricLogClientProtocol
	}
}
