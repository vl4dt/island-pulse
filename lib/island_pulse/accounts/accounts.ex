defmodule IslandPulse.Accounts do
  import Ecto.Query
  alias IslandPulse.Repo
  alias IslandPulse.Accounts.User

  @doc """
  Get or create a user by Telegram ID.
  """
  def get_or_create_user(telegram_id) do
    case Repo.get_by(User, telegram_id: telegram_id) do
      %User{} = user ->
        {:ok, user}

      nil ->
        case User.changeset(%User{}, telegram_id: telegram_id) |> Repo.insert() do
          {:ok, user} -> {:ok, user}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Get a user by database ID.
  """
  def get_user_by_id(id) do
    Repo.get(User, id)
  end

  @doc """
  Get a user by Telegram ID.
  """
  def get_user_by_telegram_id(telegram_id) do
    Repo.get_by(User, telegram_id: telegram_id)
  end

  @doc """
  Upgrade a user's tier.
  """
  def upgrade_tier(user, tier) when tier in ["creator", "pro"] do
    User.tier_changeset(user, tier) |> Repo.update()
  end

  @doc """
  Downgrade a user to free tier.
  """
  def downgrade_to_free(user) do
    User.tier_changeset(user, "free") |> Repo.update()
  end

  @doc """
  List all users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Count users by tier.
  """
  def user_counts_by_tier do
    for tier <- ["free", "creator", "pro"] do
      {tier, Repo.aggregate(from(u in User, where: u.tier == ^tier), :count, :id)}
    end
  end
end
