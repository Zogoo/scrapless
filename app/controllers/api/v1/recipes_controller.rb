module Api
  module V1
    # "Cook with these" — a few ideas built only from what is in the kitchen.
    class RecipesController < ApplicationController
      # Declared here so they win over ApplicationController's capture-flavoured
      # copy: "photo reading is off" means nothing on this screen. Order matters —
      # Rails tries the last declared first, and Unavailable is an Error.
      rescue_from Ai::Client::Error, with: :render_ideas_unusable
      rescue_from Ai::Client::Unavailable, with: :render_ideas_unavailable
      rescue_from Recipes::Suggest::TooMany, with: :render_too_many

      def suggest
        result = Recipes::Suggest.call(household: current_household)
        render json: { recipes: result.recipes, cached: result.cached, mode: Ai::Config.mode }
      end

      private

      def render_ideas_unavailable(exception)
        Rails.logger.error("recipes unavailable: #{exception.message}")
        render json: { error: I18n.t("recipes.ai_unavailable"), retryable: false }, status: :service_unavailable
      end

      def render_ideas_unusable(exception)
        Rails.logger.error("recipes unusable: #{exception.message}")
        render json: { error: I18n.t("recipes.unusable"), retryable: true }, status: :service_unavailable
      end

      def render_too_many
        render json: { error: I18n.t("recipes.too_many"), retryable: true }, status: :too_many_requests
      end
    end
  end
end
