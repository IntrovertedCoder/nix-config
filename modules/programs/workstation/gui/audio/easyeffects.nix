{ self, inputs, ... }: {
  flake.nixosModules.easyeffects = { lib, pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
    ];

    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      systemd.user.services.easyeffects = {
        Unit = {
          After = [ "graphical-session.target" "pipewire.service" ];
          PartOf = [ "graphical-session.target" "pipewire.service" ];
        };
        Service = {
          Restart = lib.mkForce "always";
          ExecStartPost = [
            "${pkgs.coreutils}/bin/sleep 3"
            "${pkgs.easyeffects}/bin/easyeffects -l Output"
            "${pkgs.easyeffects}/bin/easyeffects -l Input"
          ];
        };
      };

      services.easyeffects = {
        enable = true;
        preset = "Output";
        extraPresets = {
          Output = {
            output = { # {{{
              blocklist = [

              ];
              plugins_order = [
                "equalizer#0" # IE200 EQ
                "bass_enhancer#0"
                "compressor#0" # Upward
                "multiband_compressor#0" # Downward (exclude bass)
              ];
              "equalizer#0" = { # {{{
                balance = 0.0;
                bypass = false;
                input-gain = 0.0;
                mode = "IIR";
                num-bands = 9;
                output-gain = 0.0;
                pitch-left = 0.0;
                pitch-right = 0.0;
                split-channels = false;
                left = { # {{{
                  band0 = {
                    frequency = 43.0;
                    gain = 0.8999999761581421;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.8999999761581421;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band1 = {
                    frequency = 150;
                    gain = -0.20000000298023224;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band2 = {
                    frequency = 250;
                    gain = -2.0;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.699999988079071;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band3 = {
                    frequency = 1600.0;
                    gain = -2.4000000953674316;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band4 = {
                    frequency = 4000.0;
                    gain = -3.0999999046325684;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.5;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band5 = {
                    frequency = 6700.0;
                    gain = 4.599999904632568;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band6 = {
                    frequency = 7900.0;
                    gain = -8.6999999809265137;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band7 = {
                    frequency = 8300.0;
                    gain = -3.200000047683716;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band8 = {
                    frequency = 11000.0;
                    gain = 12.0;
                    mode = "APO (DR)";
                    mute = false;
                    q = 1.899999976158142;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                }; # }}}
                right = { # {{{
                  band0 = {
                    frequency = 43.0;
                    gain = 0.8999999761581421;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.8999999761581421;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band1 = {
                    frequency = 150;
                    gain = -0.20000000298023224;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band2 = {
                    frequency = 250;
                    gain = -2.0;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.699999988079071;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band3 = {
                    frequency = 1600.0;
                    gain = -2.4000000953674316;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band4 = {
                    frequency = 4000.0;
                    gain = -3.0999999046325684;
                    mode = "APO (DR)";
                    mute = false;
                    q = 0.5;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band5 = {
                    frequency = 6700.0;
                    gain = 4.599999904632568;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band6 = {
                    frequency = 7900.0;
                    gain = -8.6999999809265137;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band7 = {
                    frequency = 8300.0;
                    gain = -3.200000047683716;
                    mode = "APO (DR)";
                    mute = false;
                    q = 2.0;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                  band8 = {
                    frequency = 11000.0;
                    gain = 12.0;
                    mode = "APO (DR)";
                    mute = false;
                    q = 1.899999976158142;
                    slope = "x1";
                    solo = false;
                    type = "Bell";
                    width = 4.0;
                  };
                }; # }}}
              }; # }}}
              "bass_enhancer#0" = { # {{{
                amount = 1.7;
                blend = 0.0;
                bypass = false;
                floor = 20.0;
                floor-active = false;
                harmonics = 8.5;
                input-gain = 0.0;
                output-gain = 0.0;
                scope = 150;
              }; # }}}
              "compressor#0" = { # {{{
                attack = 20.0;
                boost-amount = 6.0;
                boost-threshold = -72.0;
                bypass = false;
                dry = -100.0;
                hpf-frequency = 200.0;
                input-gain = 0.0;
                knee = -6.0;
                lpf-frequency = 20000.0;
                lpf-mode = "off";
                makeup = 0.0;
                mode = "Upward";
                output-gain = 0.0;
                ratio = 4.0;
                release = 100.0;
                release-threshold = -100.0;
                sidechain = {
                  lookahead = 0.0;
                  mode = "RMS";
                  preamp = 0.0;
                  reactivity = 10.0;
                  source = "Middle";
                  stereo-split-source = "Left/Right";
                  type = "Feed-forward";
                };
                stereo-split = false;
                threshold = -30.0;
                wet = 0.0;
              }; # }}}
              "multiband_compressor#0" = { # {{{
                band0 = {
                  attack-threshold = 0.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 500.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 10.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  stereo-split-source = "Left/Right";
                };
                band1 = {
                  attack-threshold = -30.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = true;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 4.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 1000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 500.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 300.0;
                  stereo-split-source = "Left/Right";
                };
                band2 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 2000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 1000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 1000.0;
                  stereo-split-source = "Left/Right";
                };
                band3 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 4000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 2000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 2000.0;
                  stereo-split-source = "Left/Right";
                };
                band4 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 8000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 4000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 4000.0;
                  stereo-split-source = "Left/Right";
                };
                band5 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 12000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 8000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 8000.0;
                  stereo-split-source = "Left/Right";
                };
                band6 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 16000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 12000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 12000.0;
                  stereo-split-source = "Left/Right";
                };
                band7 = {
                  attack-threshold = -12.0;
                  attack-time = 20.0;
                  boost-amount = 6.0;
                  boost-threshold = -72.0;
                  compression-mode = "Downward";
                  compressor-enable = true;
                  enable-band = false;
                  external-sidechain = false;
                  knee = -6.0;
                  makeup = 0.0;
                  mute = false;
                  ratio = 1.0;
                  release-threshold = -100.0;
                  release-time = 100.0;
                  sidechain-custom-highcut-filter = false;
                  sidechain-custom-lowcut-filter = false;
                  sidechain-highcut-frequency = 20000.0;
                  sidechain-lookahead = 0.0;
                  sidechain-lowcut-frequency = 16000.0;
                  sidechain-mode = "RMS";
                  sidechain-preamp = 0.0;
                  sidechain-reactivity = 10.0;
                  sidechain-source = "Middle";
                  solo = false;
                  split-frequency = 16000.0;
                  stereo-split-source = "Left/Right";
                };
                bypass = false;
                compressor-mode = "Modern";
                dry = -100.0;
                envelope-boost = "None";
                input-gain = 0.0;
                output-gain = 0.0;
                stereo-split = false;
                wet = 0.0;
              }; # }}}
            }; # }}}
          };
          Input = {
            input =  { # {{{
              blocklist = [

              ];
              plugins_order = [
                # "gate#0"
                # "bass_enhancer#0"
                # "compressor#0"
                # "compressor#1"
                "speex#0"
              ];
              "gate#0" = { # {{{
                bypass = false;
                attack = 20.0;
                curve-threshold = -50.0;
                curve-zone = -6.0;
                dry = -100.0;
                hpf-frequency = 10;
                hpf-mode = "off";
                hysteresis = true;
                hysteresis-threshold = -12.0;
                hysteresis-zone = -6.0;
                input-gain = 0.0;
                lpf-frequency = 20000.0;
                lpf-mode = "off";
                makeup = 0.0;
                output-gain = 0.0;
                reduction = -72.0;
                release = 10;
                sidechain = {
                  input = "Internal";
                  lookahead = 0.0;
                  mode = "RMS";
                  preamp = 0.0;
                  reactivity = 10.0;
                  source = "Middle";
                  stereo-split-source = "Left/Right";
                };
                stereo-split = false;
                wet = 0.0;
              }; # }}}
              "bass_enhancer#0" = { # {{{
                bypass = false;
                amount = 1.7;
                blend = 0.0;
                floor = 20.0;
                floor-active = false;
                harmonics = 8.5;
                input-gain = 0.0;
                output-gain = 0.0;
                scope = 250.0;
              }; # }}}
              "compressor#0" = { # {{{
                bypass = false;
                attack = 10.0;
                boost-amount = 6.0;
                boost-threshold = -72.0;
                dry = -100.0;
                hpf-frequency = 10.0;
                hpf-mode = "off";
                input-gain = 0.0;
                knee = -6.0;
                lpf-frequency = 20000.0;
                lpf-mode = "off";
                makeup = 0.0;
                mode = "Downward";
                output-gain = 0.0;
                ratio = 4.0;
                release = 20.0;
                release-threshold = -100.0;
                sidechain = {
                  lookahead = 0.0;
                  mode = "RMS";
                  preamp = 0.0;
                  reactivity = 10.0;
                  source = "Middle";
                  stereo-split-source = "Left/Right";
                  type = "Feed-forward";
                };
                stereo-split = false;
                threshold = -15.0;
                wet = 0.0;
              }; # }}}
              "compressor#1" = { # {{{
                bypass = false;
                attack = 20.0;
                boost-amount = 6.0;
                boost-threshold = -72.0;
                dry = -100.0;
                hpf-frequency = 10.0;
                hpf-mode = "off";
                input-gain = 0.0;
                knee = -6.0;
                lpf-frequency = 20000.0;
                lpf-mdoe = "off";
                makeup = 0.0;
                mode = "Upward";
                output-gain = 0.0;
                ratio = 4.0;
                release = 20.0;
                release-threshold = -100.0;
                sidechain = {
                  lookahead = 0.0;
                  mode = "RMS";
                  preamp = 0.0;
                  reactivity = 10.0;
                  source = "Middle";
                  stereo-split-source = "Left/Right";
                  type = "Feed-forward";
                };
                stero-split = false;
                threshold = -15.0;
                wet = 0.0;
              }; # }}}
              "speex#0" = { # {{{
                bypass = false;
                enable-agc = true;
                enable-denoise = true;
                enable-dereverb = true;
                input-gain = 0.0;
                vad = {
                  enable = true;
                  probability-continue = 85;
                  probability-start = 90;
                };
              }; # }}}
            }; # }}}
          };
        };
      };
    };
  };
}
