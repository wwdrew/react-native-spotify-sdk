#!/usr/bin/env node

/* eslint-disable no-console */
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const MANIFEST_PATH = path.join(REPO_ROOT, 'spotify-artifacts.json');
const DOWNLOAD_TIMEOUT_MS = 30000;
const MAX_ATTEMPTS = 3;

function readManifest() {
  return JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
}

function sha256ForFile(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

function downloadWithRedirects(url, destination, redirectCount = 0) {
  return new Promise((resolve, reject) => {
    if (redirectCount > 8) {
      reject(new Error(`Too many redirects while downloading ${url}`));
      return;
    }

    const request = https.get(url, (response) => {
      const statusCode = response.statusCode || 0;

      if (
        statusCode >= 300 &&
        statusCode < 400 &&
        typeof response.headers.location === 'string'
      ) {
        response.resume();
        downloadWithRedirects(response.headers.location, destination, redirectCount + 1)
          .then(resolve)
          .catch(reject);
        return;
      }

      if (statusCode !== 200) {
        response.resume();
        reject(new Error(`Failed to download ${url}. HTTP ${statusCode}`));
        return;
      }

      const tempPath = `${destination}.tmp`;
      const fileStream = fs.createWriteStream(tempPath);
      response.pipe(fileStream);

      fileStream.on('finish', () => {
        fileStream.close(() => {
          fs.renameSync(tempPath, destination);
          resolve();
        });
      });

      fileStream.on('error', (error) => {
        fileStream.close(() => {
          try {
            fs.unlinkSync(tempPath);
          } catch (_) {}
          reject(error);
        });
      });
    });

    request.setTimeout(DOWNLOAD_TIMEOUT_MS, () => {
      request.destroy(
        new Error(
          `Timed out after ${DOWNLOAD_TIMEOUT_MS}ms while downloading ${url}`
        )
      );
    });

    request.on('error', reject);
  });
}

async function downloadWithRetries(url, destination) {
  let lastError = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      await downloadWithRedirects(url, destination);
      return;
    } catch (error) {
      lastError = error;
      if (attempt < MAX_ATTEMPTS) {
        console.log(
          `spotify-artifacts: download attempt ${attempt}/${MAX_ATTEMPTS} failed, retrying...`
        );
      }
    }
  }

  throw lastError;
}

async function resolveAndroidAppRemoteAar(artifact) {
  const destination = path.join(REPO_ROOT, artifact.outputPath);
  fs.mkdirSync(path.dirname(destination), { recursive: true });

  if (fs.existsSync(destination)) {
    const currentHash = sha256ForFile(destination);
    if (currentHash === artifact.sha256) {
      console.log(`spotify-artifacts: cache hit (${artifact.outputPath})`);
      return destination;
    }
    console.log(
      `spotify-artifacts: checksum mismatch for cached file, redownloading (${artifact.outputPath})`
    );
  } else {
    console.log(`spotify-artifacts: downloading ${artifact.url}`);
  }

  await downloadWithRetries(artifact.url, destination);
  const downloadedHash = sha256ForFile(destination);

  if (downloadedHash !== artifact.sha256) {
    throw new Error(
      `Checksum verification failed for ${artifact.outputPath}. Expected ${artifact.sha256}, received ${downloadedHash}.`
    );
  }

  console.log(`spotify-artifacts: ready (${artifact.outputPath})`);
  return destination;
}

async function run() {
  const manifest = readManifest();
  if (!manifest.android?.appRemoteAar) {
    throw new Error('spotify-artifacts.json missing android.appRemoteAar definition.');
  }

  await resolveAndroidAppRemoteAar(manifest.android.appRemoteAar);
}

run().catch((error) => {
  console.error(`spotify-artifacts: ${error.message}`);
  console.error(
    'spotify-artifacts: if GitHub is unavailable, preseed the cache file and rerun.'
  );
  console.error(
    'spotify-artifacts: expected path .spotify-sdk-cache/android/spotify-app-remote-release-0.8.0.aar'
  );
  console.error(
    'spotify-artifacts: then run `yarn spotify:artifacts:resolve` to verify checksum.'
  );
  process.exit(1);
});
