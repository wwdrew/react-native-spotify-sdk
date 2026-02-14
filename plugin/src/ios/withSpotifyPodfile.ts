import { ConfigPlugin, withDangerousMod } from '@expo/config-plugins';
import * as fs from 'fs';
import * as path from 'path';

const withSpotifyPodfile: ConfigPlugin = (config) => {
  return withDangerousMod(config, [
    'ios',
    async (config) => {
      const podfilePath = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile'
      );

      let podfile = fs.readFileSync(podfilePath, 'utf8');

      // Use File.expand_path for absolute path
      const spotifyPodLine =
        "pod 'SpotifyiOS', :podspec => File.exist?('../../podspecs') ? '../../podspecs' : '../node_modules/@wwdrew/react-native-spotify-sdk/podspecs'";

      // Only add if not already present
      if (!podfile.includes("pod 'SpotifyiOS'")) {
        // Add after the platform line
        podfile = podfile.replace(
          /(platform :ios.*)/,
          `$1\n\n  ${spotifyPodLine}`
        );

        fs.writeFileSync(podfilePath, podfile);
      }

      return config;
    },
  ]);
};

export default withSpotifyPodfile;
