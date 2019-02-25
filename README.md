# Dev Environment

This repository contains everything you need to set up a Livepeer local
dev environment.

There is a virtual machine that is pre-built with key dependencies and
includes a wizard (lpdev) that will let you:

- Run a local Geth node and a local Ethereum network
- Deploy the Livepeer protocol to the local Ethereum network
- Configure and run a Livepeer broadcaster node
- Configure and run a Livepeer transcoder node

## Installation

Install Vagrant 2.0.x: https://www.vagrantup.com/

Install VirtualBox 5.0.x or 5.1.x: https://www.virtualbox.org/

Clone the repo and run this command:

```
host-machine $ git clone https://github.com/livepeer/devenv.git
host-machine $ cd devenv
host-machine $ vagrant up
```

### Host Machine Repos and `$LPSRC`

By default, Vagrant will mount a host machine directory as the location for 
this project's source repos in the virtual machine as `$HOME/src`.

You can provide a customized directory to Vagrant when bringing the
virtual machine "up" via the environment variable `$LPSRC`. We recommend
the directory of your `devenv` repo.

```
host-machine $ LPSRC=$HOME/your/local/repos/devenv vagrant up
```

Or during a reload:

```
host-machine $ LPSRC=$HOME/your/local/repos/devenv vagrant reload
```

If this is not provided and `~/src` does not exist, the default value of
`..` is used and should work in most cases.

## Usage

**Protip:** Virtual machines are cheap. Don’t feel tied to this
directory. Make new directories and copy the Vagrantfile to start fresh
at anytime. Or `vagrant destroy` to blow away the vm in this directory.

### Enter the virtual machine

```
host-machine $ vagrant ssh -- -A
```

### Run the lpdev wizard

```
virtual-machine $ lpdev

+----------------------------------------------------+
| Welcome to the Livepeer local dev environment tool |
|                                                    |
+----------------------------------------------------+

== Current Status ==

Geth miner is running: true (19943)
Geth accounts:
  ca4a8b268e1fb4d7105d95d0c90aa5b2b3d6b4ac (miner)
  3206f44d47f9059366a80b6073bc0132cb77b192
  f938d2bc074b36d480cdee4817c907ec8dc6ef4b
  7a50d0f6f8c07568233bfe62538d70efec4df261

Protocol is built: true (current branch: develop)
Protocol deployed to: 0x4d6d6762160436facc3571f1751ce2cd66a7f553

Broadcaster node is running: true (21101)
Transcoder node is running: true (21182)

--

What would you like to do?
1) Display status			  4) Start & set up broadcaster node	   7) Update livepeer and cli		   10) Destroy current environment
2) Set up & start Geth local network	  5) Start & set up transcoder node	   8) Install FFmpeg			   11) Exit
3) Deploy/overwrite protocol contracts	  6) Start & set up verifier		   9) Rebuild FFmpeg
```

_The Current Status values above are specific to your environment. Yours
will be different._

To initialize a Livepeer test environment, run commands 2 through 8.
Command 1 can be used to ensure that everything is running correctly.

Command 4 creates and provisions a broadcaster Ethereum account with a
small amount of test Eth. To replenish this deposit, re-run command 4.
Note that this is not Rinkeby Eth; it is devenv Eth that is only valid
within this VM. From here, broadcasters can stream into the node using
RTMP port 1935 on the host machine.

Command 5 creates, stakes and configures a transcoder node and its
corresponding Ethereum account. Re-running command 5 multiple times will
acquire more test LPT and stake it to the same account. Note this is not
Rinkeby LPT; it is devenv LPT that is only valid within this VM.

Command 9 can be run to force-rebuild FFmpeg if a (re-)install via
command 8 is insufficient. Since FFMpeg is built in the shared directory,
a full FFmpeg rebuild is not necessary is the VM is recreated. Rebuilds
can take a long time; for fresh VMs, a reinstall via Command 8 should
suffice to save time.

### Alternate Usage

Sometimes actually doing development in a VM may be inconvenient. For
example, you might be testing [go-livepeer](github.com/livepeer/go-livepeer)
locally on OSX, rather than Linux. Devenv can be used to jump-start a
test Livepeer environment by automating many of the required steps.
Local nodes can then connect to this VM "remotely".

The idea is to get the blockchain parts running in the devenv VM, and
use the devenv to prepare parameters that can be used by a local build
of go-livepeer. Here is an example workflow:

* Run `lpdev` steps 2 and 3 (Start Geth, deploy protocol contracts)
* Run `lpdev`step 4: start broadcast node. Ensure that it succeeds with
a deposit, eg this message should have been printed: `Depositing 500 Wei`.
Take note of the `datadir` address. For example:
```
      livepeer -controllerAddr 0x7023155754d3c4b7c9ce73778e5c83261ff78f37 \
              -datadir /home/vagrant/.lpdata/broadcaster-ce684ee753 \
              -ethAcctAddr ce684ee753ceff32c69828f8513a55bd16653ade \
              -ethIpcPath /home/vagrant/.ethereum/geth.ipc \
              -ethPassword "pass" \
              -monitor=false \
              -rtmpAddr 0.0.0.0:1935 \
              -httpAddr 0.0.0.0:8935 \
              -cliAddr 0.0.0.0:7935 
```

