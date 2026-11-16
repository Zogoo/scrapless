Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Identity without an account: one POST creates the fridge.
      resource :fridge, only: %i[create show update destroy], controller: "fridges" do
        post :join
        post :preview
      end

      resources :items, only: %i[index show update destroy] do
        post :resolve, on: :member
        post :undo, on: :member
        post :level, on: :collection
      end

      resources :captures, only: %i[create show]

      resources :memo_items, path: "memo", only: %i[index create update destroy] do
        collection do
          post :dictate
          get :suggestions
          post :dismiss_suggestion
          delete :clear_done
        end
      end

      resource :costs, only: :show, controller: "costs"

      resource :push_subscription, only: %i[create destroy] do
        get :key
      end
      resources :notifications, only: :index do
        post :read, on: :member
        post :read_all, on: :collection
      end
      # The first push build called it "opened"; a phone still running that
      # bundle after a deploy keeps counting.
      post "notifications/:id/opened", to: "notifications#read"

      post "recipes/suggest", to: "recipes#suggest"
    end
  end

  # Server-to-server only: the hourly Fly machine that wakes this one.
  namespace :internal do
    post "notifications/tick", to: "notifications#tick"
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
