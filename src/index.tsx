import ReactNativeSpotifySdk, {
  type SpotifyScope,
  type SpotifySession,
} from './NativeReactNativeSpotifySdk';

export interface AuthenticateConfig {
  scopes: Array<SpotifyScope>;
  tokenSwapURL?: string;
  tokenRefreshURL?: string;
}

export function isAvailable(): boolean {
  return ReactNativeSpotifySdk.isAvailable();
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
