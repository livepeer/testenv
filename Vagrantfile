# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.require_version ">= 2.0.0"

require 'etc'

# Specify a custom local directory for project source repos.
DEFAULT_DATADIR = File.join("..", "lpdev-data")
project_src_dirs = ENV["LPSRC"] || File.join(ENV["HOME"],"src")

if !File.directory?(project_src_dirs)
  if ["reload","up"].include?(ARGV[0])
    puts "INFO: The default directory for project source files (~/src) or the
  directory you provided in the environment variable $LPSRC does not exist.
  Setting this to '#{DEFAULT_DATADIR}', please create ~/src or provide a directory that contains
  your project's source repos. This will be mounted in the virtual machine as
  /src."
  end

  project_src_dirs = DEFAULT_DATADIR
end

# NOTE: In some use cases it might be desirable to have the VM act as an
# independent device on the network. In this case, set the env var below.
bridge_network = ENV["BRIDGED_NET"] || false

# By default, we expect to run up to 5 nodes so we forward 5 port pairs
# starting with the ports listed below.
default_nodes = ENV["NODES"] || 5

# Livepeer RTMP and HTTP ports used by the guest VM.
rtmp_port = 1935
api_port = 8935
ipfs_port = 4001

# Get current user pid and gid
uid = Etc.getpwnam(ENV["USER"]).uid
gid = Etc.getpwnam(ENV["USER"]).gid

Vagrant.configure("2") do |config|

  config.vm.box = "livepeer/ubuntu1604"
  config.vm.box_version = "201712.11.01"
  config.vm.hostname = "livepeer-ubuntu1604"

  if !bridge_network
    default_nodes.times do
      config.vm.network "forwarded_port", guest: rtmp_port, host: rtmp_port
      config.vm.network "forwarded_port", guest: api_port, host: api_port
      rtmp_port += 1
      api_port += 1
    end

    config.vm.network "forwarded_port", guest: ipfs_port, host: ipfs_port
  else
    config.vm.network "public_network"
  end

  config.vm.synced_folder project_src_dirs, "/home/vagrant/src", create: true

  config.vm.provision "shell", inline: "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -"
  config.vm.provision "shell", inline: "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\""
  config.vm.provision "shell", inline: "sudo apt-get update"
  config.vm.provision "shell", inline: "sudo apt-get install -y bindfs"
  config.vm.provision "shell", inline: "sudo apt-get install -y jq"
  config.vm.provision "shell", inline: "sudo apt-get install unzip"
  config.vm.provision "shell", inline: "sudo apt-get install -y docker-ce"

  config.vm.provision "file", source: "dot_lpdev_cmds.sh", destination: "$HOME/.lpdev_cmds.sh"
  config.vm.provision "shell", inline: "if ! grep -q lpdev_cmds.sh /home/vagrant/.bashrc; then echo 'source $HOME/.lpdev_cmds.sh' >> /home/vagrant/.bashrc; fi"
  config.vm.provision "shell", privileged: false, inline: "source $HOME/.lpdev_cmds.sh && __lpdev_node_update --no-verbose"
  config.vm.provision "shell", privileged: false, inline: <<~SCREENRC
    cat <<-SHELL_SCREENRC > $HOME/.screenrc
    	# An alternative hardstatus to display a bar at the bottom listing the
    	# windownames and highlighting the current windowname in blue. (This is only
    	# enabled if there is no hardstatus setting for your terminal)
    	hardstatus on
    	hardstatus alwayslastline
    	hardstatus string "%{.bW}%-w%{.rW}%n %t%{-}%+w %=%{..G} %H %{..Y} %m/%d %C%a "
    SHELL_SCREENRC
  SCREENRC

  config.vm.provider "virtualbox" do |vb|
    # Customize the number of CPUs and amount of memory on the VM:
    vb.cpus = 2
    vb.memory = 4096
  end

end
