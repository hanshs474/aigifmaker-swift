Pod::Spec.new do |s|
  s.name             = 'AIGifMaker'
  s.version          = '0.1.0'
  s.summary          = 'Official SDK for AI GIF Maker (aigifmaker.ai): turn text into animated GIFs.'
  s.description      = 'Turn text into animated GIFs with AI GIF Maker. Native GIF generation, no video conversion. Official Swift SDK: send a prompt from iOS or macOS with your AI GIF Maker API key and get back the URL of the finished GIF.'
  s.homepage         = 'https://aigifmaker.ai/?utm_source=cocoapods&utm_medium=package'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'AI GIF Maker' => 'support@aigifmaker.ai' }
  s.source           = { :git => 'https://github.com/hanshs474/aigifmaker-swift.git', :tag => "v#{s.version}" }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_versions   = ['5.7']
  s.source_files     = 'Sources/AIGifMaker/**/*.swift'
end
