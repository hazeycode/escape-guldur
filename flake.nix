{
  description = "Ludutra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            zig.overlays.default
          ];
        };
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            zigpkgs."0.14.1"
            nodejs
            binaryen
            wapm
          ];
          shellHook = ''
            # Install w4 using npm if it's not already installed
            if [ ! -d "node_modules/.bin" ] || [ ! -f "node_modules/.bin/w4" ]; then
              echo "Installing wasm4 CLI..."
              npm install --no-save wasm4@2.7.1
            fi
            
            export PATH="$PWD/node_modules/.bin:$PATH"
            
            echo ""
            echo "Welcome to the Escape Guldur dev shell..."
            echo ""
            echo "  zig $(zig version)"
            echo "  w4 $(w4 --version)"
            echo "  $(wasm-opt --version)"
            echo "  $(wapm --version)"
            echo ""
          '';
        };
      }
    );
}
