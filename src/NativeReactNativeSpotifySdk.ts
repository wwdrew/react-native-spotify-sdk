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

export interface Spec extends TurboModule {
  isAvailable(): boolean;
  authenticate(
    scopes: Array<SpotifyScope>,
    tokenSwapURL: string | null,
    tokenRefreshURL: string | null
  ): Promise<SpotifySession>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('ReactNativeSpotifySdk');
