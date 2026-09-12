Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Identity without an account: one POST creates the fridge.
      resource :fridge, only: %i[create show update destroy], controller: "fridges"

      resources :items, only: %i[index show update destroy] do
        post :resolve, on: :member
      end

      resources :captures, only: %i[create show]

      resources :memo_items, path: "memo", only: %i[index create update destroy] do
        collection do
          post :dictate
          get :suggestions
        end
      end

      resource :costs, only: :show, controller: "costs"
    end
  end

  # "/" is not matched by the catch-all below, and without this Rails serves its
  # own welcome page there in development.
  root to: "spa#index"

  # SPA catch-all: everything except the API, health check and asset-like paths
  # is served by the built Angular app.
  get "*path", to: "spa#index", constraints: ->(req) {
    !req.path.start_with?("/api/", "/up") && !req.path.match?(/\.\w+$/)
  }
end
