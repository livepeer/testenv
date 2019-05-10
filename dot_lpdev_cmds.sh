#!/bin/bash

##
# The app formerly known as "testenv-cli"
# Purpose: Set up local Livepeer dev and testing environment.

##
srcDir=${LPSRC:-$HOME/src}
binDir=${LPBIN:-livepeer}
nodeBaseDataDir=$HOME/.lpdata

gethDir=${LPETH:-$HOME/.ethereum}
gethIPC=$gethDir/geth.ipc
gethPid=0
gethRunning=false
gethMiningAccount=
accountAddress=

protocolBuilt=false
protocolBranch="repo not found"
controllerAddress=

broadcasterCliPort=7935
broadcasterRtmpAddr=0.0.0.0:1935
broadcasterHttpAddr=0.0.0.0:8935
broadcasterCliAddr=0.0.0.0:$broadcasterCliPort
broadcasterPid=0
broadcasterRunning=false
broadcasterGeth=

transcoderCliPort=7936
transcoderServiceAddr=127.0.0.1:8936
transcoderHttpAddr=0.0.0.0:8936
transcoderCliAddr=0.0.0.0:$transcoderCliPort
transcoderPid=0
transcoderRunning=false
transcoderGeth=

verifierPid=0
verifierRunning=false
verifierGeth=

verifierIPFSPid=0
verifierIPFSRunning=false

##
#
# TODO: create separate commands
# $ lpdev geth [ init run reset ]
# $ lpdev protocol [ init deploy reset ]
# $ lpdev node [ broadcaster transcoder reset ]
# $ lpdev [ status wizard reset ]
#
##

##
# Display the status of the current environment
##

function __lpdev_status {
  echo "== Current Status ==
  "

  ##
  # Is geth set up and running?
  ##
  __lpdev_geth_refresh_status

  echo "Geth miner is running: $gethRunning ($gethPid)"
  if [ $gethRunning ]
  then
    gethAccounts=($(geth account list | cut -d' ' -f3 | tr -cd '[:alnum:]\n'))
    echo "Geth accounts:"
    for i in ${!gethAccounts[@]}
    do
      accountAddress=${gethAccounts[$i]}
      if [ "${accountAddress}" = "${gethMiningAccount}" ]
      then
        accountAddress="$accountAddress (miner)"
      fi
      echo "  $accountAddress"
    done
  fi

  echo ""

  ##
  # Is the protocol compiled and deployed?
  ##
  __lpdev_protocol_refresh_status

  echo "Protocol is built: $protocolBuilt (current branch: $protocolBranch)"

  if [ $controllerAddress ]
  then
    echo "Protocol deployed to: $controllerAddress"
  fi

  echo ""

  ##
  # Are nodes running?
  ##
  __lpdev_node_refresh_status

  echo "Broadcaster node is running: $broadcasterRunning ($broadcasterPid)"
  echo "Transcoder node is running: $transcoderRunning ($transcoderPid)"
  echo "Verifier is running: $verifierRunning ($verifierPid)"
  echo "Verifier IPFS node is running: $verifierIPFSRunning ($verifierIPFSPid)"

  echo "
--
  "

}

function __lpdev_reset {

  echo "This will reset the dev environment"
  read -p "Are you sure you want to continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    return 1
  fi

  __lpdev_geth_reset
  __lpdev_protocol_reset
  __lpdev_node_reset
  echo "Local dev environment has been reset"

}

##
#
# Geth commands: init run reset
#
##

function __lpdev_geth_refresh_status {

  gethPid=$(pgrep -f "geth.*-mine")

  if [ -z "${gethMiningAccount}" ]
  then
    gethMiningAccount=$(cat $gethDir/lpMiningAccount 2>/dev/null)
  fi

  if [ -n "${gethPid}" ] && [ -n "${gethMiningAccount}" ]
  then
    gethRunning=true
  else
    gethRunning=false
  fi

}

