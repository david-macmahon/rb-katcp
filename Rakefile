require 'rubygems'
require 'rake/gempackagetask'

# Get KATCP::VERSION
require './lib/katcp/version.rb'

spec = Gem::Specification.new do |s|
  # Basics
  s.name = 'katcp'
  s.version = KATCP::VERSION
  s.summary = 'KATCP library for Ruby'
  s.description = <<-EOD
    Provides KATCP client library for Ruby.  KATCP is the Karoo Array Telescope
    Control Protocol.
    EOD
  #s.platform = Gem::Platform::Ruby
  s.required_ruby_version = '>= 1.8.1'
  s.add_dependency('narray', '>= 0.5.9')

  # About
  s.authors = 'David MacMahon'
  s.email = 'davidm@astro.berkeley.edu'
  s.homepage = 'http://rb-katcp.rubyforge.org/'
  s.rubyforge_project = 'rb-katcp' 

  # Files, Libraries, and Extensions
  s.files = %w[
    README
    lib/katcp.rb
    lib/katcp/client.rb
    lib/katcp/client/roach.rb
    lib/katcp/irb.rb
    lib/katcp/response.rb
    lib/katcp/util.rb
    lib/katcp/version.rb
    examples/listdev.rb
  ]
  s.require_paths = ['lib']
  #s.autorequire = nil
  #s.bindir = 'bin'
  #s.executables = []
  #s.default_executable = nil

  # C compilation
  #s.extensions = %w[ ext/extconf.rb ]

  # Documentation
  s.rdoc_options = ['-m', 'README', '--title', "Ruby/KATCP #{s.version} Documentation"]
  s.has_rdoc = true
  s.extra_rdoc_files = %w[README]

  # Testing TODO
  #s.test_files = [test/test.rb]
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end
