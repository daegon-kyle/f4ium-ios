/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Handles UI interaction and retrieves window images.
 */

#import "Controller.h"
#import "StepCollectionViewItem.h"
#import "SOLogger.h"
#import "SecurityKeypadMap.h"
#import <AppKit/NSClickGestureRecognizer.h>
#import "AFNetworking.h"
#import "F4ium-ios.h"

extern SOLogger *gLogger;

@implementation NSWindow (TitleBarHeight)

- (CGFloat)titlebarHeight {
    CGFloat contentHeight = [self contentRectForFrameRect: self.frame].size.height;
    return self.frame.size.height - contentHeight;
}

@end


@interface WindowListApplierData : NSObject
{
}

@property (strong, nonatomic) NSMutableArray * outputArray;
@property int order;

@end

@implementation WindowListApplierData

-(instancetype)initWindowListData:(NSMutableArray *)array
{
    self = [super init];
    
    self.outputArray = array;
    self.order = 0;
    
    return self;
}

@end


@interface Controller () {
    IBOutlet NSImageView *outputView;
    IBOutlet NSArrayController *arrayController;
    IBOutlet NSCollectionView *collectionView;
    
    CGWindowListOption listOptions;
    CGWindowListOption singleWindowListOptions;
    CGWindowImageOption imageOptions;
    CGRect imageBounds;
    
    CGWindowID selectedWindowID;
    NSString *selectedWindowName;
    NSString *selectedWindowTitle;
    int selectedWindowOriginX, selectedWindowOriginY;
    int selectedWindowSizeW, selectedWindowSizeH;
    float selectedDeviceInch;
    NSString *selectedDeviceID;
    NSMutableSet *recordedLogs;
    NSString *lastRetrievedID;
    
    NSMutableArray *cmdList;
    int cmdInsertLocation;
    BOOL bPauseRecording;
}

@property (weak) IBOutlet NSButton * imageFramingEffects;
@property (weak) IBOutlet NSButton * imageOpaqueImage;
@property (weak) IBOutlet NSButton *btnPauseResume;

@end


@implementation Controller


#pragma mark Basic Profiling Tools
// Set to 1 to enable basic profiling. Profiling information is logged to console.
#ifndef PROFILE_WINDOW_GRAB
#define PROFILE_WINDOW_GRAB 0
#endif

#if PROFILE_WINDOW_GRAB
#define StopwatchStart() AbsoluteTime start = UpTime()
#define Profile(img) CFRelease(CGDataProviderCopyData(CGImageGetDataProvider(img)))
#define StopwatchEnd(caption) do { Duration time = AbsoluteDeltaToDuration(UpTime(), start); double timef = time < 0 ? time / -1000000.0 : time / 1000.0; NSLog(@"%s Time Taken: %f seconds", caption, timef); } while(0)
#else
#define StopwatchStart()
#define Profile(img)
#define StopwatchEnd(caption)
#endif


#pragma mark Utilities

// Simple helper to twiddle bits in a uint32_t.
uint32_t ChangeBits(uint32_t currentBits, uint32_t flagsToChange, BOOL setFlags);
inline uint32_t ChangeBits(uint32_t currentBits, uint32_t flagsToChange, BOOL setFlags) {
    if(setFlags)
        return currentBits | flagsToChange;
    else
        return currentBits & ~flagsToChange;
}

- (void)setOutputImage:(CGImageRef)cgImage {
    if(cgImage != NULL) {
        // Create a bitmap rep from the image...
        NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        // Create an NSImage and add the bitmap rep to it...
        NSImage *image = [[NSImage alloc] init];
        [image addRepresentation:bitmapRep];
        // Set the output view to the new NSImage.
        [outputView setImage:image];
    } else {
        [outputView setImage:nil];
    }
}


#pragma mark Window List & Window Image Methods

NSString *kAppNameKey = @"applicationName";	// Application Name & PID
NSString *kWindowTitleKey = @"windowTitle";     // Window Title
NSString *kWindowOriginKey = @"windowOrigin";	// Window Origin as a string
NSString *kWindowSizeKey = @"windowSize";		// Window Size as a string
NSString *kWindowIDKey = @"windowID";			// Window ID
NSString *kWindowLevelKey = @"windowLevel";	// Window Level
NSString *kWindowOrderKey = @"windowOrder";	// The overall front-to-back ordering of the windows as returned by the window server

void WindowListApplierFunction(const void *inputDictionary, void *context) {
    NSDictionary *entry = (__bridge NSDictionary*)inputDictionary;
    WindowListApplierData *data = (__bridge WindowListApplierData*)context;
    
    // The flags that we pass to CGWindowListCopyWindowInfo will automatically filter out most undesirable windows.
    // However, it is possible that we will get back a window that we cannot read from, so we'll filter those out manually.
    int sharingState = [entry[(id)kCGWindowSharingState] intValue];
    if (sharingState != kCGWindowSharingNone) {
        NSMutableDictionary *outputEntry = [NSMutableDictionary dictionary];
        
        // Grab the application name, but since it's optional we need to check before we can use it.
        NSString *applicationName = entry[(id)kCGWindowOwnerName];
        NSString *windowTitle = entry[(id)kCGWindowName];
        if (![applicationName containsString:@"Simulator"] || ![windowTitle containsString:@"iPhone"])
            return;
        
        if (applicationName != NULL) {
            // PID is required so we assume it's present.
            NSString *nameAndPID = [NSString stringWithFormat:@"%@ (%@)", applicationName, entry[(id)kCGWindowOwnerPID]];
            outputEntry[kAppNameKey] = nameAndPID;
        } else {
            // The application name was not provided, so we use a fake application name to designate this.
            // PID is required so we assume it's present.
            NSString *nameAndPID = [NSString stringWithFormat:@"((unknown)) (%@)", entry[(id)kCGWindowOwnerPID]];
            outputEntry[kAppNameKey] = nameAndPID;
        }
        
        outputEntry[kWindowTitleKey] = windowTitle;
        
        // Grab the Window Bounds, it's a dictionary in the array, but we want to display it as a string
        CGRect bounds;
        CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)entry[(id)kCGWindowBounds], &bounds);
        NSString *originString = [NSString stringWithFormat:@"%.0f/%.0f", bounds.origin.x, bounds.origin.y];
        outputEntry[kWindowOriginKey] = originString;
        NSString *sizeString = [NSString stringWithFormat:@"%.0f*%.0f", bounds.size.width, bounds.size.height];
        outputEntry[kWindowSizeKey] = sizeString;
        
        // Grab the Window ID & Window Level. Both are required, so just copy from one to the other
        outputEntry[kWindowIDKey] = entry[(id)kCGWindowNumber];
        outputEntry[kWindowLevelKey] = entry[(id)kCGWindowLayer];
        
        // Finally, we are passed the windows in order from front to back by the window server
        // Should the user sort the window list we want to retain that order so that screen shots
        // look correct no matter what selection they make, or what order the items are in. We do this
        // by maintaining a window order key that we'll apply later.
        outputEntry[kWindowOrderKey] = @(data.order);
        data.order++;
        
        [data.outputArray addObject:outputEntry];
    }
}

