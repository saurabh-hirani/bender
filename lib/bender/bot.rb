require 'thread'

require 'robut'
require 'robut/storage/yaml_store'
require 'fuzzystringmatch'
require 'queryparams'

Bot = Robut # alias



module Bot
  def self.run! options
    BenderBot.class_variable_set :@@options, options
    Bot::Plugin.plugins = [ BenderBot ]
    conn = Bot::Connection.new
    conn.store['users'] ||= {}
    Bot::Web.set :connection, conn.connect
    return conn
  end
end


class BenderBot
  include Bot::Plugin

  JARO = FuzzyStringMatch::JaroWinkler.create :native

  SHOW_FIELDS = %w[
    summary
    description
    priority
    status
    created
    updated
  ]


  def handle time, sender, message
    case message


    when /^\s*\?opts\s*$/
      reply options.inspect

    when /^\s*\?whoami\s*$/
      u = user_where name: sender
      reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

    when /^\s*\?lookup\s+(.+)\s*$/
      u = user_where(name: $1) || user_where(nick: $1)
      reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

    when /^\s*\?incident\s*$/
      reply [
        '?icident - This help text',
        '?incidents - List open incidents',
        '?incident NUM - Show incident',
        '?incident NUM FIELD - Show incident field',
        '?incident SUMMARY - File a new incident'
      ].join("\n")

    when /^\s*\?incidents\s*$/
      refresh_incidents

      is = store['incidents'].map do |i|
        '%s: %s' % [ i['num'], i['fields']['summary'] ]
      end.join("\n")

      reply is

    when /^\s*\?incident\s+(\d+)\s*$/
      refresh_incidents
      incident = store['incidents'].select { |i| i['num'] == $1 }.first

      fields = SHOW_FIELDS - %w[ summary ]

      i = fields.map do |f|
        val = incident['fields'][f]
        if val
          val = val.is_a?(Hash) ? val['name'] : val
          '%s: %s' % [ f, val ]
        end
      end.compact

      reply "%s: %s\n%s" % [
        incident['key'],
        incident['fields']['summary'],
        i.join("\n")
      ]

    when /^\s*\?incident\s+(\d+)\s+(.*?)\s*$/
      refresh_incidents
      incident = store['incidents'].select { |i| i['num'] == $1 }.first
      val = incident['fields'][$2]
      val = val.is_a?(Hash) ? val['name'] : val
      reply val

    when /^\s*\?incident\s+(.*?)\s*$/
      user = user_where name: sender
      data = {
        fields: {
          project: { key: options.jira_project },
          issuetype: { name: options.jira_type },
          reporter: { name: user[:nick] },
          summary: $1
        }
      }

      reply file_incident(data)
    end

    return true
  end



private

  def options ; @@options end

  def user_where fields, threshold=0.8
    field, value = fields.to_a.shift
    suggested_user = store['users'].values.sort_by do |u|
      compare value, u[field]
    end.last

    distance = compare value, suggested_user[field]
    return distance < threshold ? nil : suggested_user
  end


  def compare name1, name2
    n1 = name1.gsub /\W/, ''
    n2 = name2.gsub /\W/, ''
    d1 = JARO.getDistance n1.downcase, n2.downcase
    d2 = JARO.getDistance n1, n2
    return d1 + d2 / 2.0
  end



  def refresh_incidents
    req_path = '/rest/api/2/search'
    req_params = QueryParams.encode \
      jql: "project = #{options.jira_project} AND resolution = Unresolved ORDER BY created ASC, priority DESC",
      fields: SHOW_FIELDS.join(','),
      startAt: 0,
      maxResults: 1_000_000

    uri = URI(options.jira_site + req_path + '?' + req_params)
    http = Net::HTTP.new uri.hostname, uri.port

    req = Net::HTTP::Get.new uri
    req.basic_auth options.jira_user, options.jira_pass
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'

    resp = http.request req
    issues = JSON.parse(resp.body)['issues']

    store['incidents'] = issues.map! do |i|
      i['num'] = i['key'].split('-', 2).last ; i
    end
  end


  def file_incident data
    req_path = '/rest/api/2/issue'
    uri = URI(options.jira_site + req_path)
    http = Net::HTTP.new uri.hostname, uri.port

    req = Net::HTTP::Post.new uri
    req.basic_auth options.jira_user, options.jira_pass
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    req.body = data.to_json

    resp = http.request req
    issue = JSON.parse(resp.body)

    return options.jira_site + '/browse/' + issue['key']
  end


end