//
//  MyWindow.m
//  Zephyros
//
//  Created by Steven Degutis on 2/28/13.
//  Copyright (c) 2013 Steven Degutis. All rights reserved.
//

#import "SIWindow.h"

#import "NSScreen+SilicaExtension.h"
#import "SIApplication.h"
#import "SISystemWideElement.h"
#import "SIUniversalAccessHelper.h"

@implementation SIWindow

#pragma mark Window Accessors

+ (NSArray *)allWindows {
    if ([SIUniversalAccessHelper complainIfNeeded]) return nil;
    
    NSMutableArray *windows = [NSMutableArray array];
    
    for (SIApplication *application in [SIApplication runningApplications]) {
        [windows addObjectsFromArray:[application windows]];
    }
    
    return windows;
}

+ (NSArray *)visibleWindows {
    if ([SIUniversalAccessHelper complainIfNeeded])
        return nil;

    return [[self allWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SIWindow *win, NSDictionary *bindings) {
        return ![[win app] isHidden]
        && ![win isWindowMinimized]
        && [win isNormalWindow];
    }]];
}

+ (SIWindow *)focusedWindow {
    if ([SIUniversalAccessHelper complainIfNeeded])
        return nil;

    CFTypeRef app;
    AXUIElementCopyAttributeValue([SISystemWideElement systemWideElement].axElementRef, kAXFocusedApplicationAttribute, &app);

    if (app) {
        CFTypeRef win;
        AXError result = AXUIElementCopyAttributeValue(app, (CFStringRef)NSAccessibilityFocusedWindowAttribute, &win);

        CFRelease(app);

        if (result == kAXErrorSuccess) {
            SIWindow *window = [[SIWindow alloc] initWithAXElement:win];
            return window;
        }
    }

    return nil;
}

- (NSArray *)otherWindowsOnSameScreen {
    return [[SIWindow visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SIWindow *win, NSDictionary *bindings) {
        return ![self isEqual:win] && [[self screen] isEqual: [win screen]];
    }]];
}

- (NSArray *)otherWindowsOnAllScreens {
    return [[SIWindow visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SIWindow *win, NSDictionary *bindings) {
        return ![self isEqual:win];
    }]];
}

