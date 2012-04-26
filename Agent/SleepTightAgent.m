//
//  SleepTightAgent.m
//
//	Helper app implementation
//
//	Copyright © 2003 Alex Harper
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

#import "SleepTightAgent.h"

///////////////////////////////////////////////////////////////
//	
//	Carbon/IOKit callbacks
//
///////////////////////////////////////////////////////////////

pascal OSStatus LockHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
	
	if (userData) {
		[(SleepTightAgent *)userData lockFromHotKey];
	}
	return noErr;

} // LockHotKeyHandler

@implementation SleepTightAgent

///////////////////////////////////////////////////////////////
//	
//	Startup/Terminate
//
///////////////////////////////////////////////////////////////

- (void)awakeFromNib {
	// OS version
	SInt32 				osVersion ;
	// Hotkey support
	EventHandlerUPP			hotKeyCallback = nil;
	EventTypeSpec 			eventType;
	
	// Check OS version
	if (Gestalt(gestaltSystemVersion, &osVersion) == noErr) {
		if (osVersion < 0x1030) {
			NSLog(@"SleepTightAgent is not supported on MacOS X versions older than MacOS X 10.3 (Panther). Abort.\n");
			[NSApp terminate:self];
		}
	}
	else {
		NSLog(@"SleepTightAgent cannot check OS version. Abort.\n");
		[NSApp terminate:self];
	}
	
	// Build a screensaver controller
	ssControl = [[ScreenSaverController controller] retain];
	if (!ssControl) {
		NSLog(@"SleepTightAgent cannot build a screensaver controller. Abort.\n");
		[NSApp terminate:self];
	}
	
	// Register for power notifications
//	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(ioNotify),
//                        kCFRunLoopDefaultMode);
						
	// Load up prefs
	ourPrefs = [[SleepTightDefaults alloc] init];					
						
	// Set up hotkey callback (key registration handled in configFromPrefs)
	// Install the Carbon callbacks
	hotKeyCallback = NewEventHandlerUPP(LockHotKeyHandler);
	eventType.eventClass=kEventClassKeyboard;
	eventType.eventKind=kEventHotKeyPressed;
	InstallApplicationEventHandler(hotKeyCallback, 1, &eventType, self, NULL);
							
	// Validate saver prefs
	if (!ScreenSaverPasswordActive()) {
		SetScreenSaverPasswordPref(TRUE);
	}
		
	// Load up our prefs
	[self configFromPrefs:nil];
	
	// Register for all the notifications we need
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(configFromPrefs:) 
				name:SLEEPTIGHTID object:@"prefChange"];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(unregisterHotKey:) 
				name:SLEEPTIGHTID object:@"stopHotKey"];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(killAgent:) 
				name:SLEEPTIGHTID object:@"killAgent"];
				
	NSLog(@"SleepTightAgent started.\n");			
	
} // awakeFromNib

///////////////////////////////////////////////////////////////
//	
//	Callbacks
//
///////////////////////////////////////////////////////////////

- (void)lockFromHotKey {
	
	// Show the lock bezel
	[bezelWindow showLockDisplay];
	
	// Lock screen
	[self startSaver];
	
} // lockFromHotkey

///////////////////////////////////////////////////////////////
//	
//	Screensaver control
//
///////////////////////////////////////////////////////////////

- (void)startSaver {
	
	// If the saver is already front do nothing
	if ([ssControl screenSaverIsRunning]) {
		return;
	}
	
	// Validate saver prefs
	if (!ScreenSaverPasswordActive()) {
		SetScreenSaverPasswordPref(TRUE);
	}
	
	// Can saver start?
	if (![ssControl screenSaverCanRun]) {
		return;
	}

	// Start the saver
	[ssControl screenSaverStartNow];

} // startSaver

- (BOOL)saverIsFront {
	OSStatus				err;
	ProcessSerialNumber		psn;
	CFDictionaryRef			processInfo = nil;
	
	// Check if the saver is already running
	err = GetFrontProcess(&psn);
	if (err != noErr) {
		return NO; // Assume not
	}
	// Using ProcessInformationCopyDictionary here even though it was crashy in the pref because we are
	// not iterating over background processes which seems to be the cause of the crash.
	processInfo = ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
	if (!processInfo) {
		return NO; // Assume not
	}
	if (![(NSDictionary *)processInfo objectForKey:@"BundlePath"]) {
		CFRelease(processInfo);
		return NO; // Assume not
	}
	if ([(NSString *)[(NSDictionary *)processInfo objectForKey:@"BundlePath"] isEqualToString:SAVERBUNDLEPATH]) {
		CFRelease(processInfo);
		return YES; // Its running
	}
	
	CFRelease(processInfo);
	return NO;
	
} // saverIsFront

///////////////////////////////////////////////////////////////
//	
//	Preferences
//
///////////////////////////////////////////////////////////////

- (void)configFromPrefs:(NSNotification *)notification {

	// Sync prefs
	[ourPrefs syncFromDisk];
	
	// Check enabled
	if (![ourPrefs sleepTightEnabled]) {
		[self killAgent:nil];
	}
	
	// Hotkey setup
	if ([ourPrefs hotkeyEnabled] && [ourPrefs hotkeyModifier] && [ourPrefs hotkeyCode]) {
		[self registerHotKey];
	}
	else {
		[self unregisterHotKey:nil];
	}

} // configFromPrefs 

///////////////////////////////////////////////////////////////
//	
//	Hotkey management
//
///////////////////////////////////////////////////////////////

- (void)registerHotKey {
	OSStatus				err;

	if (lockHotKeyRef) {
		err = UnregisterEventHotKey(lockHotKeyRef);
		if (err != noErr) {
			NSLog(@"SleepTightAgent unable to unregister its hotkey.\n");
		}
	}
	// Set up our callback data
	lockHotKeyID.signature = SLEEPTIGHTHOTKEYSIGNATURE;
	lockHotKeyID.id = 1;
	err = RegisterEventHotKey([ourPrefs hotkeyCode], [ourPrefs hotkeyModifier], lockHotKeyID, GetApplicationEventTarget(), 0, &lockHotKeyRef);
	if (err != noErr) {
		lockHotKeyRef = nil;
		NSLog(@"SleepTightAgent unable to register its hotkey.\n");
	}

} // registerHotKey

- (void)unregisterHotKey:(NSNotification *)notification {
	OSStatus				err;

	if (lockHotKeyRef) {
		err = UnregisterEventHotKey(lockHotKeyRef);
		if (err != noErr) {
			NSLog(@"SleepTightAgent unable to unregister its hotkey.\n");
		}
	}
	lockHotKeyRef = nil;

};

///////////////////////////////////////////////////////////////
//	
//	Exit notification
//
///////////////////////////////////////////////////////////////

- (void)killAgent:(NSNotification *)notification {
	
	NSLog(@"SleepTightAgent exit.\n");
	[NSApp terminate:self];

} // killAgent

@end
