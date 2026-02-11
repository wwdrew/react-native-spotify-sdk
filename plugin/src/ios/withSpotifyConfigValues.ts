import { withInfoPlist } from '@expo/config-plugins';

import type { ConfigPlugin } from '@expo/config-plugins';
import type { SpotifyConfig } from '../types';

interface SpotifySDKConfig {
  [key: string]: string;
}

export const withSpotifyConfigValues: ConfigPlugin<SpotifyConfig> = (
  config,
  spotifyConfig
) =>
  withInfoPlist(config, (config) => {
    if (!config.modResults.ExpoSpotifySDK) {
      config.modResults.ExpoSpotifySDK = {};
    }

    const spotifySDKConfig = config.modResults
      .ExpoSpotifySDK as SpotifySDKConfig;

    Object.entries(spotifyConfig).forEach(([key, value]) => {
      spotifySDKConfig[key] = value;
    });

    return config;
  });
