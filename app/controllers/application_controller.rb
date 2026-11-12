class ApplicationController < ActionController::API
  include ActionController::Cookies
  include FridgeIdentifiable

  before_action :set_locale
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from Ai::Client::Error, with: :render_unreadable
  rescue_from Ai::Client::Unavailable, with: :render_ai_unavailable

  private

  def set_locale
    locale = request.headers["X-Locale"]&.to_sym
    I18n.locale = I18n.available_locales.include?(locale) ? locale : I18n.default_locale
  end

  def household_json(household)
    {
      id: household.uuid,
      name: household.name,
      token: household.token,
      join_code: household.join_code,
      locale: household.locale,
      created_at: household.created_at
    }
  end

  # The name on this phone, if it sent one. Never required: a capture or a memo
  # line still lands when the phone has no name. Truncation lives on the model.
  def actor_name
    raw = request.headers["X-Actor-Name"].presence || params[:added_by].presence
    return if raw.blank?

    text = raw.to_s
    text = URI.decode_www_form_component(text) if text.match?(/%[0-9A-Fa-f]{2}/)
    text
  rescue ArgumentError
    nil
  end

  def render_not_found
    render json: { error: I18n.t("record.not_found") }, status: :not_found
  end

  def render_unprocessable(exception)
    render json: { error: exception.record&.errors&.full_messages || [ exception.message ] },
           status: :unprocessable_content
  end

  # The model read the photo and could not make sense of it. Retaking it is
  # genuinely worth a try, so offer that (doc 4 §4.4's three ways forward).
  def render_unreadable(exception)
    Rails.logger.error("ai parse failed: #{exception.message}")
    render json: { error: I18n.t("capture.unreadable"), retryable: true },
           status: :service_unavailable
  end

  # The provider refused — quota, credentials, an outage. Retaking the photo
  # cannot help, so say so and send them to the paths that cost nothing and
  # still work. Never an error code (doc 4 §4.13).
  def render_ai_unavailable(exception)
    Rails.logger.error("ai unavailable: #{exception.message}")
    render json: { error: I18n.t("capture.ai_unavailable"), retryable: false },
           status: :service_unavailable
  end
end
