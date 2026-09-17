{ self, inputs, ... }: {
  flake.nixosModules.goxlr = { lib, pkgs, ... }:
    let
      # GoXLR Mini ALSA/PipeWire sink nodes for its "PC playback" channels.
      # Names come from the ALSA HiFi profile the goxlr-utility udev rules install,
      # and are stable across reboots as long as that profile doesn't change.
      musicSink = "alsa_output.usb-TC-Helicon_GoXLRMini-00.HiFi__Line2__sink";
      chatSink = "alsa_output.usb-TC-Helicon_GoXLRMini-00.HiFi__Headphones__sink";

      # Apps routed straight to the GoXLR Music/Chat channels instead of System.
      # `apps` match the PipeWire "application.name" property of the app's
      # playback stream (see `wpctl status` under Audio > Streams).
      # Add/remove entries here to change routing - no other files need editing.
      routes = [
        { apps = [ "Music Player Daemon" ]; sink = musicSink; }
        { apps = [ "vesktop" "Signal" "signal-desktop" ]; sink = chatSink; }
      ];

      luaList = items: "{ ${lib.concatMapStringsSep ", " (i: "\"${i}\"") items} }";

      luaRoutes = lib.concatMapStringsSep "\n  " (r: ''
        { apps = ${luaList r.apps}, sink = "${r.sink}" },
      '') routes;

      goxlrRoutingLua = ''
        -- Routes specific apps to fixed GoXLR channel sinks instead of the
        -- default System channel. Generated from `routes` in goxlr.nix.

        lutils = require ("linking-utils")
        log = Log.open_topic ("s-linking")

        local routes = {
          ${luaRoutes}
        }

        SimpleEventHook {
          name = "linking/goxlr-routing",
          before = "linking/find-defined-target",
          interests = {
            EventInterest {
              Constraint { "event.type", "=", "select-target" },
            },
          },
          execute = function (event)
            local source, om, si, si_props, si_flags, target =
                lutils:unwrap_select_target_event (event)

            if target then
              return
            end

            if si_props ["media.class"] ~= "Stream/Output/Audio" then
              return
            end

            local app_name = si_props ["application.name"]
            if not app_name then
              return
            end

            for _, route in ipairs (routes) do
              for _, app in ipairs (route.apps) do
                if app_name == app then
                  for lnkbl in om:iterate { type = "SiLinkable" } do
                    local target_props = lnkbl.properties
                    if target_props ["node.name"] == route.sink
                        and target_props ["item.node.direction"] == "input"
                        and lutils.canLink (si_props, lnkbl) then
                      log:info (si, "goxlr-routing: routing " .. app_name .. " to " .. route.sink)
                      event:set_data ("target", lnkbl)
                      return
                    end
                  end
                  return
                end
              end
            end
          end
        }:register ()
      '';
    in {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    services.goxlr-utility.enable = true;

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".local/share/goxlr-utility"
        ];
        files = [
          ".config/goxlr-utility/settings.json"
        ];
      };
    };

    home-manager.users.shot = {
      # WirePlumber only resolves lua scripts named by a bare component
      # name (no path) under $XDG_DATA_HOME/wireplumber/scripts - NOT
      # $XDG_CONFIG_HOME, even though the .conf.d fragment below does live
      # under $XDG_CONFIG_HOME. Confirmed live: placing it under
      # xdg.configFile fails with "Could not locate script".
      xdg.dataFile."wireplumber/scripts/goxlr-routing.lua".text = goxlrRoutingLua;

      xdg.configFile."wireplumber/wireplumber.conf.d/51-goxlr-routing.conf".text = ''
        wireplumber.components = [
          {
            name = goxlr-routing.lua
            type = script/lua
            provides = hooks.linking.target.find-goxlr
          }
        ]

        # `wireplumber.profiles` from this fragment isn't merged with the
        # base profile (confirmed live: wp-conf logs "used as-is" for that
        # section), so requesting our hook has to go through the rule-merge
        # mechanism instead, which does merge across conf.d fragments.
        wireplumber.components.rules = [
          {
            matches = [
              { provides = "policy.linking.standard" }
            ]
            actions = {
              merge = {
                wants = [ hooks.linking.target.find-goxlr ]
              }
            }
          }
        ]
      '';
    };
  };
}
