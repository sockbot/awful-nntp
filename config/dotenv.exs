# Environment Configuration Helper
# Load .awful-nntp.env file from home directory

env_file = Path.expand("~/.awful-nntp.env")

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
else
  IO.warn("""
  SA credentials file not found at ~/.awful-nntp.env
  
  To create it:
    cp .awful-nntp.env.example ~/.awful-nntp.env
    nano ~/.awful-nntp.env
  
  Then add your SA_USERNAME and SA_PASSWORD.
  """)
end

