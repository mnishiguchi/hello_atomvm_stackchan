defmodule SampleApp do
  @moduledoc false

  def start do
    {:ok, _pid} = SampleApp.FaceServer.start_link()
    Process.sleep(:infinity)
  end
end
