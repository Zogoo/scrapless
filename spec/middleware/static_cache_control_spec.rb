require "rails_helper"

# Observed on fly.io: after a deploy the new bundle loaded, but en.json came
# from a year-long cache without the new keys, so the tap grid read
# "capture.grid.milk". Only a file whose name changes with its content may be
# cached for a year.
RSpec.describe StaticCacheControl do
  let(:public_files) { ->(_env) { [ 200, { "cache-control" => "no-cache" }, [ "" ] ] } }
  let(:middleware) { described_class.new(public_files) }

  def cache_control(path, app: middleware)
    app.call(Rack::MockRequest.env_for(path))[1]["cache-control"]
  end

  it "keeps a content-hashed bundle for a year" do
    %w[/main-5OKTYVF2.js /chunk-g_iRL40S.js /styles-GMZNYZZK.css /polyfills-ABCDEFGH.js].each do |path|
      expect(cache_control(path)).to eq(described_class::FOREVER), path
    end
  end

  it "revalidates every file whose name survives a deploy" do
    %w[/ /index.html /assets/i18n/en.json /sw.js /manifest.webmanifest /branding/rettich/png/icon-512.png].each do |path|
      expect(cache_control(path)).to eq("no-cache"), path
    end
  end

  it "leaves a missing bundle alone, so a 404 is not cached for a year" do
    missing = described_class.new(->(_env) { [ 404, {}, [ "" ] ] })

    expect(cache_control("/main-OLDHASH1.js", app: missing)).to be_nil
  end

  it "is what production serves public/ with by default" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to include(%(config.public_file_server.headers = { "cache-control" => "no-cache" }))
  end
end
