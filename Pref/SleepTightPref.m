//
//  SleepTightPref.m
//
//	The pref pane
//
//	Copyright � 2003 Alex Harper
//
// 	This file is part of SleepTight.
// 
// 	SleepTight is free software; you can redistribute it and/or modify
// 	it under the terms of the GNU General Public License as published by
// 	the Free Software Foundation; either version 2 of the License, or
// 	(at your option) any later version.
// 
// 	SleepTight is distributed in the hope that it will be useful,
// 	but WITHOUT ANY WARRANTY; without even the implied warranty of
// 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// 	GNU General Public License for more details.
// 
// 	You should have received a copy of the GNU General Public License
// 	along with SleepTight; if not, write to the Free Software
// 	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
// 

#import "SleepTightPref.h"

@implementation SleepTightPref

///////////////////////////////////////////////////////////////
//	
//	Pref pane standard stuff
//
///////////////////////////////////////////////////////////////

- (void) mainViewDidLoad {
    NSDictionary *info = [[NSBundle bundleForClass:[self class]]infoDictionary];
    NSString *name = [info objectForKey:@"CFBundleName"];
    NSString *version = [info objectForKey:@"CFBundleVersion"];
    NSString *copyright = [info objectForKey:@"NSHumanReadableCopyright"];
	// On first load set the version string
	[versionDisplay setStringValue:[NSString localizedStringWithFormat:@"%@ %@\n%@",name,version,copyright]];
		
	// Load up our keycode conversion
	keyCoder = [[SleepTightKeyCode alloc] init];	

} // mainViewDidLoad

- (void)willSelect {

	// Reread prefs on each load
	if (ourPrefs) {
		// Shouldn't happen but better safe
		[ourPrefs release];
	}
	ourPrefs = [[SleepTightDefaults alloc] init];
	
	// Configure controls
	[self updateControls];

} // willSelect

- (void)didSelect {
	SInt32 			gestValue;
	
	// Check OS version for Panther and give a dialog if needed.
	if (Gestalt(gestaltSystemVersion, &gestValue) == noErr) {
		if (gestValue < 0x1030) {
			NSBeginCriticalAlertSheet(
				// Title
				[[NSBundle bundleForClass:[self class]] localizedStringForKey:OSERRORTITLESTRING value:nil table:nil],
				// Default button
				[[NSBundle bundleForClass:[self class]] localizedStringForKey:@"OK" value:nil table:nil],
				// Alternate button
				nil,
				// Other button
				nil,
				// Window
				[[self mainView] window],
				// Delegate
				nil,
				// end elector
				nil,
				// dismiss selector
				nil,
				// context
				nil,
				// msg
				[[NSBundle bundleForClass:[self class]] 
					localizedStringForKey:OSERRORSTRING 
					value:nil table:nil]
				);
			// Disable all controls
			[self disableControls];
			// Don't let the agent start, just bail
			return;
		}
	}
	else {
		// Go ahead and start the agent anyway
		NSLog(@"SleepTight unable to check system version number.\n");
	}
		
	// Go ahead and start the agent
	[self startAgent];
			
} // didSelect

- (void)didUnselect {

	// Release prefs
	[ourPrefs release];
	ourPrefs = nil;

} // didUnselect

- (void)disableControls {

	// Disable all controls
	[stEnable setEnabled:NO];
	[hotkeyLabel setTextColor:[NSColor lightGrayColor]];
	[hotkeyDisplay setTextColor:[NSColor lightGrayColor]];
	[hotkeyChange setEnabled:NO];

} // disableControls

///////////////////////////////////////////////////////////////
//	
//	Preference configuration
//
///////////////////////////////////////////////////////////////

- (IBAction)enableChange:(id)sender {

	// Handle changes
	if (sender == stEnable) {
		[ourPrefs setSleepTightEnabled:(([stEnable state] == NSOnState) ? YES : NO)];
	}
	
	// Write prefs
	[ourPrefs syncToDisk];
	
	// Update controls
	[self updateControls];
	
	// Update the agent
	[self updateAgent];
	
	// Handle loginitems
	if ([ourPrefs sleepTightEnabled]) {
		[self addAgentLoginItem];
	}
	else {
		[self removeAgentLoginItem];
	}
	
} // enableChange

