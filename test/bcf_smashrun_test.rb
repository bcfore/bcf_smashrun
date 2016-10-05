ENV["RACK_ENV"] = "test"

# Definitely not a full test suite, just enough
# to review some of the main concepts.

require "fileutils"

require "minitest/autorun"
require "rack/test"

require_relative "../bcf_smashrun"

class BCFSmashrunTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def session
    last_request.env["rack.session"]
  end

  def test_welcome
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Welcome!"
  end

  def test_overview_no_runs
    get "/overview"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Overall running report"
    assert_includes last_response.body, "No runs yet"
  end

  def test_redirect
    get "/notapage"

    assert_equal 302, last_response.status
    assert_equal "Page not found!", session[:msg]
    assert_includes last_response["Location"], '/runs'
  end

  def test_add_one_run
    post "/runs/new",
      { date: Date.today.strftime("%F"),
        hours: 1,
        minutes: 0,
        seconds: 0,
        distance: 10 }

    assert_equal 302, last_response.status
    assert_includes last_response["Location"], '/runs'

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New!"
    assert_includes last_response.body, "1:00:00" # Duration
    assert_includes last_response.body, "10.00"   # Distance and Speed
    assert_includes last_response.body, "6:00"    # Pace

    get '/overview'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Overall running report"
    assert_includes last_response.body, "Today!" # Last run
    assert_includes last_response.body, "6:00 per km" # Pace
  end

  def test_add_two_runs
    post "/runs/new",
      { date: (Date.today - 1).strftime("%F"),
        hours: 1,
        minutes: 0,
        seconds: 0,
        distance: 10 }

    post "/runs/new",
      { date: (Date.today - 2).strftime("%F"),
        hours: 0,
        minutes: 90,
        seconds: 30,
        distance: 20 }

    assert_equal 302, last_response.status
    assert_includes last_response["Location"], '/runs'

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New!"
    assert_includes last_response.body, "1:30:30" # Duration (of 2nd run)
    assert_includes last_response.body, "13.26"   # Speed
    assert_includes last_response.body, "4:31"    # Pace

    get '/overview'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Overall running report"
    assert_includes last_response.body, "Yesterday" # Last run
    assert_includes last_response.body, "5:01 per km" # Pace
  end

  def test_add_run_with_errors
    post "/runs/new",
      { date: '9999-10-02',
        hours: '',
        minutes: '',
        seconds: '',
        distance: '' }

    assert_equal 422, last_response.status
    assert_includes last_response.body, "There are some errors in your input"
    assert_includes last_response.body, "The run date cannot be in the future"
    assert_includes last_response.body, "The total duration should be greater than 0"
    assert_includes last_response.body, "The distance should be greater than 0"
  end
end
