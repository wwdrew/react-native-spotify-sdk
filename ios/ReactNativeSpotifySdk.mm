#import "ReactNativeSpotifySdk.h"
#import <SpotifyiOS/SpotifyiOS.h>
#import <objc/runtime.h>

static __weak id sCurrentSpotifyModule = nil;
static BOOL sDidSwizzleAppDelegate = NO;

@interface ReactNativeSpotifySdk () <SPTSessionManagerDelegate>
@property(nonatomic, strong) SPTConfiguration *configuration;
@property(nonatomic, strong) SPTSessionManager *sessionManager;
@property(nonatomic, copy) RCTPromiseResolveBlock pendingResolve;
@property(nonatomic, copy) RCTPromiseRejectBlock pendingReject;
@property(nonatomic, copy) NSArray<NSString *> *pendingScopes;
@end

static BOOL HandleSpotifyOpenURL(UIApplication *application, NSURL *url, NSDictionary *options) {
  ReactNativeSpotifySdk *module = (ReactNativeSpotifySdk *)sCurrentSpotifyModule;
  if (module.sessionManager == nil) {
    return NO;
  }

  return [module.sessionManager application:application openURL:url options:options];
}

static BOOL SwizzledApplicationOpenURL(id selfObj, SEL _cmd, UIApplication *application, NSURL *url, NSDictionary *options) {
  BOOL handledBySpotify = HandleSpotifyOpenURL(application, url, options);
  BOOL handledByOriginal = NO;

  SEL swizzledSelector = NSSelectorFromString(@"rnSpotify_application:openURL:options:");
  if ([selfObj respondsToSelector:swizzledSelector]) {
    typedef BOOL (*SwizzledOpenURLImp)(id, SEL, UIApplication *, NSURL *, NSDictionary *);
    SwizzledOpenURLImp imp = (SwizzledOpenURLImp)[selfObj methodForSelector:swizzledSelector];
    handledByOriginal = imp(selfObj, swizzledSelector, application, url, options);
  }

  return handledBySpotify || handledByOriginal;
}

static void SwizzleAppDelegateOpenURL(void) {
  if (sDidSwizzleAppDelegate) {
    return;
  }

  id<UIApplicationDelegate> appDelegate = UIApplication.sharedApplication.delegate;
  if (appDelegate == nil) {
    return;
  }

  Class appDelegateClass = [appDelegate class];
  SEL originalSelector = @selector(application:openURL:options:);
  Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
  if (originalMethod == nil) {
    return;
  }

  IMP newImp = (IMP)SwizzledApplicationOpenURL;
  const char *typeEncoding = method_getTypeEncoding(originalMethod);
  SEL swizzledSelector = NSSelectorFromString(@"rnSpotify_application:openURL:options:");
  if (!class_addMethod(appDelegateClass, swizzledSelector, method_getImplementation(originalMethod), typeEncoding)) {
    return;
  }

  class_replaceMethod(appDelegateClass, originalSelector, newImp, typeEncoding);
  sDidSwizzleAppDelegate = YES;
}

static NSDictionary<NSString *, NSNumber *> *SpotifyScopeMap(void) {
  return @{
    @"playlist-read-private": @(SPTScopePlaylistReadPrivate),
    @"playlist-read-collaborative": @(SPTScopePlaylistReadCollaborative),
    @"playlist-modify-public": @(SPTScopePlaylistModifyPublic),
    @"playlist-modify-private": @(SPTScopePlaylistModifyPrivate),
    @"user-follow-read": @(SPTScopeUserFollowRead),
    @"user-follow-modify": @(SPTScopeUserFollowModify),
    @"user-library-read": @(SPTScopeUserLibraryRead),
    @"user-library-modify": @(SPTScopeUserLibraryModify),
    @"user-read-email": @(SPTScopeUserReadEmail),
    @"user-read-private": @(SPTScopeUserReadPrivate),
    @"user-top-read": @(SPTScopeUserTopRead),
    @"ugc-image-upload": @(SPTScopeUGCImageUpload),
    @"streaming": @(SPTScopeStreaming),
    @"app-remote-control": @(SPTScopeAppRemoteControl),
    @"user-read-playback-state": @(SPTScopeUserReadPlaybackState),
    @"user-modify-playback-state": @(SPTScopeUserModifyPlaybackState),
    @"user-read-currently-playing": @(SPTScopeUserReadCurrentlyPlaying),
    @"user-read-recently-played": @(SPTScopeUserReadRecentlyPlayed),
  };
}

