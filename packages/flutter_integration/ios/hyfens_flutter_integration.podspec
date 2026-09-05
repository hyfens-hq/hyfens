Pod::Spec.new do |s|
  s.name             = 'hyfens_flutter_integration'
  s.version          = '0.1.0'
  s.summary          = 'Native installation identity for Hyfens Flutter integration.'
  s.description      = <<-DESC
Native Keychain/Secure Enclave installation identity and P-256 signing for Hyfens.
                       DESC
  s.homepage         = 'https://github.com/hyfens-hq/hyfens'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Hyfens' => 'https://github.com/hyfens-hq' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
