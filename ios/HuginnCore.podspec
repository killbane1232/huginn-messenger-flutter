Pod::Spec.new do |s|
  s.name = 'HuginnCore'
  s.version = '1.0.0'
  s.summary = 'Huginn Go messenger core for the iOS runner.'
  s.homepage = 'https://github.com/killbane1232/huginn-messenger'
  s.license = { :type => 'GPL-3.0', :file => '../LICENSE' }
  s.author = 'Huginn contributors'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/HuginnCore.xcframework'
  s.frameworks = 'CoreFoundation', 'Security', 'SystemConfiguration', 'Network', 'UIKit', 'Foundation'
  s.libraries = 'resolv'
  # Dart resolves these C ABI functions with dlsym; keep them in release builds.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -force_load "$(PODS_XCFRAMEWORKS_BUILD_DIR)/HuginnCore/libhuginn_messenger.a" -Wl,-exported_symbol,_messenger_*'
  }
end
