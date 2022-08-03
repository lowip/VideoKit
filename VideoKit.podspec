#
# Be sure to run `pod lib lint VideoKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'VideoKit'
  s.version          = '0.1.2'
  s.summary          = 'An optimized video player view (mostly asynchronous)'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  A Library providing an easy to use, highly asynchronous video player view.
  DESC

  s.homepage         = 'https://github.com/lowip/VideoKit'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'lowip' => 'louisbur92@gmail.com' }
  s.source           = { :git => 'https://github.com/lowip/VideoKit.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.swift_version = '4.2'
  s.ios.deployment_target = '11.0'

  s.source_files = 'VideoKit/Classes/**/*'
  
  # s.resource_bundles = {
  #   'VideoKit' => ['VideoKit/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'UIKit', 'AVFoundation'
  # s.dependency 'AFNetworking', '~> 2.3'
end
