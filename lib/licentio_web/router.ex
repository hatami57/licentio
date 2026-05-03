defmodule LicentioWeb.Router do
  use LicentioWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug LicentioWeb.Plugs.LoadTenant
  end

  scope "/api", LicentioWeb do
    pipe_through :api

    resources "/tenants", TenantController, only: [:create, :show]

    scope "/tenants/:tenant_id" do
      resources "/features", FeatureController, only: [:index, :create]

      resources "/features", FeatureController, only: [:index, :create]

      resources "/plans", PlanController, only: [:index, :create] do
        post "/features", PlanController, :add_feature
        post "/prices", PlanController, :add_price
      end

      scope "/users/:user_id" do
        post "/", UserController, :register
        get "/license", LicenseController, :show
        post "/license", LicenseController, :grant

        get "/features/:code", AccessController, :check
        post "/features/:code/consume", AccessController, :consume
        post "/features/:code/reclaim", AccessController, :reclaim
      end
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:licentio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: LicentioWeb.Telemetry
    end
  end
end
