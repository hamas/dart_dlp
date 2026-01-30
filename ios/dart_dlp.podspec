#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint dart_dlp.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'dart_dlp'
  s.version          = '1.0.0'
  s.summary          = 'A high-performance media extraction engine.'
  s.description      = <<-DESC
A high-performance media extraction engine built by Hamas.
                       DESC
  s.homepage         = 'https://github.com/hamas/dart_dlp'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hamas' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