- (void)updateWindowList {
    // Ask the window server for the list of windows.
    StopwatchStart();
    CFArrayRef windowList = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID);
    StopwatchEnd("Create Window List");
    
    // Copy the returned list, further pruned, to another list. This also adds some bookkeeping
    // information to the list as well as
    NSMutableArray * prunedWindowList = [NSMutableArray array];
    WindowListApplierData *windowListData = [[WindowListApplierData alloc] initWindowListData:prunedWindowList];
    
    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), &WindowListApplierFunction, (__bridge void *)windowListData);
    CFRelease(windowList);
    
    // Set the new window list
    [arrayController setContent:prunedWindowList];
}

- (CFArrayRef)newWindowListFromSelection:(NSArray*)selection {
    // Create a sort descriptor array. It consists of a single descriptor that sorts based on the kWindowOrderKey in ascending order
    NSArray * sortDescriptors = @[[[NSSortDescriptor alloc] initWithKey:kWindowOrderKey ascending:YES]];
    
    // Next sort the selection based on that sort descriptor array
    NSArray * sortedSelection = [selection sortedArrayUsingDescriptors:sortDescriptors];
    
    // Now we Collect the CGWindowIDs from the sorted selection
    unsigned long count = sortedSelection.count;
    const void *windowIDs[count];
    int i = 0;
    for(NSMutableDictionary *entry in sortedSelection)
    {
        windowIDs[i++] = [entry[kWindowIDKey] unsignedIntValue];
    }
    CFArrayRef windowIDsArray = CFArrayCreate(kCFAllocatorDefault, (const void**)windowIDs, [sortedSelection count], NULL);
    
    // And send our new array on it's merry way
    return windowIDsArray;
}

- (void)createSingleWindowShot:(CGWindowID)windowID {
    // Create an image from the passed in windowID with the single window option selected by the user.
    StopwatchStart();
    CGImageRef windowImage = CGWindowListCreateImage(imageBounds, singleWindowListOptions, windowID, imageOptions);
    Profile(windowImage);
    StopwatchEnd("Single Window");
    [self setOutputImage:windowImage];
    CGImageRelease(windowImage);
}

- (void)createMultiWindowShot:(NSArray*)selection {
    // Get the correctly sorted list of window IDs. This is a CFArrayRef because we need to put integers in the array
    // instead of CFTypes or NSObjects.
    CFArrayRef windowIDs = [self newWindowListFromSelection:selection];
    
    // And finally create the window image and set it as our output image.
    StopwatchStart();
    CGImageRef windowImage = CGWindowListCreateImageFromArray(imageBounds, windowIDs, imageOptions);
    Profile(windowImage);
    StopwatchEnd("Multiple Window");
    CFRelease(windowIDs);
    [self setOutputImage:windowImage];
    CGImageRelease(windowImage);
}

- (void)createScreenShot {
    // This just invokes the API as you would if you wanted to grab a screen shot. The equivalent using the UI would be to
    // enable all windows, turn off "Fit Image Tightly", and then select all windows in the list.
    StopwatchStart();
    CGImageRef screenShot = CGWindowListCreateImage(CGRectInfinite, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault);
    Profile(screenShot);
    StopwatchEnd("Screenshot");
    [self setOutputImage:screenShot];
    CGImageRelease(screenShot);
    /*
     aslmsg q, m;
     int i;
     const char *key, *val;
     
     q = asl_new(ASL_TYPE_QUERY);
     asl_set_query(q, ASL_KEY_SENDER, "Logger", ASL_QUERY_OP_EQUAL);
     
     aslresponse r = asl_search(NULL, q);
     while (NULL != (m = aslresponse_next(r)))
     {
     NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
     
     for (i = 0; (NULL != (key = asl_key(m, i))); i++)
     {
     NSString *keyString = [NSString stringWithUTF8String:(char *)key];
     
     val = asl_get(m, key);
     
     NSString *string = [NSString stringWithUTF8String:val];
     [tmpDict setObject:string forKey:keyString];
     }
     
     NSLog(@"%@", tmpDict);
     }
     aslresponse_free(r);
     
     */
}

- (void)readDeviceID {
    NSString *output = [self runCommand:@"/usr/bin/xcrun" withArguments:@[@"simctl", @"list"]];
    
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"\\R.+\\(Booted\\)"
                                  options:NSRegularExpressionCaseInsensitive
                                  error:&error];
    [regex enumerateMatchesInString:output options:0 range:NSMakeRange(0, output.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *result = [[output substringWithRange:match.range] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSLog(@"%@", result);
        NSRange openParenthesis = [result rangeOfString:@"("];
        NSRange closeParenthesis = [result rangeOfString:@")"];
        openParenthesis.location += 1;
        openParenthesis.length = closeParenthesis.location - openParenthesis.location;
        if ([selectedWindowTitle hasPrefix:[result substringToIndex:openParenthesis.location-2]]) {
            selectedDeviceID = [result substringWithRange:openParenthesis];
            NSLog(@"%@ with ID=%@", [result substringToIndex:openParenthesis.location-2], selectedDeviceID);
        }
    }];
}

