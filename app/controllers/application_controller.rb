class ApplicationController < ActionController::API
  include ActionController::Cookies
  include FridgeIdentifiable

  before_action :set_locale
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from Ai::Client::Error, with: :render_ai_unavailable

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
      locale: household.locale,
      created_at: household.created_at
    }
  end

  def render_not_found
    render json: { error: I18n.t("record.not_found") }, status: :not_found
  end

  def render_unprocessable(exception)
    render json: { error: exception.record&.errors&.full_messages || [ exception.message ] },
           status: :unprocessable_content
  end

  # A model outage is not the user's problem to debug, so it reads as a retry
  # prompt rather than an error code (doc 4 §4.13).
  def render_ai_unavailable(exception)
    Rails.logger.error("ai call failed: #{exception.message}")
    render json: { error: I18n.t("capture.unreadable"), retryable: true }, status: :service_unavailable
  end
end
