import { spawnSync } from 'child_process';
import * as path from 'path';

let didResolve = false;

function getPackageRoot(): string {
  return path.resolve(__dirname, '../../');
}

export function resolveSpotifyArtifactsOnce(): void {
  if (didResolve) {
    return;
  }

  const packageRoot = getPackageRoot();
  const resolverPath = path.join(
    packageRoot,
    'scripts',
    'resolve-spotify-artifacts.js'
  );

  const result = spawnSync(process.execPath, [resolverPath], {
    cwd: packageRoot,
    stdio: 'inherit',
  });

  if (result.status !== 0) {
    throw new Error(
      'Failed to resolve Spotify native artifacts. Re-run `yarn spotify:artifacts:resolve` and try prebuild again.'
    );
  }

  didResolve = true;
}
