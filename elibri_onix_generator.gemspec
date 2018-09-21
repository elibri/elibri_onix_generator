# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "elibri_onix_generator/version"

Gem::Specification.new do |s|
  s.name        = "elibri_onix_generator"
  s.version     = ElibriOnixGenerator::VERSION
  s.authors     = ["Marcin Urbański", "Piotr Szmielew"]
  s.email       = ["marcin@urbanski.vdl.pl", "p.szmielew@beinformed.pl"]
  s.homepage    = ""
  s.summary     = %q{XML Generator used by Elibri gems}
  s.description = %q{XML Generator used by Elibri gems}

  s.rubyforge_project = "elibri_onix_generator"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "builder"
  s.add_runtime_dependency "elibri_onix_dict"
end
