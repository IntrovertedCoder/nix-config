echo "Setup github ssh key: https://github.com/settings/ssh/new"
cat /home/shot/.ssh/github.pub
echo "Tailscale"
sudo tailscale login -qr
sudo tailscale up --operator=$USER
tailscale debug prefs | grep -i operator
tailscale up --accept-routes
