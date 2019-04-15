require 'ostruct'
require 'ig_api/device'
require 'ig_api/constants'

module IgApi
  class User
    attr_reader :password, :language
    attr_accessor :username, :config, :session, :data

    def initialize(params = {})
      @account = nil
      @feed = nil
      @api = IgApi::Http.singleton

      if params.key? :session
        @username = params[:session].scan(/ds_user=(.*?);/)[0][0]

        id = params[:session].scan(/ds_user_id=(\d+)/)[0][0]

        if data.nil?
          @data = { id: id }
        else
          @data[:id] = id
        end
      end

      inject_variables(params)
    end

    def inject_variables(params)
      params.each { |key, value| instance_variable_set(:"@#{key}", value) }
    end

    def search_for_user(username)
      account.search_for_user(self, username)
    end

    def info_by_name(username)
      response = @api.get(Constants::URL + "users/#{username}/usernameinfo/")
                     .with(ua: useragent, session: session)
                     .exec

      JSON.parse response.body, object_class: OpenStruct
    end

    def following(limit = Float::INFINITY, data = {})
      has_next_page = true
      followers = []
      user_id = self.data[:pk]

      if Rails.env.test?
        data[:rank_token] = '11763263075_b38bc3b4-ed85-4c59-a557-1dd103bbe8755'
      else
        data[:rank_token] = IgApi::Http.generate_rank_token self.session.scan(/ds_user_id=([\d]+);/)[0][0]
      end

      while has_next_page && limit > followers.size
        response = user_following_next_page(user_id, data)
        has_next_page = !response['next_max_id'].nil?
        data[:max_id] = response['next_max_id']
        followers += response['users']
      end
      limit.infinite? ? followers : followers[0...limit]
    end

    def user_following_next_page(user_id, data)
      endpoint = "https://i.instagram.com/api/v1/friendships/#{user_id}/following/"
      param = "?rank_token=#{data[:rank_token]}" +
          (!data[:max_id].nil? ? '&max_id=' + data[:max_id] : '')

      response = @api.get(endpoint + param)
                     .with(ua: useragent, session: session)
                     .exec

      JSON.parse response.body, object_class: OpenStruct
    end


    def followers(limit = Float::INFINITY, data = {})
      has_next_page = true
      followers = []
      user_id = self.data[:pk]
      data[:rank_token] = IgApi::Http.generate_rank_token self.session.scan(/ds_user_id=([\d]+);/)[0][0]
      while has_next_page && limit > followers.size
        response = user_followers_next_page(user_id, data)
        has_next_page = !response['next_max_id'].nil?
        data[:max_id] = response['next_max_id']
        followers += response['users']
      end
      limit.infinite? ? followers : followers[0...limit]
    end

    def user_followers_next_page(user_id, data)
      endpoint = "https://i.instagram.com/api/v1/friendships/#{user_id}/followers/"
      param = "?rank_token=#{data[:rank_token]}" +
          (!data[:max_id].nil? ? '&max_id=' + data[:max_id] : '')

      response = @api.get(endpoint + param)
                     .with(ua: useragent, session: session)
                     .exec

      JSON.parse response.body, object_class: OpenStruct
    end

    def search_for_user_graphql(username)
      account.search_for_graphql(self, username)
    end

    def relationship
      unless instance_variable_defined? :@relationship
        @relationship = Relationship.new self
      end

      @relationship
    end

    def account
      @account = IgApi::Account.new if @account.nil?

      @account
    end

    def feed
      @feed = IgApi::Feed.new if @feed.nil?

      @feed.using(self)
    end

    def thread
      @thread = IgApi::Thread.new unless defined? @thread

      @thread.using self
    end

    def md5
      Digest::MD5.hexdigest @username
    end

    def md5int
      (md5.to_i(32) / 10e32).round
    end

    def api
      (18 + (md5int % 5)).to_s
    end

    # @return [string]
    def release
      %w[4.0.4 4.3.1 4.4.4 5.1.1 6.0.1][md5int % 5]
    end

    def dpi
      %w[801 577 576 538 515 424 401 373][md5int % 8]
    end

    def resolution
      %w[3840x2160 1440x2560 2560x1440 1440x2560
         2560x1440 1080x1920 1080x1920 1080x1920][md5int % 8]
    end

    def info
      line = Device.devices[md5int % Device.devices.count]
      {
        manufacturer: line[0],
        device: line[1],
        model: line[2]
      }
    end

    def useragent_hash
      agent = [api + '/' + release, dpi + 'dpi',
               resolution, info[:manufacturer],
               info[:model], info[:device], @language]

      {
        agent: agent.join('; '),
        version: Constants::PRIVATE_KEY[:APP_VERSION]
      }
    end

    def useragent
      format('Instagram %s Android(%s)', useragent_hash[:version], useragent_hash[:agent].rstrip)
    end

    def device_id
      'android-' + md5[0..15]
    end
  end
end
