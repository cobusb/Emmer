defmodule EmmerWeb.PageController do
  use EmmerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
