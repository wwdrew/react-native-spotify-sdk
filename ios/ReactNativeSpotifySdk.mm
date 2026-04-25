#import "ReactNativeSpotifySdk.h"
#import <SpotifyiOS/SpotifyiOS.h>
#import <objc/runtime.h>

static __weak id sCurrentSpotifyModule = nil;
static BOOL sDidSwizzleAppDelegate = NO;

@interface ReactNativeSpotifySdk () <SPTSessionManagerDelegate, SPTAppRemoteDelegate>
@property(nonatomic, strong) SPTConfiguration *configuration;
@property(nonatomic, strong) SPTSessionManager *sessionManager;
@property(nonatomic, strong) SPTAppRemote *appRemote;
@property(nonatomic, copy) RCTPromiseResolveBlock pendingResolve;
@property(nonatomic, copy) RCTPromiseRejectBlock pendingReject;
@property(nonatomic, copy) NSArray<NSString *> *pendingScopes;
@property(nonatomic, copy) RCTPromiseResolveBlock pendingConnectResolve;
@property(nonatomic, copy) RCTPromiseRejectBlock pendingConnectReject;
@property(nonatomic, copy) NSString *pendingInitialContextUri;
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

- (BOOL)isSpotifyAppInstalled {
  return [self isAvailable];
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
  self.appRemote = [[SPTAppRemote alloc] initWithConfiguration:self.configuration logLevel:SPTAppRemoteLogLevelNone];
  self.appRemote.delegate = (id<SPTAppRemoteDelegate>)self;
  self.pendingResolve = resolve;
  self.pendingReject = reject;
  self.pendingScopes = scopes;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.sessionManager initiateSessionWithScope:DeserializeSpotifyScopes(scopes) options:SPTDefaultAuthorizationOption campaign:nil];
  });
}

- (void)connect:(NSDictionary *)options
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject
{
  NSString *accessToken = options[@"accessToken"];
  if (accessToken.length == 0) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"connect requires accessToken", nil);
    return;
  }

  NSDictionary *spotifyConfig = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ExpoSpotifySDK"];
  NSString *clientID = spotifyConfig[@"clientID"];
  NSString *scheme = spotifyConfig[@"scheme"];
  NSString *host = spotifyConfig[@"host"];
  NSString *redirectPath = spotifyConfig[@"redirectPath"];
  NSString *redirectURLString = [NSString stringWithFormat:@"%@://%@%@", scheme, host, redirectPath ?: @""];
  NSURL *redirectURL = [NSURL URLWithString:redirectURLString];
  if (clientID.length == 0 || redirectURL == nil) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Missing Spotify iOS configuration in Info.plist.", nil);
    return;
  }

  self.configuration = [[SPTConfiguration alloc] initWithClientID:clientID redirectURL:redirectURL];
  self.appRemote = [[SPTAppRemote alloc] initWithConfiguration:self.configuration logLevel:SPTAppRemoteLogLevelNone];
  self.appRemote.delegate = (id<SPTAppRemoteDelegate>)self;
  self.appRemote.connectionParameters.accessToken = accessToken;
  self.pendingConnectResolve = resolve;
  self.pendingConnectReject = reject;
  self.pendingInitialContextUri = options[@"initialContextUri"];

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.appRemote connect];
  });
}

- (void)disconnect:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.appRemote.isConnected) {
      [self.appRemote disconnect];
    }
    resolve(nil);
  });
}

- (void)isConnected:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve(@(self.appRemote != nil && self.appRemote.isConnected));
}

- (void)play:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  NSString *uri = options[@"uri"];
  if (uri.length == 0) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"play requires uri", nil);
    return;
  }
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }

  [self.appRemote.playerAPI play:uri callback:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
      return;
    }

    NSNumber *position = options[@"positionMs"];
    if (position != nil) {
      [self.appRemote.playerAPI seekToPosition:position.integerValue callback:^(id  _Nullable seekResult, NSError * _Nullable seekError) {
        if (seekError != nil) {
          reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", seekError.localizedDescription, seekError);
        } else {
          resolve(nil);
        }
      }];
      return;
    }

    resolve(nil);
  }];
}

- (void)pause:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI pause:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)resume:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI resume:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)skipNext:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI skipToNext:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)skipPrevious:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI skipToPrevious:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)seekTo:(double)positionMs resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI seekToPosition:(NSInteger)positionMs callback:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)setShuffle:(BOOL)enabled resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }
  [self.appRemote.playerAPI setShuffle:enabled callback:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)setRepeatMode:(NSString *)mode resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }

  SPTAppRemotePlaybackOptionsRepeatMode repeatMode = SPTAppRemotePlaybackOptionsRepeatModeOff;
  if ([mode isEqualToString:@"track"]) {
    repeatMode = SPTAppRemotePlaybackOptionsRepeatModeTrack;
  } else if ([mode isEqualToString:@"context"]) {
    repeatMode = SPTAppRemotePlaybackOptionsRepeatModeContext;
  }

  [self.appRemote.playerAPI setRepeatMode:repeatMode callback:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
    } else {
      resolve(nil);
    }
  }];
}

- (void)getPlayerState:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (self.appRemote == nil || !self.appRemote.isConnected) {
    reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", @"Not connected to Spotify App Remote.", nil);
    return;
  }

  [self.appRemote.playerAPI getPlayerState:^(id  _Nullable result, NSError * _Nullable error) {
    if (error != nil) {
      reject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription, error);
      return;
    }

    SPTAppRemotePlayerState *state = (SPTAppRemotePlayerState *)result;
    NSDictionary *serialized = @{
      @"trackUri": state.track.URI ?: [NSNull null],
      @"trackName": state.track.name ?: [NSNull null],
      @"artistName": state.track.artist.name ?: [NSNull null],
      @"albumName": state.track.album.name ?: [NSNull null],
      @"durationMs": @(state.track.duration),
      @"positionMs": @(state.playbackPosition),
      @"isPaused": @(state.isPaused),
      @"shuffle": @(NO),
      @"repeatMode": @"off",
      @"contextUri": [NSNull null],
    };
    resolve(serialized);
  }];
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

- (void)appRemoteDidEstablishConnection:(SPTAppRemote *)appRemote
{
  if (self.pendingInitialContextUri.length > 0) {
    [appRemote.playerAPI play:self.pendingInitialContextUri callback:nil];
  }

  if (self.pendingConnectResolve != nil) {
    self.pendingConnectResolve(nil);
  }
  self.pendingConnectResolve = nil;
  self.pendingConnectReject = nil;
  self.pendingInitialContextUri = nil;
}

- (void)appRemote:(SPTAppRemote *)appRemote didFailConnectionAttemptWithError:(NSError *)error
{
  if (self.pendingConnectReject != nil) {
    self.pendingConnectReject(@"ERR_REACT_NATIVE_SPOTIFY_SDK", error.localizedDescription ?: @"Failed to connect to Spotify App Remote.", error);
  }
  self.pendingConnectResolve = nil;
  self.pendingConnectReject = nil;
  self.pendingInitialContextUri = nil;
}

- (void)appRemote:(SPTAppRemote *)appRemote didDisconnectWithError:(NSError *)error
{
  self.pendingConnectResolve = nil;
  self.pendingConnectReject = nil;
  self.pendingInitialContextUri = nil;
}

@end
