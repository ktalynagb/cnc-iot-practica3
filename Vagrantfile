Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2004"
  config.ssh.insert_key = false
  config.vbguest.auto_update = false

  config.vm.hostname = "cnc-iot"
  config.vm.network "forwarded_port", guest: 8000, host: 8000
  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "cnc-iot-backend"
    vb.memory = "2048"
    vb.cpus   = 2
  end

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y python3 python3-pip python3-venv postgresql postgresql-contrib git make
    sudo -u postgres psql -c "CREATE USER cnc_user WITH PASSWORD 'cnc_password';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE cnc_iot OWNER cnc_user;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cnc_iot TO cnc_user;" 2>/dev/null || true
    echo "Provisioning completo"
  SHELL
end