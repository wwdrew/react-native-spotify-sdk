import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type SpotifyScope =
  | 'ugc-image-upload'
  | 'user-read-playback-state'
  | 'user-modify-playback-state'
  | 'user-read-currently-playing'
  | 'app-remote-control'
  | 'streaming'
  | 'playlist-read-private'
  | 'playlist-read-collaborative'
  | 'playlist-modify-private'
  | 'playlist-modify-public'
  | 'user-follow-modify'
  | 'user-follow-read'
  | 'user-top-read'
  | 'user-read-recently-played'
  | 'user-library-modify'
  | 'user-library-read'
  | 'user-read-email'
  | 'user-read-private';

export type SpotifySession = {
  accessToken: string;
  refreshToken: string | null;
  expirationDate: number;
  scopes: Array<SpotifyScope>;
};

export type RepeatMode = 'off' | 'context' | 'track';

export type ConnectOptions = {
  accessToken: string;
  initialContextUri?: string;
};

export type PlayOptions = {
  uri: string;
  index?: number;
  positionMs?: number;
};

export type SpotifyPlayerState = {
  trackUri?: string;
  trackName?: string;
  artistName?: string;
  albumName?: string;
  durationMs: number;
  positionMs: number;
  isPaused: boolean;
  shuffle: boolean;
  repeatMode: RepeatMode;
  contextUri?: string;
};

export interface Spec extends TurboModule {
  isSpotifyAppInstalled(): boolean;
  authenticate(
    scopes: Array<SpotifyScope>,
    tokenSwapURL: string | null,
    tokenRefreshURL: string | null
  ): Promise<SpotifySession>;
  connect(options: ConnectOptions): Promise<void>;
  disconnect(): Promise<void>;
  isConnected(): Promise<boolean>;
  play(options: PlayOptions): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  skipNext(): Promise<void>;
  skipPrevious(): Promise<void>;
  seekTo(positionMs: number): Promise<void>;
  setShuffle(enabled: boolean): Promise<void>;
  setRepeatMode(mode: RepeatMode): Promise<void>;
  getPlayerState(): Promise<SpotifyPlayerState>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('ReactNativeSpotifySdk');
