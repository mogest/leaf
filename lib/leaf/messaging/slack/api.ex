defmodule Leaf.Messaging.Slack.API do
  @moduledoc """
  The Slack Web API methods Leaf calls, one function each.

  A body Slack answers with `"ok": false` is an error like any other, named by Slack's own code.
  """

  @spec lookup_by_email(String.t()) :: {:ok, String.t()} | {:error, term()}
  def lookup_by_email(email) do
    with {:ok, body} <- call("users.lookupByEmail", form: [email: email]) do
      {:ok, body["user"]["id"]}
    end
  end

  @spec post_message(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def post_message(channel, text) do
    with {:ok, body} <- call("chat.postMessage", json: %{channel: channel, text: text}) do
      {:ok, Map.take(body, ["channel", "ts"])}
    end
  end

  @spec update(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def update(channel, ts, text) do
    with {:ok, _body} <- call("chat.update", json: %{channel: channel, ts: ts, text: text}) do
      :ok
    end
  end

  defp call(method, options) do
    [url: "https://slack.com/api/" <> method, auth: {:bearer, token()}]
    |> Keyword.merge(options)
    |> Req.post()
    |> answer()
  end

  defp answer({:ok, %{status: 200, body: %{"ok" => true} = body}}), do: {:ok, body}
  defp answer({:ok, %{status: 200, body: %{"error" => error}}}), do: {:error, error}
  defp answer({:ok, response}), do: {:error, {:status, response.status}}
  defp answer({:error, exception}), do: {:error, exception}

  defp token, do: Application.fetch_env!(:leaf, Leaf.Messaging.Slack)[:token]
end
