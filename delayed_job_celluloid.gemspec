# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'delayed_job_celluloid/version'

Gem::Specification.new do |s|
  s.name          = "delayed_job_celluloid"
  s.version       = DelayedJobCelluloid::VERSION
  s.authors       = ["Tom Mooney"]
  s.email         = ["tmooney3979@gmail.com"]
  s.description   = %q{run delayed_job workers in multiple threads within a single process}
  s.summary       = %q{multi-threaded delayed_job workers!}
  s.homepage      = ""
  s.license       = "MIT"

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_dependency 'delayed_job'
  s.add_dependency 'celluloid'

  s.add_development_dependency "bundler", "~> 1.3"
  s.add_development_dependency "rake"
  s.add_development_dependency "sqlite3"
  s.add_development_dependency "delayed_job_active_record"
end
