require_relative "lib/sproc/version"

Gem::Specification.new do |spec|
  spec.name = "sproc"
  spec.version = SProc::VERSION
  spec.authors = ["Anders Rillbert"]
  spec.email = ["anders.rillbert@kutso.se"]

  spec.summary = "Spawn commands as asynch/synch subprocesses."
  spec.description = "Easier invokation of asynch/synch commands with "\
                       "a reasonable easy and flexible interface for processing stdout and stderr"
  spec.homepage = "https://github.com/rillbert/sproc"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Developer dependencies
  spec.add_development_dependency "minitest", "~> 5.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard", "~> 1.7"

  # Uncomment to register a runtime dependency
  #  spec.add_dependency "example-gem", "~> 1.0"
end
