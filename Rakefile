require 'rubygems'
require 'bundler'
require 'rake'


require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/test*.rb']
  test.verbose = true
end

task :default => :test


require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.files = %w[ --readme Readme.md lib/**/*.rb - VERSION ]
end


require 'rubygems/tasks'
Gem::Tasks.new({
  sign: {}
}) do |tasks|
  tasks.console.command = 'pry'
end
Gem::Tasks::Sign::Checksum.new sha2: true


require 'rake/version_task'
Rake::VersionTask.new



# Packaging
#
# Based on Travelling Ruby and FPM:
# - http://phusion.github.io/traveling-ruby
# - https://github.com/jordansissel/fpm
#
require_relative 'lib/bender/metadata'

include Bender

`which gtar` # Necessary on OS X
TAR = $?.exitstatus.zero? ? 'gtar' : 'tar'

desc 'Package Bender for Docker, Linux and OS X'
task native_packages: %w[ docker package:osx ]


namespace :package do
  task linux: [
    'pkg/traveling-ruby-linux-x86_64',
    'pkg/traveling-ruby-gem-thin-linux-x86_64',
    'pkg/traveling-ruby-gem-eventmachine-linux-x86_64'
  ] do
    create_package 'linux-x86_64'
  end

  task osx: [
    'pkg/traveling-ruby-osx',
    'pkg/traveling-ruby-gem-thin-osx',
    'pkg/traveling-ruby-gem-eventmachine-osx'
  ] do
    create_package 'osx'
  end
end


# desc 'Package Bender into a Docker container'
task docker: %w[ package:linux ] do
  sh 'docker build -t bender .'
  latest_image = "docker images | grep bender | head -n 1 | awk '{ print $3 }'"
  sh "docker tag `#{latest_image}` sczizzo/bender:#{VERSION}"
  sh "docker tag `#{latest_image}` sczizzo/bender:latest"
  sh "docker push sczizzo/bender"
  clean
end


file 'pkg/traveling-ruby-linux-x86_64' do
  download_runtime TRAVELING_RUBY_VERSION, 'linux-x86_64'
end

file 'pkg/traveling-ruby-osx' do
  download_runtime TRAVELING_RUBY_VERSION, 'osx'
end

file 'pkg/traveling-ruby-gem-thin-linux-x86_64' do
  download_extension 'thin', THIN_VERSION, 'linux-x86_64'
end

file 'pkg/traveling-ruby-gem-thin-osx' do
  download_extension 'thin', THIN_VERSION, 'osx'
end

file 'pkg/traveling-ruby-gem-eventmachine-linux-x86_64' do
  download_extension 'eventmachine', EM_VERSION, 'linux-x86_64'
end

file 'pkg/traveling-ruby-gem-eventmachine-osx' do
  download_extension 'eventmachine', EM_VERSION, 'osx'
end




def bundle_install
  if RUBY_VERSION !~ /^2\.2\./
    abort "You can only 'bundle install' using Ruby 2.2, because that's what Traveling Ruby uses."
  end

  sh 'rm -rf pkg/tmp pkg/vendor'
  sh 'mkdir pkg/tmp'
  sh 'cp -R bender.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock bin lib pkg/tmp'

  Bundler.with_clean_env do
    sh 'cd pkg/tmp && env BUNDLE_IGNORE_CONFIG=1 bundle install --path vendor --without development'
    sh 'mv pkg/tmp/vendor pkg'
  end

  sh 'rm -rf pkg/tmp'

  if !ENV['NO_EXT']
    sh 'rm -f pkg/vendor/*/*/cache/*'
    sh 'rm -rf pkg/vendor/ruby/*/extensions'

    # Remove tests
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/test'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/tests'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/spec'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/features'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/benchmark'

    # Remove documentation
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/README*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/CHANGE*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/change*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/COPYING*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/LICENSE*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/MIT-LICENSE*'
    sh 'rm -f pkg/vendor/ruby/*/gemS/*/TODO'
    sh 'rm -f pkg/vendor/ruby/*/gems/*/*.txt'
    sh 'rm -f pkg/vendor/ruby/*/gems/*/*.md'
    sh 'rm -f pkg/vendor/ruby/*/gems/*/*.rdoc'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/doc'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/docs'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/example'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/examples'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/sample'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/doc-api'
    sh "find pkg/vendor/ruby -name '*.md' | xargs sh 'rm -f' || true"

    # Remove misc unnecessary files
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/.gitignore'
    sh 'rm -rf pkg/vendor/ruby/*/gems/*/.travis.yml'

    # Remove leftover native extension sources and compilation objects
    sh 'rm -f pkg/vendor/ruby/*/gems/*/Ext/makefile'
    sh 'rm -f pkg/vendor/ruby/*/gems/*/exT/*/makefile'
    sh 'rm -f pkg/vendor/ruby/*/gems/*/ext/*/tmp'
    sh "find pkg/vendor/ruby -name '*.c' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby -name '*.cpp' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby -name '*.h' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby -name '*.rl' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby -name 'extconf.rb' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby/*/gems -name '*.o' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby/*/gems -name '*.so' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby/*/gems -name '*.bundle' | xargs sh 'rm -f' || true"

    # Remove Java files. They're only used for JRuby support
    sh "find pkg/vendor/ruby -name '*.java' | xargs sh 'rm -f' || true"
    sh "find pkg/vendor/ruby -name '*.class' | xargs sh 'rm -f' || true"
  end
