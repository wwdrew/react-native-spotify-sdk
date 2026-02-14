import { withSpotifyAndroidAppBuildGradle } from './android/withSpotifyAndroidAppBuildGradle';
import { withSpotifyConfigValues } from './ios/withSpotifyConfigValues';
import { withSpotifyQueryScheme } from './ios/withSpotifyQueryScheme';
import { withSpotifyURLScheme } from './ios/withSpotifyURLScheme';

import type { ConfigPlugin } from '@expo/config-plugins';
import type { SpotifyConfig } from './types';
import withSpotifyPodfile from './ios/withSpotifyPodfile';

export const withSpotifySdkConfig: ConfigPlugin<SpotifyConfig> = (
  config,
  spotifyConfig
) => {
  if (!spotifyConfig.host) {
    throw new Error('Missing required Spotify config value: host');
  }

  if (!spotifyConfig.scheme) {
    throw new Error('Missing required Spotify config value: scheme');
  }

  if (!spotifyConfig.clientID) {
    throw new Error('Missing required Spotify config value: clientID');
  }

  // Android specific
  config = withSpotifyAndroidAppBuildGradle(config, spotifyConfig);

  // iOS specific
  config = withSpotifyConfigValues(config, spotifyConfig);
  config = withSpotifyQueryScheme(config, spotifyConfig);
  config = withSpotifyURLScheme(config, spotifyConfig);
  config = withSpotifyPodfile(config);

  return config;
};

export default withSpotifySdkConfig;
