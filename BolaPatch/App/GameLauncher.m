//
//  GameLauncher.m
//  private-API app launching (same trick Delta Proxy / other loaders use)
//

#import "GameLauncher.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static id lswWorkspace(void) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    if (cls == Nil) {
        return nil;
    }
    SEL sel = NSSelectorFromString(@"defaultWorkspace");
    if (![cls respondsToSelector:sel]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
}

BOOL BolaLaunchApp(NSString *bundleID) {
    if (bundleID.length == 0) {
        return NO;
    }

    id workspace = lswWorkspace();
    if (workspace != nil) {
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([workspace respondsToSelector:openSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(workspace, openSel, bundleID);
            return YES;
        }
    }

    // fallback: try the app's URL scheme if it has one
    NSArray<NSString *> *schemes = @[ @"freefire", @"ff", @"freefireth", @"freefiremax" ];
    for (NSString *scheme in schemes) {
        NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:@"://"]];
        if (url == nil) {
            continue;
        }
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return YES;
        }
    }
    return NO;
}

BOOL BolaIsAppInstalled(NSString *bundleID) {
    if (bundleID.length == 0) {
        return NO;
    }
    id workspace = lswWorkspace();
    if (workspace == nil) {
        return NO;
    }
    SEL sel = NSSelectorFromString(@"applicationIsInstalled:");
    if ([workspace respondsToSelector:sel]) {
        return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, sel, bundleID);
    }
    return NO;
}