- (NSString *)readLogFile {
    [NSThread sleepForTimeInterval:0.33f];
    __block NSString *ids = @"";
    __block BOOL bFirstRead = NO;
    if (recordedLogs.count == 0)
        bFirstRead = YES;
    NSString *output = [self runCommand:@"/usr/bin/tail" withArguments:@[@"-n",
                                                                         @"200",
                                                                         [NSString stringWithFormat:@"%@/Library/Logs/CoreSimulator/%@/system.log", NSHomeDirectory(), selectedDeviceID]]];
    
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"\\R.+AccessibilityID=.+"
                                  options:NSRegularExpressionCaseInsensitive
                                  error:&error];
    [regex enumerateMatchesInString:output options:0 range:NSMakeRange(0, output.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *result = [[output substringWithRange:match.range] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([recordedLogs containsObject:result])
            return;
        [recordedLogs addObject:result];
        NSRange idHeader = [result rangeOfString:@"AccessibilityID="];
        if (bFirstRead || ids.length == 0)
            ids = [result substringFromIndex:idHeader.location + idHeader.length];
        else
            ids = [NSString stringWithFormat:@"%@,%@", ids, [result substringFromIndex:idHeader.location + idHeader.length]];
        lastRetrievedID = ids;
    }];
    
    return ids;
}


#pragma mark GUI Support

- (void)updateImageWithSelection {
    // Depending on how much is selected either clear the output image
    // set the image based on a single selected window or
    // set the image based on multiple selected windows.
    NSArray *selection = [arrayController selectedObjects];
    if([selection count] == 0)
        [self setOutputImage:NULL];
    else if([selection count] == 1) {
        // Single window selected, so use the single window options.
        // Need to grab the CGWindowID to pass to the method.
        CGWindowID windowID = [selection[0][kWindowIDKey] unsignedIntValue];
        [self createSingleWindowShot:windowID];
    } else {
        // Multiple windows selected, so composite just those windows
        [self createMultiWindowShot:selection];
    }
}

enum {
    // Constants that correspond to the rows in the
    // Single Window Option matrix.
    kSingleWindowAboveOnly = 0,
    kSingleWindowAboveIncluded = 1,
    kSingleWindowOnly = 2,
    kSingleWindowBelowIncluded = 3,
    kSingleWindowBelowOnly = 4,
};

// Simple helper that converts the selected row number of the singleWindow NSMatrix
// to the appropriate CGWindowListOption.
- (CGWindowListOption)singleWindowOption {
    return kCGWindowListOptionIncludingWindow;
}

NSString *kvoContext = @"f4ium-iosContext";
- (void)awakeFromNib {
    // Set the initial list options to match the UI.
    listOptions = kCGWindowListOptionOnScreenOnly;
    
    // Set the initial image options to match the UI.
    imageOptions = kCGWindowImageDefault;
    imageOptions = ChangeBits(imageOptions, kCGWindowImageBoundsIgnoreFraming, [_imageFramingEffects intValue] == NSOnState);
    imageOptions = ChangeBits(imageOptions, kCGWindowImageShouldBeOpaque, [_imageOpaqueImage intValue] == NSOnState);
    
    // Set initial single window options to match the UI.
    singleWindowListOptions = [self singleWindowOption];
    
    // CGWindowListCreateImage & CGWindowListCreateImageFromArray will determine their image size dependent on the passed in bounds.
    // This sample only demonstrates passing either CGRectInfinite to get an image the size of the desktop
    // or passing CGRectNull to get an image that tightly fits the windows specified, but you can pass any rect you like.
    imageBounds = CGRectNull;
    
    // Register for updates to the selection
    [arrayController addObserver:self forKeyPath:@"selectionIndexes" options:0 context:&kvoContext];
    
    // Make sure the source list window is in front
    [[outputView window] makeKeyAndOrderFront:self];
    [[self window] makeKeyAndOrderFront:self];
    
    // Get the initial window list, and set the initial image, but wait for us to return to the
    // event loop so that the sample's windows will be included in the list as well.
    [self performSelectorOnMainThread:@selector(refreshWindowList:) withObject:self waitUntilDone:NO];
    
    // Default to creating a screen shot. Do this after our return since the previous request
    // to refresh the window list will set it to nothing due to the interactions with KVO.
    [self performSelectorOnMainThread:@selector(createScreenShot) withObject:self waitUntilDone:NO];
    
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
    if (!accessibilityEnabled) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"\'손쉬운 사용\' 권한 확인"];
        [alert setInformativeText:@"[시스템 환경설정]➝[보안 및 개인 정보 보호]➝[개인 정보 보호]➝[손쉬운 사용] 에서 이 앱의 활성화 필요합니다."];
        [alert addButtonWithTitle:@"확인"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        
    } else {
        static int startX, startY;
        static BOOL dragging = NO;
        
        id lDownEvent = ^(NSEvent *event){
            [self updateSelectedWindow];
            if ([self filterOutEvent])
                return;
            
            startX = [self getMouseX];
            startY = [self getMouseY];
        };
        
        id lDraggedEvent = ^(NSEvent *event){
            if ([self filterOutEvent])
                return;
            
            dragging = YES;
        };
        
        id lUpEvent = ^(NSEvent *event){
            if ([self filterOutEvent]) {
                dragging = NO;
                return;
            }
            
            int endX = [self getMouseX];
            int endY = [self getMouseY];
            
            if (fabs((float)(startX-endX)) <= 10 && fabs((float)(startY-endY)) <= 10)
                dragging = NO;
            
            if (bPauseRecording)
                return;
            
            [self createSingleWindowShot:selectedWindowID];
            
            NSMutableDictionary *cmd = [NSMutableDictionary new];
            NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
            NSString *cmdCoordinate = @"";
            if (!dragging)
                cmdCoordinate = [NSString stringWithFormat:@"(new TouchAction(driver)).tap(%d, %d).perform();", endX, endY];
            else
                cmdCoordinate = [NSString stringWithFormat:@"(new TouchAction(driver)).press(%d, %d).moveTo(%d, %d).release().perform();", startX, startY, endX-startX, endY-startY];
            NSLog(@"%@", cmdCoordinate);
            
            NSString *cmdID = [self readLogFile];
            if (cmdID.length > 0) {
                cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", cmdID];
                NSLog(@"%@", cmdID);
            }
            
            [cmd setValue:outputView.image forKey:@"image"];
            [cmd setValue:cmdNumber forKey:@"cmdNumber"];
            [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
            [cmd setValue:cmdID forKey:@"cmdID"];
            [cmdList addObject:cmd];
            
            dragging = NO;
            
            [self updateCommandList];
        };
        
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:lDownEvent];
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged handler:lDraggedEvent];
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:lUpEvent];
    }
    [collectionView setItemPrototype:[StepCollectionViewItem new]];
    [collectionView.enclosingScrollView setHasHorizontalScroller:NO];
    [collectionView.enclosingScrollView setHasVerticalScroller:YES];
    cmdList = [NSMutableArray new];
}

