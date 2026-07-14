/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

#import "BuildConfig.h"

#import <Network/Network.h>

#import "NSObjectHelperPrivate.h"
#import "TDCAlert.h"
#import "TLOLocalization.h"
#import "TLOSpeechSynthesizerPrivate.h"
#import "THOPluginManagerPrivate.h"
#import "TVCLogControllerHistoricLogFilePrivate.h"
#import "TVCLogControllerInlineMediaServicePrivate.h"
#import "TVCLogControllerOperationQueuePrivate.h"
#import "TVCMainWindowPrivate.h"
#import "IRCChannelPrivate.h"
#import "IRCChannelMemberListPrivate.h"
#import "IRCCommandIndexPrivate.h"
#import "IRCExtrasPrivate.h"
#import "IRCWorldPrivate.h"
#import "TPCApplicationInfoPrivate.h"
#import "TPCPreferencesLocalPrivate.h"
#import "TPCPreferencesUserDefaults.h"
#import "TPCResourceManagerPrivate.h"
#import "TPCSandboxMigrationPrivate.h"
#import "TPCThemeControllerPrivate.h"
#import "TXMenuControllerPrivate.h"
#import "TXWindowControllerPrivate.h"
#import "TXMasterControllerPrivate.h"
#import "IRCClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface TXMasterController ()
@property (nonatomic, strong, readwrite) IRCWorld *world;
@property (nonatomic, assign, readwrite) BOOL debugModeIsOn;
@property (nonatomic, assign, readwrite) BOOL ghostModeIsOn;
@property (nonatomic, assign, readwrite) BOOL applicationIsActive;
@property (nonatomic, assign, readwrite) BOOL applicationIsLaunched;
@property (nonatomic, assign, readwrite) BOOL applicationIsTerminating;
@property (nonatomic, assign, readwrite) BOOL applicationIsChangingActiveState;
@property (readonly) BOOL isSafeToPerformApplicationTermination;
@property (nonatomic, assign, readwrite) BOOL terminateHistoricLogSaveFinished;
@property (nonatomic, strong, readwrite) IBOutlet TVCMainWindow *mainWindow;
@property (nonatomic, weak, readwrite) IBOutlet TXMenuController *menuController;
@property (nonatomic, assign) NSUInteger applicationLaunchRemainder;
@property (nonatomic, strong) nw_path_monitor_t pathMonitor;

@end

@implementation TXMasterController

#pragma mark -
#pragma mark Initialization

