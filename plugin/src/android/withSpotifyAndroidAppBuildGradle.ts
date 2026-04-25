import { withAppBuildGradle } from '@expo/config-plugins';
import type { ConfigPlugin } from '@expo/config-plugins';
import type { SpotifyConfig } from '../types';

export function injectSpotifyManifestPlaceholders(
  contents: string,
  { clientID, scheme, host, redirectPath }: SpotifyConfig
): string {
  if (contents.includes('spotifyClientId')) {
    return contents;
  }

  const start = contents.indexOf('defaultConfig');
  if (start === -1) return contents;

  const open = contents.indexOf('{', start);
  if (open === -1) return contents;

  let depth = 1;
  let i = open + 1;

  while (i < contents.length && depth > 0) {
    if (contents[i] === '{') depth++;
    else if (contents[i] === '}') depth--;
    i++;
  }

  if (depth !== 0) return contents;

  const injection = `
        manifestPlaceholders += [
            spotifyClientId: "${clientID}",
            redirectSchemeName: "${scheme}",
            redirectHostName: "${host}",
            redirectPathPattern: "${redirectPath ? redirectPath : '.*'}"
        ]
`;

  return contents.slice(0, i - 1) + injection + contents.slice(i - 1);
}

export const withSpotifyAndroidAppBuildGradle: ConfigPlugin<SpotifyConfig> = (
  config,
  spotifyConfig
) => {
  return withAppBuildGradle(config, (config) => {
    config.modResults.contents = injectSpotifyManifestPlaceholders(
      config.modResults.contents,
      spotifyConfig
    );
    return config;
  });
};
