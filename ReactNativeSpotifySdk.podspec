require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "ReactNativeSpotifySdk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/wwdrew/react-native-spotify-sdk.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  s.dependency "SpotifyiOS"
  s.pod_target_xcconfig = {
    "CLANG_ENABLE_MODULES" => "YES",
    "FRAMEWORK_SEARCH_PATHS" => "$(inherited) \"${PODS_CONFIGURATION_BUILD_DIR}/SpotifyiOS\" \"${PODS_XCFRAMEWORKS_BUILD_DIR}/SpotifyiOS\"",
  }

  install_modules_dependencies(s)
end
