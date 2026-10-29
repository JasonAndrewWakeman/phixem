defmodule PhixemWeb.Router do
  use PhixemWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhixemWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", PhixemWeb do
    pipe_through :browser

    get "/health", PageController, :health
    get "/broncosAdmin", AdminController, :show
    post "/broncosAdmin", AdminController, :create
    post "/broncosAdmin/perfect", AdminController, :save_perfect
    post "/broncosAdmin/entries", AdminController, :save_entry
    live "/", PageLive
  end
end
