//
//  SleepTightKeyCode.m
//
//	Convert keycodes and modifiers to strings
//
//	Keycode conversion table from Quentin D. Carnicelli, Copyright (c) 2002 Subband Inc. 
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

#import "SleepTightKeyCode.h"

@implementation SleepTightKeyCode

///////////////////////////////////////////////////////////////
//	
//	init/dealloc
//
///////////////////////////////////////////////////////////////

- (id)init {
	
	// Allow super to init
	self = [super init];
	if (!self) {
		return nil;
	}
	
	// Load up our localized keycode dictionary
	codeDict = [[[NSString stringWithContentsOfFile:
					[[NSBundle bundleForClass:[self class]] pathForResource:@"KeyCode" ofType:@"plist"]]
					propertyList] retain];

	return self;

} // init

- (void)dealloc {
	
	if (codeDict) {
		[codeDict release];
	}		
	[super dealloc];

} // dealloc

///////////////////////////////////////////////////////////////
//	
//	Conversion and checks
//
///////////////////////////////////////////////////////////////

- (NSString *)stringForModifiers:(int)modifiers {
	NSString	*modString = @"";
	
	if (modifiers & cmdKey) {
		modString = [modString stringByAppendingString:[NSString stringWithFormat:@"%C", kCommandUnicode]];
	}
	if (modifiers & shiftKey) {
		modString = [modString stringByAppendingString:[NSString stringWithFormat:@"%C", kShiftUnicode]];
	}
	if (modifiers & optionKey) {
		modString = [modString stringByAppendingString:[NSString stringWithFormat:@"%C", kOptionUnicode]];
	}
	if (modifiers & controlKey) {
		modString = [modString stringByAppendingString:[NSString stringWithFormat:@"%C", kControlUnicode]];
	}
	
	return modString;

} // stringForModifiers

- (NSString *)stringForKeyCode:(int)code {
	NSString		*keyString = nil;
	
	if ([codeDict objectForKey:[NSString stringWithFormat:@"%i",code]]) {
		// Use the dict
		keyString = [codeDict objectForKey:[NSString stringWithFormat:@"%i",code]];
	}
		
	return keyString;

} // stringForKeyCode

- (int)cocoaModifiersToCarbon:(int)modifiers {
	int			carbonmods = 0;
	
	if (modifiers & NSCommandKeyMask) {
		carbonmods = carbonmods | cmdKey;
	}
	if (modifiers & NSShiftKeyMask) {
		carbonmods = carbonmods | shiftKey;
	}
	if (modifiers & NSAlternateKeyMask) {
		carbonmods = carbonmods | optionKey;
	}
	if (modifiers & NSControlKeyMask) {
		carbonmods = carbonmods | controlKey;
	}
	
	return carbonmods;
	
} // cocoaModifiersToCarbon

@end