function __lpdev_geth_reset {

  pkill -9 geth
  echo "Removing $gethDir and ~/.ethash"
  rm -rf $gethDir ~/.ethash
  unset gethPid
  unset gethMiningAccount
  gethRunning=false

}

function __lpdev_geth_init {

  __lpdev_geth_refresh_status

  if [ -n "${gethMiningAccount}" ]
  then
    echo "Geth mining account exists"
    return 1
  else
    echo "Creating miner account"
    gethMiningAccount=$(geth account new --password <(echo "") | cut -d' ' -f2 | tr -cd '[:alnum:]')
    echo $gethMiningAccount > $gethDir/lpMiningAccount
    echo "Created mining account $gethMiningAccount"
  fi

  if [ ! -d $nodeBaseDataDir ]
  then
    mkdir -p $nodeBaseDataDir
  fi

  if [ -d $gethDir/geth/chaindata ]
  then
    echo "Geth genesis was initialized"
    return 1
  fi

  echo "Setting up Geth data at ~/.ethereum"
  geth init <( cat << EOF
  {
    "config": {
      "chainId": 54321,
      "homesteadBlock": 1,
      "eip150Block": 2,
      "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "eip155Block": 3,
      "eip158Block": 3,
      "byzantiumBlock": 4,
      "clique": {
        "period": 1,
        "epoch": 30000
      }
    },
    "nonce": "0x0",
    "timestamp": "0x59bc2eff",
    "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000${gethMiningAccount}0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "gasLimit": "0x7A1200",
    "difficulty": "0x1",
    "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "coinbase": "0x0000000000000000000000000000000000000000",
    "alloc": {
      "$gethMiningAccount": {
        "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
      }
    },
    "number": "0x0",
    "gasUsed": "0x0",
    "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
  }
EOF
)

  if [ $? -ne 0 ]
  then
    echo "Could not initialize Geth"
  fi

}

