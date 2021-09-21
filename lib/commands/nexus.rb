# frozen_string_literal: true

module Gem
  module Commands
    class NexusCommand < Gem::AbstractCommand
      def description
        'Upload a gem up to Nexus server'
      end

      def arguments
        'GEM       built gem to upload. some options do not require it.'
      end

      def usage
        "#{program_name} GEM [GEM [...]]"
      end

      def list_repos
        puts
        config.repos.each do |k, v|
          puts "#{k}: #{v}"
        end
        puts
      end

      private :list_repos

      def initialize
        super 'nexus', description
        add_proxy_option

        add_option('--all-repos',
                   'list all configured repos with their respective urls.') do |value, options|
          options[:nexus_all_repos] = value
        end

        add_option('--clear-all',
                   'clears all credentials') do |value, options|
          options[:nexus_clear_all] = value
        end

        add_option('--secrets FILE',
                   'move the credentials to the given secrets file.') do |value, options|
          options[:nexus_secrets] = File.expand_path(value)
        end

        add_option('--no-secrets',
                   'move the credentials to the configuration file and delete the secrets file.') do |_value, options|
          options[:nexus_secrets] = false
        end

        add_option('--[no-]prompt',
                   'always prompt for the credentials. this is helpful to reset your username/password for a specific host.') do |value, options|
          options[:nexus_prompt_all] = value
        end

        add_option('--[no-]encrypt',
                   'encrypt/decrypt the credentials with a master password.') do |value, options|
          options[:nexus_encrypt] = value
        end
      end

      def execute
        names = begin
          get_all_gem_names
        rescue StandardError
          nil
        end
        if names && (!options[:nexus_all_repos].nil? ||
          !options[:nexus_clear_all].nil? ||
          !options[:nexus_prompt_all].nil? ||
          !options[:nexus_encrypt].nil? ||
          !options[:nexus_secrets].nil?)
          warn "given gemfile(s) #{names.join(' ')} get ignored due to the options used"
        end

        if options[:nexus_all_repos]
          list_repos
        elsif options[:nexus_prompt_all]
          if ask('setup nexus to always prompt username/passwords and delete all current credentials ? (y/N)') == 'y'
            config.always_prompt
          end
        elsif options[:nexus_prompt_all] == false
          say('setup nexus to store username/passwords')
          config.clear_always_prompt
        elsif options[:nexus_clear_all]
          config.clear_credentials if ask('delete all current credentials ? (y/N)') == 'y'
        elsif options[:nexus_encrypt]
          prompt_encryption
          config.encrypt_credentials
        elsif options[:nexus_encrypt] == false
          prompt_encryption
          config.decrypt_credentials
        elsif options[:nexus_secrets] == false
          config.new_secrets(nil)
        elsif options[:nexus_secrets]
          config.new_secrets(options[:nexus_secrets])
        else
          setup
          # if there is no gemname and no options which then fail with send_gem
          send_gem
        end
      end

      def send_gem
        gems = get_all_gem_names

        say "Uploading #{gems.size} gem#{'s' if gems.size != 1} to Nexus..."

        gems.each do |path|
          response = make_request(:put, "gems/#{File.basename(path)}") do |request|
            request.body = Gem.read_binary(path)
            request.add_field('Content-Length', request.body.size)
            request.add_field('Content-Type', 'application/octet-stream')
            request.add_field('Authorization', authorization.strip) if authorization
          end

          case response.code
          when '400'
            say 'something went wrong - maybe (re)deployment is not allowed'
          when '401'
            say 'Unauthorized'
          when '500'
            say 'something went wrong'
          else
            say "#{response.message} #{path.split(%r{/}).last}"
          end

          exit 1 unless response.is_a? Net::HTTPSuccess
        end
      end
    end
  end
end
