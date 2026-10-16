Pod::Spec.new do |s|
  s.name = 'local_receipt_ocr'
  s.version = '1.0.0'
  s.summary = 'Offline Greek and English receipt OCR'
  s.homepage = 'https://github.com/ratulsdream/basha-hisab'
  s.license = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author = 'BashaHisab'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'BashaTesseract', '0.2.0'
  s.platform = :ios, '15.5'
  s.swift_version = '5.0'
  s.libraries = 'z', 'c++'
end
