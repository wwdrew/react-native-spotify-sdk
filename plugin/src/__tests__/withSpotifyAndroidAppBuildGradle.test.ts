import { injectSpotifyManifestPlaceholders } from '../android/withSpotifyAndroidAppBuildGradle';

describe('injectSpotifyManifestPlaceholders', () => {
  const spotifyConfig = {
    clientID: 'abc123',
    scheme: 'my-app',
    host: 'authenticate',
    redirectPath: '/callback',
  };

  it('injects manifest placeholders into defaultConfig', () => {
    const input = `android {
  defaultConfig {
    applicationId "com.example.app"
  }
}
`;

    const output = injectSpotifyManifestPlaceholders(input, spotifyConfig);

    expect(output).toContain('spotifyClientId: "abc123"');
    expect(output).toContain(
      'spotifyRedirectUri: "my-app://authenticate/callback"'
    );
    expect(output).toContain('redirectSchemeName: "my-app"');
    expect(output).toContain('redirectHostName: "authenticate"');
    expect(output).toContain('redirectPathPattern: "/callback"');
  });

  it('does not inject a second time', () => {
    const input = `android {
  defaultConfig {
    applicationId "com.example.app"
  }
}
`;

    const once = injectSpotifyManifestPlaceholders(input, spotifyConfig);
    const twice = injectSpotifyManifestPlaceholders(once, spotifyConfig);
    const matches = twice.match(/spotifyClientId/g) ?? [];

    expect(matches).toHaveLength(1);
  });
});