- (IBAction)enableHotkey:(id)sender {

	// Handle changes
	[ourPrefs setHotkeyEnabled:(YES)];
	[ourPrefs setHotkeySleep:(NO)];
	
	// Write prefs
	[ourPrefs syncToDisk];

	// Update controls
	[self updateControls];
	
	// Update the agent
	[self updateAgent];
	
} // enableHotkey

- (IBAction)configureHotkey:(id)sender {
	NSString	*keyCodeString = [keyCoder stringForKeyCode:[ourPrefs hotkeyCode]];
	int 		result;
	
	// Disable current hotkey
	[[NSDistributedNotificationCenter defaultCenter] 
		postNotificationName:SLEEPTIGHTID object:@"stopHotKey"];
	
	// Do the hotkey sheet
	[hotkeyPanelDisplay setStringValue:[NSString stringWithFormat:@"%@%@",
			[keyCoder stringForModifiers:[ourPrefs hotkeyModifier]],
			(keyCodeString ? keyCodeString : @"Unknown")
			]];
	lastPanelModifiers = 0;
	lastPanelKeyCode = 0;
	[hotkeyPanel setDelegate:self];	
    [NSApp beginSheet:hotkeyPanel modalForWindow:[[self mainView] window] modalDelegate:self didEndSelector:nil contextInfo:nil];
	result = [NSApp runModalForWindow:hotkeyPanel];
	[NSApp endSheet:hotkeyPanel];
	[hotkeyPanel orderOut:nil];
	[hotkeyPanel setDelegate:nil];	
	
	if ((result == NSOKButton) && lastPanelModifiers && lastPanelKeyCode) {
		
		// Store
		[ourPrefs setHotkeyModifier:lastPanelModifiers];
		[ourPrefs setHotkeyCode:lastPanelKeyCode];
		
		// Write prefs
		[ourPrefs syncToDisk];
	}
	
	// Update controls
	[self updateControls];
	
	// Update the agent (restart the hotkey)
	[self updateAgent];
	
} // configureHotkey

- (void)updateControls {
	NSString	*keyCodeString = [keyCoder stringForKeyCode:[ourPrefs hotkeyCode]];

	// Update controls
	[stEnable setState:([ourPrefs sleepTightEnabled] ? NSOnState : NSOffState)];
	[hotkeyDisplay setStringValue:[NSString stringWithFormat:@"%@%@",
			[keyCoder stringForModifiers:[ourPrefs hotkeyModifier]],
			(keyCodeString ? keyCodeString : @"Unknown")
			]];
	
	// Enable controls
        [hotkeyLabel setTextColor:[NSColor blackColor]];
        [hotkeyDisplay setTextColor:[NSColor blackColor]];
        [hotkeyChange setEnabled:YES];
} // updateControls

- (void)updateAgent {
	BOOL 		isAgentRunning = [self agentIsRunning];

	// Manage saver prefs
	if ([ourPrefs sleepTightEnabled] && !ScreenSaverPasswordActive()) {
		SetScreenSaverPasswordPref(YES);
	}

	// Handle agent
	if ([ourPrefs sleepTightEnabled] && isAgentRunning) {
		// Notify running agent
		[[NSDistributedNotificationCenter defaultCenter] 
			postNotificationName:SLEEPTIGHTID object:@"prefChange"];
	}
	else if ([ourPrefs sleepTightEnabled] && !isAgentRunning) {
		// Start the agent
		[self startAgent];
	}
	else {
		// Stop the agent
		[self stopAgent];
	}	

} // updateAgent

///////////////////////////////////////////////////////////////
//	
//	HotKey sheet
//
///////////////////////////////////////////////////////////////

