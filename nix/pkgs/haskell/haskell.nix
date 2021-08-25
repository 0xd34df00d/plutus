############################################################################
# Builds Haskell packages with Haskell.nix
############################################################################
{ lib
, rPackages
, haskell-nix
, agdaWithStdlib
, gitignore-nix
, z3
, R
, libsodium-vrf
, checkMaterialization
, compiler-nix-name
, enableHaskellProfiling
  # Whether to set the `defer-plugin-errors` flag on those packages that need
  # it. If set to true, we will also build the haddocks for those packages.
, deferPluginErrors
, actus-tests
, ghcjsPluginPkgs ? null
, cabalProjectLocal ? null
}:
let
  r-packages = with rPackages; [ R tidyverse dplyr stringr MASS plotly shiny shinyjs purrr ];
  project = haskell-nix.cabalProject' ({ pkgs, ... }: {
    compiler-nix-name = if pkgs.stdenv.hostPlatform.isGhcjs then "ghc8105" else compiler-nix-name;
    # This is incredibly difficult to get right, almost everything goes wrong, see https://github.com/input-output-hk/haskell.nix/issues/496
    src = let root = ../../../.; in
      haskell-nix.haskellLib.cleanSourceWith {
        filter = gitignore-nix.gitignoreFilter root;
        src = root;
        # Otherwise this depends on the name in the parent directory, which reduces caching, and is
        # particularly bad on Hercules, see https://github.com/hercules-ci/support/issues/40
        name = "plutus";
      };
    # These files need to be regenerated when you change the cabal files.
    # See ../CONTRIBUTING.doc for more information.
    # Unfortuntely, they are *not* constant across all possible systems, so in some circumstances we need different sets of files
    # At the moment, we only need one but conceivably we might need one for darwin in future.
    # See https://github.com/input-output-hk/nix-tools/issues/97
    materialized =
      if pkgs.stdenv.hostPlatform.isLinux then ./materialized-linux
      else if pkgs.stdenv.hostPlatform.isGhcjs then ./materialized-ghcjs
      else if pkgs.stdenv.hostPlatform.isDarwin then ./materialized-darwin
      else if pkgs.stdenv.hostPlatform.isWindows then ./materialized-windows
      else builtins.error "Don't have materialized files for this platform";
    # If true, we check that the generated files are correct. Set in the CI so we don't make mistakes.
    inherit checkMaterialization;
    sha256map = {
      "https://github.com/michaelpj/flat.git"."ee59880f47ab835dbd73bea0847dab7869fc20d8" = "1lrzknw765pz2j97nvv9ip3l1mcpf2zr4n56hwlz0rk7wq7ls4cm";
      "https://github.com/shmish111/purescript-bridge.git"."6a92d7853ea514be8b70bab5e72077bf5a510596" = "13j64vv116in3c204qsl1v0ajphac9fqvsjp7x3zzfr7n7g61drb";
      "https://github.com/shmish111/servant-purescript.git"."a76104490499aa72d40c2790d10e9383e0dbde63" = "11nxxmi5bw66va7psvrgrw7b7n85fvqgfp58yva99w3v9q3a50v9";
      "https://github.com/input-output-hk/cardano-base"."cb0f19c85e5bb5299839ad4ed66af6fa61322cc4" = "0dnkfqcvbifbk3m5pg8kyjqjy0zj1l4vd23p39n6ym4q0bnib1cq";
      "https://github.com/input-output-hk/cardano-crypto.git"."07397f0e50da97eaa0575d93bee7ac4b2b2576ec" = "06sdx5ndn2g722jhpicmg96vsrys89fl81k8290b3lr6b1b0w4m3";
      "https://github.com/input-output-hk/cardano-ledger-specs"."12a0ef69d64a55e737fbf4e846bd8ed9fb30a956" = "0mx1g18ypdd5m8ijc2cl9m1xmymlqfbwl1r362f92vxrmziacifv";
      "https://github.com/input-output-hk/cardano-prelude"."fd773f7a58412131512b9f694ab95653ac430852" = "02jddik1yw0222wd6q0vv10f7y8rdgrlqaiy83ph002f9kjx7mh6";
      "https://github.com/input-output-hk/goblins"."cde90a2b27f79187ca8310b6549331e59595e7ba" = "17c88rbva3iw82yg9srlxjv2ia5wjb9cyqw44hik565f5v9svnyg";
      "https://github.com/input-output-hk/iohk-monitoring-framework"."34abfb7f4f5610cabb45396e0496472446a0b2ca" = "1fdc0a02ipa385dnwa6r6jyc8jlg537i12hflfglkhjs2b7i92gs";
      "https://github.com/input-output-hk/ouroboros-network"."f149c1c1e4e4bb5bab51fa055e9e3a7084ddc30e" = "1szh3xr7qnx56kyxd554yswpddbavb7m7k2mk3dqdn7xbg7s8b8w";
      "https://github.com/input-output-hk/cardano-node.git"."3a56ac245c83d3345f81123ec3bb496bb23477a3" = "0dglxqhqrdn5nc3n6c8b7himgxrjdjszcl905xihrnaav49z09mg";
      "https://github.com/input-output-hk/optparse-applicative"."7497a29cb998721a9068d5725d49461f2bba0e7a" = "1gvsrg925vynwgqwplgjmp53vj953qyh3wbdf34pw21c8r47w35r";
      "https://github.com/input-output-hk/Win32-network"."3825d3abf75f83f406c1f7161883c438dac7277d" = "19wahfv726fa3mqajpqdqhnl9ica3xmf68i254q45iyjcpj1psqx";
      "https://github.com/input-output-hk/hedgehog-extras"."edf6945007177a638fbeb8802397f3a6f4e47c14" = "0wc7qzkc7j4ns2rz562h6qrx2f8xyq7yjcb7zidnj7f6j0pcd0i9";
    };
    # Configuration settings needed for cabal configure to work when cross compiling
    # for windows. We can't use `modules` for these as `modules` are only applied
    # after cabal has been configured.
    cabalProjectLocal = lib.optionalString pkgs.stdenv.hostPlatform.isWindows ''
      -- When cross compiling for windows we don't have a `ghc` package, so use
      -- the `plutus-ghc-stub` package instead.
      packages:
        stubs/plutus-ghc-stub
      package plutus-tx-plugin
        flags: +use-ghc-stub

      -- Exlcude test that use `doctest`.  They will not work for windows
      -- cross compilation and `cabal` will not be able to make a plan.
      package marlowe
        tests: False
      package prettyprinter-configurable
        tests: False
    '' + lib.optionalString pkgs.stdenv.hostPlatform.isGhcjs ''
      packages:
        stubs/cardano-api-stub
        stubs/iohk-monitoring-stub
        stubs/plutus-ghc-stub
        contrib/*

      allow-newer:
             stm:base

           -- ghc-boot 8.10.4 is not in hackage, so haskell.nix needs consider 8.8.3
           -- when cross compiling for windows or it will fail to find a solution including
           -- a new Win32 version (ghc-boot depends on Win32 via directory)
           , ghc-boot:base
           , ghc-boot:ghc-boot-th
           , snap-server:attoparsec
           , io-streams-haproxy:attoparsec
           , snap-core:attoparsec
           , websockets:attoparsec
           , jsaddle:base64-bytestring

      source-repository-package
        type: git
        location: https://github.com/hamishmack/foundation
        tag: 421e8056fabf30ef2f5b01bb61c6880d0dfaa1c8
        --sha256: 0cbsj3dyycykh0lcnsglrzzh898n2iydyw8f2nwyfvfnyx6ac2im
        subdir: foundation
    '';
    modules = [
      ({ pkgs, ... }: lib.mkIf (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform) {
        packages = {
          # Things that need plutus-tx-plugin
          marlowe.package.buildable = false; # Would also require libpq
          marlowe-actus.package.buildable = false;
          marlowe-dashboard-server.package.buildable = false;
          marlowe-playground-server.package.buildable = false; # Would also require libpq
          marlowe-symbolic.package.buildable = false;
          playground-common.package.buildable = false;
          plutus-benchmark.package.buildable = false;
          plutus-chain-index.package.buildable = false;
          plutus-contract.package.buildable = false;
          plutus-errors.package.buildable = false;
          plutus-ledger.package.buildable = false;
          plutus-pab.package.buildable = false;
          plutus-playground-server.package.buildable = false; # Would also require libpq
          plutus-use-cases.package.buildable = false;
          web-ghc.package.buildable = false;
          # Needs agda
          plutus-metatheory.package.buildable = false;
          # These need R
          plutus-core.components.benchmarks.cost-model-test.buildable = lib.mkForce false;
          plutus-core.components.benchmarks.update-cost-model.buildable = lib.mkForce false;
          # Windows build of libpq is marked as broken
          fake-pab.package.buildable = false;
        };
      })
      ({ pkgs, ... }:
        let
          # Add symlinks to the DLLs used by executable code to the `bin` directory
          # of the components with we are going to run.
          # We should try to find a way to automate this will in haskell.nix.
          symlinkDlls = ''
            ln -s ${libsodium-vrf}/bin/libsodium-23.dll $out/bin/libsodium-23.dll
            ln -s ${pkgs.buildPackages.gcc.cc}/x86_64-w64-mingw32/lib/libgcc_s_seh-1.dll $out/bin/libgcc_s_seh-1.dll
            ln -s ${pkgs.buildPackages.gcc.cc}/x86_64-w64-mingw32/lib/libstdc++-6.dll $out/bin/libstdc++-6.dll
            ln -s ${pkgs.windows.mcfgthreads}/bin/mcfgthread-12.dll $out/bin/mcfgthread-12.dll
          '';
        in
        lib.mkIf (pkgs.stdenv.hostPlatform.isWindows) {
          packages = {
            # Add dll symlinks to the compoents we want to run.
            plutus-core.components.tests.plutus-core-test.postInstall = symlinkDlls;
            plutus-core.components.tests.plutus-ir-test.postInstall = symlinkDlls;
            plutus-core.components.tests.untyped-plutus-core-test.postInstall = symlinkDlls;
            plutus-ledger-api.components.tests.plutus-ledger-api-test.postInstall = symlinkDlls;

            # These three tests try to use `diff` and the following could be used to make the
            # linux version of diff available.  Unfortunately the paths passed to it are windows style.
            # plutus-core.components.tests.plutus-core-test.build-tools = [ pkgs.buildPackages.diffutils ];
            # plutus-core.components.tests.plutus-ir-test.build-tools = [ pkgs.buildPackages.diffutils ];
            # plutus-core.components.tests.untyped-plutus-core-test.build-tools = [ pkgs.buildPackages.diffutils ];
            plutus-core.components.tests.plutus-core-test.buildable = lib.mkForce false;
            plutus-core.components.tests.plutus-ir-test.buildable = lib.mkForce false;
            plutus-core.components.tests.untyped-plutus-core-test.buildable = lib.mkForce false;
          };
        }
      )
      ({ pkgs, config, ... }: {
        packages = {

          ghcjs.components.library.build-tools = let alex = pkgs.haskell-nix.tool compiler-nix-name "alex" {
            index-state = pkgs.haskell-nix.internalHackageIndexState;
            version = "3.2.5";
          }; in [ alex ];
          ghcjs.flags.use-host-template-haskell = true;

          # This is important. We may be reinstalling lib:ghci, and if we do
          # it *must* have the ghci flag enabled (default is disabled).
          ghci.flags.ghci = true;

          plutus-use-cases.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-tx-plugin.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  #                                              "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-tx-tests.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  #                                              "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-errors.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-benchmark.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];


          plutus-ledger.components.library.build-tools = if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs) then [ pkgs.pkgsCross.ghcjs.buildPackages.haskell-nix.compiler.${compiler-nix-name}.buildGHC ] else [ ];
          plutus-ledger.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-ledger-test.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          plutus-pab.ghcOptions =
            if (ghcjsPluginPkgs != null && pkgs.stdenv.hostPlatform.isGhcjs)
            then
              (
                let attr = ghcjsPluginPkgs.haskell.projectPackages.plutus-tx-plugin.components.library;
                in
                [
                  "-host-package-db ${attr.passthru.configFiles}/${attr.passthru.configFiles.packageCfgDir}"
                  "-host-package-db ${attr}/package.conf.d"
                  "-Werror"
                ]
              )
            else __trace "nativePlutus is null" [ ];

          Cabal.patches = [ ../../patches/cabal.patch ];
          # See https://github.com/input-output-hk/plutus/issues/1213 and
          # https://github.com/input-output-hk/plutus/pull/2865.
          marlowe.doHaddock = deferPluginErrors;
          marlowe.flags.defer-plugin-errors = deferPluginErrors;

          plutus-contract.doHaddock = deferPluginErrors;
          plutus-contract.flags.defer-plugin-errors = deferPluginErrors;

          plutus-use-cases.doHaddock = deferPluginErrors;
          plutus-use-cases.flags.defer-plugin-errors = deferPluginErrors;

          plutus-ledger.doHaddock = deferPluginErrors;
          plutus-ledger.flags.defer-plugin-errors = deferPluginErrors;

          # Packages we just don't want docs for
          plutus-benchmark.doHaddock = false;
          # FIXME: Haddock mysteriously gives a spurious missing-home-modules warning
          plutus-tx-plugin.doHaddock = false;

          # Fix missing executables on the paths of the test runners. This is arguably
          # a bug, and the fix is a bit of a hack.
          marlowe.components.tests.marlowe-test.preCheck = ''
            PATH=${lib.makeBinPath [ z3 ]}:$PATH
          '';
          # In this case we can just propagate the native dependencies for the build of the test executable,
          # which are actually set up right (we have a build-tool-depends on the executable we need)
          # I'm slightly surprised this works, hooray for laziness!
          plutus-metatheory.components.tests.test1.preCheck = ''
            PATH=${lib.makeBinPath project.hsPkgs.plutus-metatheory.components.tests.test1.executableToolDepends }:$PATH
          '';
          # FIXME: Somehow this is broken even with setting the path up as above
          plutus-metatheory.components.tests.test2.doCheck = false;
          # plutus-metatheory needs agda with the stdlib around for the custom setup
          # I can't figure out a way to apply this as a blanket change for all the components in the package, oh well
          plutus-metatheory.components.library.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.exes.plc-agda.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test1.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test2.build-tools = [ agdaWithStdlib ];
          plutus-metatheory.components.tests.test3.build-tools = [ agdaWithStdlib ];

          # Relies on cabal-doctest, just turn it off in the Nix build
          prettyprinter-configurable.components.tests.prettyprinter-configurable-doctest.buildable = lib.mkForce false;

          plutus-core.components.benchmarks.update-cost-model = {
            build-tools = r-packages;
            # Seems to be broken on darwin for some reason
            platforms = lib.platforms.linux;
          };

          plutus-core.components.benchmarks.cost-model-test = {
            build-tools = r-packages;
            # Seems to be broken on darwin for some reason
            platforms = lib.platforms.linux;
          };

          marlowe-actus.components.exes.marlowe-shiny = {
            build-tools = r-packages;
            # Seems to be broken on darwin for some reason
            platforms = lib.platforms.linux;
          };

          # The marlowe-actus tests depend on external data which is
          # provided from Nix (as niv dependency)
          marlowe-actus.components.tests.marlowe-actus-test.preCheck = ''
            export ACTUS_TEST_DATA_DIR=${actus-tests}/tests/
          '';

          # Broken due to warnings, unclear why the setting that fixes this for the build doesn't work here.
          iohk-monitoring.doHaddock = false;

          # Werror everything. This is a pain, see https://github.com/input-output-hk/haskell.nix/issues/519
          plutus-core.ghcOptions = [ "-Werror" ];
          marlowe.ghcOptions = [ "-Werror" ];
          marlowe-symbolic.ghcOptions = [ "-Werror" ];
          marlowe-actus.ghcOptions = [ "-Werror" ];
          marlowe-playground-server.ghcOptions = [ "-Werror" ];
          marlowe-dashboard-server.ghcOptions = [ "-Werror" ];
          fake-pab.ghcOptions = [ "-Werror" ];
          playground-common.ghcOptions = [ "-Werror" ];
          # FIXME: has warnings
          #plutus-metatheory.package.ghcOptions = "-Werror";
          plutus-contract.ghcOptions = [ "-Werror" ];
          # plutus-ledger.ghcOptions = [ "-Werror" ];
          plutus-ledger-api.ghcOptions = [ "-Werror" ];
          plutus-playground-server.ghcOptions = [ "-Werror" ];
          # plutus-pab.ghcOptions = [ "-Werror" ];
          plutus-tx.ghcOptions = [ "-Werror" ];
          # plutus-tx-plugin.ghcOptions = [ "-Werror" ];
          plutus-doc.ghcOptions = [ "-Werror" ];
          # plutus-use-cases.ghcOptions = [ "-Werror" ];

          # External package settings

          inline-r.ghcOptions = [ "-XStandaloneKindSignatures" ];

          # Honestly not sure why we need this, it has a mysterious unused dependency on "m"
          # This will go away when we upgrade nixpkgs and things use ieee754 anyway.
          ieee.components.library.libs = lib.mkForce [ ];

          # See https://github.com/input-output-hk/iohk-nix/pull/488
          cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ libsodium-vrf ] ];
          cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ [ libsodium-vrf ] ];
        };
      })
    ] ++ lib.optional enableHaskellProfiling {
      enableLibraryProfiling = true;
      enableExecutableProfiling = true;
    };
  });

in
project
