module Api
  module V1
    # Create a fridge, look at it, rename it, or open one that was shared.
    # That is the whole account system.
    class FridgesController < ApplicationController
      skip_before_action :authenticate!, only: %i[create join]

      # Unauthenticated, and the door to the only expensive endpoint. A per-fridge
      # capture limit is no defence when fridges are free to mint, so the minting
      # itself is capped per client.
      #
      # A speed bump, not a wall: it is cache-backed, so a restart resets it.
      # The durable protection is Ai::Budget, which counts real spend.
      rate_limit to: 10, within: 1.hour, only: :create,
                 with: -> { render json: { error: I18n.t("auth.too_many_fridges") },
                                   status: :too_many_requests }

      # Joining is free, but the code is a capability, so guessing is capped.
      rate_limit to: 30, within: 1.hour, only: :join,
                 with: -> { render json: { error: I18n.t("auth.too_many_joins") },
                                   status: :too_many_requests }

      # Called once, on first visit, after the single onboarding question
      # ("name your fridge?" / skip).
      def create
        household = Household.create!(
          { name: params[:name].presence, locale: locale_param }.compact
        )
        refresh_cookie(household)
        render json: household_json(household), status: :created
      end

      # Trades the join code for the bearer token and the ten-year cookie.
      #
      # The code is not the token. The share link carries only the code, in the
      # URL fragment, so a page load never puts either secret in the access log.
      # The token comes back in this response, the same way creating a fridge
      # does, and the phone stores it. A phone that already had a kitchen
      # switches: the cookie is overwritten with the shared one.
      def join
        code = params[:join_code].to_s
        household = code.present? && code.length <= 64 ? Household.find_by(join_code: code) : nil
        return render json: { error: I18n.t("auth.unknown_kitchen") }, status: :not_found unless household

        refresh_cookie(household)
        household.touch_seen!
        render json: household_json(household)
      end

      def show
        render json: household_json(current_household).merge(stats: stats)
      end

      def update
        current_household.update!(
          name: params[:name].presence || current_household.name,
          locale: locale_param || current_household.locale
        )
        render json: household_json(current_household)
      end

      # Erasure is a plain row delete: ItemEvent is an audit log, not an
      # immutable ledger, so there is nothing to crypto-shred (doc 5 §5.3).
      def destroy
        current_household.destroy!
        clear_cookie
        head :no_content
      end

      private

      def locale_param
        value = params[:locale].to_s
        I18n.available_locales.map(&:to_s).include?(value) ? value : nil
      end

      def stats
        {
          items: current_household.items.active.count,
          captures: current_household.captures.count,
          memo_open: current_household.memo_items.open.count
        }
      end
    end
  end
end
