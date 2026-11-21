module Api
  module V1
    # Create a fridge, look at it, rename it, or open one that was shared.
    # That is the whole account system.
    class FridgesController < ApplicationController
      skip_before_action :authenticate!, only: %i[create join preview]

      # Unauthenticated, and the door to the only expensive endpoint. A per-fridge
      # capture limit is no defence when fridges are free to mint, so the minting
      # itself is capped per client.
      #
      # A speed bump, not a wall: it is cache-backed, so a restart resets it.
      # The durable protection is Ai::Budget, which counts real spend.
      # Named, because an unnamed limiter's counter is per controller: joining a
      # few kitchens used to count against the fridge-creation limit too.
      rate_limit to: 10, within: 1.hour, only: :create, name: "create",
                 with: -> { render json: { error: I18n.t("auth.too_many_fridges") },
                                   status: :too_many_requests }

      # Joining is free, but the code is a capability, so guessing is capped —
      # and previewing a code shares the cap, or it would be a free oracle.
      rate_limit to: 30, within: 1.hour, only: %i[join preview], name: "join",
                 with: -> { render json: { error: I18n.t("auth.too_many_joins") },
                                   status: :too_many_requests }

      # Called once, on first visit, after the single onboarding question
      # ("name your fridge?" / skip).
      #
      # A browser that already holds a fridge gets that fridge back rather than a
      # new one. The welcome screen can be reached by a phone whose boot request
      # failed, and its Skip must not overwrite the cookie — on a one-phone
      # household that cookie is the only copy of the kitchen. Starting over is
      # Settings → forget, which clears it first.
      def create
        existing = identified_household
        if existing
          refresh_cookie(existing)
          return render json: household_json(existing), status: :ok
        end

        household = Household.create!(
          { name: params[:name].presence, locale: locale_param }.compact.merge(food_settings)
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
        household = shared_household
        return render_unknown_kitchen unless household

        refresh_cookie(household)
        household.touch_seen!
        render json: household_json(household)
      end

      # The kitchen's name, before anything changes on this phone, so the join
      # page can say "Open Quiet Kitchen?" — or that the link is dead — instead
      # of offering a button that fails. Name only: no token, no cookie.
      def preview
        household = shared_household
        return render_unknown_kitchen unless household

        render json: { name: household.name }
      end

      def show
        render json: household_json(current_household).merge(stats: stats)
      end

      def update
        current_household.update!(
          {
            name: params[:name].presence || current_household.name,
            locale: locale_param || current_household.locale,
            alerts_per_week: params.fetch(:alerts_per_week, current_household.alerts_per_week)
          }.merge(food_settings)
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

      def shared_household
        code = params[:join_code].to_s
        Household.find_by(join_code: code) if code.present? && code.length <= 64
      end

      def render_unknown_kitchen
        render json: { error: I18n.t("auth.unknown_kitchen") }, status: :not_found
      end

      # Only what was sent: Settings saves one field at a time, so a missing key
      # leaves that setting alone. An explicit null clears it back to "not asked".
      def food_settings
        settings = {}
        settings[:brotbox_count] = params[:brotbox_count] if params.key?(:brotbox_count)
        settings[:diet] = params[:diet].presence if params.key?(:diet)
        settings[:excluded_foods] = Array(params[:excluded_foods]).map(&:to_s) if params.key?(:excluded_foods)
        settings
      end

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