- (void)updateCommandList {
    [collectionView setContent:cmdList];
    
    NSClickGestureRecognizer *click = nil;
    NSUInteger numberOfItems = collectionView.content.count;
    for (NSUInteger itemIndex = 0; itemIndex < numberOfItems; itemIndex++) {
        StepCollectionViewItem *item = (StepCollectionViewItem*)[collectionView itemAtIndex:itemIndex];
        
        if (item.btnMoveUp.gestureRecognizers.count > 0)
            continue;
        
        click = [[NSClickGestureRecognizer alloc] init];
        click.target = self;
        click.numberOfClicksRequired = 1;
        click.action = @selector(moveUpAction:);
        [item.btnMoveUp addGestureRecognizer:click];
        
        click = [[NSClickGestureRecognizer alloc] init];
        click.target = self;
        click.numberOfClicksRequired = 1;
        click.action = @selector(moveDownAction:);
        [item.btnMoveDown addGestureRecognizer:click];
        
        click = [[NSClickGestureRecognizer alloc] init];
        click.target = self;
        click.numberOfClicksRequired = 1;
        click.action = @selector(addEventAction:);
        [item.btnAddEvent addGestureRecognizer:click];
        
        click = [[NSClickGestureRecognizer alloc] init];
        click.target = self;
        click.numberOfClicksRequired = 1;
        click.action = @selector(copyEventAction:);
        [item.btnCopyEvent addGestureRecognizer:click];
        
        click = [[NSClickGestureRecognizer alloc] init];
        click.target = self;
        click.numberOfClicksRequired = 1;
        click.action = @selector(removeEventAction:);
        [item.btnRemoveEvent addGestureRecognizer:click];
    }
    
    if (cmdList.count > 0) {
        NSRect rect = collectionView.enclosingScrollView.frame;
        rect.origin.y += (cmdList.count-1) * rect.size.height;
        [collectionView scrollRectToVisible:rect];
    }
}

- (void)changeItemNumberTo:(int)newNum atIndex:(int)index {
    StepCollectionViewItem *item = (StepCollectionViewItem*)[collectionView itemAtIndex:index];
    [item.txtTitle setStringValue:[NSString stringWithFormat:@"Step #%d", newNum]];
    [item.btnMoveUp setTag:newNum];
    [item.btnMoveDown setTag:newNum];
    [item.btnAddEvent setTag:newNum];
    [item.btnCopyEvent setTag:newNum];
    [item.btnRemoveEvent setTag:newNum];
}

- (void)moveUpAction:(NSClickGestureRecognizer *)sender {
    int tag = (int)[(NSButton*)sender.view tag];
    int index = tag-1;
    NSInteger totalCmdCount = [cmdList count];
    if (index == 0)
        return;
    
    NSMutableDictionary *prev = [cmdList objectAtIndex:index-1];
    [prev setValue:[NSString stringWithFormat:@"%d", index+1] forKey:@"cmdNumber"];
    [self changeItemNumberTo:index+1 atIndex:index-1];
    
    NSMutableDictionary *current = [cmdList objectAtIndex:index];
    [current setValue:[NSString stringWithFormat:@"%d", index] forKey:@"cmdNumber"];
    [self changeItemNumberTo:index atIndex:index];
    
    [cmdList replaceObjectAtIndex:index-1 withObject:current];
    [cmdList replaceObjectAtIndex:index withObject:prev];
    [collectionView setContent:cmdList];
}

- (void)moveDownAction:(NSClickGestureRecognizer *)sender {
    int tag = (int)[(NSButton*)sender.view tag];
    int index = tag-1;
    NSInteger totalCmdCount = [cmdList count];
    if (tag == totalCmdCount)
        return;
    
    NSMutableDictionary *next = [cmdList objectAtIndex:index+1];
    [next setValue:[NSString stringWithFormat:@"%d", index+1] forKey:@"cmdNumber"];
    [self changeItemNumberTo:index+1 atIndex:index+1];
    
    NSMutableDictionary *current = [cmdList objectAtIndex:index];
    [current setValue:[NSString stringWithFormat:@"%d", index+2] forKey:@"cmdNumber"];
    [self changeItemNumberTo:index+2 atIndex:index];
    
    [cmdList replaceObjectAtIndex:index+1 withObject:current];
    [cmdList replaceObjectAtIndex:index withObject:next];
    [collectionView setContent:cmdList];
}

- (void)addEventAction:(NSClickGestureRecognizer *)sender {
    int tag = (int)[(NSButton*)sender.view tag];
    cmdInsertLocation = tag; // 현재 위치에 삽입하므로 -1 하지 않음
    
    NSMenu *ctxMenu = [[NSMenu alloc] initWithTitle:@"Add Event"];
    [ctxMenu insertItemWithTitle:@"Normal Keypad Input" action:@selector(insertNormalKeypadInput:) keyEquivalent:@"" atIndex:0];
    [ctxMenu insertItemWithTitle:@"Security Keypad Input" action:@selector(insertSecurityKeypadInput:) keyEquivalent:@"" atIndex:1];
    [ctxMenu insertItemWithTitle:@"System Keypad Input" action:@selector(insertSystemKeypadInput:) keyEquivalent:@"" atIndex:2];
    [ctxMenu insertItem:NSMenuItem.separatorItem atIndex:3];
    [ctxMenu insertItemWithTitle:@"Delay Event" action:@selector(insertDelayEvent:) keyEquivalent:@"" atIndex:4];
    CGPoint location = [sender.view convertRect:sender.view.bounds toView:nil].origin;
    location.x += [sender locationInView:sender.view].x;
    location.y += [sender locationInView:sender.view].y;
    NSEvent* event = [NSEvent otherEventWithType:NSApplicationDefined
                                        location:location
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:[[self window] windowNumber]
                                         context:[[self window] graphicsContext]
                                         subtype:100
                                           data1:0
                                           data2:0];
    [NSMenu popUpContextMenu:ctxMenu withEvent:event forView:sender.view];
}

