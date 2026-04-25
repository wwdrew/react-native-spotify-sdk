Pod::Spec.new do |s|
  s.name             = 'SpotifyiOS'
  s.version          = '5.0.1'
  s.summary          = 'Spotify iOS SDK for playback control and metadata'
  s.description      = <<-DESC
    The Spotify iOS framework allows your application to interact with the Spotify app 
    running in the background on a user's device. Capabilities include authorization, 
    getting metadata for the currently playing track and context, as well as issuing 
    playback commands.
  DESC

  s.homepage         = 'https://github.com/spotify/ios-sdk'
  s.license          = { :type => 'Proprietary', :file => 'Licenses/license.txt' }
  s.author           = { 'Spotify' => 'https://github.com/spotify' }

  s.source           = { 
    :git => 'https://github.com/spotify/ios-sdk.git', 
    :tag => "v#{s.version}" 
  }

  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'

  s.vendored_frameworks = 'SpotifyiOS.xcframework'
end