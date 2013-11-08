# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ec2-backup/ec2-backup'

Gem::Specification.new do |gem|
  gem.name          = "ec2-backup"
  gem.version       = '1.0.0'
  gem.authors       = ["Alfred Moreno"]
  gem.email         = ["kryptek@gmail.com"]
  gem.description   = %q{Automate backups of your infrastructure dynamically via AWS EC2 Tagging and Snapshots}
  gem.summary       = %q{A configurable backup gem for ec2 volumes. See the github page for more}
  gem.homepage      = "https://github.com/kryptek/ec2-backup"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'active_support'
  gem.add_dependency 'fog'

  gem.license       = 'MIT'
end
