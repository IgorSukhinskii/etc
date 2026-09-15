{ ... }:
{
  flake.homeManagerModules.local-llm =
    { pkgs, lib, ... }:
    let
      cfgDir = "\${XDG_CONFIG_HOME:-$HOME/.config}/local-llm";
      tlsDir = "${cfgDir}/tls";
      apiFile = "${cfgDir}/api-keys.txt";
      # Written by the private-llm repo's install.sh. Names the model, the
      # chat template and the context size — i.e. everything personal. This
      # repo is public, so none of that is hardcoded here; the wrapper reads
      # the file and fails loudly if it is missing.
      envFile = "${cfgDir}/chat.env";

      # Shared prelude, sourced by both wrappers: load chat.env, require the
      # keys we use, and export LLAMA_CACHE so llama.cpp's -hf resolution
      # reads the model cache under ~/data instead of ~/.cache.
      loadEnv = pkgs.writeText "local-llm-load-env.sh" ''
        env_file="${envFile}"
        if [[ ! -f "$env_file" ]]; then
          echo "missing $env_file" >&2
          echo "run the private-llm repo's install.sh to generate it" >&2
          exit 1
        fi
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a

        : "''${LOCAL_LLM_HF:?LOCAL_LLM_HF unset in $env_file}"
        : "''${LOCAL_LLM_CACHE:?LOCAL_LLM_CACHE unset in $env_file}"
        export LLAMA_CACHE="$LOCAL_LLM_CACHE"
      '';

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
            chat.env:    ${envFile}

          Fetch the pinned model:
            local-llm-fetch

          Start:
            local-llm-server               # model + template from chat.env
            local-llm-server /path/to.gguf # override with an explicit file

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

      # Fetch (or verify) the pinned GGUF into LOCAL_LLM_CACHE. Separate from
      # the server so the multi-GB download is an explicit, resumable step and
      # the server can then run with --offline. `llama download` also pulls the
      # mmproj sidecar when the repo has one (Qwen3.8 does).
      localLlmFetch = pkgs.writeShellApplication {
        name = "local-llm-fetch";
        runtimeInputs = with pkgs; [
          coreutils
          llama-cpp
        ];
        text = ''
          set -euo pipefail

          # shellcheck source=/dev/null
          . ${loadEnv}

          mkdir -p "$LLAMA_CACHE"

          echo "fetching $LOCAL_LLM_HF into $LLAMA_CACHE" >&2
          llama download -hf "$LOCAL_LLM_HF"

          # Verify against the pin in the private-llm repo's model.lock, which
          # install.sh copied into chat.env. Skipped when unset.
          if [[ -n "''${LOCAL_LLM_SHA256:-}" ]]; then
            gguf=$(find "$LLAMA_CACHE" -name '*.gguf' ! -name '*mmproj*' -type f \
              -exec ls -S {} + | head -1)
            if [[ -z "$gguf" ]]; then
              echo "no .gguf found under $LLAMA_CACHE after download" >&2
              exit 1
            fi
            echo "verifying $gguf" >&2
            have=$(sha256sum "$gguf" | cut -d' ' -f1)
            if [[ "$have" != "$LOCAL_LLM_SHA256" ]]; then
              echo "sha256 mismatch for $gguf" >&2
              echo "  expected: $LOCAL_LLM_SHA256" >&2
              echo "  actual:   $have" >&2
              exit 1
            fi
            echo "sha256 ok" >&2
          fi

          echo "model ready; start it with: local-llm-server" >&2
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

          # shellcheck source=/dev/null
          . ${loadEnv}

          for path in "$tls_dir/server.crt" "$tls_dir/server.key" "$api_file"; do
            if [[ ! -f "$path" ]]; then
              echo "missing $path; run local-llm-init first" >&2
              exit 1
            fi
          done

          # Model selection: an explicit path (argv or LOCAL_LLM_MODEL) wins,
          # otherwise the pinned -hf spec resolved out of the local cache.
          # --offline makes that resolution read-only: llama.cpp never reaches
          # the network, so an unfetched or evicted model is a hard error here
          # rather than a silent multi-GB download. Run local-llm-fetch first.
          if [[ -n "$model" ]]; then
            model_args=( --model "$model" )
          else
            model_args=( --hf-repo "$LOCAL_LLM_HF" )
          fi

          # Chat template: the stock Qwen3.8 template is broken multi-turn
          # (it prepends empty <think></think> blocks to real history and
          # hardcodes xhigh reasoning effort). The pinned replacement lives
          # with the model pin in the private-llm repo.
          template_args=()
          if [[ -n "''${LOCAL_LLM_CHAT_TEMPLATE:-}" ]]; then
            if [[ ! -f "$LOCAL_LLM_CHAT_TEMPLATE" ]]; then
              echo "missing chat template: $LOCAL_LLM_CHAT_TEMPLATE" >&2
              exit 1
            fi
            template_args=( --jinja --chat-template-file "$LOCAL_LLM_CHAT_TEMPLATE" )
          fi

          alias_args=()
          if [[ -n "''${LOCAL_LLM_ALIAS:-}" ]]; then
            alias_args=( --alias "$LOCAL_LLM_ALIAS" )
          fi

          # Thinking default. Per-request overrides still work: the fixed
          # template honours enable_thinking / reasoning_effort kwargs, so a
          # frontend can turn it back on for a single completion.
          reasoning_args=()
          if [[ -n "''${LOCAL_LLM_REASONING:-}" ]]; then
            reasoning_args=( --reasoning "$LOCAL_LLM_REASONING" )
          fi

          # Privacy posture (decision 2): loopback bind only, TLS with the
          # private CA, API key required, no network egress, no web UI, no
          # logs, and no prompt state written to disk --
          #   --cache-ram 0            no host-RAM prompt cache
          #   --ctx-checkpoints 0      no context checkpoints
          #   --no-cache-idle-slots    idle slots drop their KV instead of
          #                            being spilled
          exec llama-server \
            "''${model_args[@]}" \
            "''${alias_args[@]}" \
            "''${template_args[@]}" \
            "''${reasoning_args[@]}" \
            --host 127.0.0.1 \
            --port "$port" \
            --ssl-key-file "$tls_dir/server.key" \
            --ssl-cert-file "$tls_dir/server.crt" \
            --api-key-file "$api_file" \
            --ctx-size "''${LOCAL_LLM_CTX:-65536}" \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --reasoning-format deepseek \
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
        localLlmFetch
        localLlmServer
      ];
    };
}