- (void)copyEventAction:(NSClickGestureRecognizer *)sender {
    NSPasteboard *nspb = [NSPasteboard generalPasteboard];
    
    int tag = (int)[(NSButton*)sender.view tag];
    int index = tag-1;
    NSInteger totalCmdCount = [cmdList count];
    
    if (totalCmdCount > index) {
        [nspb clearContents];
        StepCollectionViewItem *stepItem = (StepCollectionViewItem *)[collectionView itemAtIndex:index];
        
        if (stepItem.radioCoordinate.state == NSOnState) {
            [nspb setString:stepItem.tfCmdCooridatenate.stringValue forType:NSStringPboardType];
        } else {
            [nspb setString:stepItem.tfCmdID.stringValue forType:NSStringPboardType];
        }
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"복사완료"];
        [alert setInformativeText:[nspb stringForType:NSStringPboardType]];
        [alert addButtonWithTitle:@"확인"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
    }
}

- (void)removeEventAction:(NSClickGestureRecognizer *)sender {
    int tag = (int)[(NSButton*)sender.view tag];
    int index = tag-1;
    NSInteger totalCmdCount = [cmdList count];
    
    if (totalCmdCount > index) {
        if (totalCmdCount == tag) {
            [cmdList removeObjectAtIndex:totalCmdCount-1];
        } else {
            for (int i = index; i < totalCmdCount-1; i++) {
                NSMutableDictionary *cmd = [cmdList objectAtIndex:i+1];
                [cmd setValue:[NSString stringWithFormat:@"%d", i+1] forKey:@"cmdNumber"];
                [self changeItemNumberTo:i+1 atIndex:i+1];
                [cmdList replaceObjectAtIndex:i withObject:cmd];
            }
            [cmdList removeObjectAtIndex:totalCmdCount-1];
        }
        [collectionView setContent:cmdList];
    }
}

- (void)updateSelectedWindow {
    // 윈도우 위치가 갱신되었을 경우 업데이트
    StopwatchStart();
    CFArrayRef windowList = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID);
    StopwatchEnd("Create Window List");
    
    NSMutableArray * prunedWindowList = [NSMutableArray array];
    WindowListApplierData *windowListData = [[WindowListApplierData alloc] initWindowListData:prunedWindowList];
    
    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), &WindowListApplierFunction, (__bridge void *)windowListData);
    CFRelease(windowList);
    
    for (NSDictionary *window in prunedWindowList) {
        if ([window[kWindowIDKey] intValue] == selectedWindowID) {
            NSArray *coords = [window[kWindowOriginKey] componentsSeparatedByString:@"/"];
            selectedWindowOriginX = [coords[0] intValue];
            selectedWindowOriginY = [coords[1] intValue] + self.window.titlebarHeight;
            NSArray *size = [window[kWindowSizeKey] componentsSeparatedByString:@"*"];
            selectedWindowSizeW = [size[0] intValue];
            selectedWindowSizeH = [size[1] intValue];
            break;
        }
    }
}

- (BOOL)filterOutEvent {
    // 이름이 일치하는 윈도우만
    NSDictionary *activeApp = NSWorkspace.sharedWorkspace.activeApplication;
    if (![selectedWindowName containsString:activeApp[@"NSApplicationName"]])
        return YES;
    
    NSRect e = [[NSScreen mainScreen] frame];
    int H = (int)e.size.height;
    float x = [self getMouseX];
    float y = [self getMouseY];
    
    // 좌표가 창 영역 안에 없는 경우에는 필터링
    if (x > selectedWindowSizeW || y > selectedWindowSizeH || y < 0)
        return YES;
    
    return NO;
}

- (int)getMouseX {
    float x = NSEvent.mouseLocation.x - selectedWindowOriginX;
    
    if (selectedDeviceInch != 5.5)
        return x;
    else
        return x*2/3;
}

- (int)getMouseY {
    NSScreen *mainScreen = [NSScreen mainScreen];
    NSRect mainScreenRect = [mainScreen frame];
    int H = 0;
    float y = 0.0;
    
    if (selectedWindowOriginX < 0 || selectedWindowOriginY < 0 ||
        selectedWindowOriginX > mainScreenRect.size.width || selectedWindowOriginY > mainScreenRect.size.height) {
        NSScreen *subScreen;
        if ([NSScreen screens][0] == mainScreen)
            subScreen = [NSScreen screens][1];
        else
            subScreen = [NSScreen screens][0];
        
        NSRect subScreenRect = [subScreen frame];
        H = (int)subScreenRect.size.height;
    } else
        H = (int)mainScreenRect.size.height;
    
    y = H - NSEvent.mouseLocation.y - selectedWindowOriginY;
    
    if (selectedDeviceInch != 5.5)
        return y;
    else
        return y*2/3;
}

- (void)dealloc {
    // Remove our KVO notification
    [arrayController removeObserver:self forKeyPath:@"selectionIndexes"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context == &kvoContext) {
        // Selection has changed, so update the image
        [self updateImageWithSelection];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (NSString *)runCommand:(NSString *)cmdPath withArguments:(NSArray *)arguments {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *file = pipe.fileHandleForReading;
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = cmdPath;
    task.arguments = arguments;
    task.standardOutput = pipe;
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    [file closeFile];
    
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}


#pragma mark Control Actions

- (IBAction)openFile:(id)sender {
    NSOpenPanel* openPanel = NSOpenPanel.openPanel;
    [openPanel setAllowedFileTypes:@[@"f4i"]];
    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSMutableArray *fileContent = [NSMutableArray arrayWithContentsOfFile:openPanel.URL.path];
            
            if (fileContent == nil) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"알림"];
                [alert setInformativeText:@"파일 열기에 실패하였습니다."];
                [alert addButtonWithTitle:@"확인"];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
                
            } else {
                for (int i = 0; i < fileContent.count; i++) {
                    NSImage *image = [[NSImage alloc] initWithData:[fileContent[i] objectForKey:@"image"]];
                    [fileContent[i] setObject:image forKey:@"image"];
                }
                
                cmdList = fileContent;
                [self updateCommandList];
            }
        }
    }];
}

