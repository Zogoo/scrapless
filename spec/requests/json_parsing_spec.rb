require "rails_helper"

# Regression guard for a class of bug that ordinary request specs miss.
#
# `post ..., params: {...}` sends form-encoded data. Real clients send
# `Content-Type: application/json`, which goes through ActionDispatch's
# parameter parser and `ActiveSupport::JSON.decode`. Those are different code
# paths, and a break in the JSON one takes down every real request while a
# form-encoded suite stays green.
#
# This happened: json 3.0 made `JSON.parse` keyword-only while ActiveSupport
# still passed its options hash positionally, so under Ruby 3.4 the API
# returned 400 for everything. The Gemfile pins json to 2.x; these examples
# make sure the parser is actually exercised.
RSpec.describe "JSON request parsing", type: :request do
  it "parses a JSON request body" do
    post "/api/v1/fridge", params: { name: "Küche" }, as: :json

    expect(response).to have_http_status(:created),
      "a JSON body failed to parse — check ActiveSupport::JSON.decode and the json gem pin"
    expect(response.parsed_body).to include("token")
  end

  it "decodes JSON through ActiveSupport, which is what the parser uses" do
    expect(ActiveSupport::JSON.decode('{"a":1}')).to eq("a" => 1)
  end
end
