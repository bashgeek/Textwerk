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

final class RCMProcessMain: NSObject, RCMConnectionManagerServerProtocol {
	private var connection: Connection?
	private let serviceConnection: NSXPCConnection

	@available(*, unavailable)
	override init() { fatalError() }

	init(xpcConnection: NSXPCConnection) {
		serviceConnection = xpcConnection
		super.init()
		Logging.defaultSubsystem = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "General")
	}

	func open(with config: IRCConnectionConfig) {
		precondition(connection == nil, "Method invoked with connection already open")
		let conn = Connection(with: config, on: serviceConnection)
		conn.open()
		connection = conn
	}

	func close() {
		precondition(connection != nil, "Method invoked without performing setup first")
		connection?.close()
	}

	func sendData(_ data: Data) {
		sendData(data, bypassQueue: false)
	}

	func sendData(_ data: Data, bypassQueue: Bool) {
		precondition(connection != nil, "Method invoked without performing setup first")
		connection?.send(data, bypassQueue: bypassQueue)
	}

	func exportSecureConnectionInformation(_ completionBlock: RCMSecureConnectionInformationCompletionBlock) {
		precondition(connection != nil, "Method invoked without performing setup first")
		try? connection?.exportSecureConnectionInformation(to: completionBlock)
	}

	func enforceFloodControl() {
		precondition(connection != nil, "Method invoked without performing setup first")
		connection?.enforceFloodControl()
	}

	func clearSendQueue() {
		precondition(connection != nil, "Method invoked without performing setup first")
		connection?.clearSendQueue()
	}

	func enableAppNap() {
		UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": false])
	}

	func disableAppNap() {
		UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": true])
	}

	func enableSuddenTermination() {
		ProcessInfo.processInfo.enableSuddenTermination()
	}

	func disableSuddenTermination() {
		ProcessInfo.processInfo.disableSuddenTermination()
	}
}
