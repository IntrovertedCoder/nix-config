{ config, self, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.music = { pkgs, lib, config, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    services.mpd = {
      enable = true;
      user = "shot";
      group = "users";
      settings = {
        music_directory = "/home/shot/Music";
        bind_to_address = "/run/mpd/socket";
        replaygain = "auto";
        audio_output = [
          {
            type = "pipewire";
            name = "PipeWire";
          }
        ];
      };
    };

    systemd.services.mpd = {
      after = [ "sound.target" ];
      serviceConfig = {
        Environment = [
          "XDG_RUNTIME_DIR=/run/user/1000"
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    preservation.preserveAt."/persistent" = {
      directories = lib.mkIf config.services.mpd.enable [
        "/var/lib/mpd"
      ];
      users.shot = {
        directories = [
          "Music"
          ".local/share/mpd"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];

    home-manager.users.shot = {
      home.packages = with pkgs; [
        mpc
      ];

      services.mpd = {
        enable = true;
        musicDirectory = "/home/shot/Music";
        network.listenAddress = "/run/user/1000/mpd-main.sock";
        extraConfig = ''
          replaygain "auto"
          audio_output {
              type "pipewire"
              name "PipeWire"
          }
        '';
      };

      programs.rmpc = {
        enable = true;
        config = ''
          #![enable(implicit_some)]
          (
              address: "/run/user/1000/mpd-main.sock",
              theme: "guildmaster",
          )
        '';
      };

      xdg.configFile."rmpc/themes/guildmaster.ron".text = ''
        #![enable(implicit_some)]
        #![enable(unwrap_newtypes)]
        #![enable(unwrap_variant_newtypes)]
        (
            background_color: None,
            text_color: "#${c.white}",
            header_background_color: None,
            modal_background_color: None,
            preview_label_style: (fg: "#${c.yellow}"),
            preview_metadata_group_style: (fg: "#${c.yellow}", modifiers: "Bold"),
            highlighted_item_style: (fg: "#${c.blue}", modifiers: "Bold"),
            current_item_style: (fg: "#${c.black}", bg: "#${c.blue}", modifiers: "Bold"),
            borders_style: (fg: "#${c.grey1}"),
            highlight_border_style: (fg: "#${c.green}"),
            level_styles: (
                info: (fg: "#${c.blue}", bg: "#${c.black}"),
                warn: (fg: "#${c.yellow}", bg: "#${c.black}"),
                error: (fg: "#${c.red}", bg: "#${c.black}"),
                debug: (fg: "#${c.lgreen}", bg: "#${c.black}"),
                trace: (fg: "#${c.magenta}", bg: "#${c.black}"),
            ),
            progress_bar: (
                symbols: ["█", "█", "█", " ", "█"],
                track_style: None,
                elapsed_style: (fg: "#${c.blue}"),
                thumb_style: (fg: "#${c.blue}"),
                use_track_when_empty: true,
            ),
            scrollbar: (
                symbols: ["│", "█", "▲", "▼"],
                track_style: (),
                ends_style: (),
                thumb_style: (fg: "#${c.blue}"),
            ),
            tab_bar: (
                active_style: (fg: "#${c.black}", bg: "#${c.blue}", modifiers: "Bold"),
            ),
            song_table_format: [
                (
                    prop: (kind: Property(Artist), default: (kind: Text("Unknown"))),
                    label_prop: (kind: Text("Artist")),
                    width: "20%",
                ),
                (
                    prop: (kind: Property(Title), default: (kind: Text("Unknown"))),
                    label_prop: (kind: Text("Title")),
                    width: "35%",
                ),
                (
                    prop: (kind: Property(Album), style: (fg: "#${c.white2}"),
                        default: (kind: Text("Unknown Album"), style: (fg: "#${c.white2}"))
                    ),
                    label_prop: (kind: Text("Album")),
                    width: "30%",
                ),
                (
                    prop: (kind: Property(Duration), default: (kind: Text("-"))),
                    label_prop: (kind: Text("Duration")),
                    width: "15%",
                    alignment: Right,
                ),
            ],
        )
      '';

      wayland.windowManager.mango.settings.bind = [
        # Main mpd instance
        "ALT,comma,spawn,env MPD_HOST=/run/user/1000/mpd-main.sock ${pkgs.mpc}/bin/mpc prev"
        "ALT,period,spawn,env MPD_HOST=/run/user/1000/mpd-main.sock ${pkgs.mpc}/bin/mpc next"
        "ALT,slash,spawn,env MPD_HOST=/run/user/1000/mpd-main.sock ${pkgs.mpc}/bin/mpc toggle"
        "ALT,grave,spawn,uwsm app -- foot -a launcher -e ${pkgs.rmpc}/bin/rmpc --address /run/user/1000/mpd-main.sock"

        # Background mpd instance
        "ALT+SHIFT,comma,spawn,env MPD_HOST=/run/mpd/socket ${pkgs.mpc}/bin/mpc prev"
        "ALT+SHIFT,period,spawn,env MPD_HOST=/run/mpd/socket ${pkgs.mpc}/bin/mpc next"
        "ALT+SHIFT,slash,spawn,env MPD_HOST=/run/mpd/socket ${pkgs.mpc}/bin/mpc toggle"
        "ALT+SHIFT,grave,spawn,uwsm app -- foot -a launcher -e ${pkgs.rmpc}/bin/rmpc --address /run/mpd/socket"
      ];
    };
  };
}
