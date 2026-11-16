# How long a browser may keep a file from public/, decided by its name.
#
# Angular's bundles carry a content hash (main-5OKTYVF2.js), so a new build is
# a new URL and the old one can be kept forever. Everything else keeps its URL
# across deploys — index.html, assets/i18n/*.json, sw.js, the manifest — and
# must be revalidated, or a phone pairs new code with old files. That happened:
# after a deploy the new bundle asked for capture.grid.* in an en.json cached
# for a year, and the tap grid showed raw keys.
#
# public_file_server sends "no-cache" for every file (production.rb); this only
# raises the bundles. If the pattern ever stops matching, files revalidate
# rather than go stale.
class StaticCacheControl
  FINGERPRINTED = %r{\A/(?:main|chunk|polyfills|styles)-[A-Za-z0-9_]{8}\.(?:js|css)\z}
  FOREVER = "public, max-age=31536000, immutable".freeze # one year

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["cache-control"] = FOREVER if status == 200 && FINGERPRINTED.match?(env["PATH_INFO"])
    [ status, headers, body ]
  end
end
