ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../bcf_app_name"

class BCFTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
  end

  def teardown
  end

  def session
    last_request.env["rack.session"]
  end

#  def admin_session
#    { "rack.session" => { user: "admin" } }
#  end

  def test_index
    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
  end
end