- (instancetype)init
{
	if ((self = [super init])) {
		[NSObject setGlobalMasterControllerClassReference:self];

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	LogToConsoleSetDefaultSubsystemToMainBundle(@"General");

	NSUInteger keyboardKeys = ([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask);

	if ((keyboardKeys & NSEventModifierFlagControl) == NSEventModifierFlagControl) {
		self.debugModeIsOn = YES;

		LogToConsoleInfo("Launching in debug mode");
	}

#if defined(DEBUG)
	self.ghostModeIsOn = YES; // Do not use auto connect during debug
#else
	if ((keyboardKeys & NSEventModifierFlagShift) == NSEventModifierFlagShift) {
		self.ghostModeIsOn = YES;

		LogToConsoleInfo("Launching without auto connecting to the configured servers");
	}
#endif
}

- (void)awakeFromNib
{
	static BOOL _awakeFromNibCalled = NO;

	if (_awakeFromNibCalled == NO) {
		_awakeFromNibCalled = YES;

		[self _awakeFromNib];
	}
}

- (void)_awakeFromNib
{
	/* Migrate files and preferences */
	[TPCSandboxMigration migrateResources];

	/* Offer one-time import from previous Textual if settings are present */
	[TPCSandboxMigration offerLegacyImportIfNeeded];

	/* Initialize preferences */
	[TPCPreferences initPreferences];

	/* Call shared instance to warm it */
	[TXSharedApplication sharedAppearance];

	/* We wait until -awakeFromNib to wake the window so that the menu
	 controller created by the main nib has time to load. */
	[RZMainBundle() loadNibNamed:@"TVCMainWindow" owner:self topLevelObjects:nil];
}

- (void)applicationWakeStepOne
{
	self.world = [IRCWorld new];
}

- (void)applicationWakeStepTwo
{
	[IRCCommandIndex populateCommandIndex];

	[self prepareNetworkReachabilityNotifier];

	[RZWorkspaceNotificationCenter() addObserver:self selector:@selector(computerDidWakeUp:) name:NSWorkspaceDidWakeNotification object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self selector:@selector(computerWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self selector:@selector(computerWillPowerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self selector:@selector(computerScreenDidWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
	[RZWorkspaceNotificationCenter() addObserver:self selector:@selector(computerScreenWillSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];

	[RZNotificationCenter() addObserver:self selector:@selector(pluginsFinishedLoading:) name:THOPluginManagerFinishedLoadingPluginsNotification object:nil];

	[RZAppleEventManager() setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];

	[NSColorPanel setPickerMask:(NSColorPanelRGBModeMask | NSColorPanelGrayModeMask | NSColorPanelColorListModeMask | NSColorPanelWheelModeMask | NSColorPanelCrayonModeMask)];

	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES];

	XRPerformBlockAsynchronouslyOnGlobalQueueWithPriority(^{
		[TPCResourceManager copyResourcesToApplicationSupportFolder];
	}, DISPATCH_QUEUE_PRIORITY_BACKGROUND);

	/* We want to guarantee some specific things happen before the
	 app is considered "launched" and ready to use. This property
	 counts down once each task completes and once it reaches 0,
	 then the app is considered launched. */
	/* 1 is default value because we want plugins to be loaded
	 before we are finished launching. */
	[self addObserver:self forKeyPath:@"applicationLaunchRemainder" options:NSKeyValueObservingOptionNew context:NULL];

	self.applicationLaunchRemainder = 1;

	[self prepareThirdPartyServices];

	/* Load plugins last so that -applicationDidFinishLaunching is posted
	 only once they have loaded and everything else has been setup. */
	[sharedPluginManager() loadPlugins];
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSString *, id> *)change context:(nullable void *)context
{
	if ([keyPath isEqualToString:@"applicationLaunchRemainder"]) {
		if (self.applicationLaunchRemainder == 0) {
			[self applicationDidFinishLaunching];
		}
	}
}

- (void)pluginsFinishedLoading:(NSNotification *)notification
{
	self.applicationLaunchRemainder -= 1;
}

#pragma mark -
#pragma mark Services

- (void)prepareThirdPartyServiceSparkleFramework
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self checkForUpdatesFromGitHub:NO];
	});
}

- (void)checkForUpdatesFromGitHub:(BOOL)userInitiated
{
	NSURL *apiURL = [NSURL URLWithString:@"https://api.github.com/repos/bashgeek/Textwerk/releases/latest"];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:apiURL
	                                                       cachePolicy:NSURLRequestReloadIgnoringCacheData
	                                                   timeoutInterval:30.0];

	[request setValue:@"Textwerk IRC" forHTTPHeaderField:@"User-Agent"];

	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
	                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (error || data == nil) {
				if (userInitiated) {
					NSAlert *alert = [[NSAlert alloc] init];
					alert.messageText = @"Update Check Failed";
					alert.informativeText = error.localizedDescription ?: @"Could not contact GitHub.";
					[alert addButtonWithTitle:@"OK"];
					[alert runModal];
				}
				return;
			}

			NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			NSString *latestTag = json[@"tag_name"];

			if (!latestTag) {
				if (userInitiated) {
					NSAlert *alert = [[NSAlert alloc] init];
					alert.messageText = @"Update Check Failed";
					alert.informativeText = @"Could not parse release information from GitHub.";
					[alert addButtonWithTitle:@"OK"];
					[alert runModal];
				}
				return;
			}

			NSString *latestVersion = [latestTag hasPrefix:@"v"] ? [latestTag substringFromIndex:1] : latestTag;
			NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

			if ([currentVersion compare:latestVersion options:NSNumericSearch] == NSOrderedAscending) {
				NSAlert *alert = [[NSAlert alloc] init];
				alert.messageText = @"Update Available";
				alert.informativeText = [NSString stringWithFormat:@"Textwerk %@ is available. You have %@.", latestTag, currentVersion];
				[alert addButtonWithTitle:@"View on GitHub"];
				[alert addButtonWithTitle:@"Later"];

				if ([alert runModal] == NSAlertFirstButtonReturn) {
					NSString *urlString = json[@"html_url"];
					if (urlString) {
						[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
					}
				}
			} else if (userInitiated) {
				NSAlert *alert = [[NSAlert alloc] init];
				alert.messageText = @"You're Up to Date";
				alert.informativeText = [NSString stringWithFormat:@"Textwerk %@ is the latest version.", currentVersion];
				[alert addButtonWithTitle:@"OK"];
				[alert runModal];
			}
		});
	}];

	[task resume];
}

