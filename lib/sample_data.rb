module SampleData

  # Methods to generate random data

  def random_string(length = 10)
    (0...length).map{ (65 + rand(26)).chr }.join
  end

  def random_number(max = 50)
    rand(max) + 1
  end

  def random_email
    random_string + '@' + random_string + '.com'
  end

  def create_api_key(options = {})
    a = ApiKey.new
    options.each do |key, value|
      a.send("#{key}=", value)
    end
    a.save!
    a.reload
  end

  def create_user(options = {})
    u = User.new
    u.name = options[:name] || random_string
    u.login = options.has_key?(:login) ? options[:login] : random_string
    u.uuid = options[:uuid] || random_string
    u.provider = options.has_key?(:provider) ? options[:provider] : %w(twitter facebook).sample
    u.token = options.has_key?(:token) ? options[:token] : random_string(50)
    u.email = options[:email] || "#{random_string}@#{random_string}.com"
    u.password = options[:password] || random_string
    u.password_confirmation = options[:password_confirmation] || u.password
    u.url = options[:url] if options.has_key?(:url)
    u.save!
    u.reload
  end

  def create_comment(options = {})
    c = Comment.create({ text: random_string(50) }.merge(options))
    sleep 1 if Rails.env.test?
    c.reload
  end

  def create_annotation(options = {})
    Annotation.create(options)
  end

  def create_account(options = {})
    return create_valid_account(options) unless options.has_key?(:url)
    account = Account.new
    account.url = options[:url]
    account.data = options[:data] || {}
    if options.has_key?(:user_id)
      account.user_id = options[:user_id]
    else
      account.user = options[:user] || create_user
    end
    account.source = options[:source] || create_source
    account.save!
    account.reload
  end

  def create_project(options = {})
    project = Project.new
    project.title = options[:title] || random_string
    project.description = options[:description] || random_string(40)
    project.user = options[:user] || create_user
    project.lead_image = options[:lead_image]
    project.save!
    project.reload
  end

  def create_team(options = {})
    team = Team.new
    team.name = options[:name] || random_string
    team.logo = options[:logo]
    team.archived = options[:archived] || false
    team.save!
    team.reload
  end

  def create_media(options = {})
    return create_valid_media(options) if options[:url].blank?
    account = options[:account] || create_account
    project = options[:project] || create_project
    user = options[:user] || create_user
    m = Media.new
    m.url = options[:url]
    m.project_id = options[:project_id] || project.id
    m.account_id = options[:account_id] || account.id
    m.user_id = options[:user_id] || user.id
    m.save!
    m.reload
  end

  def create_source(options = {})
    source = Source.new
    source.name = options[:name] || random_string
    source.slogan = options[:slogan] || random_string(20)
    source.user = options[:user]
    source.avatar = options[:avatar]
    source.save!
    source.reload
  end

  def create_project_source(options = {})
    ps = ProjectSource.new
    project = options[:project] || create_project
    source = options[:source] || create_source
    ps.project_id = options[:project_id] || project.id
    ps.source_id = options[:source_id] || source.id
    ps.save!
    ps.reload
  end

  def create_team_user(options = {})
    tu = TeamUser.new
    team = options[:team] || create_team
    user = options[:user] || create_user
    tu.team_id = options[:team_id] || team.id
    tu.user_id = options[:user_id] || user.id
    tu.save!
    tu.reload
  end

  def create_valid_media(options = {})
    m = nil
    url = 'https://www.youtube.com/user/MeedanTube'
    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
      a = create_account(url: url)
      m = create_media({ url: url, account: a }.merge(options))
    end
    m
  end

  def create_valid_account(options = {})
    a = nil
    url = 'https://www.youtube.com/user/MeedanTube'
    PenderClient::Mock.mock_medias_returns_parsed_data(CONFIG['pender_host']) do
      options.merge!({ url: url })
      a = create_account(options)
    end
    a
  end
end
