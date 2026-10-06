defmodule Leaf.Mailer do
  @moduledoc "Sends email through Swoosh."

  use Swoosh.Mailer, otp_app: :leaf
end
