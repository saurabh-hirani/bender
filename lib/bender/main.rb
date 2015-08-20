require 'logger'
require 'net/http'

require 'tilt/erb'
require 'queryparams'

require_relative 'metadata'
require_relative 'mjolnir'
require_relative 'web'
require_relative 'bot'


module Bender
  class Main < Mjolnir

    desc 'version', 'Echo the application version'
    def version
      puts VERSION
    end


    desc 'art', 'View the application art'
    def art
      puts "\n%s\n" % ART
    end



    desc 'bot', 'Start Bender HipChat bot and Web server'
    option :bind, \
      type: :string,
      aliases: %w[ -b ],
      desc: 'Set Sinatra interface',
      default: '0.0.0.0'
    option :port, \
      type: :numeric,
      aliases: %w[ -o ],
      desc: 'Set Sinatra port',
      default: 4567
    option :environment, \
      type: :string,
      aliases: %w[ -e ],
      desc: 'Set Sinatra environment',
      default: 'development'
    option :hipchat_token, \
      type: :string,
      aliases: %w[ -t ],
      desc: 'Set HipChat v1 API token',
      required: true
    option :jid, \
      type: :string,
      aliases: %w[ -j ],
      desc: 'Set HipChat JID',
      required: true
    option :password, \
      type: :string,
      aliases: %w[ -p ],
      desc: 'Set HipChat password',
      required: true
    option :nick, \
      type: :string,
      aliases: %w[ -n ],
      desc: 'Set HipChat nick name',
      required: true
    option :mention, \
      type: :string,
      aliases: %w[ -m ],
      desc: 'Set HipChat mention name',
      required: true
    option :rooms, \
      type: :string,
      aliases: %w[ -r ],
      desc: 'Set HipChat rooms (comma-separated)',
      required: true
    option :database, \
      type: :string,
      aliases: %w[ -d ],
      desc: 'Set path to application database',
      required: true
    option :rooms, \
      type: :string,
      aliases: %w[ -r ],
      desc: 'Set HipChat rooms (comma-separated)',
      required: true
    option :jira_user, \
      type: :string,
      aliases: %w[ -U ],
      desc: 'Set JIRA username',
      required: true
    option :jira_pass, \
      type: :string,
      aliases: %w[ -P ],
      desc: 'Set JIRA password',
      required: true
    option :jira_site, \
      type: :string,
      aliases: %w[ -S ],
      desc: 'Set JIRA site',
      required: true
    option :jira_project, \
      type: :string,
      aliases: %w[ -J ],
      desc: 'Set JIRA project',
      required: true
    option :jira_type, \
      type: :string,
      aliases: %w[ -T ],
      desc: 'Set JIRA issue type',
      required: true
    option :refresh, \
      type: :numeric,
      aliases: %w[ -R ],
      desc: 'Set JIRA refresh rate',
      default: 300
    include_common_options
    def start
      bot = start_bot
      refresh_users bot
      serve_web bot
    end



  private

    def start_bot
      Bot::Connection.configure do |config|
        config.jid = options.jid
        config.password = options.password
        config.nick = options.mention
        config.mention_name = options.nick
        config.rooms = options.rooms.split(',')

        Bot::Storage::YamlStore.file = options.database
        config.store = Bot::Storage::YamlStore

        config.logger = log
      end

      Bot.run! options
    end


    def refresh_users bot
      req_path = '/rest/api/2/user/assignable/search'
      req_params = QueryParams.encode \
        project: options.jira_project,
        startAt: 0,
        maxResults: 1_000_000

      uri = URI(options.jira_site + req_path + '?' + req_params)
      http = Net::HTTP.new uri.hostname, uri.port

      req = Net::HTTP::Get.new uri
      req.basic_auth options.jira_user, options.jira_pass
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'

      Thread.new do
        loop do
          resp = http.request req
          users = JSON.parse(resp.body).inject({}) do |h, user|
            h[user['key']] = {
              nick: user['key'],
              name: user['displayName'],
              email: user['emailAddress']
            } ; h
          end

          bot.store['users'] = users

          sleep options.refresh
        end
      end
    end


    def serve_web bot
      Web.set :environment, options.environment
      Web.set :port, options.port
      Web.set :bind, options.bind
      Web.set :store, options.database

      if log.level >= ::Logger::DEBUG
        Web.set :raise_errors, true
        Web.set :dump_errors, true
        Web.set :show_exceptions, true
        Web.set :logging, ::Logger::DEBUG
      end

      Web.set :bot, bot
      Web.run!
    end


  end
end
