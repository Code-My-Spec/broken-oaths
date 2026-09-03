defmodule BrokenOathsWeb.Router do
  use BrokenOathsWeb, :router

  import BrokenOathsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BrokenOathsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Must come AFTER put_secure_browser_headers: that plug sends
    # frame-ancestors 'self', which silently refuses the CodeMySpec
    # agent-conversation preview pane (blank iframe, no error) — this
    # overwrites it for the preview case. otp_app tells the plug which
    # app it's protecting; without it, it's a no-op.
    plug ClientUtils.PreviewFraming, otp_app: :broken_oaths
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BrokenOathsWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/roadmap", PageController, :roadmap
    get "/worlds/:id/texture.png", WorldTextureController, :show
    get "/worlds/:id/airspace.png", WorldTextureController, :airspace

    live_session :worlds,
      layout: {BrokenOathsWeb.Layouts, :app_full},
      on_mount: [{BrokenOathsWeb.UserAuth, :mount_current_scope}] do
      live "/worlds", WorldLive.Index, :index
      live "/worlds/new", WorldLive.New, :new
      live "/worlds/:id", WorldLive.Show, :show
    end
  end

  # Registered-users read model for the CodeMySpec dashboard
  # (deploy-key Bearer auth inside the controller, not a session).
  scope "/api/cms", BrokenOathsWeb do
    pipe_through :api

    get "/users", CmsUsersController, :index
  end

  # Ask an integration to prove itself, on demand.
  #
  # Separate from `/up` deliberately: the proxy gates the traffic swap on
  # that route, so it stays shallow. These actions reach a dependency for
  # real — the widget's socket, its credential, its origin — which is
  # exactly what must not decide whether traffic moves.
  #
  # Under `/_cms` so it cannot collide with the application's own routes,
  # and behind the project's deploy key, which this app already holds.
  # Each action can only make its integration *speak*; none of them can
  # take the app down.
  scope "/_cms", BrokenOathsWeb do
    pipe_through :api

    post "/verify/widget", VerifyController, :widget

    # Down by construction, so a monitor can be proven to notice something
    # without anything real being broken. Unauthenticated: a monitor will
    # not carry a credential, and a constant reveals nothing.
    get "/verify/always-failing", VerifyController, :always_failing
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:broken_oaths, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BrokenOathsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Dev-only QA control surface (see `BrokenOathsWeb.DevQaController`'s
    # moduledoc for the full endpoint list and example curl calls) —
    # gated behind the same `:dev_routes` compile_env flag as
    # LiveDashboard above, so it never exists in a production build
    # (false in `config/prod.exs`). No auth: dev-only, localhost.
    scope "/dev/qa", BrokenOathsWeb do
      pipe_through :api

      get "/worlds/:id", DevQaController, :show
      post "/worlds/:id/reload", DevQaController, :reload
      post "/worlds/:id/pause", DevQaController, :pause
      post "/worlds/:id/resume", DevQaController, :resume
      post "/worlds/:id/step", DevQaController, :step
      post "/worlds/:id/units", DevQaController, :spawn_unit
      post "/worlds/:id/barbarians", DevQaController, :spawn_barbarian
      patch "/worlds/:id/units/:unit_id", DevQaController, :update_unit
      delete "/worlds/:id/units/:unit_id", DevQaController, :delete_unit
      patch "/worlds/:id/camps/:camp_id", DevQaController, :update_camp
    end
  end

  ## Authentication routes

  scope "/", BrokenOathsWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BrokenOathsWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/accounts", AccountLive.Index, :index
      live "/accounts/picker", AccountLive.Picker, :index
      live "/accounts/:id", AccountLive.Manage, :show
      live "/accounts/:id/manage", AccountLive.Manage, :show
      live "/accounts/:id/members", AccountLive.Members, :show
      live "/accounts/:id/invitations", AccountLive.Invitations, :show
      live "/integrations", IntegrationLive.Index, :index

      live "/play", GameLive.Join, :index
      live "/play/:id", GameLive.Play, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # Social login entry + shared OAuth callback — both must work for
  # unauthenticated visitors (the callback serves the login flow too;
  # it guards the integration flow itself when no user is present).
  scope "/integrations/oauth", BrokenOathsWeb do
    pipe_through :browser
    get "/login/:provider", IntegrationsController, :login
    get "/callback/:provider", IntegrationsController, :callback
    # The redirect URI shape registered in the Google Cloud console.
    get "/:provider/callback", IntegrationsController, :callback
  end

  scope "/integrations/oauth", BrokenOathsWeb do
    pipe_through [:browser, :require_authenticated_user]
    get "/:provider", IntegrationsController, :request
  end

  scope "/", BrokenOathsWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BrokenOathsWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      live "/invitations/accept/:token", InvitationsLive.Accept, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
