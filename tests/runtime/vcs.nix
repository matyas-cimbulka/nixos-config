{ inputs, config, lib, ... }:
let
  modules = config.flake.modules;
  identity = { name = "Test Author"; email = "test@example.invalid"; };
  signingKey = "/home/matyas/vcs-test/key.pub";
in {
  perSystem = { pkgs, system, ... }: lib.mkIf (system == "x86_64-linux") {
    checks.runtime-vcs = inputs.nixpkgs.lib.nixos.runTest {
      name = "development-vcs";
      hostPkgs = pkgs;
      qemu.forceAccel = true;
      nodes.workstation = { ... }: {
        imports = [ modules.nixos.base-profile modules.nixos.home-manager modules.nixos.matyas ];
        system.stateVersion = "26.11";
        virtualisation = { writableStore = true; writableStoreUseTmpfs = false; };
        home-manager.users.matyas = {
          imports = [ modules.homeManager.matyas-base ];
          deployment = {
            git.development.enable = true;
            jujutsu.development = { enable = true; signing.key = signingKey; };
          };
          programs = {
            git = {
              settings = {
                user = identity;
                gpg.ssh.allowedSignersFile = "/home/matyas/vcs-test/allowed_signers";
              };
              signing.key = signingKey;
            };
            jujutsu.settings = {
              user = identity;
              signing.backends.ssh.allowed-signers = "/home/matyas/vcs-test/allowed_signers";
            };
          };
        };
        environment.etc."vcs-test.sh".text = ''
          set -eu
          export SSH_AUTH_SOCK="$HOME/vcs-test/agent.sock"
          mkdir -p "$HOME/vcs-test/repository"
          ssh-keygen -q -t ed25519 -N "" -f "$HOME/vcs-test/key"
          ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null
          trap 'ssh-agent -k > /dev/null 2>&1 || true' EXIT
          ssh-add "$HOME/vcs-test/key"
          rm "$HOME/vcs-test/key"
          printf 'test@example.invalid %s\n' "$(cat "$HOME/vcs-test/key.pub")" > "$HOME/vcs-test/allowed_signers"
          cd "$HOME/vcs-test/repository"
          git init
          git commit --allow-empty -m 'Signed Git fixture'
          git verify-commit HEAD
          jj git init --colocate
          jj new -m 'Signed Jujutsu fixture'
          commit=$(jj log --no-graph -r @ -T 'commit_id')
          git verify-commit "$commit"
          printf 'Agent-backed Git and Jujutsu signatures verified\n'
        '';
      };
      testScript = ''
        start_all()
        workstation.wait_for_unit("home-manager-matyas.service")
        result = workstation.succeed("runuser -u matyas -- env PATH=/etc/profiles/per-user/matyas/bin:/run/current-system/sw/bin bash /etc/vcs-test.sh 2>&1")
        assert "Agent-backed Git and Jujutsu signatures verified" in result, result
      '';
    };
  };
}
