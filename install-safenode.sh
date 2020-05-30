#!/bin/bash

### Change to home dir (just in case)
cd ~

### Prereq
echo "Setting up prerequisites and updating the server..."
sudo apt-get update -y
sudo apt-get install --no-install-recommends unzip curl lsof -y

### Setup Vars
GENPASS="$(dd if=/dev/urandom bs=33 count=1 2>/dev/null | base64)"
confFile=~/.safecoin/safecoin.conf
HIGHESTBLOCK=$(curl -sSL https://explorer.safecoin.org/api/blocks/\?limit=1 | grep -o '"height":[0-9]*' | cut -c10-)
BINARYDL="https://github.com/Fair-Exchange/safewallet/releases/download/v0.2.9/linux-binaries-safecoinwallet-v0.2.9.tar.gz"
BOOTSTRAP="https://safepay.safecoin.org/blockchain_txindex.zip"

### Font Colors
BLACK='\e[30m'
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
PINK='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
NC='\033[0m'

### Welcome
clear
echo -e "${WHITE}============================================"
echo -e "SafeNode Setup Tool ${PINK}v0.16.9${NC}"
echo -e "${WHITE}Special thanks to:${NC}"
echo -e "${CYAN}@Team Safe"
echo -e "@Safers"
echo -e "Miodrag"
echo -e "Oleksandr"
echo -e "Eternity"
echo -e "3DA4C300"
echo -e "Potato${NC}"
echo -e "${WHITE}============================================${NC}"

read -p "Press any key to begin..."

### Check user
if [ "$EUID" -eq 0 ]; then
    clear
    echo -e "${RED}Warning:${NC} You should not run this as root! Create a new user with sudo permissions!\nThis can be done with (replace username with an actual username such as node):\nadduser username\nusermod -aG sudo username\nsu username\ncd ~\n\nYou will be in a new home directory. Make sure you redownload the script or move it from your /root directory!"
    exit 1
fi

function ckLen {
    [ "${#1}" == 66 ] || (echo "Double check you have entered the correct SafeKey in full!" && exit 1)
}

function safeKeyConf {
    clear
    echo -e "Is \"${CYAN}$1${NC}\" the correct SafeKey you would like to use for this installation?"
    read -p "Y/n: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]*$ ]]; then
        clear
        echo "Please re-run the script with the correct SafeKey!"
        exit
    fi

    ckLen $1

}

starting_port=8771
ending_port=8871
function check_port {
    for NEXTPORT in $(seq $starting_port $ending_port); do
        if ! sudo lsof -Pi :$NEXTPORT -sTCP:LISTEN -t >/dev/null; then
            echo "$NEXTPORT not in use. Using it for rpcport"
            port_to_use=$NEXTPORT
            return $NEXTPORT
        fi
    done
    echo "No port to use"
    exit 1
}

### Check SafeKey
if [ -z "$1" ]; then
    # No SafeKey entered, ask for one
    clear
    read -p "Enter your SafeKey: " safeKey
    safeKeyConf $safeKey
else
    # SafeKey entered
    clear
    safeKey=$1
    safeKeyConf $safeKey
fi

### Kill any existing processes
echo "Stopping any existing SafeNode services..."
sudo systemctl stop safecoinnode-$USER
killall -9 safecoind
### Stop old service file >= 0.14.1
sudo systemctl stop safecoinnode &>/dev/null

### Backup wallet.dat
if [ -f .safecoin/wallet.dat ]; then
    echo "Backing up wallet.dat"
    if [ ! -d safenode-backup ]; then
        mkdir safenode-backup
    fi
    cp ~/.safecoin/wallet.dat ~/safenode-backup/wallet$(date "+%Y.%m.%d-%H.%M.%S").dat
fi

### Fetch Params
echo "Fetching Zcash-params..."
curl -sSL https://raw.githubusercontent.com/Fair-Exchange/safecoin/master/zcutil/fetch-params.sh | bash

### Setup Swap
echo -e "Adding swap if needed..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

### Check if old binaries exist
clear
if [ -f safecoind ]; then
    echo -e "Found old binaries... Deleting them..."
    rm safecoind
    rm safecoin-cli
fi

### Prompt user to build or download
echo "Would you prefer to build the daemon from source or download an existing daemon binary?"
echo "1 - Build from source"
echo "2 - Download binary"
read -p "Choose: " downloadOption

### Compile or Download based on user selection
if [ "$downloadOption" == "1" ]; then
    ### Build Daemon
    echo "Installing building dependencies..."
    sudo apt-get install -y --no-install-recommends build-essential pkg-config m4 autoconf libtool automake
    echo "Begin compiling of daemon..."
    cd ~
    curl -sSL https://github.com/Fair-Exchange/safecoin/archive/master.tar.gz | tar xz
    cd safecoin-master
    ./zcutil/build.sh -j$(nproc)
    cd ~
    cp safecoin-master/src/safecoind safecoin-master/src/safecoin-cli .
    chmod +x safecoind safecoin-cli
    strip -s safecoin*
else
    echo "Installing dependencies..."
    sudo apt-get install -y --no-install-recommends libgomp1
    ### Download Daemon
    echo "Grabbing the latest daemon..."
    curl -L $BINARYDL -o ~/binary.tar.gz
    tar xvzf binary.tar.gz
    rm ~/binary.tar.gz
    find . -type f \( -name "safecoind" -o -name "safecoin-cli" \) -exec mv '{}' ~/ \;
    chmod +x safecoind safecoin-cli
fi

### Initial .safecoin/
if [ ! -d ~/.safecoin ]; then
    echo "Created .safecoin directory..."
    mkdir .safecoin
fi

### Download bootstrap
if [ ! -d ~/.safecoin/blocks ]; then
    echo -e "Grabbing the latest bootstrap (to speed up syncing)..."
    curl -L $BOOTSTRAP -o ~/blockchain_txindex.zip
    unzip -o ~/blockchain_txindex.zip -d ~/.safecoin
    rm ~/blockchain_txindex.zip
fi

### Check if safecoin.conf exists and prompt user about overwriting it
if [ -f "$confFile" ]; then
    clear
    echo "A safecoin.conf already exists. Do you want to overwrite it?"
    read -p "Y/n: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]*$ ]]; then
        rm -fv $confFile
    fi
fi

### Final conf setup
if [ ! -f $confFile ]; then
    ### Grab current height
    HIGHESTBLOCK=$(curl -sSL https://explorer.safecoin.org/api/blocks/\?limit=1 | grep -o '"height":[0-9]*' | cut -c10-)
    if [ -z "$HIGHESTBLOCK" ]; then
        clear
        echo "Unable to fetch current block height from explorer. Please enter it manually. You can obtain it from https://explorer.safecoin.org or https://explorer.deepsky.space/"
        read -p "Current Height: " HIGHESTBLOCK
    fi

    ### Checking ports
    check_port

    ### Write to safecoin.conf
    rpcuser=$(dd if=/dev/urandom bs=33 count=1 2>/dev/null | md5sum | cut -c1-33)
    echo "rpcuser="$rpcuser >> $confFile
    rpcpassword=$(dd if=/dev/urandom bs=33 count=1 2>/dev/null | md5sum | cut -c1-33)
    echo "rpcpassword="$rpcpassword >> $confFile
    echo "addnode=explorer.safecoin.org" >> $confFile
    echo "addnode=explorer.deepsky.space" >> $confFile
    echo "addnode=dnsseed.local.support" >> $confFile
    echo "addnode=dnsseed.fair.exchange" >> $confFile
    echo "rpcport=$NEXTPORT" >> $confFile
    if [ "$NEXTPORT" != 8771 ]; then
        echo "listen=0" >> $confFile
    else
        echo "listen=1" >> $confFile
    fi
    echo "port=8770" >> $confFile
    echo "server=1" >> $confFile
    echo "txindex=1" >> $confFile
    echo "timestampindex=1" >> $confFile
    echo "addressindex=1" >> $confFile
    echo "spentindex=1" >> $confFile
    echo "daemon=1" >> $confFile
    echo "parentkey=0333b9796526ef8de88712a649d618689a1de1ed1adf9fb5ec415f31e560b1f9a3" >> $confFile
    echo "safekey=$safeKey" >> $confFile
    echo "safepass=$GENPASS" >> $confFile
    echo "safeheight=$HIGHESTBLOCK" >> $confFile
else
    clear
    echo "safecoin.conf exists. Skipping..."
fi

### Choose to setup service or not
clear
echo "Would you like to setup a service to automatically start/restart safecoind on reboots/failures?"
read -p "Y/n: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]*$ ]]; then
        ### Setup Service
        echo "Creating service file..."
        createdService="1"

        ### Remove old service file >= 0.14.1
        if [ -f /lib/systemd/system/safecoinnode.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode.service &>/dev/null
            sudo rm /lib/systemd/system/safecoinnode.service &>/dev/null
        fi

        ### Remove old service file >= v0.16.2
        if [ -f /lib/systemd/system/safecoinnode-$USER.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode-$USER.service &>/dev/null
            sudo rm /lib/systemd/system/safecoinnode-$USER.service &>/dev/null
        fi

        ### Remove old service file
        if [ -f /etc/systemd/system/safecoinnode-$USER.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode-$USER.service
            sudo rm /etc/systemd/system/safecoinnode-$USER.service
        fi

        service="echo '[Unit]
Description=SafeNodes daemon
After=network-online.target
[Service]
User=$USER
Group=$USER
Type=forking
Restart=always
RestartSec=120
RemainAfterExit=true
ExecStart=$HOME/safecoind -daemon
ProtectSystem=full
[Install]
WantedBy=multi-user.target' >> /etc/systemd/system/safecoinnode-$USER.service"

        #echo $service
        sudo sh -c "$service"

        ### Fire up the engines
        sudo systemctl enable safecoinnode-$USER.service
        sudo systemctl start safecoinnode-$USER
    else
        ### Remove old service file >= 0.14.1
        if [ -f /lib/systemd/system/safecoinnode.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode.service &>/dev/null
            sudo rm /lib/systemd/system/safecoinnode.service &>/dev/null
        fi

        ### Remove old service file >= v0.16.2
        if [ -f /lib/systemd/system/safecoinnode-$USER.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode-$USER.service &>/dev/null
            sudo rm /lib/systemd/system/safecoinnode-$USER.service &>/dev/null
        fi

        ### Remove old service file
        if [ -f /etc/systemd/system/safecoinnode-$USER.service ]; then
            echo "Removing old service file..."
            sudo systemctl disable --now safecoinnode-$USER.service
            sudo rm /etc/systemd/system/safecoinnode-$USER.service
        fi

        echo -e "${WHITE}No service was created...${NC} ${CYAN}Starting daemon...${NC}"
        ~/safecoind -daemon
    fi

echo -e "${CYAN}Safecoind started...${NC} Waiting 2 minutes for startup to finish"
sleep 120
newHighestBlock=$(curl -sSL https://explorer.safecoin.org/api/blocks/\?limit=1 | grep -o '"height":[0-9]*' | cut -c10-)
currentBlock="$(~/safecoin-cli getblockcount)"

### We need to add some failed start detection here with troubleshooting steps
### error code: -28

if [ -z "$newHighestBlock" ]; then
    echo
    echo "Unable to fetch current block height from explorer. Please enter it manually. You can obtain it from https://explorer.safecoin.org or https://explorer.deepsky.space/"
    read -p "Current Height: " newHighestBlock
    newHighestBlockManual="$newHighestBlock"
fi

echo -e "Current Height is now $newHighestBlock"

while  [ "$newHighestBlock" != "$currentBlock" ]; do
    clear
    if [ -z "$newHighestBlockManual" ]; then
        newHighestBlock=$(curl -sSL https://explorer.safecoin.org/api/blocks/\?limit=1 | grep -o '"height":[0-9]*' | cut -c10-)
    else
        newHighestBlock="$newHighestBlockManual"
    fi
    currentBlock="$(~/safecoin-cli getblockcount)"
    echo -e "${WHITE}Comparing block heights to ensure server is fully synced every 10 seconds${NC}";
    echo -e "${CYAN}Highest: $newHighestBlock ${NC}";
    echo -e "${PINK}Currently at: $currentBlock ${NC}";
    echo -e "${WHITE}Checking again in 10 seconds... The install will continue once it's synced.";echo
    echo -e "Last 10 lines of the log for error checking...";
    echo -e "===============${NC}";
    tail -10 ~/.safecoin/debug.log
    echo -e "${WHITE}===============";
    echo -e "Just ensure the current block height is rising over time... ${NC}";
    sleep 10
done

clear
echo -e "${WHITE}Chain is fully synced with explorer height!${NC}"
echo
echo -e "${PINK}SafeNode${NC}${WHITE} successfully configured and launched!${NC}"
echo
echo -e "${CYAN}SafeKey:${NC} ${PINK}$safeKey${NC}"
echo -e "${CYAN}ParentKey:${NC} ${PINK}0333b9796526ef8de88712a649d618689a1de1ed1adf9fb5ec415f31e560b1f9a3${NC}"
echo -e "${CYAN}SafePass:${NC} ${PINK}$GENPASS${NC}"
echo -e "${CYAN}SafeHeight:${NC} ${PINK}$HIGHESTBLOCK${NC}"
echo
echo -e "${WHITE}##################################################${NC}"
echo

### Check balance
BALANCE=$(~/safecoin-cli z_gettotalbalance | grep -o "total[^$]*" | grep -o "[\.0-9]*")
if [[ "0.2" > $BALANCE ]]; then
    echo -e "${GREEN}Send ${CYAN}1${NC}${GREEN} SAFE to the address below. This will power the SafeNode for 1 year!${NC}"
    ### Generate address to fuel safenode
    echo -e "${PINK}"
    ~/safecoin-cli getnewaddress
    echo -e "${NC}${WHITE}"
else
    echo -e "${CYAN}Current SafeNode balance:${NC} ${PINK}$BALANCE SAFE${NC}"
fi

echo
echo -e "${WHITE}You can view your SafeNode rewards online at ${PINK}https://safenodes.org/address/$(~/safecoin-cli getnodeinfo | grep -o -e '"SAFE_address": [^,]*' | cut -c18-51)${NC}${WHITE}"
echo
echo -e "##################################################"
echo
echo -e "A message of "${PINK}Validate SafeNode${NC}" ${WHITE}will appear when your SafeNode Is activated. This will happen roughly 10 blocks after the safeheight above."
echo
echo -e "Checking the safecoind service status...${NC}"

### Check health of service
if [ ! -z "$createdService" ]; then
    sudo systemctl --no-pager status safecoinnode-$USER
    echo
    echo -e "##################################################"
    echo
    echo -e "${WHITE}Fetching ${PINK}getnodeinfo${NC}${WHITE}"
    ~/safecoin-cli getnodeinfo
    echo -e "${NC}"
else
    echo -e "${WHITE}No service was created... returning ${PINK}getnodeinfo${NC}${WHITE}"
    ~/safecoin-cli getnodeinfo
    echo -e "${NC}"
fi

if [ -d ~/safecoin ]; then
    echo "Cleaning up... Do you want to remove your safecoin build directory?"
    read -p "Y/n: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]*$ ]]; then
        rm -rf ~/safecoin
        echo "Build directory removed..."
    fi
fi
