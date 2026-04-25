import { transformSpotifyPodfile } from '../ios/withSpotifyPodfile';

describe('transformSpotifyPodfile', () => {
  it('injects Spotify pod block in Expo-style Podfile', () => {
    const input = `require 'json'
platform :ios, '15.1'
prepare_react_native_project!

target 'Example' do
  use_expo_modules!
end
`;

    const output = transformSpotifyPodfile(input);

    expect(output).toContain('# @wwdrew/react-native-spotify-sdk begin');
    expect(output).toContain("pod 'SpotifyiOS', :podspec =>");
    expect(output.indexOf("pod 'SpotifyiOS', :podspec =>")).toBeLessThan(
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

  it('does not add managed block when manual Spotify pod exists', () => {
    const input = `require 'json'
platform :ios, '15.1'

target 'Example' do
  pod 'SpotifyiOS', :path => '../vendor/SpotifyiOS'
  use_expo_modules!
end
`;

    const output = transformSpotifyPodfile(input);
    expect(output).not.toContain('# @wwdrew/react-native-spotify-sdk begin');
    expect(output).not.toContain("pod 'SpotifyiOS', :podspec =>");
  });
});