static SPTScope DeserializeSpotifyScopes(NSArray<NSString *> *scopes) {
  NSDictionary<NSString *, NSNumber *> *scopeMap = SpotifyScopeMap();
  SPTScope result = 0;
  for (NSString *scope in scopes) {
    NSNumber *scopeValue = scopeMap[scope];
    if (scopeValue != nil) {
      result |= scopeValue.unsignedIntegerValue;
    }
  }
  return result;
}

static NSArray<NSString *> *SerializeSpotifyScopes(SPTScope scopes) {
  NSDictionary<NSString *, NSNumber *> *scopeMap = SpotifyScopeMap();
  NSMutableArray<NSString *> *serialized = [NSMutableArray new];
  [scopeMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
    if ((scopes & value.unsignedIntegerValue) == value.unsignedIntegerValue) {
      [serialized addObject:key];
    }
  }];
  return serialized;
}

@implementation ReactNativeSpotifySdk

- (instancetype)init {
  self = [super init];
  if (self) {
    sCurrentSpotifyModule = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      SwizzleAppDelegateOpenURL();
    });
  }
  return self;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeReactNativeSpotifySdkSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"ReactNativeSpotifySdk";
}

- (BOOL)isAvailable {
  if (self.sessionManager == nil) {
    return NO;
  }

  __block BOOL installed = NO;
  dispatch_sync(dispatch_get_main_queue(), ^{
    installed = self.sessionManager.isSpotifyAppInstalled;
  });
  return installed;
}

- (void)authenticate:(NSArray<NSString *> *)scopes
        tokenSwapURL:(NSString * _Nullable)tokenSwapURL
     tokenRefreshURL:(NSString * _Nullable)tokenRefreshURL
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject
{
  if (scopes.count == 0) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"scopes are required", nil);
    return;
  }

  NSDictionary *spotifyConfig = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ExpoSpotifySDK"];
  NSString *clientID = spotifyConfig[@"clientID"];
  NSString *scheme = spotifyConfig[@"scheme"];
  NSString *host = spotifyConfig[@"host"];
  NSString *redirectPath = spotifyConfig[@"redirectPath"];

  if (clientID.length == 0 || scheme.length == 0 || host.length == 0) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Missing Spotify iOS configuration in Info.plist.", nil);
    return;
  }

  NSString *redirectURLString = [NSString stringWithFormat:@"%@://%@%@", scheme, host, redirectPath ?: @""];
  NSURL *redirectURL = [NSURL URLWithString:redirectURLString];
  if (redirectURL == nil) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Invalid Spotify redirect URL configuration.", nil);
    return;
  }

  self.configuration = [[SPTConfiguration alloc] initWithClientID:clientID redirectURL:redirectURL];
  if (tokenSwapURL.length > 0) {
    self.configuration.tokenSwapURL = [NSURL URLWithString:tokenSwapURL];
  }
  if (tokenRefreshURL.length > 0) {
    self.configuration.tokenRefreshURL = [NSURL URLWithString:tokenRefreshURL];
  }

  self.sessionManager = [[SPTSessionManager alloc] initWithConfiguration:self.configuration delegate:self];
  self.pendingResolve = resolve;
  self.pendingReject = reject;
  self.pendingScopes = scopes;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.sessionManager initiateSessionWithScope:DeserializeSpotifyScopes(scopes) options:SPTDefaultAuthorizationOption campaign:nil];
  });
}

- (void)sessionManager:(SPTSessionManager *)manager didInitiateSession:(SPTSession *)session
{
  if (self.pendingResolve == nil) {
    return;
  }

  self.pendingResolve(@{
    @"accessToken": session.accessToken ?: @"",
    @"refreshToken": session.refreshToken ?: [NSNull null],
    @"expirationDate": @((NSInteger)(session.expirationDate.timeIntervalSince1970 * 1000)),
    @"scopes": SerializeSpotifyScopes(session.scope),
  });
  self.pendingResolve = nil;
  self.pendingReject = nil;
}

- (void)sessionManager:(SPTSessionManager *)manager didFailWithError:(NSError *)error
{
  if (self.pendingReject != nil) {
    self.pendingReject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription ?: @"Spotify authentication failed.", error);
  }
  self.pendingResolve = nil;
  self.pendingReject = nil;
}

- (void)sessionManager:(SPTSessionManager *)manager didRenewSession:(SPTSession *)session
{
  if (self.pendingResolve == nil) {
    return;
  }

  self.pendingResolve(@{
    @"accessToken": session.accessToken ?: @"",
    @"refreshToken": session.refreshToken ?: [NSNull null],
    @"expirationDate": @((NSInteger)(session.expirationDate.timeIntervalSince1970 * 1000)),
    @"scopes": SerializeSpotifyScopes(session.scope),
  });
  self.pendingResolve = nil;
  self.pendingReject = nil;
}

@end
