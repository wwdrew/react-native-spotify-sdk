def install_spotify_sdk_pods!
  podspecs_path = File.expand_path('../podspecs', __dir__)

  pod 'SpotifyiOS', :path => podspecs_path
end
