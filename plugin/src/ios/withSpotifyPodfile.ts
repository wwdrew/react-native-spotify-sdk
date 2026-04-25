import { withDangerousMod } from '@expo/config-plugins';
import * as fs from 'fs';
import * as path from 'path';
import type { ConfigPlugin } from '@expo/config-plugins';

const POD_BLOCK_START = '# @wwdrew/react-native-spotify-sdk begin';
const POD_BLOCK_END = '# @wwdrew/react-native-spotify-sdk end';
const SPOTIFY_POD_REGEX = /^\s*pod\s+['"]SpotifyiOS['"]/m;
const LEGACY_HELPER_CALL_REGEX =
  /^\s*install_spotify_sdk_pods!\s*[\r\n]?/gm;
const LEGACY_REQUIRE_REGEX =
  /^\s*require\s+\(File\.exist\?\(File\.expand_path\('\.\.\/\.\.\/ios\/spotify_sdk_pods\.rb', __dir__\)\).*$/gm;

function createPodBlock(): string {
  const spotifyPodLine =
    "pod 'SpotifyiOS', :podspec => (File.exist?(File.expand_path('../../podspecs/SpotifyiOS.podspec', __dir__)) ? File.expand_path('../../podspecs/SpotifyiOS.podspec', __dir__) : File.expand_path('../node_modules/@wwdrew/react-native-spotify-sdk/podspecs/SpotifyiOS.podspec', __dir__))";

  return [POD_BLOCK_START, `  ${spotifyPodLine}`, POD_BLOCK_END].join('\n');
}

function replaceManagedBlockIfPresent(
  podfileContents: string,
  replacement: string
): string | null {
  const blockRegex = new RegExp(`${POD_BLOCK_START}[\\s\\S]*?${POD_BLOCK_END}`, 'm');
  if (!blockRegex.test(podfileContents)) {
    return null;
  }

  return podfileContents.replace(blockRegex, replacement);
}

function insertPodBlock(
  podfileContents: string,
  podBlock: string
): string {
  const useExpoRegex = /^\s*use_expo_modules!\s*$/m;
  const useExpoMatch = podfileContents.match(useExpoRegex);
  if (useExpoMatch?.index !== undefined) {
    const insertAt = useExpoMatch.index;
    return (
      `${podfileContents.slice(0, insertAt)}` +
      `${podBlock}\n` +
      `${podfileContents.slice(insertAt)}`
    );
  }

  const firstTargetRegex = /^target\s+['"][^'"]+['"]\s+do[^\n]*$/m;
  const targetMatch = podfileContents.match(firstTargetRegex);
  if (targetMatch?.index !== undefined) {
    const insertAt = targetMatch.index + targetMatch[0].length;
    return (
      `${podfileContents.slice(0, insertAt)}\n` +
      `${podBlock}\n` +
      `${podfileContents.slice(insertAt)}`
    );
  }

  throw new Error(
    'Unable to find safe insertion point in Podfile for SpotifyiOS pod.'
  );
}

function validateManagedPodState(podfileContents: string): void {
  const managedStartCount = (
    podfileContents.match(new RegExp(POD_BLOCK_START, 'g')) ?? []
  ).length;
  const managedEndCount = (
    podfileContents.match(new RegExp(POD_BLOCK_END, 'g')) ?? []
  ).length;
  const spotifyMatches = podfileContents.match(
    /^\s*pod\s+['"]SpotifyiOS['"][^\n]*$/gm
  );

  if (managedStartCount !== managedEndCount) {
    throw new Error('Spotify Podfile managed markers are imbalanced.');
  }

  if (managedStartCount > 1) {
    throw new Error(
      'Spotify Podfile managed marker block should appear at most once.'
    );
  }

  if ((spotifyMatches?.length ?? 0) > 1) {
    throw new Error(
      'Detected multiple SpotifyiOS pod declarations in Podfile. Please keep exactly one.'
    );
  }
}

export function transformSpotifyPodfile(podfile: string): string {
  let nextPodfile = podfile;
  const podBlock = createPodBlock();

  nextPodfile = nextPodfile
    .replace(LEGACY_HELPER_CALL_REGEX, '')
    .replace(LEGACY_REQUIRE_REGEX, '');

  const replaced = replaceManagedBlockIfPresent(nextPodfile, podBlock);
  if (replaced !== null) {
    nextPodfile = replaced;
    validateManagedPodState(nextPodfile);
    return nextPodfile;
  }

  if (!SPOTIFY_POD_REGEX.test(nextPodfile)) {
    nextPodfile = insertPodBlock(nextPodfile, podBlock);
  }

  validateManagedPodState(nextPodfile);
  return nextPodfile;
}

const withSpotifyPodfile: ConfigPlugin = (config) => {
  return withDangerousMod(config, [
    'ios',
    async (config) => {
      const podfilePath = path.join(
        config.modRequest.platformProjectRoot,
        'Podfile'
      );

      const podfile = fs.readFileSync(podfilePath, 'utf8');
      const nextPodfile = transformSpotifyPodfile(podfile);

      if (nextPodfile !== podfile) {
        fs.writeFileSync(podfilePath, nextPodfile);
      }

      return config;
    },
  ]);
};

export default withSpotifyPodfile;
