Pod::Spec.new do |s|
  s.name = 'HuginnCore'
  s.version = '1.0.0'
  s.summary = 'Huginn Go messenger core for the macOS runner.'
  s.homepage = 'https://github.com/killbane1232/huginn-messenger'
  s.license = { :type => 'GPL-3.0', :file => '../LICENSE' }
  s.author = 'Huginn contributors'
  s.source = { :path => '.' }
  s.platform = :osx, '13.0'
  s.vendored_frameworks = 'Frameworks/huginn_messenger.framework'
end
