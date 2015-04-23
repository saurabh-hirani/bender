require 'slog'
require 'thor'


# Thor's hammer! Like Thor with better logging
class Mjolnir < Thor

  # Common options for Thor commands
  COMMON_OPTIONS = {
    log: {
      type: :string,
      aliases: %w[ -L ],
      desc: 'Log to file instead of STDOUT',
      default: ENV['BENDER_LOG'] || nil
    },
    debug: {
      type: :boolean,
      aliases: %w[ -V ],
      desc: 'Enable DEBUG-level logging',
      default: ENV['BENDER_DEBUG'] || false
    },
    trace: {
      type: :boolean,
      aliases: %w[ -VV ],
      desc: 'Enable TRACE-level logging',
      default: ENV['BENDER_TRACE'] || false
    }
  }

  # Decorate Thor commands with the options above
  def self.include_common_options
    COMMON_OPTIONS.each do |name, spec|
      option name, spec
    end
  end


  no_commands do

    # Construct a Logger given the command-line options
    def log
      return @logger if defined? @logger
      level = :info
      level = :debug if options.debug?
      level = :trace if options.trace?
      device = options.log || $stderr
      pretty = device.tty? rescue false
      @logger = Slog.new \
        out: device,
        level: level,
        colorize: pretty,
        prettify: pretty
    end

  end
end