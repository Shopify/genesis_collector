# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'genesis_collector/version'

Gem::Specification.new do |spec|
  spec.name          = 'genesis_collector'
  spec.version       = GenesisCollector::VERSION
  spec.authors       = ['David Radcliffe']
  spec.email         = ['david.radcliffe@shopify.com']

  spec.summary       = 'Agent to collect information about bare metal servers and send it to Genesis.'
  spec.homepage      = "https://github.com/Shopify/genesis_collector"
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nokogiri'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'webmock', '~> 1.22'
end
