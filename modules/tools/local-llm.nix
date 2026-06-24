{ ... }:
{
  flake.homeManagerModules.local-llm =
    { pkgs, lib, ... }:
    let
      cfgDir = "\${XDG_CONFIG_HOME:-$HOME/.config}/local-llm";
      tlsDir = "${cfgDir}/tls";
      apiFile = "${cfgDir}/api-keys.txt";

      localLlmInit = pkgs.writeShellApplication {
        name = "local-llm-init";
        runtimeInputs = with pkgs; [
          coreutils
          openssl
        ];
        text = ''
          set -euo pipefail

          cfg_dir="${cfgDir}"
          tls_dir="${tlsDir}"
          api_file="${apiFile}"

          mkdir -p "$tls_dir"
          chmod 700 "$cfg_dir" "$tls_dir"

          if [[ ! -f "$tls_dir/ca.key" || ! -f "$tls_dir/ca.crt" ]]; then
            openssl genrsa -out "$tls_dir/ca.key" 4096
            chmod 600 "$tls_dir/ca.key"
            openssl req -x509 -new -nodes \
              -key "$tls_dir/ca.key" \
              -sha256 -days 3650 \
              -out "$tls_dir/ca.crt" \
              -subj "/CN=local-llm-dev-ca"
            chmod 644 "$tls_dir/ca.crt"
          fi

          cat > "$tls_dir/server.ext" <<'EOF'
          authorityKeyIdentifier=keyid,issuer
          basicConstraints=CA:FALSE
          keyUsage=digitalSignature,keyEncipherment
          extendedKeyUsage=serverAuth
          subjectAltName=@alt_names

          [alt_names]
          DNS.1=host.private
          DNS.2=localhost
          IP.1=127.0.0.1
          IP.2=192.168.5.2
          EOF

          openssl genrsa -out "$tls_dir/server.key" 4096
          chmod 600 "$tls_dir/server.key"
          openssl req -new \
            -key "$tls_dir/server.key" \
            -out "$tls_dir/server.csr" \
            -subj "/CN=host.private"
          openssl x509 -req \
            -in "$tls_dir/server.csr" \
            -CA "$tls_dir/ca.crt" \
            -CAkey "$tls_dir/ca.key" \
            -CAcreateserial \
            -out "$tls_dir/server.crt" \
            -days 825 -sha256 \
            -extfile "$tls_dir/server.ext"
          chmod 644 "$tls_dir/server.crt"
          rm -f "$tls_dir/server.csr" "$tls_dir/server.ext"

          if [[ ! -f "$api_file" ]]; then
            openssl rand -base64 48 > "$api_file"
            chmod 600 "$api_file"
          fi

          cat <<EOF
          local-llm initialized:
            CA cert:     $tls_dir/ca.crt
            Server cert: $tls_dir/server.crt
            Server key:  $tls_dir/server.key
            API keys:    $api_file

          In private-vm, map and trust:
            192.168.5.2 host.private

          VM URL:
            https://host.private:8443
          EOF
        '';
      };

      localLlmInfo = pkgs.writeShellApplication {
        name = "local-llm-info";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
        ];
        text = ''
          set -euo pipefail

          tls_dir="${tlsDir}"
          api_file="${apiFile}"

          cat <<EOF
          Host bind:
            127.0.0.1:8443

          VM endpoint:
            https://host.private:8443
            https://192.168.5.2:8443

          VM /etc/hosts entry:
            192.168.5.2 host.private

          Files:
            CA cert:     $tls_dir/ca.crt
            Server cert: $tls_dir/server.crt
            Server key:  $tls_dir/server.key
            API keys:    $api_file

          Start:
            local-llm-server /path/to/model.gguf

          Show API key:
            sed -n '1p' "$api_file"
          EOF

          if [[ ! -f "$tls_dir/ca.crt" || ! -f "$tls_dir/server.crt" || ! -f "$tls_dir/server.key" || ! -f "$api_file" ]]; then
            echo
            echo "Missing one or more files; run local-llm-init first."
            exit 1
          fi
        '';
      };

      localLlmServer = pkgs.writeShellApplication {
        name = "local-llm-server";
        runtimeInputs = with pkgs; [
          coreutils
          llama-cpp
        ];
        text = ''
          set -euo pipefail

          tls_dir="${tlsDir}"
          api_file="${apiFile}"
          port="''${LOCAL_LLM_PORT:-8443}"
          model="''${LOCAL_LLM_MODEL:-}"

          if [[ $# -gt 0 && "$1" != --* ]]; then
            model="$1"
            shift
          fi

          if [[ -z "$model" ]]; then
            echo "usage: local-llm-server /path/to/model.gguf [extra llama-server args]" >&2
            echo "   or: LOCAL_LLM_MODEL=/path/to/model.gguf local-llm-server [extra args]" >&2
            exit 2
          fi

          for path in "$tls_dir/server.crt" "$tls_dir/server.key" "$api_file"; do
            if [[ ! -f "$path" ]]; then
              echo "missing $path; run local-llm-init first" >&2
              exit 1
            fi
          done

          exec llama-server \
            --model "$model" \
            --host 127.0.0.1 \
            --port "$port" \
            --ssl-key-file "$tls_dir/server.key" \
            --ssl-cert-file "$tls_dir/server.crt" \
            --api-key-file "$api_file" \
            --cache-ram 0 \
            --ctx-checkpoints 0 \
            --no-cache-idle-slots \
            --no-ui \
            --offline \
            --log-disable \
            "$@"
        '';
      };
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [
        pkgs.llama-cpp
        localLlmInit
        localLlmInfo
        localLlmServer
      ];
    };
}