function __lpdev_geth_run {

  __lpdev_geth_refresh_status

  if $gethRunning
  then
    echo "Geth is running, please kill it ($gethPid) or reset the environment if you'd like a fresh start."
    return 1
  fi

  echo "Running Geth miner with the following command:
  geth -networkid 54321 \\
       -rpc -ws \\
       -rpcaddr "0.0.0.0" -wsaddr "0.0.0.0" \\
       -rpccorsdomain "*" -wsorigins "*" \\
       -rpcapi 'personal,account,eth,web3,net' \\
       -wsapi 'personal,account,eth,web3,net' \\
       -targetgaslimit 8000000 \\
       -unlock $gethMiningAccount \\
       --password <(echo \"\") \\
       -mine"

  nohup geth -networkid 54321 -rpc -ws \
      -rpcaddr "0.0.0.0" -wsaddr "0.0.0.0" \
      -rpccorsdomain "*" -wsorigins "*" \
      -rpcapi 'personal,account,eth,web3,net' \
      -wsapi 'personal,account,eth,web3,net' \
      -targetgaslimit 8000000 -unlock $gethMiningAccount --password <(echo "") -mine &>>$nodeBaseDataDir/geth.log &

  if [ $? -ne 0 ]
  then
    echo "Could not start Geth"
  else
    echo "Geth started successfully"
    disown
  fi

}

function __lpdev_protocol_refresh_status {

  if [ -d $srcDir/protocol/build ]
  then
    protocolBuilt=true
  fi

  if [ -d $srcDir/protocol ]
  then
    protocolBranch=$(cd $srcDir/protocol && git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
    controllerAddress=$(cd $srcDir/protocol && truffle networks | awk '/54321/{f=1;next} /TokenPools/{f=0} f' | grep Controller | cut -d':' -f2 | tr -cd '[:alnum:]')
  fi

}

function __lpdev_protocol_reset {

  if [ -d $srcDir/protocol/build ]
  then
    rm -rf $srcDir/protocol/build
  fi

  protocolBuilt=false
  protocolBranch="repo not found"
  unset controllerAddress

}

function __lpdev_protocol_init {

  if [ -d $srcDir/protocol ]
  then
    echo "Protocol src directory exists.  Trying to pull the latest version."
    git pull
  else
    echo "Cloning github.com/livepeer/protocol into src directory"
    OPWD=$PWD
    cd $srcDir
    git clone -b pm "https://github.com/livepeer/protocol.git"
    cd $OPWD
  fi

  if [ ! -d $HOME/.protocol_node_modules ]
  then
    mkdir $HOME/.protocol_node_modules
  fi

  if ! mountpoint -q $srcDir/protocol/node_modules
  then
    echo "Mounting local vm node_modules"
    mkdir -p $srcDir/protocol/node_modules
    bindfs -n -o nonempty $HOME/.protocol_node_modules $srcDir/protocol/node_modules
  fi

  ##
  # Set devenv specific configuration
  ##
  echo "Setting devenv specific protocol parameters"
  migrations="$HOME/src/protocol/migrations/migrations.config.js"
  sed -i 's/roundLength:.*$/roundLength: 50,/' $migrations
  sed -i 's/unlockPeriod:.*$/unlockPeriod: 50,/' $migrations

  ##
  # Install local dev truffle.js
  ##

  __lpdev_geth_refresh_status

  if [ -z "${gethMiningAccount}" ]
  then
    echo "Geth Mining Account not found"
    return 1
  fi

  if grep -q ${gethMiningAccount:-"none"} $srcDir/protocol/truffle.js
  then
    echo "Local dev version of $srcDir/protocol/truffle.js already exists"
  else
    echo "Installing local dev version of $srcDir/protocol/truffle.js"

    cat << EOF > $srcDir/protocol/truffle.js
require("babel-register")
require("babel-polyfill")

module.exports = {
    networks: {
        development: {
            host: "localhost",
            port: 8545,
            network_id: "*", // Match any network id
            gas: 8000000
        },
        lpTestNet: {
            from: "0x$gethMiningAccount",
            host: "localhost",
            port: 8545,
            network_id: 54321,
            gas: 8000000
        }
    },
    compilers: {
        solc: {
            version: "0.4.25",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                }
            }
        }
    }
};
EOF

  fi

  if grep -q ${gethMiningAccount:="none"} $srcDir/protocol/scripts/unpauseController.js
  then
    echo "Local dev version of $srcDir/protocol/scripts/unpauseController.js"
  else
    echo "Installing local dev version of $srcDir/protocol/scripts/unpauseController.js"

    cat <<EOF > $srcDir/protocol/scripts/unpauseController.js
const Controller = artifacts.require("Controller")

module.exports = async () => {
    const controller = await Controller.deployed()
    await controller.unpause()
}
EOF

  fi


  ##
  # Update npm
  ##

  listModules=($(ls $srcDir/protocol/node_modules))
  if [ -d $srcDir/protocol/node_modules ] && [ ${#listModules[@]} -gt 0 ]
  then
    echo "Npm packages already installed"
  else
    echo "Running \`npm install\`"
    OPWD=$PWD
    cd $srcDir/protocol
    npm install
    cd $OPWD
  fi
}

function __lpdev_protocol_deploy {

  __lpdev_geth_refresh_status

  if ! $gethRunning
  then
    echo "Geth is not running, please start it before deploying protocol"
    return 1
  fi

  __lpdev_protocol_refresh_status

  if $protocolBuilt && [ -n "${controllerAddress}" ]
  then
    echo "Protocol was previously deployed ($controllerAddress)"
    read -p "Would you like to recompile and redeploy? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
      return 1
    fi
    redeployed=true
  fi

  OPWD=$PWD
  cd $srcDir/protocol
  migrateCmd="npm run migrate -- --reset --network=lpTestNet"
  echo "Running $migrateCmd"
  eval $migrateCmd
  unpauseCmd="./node_modules/.bin/truffle exec scripts/unpauseController.js"
  echo "Running $unpauseCmd"
  eval $unpauseCmd
  cd $OPWD

  if $redeployed
  then
    echo "Don't forget to restart any nodes that may be using the previous controllerAddr!"
  fi
}

function __lpdev_node_refresh_status {

  broadcasterPid=$(pgrep -f "livepeer.*$broadcasterCliAddr")
  if [ -n "${broadcasterPid}" ]
  then
    broadcasterRunning=true
  else
    broadcasterRunning=false
  fi

  transcoderPid=$(pgrep -f "livepeer.*$transcoderCliAddr")
  if [ -n "${transcoderPid}" ]
  then
    transcoderRunning=true
  else
    transcoderRunning=false
  fi

  verifierPid=$(pgrep -f "nohup node index")
  if [ -n "${verifierPid}" ]
  then
    verifierRunning=true
  else
    verifierRunning=false
  fi

  verifierIPFSPid=$(pgrep -f "ipfs daemon")
  if [ -n "${verifierIPFSPid}" ]
  then
    verifierIPFSRunning=true
  else
    verifierIPFSRunning=false
  fi
}

function __lpdev_node_reset {

  pkill -9 livepeer

  if [ -n "${verifierPid}" ]
  then
    kill -9 $verifierPid
  fi

  if [ -n "${verifierIPFSPid}" ]
  then
    kill -9 $verifierIPFSPid
  fi

  unset broadcasterPid
  broadcasterRunning=false
  unset broadcasterGeth
  rm -rf $nodeBaseDataDir/broadcaster-*

  unset transcoderPid
  transcoderRunning=false
  unset transcoderGeth
  rm -rf $nodeBaseDataDir/transcoder-*

  unset verifierPid
  verifierRunning=false
  unset verifierGeth

  unset verifierIPFSPid
  verifierIPFSRunning=false
}

function __lpdev_node_update {
  if [ -d $GOPATH/src/github.com/livepeer/go-livepeer ]
  then
    echo "go-livepeer src directory exists. Installing using local version"
    OPWD=$PWD
    cd $GOPATH/src/github.com/livepeer/go-livepeer
    go install ./cmd/...
    cd $OPWD
  else
    goGetCmd="go get github.com/livepeer/go-livepeer/cmd/..."
    echo "$goGetCmd: Downloading and installing go-livepeer packages"
    eval $goGetCmd
  fi

  echo "Don't forget to restart any running nodes to use the latest release"
}

function __lpdev_node_broadcaster {

  __lpdev_node_refresh_status

  if $broadcasterRunning
  then
    echo "Broadcaster running ($broadcasterPid)"
  fi

  __lpdev_geth_refresh_status
  __lpdev_protocol_refresh_status

  if ! $gethRunning || ! $protocolBuilt || [ -z ${controllerAddress} ]
  then
    echo "Geth must be running & protocol must be deployed to run a node"
    return 1
  fi

  ##
  # Attempt to reuse broadcaster data
  ##
  broadcasterExists=false
  broadcasterPath=$(ls -dt $nodeBaseDataDir/broadcaster-* | head -1)
  if  [ -d "${broadcasterPath}" ]
  then
    echo "Found exisitng broadcaster working dir $broadcasterPath"
    broadcasterExists=true
  fi


  if $broadcasterExists
  then
    broadcasterGeth=$(jq -r '.["address"]' < $broadcasterPath/keystore/*)
  else
    echo "Creating broadcaster account"
    broadcasterGeth=$(geth account new --password <(echo "pass") | cut -d' ' -f2 | tr -cd '[:alnum:]')
    echo "Created $broadcasterGeth"
  fi

  if [ -z $broadcasterGeth ]
  then
    echo "Couldn't find the broadcast node's Account address"
    return 1
  fi

  echo "Transferring funds to $broadcasterGeth"
  transferEth="geth attach ipc:/home/vagrant/.ethereum/geth.ipc --exec 'eth.sendTransaction({from: \"$gethMiningAccount\", to: \"$broadcasterGeth\", value: web3.toWei(1000000, \"ether\")})'"
  echo "Running $transferEth"
  eval $transferEth

  nodeDataDir=$nodeBaseDataDir/broadcaster-${broadcasterGeth:0:10}
  if [ ! -d $nodeDataDir ]
  then
    mkdir -p $nodeDataDir/devenv/keystore
    ethKeystorePath=$(ls $gethDir/keystore/*$broadcasterGeth)
    mv $ethKeystorePath $nodeDataDir/devenv/keystore
  fi

  echo "Sleeping for 3 secs"
  sleep 3s

  if ! $broadcasterRunning && [ -n $broadcasterGeth ]
  then
    echo "Running LivePeer broadcast node with the following command:
      $binDir -controllerAddr $controllerAddress \\
              -datadir $nodeDataDir \\
              -ethAcctAddr $broadcasterGeth \\
              -ethIpcPath $gethIPC \\
              -devenv=true \\
              -ethPassword \"pass\" \\
              -monitor=false \\
              -rtmpAddr $broadcasterRtmpAddr \\
              -httpAddr $broadcasterHttpAddr \\
              -cliAddr $broadcasterCliAddr "

    nohup $binDir -controllerAddr $controllerAddress -datadir $nodeDataDir \
      -ethAcctAddr $broadcasterGeth -ethIpcPath $gethIPC -devenv=true -ethPassword "pass" \
      -monitor=false -rtmpAddr $broadcasterRtmpAddr -httpAddr $broadcasterHttpAddr \
      -cliAddr $broadcasterCliAddr &>> $nodeDataDir/devenv/broadcaster.log &

    if [ $? -ne 0 ]
    then
      echo "Could not start LivePeer broadcast node"
      return 1
    else
      echo "LivePeer broadcast node started successfully"
      disown
      broadcasterRunning=true
    fi
  fi

  # Wait for the node's webserver to start
  echo -n "Attempting to connect to the LivePeer broadcast node webserver"
  attempts=15
  while ! nc -z localhost $broadcasterCliPort
  do
    if [ $attempts -eq 0 ]
    then
      echo "Giving up."
      return 1
    fi
    echo -n "."
    sleep 1
    attempts=$((attempts - 1))
  done

  echo ""

  echo "Sleeping for 3 secs"
  sleep 3s
}

function __lpdev_node_transcoder {

  __lpdev_node_refresh_status

  if $transcoderRunning
  then
    echo "Transcoder running ($transcoderPid)"
  fi

  __lpdev_geth_refresh_status
  __lpdev_protocol_refresh_status

  if ! $gethRunning || ! $protocolBuilt || [ -z ${controllerAddress} ]
  then
    echo "Geth must be running & protocol must be deployed to run a node"
    return 1
  fi

  ##
  # Attempt to reuse transcoder data
  ##
  transcoderExists=false
  transcoderPath=$(ls -dt $nodeBaseDataDir/transcoder-* | head -1)
  if  [ -d "${transcoderPath}" ]
  then
    echo "Found exisitng transcoder working dir $transcoderPath"
    transcoderExists=true
  fi

  if $transcoderExists
  then
    transcoderGeth=$(jq -r '.["address"]' < $transcoderPath/keystore/*)
  else
    echo "Creating transcoder account"
    transcoderGeth=$(geth account new --password <(echo "pass") | cut -d' ' -f2 | tr -cd '[:alnum:]')
    echo "Created $transcoderGeth"
  fi

  if [ -z $transcoderGeth ]
  then
    echo "Couldn't find the transcoder node's Account address"
    return 1
  fi

  echo "Transferring funds to $transcoderGeth"
  transferEth="geth attach ipc:/home/vagrant/.ethereum/geth.ipc --exec 'eth.sendTransaction({from: \"$gethMiningAccount\", to: \"$transcoderGeth\", value: web3.toWei(1000000, \"ether\")})'"
  echo "Running $transferEth"
  eval $transferEth

  nodeDataDir=$nodeBaseDataDir/transcoder-${transcoderGeth:0:10}
  if [ ! -d $nodeDataDir ]
  then
    mkdir -p $nodeDataDir/devenv/keystore
    ethKeystorePath=$(ls $gethDir/keystore/*$transcoderGeth)
    mv $ethKeystorePath $nodeDataDir/devenv/keystore
  fi
  transIPFSPath=$HOME/.transcoder-ipfs-${transcoderGeth:0:10}
  if [ ! -d $transIPFSPath ]
  then
    mkdir -p $transIPFSPath
  fi

  echo "Sleeping for 3 secs"
  sleep 3s

  if ! $transcoderRunning && [ -n $transcoderGeth ]
  then
    echo "Running LivePeer transcode node with the following command:
      $binDir -controllerAddr $controllerAddress \\
              -datadir $nodeDataDir \\
              -ethAcctAddr $transcoderGeth \\
              -ethIpcPath $gethIPC \\
              -ethPassword \"pass\" \\
              -devenv=true \\
              -monitor=false \\
              -initializeRound=true \\
              -serviceAddr $transcoderServiceAddr \\
              -httpAddr $transcoderHttpAddr \\
              -cliAddr $transcoderCliAddr \\
              -ipfsPath $transIPFSPath \\
              -transcoder"

    nohup $binDir -controllerAddr $controllerAddress -datadir $nodeDataDir \
      -ethAcctAddr $transcoderGeth -ethIpcPath $gethIPC -ethPassword "pass" \
      -devenv=true -monitor=false -initializeRound=true \
      -serviceAddr $transcoderServiceAddr -httpAddr $transcoderHttpAddr \
      -cliAddr $transcoderCliAddr -ipfsPath $transIPFSPath -transcoder &>> $nodeDataDir/devenv/transcoder.log &

    if [ $? -ne 0 ]
    then
      echo "Could not start LivePeer transcoder node"
      return 1
    else
      echo "LivePeer transcoder node started successfully"
      disown
      transcoderRunning=true
    fi
  fi

  # Wait for the node's webserver to start
  echo -n "Attempting to connect to the LivePeer transcoder node webserver"
  attempts=15
  while ! nc -z localhost $transcoderCliPort
  do
    if [ $attempts -eq 0 ]
    then
      echo "Giving up."
      return 1
    fi
    echo -n "."
    sleep 1
    attempts=$((attempts - 1))
  done

  echo ""

  echo "Sleeping for 3 secs"
  sleep 3s

  echo "Requesting test tokens"
  curl -X "POST" http://localhost:$transcoderCliPort/requestTokens

  echo "Initializing current round"
  curl -X "POST" http://localhost:$transcoderCliPort/initializeRound

  echo "Activating transcoder"
  curl -d "blockRewardCut=10&feeShare=5&pricePerSegment=1&amount=500" --data-urlencode "serviceURI=https://$transcoderServiceAddr" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -X "POST" http://localhost:$transcoderCliPort/activateOrchestrator\

}

function __lpdev_verifier_init {
  if [ -d $srcDir/verification-computation-solver ]
  then
    echo "Verifier src directory exists.  Trying to pull the latest version."
    git pull
  else
    echo "Cloning github.com/livepeer/verification-computation-solver into src directory"
    OPWD=$PWD
    cd $srcDir
    git clone "https://github.com/livepeer/verification-computation-solver.git"
    cd $OPWD
  fi

  ##
  # Update npm
  ##

  listModules=($(ls $srcDir/verification-computation-solver/node_modules))
  if [ -d $srcDir/verification-computation-solver/node_modules ] && [ ${#listModules[@]} -gt 0 ]
  then
    echo "Npm packages already installed"
  else
    echo "Running \`npm install\`"
    OPWD=$PWD
    cd $srcDir/verification-computation-solver
    npm install
    cd $OPWD
  fi
}

function __lpdev_verifier {

  __lpdev_node_refresh_status

  if $verifierIPFSRunning
  then
     echo "Verifier IPFS node is already running at ($verifierIPFSPid)"
  else
    __lpdev_ipfs_init
  fi

  __lpdev_node_refresh_status

  if $verifierRunning
  then
    echo "Verifier is already running at ($verifierPid)"
  else
    __lpdev_geth_refresh_status
    __lpdev_protocol_refresh_status

    if ! $gethRunning || ! $verifierIPFSRunning || ! $protocolBuilt || [ -z ${controllerAddress} ]
    then
      echo "Geth must be running, IPFS node must be running & protocol must be deployed to run a verifier node"
      return 1
    fi

    __lpdev_verifier_init

    echo "Making verifier address"
    verifierGeth=$(geth account new --password <(echo "pass") | cut -d' ' -f2 | tr -cd '[:alnum:]')
    echo "Created $verifierGeth"

    echo "Transferring funds to $verifierGeth"
    transferEth="geth attach ipc:/home/vagrant/.ethereum/geth.ipc --exec 'eth.sendTransaction({from: \"$gethMiningAccount\", to: \"$verifierGeth\", value: web3.toWei(1000000, \"ether\")})'"
    echo "Running $transferEth"
    eval $transferEth

    echo "Whitelisting solver $verifierGeth"
    OPWD=$PWD
    cd $srcDir/protocol
    addSolver="truffle exec scripts/addSolver.js 0x$verifierGeth"
    echo "Running $addSolver"
    eval $addSolver

    solverCMD="sudo nohup node index -a 0x$verifierGeth -c $controllerAddress -p pass &>> ./verification-solver.log &"
    echo "Starting Livepeer verifier with:"
    echo $solverCMD
    cd $srcDir/verification-computation-solver
    sudo nohup node index -a 0x$verifierGeth -c $controllerAddress -p pass &>> ~/verification-solver.log &
    cd $OPWD
  fi
}

function __lpdev_ipfs_init {
  export IPFS_PATH=$HOME/.verifierIpfs

  echo "Checking to start IPFS"
  if [ ! -d $IPFS_PATH ]
  then
    echo "Initializing ipfs"
    ipfs init
  fi

  echo "Starting IPFS daemon"
  nohup ipfs daemon &>> ~/verification-solver-ipfs.log &
  # Make sure daemon has started
  sleep 10

  echo "IPFS init finished"
}

function __lpdev_wizard {

  echo "
+----------------------------------------------------+
| Welcome to the Livepeer local dev environment tool |
|                                                    |
+----------------------------------------------------+
"
  __lpdev_status

  echo "What would you like to do?"

  wizardOptions=(
  "Display status"
  "Set up & start Geth local network"
  "Deploy/overwrite protocol contracts"
  #"Set up IPFS"
  "Start & set up broadcaster node"
  "Start & set up transcoder node"
  #"Deposit tokens to node"
  "Start & set up verifier"
  "Update livepeer and cli"
  "Install FFmpeg"
  "Rebuild FFmpeg"
  "Destroy current environment"
  "Exit"
  )

  select opt in "${wizardOptions[@]}"
  do
    case $opt in
      "Display status")
        __lpdev_status
        ;;
      "Set up & start Geth local network")
        __lpdev_geth_init
        __lpdev_geth_run
        ;;
      "Deploy/overwrite protocol contracts")
        __lpdev_protocol_init
        __lpdev_protocol_deploy
        ;;
      "Set up IPFS")
        echo "Coming soon";;
      "Start & set up broadcaster node")
        __lpdev_node_broadcaster
        ;;
      "Start & set up transcoder node")
        __lpdev_node_transcoder
        ;;
      "Start & set up verifier")
        __lpdev_verifier
        ;;
      "Deposit tokens to node")
        echo "Coming soon"
        ;;
      "Update livepeer and cli")
        __lpdev_node_update
        ;;
      "Install FFmpeg")
        ~/.install_src_deps.sh
        ;;
      "Rebuild FFmpeg")
        ~/.build_src_deps.sh
        ;;
      "Destroy current environment")
        __lpdev_reset
        ;;
      "Exit")
        return 0;;
    esac
  done
}

alias lpdev=__lpdev_wizard