- (void)prepareThirdPartyServices
{
	[self prepareThirdPartyServiceSparkleFramework];
}

- (void)prepareNetworkReachabilityNotifier
{
	nw_path_monitor_t monitor = nw_path_monitor_create();

	nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
		BOOL reachable = nw_path_get_status(path) == nw_path_status_satisfied;

		[self.world noteReachabilityChanged:reachable];
	});

	nw_path_monitor_set_queue(monitor, dispatch_get_main_queue());
	nw_path_monitor_start(monitor);

	self.pathMonitor = monitor;
}

#pragma mark -
#pragma mark NSApplication Delegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	/* UserNotifications.framework wants delegation set before app has
	 finished launching. A simple access to the singleton will set this
	 for us which we can just do here. */
	LogToConsoleDebug("Preparing notification controller singeton: %@",
			sharedNotificationController().description);

	/* Prevents AppKit from injecting its automatic search field into
	 the Help menu. */
	NSApp.helpMenu = nil;
}

- (void)applicationDidFinishLaunching
{
	[self removeObserver:self forKeyPath:@"applicationLaunchRemainder"];

	self.applicationIsLaunched = YES;

	if ([self.mainWindow reloadLoadingScreen]) {
		[self.world autoConnectAfterWakeup:NO];
	}

	[self.mainWindow maybeToggleFullscreenAfterLaunch];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
	self.applicationIsChangingActiveState = YES;
}

- (void)applicationWillBecomeActive:(NSNotification *)notification
{
	self.applicationIsChangingActiveState = YES;
}

- (void)applicationDidResignActive:(NSNotification *)notification
{
	self.applicationIsActive = NO;
	self.applicationIsChangingActiveState = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	self.applicationIsActive = YES;
	self.applicationIsChangingActiveState = NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
	if (self.applicationIsTerminating) {
		return NO;
	}

	[self.mainWindow makeKeyAndOrderFront:nil];

	return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	if (self.applicationIsTerminating) {
		return NO;
	}

	[self.mainWindow makeKeyAndOrderFront:nil];

	return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)sender
{
	/* This will have no effect on our app. Implement to suppress warning in console. */
	return YES;
}

#pragma mark -
#pragma mark NSApplication Terminate Procedure

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	return self.menuController.dockMenu;
}

- (BOOL)queryTerminate
{
	if (self.applicationIsTerminating) {
		LogToConsoleTerminationProgress("Termination is already in progress");

		return YES;
	}

	if ([TPCPreferences confirmQuit] == NO) {
		return YES;
	}

	BOOL stillConnected = NO;

	for (IRCClient *u in worldController().clientList) {
		if (u.isConnecting || u.isConnected) {
			stillConnected = YES;
		}
	}

	if (stillConnected) {
		BOOL result = [TDCAlert modalAlertWithMessage:TXTLS(@"Prompts[77u-vp]")
												title:TXTLS(@"Prompts[6vj-2p]")
										defaultButton:TXTLS(@"Prompts[1bf-k0]")
									  alternateButton:TXTLS(@"Prompts[qso-2g]")];

		LogToConsoleTerminationProgress("Perform termination: %{BOOL}d", result);

		return result;
	}

	return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ([self queryTerminate] == NO) {
		return NSTerminateCancel;
	}

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self performApplicationTerminationStepOne];
	});

	return NSTerminateLater;
}

- (BOOL)isSafeToPerformApplicationTermination
{
	/* Clients are still disconnecting */
	BOOL condition1 = (self.terminatingClientCount == 0);

	/* Core Data is saving */
	BOOL condition2 = (TVCLogControllerHistoricLogSharedInstance().isSaving == NO &&
							self.terminateHistoricLogSaveFinished);


	LogToConsoleTerminationProgress("Conditions: %{BOOL}d %{BOOL}d", condition1, condition2);

	return (condition1 && condition2);
}