- (IBAction)acceptHotkeySheet:(id)sender {
	
	[NSApp stopModalWithCode:NSOKButton];
	
} // acceptHotkeySheet

- (IBAction)cancelHotkeySheet:(id)sender {

	[NSApp stopModalWithCode:NSCancelButton];

} // cancelHotkeySheet

- (BOOL)hotkeyFromPanelKeyEvent:(NSEvent *)event {
	NSString	*keyCodeString = nil;
	int 		modCount = 0;
	int			modifiers = 0;
	int			keyCode = 0;
	BOOL		isFkey = NO;	

	
	// Do we want this event?
	if ([event type] == NSKeyDown) {
		// Count modifiers
		modifiers = [event modifierFlags];
		if (modifiers & NSCommandKeyMask) { modCount++; }
		if (modifiers & NSAlternateKeyMask) { modCount++; }
		if (modifiers & NSShiftKeyMask) { modCount++; }
		if (modifiers & NSControlKeyMask) { modCount++; }
		// Is it a FKey?
		keyCode = [event keyCode];
		if (((keyCode >= 96) && (keyCode <= 101)) || 
			((keyCode >= 103) && (keyCode <= 113) && ((keyCode % 2) == 1)) ||
			((keyCode >= 118) && (keyCode <= 122) && ((keyCode % 2) == 0))) {
			isFkey = YES;
		}
		if ((modCount >= 2) || isFkey) {
			keyCodeString = [keyCoder stringForKeyCode:[event keyCode]];
			// Skip events we can't code
			if (keyCodeString) {
				lastPanelKeyCode = [event keyCode];
				lastPanelModifiers = [keyCoder cocoaModifiersToCarbon:[event modifierFlags]];
				[hotkeyPanelDisplay setStringValue:[NSString stringWithFormat:@"%@%@",
						[keyCoder stringForModifiers:lastPanelModifiers],
						(keyCodeString ? keyCodeString : @"Unknown")
						]];
				return YES;		
			}
		}
	}
	
	return NO;

} // hotkeyFromPanelKeyEvent

///////////////////////////////////////////////////////////////
//	
//	LoginItems Management
//
///////////////////////////////////////////////////////////////

- (void)addAgentLoginItem {
	NSUserDefaults 			*defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary		*logininfo = [[defaults persistentDomainForName:LOGINITEMDEFAULTSDOMAIN] mutableCopy];
	NSMutableArray			*loginitems = nil;
	NSEnumerator			*itemEnum = nil;
	NSDictionary			*loginitem = nil;
	BOOL					alreadyPresent = NO;
	
	if (!(logininfo && [logininfo objectForKey:LOGINITEMLISTKEY])) {
		NSLog(@"SleepTightPref unable to find login item defaults.\n");
		return;
	}
	
	loginitems = [[logininfo objectForKey:LOGINITEMLISTKEY] mutableCopy];
	if (!loginitems) {
		NSLog(@"SleepTightPref unable to find login item list.\n");
		return;
	}
	
	itemEnum = [loginitems objectEnumerator];
	while (loginitem = [itemEnum nextObject]) {
		if ([loginitem objectForKey:LOGINITEMPATHKEY] && [[loginitem objectForKey:LOGINITEMPATHKEY] hasSuffix:AGENTBUNDLENAME]) {
			alreadyPresent = YES;
			break;
		}
	}
	
	if (!alreadyPresent) {
		[loginitems addObject:[NSDictionary dictionaryWithObjectsAndKeys:
									AGENTPATH,
									LOGINITEMPATHKEY,
									[NSNumber numberWithBool:YES],
									LOGINITEMHIDEKEY,
									nil]];
		[logininfo setObject:loginitems forKey:LOGINITEMLISTKEY];
		[defaults setPersistentDomain:logininfo forName:LOGINITEMDEFAULTSDOMAIN];
	}

} // addAgentLoginItem

