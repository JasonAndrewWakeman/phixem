defmodule PhixemWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PhixemWeb.Endpoint

      use PhixemWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PhixemWeb.ConnCase
    end
  end

  setup tags do
    Phixem.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