- (void)performApplicationTerminationStepOne
{
	LogToConsoleTerminationProgress("Step one entry");

	self.applicationIsTerminating = YES;

	[[TXSharedApplication sharedAppearance] prepareForApplicationTermination];

	[self.mainWindow prepareForApplicationTermination];

	LogToConsoleTerminationProgress("Giving up shared application delegation");

	[[NSApplication sharedApplication] setDelegate:nil];

	LogToConsoleTerminationProgress("Removing workspace notification center observer");

	[RZWorkspaceNotificationCenter() removeObserver:self];

	LogToConsoleTerminationProgress("Removing shared notification center observer");

	[RZNotificationCenter() removeObserver:self];

	LogToConsoleTerminationProgress("Removing AppleScript event observer");

	[RZAppleEventManager() removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];

	LogToConsoleTerminationProgress("Stopping path monitor");

	nw_path_monitor_cancel(self.pathMonitor);

	LogToConsoleTerminationProgress("Stopping speech synthesizer");

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:YES];

	[TVCLogControllerInlineMediaSharedInstance() prepareForApplicationTermination];

	[self.menuController prepareForApplicationTermination];

	[self performApplicationTerminationStepTwo];
}

- (void)performApplicationTerminationStepTwo
{
	if (self.applicationIsTerminating == NO) {
		return;
	}

	LogToConsoleTerminationProgress("Step two entry");

	self.terminatingClientCount = worldController().clientCount;

	[self.world prepareForApplicationTermination];

	if (self.isSafeToPerformApplicationTermination) {
		[self performApplicationTerminationStepThree];

		return;
	}

	/* We want certain things to 100% happen before the app completely closes.
	 Notable actions: gracefully leaving IRC, saving historic logs, etc. */
	[self performApplicationTerminationStepTwoPoll];
}

- (void)performApplicationTerminationStepTwoPoll
{
	if (self.terminatingClientCount == 0) {
		[TVCLogControllerHistoricLogSharedInstance() prepareForApplicationTermination];

		self.terminateHistoricLogSaveFinished = YES;
	}

	if (self.isSafeToPerformApplicationTermination == NO) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
					   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
			[self performApplicationTerminationStepTwoPoll];
		});

		return;
	}

	XRPerformBlockAsynchronouslyOnMainQueue(^{
		[self performApplicationTerminationStepThree];
	});
}

- (void)performApplicationTerminationStepThree
{
	if (self.applicationIsTerminating == NO) {
		return;
	}

	LogToConsoleTerminationProgress("Step three entry");

	if (self.skipTerminateSave == NO) {
		LogToConsoleTerminationProgress("Saving IRC world");

		[self.world save];
	}

	LogToConsoleTerminationProgress("Suspending member list dispatch queue");

	[IRCChannelMemberList suspendMemberListSerialQueues];

	LogToConsoleTerminationProgress("Unloading plugins");

	[sharedPluginManager() unloadPlugins];

	[windowController() prepareForApplicationTermination];

	[themeController() prepareForApplicationTermination];

	LogToConsoleTerminationProgress("Saving running internal");

	[TPCApplicationInfo saveTimeIntervalSinceApplicationInstall];

	LogToConsoleTerminationProgress("Terminate");

	[NSApp replyToApplicationShouldTerminate:YES];
}

- (void)terminateGracefully
{
	self.applicationIsTerminating = YES;

	[RZSharedApplication() terminate:nil];
}

#pragma mark -
#pragma mark NSWorkspace Notifications

- (void)handleURLEvent:(NSAppleEventDescriptor *)event
		withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSAppleEventDescriptor *description = [event descriptorAtIndex:1];

	NSString *stringValue = description.stringValue;

	[IRCExtras parseIRCProtocolURI:stringValue withDescriptor:event];
}

- (void)computerScreenWillSleep:(NSNotification *)note
{
	LogToConsole("Preparing for screen sleep");

	[self.world prepareForScreenSleep];
}

- (void)computerScreenDidWake:(NSNotification *)note
{
	LogToConsole("Waking from screen sleep");

	[self.world wakeFromScreenSleep];
}

- (void)computerWillSleep:(NSNotification *)note
{
	LogToConsole("Preparing for sleep");

	[self.world prepareForSleep];

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:YES];
	[[TXSharedApplication sharedSpeechSynthesizer] clearQueue];
}

- (void)computerDidWakeUp:(NSNotification *)note
{
	LogToConsole("Waking from sleep");

	[[TXSharedApplication sharedSpeechSynthesizer] setIsStopped:NO];

	[self.world autoConnectAfterWakeup:YES];
}

- (void)computerWillPowerOff:(NSNotification *)note
{
	[self terminateGracefully];
}

@end

NS_ASSUME_NONNULL_END
