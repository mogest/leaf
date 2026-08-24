defmodule LeafWeb.Router do
  use LeafWeb, :router

  import LeafWeb.SignIn

  # Everything the site loads comes from the site, bar the web fonts, and there is no inline script
  # or style anywhere — so neither is allowed, and an injected one is what that stops. The
  # directives that do not fall back to `default-src` are stated in full.
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "style-src 'self' https://fonts.googleapis.com",
                               "font-src https://fonts.gstatic.com",
                               "form-action 'self'",
                               "frame-ancestors 'none'",
                               "base-uri 'self'",
                               "object-src 'none'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LeafWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
    plug :fetch_current_person
  end

  pipeline :signed_in do
    plug :require_person
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LeafWeb do
    get "/healthz", HealthController, :show
    get "/healthz/ready", HealthController, :ready
  end

  scope "/", LeafWeb do
    pipe_through :browser

    get "/sign-in", SignInController, :index
    post "/sign-in/:id", SignInController, :create
    delete "/sign-out", SignInController, :delete
  end

  # The administrator's pages come first, so that a literal segment wins over `/people/:id`.
  scope "/", LeafWeb do
    pipe_through [:browser, :signed_in]

    live_session :admin,
      on_mount: [{LeafWeb.SignIn, :current_person}, {LeafWeb.SignIn, :admin}] do
      live "/people", PeopleLive
      live "/people/new", PersonFormLive, :new
      live "/people/:person_id/edit", PersonFormLive, :edit
      live "/people/:person_id/work-patterns/new", WorkPatternLive, :new
      live "/people/:person_id/work-patterns/:id", WorkPatternLive, :edit
      live "/people/:person_id/policy-assignments/new", PolicyAssignmentLive
      live "/people/:person_id/calendar-assignments/new", CalendarAssignmentLive
      live "/people/:person_id/balance-entries/new", BalanceEntryLive

      live "/settings", OrganisationLive
      live "/settings/leave-types", LeaveTypesLive
      live "/settings/leave-types/:id", LeaveTypeLive
      live "/settings/policies", PoliciesLive
      live "/settings/policies/:id", PolicyLive
      live "/settings/policies/:policy_id/entitlements/new", EntitlementLive, :new
      live "/settings/policies/:policy_id/entitlements/:id", EntitlementLive, :edit
      live "/settings/calendars", CalendarsLive
      live "/settings/calendars/:id", CalendarLive
      live "/settings/audit", AuditLive
    end

    live_session :signed_in, on_mount: {LeafWeb.SignIn, :current_person} do
      live "/", AtAGlanceLive
      live "/leave", YourRequestsLive
      live "/leave/new", RequestLeaveLive, :new
      live "/leave/:id/amend", RequestLeaveLive, :amend
      live "/approvals", ApprovalsLive
      live "/away", WhoIsAwayLive
      live "/balances", BalancesLive
      live "/balances/:leave_type_id", BalancesLive
      live "/people/:person_id", PersonLive
      live "/people/:person_id/balances", BalancesLive
      live "/people/:person_id/balances/:leave_type_id", BalancesLive
    end
  end

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
