defmodule AttackBlobWeb.Router do
  use AttackBlobWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AttackBlobWeb do
    # Health check endpoint
    get "/health", HealthController, :check

    # Public read-only blob access (no authentication required)
    get "/:bucket", BlobController, :list_objects
    get "/:bucket/*key", BlobController, :get_object
    head "/:bucket/*key", BlobController, :head_object

    # Multipart upload operations (require AWS Signature V4 authentication)
    # Routes are matched by query parameters in the controller
    post "/:bucket/*key", BlobController, :post_object

    # Signed write operations (require AWS Signature V4 authentication)
    put "/:bucket/*key", BlobController, :put_object
    delete "/:bucket/*key", BlobController, :delete_object
  end

  scope "/api", AttackBlobWeb do
    pipe_through :api
  end
end
