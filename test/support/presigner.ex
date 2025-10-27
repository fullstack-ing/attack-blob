defmodule AttackBlob.Test.Presigner do
  @moduledoc """
  Simplified AWS S3 presigner for testing AttackBlob.

  Generates presigned URLs for PUT and DELETE requests.
  """

  @sign_v4_algo "AWS4-HMAC-SHA256"
  @unsigned_payload "UNSIGNED-PAYLOAD"

  @doc """
  Signs a URL for a PUT or DELETE request.

  ## Options
  - `:bucket` - Bucket name (required)
  - `:key` - Object key (required)
  - `:method` - HTTP method (default: :put)
  - `:request_datetime` - Request datetime (default: DateTime.utc_now())
  - `:link_expiry` - URL expiry in seconds (default: 3600)
  - `:headers` - Additional headers to sign (default: %{})
  - `:query_params` - Additional query parameters to include (default: %{})

  ## Examples

      config = %{
        endpoint: "http://localhost:4004",
        access_key_id: "AKIATEST",
        secret_access_key: "secret123",
        region: "us-east-1"
      }

      presign_url(config, bucket: "test", key: "file.txt", method: :put)
  """
  def presign_url(config, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    key = Keyword.fetch!(opts, :key)
    method = Keyword.get(opts, :method, :put)
    request_datetime = Keyword.get(opts, :request_datetime, DateTime.utc_now())
    link_expiry = Keyword.get(opts, :link_expiry, 3_600)
    additional_headers = Keyword.get(opts, :headers, %{})
    query_params = Keyword.get(opts, :query_params, %{})

    uri =
      config.endpoint
      |> URI.parse()
      |> URI.merge("#{bucket}/#{key}")

    headers_to_sign =
      Map.merge(
        %{"Host" => remove_default_port(uri)},
        additional_headers
      )

    credential = credential(config, request_datetime)

    query =
      Map.merge(query_params, %{
        "X-Amz-Algorithm" => @sign_v4_algo,
        "X-Amz-Credential" => credential,
        "X-Amz-Date" => iso8601_datetime(request_datetime),
        "X-Amz-Expires" => to_string(link_expiry),
        "X-Amz-SignedHeaders" => get_signed_headers(headers_to_sign)
      })
      |> URI.encode_query()

    new_uri = Map.put(uri, :query, query)

    canonical_request = get_canonical_request(method, new_uri, headers_to_sign)
    string_to_sign = string_to_sign(config, canonical_request, request_datetime)

    signature =
      signing_key(config, request_datetime)
      |> hmac(string_to_sign)
      |> hex_digest()

    "#{URI.to_string(new_uri)}&X-Amz-Signature=#{signature}"
  end

  defp credential(config, requested_at) do
    "#{config.access_key_id}/#{short_date(requested_at)}/#{config.region}/s3/aws4_request"
  end

  defp short_date(datetime) do
    datetime
    |> iso8601_date()
    |> String.slice(0..7)
  end

  defp remove_default_port(%URI{host: host, port: port}) when port in [80, 443],
    do: to_string(host)

  defp remove_default_port(%URI{host: host, port: port}),
    do: "#{host}:#{port}"

  defp get_signed_headers(headers) do
    headers
    |> Map.keys()
    |> Enum.map(&String.downcase/1)
    |> Enum.sort()
    |> Enum.join(";")
  end

  defp get_canonical_request(method, uri, headers) do
    [
      method |> Atom.to_string() |> String.upcase(),
      uri.path,
      uri.query
    ]
    |> Kernel.++(
      Enum.sort(headers)
      |> Enum.map(fn {k, v} ->
        "#{String.downcase(k)}:#{to_string(v) |> String.trim()}"
      end)
    )
    |> Kernel.++(["", get_signed_headers(headers), @unsigned_payload])
    |> Enum.join("\n")
  end

  defp signing_key(config, request_datetime) do
    "AWS4#{config.secret_access_key}"
    |> hmac(iso8601_date(request_datetime))
    |> hmac(config.region)
    |> hmac("s3")
    |> hmac("aws4_request")
  end

  defp string_to_sign(config, canonical_request, request_datetime) do
    [
      @sign_v4_algo,
      iso8601_datetime(request_datetime),
      get_scope(config, request_datetime),
      canonical_request
      |> sha256()
      |> hex_digest()
    ]
    |> Enum.join("\n")
  end

  defp get_scope(config, request_datetime) do
    [
      iso8601_date(request_datetime),
      config.region,
      "s3",
      "aws4_request"
    ]
    |> Enum.join("/")
  end

  defp iso8601_datetime(date), do: %{date | microsecond: {0, 0}} |> DateTime.to_iso8601(:basic)
  defp iso8601_date(datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601(:basic)
  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
  defp sha256(data), do: :crypto.hash(:sha256, data)
  defp hex_digest(data), do: Base.encode16(data, case: :lower)
end
