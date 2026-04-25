import { withSpotifySdkConfig } from '../index';

jest.mock('../resolveSpotifyArtifacts', () => ({
  resolveSpotifyArtifactsOnce: jest.fn(),
}));

describe('withSpotifySdkConfig validation', () => {
  const baseConfig = { name: 'test-app', slug: 'test-app' };

  it('throws when host is missing', () => {
    expect(() =>
      withSpotifySdkConfig(baseConfig as any, {
        clientID: 'id',
        scheme: 'scheme',
      } as any)
    ).toThrow('Missing required Spotify config value: host');
  });

  it('throws when scheme is missing', () => {
    expect(() =>
      withSpotifySdkConfig(baseConfig as any, {
        clientID: 'id',
        host: 'authenticate',
      } as any)
    ).toThrow('Missing required Spotify config value: scheme');
  });

  it('throws when clientID is missing', () => {
    expect(() =>
      withSpotifySdkConfig(baseConfig as any, {
        host: 'authenticate',
        scheme: 'scheme',
      } as any)
    ).toThrow('Missing required Spotify config value: clientID');
  });
});
