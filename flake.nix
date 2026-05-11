{
  description = "JARVIS Annotation Tool — multi-camera 3D markerless motion capture annotation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # The project targets the legacy OpenCV aruco API (pre-4.7). nixpkgs
    # unstable now ships OpenCV 4.13, so we pull OpenCV 4.6 from the
    # release-22.11 branch where it's still the packaged version.
    nixpkgs-opencv.url = "github:NixOS/nixpkgs/release-22.11";

    # libcbdetect is a git submodule of this repo. We fetch it explicitly so
    # the flake builds cleanly without requiring `git submodule update --init`.
    libcbdetect-src = {
      url = "github:JARVIS-MoCap/libcbdetect";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-opencv, flake-utils, libcbdetect-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsOpencv = import nixpkgs-opencv {
          inherit system;
          config.permittedInsecurePackages = [ ];
        };

        opencvWithAruco = pkgsOpencv.opencv4.override {
          enableContrib = true;
          enableFfmpeg = true;
          enableGtk2 = false;
          enableGtk3 = false;
        };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "jarvis-annotationtool";
          version = "1.3.0";

          src = self;

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            qt6.wrapQtAppsHook
          ];

          buildInputs = with pkgs; [
            qt6.qtbase
            qt6.qtsvg
            qt6.qtcharts
            qt6.qtmultimedia
            qt6.qt3d
            qt6.qtdeclarative
            qt6.qtshadertools
            opencvWithAruco
            yaml-cpp
            eigen
            ffmpeg-headless
          ];

          postPatch = ''
            # Strip the hardcoded local-build paths so the system Qt6, OpenCV
            # and yaml-cpp from nixpkgs are picked up instead of the in-tree
            # libs/* submodule builds.
            substituteInPlace CMakeLists.txt \
              --replace-fail 'set (CMAKE_PREFIX_PATH "libs/Qt5/qt_install/lib/cmake/")' ''' \
              --replace-fail 'find_package(Qt6  QUIET PATHS "libs/Qt5/qt_install/lib/cmake/" REQUIRED' 'find_package(Qt6 REQUIRED' \
              --replace-fail 'set(OpenCV_DIR "libs/OpenCV/opencv_install/lib/cmake/opencv4")' ''' \
              --replace-fail 'set(OpenCV_STATIC ON)' ''' \
              --replace-fail 'add_subdirectory(libs/yaml-cpp/)' 'find_package(yaml-cpp REQUIRED)' \
              --replace-fail 'set(CMAKE_INSTALL_RPATH /usr/local/lib/JARVIS-AnnotationTool;)' '''

            # The project's vendored Qt6 was a static build, which masked
            # under-linkage. Against dynamic Qt6 from nixpkgs we need to
            # declare Qt::3DExtras explicitly on the visualizationwindow lib
            # (it uses QOrbitCameraController / QAbstractCameraController).
            substituteInPlace gui/editor/visualizationwindow/CMakeLists.txt \
              --replace-fail 'Qt::3DRender' 'Qt::3DRender
  Qt::3DExtras'

            # Drop the libcbdetect sources into place (submodule isn't checked
            # out from the flake source).
            rm -rf libs/libcbdetect
            cp -r ${libcbdetect-src} libs/libcbdetect
            chmod -R u+w libs/libcbdetect
          '';

          # The in-tree CMakeLists.txt only installs the binary on specific
          # Ubuntu targets, so do it manually here.
          installPhase = ''
            runHook preInstall
            install -Dm755 AnnotationTool $out/bin/jarvis-annotationtool
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Multi-camera 3D markerless motion capture annotation tool";
            homepage = "https://github.com/JARVIS-MoCap/JARVIS-AnnotationTool";
            license = licenses.gpl2Only;
            platforms = platforms.linux;
            mainProgram = "jarvis-annotationtool";
          };
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/jarvis-annotationtool";
        };
      });
}
