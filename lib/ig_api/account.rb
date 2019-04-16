require 'ostruct'

module IgApi
  class IgApiLoginFailed < StandardError
    attr_reader :object

    def initialize(object)
      @object = object
    end
  end

  class Account
    def initialized
      @api = nil
    end

    def api
      @api = IgApi::Http.new if @api.nil?

      @api
    end

    def using(session)
      User.new session: session
    end

    def login(username, password, proxy = nil, config = IgApi::Configuration.new)
      user = User.new username: username,
                      password: password

      request = api.post(
        Constants::URL + 'accounts/login/',
        format(
          'ig_sig_key_version=4&signed_body=%s',
          IgApi::Http.generate_signature(
            device_id: user.device_id,
            login_attempt_user: 0, password: user.password, username: user.username,
            _csrftoken: 'missing', _uuid: IgApi::Http.generate_uuid
          )
        )
      ).with(ua: user.useragent, proxy: proxy).exec

      response = JSON.parse request.body, object_class: OpenStruct

      raise IgApiLoginFailed, response.message if response.status == 'fail'
      logged_in_user = response.logged_in_user
      user.data = logged_in_user

      cookies_array = []

      all_cookies = request.get_fields('set-cookie')
      all_cookies.each do |cookie|
        cookies_array.push(cookie.split('; ')[0])
      end
      cookies = cookies_array.join('; ')
      user.config = config
      user.session = cookies

      user
    end

    def self.search_for_user_graphql(user, username)
      endpoint = "https://www.instagram.com/#{username}/?__a=1"
      result = IgApi::API.http(url: endpoint, method: 'GET', user: user)

      response = JSON.parse result.body, symbolize_names: true, object_class: OpenStruct
      return nil unless response.user.any?
    end

    def search_for_user(user, username)
      if Rails.env.test?
        rank_token = '11763263075_fdc42913-f466-46ba-9b57-5f66a8a4d375'
      else
        rank_token = IgApi::Http.generate_rank_token user.session.scan(/ds_user_id=([\d]+);/)[0][0]
      end
      endpoint = 'https://i.instagram.com/api/v1/users/search/'
      param = format('?is_typehead=true&q=%s&rank_token=%s', username, rank_token)
      result = api.get(endpoint + param)
                   .with(session: user.session, ua: user.useragent).exec

      result = JSON.parse result.body, object_class: OpenStruct

      if result.num_results > 0
        user_result = result.users[0]
        user_object = IgApi::User.new username: username
        user_object.data = user_result
        user_object.session = user.session
        user_object
      end
    end
  end
end
