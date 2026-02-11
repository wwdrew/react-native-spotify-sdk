import { withAppBuildGradle } from '@expo/config-plugins';
import type { ConfigPlugin } from '@expo/config-plugins';
import type { SpotifyConfig } from '../types';

export const withSpotifyAndroidAppBuildGradle: ConfigPlugin<SpotifyConfig> = (
  config,
  { clientID, scheme, host, redirectPath }
) => {
  return withAppBuildGradle(config, (config) => {
    const contents = config.modResults.contents;

    if (contents.includes('spotifyClientId')) {
      return config;
    }

    const start = contents.indexOf('defaultConfig');
    if (start === -1) return config;

    const open = contents.indexOf('{', start);
    if (open === -1) return config;

    let depth = 1;
    let i = open + 1;

    while (i < contents.length && depth > 0) {
      if (contents[i] === '{') depth++;
      else if (contents[i] === '}') depth--;
      i++;
    }

    if (depth !== 0) return config;

    const injection = `
        manifestPlaceholders += [
            spotifyClientId: "${clientID}",
            redirectSchemeName: "${scheme}",
            redirectHostName: "${host}",
            redirectPathPattern: "${redirectPath ? redirectPath : '.*'}"
        ]
`;

    const updated =
      contents.slice(0, i - 1) + injection + contents.slice(i - 1);

    config.modResults.contents = updated;
    return config;
  });
};
