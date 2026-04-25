import ReactNativeSpotifySdk, {
  type ConnectOptions,
  type PlayOptions,
  type RepeatMode,
  type SpotifyPlayerState,
  type SpotifyScope,
  type SpotifySession,
} from './NativeReactNativeSpotifySdk';

export interface AuthenticateConfig {
  scopes: Array<SpotifyScope>;
  tokenSwapURL?: string;
  tokenRefreshURL?: string;
}

export function isSpotifyAppInstalled(): boolean {
  return ReactNativeSpotifySdk.isSpotifyAppInstalled();
}

export async function authenticateAsync(
  config: AuthenticateConfig
): Promise<SpotifySession> {
  if (!config.scopes?.length) {
    throw new Error('scopes are required');
  }

  return ReactNativeSpotifySdk.authenticate(
    config.scopes,
    config.tokenSwapURL ?? null,
    config.tokenRefreshURL ?? null
  );
}

export function connect(options: ConnectOptions): Promise<void> {
  return ReactNativeSpotifySdk.connect(options);
}

export function disconnect(): Promise<void> {
  return ReactNativeSpotifySdk.disconnect();
}

export function isConnected(): Promise<boolean> {
  return ReactNativeSpotifySdk.isConnected();
}

export function play(options: PlayOptions): Promise<void> {
  return ReactNativeSpotifySdk.play(options);
}

export function pause(): Promise<void> {
  return ReactNativeSpotifySdk.pause();
}

export function resume(): Promise<void> {
  return ReactNativeSpotifySdk.resume();
}

export function skipNext(): Promise<void> {
  return ReactNativeSpotifySdk.skipNext();
}

export function skipPrevious(): Promise<void> {
  return ReactNativeSpotifySdk.skipPrevious();
}

export function seekTo(positionMs: number): Promise<void> {
  return ReactNativeSpotifySdk.seekTo(positionMs);
}

export function setShuffle(enabled: boolean): Promise<void> {
  return ReactNativeSpotifySdk.setShuffle(enabled);
}

export function setRepeatMode(mode: RepeatMode): Promise<void> {
  return ReactNativeSpotifySdk.setRepeatMode(mode);
}

export function getPlayerState(): Promise<SpotifyPlayerState> {
  return ReactNativeSpotifySdk.getPlayerState();
}
