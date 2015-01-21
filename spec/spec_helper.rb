#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2015 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

require 'rubygems'
if ENV['CI'] == 'true'
  # we are running on a CI server, report coverage to code climate
  require 'codeclimate-test-reporter'
  CodeClimate::TestReporter.start
end

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rspec/rails'

require 'rspec/autorun'
require 'rspec/example_disabler'
require 'capybara/rails'

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }
Dir[Rails.root.join('spec/features/support/**/*.rb')].each { |f| require f }
Dir[Rails.root.join('spec/lib/api/v3/support/**/*.rb')].each { |f| require f }
Dir[Rails.root.join('spec/requests/api/v3/support/**/*.rb')].each { |f| require f }

RSpec.configure do |config|
  # ## Mock Framework
  #
  # If you prefer to use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr
  config.mock_with :rspec

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = "#{::Rails.root}/spec/fixtures"

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  #
  # Taken from http://stackoverflow.com/questions/21922046/deadlock-detected-with-capybara-webkit
  # which replaces the one we had before taken from http://stackoverflow.com/a/13234966
  # Thanks a lot!
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation
  end

  config.before(:each) do |example|
    DatabaseCleaner.strategy = if example.metadata[:js]
                                 # JS => doesn't share connections => can't use transactions
                                 # truncations seem to fail more often + they are slower
                                 :deletion
                               else
                                 # No JS/Devise => run with Rack::Test => transactions are ok
                                 :transaction
                               end

    DatabaseCleaner.start

    acc = Multitenancy::Account.new owner: 'public',
                                    domain: 'example.org',
                                    namespace: 'public'
    acc.save validate: false

    allow(OpenProject::OmniAuth::Authorization).to receive(:callbacks).and_return([])
    allow(OpenProject::OmniAuth::Authorization).to receive(:after_login_callbacks).and_return([])
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  # If true, the base class of anonymous controllers will be inferred
  # automatically. This will be the default behavior in future versions of
  # rspec-rails.
  config.infer_base_class_for_anonymous_controllers = false

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'

  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true

  # add helpers to parse json-responses
  config.include JsonSpec::Helpers

  config.after(:each) do |example|
    OpenProject::RSpecLazinessWarn.warn_if_user_current_set(example)
  end

  config.after(:each) do
    # Cleanup after specs changing locale explicitly or
    # by calling code in the app setting changing the locale.
    I18n.locale = :en
  end

  config.after(:suite) do
    [User, Project, WorkPackage].each do |cls|
      raise "your specs leave a #{cls} in the DB\ndid you use before(:all) instead of before or forget to kill the instances in a after(:all)?" if cls.count > 0
    end
  end

  config.mock_with :rspec do |c|
    c.yield_receiver_to_any_instance_implementation_blocks = true
  end

  # include spec/api for API request specs
  config.include RSpec::Rails::RequestExampleGroup, type: :request, example_group: { file_path: /spec\/api/ }
end

# load disable_specs.rbs from plugins
Rails.application.config.plugins_to_test_paths.each do |dir|
  disable_specs_file = File.join(dir, 'spec', 'disable_specs.rb')
  if File.exists?(disable_specs_file)
    puts 'Loading ' + disable_specs_file
    require disable_specs_file
  end
end

module OpenProject::RSpecLazinessWarn
  def self.warn_if_user_current_set(example)
    # Using the hacky way of getting current_user to avoid under the hood creation of AnonymousUser
    # which might break other tests and at least leaves this user in the db after the test is run.
    user = User.instance_variable_get(:@current_user)
    unless user.nil? or user.is_a? AnonymousUser
      # we only want an abbreviated_stacktrace because the logfiles
      # might otherwise not be capable to show all the warnings.
      # Thus we only take the callers that are part of the user code.
      file_roots = Rails::Application::Railties.engines.map { |e| e.root.to_s } << Rails.root.to_s
      abbreviated_stacktrace = example.metadata[:caller].select { |s| file_roots.any? { |root| s.include?(root) } }

      # we only want to show the more verbose warning once
      if warned
        warn <<-DOC

              ============================================================================================
              #{ example.full_description }
              ============================================================================================
              This spec also leaves User.current in an unclean state.
              ============================================================================================
              #{ abbreviated_stacktrace.join("\n              ") }
              ============================================================================================
        DOC
      else
        warn <<-DOC

                ============================================================================================
                #{ example.full_description }
                ============================================================================================
                This spec leaves User.current in an unclean state, creating a dependency to other specs.

                It sets User.current to a value other than User.anonymous but does not clean up after the
                spec is run. User.current saves this value in an instance variable of the User class.
                This class instance variable is not removed between tests.

                So please go ahead and set User.current to nil afterwards.
                ============================================================================================

                Abbreviated stacktrace:

                #{ abbreviated_stacktrace.join("\n              ") }

                ============================================================================================


        DOC

        self.warned = true
      end

      User.current = nil
    end
  end

  protected

  class << self
    attr_accessor :warned
  end
end

OpenProject::Configuration['attachments_storage_path'] = 'tmp/files'