- (void)removeAgentLoginItem {
	NSUserDefaults 			*defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary		*logininfo = [[defaults persistentDomainForName:LOGINITEMDEFAULTSDOMAIN] mutableCopy];
	NSArray					*loginitems = nil;
	NSMutableArray			*newloginitems = [NSMutableArray array];
	NSEnumerator			*itemEnum = nil;
	NSDictionary			*loginitem = nil;
	BOOL					wasRemoved = NO;
	
	if (!(logininfo && [logininfo objectForKey:LOGINITEMLISTKEY])) {
		NSLog(@"SleepTightPref unable to find login item defaults.\n");
		return;
	}
	
	loginitems = [logininfo objectForKey:LOGINITEMLISTKEY];
	if (!loginitems) {
		NSLog(@"SleepTightPref unable to find login item list.\n");
		return;
	}
	
	itemEnum = [loginitems objectEnumerator];
	while (loginitem = [itemEnum nextObject]) {
		if ([loginitem objectForKey:LOGINITEMPATHKEY] && [[loginitem objectForKey:LOGINITEMPATHKEY] hasSuffix:AGENTBUNDLENAME]) {
			wasRemoved = YES;
		}
		else {
			[newloginitems addObject:loginitem];
		}
	}
	
	if (wasRemoved) {
		[logininfo setObject:newloginitems forKey:LOGINITEMLISTKEY];
		[defaults setPersistentDomain:logininfo forName:LOGINITEMDEFAULTSDOMAIN];
	}

} // removeAgentLoginItem

///////////////////////////////////////////////////////////////
//	
//	Agent Management
//
///////////////////////////////////////////////////////////////

- (void)startAgent {
	LSLaunchURLSpec		launchSpec;
	
	// Only start if needed
	if (![self agentIsRunning]) {
		// Despite the fact that the Agent is LSBackgroundOnly it still deactivates
		// the SystemPreferences window if we launch from NSWorkspace, so we use
		// LaunchServices instead
		launchSpec.appURL = (CFURLRef)[NSURL fileURLWithPath:AGENTPATH];
		launchSpec.itemURLs = NULL;
		launchSpec.passThruParams = NULL;
		launchSpec.launchFlags = kLSLaunchDefaults | kLSLaunchDontAddToRecents | kLSLaunchDontSwitch | kLSLaunchNoParams;
		launchSpec.asyncRefCon = NULL;
		if (LSOpenFromURLSpec(&launchSpec,NULL) != noErr) {
			NSLog(@"SleepTightPref unable to launch agent.\n");
		}
	}

} // startAgent

- (void)stopAgent {

	// No need to worry, just send
	[[NSDistributedNotificationCenter defaultCenter] 
		postNotificationName:SLEEPTIGHTID object:@"killAgent"];

} // stopAgent

- (BOOL)agentIsRunning {
	ProcessSerialNumber		psn;
	ProcessInfoRec			procInfo;
	Str255					procName;
	NSString				*procString = nil; 
	
	// Set up for iterate
	psn.highLongOfPSN = kNoProcess;
	psn.lowLongOfPSN = kNoProcess;
	
	// Set up info
	procInfo.processInfoLength = sizeof(ProcessInfoRec);
	procInfo.processName = procName;
#if __LP64__
    procInfo.processAppRef = nil;
#else
    procInfo.processAppSpec = nil;
#endif
    
	// Using GetProcessInformation because this crashed on some machines when using ProcessInformationCopyDictionary
	// Crash looks like an Apple bug since it happens inside ProcessInformationCopyDictionary and seems to be specifc
	// to the background processes on the machine.
	while (noErr == GetNextProcess(&psn)) {
		if (noErr == GetProcessInformation(&psn, &procInfo)) {
			if ((procName[1] != '\0') && (procName[0] != 0))  {
				procString = (NSString *)CFStringCreateWithPascalString(NULL,
									procInfo.processName, kCFStringEncodingMacRoman);
				[procString autorelease];				
				if ([procString hasSuffix:AGENTNAME]) {
					return YES;
				}
			}
		}
	}
	
	// Get here its not running
	return NO;

} // agentIsRunning


@end
