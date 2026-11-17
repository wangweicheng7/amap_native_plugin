#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint amap_native_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'amap_native_plugin'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for native AMap views and search.'
  s.description      = <<-DESC
Native AMap views, overlays, input tips and reverse geocoding on Android, iOS and HarmonyOS.
                       DESC
  s.homepage         = 'https://pub.dev/packages/amap_native_plugin'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'amap_native_plugin contributors'
  s.source           = { :path => '.' }
  s.source_files = 'amap_native_plugin/Sources/amap_native_plugin/**/*'
  s.dependency 'Flutter'
  s.dependency 'AMap3DMap'
  s.dependency 'AMapSearch', '~> 9.8'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'amap_native_plugin_privacy' => ['amap_native_plugin/Sources/amap_native_plugin/PrivacyInfo.xcprivacy']}
end
