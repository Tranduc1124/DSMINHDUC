//
//  GameLauncher.h
//  opens another app (Free Fire) the same way Delta Proxy does:
//  LSApplicationWorkspace.defaultWorkspace -> openApplicationWithBundleID:
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Launches the app with the given bundle id. Returns YES when the private
/// API accepted the request. Must be called on the main thread.
BOOL BolaLaunchApp(NSString *bundleID);

/// YES when the app is installed (LSApplicationWorkspace applicationIsInstalled: fallback)
BOOL BolaIsAppInstalled(NSString *bundleID);

NS_ASSUME_NONNULL_END
