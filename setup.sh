sudo mkdir -p /etc/hosts.d/
sudo rm -rf /etc/NetworkManager
sudo cp -r NetworkManager /etc
sudo rm -rf /etc/libvirt/hooks
sudo cp -r libvirt/hooks /etc/libvirt/hooks
sudo systemctl restart NetworkManager
sudo systemctl restart libvirtd