- (IBAction)saveFile:(id)sender {
    if (cmdList.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"알림"];
        [alert setInformativeText:@"저장할 명령어가 없습니다."];
        [alert addButtonWithTitle:@"확인"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        return;
    }
    
    NSSavePanel* savePanel = NSSavePanel.savePanel;
    [savePanel setAllowedFileTypes:@[@"f4i"]];
    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSMutableArray *fileContent = [NSMutableArray arrayWithArray:cmdList];
            
            for (int i = 0; i < fileContent.count; i++) {
                NSData *imageData = [[fileContent[i] objectForKey:@"image"] TIFFRepresentation];
                NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:imageData];
                NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.1] forKey:NSImageCompressionFactor];
                NSData *dataToWrite = [rep representationUsingType:NSJPEGFileType properties:options];
                [fileContent[i] setObject:dataToWrite forKey:@"image"];
            }
            
            BOOL success = [fileContent writeToURL:savePanel.URL atomically:NO];
            if (!success) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"알림"];
                [alert setInformativeText:@"파일 저장에 실패하였습니다."];
                [alert addButtonWithTitle:@"확인"];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
            }
        }
    }];
}

- (IBAction)exportAsJUnitCode:(id)sender {
    if (cmdList.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"알림"];
        [alert setInformativeText:@"내보내기할 명령어가 없습니다."];
        [alert addButtonWithTitle:@"확인"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        return;
    }
    
    NSSavePanel* savePanel = NSSavePanel.savePanel;
    [savePanel setAllowedFileTypes:@[@"java"]];
    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSMutableString *fileContent = [NSMutableString new];
            
            for (int i = 0; i < collectionView.subviews.count; i++) {
                StepCollectionViewItem *stepItem = (StepCollectionViewItem *)[collectionView itemAtIndex:i];
                
                [fileContent appendString:[NSString stringWithFormat:@"// Step #%d\n", i]];
                if (stepItem.tfComment.stringValue.length > 0)
                    [fileContent appendString:[NSString stringWithFormat:@"// %@\n", stepItem.tfComment.stringValue]];
                
                if (stepItem.radioCoordinate.state == NSOnState) {
                    if (stepItem.tfCmdCooridatenate.stringValue.length > 0) {
                        [fileContent appendString:stepItem.tfCmdCooridatenate.stringValue];
                        [fileContent appendString:@"\n"];
                    }
                    if (stepItem.tfCmdID.stringValue.length > 0) {
                        [fileContent appendString:@"// "];
                        [fileContent appendString:stepItem.tfCmdID.stringValue];
                        [fileContent appendString:@"\n"];
                    }
                } else {
                    if (stepItem.tfCmdCooridatenate.stringValue.length > 0) {
                        [fileContent appendString:@"// "];
                        [fileContent appendString:stepItem.tfCmdCooridatenate.stringValue];
                        [fileContent appendString:@"\n"];
                    }
                    if (stepItem.tfCmdID.stringValue.length > 0) {
                        [fileContent appendString:stepItem.tfCmdID.stringValue];
                        [fileContent appendString:@"\n"];
                    }
                }
            }
            
            NSError *error;
            BOOL success = [fileContent writeToURL:savePanel.URL atomically:NO encoding:NSUTF8StringEncoding error:&error];
            if (!success) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"알림"];
                [alert setInformativeText:[NSString stringWithFormat:@"%@", error.localizedDescription]];
                [alert addButtonWithTitle:@"확인"];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert runModal];
            }
        }
    }];
}

- (BOOL)checkLastRetrievedID {
    if (lastRetrievedID != nil)
        return YES;
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"알림"];
    [alert setInformativeText:@"문자열이 입력될 앱 내 텍스트 상자를 반드시 선택해주세요."];
    [alert addButtonWithTitle:@"확인"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert runModal];
    return NO;
}

- (IBAction)appendNormalKeypadInput:(id)sender {
    [self generateNormalKeypadInput:sender insertEnabled:NO];
}

- (IBAction)insertNormalKeypadInput:(id)sender {
    [self generateNormalKeypadInput:sender insertEnabled:YES];
}

- (void)generateNormalKeypadInput:(id)sender insertEnabled:(BOOL)bInsert {
    if (![self checkLastRetrievedID])
        return;
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"생성할 일반 키패드 문자열을 입력해주세요."];
    [alert setInformativeText:[NSString stringWithFormat:@"%@%@", @"현재 마지막으로 감지한 앱 내 항목: ", lastRetrievedID]];
    [alert addButtonWithTitle:@"확인"];
    [alert addButtonWithTitle:@"취소"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    
    if (button == NSAlertFirstButtonReturn) {
        [self createSingleWindowShot:selectedWindowID];
        
        NSMutableDictionary *cmd = [NSMutableDictionary new];
        NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
        if (bInsert)
            cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
        NSString *cmdCoordinate = @"";
        NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).sendKeys(\"%@\");", lastRetrievedID, input.stringValue];
        NSLog(@"%@", cmdID);
        
        [cmd setValue:outputView.image forKey:@"image"];
        [cmd setValue:cmdNumber forKey:@"cmdNumber"];
        [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
        [cmd setValue:cmdID forKey:@"cmdID"];
        if (bInsert) {
            for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                [self changeItemNumberTo:i+2 atIndex:i];
            }
            [cmdList insertObject:cmd atIndex:cmdInsertLocation];
        } else
            [cmdList addObject:cmd];
        
        [self updateCommandList];
    }
}

- (IBAction)appendSecurityKeypadInput:(id)sender {
    [self generateSecurityKeypadInput:sender insertEnabled:NO];
}

- (IBAction)insertSecurityKeypadInput:(id)sender {
    [self generateSecurityKeypadInput:sender insertEnabled:YES];
}

