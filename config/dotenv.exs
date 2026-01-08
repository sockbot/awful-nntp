# Environment Configuration Helper
# Load .env file for development

env_file = Path.join(__DIR__, "../.env")

if File.exists?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    unless String.starts_with?(line, "#") or line == "" do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          System.put_env(String.trim(key), String.trim(value))

        _ ->
          :ok
      end
    end
  end)
end