- (NSArray *)windowsToWest {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI - abs(angle); }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToEast {
    return [[self windowsInDirectionFn:^double(double angle) { return 0.0 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX <= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToNorth {
    return [[self windowsInDirectionFn:^double(double angle) { return -M_PI_2 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToSouth {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI_2 - angle; }
                     shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY <= 0); }] valueForKeyPath:@"win"];
}

#pragma mark Window Geometry

- (CGRect)frame {
    CGRect r;
    r.origin = [self topLeft];
    r.size = [self size];
    return r;
}

- (CGPoint)topLeft {
    CFTypeRef positionStorage;
    AXError result = AXUIElementCopyAttributeValue(self.axElementRef, (CFStringRef)NSAccessibilityPositionAttribute, &positionStorage);
    
    CGPoint topLeft;
    if (result == kAXErrorSuccess) {
        if (!AXValueGetValue(positionStorage, kAXValueCGPointType, (void *)&topLeft)) {
            NSLog(@"could not decode topLeft");
            topLeft = CGPointZero;
        }
    } else {
        NSLog(@"could not get window topLeft");
        topLeft = CGPointZero;
    }
    
    if (positionStorage) {
        CFRelease(positionStorage);
    }
    
    return topLeft;
}

- (CGSize)size {
    CFTypeRef sizeStorage;
    AXError result = AXUIElementCopyAttributeValue(self.axElementRef, (CFStringRef)NSAccessibilitySizeAttribute, &sizeStorage);
    
    CGSize size;
    if (result == kAXErrorSuccess) {
        if (!AXValueGetValue(sizeStorage, kAXValueCGSizeType, (void *)&size)) {
            NSLog(@"could not decode topLeft");
            size = CGSizeZero;
        }
    } else {
        NSLog(@"could not get window size");
        size = CGSizeZero;
    }
    
    if (sizeStorage) {
        CFRelease(sizeStorage);
    }
    
    return size;
}

- (void)setFrame:(CGRect)frame {
    [self setSize:frame.size];
    [self setTopLeft:frame.origin];
    [self setSize:frame.size];
}

- (void)setTopLeft:(CGPoint)thePoint {
    CFTypeRef positionStorage = (CFTypeRef)(AXValueCreate(kAXValueCGPointType, (const void *)&thePoint));
    AXUIElementSetAttributeValue(self.axElementRef, (CFStringRef)NSAccessibilityPositionAttribute, positionStorage);
    if (positionStorage)
        CFRelease(positionStorage);
}

- (void)setSize:(CGSize)theSize {
    CFTypeRef sizeStorage = (CFTypeRef)(AXValueCreate(kAXValueCGSizeType, (const void *)&theSize));
    AXUIElementSetAttributeValue(self.axElementRef, (CFStringRef)NSAccessibilitySizeAttribute, sizeStorage);
    if (sizeStorage)
        CFRelease(sizeStorage);
}

#pragma mark Window Properties

- (NSString *)title {
    return [self stringForKey:kAXTitleAttribute];
}

- (NSString *)role {
    return [self stringForKey:kAXRoleAttribute];
}

- (NSString *)subrole {
    return [self stringForKey:kAXSubroleAttribute];
}

- (BOOL)isWindowMinimized {
    return [[self numberForKey:kAXMinimizedAttribute] boolValue];
}

- (BOOL)isNormalWindow {
    NSString *subrole = [self subrole];
    if (subrole) {
        return [subrole isEqualToString:(__bridge NSString *)kAXStandardWindowSubrole];
    }
    return YES;
}

- (NSScreen *)screen {
    CGRect windowFrame = [self frame];
    
    CGFloat lastVolume = 0;
    NSScreen *lastScreen = nil;
    
    for (NSScreen *screen in [NSScreen screens]) {
        CGRect screenFrame = [screen frameIncludingDockAndMenu];
        CGRect intersection = CGRectIntersection(windowFrame, screenFrame);
        CGFloat volume = intersection.size.width * intersection.size.height;
        
        if (volume > lastVolume) {
            lastVolume = volume;
            lastScreen = screen;
        }
    }
    
    return lastScreen;
}

- (SIApplication *)app {
    NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    return [SIApplication applicationWithRunningApplication:runningApplication];
}

#pragma mark Window Actions

- (void)maximize {
    CGRect screenRect = [[self screen] frameWithoutDockOrMenu];
    [self setFrame: screenRect];
}

- (void)minimize {
    [self setWindowMinimized:YES];
}

- (void)unMinimize {
    [self setWindowMinimized:NO];
}

- (void)setWindowMinimized:(BOOL)flag {
    [self setWindowProperty:NSAccessibilityMinimizedAttribute withValue:@(flag)];
}

- (BOOL)setWindowProperty:(NSString *)propType withValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        AXError result = AXUIElementSetAttributeValue(self.axElementRef, (__bridge CFStringRef)(propType), (__bridge CFTypeRef)(value));
        if (result == kAXErrorSuccess)
            return YES;
    }
    return NO;
}

#pragma mark Window Focus

- (BOOL)focusWindow {
    AXError changedMainWindowResult = AXUIElementSetAttributeValue(self.axElementRef, (CFStringRef)NSAccessibilityMainAttribute, kCFBooleanTrue);
    if (changedMainWindowResult != kAXErrorSuccess) {
        NSLog(@"ERROR: Could not change focus to window");
        return NO;
    }

    ProcessSerialNumber psn;
    GetProcessForPID([self processIdentifier], &psn);
    OSStatus focusAppResult = SetFrontProcessWithOptions(&psn, kSetFrontProcessFrontWindowOnly);
    return (focusAppResult == 0);
}

NSPoint SIMidpoint(NSRect r) {
    return NSMakePoint(NSMidX(r), NSMidY(r));
}

- (NSArray *)windowsInDirectionFn:(double(^)(double angle))whichDirectionFn
                shouldDisregardFn:(BOOL(^)(double deltaX, double deltaY))shouldDisregardFn {
    SIWindow *thisWindow = [SIWindow focusedWindow];
    NSPoint startingPoint = SIMidpoint([thisWindow frame]);
    
    NSArray *otherWindows = [thisWindow otherWindowsOnAllScreens];
    NSMutableArray *closestOtherWindows = [NSMutableArray arrayWithCapacity:[otherWindows count]];
    
    for (SIWindow *win in otherWindows) {
        NSPoint otherPoint = SIMidpoint([win frame]);
        
        double deltaX = otherPoint.x - startingPoint.x;
        double deltaY = otherPoint.y - startingPoint.y;
        
        if (shouldDisregardFn(deltaX, deltaY))
            continue;
        
        double angle = atan2(deltaY, deltaX);
        double distance = hypot(deltaX, deltaY);
        
        double angleDifference = whichDirectionFn(angle);
        
        double score = distance / cos(angleDifference / 2.0);
        
        [closestOtherWindows addObject:@{
         @"score": @(score),
         @"win": win,
         }];
    }
    
    NSArray *sortedOtherWindows = [closestOtherWindows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* pair1, NSDictionary* pair2) {
        return [[pair1 objectForKey:@"score"] compare:[pair2 objectForKey:@"score"]];
    }];
    
    return sortedOtherWindows;
}

- (void)focusFirstValidWindowIn:(NSArray*)closestWindows {
    for (SIWindow *win in closestWindows) {
        if ([win focusWindow]) break;
    }
}

- (void)focusWindowLeft {
    [self focusFirstValidWindowIn:[self windowsToWest]];
}

- (void)focusWindowRight {
    [self focusFirstValidWindowIn:[self windowsToEast]];
}

- (void)focusWindowUp {
    [self focusFirstValidWindowIn:[self windowsToNorth]];
}

- (void)focusWindowDown {
    [self focusFirstValidWindowIn:[self windowsToSouth]];
}

@end
