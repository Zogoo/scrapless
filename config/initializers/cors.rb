# The fridge identity travels as a signed cookie as well as a bearer token, so
# cross-origin requests must be allowed to carry credentials.
#
# That has a consequence worth stating: a browser rejects
# `Access-Control-Allow-Origin: *` on any credentialed request, so the origins
# here can never be a wildcard — they are an explicit list, always.
#
# In production Rails serves the built Angular app from public/, so this is
# same-origin and never exercised. It exists for the split-origin dev setup
# (Angular on :4200, Rails on :3001), which is why the default is the dev
# origin rather than nothing: with no default the whole block used to switch
# itself off and every dev request failed with an opaque "you're offline".
origins = ENV.fetch("CORS_ORIGINS", "http://localhost:4200").split(",").map(&:strip).reject(&:blank?)

if origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*origins)

      resource "/api/*",
        headers: :any,
        credentials: true,
        methods: %i[get post put patch delete options head],
        expose: %w[Authorization],
        max_age: 600
    end
  end
end
