echo "Setup github ssh key: https://github.com/settings/ssh/new"
cat /home/shot/.ssh/github.pub
read -p "Press enter to continue"
echo "Tailscale"
sudo tailscale login -qr
sudo tailscale up --operator=$USER
tailscale debug prefs | grep -i operator
tailscale up
read -p "Press enter to continue"
echo "Bitwarden client"
echo "Open https://vault.bitwarden.com/#/settings/security/security-keys"
read -p "Press enter"
rbw register
echo ""
read -p "Sign into mullvad"
echo ""
read -p "Sign into vesktop"
echo ""
read -p "Sign into RadarOmega"
echo ""
read -p "Sign into steam"
read -p "Steam -> Settings -> Storage -> Add ~/Games/Steam -> Make Default"
echo ""
read -p "Sign into heroic"
read -p "Heroic -> Settings -> Game Defaults -> Advanced -> Wrapper command: gmmh"
echo ""
read -p "Sign into signal"
echo ""
read -p "Sign into prim"
