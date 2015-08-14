module Bender
  # Project root
  ROOT = File.dirname(__FILE__), '..', '..'

  # Pull the project version out of the VERSION file
  VERSION = File.read(File.join(ROOT, 'VERSION')).strip

  # We don't really do all that much, be humble
  SUMMARY = 'Yet another HipChat bot'

  # Your benevolent dictator for life
  AUTHOR = 'Sean Clemmer'

  # Turn here to strangle your dictator
  EMAIL = 'sclemmer@bluejeans.com'

  # Like the MIT license, but even simpler
  LICENSE = 'ISC'

  # If you really just can't get enough
  HOMEPAGE = 'https://github.com/sczizzo/bender'

  # Bundled extensions
  TRAVELING_RUBY_VERSION = '20150517-2.2.2'
  JSON_VERSION = '1.8.2'
  THIN_VERSION = '1.6.3'
  FFI_VERSION = '1.9.6'
  EM_VERSION = '1.0.4'

  # Every project deserves its own ASCII art
  ART = <<-'EOART' % VERSION
       ,,                                  ,,
      *MM                                `7MM
       MM                                  MM
       MM,dMMb.   .gP"Ya `7MMpMMMb.   ,M""bMM  .gP"Ya `7Mb,od8
       MM    `Mb ,M'   Yb  MM    MM ,AP    MM ,M'   Yb  MM' "'
       MM     M8 8M""""""  MM    MM 8MI    MM 8M""""""  MM
       MM.   ,M9 YM.    ,  MM    MM `Mb    MM YM.    ,  MM
       P^YbmdP'   `Mbmmd'.JMML  JMML.`Wbmd"MML.`Mbmmd'.JMML.   v%s
  EOART
end