end


def create_package target
  bundle_install
  package_name = "bender-#{VERSION}-#{target}"
  package_file = ::File.join Dir.pwd, 'pkg', "#{package_name}.tar.gz"
  package_dir = ::File.join Dir.pwd, 'pkg', package_name
  output = ::File.join Dir.pwd, 'pkg', "bender_#{VERSION}_amd64.deb"
  sh "rm -rf #{package_dir}"
  sh "rm -rf #{output}" if target =~ /linux/
  sh "mkdir -p #{package_dir}/bender"
  sh "cp -R bin #{package_dir}/bender"
  sh "mkdir #{package_dir}/bender/ruby"
  sh "#{TAR} -xzf pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/bender/ruby"
  sh "cp pkg/bender.sh #{package_dir}"
  sh "cp -pR pkg/vendor #{package_dir}/bender/vendor"
  sh "cp -R bender.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock lib #{package_dir}/bender/vendor"
  sh "mkdir #{package_dir}/bender/vendor/.bundle"
  sh "cp pkg/bundler-config #{package_dir}/bender/vendor/.bundle/config"
  if !ENV['NO_EXT']
    sh "#{TAR} -xzf pkg/thin-#{THIN_VERSION}.tar.gz -C #{package_dir}/bender/vendor/ruby"
    sh "#{TAR} -xzf pkg/eventmachine-#{EM_VERSION}.tar.gz -C #{package_dir}/bender/vendor/ruby"
  end
  if !ENV['NO_FPM'] && target =~ /linux/
    sh %Q~
      fpm --verbose \
        -s dir -t deb -C #{package_dir} \
        -n bender -v #{VERSION} \
        --license "#{LICENSE}" \
        --description "#{SUMMARY}" \
        --maintainer "#{AUTHOR} <#{EMAIL}>" \
        --vendor "#{AUTHOR}" \
        --url "#{HOMEPAGE}" \
        --package "#{output}" \
        bender.sh=/usr/local/bin/bender \
        bender=/opt
    ~
  end
  if !ENV['DIR_ONLY']
    sh "cd #{package_dir} && tar -czf #{package_file} ."
    sh "rm -rf #{package_dir}"
  end
  clean
end


def download_extension name, version, target
  url = 'http://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-gems-%s-%s/%s-%s.tar.gz' % [
    TRAVELING_RUBY_VERSION, target, name, version
  ]
  sh 'cd pkg && curl -L -O --fail ' + url
end


def download_runtime version, target
  sh 'cd pkg && curl -L -O --fail ' +
    "http://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-#{version}-#{target}.tar.gz"
end


def clean
  sh 'rm -rf pkg/vendor pkg/tmp pkg/thin* pkg/traveling* pkg/eventmachine*'
  sh 'find pkg/* -type d | xargs rm -rf'
  sh 'rm -f pkg/bender-*-linux-*.tar.gz'
end