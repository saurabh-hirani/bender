# -*- encoding: utf-8 -*-
$:.push File.expand_path(File.join('..', 'lib'), __FILE__)
require 'bender/metadata'

Gem::Specification.new do |s|
  s.name        = 'bender-bot'
  s.version     = Bender::VERSION
  s.platform    = Gem::Platform::RUBY
  s.author      = Bender::AUTHOR
  s.email       = Bender::EMAIL
  s.license     = Bender::LICENSE
  s.homepage    = Bender::HOMEPAGE
  s.summary     = Bender::SUMMARY
  s.description = Bender::SUMMARY + '.'

  s.add_runtime_dependency 'thor', '~> 0'
  s.add_runtime_dependency 'slog', '~> 1'
  s.add_runtime_dependency 'sinatra', '~> 1.4'
  s.add_runtime_dependency 'sclemmer-robut', '~> 0.5.2'
  s.add_runtime_dependency 'hipchat', '~> 1'
  s.add_runtime_dependency 'queryparams', '~> 0.0.3'
  s.add_runtime_dependency 'fuzzy-string-match', '~> 0.9.7'

  # Bundled libs
  s.add_runtime_dependency 'eventmachine', '= %s' % Bender::EM_VERSION
  s.add_runtime_dependency 'thin', '= %s' % Bender::THIN_VERSION

  s.files         = Dir['{bin,lib,web}/**/*'] + %w[ LICENSE Readme.md VERSION ]
  s.test_files    = Dir['test/**/*']
  s.executables   = %w[ bender ]
  s.require_paths = %w[ lib ]
end