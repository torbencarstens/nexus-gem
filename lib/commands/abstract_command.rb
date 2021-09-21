# frozen_string_literal: true

require 'rubygems/local_remote_options'
require 'net/http'
require 'base64'
require 'nexus/config'

module Gem
  class AbstractCommand < Gem::Command
    include Gem::LocalRemoteOptions

    def initialize(name, summary)
      super

      add_option('-r', '--repo KEY',
                 "pick the configuration under that key.\n                                     can be used in conjuction with --clear-repo and the upload itself.") do |value, options|
        options[:nexus_repo] = value
      end

      add_option('-c', '--clear-repo',
                 'Clears the nexus config for the given repo or the default repo') do |value, options|
        options[:nexus_clear] = value
      end

      add_option('--url URL',
                 'URL of the rubygems repository on a Nexus server') do |value, options|
        options[:nexus_url] = value
      end

      add_option('--credential USER:PASS',
                 'Enter your Nexus credentials in "Username:Password" format') do |value, options|
        options[:nexus_credential] = value
      end

      add_option('--nexus-config FILE',
                 "File location of nexus config to use.\n                                     default #{Nexus::Config.default_file}") do |value, options|
        options[:nexus_config] = File.expand_path(value)
      end

      add_option('--ignore-ssl-errors',
                 'No check certificate.') do |_value, options|
        options[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE
      end
    end

    def url
      url = config.url
      # no leading slash
      url&.sub!(%r{/$}, '')
      url
    end

    def configure_url
      url =
        if options[:nexus_url]
          options[:nexus_url]
        else
          say 'Enter the URL of the rubygems repository on a Nexus server'
          ask('URL: ')
        end

      if !URI.parse(url.to_s).host.nil?
        config.url = url

        say "The Nexus URL has been stored in #{config}"
      else
        raise 'no URL given'
      end
    end

    def setup
      prompt_encryption if config.encrypted?
      configure_url if config.url.nil? || options[:nexus_clear]
      use_proxy!(url) if http_proxy(url)
      if authorization.nil? ||
         config.always_prompt? ||
         options[:nexus_clear]
        sign_in
      end
    end

    def prompt_encryption
      password = ask_for_password('Enter your Nexus encryption credentials (no prompt)')

      # recreate config with password
      config.password = password
    end

    def sign_in
      token =
        if options[:nexus_credential]
          options[:nexus_credential]
        else
          say 'Enter your Nexus credentials'
          username = ask('Username: ')
          password = ask_for_password('Password: ')
          "#{username}:#{password}"
        end

      # mimic strict_encode64 which is not there on ruby1.8
      auth = "Basic #{Base64.encode64(token).gsub(/\s+/, '')}"
      @authorization = token == ':' ? nil : auth

      unless config.always_prompt?
        config.authorization = @authorization
        if @authorization
          say "Your Nexus credentials have been stored in #{config}"
        else
          say "Your Nexus credentials have been deleted from #{config}"
        end
      end
    end

    def this_config(_pass = nil)
      Nexus::Config.new(options[:nexus_config],
                        options[:nexus_repo])
    end

    private :this_config

    def config(pass = nil)
      @config = this_config(pass) if pass
      @config ||= this_config
    end

    def authorization
      @authorization || config.authorization
    end

    def make_request(method, path)
      require 'net/http'
      require 'net/https'

      url = URI.parse("#{self.url}/#{path}")

      http = proxy_class.new(url.host, url.port)

      if url.scheme == 'https'
        http.use_ssl = true
        http.verify_mode =
          options[:ssl_verify_mode] || config.ssl_verify_mode || OpenSSL::SSL::VERIFY_PEER
      end

      # Because sometimes our gems are huge and our people are on vpns
      http.read_timeout = 300

      request_method =
        case method
        when :get
          proxy_class::Get
        when :post
          proxy_class::Post
        when :put
          proxy_class::Put
        when :delete
          proxy_class::Delete
        else
          raise ArgumentError
        end

      request = request_method.new(url.path)
      request.add_field 'User-Agent', 'Ruby' unless RUBY_VERSION =~ /^1.9/

      yield request if block_given?

      if Gem.configuration.verbose.to_s.to_i.positive?
        warn "#{request.method} #{url}"
        if config.authorization
          warn 'use authorization'
        else
          warn 'no authorization'
        end

        warn "use proxy at #{http.proxy_address}:#{http.proxy_port}" if http.proxy_address
      end

      http.request(request)
    end

    def use_proxy!(url)
      proxy_uri = http_proxy(url)
      @proxy_class = Net::HTTP::Proxy(proxy_uri.host,
                                      proxy_uri.port,
                                      proxy_uri.user,
                                      proxy_uri.password)
    end

    def proxy_class
      @proxy_class || Net::HTTP
    end

    # @return [URI, nil] the HTTP-proxy as a URI if set; +nil+ otherwise
    def http_proxy(url)
      uri = begin
        URI.parse(url)
      rescue StandardError
        nil
      end
      return nil if uri.nil?

      no_proxy = ENV['no_proxy']
      if (no_proxy || ENV['NO_PROXY']) && no_proxy.split(/, */).member?(uri.host)
        # does not look on ip-adress ranges
        return nil
      end

      key = uri.scheme == 'http' ? 'http_proxy' : 'https_proxy'
      proxy = Gem.configuration[:http_proxy] || ENV[key] || ENV[key.upcase]
      return nil if proxy.nil? || proxy == :no_proxy

      URI.parse(proxy)
    end

    def ask_for_password(message)
      system 'stty -echo'
      password = ask(message)
      system 'stty echo'
      ui.say("\n")
      password
    end
  end
end
