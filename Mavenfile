#-*- mode: ruby -*-

spec = Gem::Specification.load( 'nexus.gemspec' )

parent 'org.sonatype.nexus.ruby:nexus-ruby-support', '1.0.1-SNAPSHOT'

group_id 'rubygems'
artifact_id spec.name
version "#{spec.version}"

packaging :gem

extension 'de.saumya.mojo:gem-extension'

description spec.description
url spec.homepage
name spec.summary

#license( spec.license )

plugin( 'de.saumya.mojo:gem-maven-plugin', '${jruby.plugins.version}',
        :gemspec => 'nexus.gemspec' ) do
  execute_goals :id => 'default-push', :skip => true
end

plugin :deploy, :skip => true
plugin( 'org.sonatype.plugins:nexus-staging-maven-plugin',
        :skipNexusStagingDeployMojo => true )

inherited do
  plugin( 'org.eclipse.m2e:lifecycle-mapping', '1.0.0',
          :lifecycleMappingMetadata => {
            :pluginExecution => [ :action => { :ignore => nil },
                                  :pluginExecutionFilter => {
                                    :groupId => 'de.saumya.mojo',
                                    :artifactId => 'gem-maven-plugin',
                                    :versionRange => '[0,)',
                                    :goals => [ :initialize ]
                                  } ]
            } )
end

profile( :push ) do
  gemspec

  # bug in gemspec above
  id :push

  build.default_goal = :deploy

  phase :test do
    plugin 'de.saumya.mojo:runit-maven-plugin', '${jruby.plugins.version}' do
      execute_goals( :test )
    end
  end
end

# lock down versions
properties( 'jruby.version' => '1.7.4',
            'jruby.plugins.version' => '1.0.0-rc',
            'tesla.dump.pom' => 'pom.xml',
            'tesla.dump.readonly' => true )

# needed for ruby maven to work
jar 'org.jruby:jruby-complete', '${jruby.version}', :scope => :provided
# vim: syntax=Ruby