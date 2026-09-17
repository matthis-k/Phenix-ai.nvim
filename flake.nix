{
  description = "Phenix AI Neovim client";

  inputs = {
    phenix-ai.url = "github:matthis-k/phenix-ai/f04a811d464136bf31c070c2a30dc62401daeafc";
    nixpkgs.follows = "phenix-ai/nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      phenix-ai,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          luaBinding = phenix-ai.packages.${system}.phenix-binding-lua;
          phenixAcp = phenix-ai.packages.${system}.phenix-acp;
          plugin = pkgs.vimUtils.buildVimPlugin {
            pname = "phenix-ai.nvim";
            version = "0";
            src = pkgs.lib.cleanSource ./.;
            postInstall = ''
              install -Dm755 ${luaBinding}/lib/lua/5.1/phenix.so "$out/lua/phenix.so"
              substituteInPlace "$out/lua/phenix_nvim/config.lua" \
                --replace-fail 'command = "phenix-acp"' \
                'command = "${phenixAcp}/bin/phenix-acp"'
              mkdir -p "$out/share/phenix-ai.nvim"
              printf '%s\n' ${pkgs.lib.escapeShellArg (phenix-ai.rev or "dirty")} \
                > "$out/share/phenix-ai.nvim/phenix-ai-revision"
            '';
          };
        in
        {
          default = plugin;
          phenix-ai-nvim = plugin;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          plugin = self.packages.${system}.phenix-ai-nvim;
        in
        {
          load = pkgs.runCommand "phenix-ai-nvim-load" { nativeBuildInputs = [ pkgs.neovim ]; } ''
            nvim --headless -u NONE \
              --cmd 'set runtimepath^=${plugin}' \
              -c ${pkgs.lib.escapeShellArg "lua dofile('${./tests/headless.lua}')"} \
              -c qa
            touch "$out"
          '';
        }
      );
    };
}