This creates a broadcaster with an Ethereum account that has been
provisioned with a small Eth deposit. Take the private key from the
`broadcaster-XXX/keystore` datadir, and copy it to the VM's shared
folder (`~/src` within the VM) to make it accessible to the host. Then
a local script can be created to use this key and point to Geth on the
VM. For example:
```
      $HOME/go/src/github.com/livepeer/go-livepeer/livepeer \
              -controllerAddr 0x7023155754d3c4b7c9ce73778e5c83261ff78f37 \
              -datadir $HOME/.lpData/broadcaster \
              -ethUrl "ws://<devenv-host>:8546" \
              -ethPassword "pass" \
              -monitor=false \
              -currentManifest=true\
              -v 99 \
              -devenv
```
Two things to note here: put the key file into `$HOME/.lpData/broadcaster/keystore/keyfile`,
and point `ethUrl` to the devenv host VM, which passes through geth's
port 8546.
* Run `lpdev` step 5: Run through the same steps for the transcoder:
export the keys, copy over and modify any relevant startup parameters,
etc. Note that you might want to shut down the transcoder or any other
Livepeer nodes running in the devenv VM before starting up a local
transcoder, eg run `kill ``pgrep livepeer`` in a VM terminal.
Here is an example of a local configuration:
```
      $HOME/go/src/github.com/livepeer/go-livepeer/livepeer \
              -controllerAddr 0x7023155754d3c4b7c9ce73778e5c83261ff78f37 \
              -datadir $HOME/.lpData/transcoder \
              -ethUrl "ws://<devenv-host>:8546" \
              -cliAddr ":7936" \
              -serviceAddr "127.0.0.1:8936" \
              -ethPassword "pass" \
              -monitor=false \
              -ipfsPath $HOME/.lpData/transcoder/ipfs \
              -v 99 \
              -devenv \
              -initializeRound=true \
              -transcoder
```
There is python script to automate this procedure - `get_eth_accounts_from_devenv.py`. Run it on host machine (after configuring broadcaster and transcoder inside VM) - it will copy keys and create shell scripts to run broadcaster and transcoder.


## Additional Details

The following software is included in this virtual machine:

```
Welcome to the Livepeer Dev Environment
Based on: Ubuntu 16.04.3 LTS (GNU/Linux 4.4.0-96-generic x86_64)

Contains:
	* Go: 1.9.1 linux/amd64
	* Node: 8.9.3
	* npm: 5.5.1
	* Geth: 1.7.3-stable-4bb3c89d
	* Truffle: v4.0.1
	* TestRPC: n/a
	* ffmpeg: 3.1-static (livepeer/ffmpeg-static)
	* livepeer: 0.1.6
	* livepeer_cli: 0.0.0

Documentation: https://github.com/livepeer/devenv
```

The following file and directories are part of the `vagrant` user’s $HOME
in the virtual machine:

### ~/.ethereum
This is the $gethDir for this virtual machine. It is created by Geth.

### ~/.lpdata
This directory is created and used by Livepeer nodes that are run using
the wizard on this virtual machine.  Each node has its own Geth Account
and the first 10 characters of the Account is used to represent the node
as subdirectories within `~/.lpdata`.

### ~/.lpdev_cmds.sh
This file is where the Livepeer local dev environment wizard lives. It
is synced from the `dot_lpdev_cmds.sh` file in this repo during the
Vagrant provisioning step and sourced `source $HOME/.lpdev_cmds.sh` in
any interactive shell.

You can add new commands or edit existing ones by modifying the host
machine copy of `dot_lpdev_cmds.sh` and re-provisioning:

```
host-machine $ vagrant provision
```

### ~/go
This is the $GOROOT for this virtual machine. This doesn't exist until you
install software using `go get [software]`.  _Changes to this directory are 
made to the host machine and vice versa in `$LPSRC/go_src`._

### ~/livepeer_linux
This directory is where the latest official release of the Livepeer node
software lives.

### ~/src
This is the synced folder on the virtual machine for working copies of
various project repositories checked out and stored on the host machine.
_Changes in the virtual machine are made to the host machine and
vice versa._

The `~/src` directory is replaced with any repositories in the directory
on the host machine as provided by environment var `$LPSRC` or the
defaults (`~/src`, `..`).

### Vagrant Commands
These commands are useful for operating a virtual machine run by
Vagrant. Run them in the directory that contains your Vagrantfile.

- If you want to init or boot it: `host-machine $ vagrant up`
- If you want to stop it: `host-machine $ vagrant halt`
- If you want to pause it: `host-machine $ vagrant suspend`
- If you want to blow it away and start over: `host-machine $ vagrant destroy`
- If you want to reboot the machine: `host-machine $ vagrant reload`
_Reload is useful if you change the Vagrantfile configuration and want
to apply those changes._

### Building a custom virtual machine

Step-by-step instructions for building your own base virtual machine
starting with a blank Ubuntu Vagrant box are in
[BUILDING.md](BUILDING.md).
