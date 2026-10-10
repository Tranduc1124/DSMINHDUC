#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#define TSERVER_SDK_RELEASE_VERSION @"ios-theos-2.1.3-activation-terminal"
#define APICLIENT_HAS_TERMINAL_EVENTS 1

// ============================================================
// APIClient.h — add this header and libAPIClient.a to your
// tweak/dylib project. Configure the package token before starting
// the license check, then open your paid menu only in the callback.
// ============================================================

// Package token copied from the Packages page in the portal.
// You may set it here or call APIClientConfigure(@"pkg_...") in your source.
static NSString * const kAPIClientPackageToken = @"REPLACE_WITH_YOUR_PACKAGE_TOKEN";

// Runtime config bridge implemented inside libAPIClient.a.
// Return scheme is automatic; current key info is loaded from the device UUID/session.
FOUNDATION_EXTERN void APIClientConfigure(NSString * _Nullable packageToken);
FOUNDATION_EXTERN void APIClientStartAuthorization(dispatch_block_t _Nullable onAuthorized,
                                                    dispatch_block_t _Nullable onRevoked);
typedef void (^APIClientTerminalEventBlock)(NSDictionary *result);
/// Starts authorization and reports every SDK-owned terminal activation failure.
/// VALID continues through onAuthorized; lease loss continues through onRevoked.
FOUNDATION_EXTERN void APIClientStartAuthorizationWithEvents(
    dispatch_block_t _Nullable onAuthorized,
    dispatch_block_t _Nullable onRevoked,
    APIClientTerminalEventBlock _Nullable onTerminal
);
FOUNDATION_EXTERN BOOL APIClientPerformAuthorized(NSString * _Nullable capability,
                                                   dispatch_block_t _Nullable work,
                                                   dispatch_block_t _Nullable denied);
FOUNDATION_EXTERN void APIClientStart(dispatch_block_t _Nullable onPaid)
    __attribute__((deprecated("Use APIClientStartAuthorization + APIClientPerformAuthorized")));
FOUNDATION_EXTERN BOOL APIClientIsValid(void)
    __attribute__((deprecated("Use APIClientPerformAuthorized at each protected feature boundary")));

/// Forward the app delegate's URL callback. The SDK validates the scheme,
/// callback context, and session before refreshing authorization state.
FOUNDATION_EXTERN BOOL APIClientHandleOpenURL(NSURL * _Nullable url);

// Auto-apply the constant only when it is a real package token.
// This prevents a copied placeholder header from overwriting a valid APIClientConfigure(@"pkg_xxx") call.
NS_INLINE void APIClientSetup(void) {
    NSString *token = [kAPIClientPackageToken stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (token.length >= 24 && [token rangeOfString:@"REPLACE" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        APIClientConfigure(token);
    }
}

#ifndef APICLIENT_NO_AUTO_SETUP
__attribute__((constructor)) static void APIClientHeaderAutoSetup(void) {
    APIClientSetup();
}
#endif

@interface APIClient : NSObject

/// Call when your tweak/menu should be gated. onPaid runs after VALID auth.
+ (void)start:(dispatch_block_t _Nullable)onPaid;

/// Start lease authorization and receive revocation/expiry callbacks.
+ (void)startAuthorization:(dispatch_block_t _Nullable)onAuthorized
                 onRevoked:(dispatch_block_t _Nullable)onRevoked;

+ (void)startAuthorization:(dispatch_block_t _Nullable)onAuthorized
                 onRevoked:(dispatch_block_t _Nullable)onRevoked
                onTerminal:(APIClientTerminalEventBlock _Nullable)onTerminal;

/// Execute only while the live signed lease grants this capability.
+ (BOOL)performAuthorized:(NSString * _Nullable)capability
                     work:(dispatch_block_t _Nullable)work
                   denied:(dispatch_block_t _Nullable)denied;

/// Compatibility aliases for older sources. New integrations must use the
/// feature-boundary API above.
+ (void)paid:(dispatch_block_t _Nullable)onPaid
    __attribute__((deprecated("Use startAuthorization:onRevoked:")));

+ (BOOL)isValid
    __attribute__((deprecated("Use performAuthorized:work:denied:")));

/// Latest VALID license payload for this UUID/device. Useful for labels like
/// Key hiện tại, hạn còn lại, max devices. Returns cached data after auth.
+ (NSDictionary * _Nullable)currentKeyInfo;
+ (NSString *)currentKeyText;
+ (NSString *)currentKeyRemainingText;
+ (NSInteger)currentKeyMaxDevices;

@end

NS_ASSUME_NONNULL_END
