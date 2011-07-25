require 'ostruct'
require 'yaml'

Mime::Type.register_alias "text/html", :fbml

module FacebookFocker
	def self.included(controller)
		controller.extend(ClassMethods)
		controller.send(:include, InstanceMethods)

    controller.class_eval do
      helper_method :facebook_session
      helper_method :fql_query
      helper_method :facebook_config
      before_filter :set_facebook_session
    end
	end

	module ClassMethods
		def ensure_application_is_installed_by_facebook_user(options = {})
			before_filter :ensure_application_is_installed_by_facebook_user, options
		end

		def ensure_authenticated_to_facebook(options = {})
			before_filter :ensure_authenticated_to_facebook, options
		end
	end

	module InstanceMethods
    def facebook_config
      return @_facebook_config if @_facebook_config
      config = YAML.load(ERB.new((IO.read("#{Rails.root}/config/facebook_focker.yml"))).result)
      all_config = config['defaults'] || {}
      all_config.merge!(config[Rails.env]) if config[RAILS_ENV]
      @_facebook_config = OpenStruct.new(all_config)
    end

    def facebook_session
      return nil unless @_facebook_cookie
      return @_facebook_session if @_facebook_session

      # Setting id doesn't really play well with ruby
      response = JSON.parse(`curl "#{facebook_profile_graph_url(@_facebook_cookie)}"`)
      return nil if response['error']
        
      response['uid'] = response['id']
      response.delete('id')

      @_facebook_session = OpenStruct.new(:user => OpenStruct.new(response))
    end

		def user_authenticated_to_facebook?
			facebook_session.user.uid
		end

		def application_is_installed_by_facebook_user?
			params[:fb_sig_added].to_i == 1
		end

		def fql_query(query)
			arguments = {
				'method' => 'fql.query',
				'v' => '1.0',
      	'format' => 'json',
				'call_id' => Time.now.to_i.to_s,
				'api_key' => facebook_config.api_key,
				'session_key' => params[:fb_sig_session_key],
				'query' => query }
			query_string = arguments.collect { |k,v| "#{k}=#{urlencode(v)}" }.join('&')

      JSON.parse(`curl "https://api.facebook.com/method/fql.query?#{query_string}&sig=#{signature_for(arguments, facebook_config.secret_key)}"`)
		end

    def facebook_access_token
      @_facebook_cookie[:access_token]
    end

    def set_facebook_session
			if params[:fb_sig_user]
				@_facebook_cookie = {}
				@_facebook_cookie[:uid] = params[:fb_sig_user]
				@_facebook_cookie[:access_token] = ''
			end

      if cookie = cookies["fbs_#{facebook_config.application_id}"]
        @_facebook_cookie = {}
        cookie.gsub('"', '').split('&').each { |key_value|
          k, v = key_value.split('=')
          @_facebook_cookie[k.to_sym] = v }
      end
    end

  private

		def ensure_authenticated_to_facebok
			unless user_authenticated_to_facebook?
				render(:text => "<fb:redirect url=\"http://www.facebook.com/install.php?api_key=#{facebook_config.api_key}&v=1.0\" />")
			end
		end

		def ensure_application_is_installed_by_facebook_user
			unless application_is_installed_by_facebook_user?
				render(:text => "<fb:redirect url=\"http://www.facebook.com/install.php?api_key=#{facebook_config.api_key}&v=1.0\" />")
			end
		end

		def urlencode(str)
			str.gsub(/[^a-zA-Z0-9_\.\-]/n) { |s| sprintf('%%%02x', s[0]) }
		end

    def facebook_profile_graph_url(cookie)
      "http://graph.facebook.com/#{cookie[:uid]}?access_token=#{cookie[:access_token]}"
    end

		def signature_for(params, secret)
			params.delete_if { |k,v| v.nil? }
			signature = params.sort.collect { |k,v| 
				"#{k}=#{v}"
			}.join << secret
			Digest::MD5.hexdigest(signature)
		end
	end
end
