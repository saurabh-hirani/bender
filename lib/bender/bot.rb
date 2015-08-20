require 'thread'
require 'date'
require 'time'

require 'robut'
require 'hipchat'
require 'robut/storage/yaml_store'
require 'fuzzystringmatch'
require 'queryparams'

Bot = Robut # alias



module Bot
  def self.run! options
    hipchat = HipChat::Client.new(options.hipchat_token)
    BenderBot.class_variable_set :@@hipchat, hipchat
    BenderBot.class_variable_set :@@rooms, hipchat.rooms
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

  CLOSED_TRANSITIONS = %w[ 61 71 ]

  CLOSED_STATE = /close/i

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


  QUOTES = [
    'Bite my shiny metal ass!',
    'This is the worst kind of discrimination there is: the kind against me!',
    'I guess if you want children beaten, you have to do it yourself.',
    "Hahahahaha! Oh wait you're serious. Let me laugh even harder.",
    "You know what cheers me up? Other people's misfortune.",
    'Anything less than immortality is a complete waste of time.',
    "Blackmail is such an ugly word. I prefer extortion. The 'x' makes it sound cool.",
    'Have you tried turning off the TV, sitting down with your children, and hitting them?',
    "You're a pimple on society’s ass and you'll never amount to anything!",
    'Shut up baby, I know it!',
    "I'm so embarrassed. I wish everyone else was dead!",
    "Afterlife? If I thought I had to live another life, I'd kill myself right now!",
    "I'm back baby!",
    "LET'S GO ALREADYYYYYY!"
  ]


  def reply_html message, color=:yellow
    @@hipchat[@room_name].send(nick, message, color: color)
  end


  def handle room, sender, message
    @room_name = @@rooms.select { |r| r.xmpp_jid == room }.first.name
    @room      = room
    @sender    = sender
    @message   = message

    severity_field = SHOW_FIELDS.key 'Severity'
    severities = Hash.new { |h,k| h[k] = [] }


    case message

    when /^\s*\/bender\s*$/
      reply_html QUOTES.sample(1).first, :red

    when /^\s*\/whoami\s*$/
      u = user_where name: sender
      m = '<b>%{nick}</b>: %{name} (<a href="mailto:%{email}">%{email}</a>)' % u
      reply_html m, :purple

    when /^\s*\/lookup\s+(.+)\s*$/
      u = user_where(name: $1) || user_where(nick: $1)
      m = '<b>%{nick}</b>: %{name} (<a href="mailto:%{email}">%{email}</a>)' % u
      reply_html m, :purple

    # ?inc - This help text
    when /^\s*\?inc\s*$/
      reply_html [
        '<code>?inc</code> - Display this help text',
        '<code>/inc</code> - List open incidents',
        '<code>/inc <i>INCIDENT_NUMBER</i></code> - Display incident details',
        '<code>/inc close <i>INCIDENT_NUMBER</i></code> - Close an incident',
        '<code>/inc open <i>SEVERITY=1,2,3,4,5</i> <i>SUMMARY_TEXT</i></code> - Open a new incident',
        '<code>/inc summary</code> - Summarize incidents from past 24 hours (open or closed)',
        '<code>/inc comment <i>INCIDENT_NUMBER</i> <i>COMMENT_TEXT</i></code> - Add a comment to an incident'
      ].join('<br />')

    # /inc - List open incidents
    when /^\s*\/inc\s*$/
      refresh_incidents

      is = store['incidents'].reverse.map do |i|
        status = normalize_value i['fields']['status']
        unless status =~ /done|complete|closed/i
          '%s (%s - %s) [%s]: %s' % [
            incident_link(i),
            short_severity(i['fields'][severity_field]['value']),
            normalize_value(i['fields']['status']),
            friendly_date(i['fields']['created']),
            i['fields']['summary']
          ]
        end
      end.compact.join('<br />')

      if is.empty?
        reply_html 'No open incidents at the moment!', :green
      else
        reply_html is
      end

    # /inc summary - Summarize recent incidents
    when /^\s*\/inc\s+summary\s*$/
      refresh_incidents

      statuses = Hash.new { |h,k| h[k] = 0 }

      store['incidents'].reverse.each do |i|
        if recent_incident? i
          status = normalize_value(i['fields']['status'])

          repr = '%s (%s) [%s]: %s' % [
            incident_link(i),
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
        summary << '%s: %d incident(s)' % [ status, size ]
      end
      summary << ''
      summary << 'By Severity:'
      severities.keys.sort.each do |severity|
        summary << '%s: %d incident(s)' % [
          short_severity(severity),
          severities[severity].size
        ]
      end

      if severities.empty?
        reply_html 'No recent incidents! Woohoo!', :green

      else
        is = severities.keys.sort.map do |sev|
          "%s:<br />%s" % [ sev, severities[sev].join("<br />") ]
        end.join("<br /><br />")

        reply_html(summary.join("<br />") + "<br /><br />" + is)
      end


    # /inc NUM - Show incident details
    when /^\s*\/inc\s+(\d+)\s*$/
      incident = select_incident $1

      if incident.nil?
        reply_html 'Sorry, no such incident!', :red
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

        reply_html "%s - %s<br />%s" % [
          incident_link(incident),
          incident['fields']['summary'],
          i.join("<br />")
        ]
      end

    # /inc close NUM - Close an incident
    when /^\s*\/inc\s+close\s+(\d+)\s*$/
      incident = select_incident $1
      if incident
        reply_html *close_incident(incident)
      else
        reply_html 'Sorry, no such incident!', :red
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

      reply_html *file_incident(data)


    # /inc comment [INCIDENT_NUMBER] [COMMENT_TEXT]
    when /^\s*\/inc\s+comment\s+(\d+)\s+(.*?)\s*$/i
      incident = select_incident $1
      comment  = $2
      user     = user_where name: sender

      if incident
        reply_html *comment_on_incident(incident, comment, user)
      else
        reply_html 'Sorry, no such incident!', :red
      end
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
      [ 'Filed ' + incident_link(issue), :green ]
    else
      [ "Sorry, I couldn't file that!", :red ]
    end
  end


  def close_incident incident
    status = normalize_value incident['fields']['status']
    if status =~ CLOSED_STATE
      return [
        "#{incident_link(incident)} is already closed!",
        :green
      ]
    end

    req_path = '/rest/api/2/issue/%s/transitions?expand=transitions.fields' % [
      incident['key']
    ]
    uri = URI(options.jira_site + req_path)
    http = Net::HTTP.new uri.hostname, uri.port

    req = Net::HTTP::Post.new uri
    req.basic_auth options.jira_user, options.jira_pass
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'

    CLOSED_TRANSITIONS.each do |tid|
      req.body = {
        transition: { id: tid }
      }.to_json
      http.request req
    end

    incident = select_incident incident['key'].split('-',2).last
    status = normalize_value incident['fields']['status']

    if status =~ CLOSED_STATE
      [ 'Closed ' + incident_link(incident), :green ]
    else
      [
        "Failed to close #{incident_link(incident)} automatically, you might try yourself",
        :red
      ]
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
      [ 'Added comment to ' + incident_link(incident), :green ]
    else
      [
        'Sorry, I had trouble adding your comment on' + incident_link(incident),
        :red
      ]
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


  def incident_url incident
    options.jira_site + '/browse/' + incident['key']
  end

  def incident_link incident
    '<a href="%s">%s-%s</a>' % [
      incident_url(incident),
      options.jira_project,
      incident['num']
    ]
  end

end