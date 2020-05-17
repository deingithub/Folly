with import (builtins.fetchTarball {
  # nixos-unstable on 2020-05-14
  url = "https://github.com/NixOS/nixpkgs/tarball/8ba41a1e14961fe43523f29b8b39acb569b70e72";
  sha256 = "0c2wn7si8vcx0yqwm92dpry8zqjglj9dfrvmww6ha6ihnjl6mfhh";
}) {};

pkgs.binutils-unwrapped.overrideAttrs (oldAttrs: rec {
  configureFlags = oldAttrs.configureFlags ++ [ "--target=riscv64-elf" ];
  doInstallCheck = false;
})
