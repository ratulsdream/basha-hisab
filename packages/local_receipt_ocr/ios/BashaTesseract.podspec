Pod::Spec.new do |s|
  s.name = 'BashaTesseract'
  s.version = '0.2.0'
  s.summary = 'Pinned Tesseract LSTM xcframework'
  s.homepage = 'https://github.com/SwiftyTesseract/libtesseract'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'SwiftyTesseract contributors'
  s.source = { :http => 'https://github.com/SwiftyTesseract/libtesseract/releases/download/0.2.0/libtesseract-0.2.0.xcframework.zip',
    :sha256 => 'cc42f3424047adc7064e6bb67d5039385629ee42199fcbb0553f57f1110d8c90' }
  s.vendored_frameworks = 'libtesseract.xcframework'
  s.platform = :ios, '15.5'
  s.libraries = 'z', 'c++'
end
