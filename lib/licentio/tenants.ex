defmodule Licentio.Tenants do
  @moduledoc """
  Context for managing tenants.

  This is the single entry point for anything tenant-related.
  External code (controllers, other contexts) should only call
  functions defined here - never use the Tenant schema directly.
  """

  import Ecto.Query

  alias Licentio.Repo
  alias Licentio.Schema.Tenant

  # ------------------
  # Queries
  # ------------------

  @doc """
  Returns all active tenants.

  ## Example
      Licentio.Tenants.list_tenants()
      #=> [%Tenant{}, ...]
  """
  def list_tenants do
    Tenant
    |> where([t], t.is_active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single tenant by id. Returns nil if not found.
  """
  def get_tenant(id), do: Repo.get(Tenant, id)

  @doc """
  Gets a tenant by its code. Returns nil if not found.

  ## Example
      Licentio.Tenants.get_tenant_by_code("acme-corp")
  """
  def get_tenant_by_code(code) do
    Repo.get_by(Tenant, code: code)
  end

  # -----------------
  # Commands
  # -----------------

  @doc """
  Creates a new tenant.

  ## Example
      Licentio.Tenants.create_tenant(%{name: "Acme", code: "acme"})
      #=> {:ok, %Tenant{}} | {:error, %Ecto.Changeset{}}
  """
  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing tenant.
  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  @doc ~S"""
  Deactivates a tenant (soft delete - never hard delete tenants).
  """
  def deactivate_tenant(%Tenant{} = tenant) do
    tenant
    |> Tenant.changeset(%{is_active: false})
    |> Repo.update()
  end
end
