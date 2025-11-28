{
  description = "LÖVR - A simple Lua framework for rapidly building VR experiences";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        stdenv = pkgs.stdenv;

        # System libraries needed for building and running
        # Based on https://lovr.org/docs/Compiling
        buildLibs = with pkgs; [
          # X11/XCB libraries (xorg-dev equivalent)
          xorg.libX11
          xorg.libxcb
          xorg.libXrandr
          xorg.libXinerama
          xorg.libXcursor
          xorg.libXi
          xorg.xcbutil
          xorg.xcbutilkeysyms
          xorg.xcbutilwm

          # Additional X libraries
          libxkbcommon

          # Audio libraries (for miniaudio)
          alsa-lib
          libpulseaudio

          # curl for networking
          curl
        ];

        runtimeLibs = with pkgs; [
          # Vulkan runtime (not in vendored deps)
          vulkan-loader
          vulkan-validation-layers

          # OpenGL
          libGL
        ];

      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Build tools (make, cmake, C11 compiler)
            cmake
            gnumake
            gcc
            pkg-config

            # Python for build scripts
            python3Minimal

            # Shader compiler (glslang)
            glslang

            # Development tools
            git
            gdb
          ] ++ buildLibs ++ runtimeLibs ++ lib.optionals (!stdenv.isDarwin) [
            valgrind
          ];

          shellHook = ''
            echo "LÖVR development environment"
            echo "=============================="
            echo ""

            # Initialize git submodules if not already done
            if [ -d .git ] && [ ! -f deps/glfw/.git ]; then
              echo "Initializing git submodules..."
              git submodule update --init --recursive
              echo ""
            fi

            echo "Dependencies are vendored in deps/ as git submodules"
            echo "System provides: cmake, make, gcc, X11 libs, curl, Vulkan loader"
            echo ""
            echo "Build LÖVR:"
            echo "  mkdir -p build && cd build"
            echo "  cmake .."
            echo "  cmake --build ."
            echo ""
            echo "Run LÖVR:"
            echo "  ./build/bin/lovr"
            echo ""
            echo "Run tests:"
            echo "  ./build/bin/lovr test"
            echo ""
          '';

          # Environment variables for Vulkan
          VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";

          # Library path for runtime linking
          LD_LIBRARY_PATH = lib.makeLibraryPath (buildLibs ++ runtimeLibs);
        };

        # Package for building LÖVR
        packages.default = stdenv.mkDerivation {
          pname = "lovr";
          version = "dev";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            cmake
            gnumake
            pkg-config
            python3Minimal
            glslang
            git  # Needed for initializing submodules
          ];

          buildInputs = buildLibs ++ runtimeLibs;

          # Initialize submodules before configuring
          preConfigure = ''
            # Check if we're in a git repository and submodules aren't initialized
            if [ -d .git ] && [ ! -f deps/glfw/.git ]; then
              echo "Initializing git submodules..."
              git submodule update --init --recursive
            fi
          '';

          # All dependencies are vendored, so disable system package lookups
          cmakeFlags = [
            "-DLOVR_SYSTEM_GLFW=OFF"
            "-DLOVR_SYSTEM_LUA=OFF"
            "-DLOVR_SYSTEM_OPENXR=OFF"
            "-DLOVR_USE_LUAJIT=ON"
            "-DLOVR_USE_VULKAN=ON"
            "-DLOVR_USE_GLFW=ON"
            "-DLOVR_BUILD_EXE=ON"
          ];

          installPhase = ''
            mkdir -p $out/bin $out/lib

            # Copy the executable and libraries from build output
            if [ -d bin ]; then
              cp -r bin/* $out/bin/ 2>/dev/null || true
              find bin -name "*.so*" -exec cp {} $out/lib/ \; 2>/dev/null || true
            fi

            if [ -f lovr ]; then
              cp lovr $out/bin/
            fi
          '';

          meta = with lib; {
            description = "A simple Lua framework for rapidly building VR experiences";
            homepage = "https://lovr.org";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "lovr";
          };
        };

        # Apps for easy `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/lovr";
        };
      }
    );
}