- (IBAction)generateSecurityKeypadInput:(id)sender insertEnabled:(BOOL)bInsert {
    SecurityKeypadMap *secKeyMap = [SecurityKeypadMap sharedSecurityKeyMap];
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"생성할 보안 키패드 문자열을 입력해주세요."];
    [alert setInformativeText:@"한글 입력 금지!"];
    [alert addButtonWithTitle:@"확인"];
    [alert addButtonWithTitle:@"취소"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    
    if (button == NSAlertFirstButtonReturn) {
        [self createSingleWindowShot:selectedWindowID];
        
        for (int i = 0; i < input.stringValue.length; i++) {
            NSString *substr = [input.stringValue substringWithRange:NSMakeRange(i, 1)];
            unichar chr = [input.stringValue characterAtIndex:i];
            
            if ((chr >= 'a' && chr <= 'z') || (chr >= '0' && chr <= '9')) {
                NSMutableDictionary *cmd = [NSMutableDictionary new];
                NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                NSString *cmdCoordinate = @"";
                NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", [secKeyMap retrieveID:substr]];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
            } else if (chr >= 'A' && chr <= 'Z') {
                NSMutableDictionary *cmd = [NSMutableDictionary new];
                NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                NSString *cmdCoordinate = @"";
                NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", @"대소문자 변경"];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
                cmd = [NSMutableDictionary new];
                cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                cmdCoordinate = @"";
                cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", [secKeyMap retrieveID:substr]];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
                cmd = [NSMutableDictionary new];
                cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                cmdCoordinate = @"";
                cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", @"대소문자 변경"];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
            } else { // 특수문자
                NSMutableDictionary *cmd = [NSMutableDictionary new];
                NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                NSString *cmdCoordinate = @"";
                NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", @"특수문자 변경"];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
                cmd = [NSMutableDictionary new];
                cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                cmdCoordinate = @"";
                cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", [secKeyMap retrieveID:substr]];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
                
                cmd = [NSMutableDictionary new];
                cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
                if (bInsert)
                    cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
                cmdCoordinate = @"";
                cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", @"특수문자 변경"];
                NSLog(@"%@", cmdID);
                
                [cmd setValue:outputView.image forKey:@"image"];
                [cmd setValue:cmdNumber forKey:@"cmdNumber"];
                [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
                [cmd setValue:cmdID forKey:@"cmdID"];
                if (bInsert) {
                    for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                        NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                        [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                        [self changeItemNumberTo:i+2 atIndex:i];
                    }
                    [cmdList insertObject:cmd atIndex:cmdInsertLocation];
                    cmdInsertLocation++;
                } else
                    [cmdList addObject:cmd];
                [self updateCommandList];
            }
        }
        
        NSMutableDictionary *cmd = [NSMutableDictionary new];
        NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
        if (bInsert)
            cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
        NSString *cmdCoordinate = @"";
        NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", @"입력완료"];
        NSLog(@"%@", cmdID);
        
        [cmd setValue:outputView.image forKey:@"image"];
        [cmd setValue:cmdNumber forKey:@"cmdNumber"];
        [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
        [cmd setValue:cmdID forKey:@"cmdID"];
        if (bInsert) {
            for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                [self changeItemNumberTo:i+2 atIndex:i];
            }
            [cmdList insertObject:cmd atIndex:cmdInsertLocation];
        } else
            [cmdList addObject:cmd];
        
        [self updateCommandList];
    }
}

- (IBAction)appendSystemKeypadInput:(id)sender {
    [self generateSystemKeypadInput:sender insertEnabled:NO];
}

- (IBAction)insertSystemKeypadInput:(id)sender {
    [self generateSystemKeypadInput:sender insertEnabled:YES];
}

- (IBAction)generateSystemKeypadInput:(id)sender insertEnabled:(BOOL)bInsert {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"생성할 시스템 키패드 메시지를 선택해주세요."];
    [alert addButtonWithTitle:@"확인"];
    [alert addButtonWithTitle:@"취소"];
    
    NSPopUpButton *popupButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    [popupButton addItemWithTitle:@"확인"];
    [popupButton addItemWithTitle:@"취소"];
    [alert setAccessoryView:popupButton];
    NSInteger button = [alert runModal];
    
    if (button == NSAlertFirstButtonReturn) {
        [self createSingleWindowShot:selectedWindowID];
        
        NSMutableDictionary *cmd = [NSMutableDictionary new];
        NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
        if (bInsert)
            cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
        NSString *cmdCoordinate = @"";
        NSString *cmdID = [NSString stringWithFormat:@"((MobileElement) driver.findElementByAccessibilityId(\"%@\")).click();", popupButton.titleOfSelectedItem];
        NSLog(@"%@", cmdID);
        
        [cmd setValue:outputView.image forKey:@"image"];
        [cmd setValue:cmdNumber forKey:@"cmdNumber"];
        [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
        [cmd setValue:cmdID forKey:@"cmdID"];
        if (bInsert) {
            for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                [self changeItemNumberTo:i+2 atIndex:i];
            }
            [cmdList insertObject:cmd atIndex:cmdInsertLocation];
        } else
            [cmdList addObject:cmd];
        
        [self updateCommandList];
    }
}

- (IBAction)appendDelayEvent:(id)sender {
    [self generateDelayEvent:sender insertEnabled:NO];
}

- (IBAction)insertDelayEvent:(id)sender {
    [self generateDelayEvent:sender insertEnabled:YES];
}

