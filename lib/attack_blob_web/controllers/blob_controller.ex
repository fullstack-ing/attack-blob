defmodule AttackBlobWeb.BlobController do
  use AttackBlobWeb, :controller
  require Logger

  alias AttackBlob.AWS.Signature
  alias AttackBlob.KeyManager

  @doc """
  GET /:bucket - List objects in a bucket

  Returns a JSON list of all objects in the bucket with their metadata.
  Query parameters:
  - prefix: Filter objects by prefix
  - delimiter: Group objects by common prefixes (e.g., "/" for folders)
  - max_keys: Maximum number of keys to return (default: 1000)
  """
  def list_objects(conn, %{"bucket" => bucket} = params) do
    with :ok <- validate_bucket_name(bucket),
         {:ok, bucket_path} <- get_bucket_path(bucket),
         true <- File.dir?(bucket_path) do
      prefix = Map.get(params, "prefix", "")
      delimiter = Map.get(params, "delimiter")
      max_keys = Map.get(params, "max_keys", "1000") |> parse_max_keys()

      objects = list_bucket_objects(bucket_path, prefix, delimiter, max_keys)

      conn
      |> put_resp_content_type("application/json")
      |> json(%{
        bucket: bucket,
        prefix: prefix,
        objects: objects.objects,
        common_prefixes: objects.common_prefixes,
        is_truncated: objects.is_truncated,
        key_count: length(objects.objects)
      })
    else
      {:error, :invalid_bucket_name} ->
        send_error(conn, 400, "Invalid bucket name")

      false ->
        send_error(conn, 404, "Bucket not found")
    end
  end

  @doc """
  GET /:bucket/*key - Retrieve an object from a bucket

  Returns the object content with appropriate headers:
  - Content-Type
  - Content-Length
  - ETag (MD5 hash)
  - Last-Modified
  - Cache-Control
  """
  def get_object(conn, %{"bucket" => bucket, "key" => key}) do
    with :ok <- validate_bucket_name(bucket),
         :ok <- validate_object_key(key),
         {:ok, file_path} <- build_file_path(bucket, key),
         {:ok, stat} <- File.stat(file_path),
         true <- stat.type == :regular do
      # Calculate ETag (MD5 hash of file)
      etag = calculate_etag(file_path)

      # Determine content type
      content_type = MIME.from_path(key)

      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("content-length", "#{stat.size}")
      |> put_resp_header("etag", "\"#{etag}\"")
      |> put_resp_header("last-modified", format_http_date(stat.mtime))
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_file(200, file_path)
    else
      {:error, :invalid_bucket_name} ->
        send_error(conn, 400, "Invalid bucket name")

      {:error, :invalid_object_key} ->
        send_error(conn, 400, "Invalid object key")

      {:error, :enoent} ->
        send_error(conn, 404, "Object not found")

      {:error, :path_traversal} ->
        Logger.warning("Path traversal attempt detected: bucket=#{bucket}, key=#{key}")
        send_error(conn, 400, "Invalid object key")

      false ->
        # File exists but is not a regular file (directory, symlink, etc.)
        send_error(conn, 404, "Object not found")

      {:error, reason} ->
        Logger.error("Error retrieving object: #{inspect(reason)}")
        send_error(conn, 500, "Internal server error")
    end
  end

  @doc """
  PUT /:bucket/*key - Upload an object to a bucket

  Requires AWS Signature V4 authentication. The request must include:
  - Authorization header with AWS4-HMAC-SHA256 signature
  - x-amz-date header with request timestamp
  - x-amz-content-sha256 header with payload hash

  Returns 200 on success with ETag header.
  """
  def put_object(conn, %{"bucket" => bucket, "key" => key}) do
    with :ok <- validate_bucket_name(bucket),
         :ok <- validate_object_key(key),
         {:ok, access_key_id} <- authenticate_request(conn),
         {:ok, access_key} <- KeyManager.lookup(access_key_id),
         :ok <- authorize_bucket_access(access_key, bucket),
         :ok <- check_permission(access_key, "put"),
         {:ok, file_path} <- build_file_path(bucket, key),
         {:ok, body} <- read_request_body(conn),
         :ok <- write_file(file_path, body) do
      # Calculate ETag for the uploaded file
      etag = calculate_etag(file_path)

      conn
      |> put_resp_header("etag", "\"#{etag}\"")
      |> send_resp(200, "")
    else
      {:error, :invalid_bucket_name} ->
        send_error(conn, 400, "Invalid bucket name")

      {:error, :invalid_object_key} ->
        send_error(conn, 400, "Invalid object key")

      {:error, :missing_authorization_header} ->
        send_error(conn, 401, "Missing authorization header")

      {:error, :invalid_authorization_header} ->
        send_error(conn, 401, "Invalid authorization header")

      {:error, :invalid_authorization_format} ->
        send_error(conn, 401, "Invalid authorization format")

      {:error, :signature_mismatch} ->
        Logger.warning("Signature mismatch for bucket=#{bucket}, key=#{inspect(key)}")
        send_error(conn, 403, "Signature mismatch")

      {:error, :signature_expired} ->
        send_error(conn, 403, "Request has expired")

      {:error, :access_key_not_found} ->
        send_error(conn, 403, "Invalid access key")

      {:error, :bucket_access_denied} ->
        send_error(conn, 403, "Access denied to bucket")

      {:error, :permission_denied} ->
        send_error(conn, 403, "Permission denied")

      {:error, :path_traversal} ->
        Logger.warning("Path traversal attempt detected: bucket=#{bucket}, key=#{inspect(key)}")
        send_error(conn, 400, "Invalid object key")

      {:error, :body_too_large} ->
        send_error(conn, 413, "Request entity too large")

      {:error, reason} ->
        Logger.error("Error uploading object: #{inspect(reason)}")
        send_error(conn, 500, "Internal server error")
    end
  end

  @doc """
  DELETE /:bucket/*key - Delete an object from a bucket

  Requires AWS Signature V4 authentication. The request must include:
  - Authorization header with AWS4-HMAC-SHA256 signature
  - x-amz-date header with request timestamp
  - x-amz-content-sha256 header with payload hash

  Returns 204 No Content on success.
  """
  def delete_object(conn, %{"bucket" => bucket, "key" => key}) do
    with :ok <- validate_bucket_name(bucket),
         :ok <- validate_object_key(key),
         {:ok, access_key_id} <- authenticate_request(conn),
         {:ok, access_key} <- KeyManager.lookup(access_key_id),
         :ok <- authorize_bucket_access(access_key, bucket),
         :ok <- check_permission(access_key, "delete"),
         {:ok, file_path} <- build_file_path(bucket, key),
         :ok <- delete_file(file_path) do
      send_resp(conn, 204, "")
    else
      {:error, :invalid_bucket_name} ->
        send_error(conn, 400, "Invalid bucket name")

      {:error, :invalid_object_key} ->
        send_error(conn, 400, "Invalid object key")

      {:error, :missing_authorization_header} ->
        send_error(conn, 401, "Missing authorization header")

      {:error, :invalid_authorization_header} ->
        send_error(conn, 401, "Invalid authorization header")

      {:error, :invalid_authorization_format} ->
        send_error(conn, 401, "Invalid authorization format")

      {:error, :signature_mismatch} ->
        Logger.warning("Signature mismatch for DELETE bucket=#{bucket}, key=#{inspect(key)}")
        send_error(conn, 403, "Signature mismatch")

      {:error, :signature_expired} ->
        send_error(conn, 403, "Request has expired")

      {:error, :access_key_not_found} ->
        send_error(conn, 403, "Invalid access key")

      {:error, :bucket_access_denied} ->
        send_error(conn, 403, "Access denied to bucket")

      {:error, :permission_denied} ->
        send_error(conn, 403, "Permission denied")

      {:error, :path_traversal} ->
        Logger.warning("Path traversal attempt detected: bucket=#{bucket}, key=#{inspect(key)}")
        send_error(conn, 400, "Invalid object key")

      {:error, :enoent} ->
        send_error(conn, 404, "Object not found")

      {:error, reason} ->
        Logger.error("Error deleting object: #{inspect(reason)}")
        send_error(conn, 500, "Internal server error")
    end
  end

  @doc """
  HEAD /:bucket/*key - Get object metadata without content

  Returns the same headers as GET but without the body.
  """
  def head_object(conn, %{"bucket" => bucket, "key" => key}) do
    with :ok <- validate_bucket_name(bucket),
         :ok <- validate_object_key(key),
         {:ok, file_path} <- build_file_path(bucket, key),
         {:ok, stat} <- File.stat(file_path),
         true <- stat.type == :regular do
      # Calculate ETag (MD5 hash of file)
      etag = calculate_etag(file_path)

      # Determine content type
      content_type = MIME.from_path(key)

      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("content-length", "#{stat.size}")
      |> put_resp_header("etag", "\"#{etag}\"")
      |> put_resp_header("last-modified", format_http_date(stat.mtime))
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, "")
    else
      {:error, :invalid_bucket_name} ->
        send_error(conn, 400, "Invalid bucket name")

      {:error, :invalid_object_key} ->
        send_error(conn, 400, "Invalid object key")

      {:error, :enoent} ->
        send_error(conn, 404, "Object not found")

      {:error, :path_traversal} ->
        Logger.warning("Path traversal attempt detected: bucket=#{bucket}, key=#{key}")
        send_error(conn, 400, "Invalid object key")

      false ->
        send_error(conn, 404, "Object not found")

      {:error, reason} ->
        Logger.error("Error retrieving object metadata: #{inspect(reason)}")
        send_error(conn, 500, "Internal server error")
    end
  end

  ## Private Functions

  defp validate_bucket_name(name) when byte_size(name) < 3, do: {:error, :invalid_bucket_name}
  defp validate_bucket_name(name) when byte_size(name) > 63, do: {:error, :invalid_bucket_name}

  defp validate_bucket_name(name) do
    case Regex.match?(~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/, name) do
      true -> :ok
      false -> {:error, :invalid_bucket_name}
    end
  end

  # Key comes as a list of path segments from router
  defp validate_object_key(key) when is_list(key) do
    key |> Enum.join("/") |> validate_object_key()
  end

  # Empty key
  defp validate_object_key(""), do: {:error, :invalid_object_key}
  defp validate_object_key("/"), do: {:error, :invalid_object_key}

  # Path traversal attempts
  defp validate_object_key(key) when is_binary(key) do
    cond do
      String.contains?(key, "..") -> {:error, :invalid_object_key}
      String.starts_with?(key, "/") -> {:error, :invalid_object_key}
      String.match?(key, ~r/[\x00-\x1F\x7F]/) -> {:error, :invalid_object_key}
      true -> :ok
    end
  end

  defp build_file_path(bucket, key) when is_list(key) do
    key |> Enum.join("/") |> then(&build_file_path(bucket, &1))
  end

  defp build_file_path(bucket, key) when is_binary(key) do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    file_path = Path.join([data_dir, "buckets", bucket, key])
    buckets_dir = Path.join([data_dir, "buckets", bucket])

    # Additional security check: ensure resolved path is within bucket directory
    resolved_path = Path.expand(file_path)
    expected_prefix = Path.expand(buckets_dir)

    case path_within_directory?(resolved_path, expected_prefix) do
      true -> {:ok, file_path}
      false -> {:error, :path_traversal}
    end
  end

  defp path_within_directory?(path, expected_prefix) do
    String.starts_with?(path, expected_prefix <> "/") or path == expected_prefix
  end

  defp calculate_etag(file_path) do
    # Calculate MD5 hash of file content
    # Using File.read!/1 for simplicity and to avoid Dialyzer false positive with File.stream!/3
    file_path
    |> File.read!()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  defp format_http_date(erl_datetime) do
    # Format as RFC 7231 HTTP date (e.g., "Mon, 27 Jul 2009 12:28:53 GMT")
    # Convert Erlang datetime to DateTime and format using Calendar
    {:ok, datetime} = DateTime.from_naive(NaiveDateTime.from_erl!(erl_datetime), "Etc/UTC")
    Calendar.strftime(datetime, "%a, %d %b %Y %H:%M:%S GMT")
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{error: message})
  end

  ## PUT Object Helpers

  defp authenticate_request(conn) do
    # Try Authorization header first (standard auth)
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["AWS4-HMAC-SHA256 " <> rest] ->
        authenticate_with_header(conn, rest)

      _ ->
        # Try query parameters (presigned URL)
        authenticate_with_query_params(conn)
    end
  end

  defp authenticate_with_header(conn, auth_string) do
    with {:ok, access_key_id} <- extract_access_key_id_from_header(auth_string),
         {:ok, access_key} <- KeyManager.lookup(access_key_id),
         {:ok, ^access_key_id} <- Signature.validate_signature(conn, access_key.secret_key) do
      {:ok, access_key_id}
    else
      :error -> {:error, :access_key_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authenticate_with_query_params(conn) do
    # Check for X-Amz-Credential in query parameters
    case Map.get(conn.query_params, "X-Amz-Credential") do
      nil ->
        {:error, :missing_authorization_header}

      credential_string ->
        with {:ok, access_key_id} <- extract_access_key_id_from_credential(credential_string),
             {:ok, access_key} <- KeyManager.lookup(access_key_id),
             {:ok, ^access_key_id} <- Signature.validate_signature(conn, access_key.secret_key) do
          {:ok, access_key_id}
        else
          :error -> {:error, :access_key_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp extract_access_key_id_from_header(auth_string) do
    # Parse "Credential=ACCESS_KEY/date/region/service/aws4_request, ..."
    case Regex.run(~r/Credential=([^\/]+)\//, auth_string) do
      [_, access_key_id] -> {:ok, access_key_id}
      _ -> {:error, :invalid_authorization_format}
    end
  end

  defp extract_access_key_id_from_credential(credential_string) do
    # Parse "ACCESS_KEY/date/region/service/aws4_request"
    case String.split(credential_string, "/") do
      [access_key_id | _] -> {:ok, access_key_id}
      _ -> {:error, :invalid_authorization_format}
    end
  end

  defp authorize_bucket_access(%{bucket: bucket}, bucket), do: :ok
  defp authorize_bucket_access(_access_key, _bucket), do: {:error, :bucket_access_denied}

  defp check_permission(%{permissions: permissions}, required_permission) do
    case required_permission in permissions do
      true -> :ok
      false -> {:error, :permission_denied}
    end
  end

  defp read_request_body(conn) do
    max_size = Application.get_env(:attack_blob, :max_upload_size, 5_368_709_120)

    case Plug.Conn.read_body(conn, length: max_size) do
      {:ok, body, _conn} -> {:ok, body}
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_file(file_path, body) do
    # Ensure parent directory exists
    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Write the file
    case File.write(file_path, body) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_file(file_path) do
    case File.rm(file_path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  ## List Objects Helpers

  defp get_bucket_path(bucket) do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    bucket_path = Path.join([data_dir, "buckets", bucket])
    {:ok, bucket_path}
  end

  defp parse_max_keys(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} when num > 0 and num <= 1000 -> num
      {num, _} when num > 1000 -> 1000
      _ -> 1000
    end
  end

  defp parse_max_keys(_), do: 1000

  defp list_bucket_objects(bucket_path, prefix, delimiter, max_keys) do
    case list_all_object_keys(bucket_path, bucket_path) do
      [] ->
        %{objects: [], common_prefixes: [], is_truncated: false}

      all_keys ->
        # Filter by prefix
        filtered_keys =
          if prefix != "" do
            Enum.filter(all_keys, &String.starts_with?(&1, prefix))
          else
            all_keys
          end

        # Apply delimiter logic if specified
        {objects, common_prefixes} =
          if delimiter do
            apply_delimiter(filtered_keys, prefix, delimiter)
          else
            {filtered_keys, []}
          end

        # Apply max_keys limit
        {limited_objects, is_truncated} =
          if length(objects) > max_keys do
            {Enum.take(objects, max_keys), true}
          else
            {objects, false}
          end

        # Build object metadata
        object_list =
          Enum.map(limited_objects, fn key ->
            full_path = Path.join(bucket_path, key)

            case File.stat(full_path) do
              {:ok, stat} ->
                %{
                  key: key,
                  size: stat.size,
                  last_modified: format_iso8601(stat.mtime),
                  etag: calculate_etag(full_path)
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        %{
          objects: object_list,
          common_prefixes: common_prefixes,
          is_truncated: is_truncated
        }
    end
  end

  defp list_all_object_keys(bucket_path, current_path, relative_to \\ nil) do
    relative_to = relative_to || bucket_path

    case File.ls(current_path) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full_path = Path.join(current_path, entry)

          cond do
            File.regular?(full_path) ->
              # Calculate relative path from bucket root
              relative_key = Path.relative_to(full_path, relative_to)
              [relative_key]

            File.dir?(full_path) ->
              list_all_object_keys(bucket_path, full_path, relative_to)

            true ->
              []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp apply_delimiter(keys, prefix, delimiter) do
    # Group keys by common prefix (everything before next delimiter)
    {objects, prefixes} =
      Enum.reduce(keys, {[], MapSet.new()}, fn key, {objs, prefs} ->
        # Remove prefix from key
        suffix = String.replace_prefix(key, prefix, "")

        case String.split(suffix, delimiter, parts: 2) do
          [_single_part] ->
            # No delimiter found, this is a direct object
            {[key | objs], prefs}

          [first_part, _rest] ->
            # Delimiter found, this is a common prefix
            common_prefix = prefix <> first_part <> delimiter
            {objs, MapSet.put(prefs, common_prefix)}
        end
      end)

    {Enum.reverse(objects), MapSet.to_list(prefixes)}
  end

  defp format_iso8601(erl_datetime) do
    {:ok, datetime} = DateTime.from_naive(NaiveDateTime.from_erl!(erl_datetime), "Etc/UTC")
    DateTime.to_iso8601(datetime)
  end
end
