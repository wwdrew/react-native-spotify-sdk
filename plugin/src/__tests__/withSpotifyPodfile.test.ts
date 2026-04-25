import { transformSpotifyPodfile } from '../ios/withSpotifyPodfile';

describe('transformSpotifyPodfile', () => {
  it('injects require and install block in Expo-style Podfile', () => {
    const input = `require 'json'
platform :ios, '15.1'
prepare_react_native_project!

target 'Example' do
  use_expo_modules!
end
`;

    const output = transformSpotifyPodfile(input);

    expect(output).toContain(
      '# @wwdrew/react-native-spotify-sdk require begin'
    );
    expect(output).toContain(
      '# @wwdrew/react-native-spotify-sdk install begin'
    );
    expect(output).toContain('install_spotify_sdk_pods!');
    expect(output.indexOf('install_spotify_sdk_pods!')).toBeLessThan(
      output.indexOf('use_expo_modules!')
    );
  });

  it('is idempotent across repeated transforms', () => {
    const input = `require 'json'
platform :ios, '15.1'
prepare_react_native_project!

target 'Example' do
  use_expo_modules!
end
`;

    const once = transformSpotifyPodfile(input);
    const twice = transformSpotifyPodfile(once);

    expect(twice).toEqual(once);
  });

  it('does not add install call when manual Spotify pod exists', () => {
    const input = `require 'json'
platform :ios, '15.1'

target 'Example' do
  pod 'SpotifyiOS', :path => '../vendor/SpotifyiOS'
  use_expo_modules!
end
`;

    const output = transformSpotifyPodfile(input);
    const installMatches = output.match(/install_spotify_sdk_pods!/g) ?? [];

    expect(installMatches).toHaveLength(0);
    expect(output).toContain(
      '# @wwdrew/react-native-spotify-sdk require begin'
    );
  });
});
