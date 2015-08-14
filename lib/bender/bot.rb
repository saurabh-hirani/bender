require 'thread'
require 'date'
require 'time'

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

  CLOSE_TRANSITIONS = %w[ 21 41 ]

  SEVERITIES = {
    1 => '10480',
    2 => '10481',
    3 => '10482',
    4 => '10483',
    5 => '10484'
  }

  SHOW_FIELDS = {
    'summary' => 'Summary',
    'description' => 'Description',
    'customfield_11250' => 'Severity',
    'customfield_11251' => 'Impact Started',
    'customfield_11252' => 'Impact Ended',
    'customfield_11253' => 'Reported By',
    'customfield_11254' => 'Services Affected',
    'customfield_11255' => 'Cause',
    'status' => 'Status',
    'created' => 'Created',
    'updated' => 'Updated'
  }


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

    when /^\s*\?inc\s*$/
      reply [
        '?inc - This help text',
        '/inc - List open incidents',
        '/inc NUM - Show incident details',
        '/inc close NUM - Close an incident',
        '/inc SEVERITY SUMMARY - File a new incident',
        '/inc summary - Summarize recent incidents'
      ].join("\n")

    when /^\s*\/inc\s*$/
      refresh_incidents

      is = store['incidents'].map do |i|
        status = normalize_value i['fields']['status']
        unless status =~ /done|complete|closed/i
          '%s: %s' % [ i['num'], i['fields']['summary'] ]
        end
      end.compact.join("\n")
      if is.empty?
        is = "No open incident at the moment"
      end
      reply is

    when /^\s*\/inc\s+summary\s*$/
      refresh_incidents

      severity_field = SHOW_FIELDS.key 'Severity'
      severities = Hash.new { |h,k| h[k] = [] }

      store['incidents'].each do |i|
        if recent_incident? i
          repr = '%s-%s: %s' % [
            options.jira_project, i['num'], i['fields']['summary']
          ]
          sev  = i['fields'][severity_field]['value']
          severities[sev] << repr
        end
      end

      is = severities.keys.sort.map do |sev|
        "%s:\n%s" % [ sev, severities[sev].join("\n") ]
      end.join("\n\n")

      reply is

    when /^\s*\/inc\s+(\d+)\s*$/
      refresh_incidents
      incident = store['incidents'].select { |i| i['num'] == $1 }.first

      fields = SHOW_FIELDS.keys - %w[ summary ]

      i = fields.map do |f|
        val = incident['fields'][f]
        if val
          key = SHOW_FIELDS[f]
          val = normalize_value val
          '%s: %s' % [ key, val ]
        end
      end.compact

      reply "%s\n%s: %s\n%s" % [
        (options.jira_site + '/browse/' + incident['key']),
        incident['key'],
        incident['fields']['summary'],
        i.join("\n")
      ]

    when /^\s*\/inc\s+close\s+(\d+)\s*$/
      refresh_incidents
      incident = store['incidents'].select { |i| i['num'] == $1 }.first

      reply close_incident(incident)

    when /^\s*\/inc\s+(sev|s|p)?(\d+)\s+(.*?)\s*$/i
      user = user_where name: sender
      data = {
        fields: {
          project: { key: options.jira_project },
          issuetype: { name: options.jira_type },
          reporter: { name: user[:nick] },
          summary: $3,
          SHOW_FIELDS.key('Severity') => {
            id: SEVERITIES[$2.to_i]
          }
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
      jql: "project = #{options.jira_project} ORDER BY created ASC, priority DESC",
      fields: SHOW_FIELDS.keys.join(','),
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

    resp  = http.request req
    issue = JSON.parse(resp.body)

    return options.jira_site + '/browse/' + issue['key']
  end


  def close_incident incident
    req_path = '/rest/api/2/issue/%s/transitions?expand=transitions.fields' % [
      incident['key']
    ]
    uri = URI(options.jira_site + req_path)
    http = Net::HTTP.new uri.hostname, uri.port

    req = Net::HTTP::Post.new uri
    req.basic_auth options.jira_user, options.jira_pass
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'

    closed = false
    CLOSE_TRANSITIONS.each do |tid|
      req.body = {
        transition: { id: tid }
      }.to_json
      resp = http.request req
      case resp
      when Net::HTTPBadRequest
        next
      else
        closed = true
        break
      end
    end

    if closed
      'Closed: ' + options.jira_site + '/browse/' + incident['key']
    else
      [
        "Failed to close, make sure you've got the ticket filled out",
        (options.jira_site + '/browse/' + incident['key'])
      ].join("\n")
    end
  end


  def normalize_value val
    case val
    when Hash
      val['name'] || val['value'] || val
    when Array
      val.map { |v| v['value'] }.join(', ')
    when /^\d{4}\-\d{2}\-\d{2}/
      '%s (%s)' % [ val, normalize_date(val) ]
    else
      val
    end
  end


  def normalize_date val
    Time.parse(val).utc.iso8601(3).sub(/Z$/, 'UTC')
  end


  def recent_incident? i
    it = Time.parse(i['fields']['created'])
    Time.now - it < one_day
  end


  def one_day
    24 * 60 * 60 # seconds/day
  end

end
