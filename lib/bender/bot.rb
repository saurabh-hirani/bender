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

  CLOSE_STATE = /done/i

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
    severity_field = SHOW_FIELDS.key 'Severity'
    severities = Hash.new { |h,k| h[k] = [] }

    case message


    when /^\s*\?opts\s*$/
      reply options.inspect

    when /^\s*\?whoami\s*$/
      u = user_where name: sender
      reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

    when /^\s*\?lookup\s+(.+)\s*$/
      u = user_where(name: $1) || user_where(nick: $1)
      reply '%s: %s (%s)' % [ u[:nick], u[:name], u[:email] ]

    # ?inc - This help text
    when /^\s*\?inc\s*$/
      reply [
        '?inc - Display this help text',
        '/inc - List open incidents',
        '/inc [INCIDENT_NUMBER] - Display incident details',
        '/inc close [INCIDENT_NUMBER] - Close an incident',
        '/inc open [SEVERITY=1,2,3,4,5] [SUMMARY_TEXT] - Open a new incident',
        '/inc summary - Summarize incidents from past 24 hours (open or closed)',
        '/inc comment [INCIDENT_NUMBER] [COMMENT_TEXT] - Add a comment to an incident'
      ].join("\n")

    # /inc - List open incidents
    when /^\s*\/inc\s*$/
      refresh_incidents

      is = store['incidents'].reverse.map do |i|
        status = normalize_value i['fields']['status']
        unless status =~ /done|complete|closed/i
          '%s-%s (%s - %s) [%s]: %s' % [
            options.jira_project,
            i['num'],
            short_severity(i['fields'][severity_field]['value']),
            normalize_value(i['fields']['status']),
            friendly_date(i['fields']['created']),
            i['fields']['summary']
          ]
        end
      end.compact.join("\n")

      is = 'No open incidents at the moment!' if is.empty?

      reply is

    # /inc summary - Summarize recent incidents
    when /^\s*\/inc\s+summary\s*$/
      refresh_incidents

      statuses = Hash.new { |h,k| h[k] = 0 }

      store['incidents'].reverse.each do |i|
        if recent_incident? i
          status = normalize_value(i['fields']['status'])

          repr = '%s-%s (%s) [%s]: %s' % [
            options.jira_project,
            i['num'],
            status,
            friendly_date(i['fields']['created']),
            i['fields']['summary']
          ]

          sev  = i['fields'][severity_field]['value']
          severities[sev] << repr
          statuses[status] += 1
        end
      end

      summary = []
      summary << 'By Status:'
      statuses.each do |status, size|
        summary << '%s: %d ticket(s)' % [ status, size ]
      end
      summary << ''
      summary << 'By Severity:'
      severities.keys.sort.each do |severity|
        summary << '%s: %d ticket(s)' % [
          short_severity(severity),
          severities[severity].size
        ]
      end

      if severities.empty?
        reply 'No recent incidents! Woohoo!'

      else
        is = severities.keys.sort.map do |sev|
          "%s:\n%s" % [ sev, severities[sev].join("\n") ]
        end.join("\n\n")

        reply(summary.join("\n") + "\n\n" + is)
      end


    # /inc NUM - Show incident details
    when /^\s*\/inc\s+(\d+)\s*$/
      incident = select_incident $1

      if incident.nil?
        reply 'Sorry, no such incident!'
      else
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
      end

    # /inc close NUM - Close an incident
    when /^\s*\/inc\s+close\s+(\d+)\s*$/
      incident = select_incident $1
      if incident
        reply close_incident(incident)
      else
        reply 'Sorry, no such incident!'
      end

    # /inc open SEVERITY SUMMARY - File a new incident
    when /^\s*\/inc\s+open\s+(severity|sev|s|p)?(\d+)\s+(.*?)\s*$/i
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


    # /inc comment [INCIDENT_NUMBER] [COMMENT_TEXT]
    when /^\s*\/inc\s+comment\s+(\d+)\s+(.*?)\s*$/i
      incident = select_incident $1
      comment  = $2
      user     = user_where name: sender

      reply comment_on_incident(incident, comment, user)
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

    if issue.has_key? 'key'
      options.jira_site + '/browse/' + issue['key']
    else
      "Sorry, I couldn't file that!"
    end
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

    CLOSE_TRANSITIONS.each do |tid|
      req.body = {
        transition: { id: tid }
      }.to_json
      http.request req
    end

    incident = select_incident incident['key'].split('-',2).last
    status = normalize_value incident['fields']['status']

    if status =~ CLOSE_STATE
      'Closed: ' + options.jira_site + '/browse/' + incident['key']
    else
      [
        'Failed to close automatically, you might try yourself',
        (options.jira_site + '/browse/' + incident['key'])
      ].join("\n")
    end
  end


  def comment_on_incident incident, comment, user
    req_path = '/rest/api/2/issue/%s/comment' % incident['key']
    uri = URI(options.jira_site + req_path)
    http = Net::HTTP.new uri.hostname, uri.port

    req = Net::HTTP::Post.new uri
    req.basic_auth options.jira_user, options.jira_pass
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    req.body = { body: '_[~%s]_ says: %s' % [ user[:nick], comment ] }.to_json

    case http.request(req)
    when Net::HTTPCreated
      'Added: ' + options.jira_site + '/browse/' + incident['key']
    else
      [
        'Sorry, I had trouble adding your comment',
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
    Time.parse(val).utc.iso8601(0).sub(/Z$/, 'UTC')
  end


  def friendly_date val
    Time.parse(val).strftime('%Y-%m-%d %H:%M %Z')
  end


  def recent_incident? i
    it = Time.parse(i['fields']['created'])
    Time.now - it < one_day
  end


  def one_day
    24 * 60 * 60 # seconds/day
  end


  def select_incident num, refresh=true
    refresh_incidents if refresh
    store['incidents'].select { |i| i['num'] == num }.first
  end


  def short_severity s
    s.split(' - ', 2).first
  end

end