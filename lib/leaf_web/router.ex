defmodule LeafWeb.Router do
  use LeafWeb, :router

  import LeafWeb.SignIn

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LeafWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_person
  end

  pipeline :signed_in do
    plug :require_person
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LeafWeb do
    pipe_through :browser

    get "/sign-in", SignInController, :index
    post "/sign-in/:id", SignInController, :create
    delete "/sign-out", SignInController, :delete
  end

  scope "/", LeafWeb do
    pipe_through [:browser, :signed_in]

    live_session :signed_in, on_mount: {LeafWeb.SignIn, :current_person} do
      live "/", YourLeaveLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", LeafWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:leaf, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live "/styleguide", LeafWeb.StyleguideLive

      live_dashboard "/dashboard", metrics: LeafWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