- (IBAction)generateDelayEvent:(id)sender insertEnabled:(BOOL)bInsert {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"시간지연을 초 단위로 입력해주세요."];
    [alert addButtonWithTitle:@"확인"];
    [alert addButtonWithTitle:@"취소"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    NSInteger button = [alert runModal];
    
    if (button == NSAlertFirstButtonReturn) {
        NSCharacterSet *alphaNums = [NSCharacterSet decimalDigitCharacterSet];
        NSCharacterSet *inStringSet = [NSCharacterSet characterSetWithCharactersInString:input.stringValue];
        if (![alphaNums isSupersetOfSet:inStringSet]) {
            [self generateDelayEvent:sender insertEnabled:bInsert];
            return;
        }
        
        [self createSingleWindowShot:selectedWindowID];
        
        NSMutableDictionary *cmd = [NSMutableDictionary new];
        NSString *cmdNumber = [NSString stringWithFormat:@"%ld", cmdList.count+1];
        if (bInsert)
            cmdNumber = [NSString stringWithFormat:@"%d", cmdInsertLocation+1];
        NSString *cmdCoordinate = @"";
        NSString *cmdID = [NSString stringWithFormat:@"Thread.sleep(%@ * 1000);", input.stringValue];
        NSLog(@"%@", cmdID);
        
        [cmd setValue:outputView.image forKey:@"image"];
        [cmd setValue:cmdNumber forKey:@"cmdNumber"];
        [cmd setValue:cmdCoordinate forKey:@"cmdCoordinate"];
        [cmd setValue:cmdID forKey:@"cmdID"];
        if (bInsert) {
            for (int i = cmdInsertLocation; i < cmdList.count; i++) {
                NSMutableDictionary *cmd = [cmdList objectAtIndex:i];
                [cmd setValue:[NSString stringWithFormat:@"%d", i+2] forKey:@"cmdNumber"];
                [self changeItemNumberTo:i+2 atIndex:i];
            }
            [cmdList insertObject:cmd atIndex:cmdInsertLocation];
        } else
            [cmdList addObject:cmd];
        
        [self updateCommandList];
    }
}

- (IBAction)refreshWindowList:(id)sender {
#pragma unused(sender)
    // Refreshing the window list combines updating the window list and updating the window image.
    [self updateWindowList];
    [self updateImageWithSelection];
}

- (IBAction)selectWindow:(id)sender {
    NSArray *selection = [arrayController selectedObjects];
    if ([selection count] > 0) {
        selectedWindowID = [selection[0][kWindowIDKey] unsignedIntValue];
        selectedWindowName = selection[0][kAppNameKey];
        selectedWindowTitle = selection[0][kWindowTitleKey];
        
        NSArray *coords = [selection[0][kWindowOriginKey] componentsSeparatedByString:@"/"];
        selectedWindowOriginX = [coords[0] intValue];
        selectedWindowOriginY = [coords[1] intValue] + self.window.titlebarHeight;
        NSArray *size = [selection[0][kWindowSizeKey] componentsSeparatedByString:@"*"];
        selectedWindowSizeW = [size[0] intValue];
        selectedWindowSizeH = [size[1] intValue];
        
        if (selectedWindowSizeW >= 355 && selectedWindowSizeW <= 395 &&
            selectedWindowSizeH >= 670 && selectedWindowSizeH <= 710)
            selectedDeviceInch = 4.7;
        else if (selectedWindowSizeW >= 600 && selectedWindowSizeW <= 640 &&
                 selectedWindowSizeH >= 1100 && selectedWindowSizeH <= 1140)
            selectedDeviceInch = 5.5;
        else
            selectedDeviceInch = 4;
        
        [self readDeviceID];
        recordedLogs = [NSMutableSet new];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"알림"];
        [alert setInformativeText:@"Window List에서 테스트하고자 하는 Simulator를 선택해주세요."];
        [alert addButtonWithTitle:@"확인"];
        [alert runModal];
    }
}

- (IBAction)toggleFramingEffects:(id)sender {
    imageOptions = ChangeBits(imageOptions, kCGWindowImageBoundsIgnoreFraming, [sender intValue] == NSOnState);
    [self updateImageWithSelection];
}

- (IBAction)toggleOpaqueImage:(id)sender {
    imageOptions = ChangeBits(imageOptions, kCGWindowImageShouldBeOpaque, [sender intValue] == NSOnState);
    [self updateImageWithSelection];
}

- (IBAction)grabScreenShot:(id)sender {
#pragma unused(sender)
    [self createScreenShot];
}

- (IBAction)pauseOrResume:(id)sender {
    if (bPauseRecording)
        [_btnPauseResume setTitle:@"Pause Recording"];
    else
        [_btnPauseResume setTitle:@"Resume Recording"];
    bPauseRecording = !bPauseRecording;
}

- (IBAction)sendCommands:(id)sender {
#pragma unused(sender)
    if (cmdList.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"알림"];
        [alert setInformativeText:@"송신할 명령어가 없습니다."];
        [alert addButtonWithTitle:@"확인"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        return;
    }
    
    NSMutableString *commands = [NSMutableString new];
    for (int i = 0; i < collectionView.subviews.count; i++) {
        StepCollectionViewItem *stepItem = (StepCollectionViewItem *)[collectionView itemAtIndex:i];
        
        [commands appendString:[NSString stringWithFormat:@"// Step #%d\n", i+1]];
        if (stepItem.tfComment.stringValue.length > 0)
            [commands appendString:[NSString stringWithFormat:@"// %@\n", stepItem.tfComment.stringValue]];
        
        if (stepItem.radioCoordinate.state == NSOnState) {
            if (stepItem.tfCmdCooridatenate.stringValue.length > 0) {
                [commands appendString:stepItem.tfCmdCooridatenate.stringValue];
                [commands appendString:@"\n"];
            }
        } else {
            if (stepItem.tfCmdID.stringValue.length > 0) {
                [commands appendString:stepItem.tfCmdID.stringValue];
                [commands appendString:@"\n"];
            }
        }
    }
    
#pragma print response object or error for test
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager.requestSerializer setTimeoutInterval:2.0f];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSString *url = TEST_URL;
    
    [manager POST:url parameters:@{@"commands": commands} progress:nil
          success:^(NSURLSessionTask *task, id responseObject) {
              NSLog(@"success: %@", responseObject);
          }
          failure:^(NSURLSessionTask *task, NSError *error) {
              NSLog(@"failure: %@", error);
          }];
}

- (IBAction)LoadCommands:(id)sender {
#pragma unused(sender)
#pragma print response object or error for test
#pragma change responseSerializer to AFJSONResponseSerializer in the futue
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager.requestSerializer setTimeoutInterval:2.0f];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSString *url = TEST_URL;
    
    [manager POST:url parameters:nil progress:nil
          success:^(NSURLSessionTask *task, id responseObject) {
              NSLog(@"success: %@", responseObject);
          }
          failure:^(NSURLSessionTask *task, NSError *error) {
              NSLog(@"failure: %@", error);
          }];
}

@end
