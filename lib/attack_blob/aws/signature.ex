defmodule AttackBlob.AWS.Signature do
  @moduledoc """
  AWS Signature Version 4 validation.

  Validates AWS S3-compliant signed requests using the AWS Signature V4 algorithm.

  Reference: https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
  """

  require Logger

  @type validation_result :: {:ok, access_key_id :: String.t()} | {:error, atom()}

  @doc """
  Validates an AWS Signature V4 signed request.

  Supports both Authorization header and presigned URL (query string) authentication.

  Returns `{:ok, access_key_id}` if the signature is valid, or `{:error, reason}` otherwise.

  ## Parameters
  - `conn` - The Plug.Conn struct containing request information
  - `secret_key` - The secret key for signature calculation

  ## Examples

      iex> validate_signature(conn, "secret_key")
      {:ok, "AKIAIOSFODNN7EXAMPLE"}

      iex> validate_signature(conn, "wrong_key")
      {:error, :signature_mismatch}
  """
  @spec validate_signature(Plug.Conn.t(), String.t()) :: validation_result()
  def validate_signature(conn, secret_key) do
    case get_authorization_header(conn) do
      {:ok, auth_header} ->
        # Header-based authentication
        validate_header_signature(conn, secret_key, auth_header)

      {:error, :missing_authorization_header} ->
        # Try presigned URL (query string) authentication
        validate_presigned_url_signature(conn, secret_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_header_signature(conn, secret_key, auth_header) do
    with {:ok, parsed} <- parse_authorization_header(auth_header),
         {:ok, canonical_request} <- build_canonical_request(conn, parsed.signed_headers),
         {:ok, string_to_sign} <- build_string_to_sign(conn, parsed, canonical_request),
         {:ok, calculated_signature} <- calculate_signature(string_to_sign, secret_key, parsed) do
      verify_signature(calculated_signature, parsed.signature, parsed.access_key_id)
    end
  end

  defp validate_presigned_url_signature(conn, secret_key) do
    with {:ok, parsed} <- parse_query_string_auth(conn),
         :ok <- validate_expiry(conn),
         {:ok, canonical_request} <- build_canonical_request_presigned(conn, parsed),
         {:ok, string_to_sign} <- build_string_to_sign(conn, parsed, canonical_request),
         {:ok, calculated_signature} <- calculate_signature(string_to_sign, secret_key, parsed) do
      verify_signature(calculated_signature, parsed.signature, parsed.access_key_id)
    end
  end

  ## Authorization Header Parsing

  defp get_authorization_header(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      [header] -> {:ok, header}
      [] -> {:error, :missing_authorization_header}
      _ -> {:error, :invalid_authorization_header}
    end
  end

  defp parse_authorization_header("AWS4-HMAC-SHA256 " <> rest) do
    with {:ok, parts} <- parse_auth_parts(rest),
         {:ok, credential} <- parse_credential(parts["Credential"]),
         {:ok, signed_headers} <- parse_signed_headers(parts["SignedHeaders"]) do
      {:ok,
       %{
         access_key_id: credential.access_key_id,
         date: credential.date,
         region: credential.region,
         service: credential.service,
         signed_headers: signed_headers,
         signature: parts["Signature"]
       }}
    end
  end

  defp parse_authorization_header(_), do: {:error, :invalid_authorization_format}

  defp parse_auth_parts(auth_string) do
    parts =
      auth_string
      |> String.split(", ")
      |> Enum.map(fn part ->
        case String.split(part, "=", parts: 2) do
          [key, value] -> {key, value}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    case Map.has_key?(parts, "Credential") and Map.has_key?(parts, "Signature") do
      true -> {:ok, parts}
      false -> {:error, :missing_required_parts}
    end
  end

  defp parse_credential(nil), do: {:error, :missing_credential}

  defp parse_credential(credential_string) do
    case String.split(credential_string, "/") do
      [access_key_id, date, region, service, "aws4_request"] ->
        {:ok,
         %{
           access_key_id: access_key_id,
           date: date,
           region: region,
           service: service
         }}

      _ ->
        {:error, :invalid_credential_format}
    end
  end

  defp parse_signed_headers(nil), do: {:error, :missing_signed_headers}

  defp parse_signed_headers(headers_string) do
    headers = String.split(headers_string, ";")
    {:ok, headers}
  end

  ## Presigned URL (Query String) Authentication Parsing

  defp validate_expiry(conn) do
    with {:ok, amz_date} <- get_query_param(conn.query_params, "X-Amz-Date"),
         {:ok, expires_str} <- get_query_param(conn.query_params, "X-Amz-Expires"),
         {:ok, request_time} <- parse_amz_date(amz_date),
         {:ok, expires_seconds} <- parse_integer(expires_str) do
      expiry_time = DateTime.add(request_time, expires_seconds, :second)
      current_time = DateTime.utc_now()

      if DateTime.compare(current_time, expiry_time) == :lt do
        :ok
      else
        {:error, :signature_expired}
      end
    else
      {:error, :missing_query_parameter} -> {:error, :invalid_presigned_url}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_amz_date(date_string) do
    # X-Amz-Date format: 20251027T045110Z (ISO 8601 basic format)
    case DateTime.from_iso8601(format_iso8601_basic(date_string)) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, :invalid_date_format}
    end
  end

  defp format_iso8601_basic(
         <<year::binary-size(4), month::binary-size(2), day::binary-size(2), "T",
           hour::binary-size(2), minute::binary-size(2), second::binary-size(2), "Z">>
       ) do
    "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
  end

  defp format_iso8601_basic(_), do: ""

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, _} -> {:ok, int}
      :error -> {:error, :invalid_integer}
    end
  end

  defp parse_query_string_auth(conn) do
    params = conn.query_params

    with {:ok, algorithm} <- get_query_param(params, "X-Amz-Algorithm"),
         true <- algorithm == "AWS4-HMAC-SHA256",
         {:ok, credential_string} <- get_query_param(params, "X-Amz-Credential"),
         {:ok, credential} <- parse_credential(credential_string),
         {:ok, signed_headers_string} <- get_query_param(params, "X-Amz-SignedHeaders"),
         {:ok, signed_headers} <- parse_signed_headers(signed_headers_string),
         {:ok, signature} <- get_query_param(params, "X-Amz-Signature") do
      {:ok,
       %{
         access_key_id: credential.access_key_id,
         date: credential.date,
         region: credential.region,
         service: credential.service,
         signed_headers: signed_headers,
         signature: signature,
         presigned: true
       }}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_algorithm}
    end
  end

  defp get_query_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, :missing_query_parameter}
      value -> {:ok, value}
    end
  end

  ## Canonical Request

  defp build_canonical_request(conn, signed_headers) do
    method = conn.method
    uri = build_canonical_uri(conn)
    query_string = build_canonical_query_string(conn)
    canonical_headers = build_canonical_headers(conn, signed_headers)
    signed_headers_string = Enum.join(signed_headers, ";")
    payload_hash = get_payload_hash(conn)

    canonical_request =
      [
        method,
        uri,
        query_string,
        canonical_headers,
        "",
        signed_headers_string,
        payload_hash
      ]
      |> Enum.join("\n")

    {:ok, canonical_request}
  end

  defp build_canonical_request_presigned(conn, parsed) do
    method = conn.method
    uri = build_canonical_uri(conn)
    # For presigned URLs, exclude X-Amz-Signature from the canonical query string
    query_string = build_canonical_query_string_presigned(conn)
    header_lines = build_canonical_header_lines(conn, parsed.signed_headers)
    signed_headers_string = Enum.join(parsed.signed_headers, ";")
    # Presigned URLs always use UNSIGNED-PAYLOAD
    payload_hash = "UNSIGNED-PAYLOAD"

    # Build array like the presigner does, then join
    canonical_request =
      [method, uri, query_string]
      |> Kernel.++(header_lines)
      |> Kernel.++(["", signed_headers_string, payload_hash])
      |> Enum.join("\n")

    {:ok, canonical_request}
  end

  defp build_canonical_header_lines(conn, signed_headers) do
    conn.req_headers
    |> Enum.filter(fn {name, _} -> String.downcase(name) in signed_headers end)
    |> Enum.map(fn {name, value} -> {String.downcase(name), String.trim(value)} end)
    |> Enum.sort()
    |> Enum.map(fn {name, value} -> "#{name}:#{value}" end)
  end

  defp build_canonical_uri(conn) do
    # URI-encode each path segment
    conn.path_info
    |> Enum.map(fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
    |> Enum.join("/")
    |> then(&("/" <> &1))
  end

  defp build_canonical_query_string(conn) do
    case conn.query_string do
      "" -> ""
      query -> query |> URI.decode_query() |> Enum.sort() |> URI.encode_query()
    end
  end

  defp build_canonical_query_string_presigned(conn) do
    case conn.query_string do
      "" ->
        ""

      query ->
        # Remove X-Amz-Signature from the query string WITHOUT re-encoding
        # This preserves the exact encoding that the presigner used
        query
        |> String.split("&")
        |> Enum.reject(fn param -> String.starts_with?(param, "X-Amz-Signature=") end)
        |> Enum.join("&")
    end
  end

  defp build_canonical_headers(conn, signed_headers) do
    conn.req_headers
    |> Enum.filter(fn {name, _} -> String.downcase(name) in signed_headers end)
    |> Enum.map(fn {name, value} -> {String.downcase(name), String.trim(value)} end)
    |> Enum.sort()
    |> Enum.map(fn {name, value} -> "#{name}:#{value}\n" end)
    |> Enum.join()
  end

  defp get_payload_hash(conn) do
    # Try to get from x-amz-content-sha256 header first
    case Plug.Conn.get_req_header(conn, "x-amz-content-sha256") do
      [hash] -> hash
      [] -> "UNSIGNED-PAYLOAD"
    end
  end

  ## String to Sign

  defp build_string_to_sign(conn, parsed, canonical_request) do
    request_datetime = get_request_datetime(conn)
    credential_scope = "#{parsed.date}/#{parsed.region}/#{parsed.service}/aws4_request"

    hashed_canonical_request =
      :crypto.hash(:sha256, canonical_request)
      |> Base.encode16(case: :lower)

    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        request_datetime,
        credential_scope,
        hashed_canonical_request
      ]
      |> Enum.join("\n")

    {:ok, string_to_sign}
  end

  defp get_request_datetime(conn) do
    # Check header first (for standard requests)
    case Plug.Conn.get_req_header(conn, "x-amz-date") do
      [datetime] ->
        datetime

      [] ->
        # Check query params (for presigned URLs)
        case Map.get(conn.query_params, "X-Amz-Date") do
          nil -> ""
          datetime -> datetime
        end
    end
  end

  ## Signature Calculation

  defp calculate_signature(string_to_sign, secret_key, parsed) do
    date_key = hmac_sha256("AWS4" <> secret_key, parsed.date)
    date_region_key = hmac_sha256(date_key, parsed.region)
    date_region_service_key = hmac_sha256(date_region_key, parsed.service)
    signing_key = hmac_sha256(date_region_service_key, "aws4_request")

    signature =
      hmac_sha256(signing_key, string_to_sign)
      |> Base.encode16(case: :lower)

    {:ok, signature}
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  ## Signature Verification

  defp verify_signature(calculated, provided, access_key_id) do
    case Plug.Crypto.secure_compare(calculated, provided) do
      true -> {:ok, access_key_id}
      false -> {:error, :signature_mismatch}
    end
  end
end
