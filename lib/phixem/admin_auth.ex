defmodule Phixem.AdminAuth do
  @moduledoc """
  Checks the broncos admin passphrase against a PBKDF2 digest.
  The plaintext passphrase is not stored in the application.
  """

  @iterations 120_000
  @key_length 32

  @spec valid_passphrase?(term()) :: boolean()
  def valid_passphrase?(passphrase) when is_binary(passphrase) and passphrase != "" do
    salt = Application.fetch_env!(:phixem, :broncos_admin_salt)
    expected = Application.fetch_env!(:phixem, :broncos_admin_hash)
    digest = digest(passphrase, salt)
    Plug.Crypto.secure_compare(digest, expected)
  end

  def valid_passphrase?(_), do: false

  defp digest(passphrase, salt) do
    :crypto.pbkdf2_hmac(:sha256, passphrase, salt, @iterations, @key_length)
    |> Base.encode64()
  end
end
