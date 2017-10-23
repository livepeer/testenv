package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/golang/glog"
	"runtime"
)

func Copy(src string, dst string) {
	data, err := ioutil.ReadFile(src)
	if err != nil {
		glog.Fatalf("Error reading: %v", err)
	}

	f, _ := os.Create(dst)
	defer f.Close()
	_, err = f.Write(data)
	if err != nil {
		glog.Fatalf("Error writing: %v", err)
	}
}

func File(filename string) []byte {
	raw, err := ioutil.ReadFile(filename)
	if err != nil {
		// fmt.Println(err.Error())
		return []byte{}
	}
	return raw
}

func GetLivePeer(build bool) {


	if build{

		if _, err := os.Stat(filepath.Join(dir, "livepeer")); os.IsExist(err) {
			return
		}

		if runtime.GOOS == "linux" {
			download("https://github.com/livepeer/go-livepeer/releases/download/0.1.3/livepeer_linux", "livepeer")
		} else {
			download("https://github.com/livepeer/go-livepeer/releases/download/0.1.3/livepeer_darwin", "livepeer")
		}
		err := os.Chmod("livepeer", 0777)
		if err != nil {
			fmt.Println(err)
		}
	}else{

		if _, err := os.Stat(filepath.Join(dir, "go-livepeer")); os.IsExist(err) {
			return
		}

		cmd := exec.Command("git", "clone", "https://github.com/livepeer/go-livepeer.git")
		cmd.Start()
		if err := cmd.Wait(); err != nil {
			glog.Infof("Couldn't clone: %v", err)
			os.Exit(1)
		}
	}

}

func (w *wizard) stats() {
	wtr := tabwriter.NewWriter(os.Stdout, 0, 0, 1, ' ', tabwriter.AlignRight)

	// //Print out if seed data is set up
	// seedSetup := false
	// if _, err := os.Stat(filepath.Join(dir, "lpdata1/keys.json")); !os.IsNotExist(err) {
	// 	if _, err := os.Stat(filepath.Join(dir, "lpdata2/keys.json")); !os.IsNotExist(err) {
	// 		seedSetup = true
	// 	}
	// }
	// fmt.Fprintf(wtr, "Seed data setup: \t%v\n", seedSetup)

	//Print out if geth is set up and running
	gethSetup := false
	gethdir := filepath.Join(dir, "lpGeth")
	if _, err := os.Stat(filepath.Join(gethdir, "geth.ipc")); !os.IsNotExist(err) {
		gethSetup = true
	}
	fmt.Fprintf(wtr, "Geth setup and running: \t%v\n", gethSetup)

	//Print out controller addresses
	tc := string(File(filepath.Join(dir, "protocol/build/contracts/Controller.json")))
	if tc != "" {
		arr := strings.Split(tc, "address\": \"")
		if len(arr) > 1 && len(arr[1]) > 42 {
			w.ControllerAddr = arr[1][:42]
		}
	}
	fmt.Fprintf(wtr, "Controller: \t%v\n", w.ControllerAddr)

	//TODO: Print out if IPFS is set up and running

	//Print out if broadcaster is running
	bStatus := []string{}
	if _, err := http.Get(fmt.Sprintf("http://localhost:%v", broadcasterPort)); err == nil {
		bStatus = append(bStatus, "Running")
	} else {
		bStatus = append(bStatus, "Not Running")
	}
	if w.getDeposit(broadcasterPort) == 0 {
		bStatus = append(bStatus, "No Deposit")
	} else {
		bStatus = append(bStatus, "Has Deposit")
	}
	fmt.Fprintf(wtr, "Broadcaster Status: \t%v\n", strings.Join(bStatus, ", "))

	//Print out if transcoder is running
	tStatus := []string{}
	if _, err := http.Get(fmt.Sprintf("http://localhost:%v", transcoderPort)); err == nil {
		tStatus = append(tStatus, "Running")
	} else {
		tStatus = append(tStatus, "Not Running")
	}
	tStatus = append(tStatus, w.getTranscoderStatus(transcoderPort))
	fmt.Fprintf(wtr, "Transcoder Status: \t%v\n", strings.Join(tStatus, ", "))

	wtr.Flush()
}

// func (w *wizard) setupSeedData() {
// 	//Set up lpdata dirs
// 	// if _, err := os.Stat(filepath.Join(dir, "lpdata1")); os.IsNotExist(err) {
// 	os.Mkdir("lpdata1", 0777)
// 	Copy(filepath.Join(dir, "lpkeys1.json"), filepath.Join(dir, "lpdata1", "keys.json"))
// 	os.Mkdir("lpdata2", 0777)
// 	Copy(filepath.Join(dir, "lpkeys2.json"), filepath.Join(dir, "lpdata2", "keys.json"))
// 	// }
// }

func (w *wizard) setupAndStartGeth() {
	//Set up geth genesis, init geth data
	gethdir := filepath.Join(dir, "lpGeth")
	if _, err := os.Stat(gethdir); os.IsNotExist(err) {
		glog.Infof("Setting up geth data at %v", gethdir)
		cmd := exec.Command("geth", "-datadir", gethdir, "init", "localPOA.json")
		if err := cmd.Start(); err != nil {
			glog.Fatalf("Error: %v", err)
		}

		if err := cmd.Wait(); err != nil {
			glog.Errorf("Error: %v", err)
		}
		//Copy keys into lpGeth
		Copy(filepath.Join(dir, "keystore", "key1"), filepath.Join(dir, "lpGeth", "keystore", "key1"))
		Copy(filepath.Join(dir, "keystore", "key2"), filepath.Join(dir, "lpGeth", "keystore", "key2"))
	}

	for i := 0; ; i++ {
		if _, err := os.Stat(filepath.Join(gethdir, "geth.ipc")); os.IsNotExist(err) {
			if i == 0 {
				fmt.Printf("\nTo start Geth, run: `geth -datadir %v -networkid 54321 -rpc -rpcapi 'personal,account,eth,web3,net' -targetgaslimit 6700000 -unlock 0x94107cb2261e722f9f4908115546eeee17decada -mine console`\n", gethdir)
			}
			time.Sleep(time.Millisecond * 500)
			continue
		} else {
			break
		}
	}
}

func (w *wizard) deployProtocol() {
	//Set up protocol contract
	if _, err := os.Stat(filepath.Join(dir, "protocol/build/contracts/LivepeerToken")); os.IsExist(err) {
		glog.Infof("Already deployed protocol.  Want to refresh? (Y/n)")
		yn := w.read()
		if strings.ToLower(yn) == "n" {
			return
		}
	}

	//Clone the protocol repo
	if _, err := os.Stat(filepath.Join(dir, "protocol")); os.IsNotExist(err) {
		cmd := exec.Command("git", "clone","-b","develop", "https://github.com/livepeer/protocol.git")
		cmd.Start()
		if err := cmd.Wait(); err != nil {
			glog.Infof("Couldn't clone: %v", err)
			os.Exit(1)
		}
		fmt.Println("Done cloning protocol")


		//Copy truffle.js
		Copy(filepath.Join(dir, "truffle.js"), filepath.Join(dir, "protocol", "truffle.js"))
		Copy(filepath.Join(dir, "migrations.config.js"), filepath.Join(dir, "protocol", "migrations", "truffle.js"))
	}

	if _, err := os.Stat(filepath.Join("dir", "protocol/build")); os.IsNotExist(err) {
		fmt.Println("Running `npm install`")
		// cmd := exec.Command("cd", "protocol", "&&", "npm", "install", "&&", "truffle", "migrate", "--network", "lpTestNet")

		cmd := exec.Command("npm", "install")
		cmd.Dir = filepath.Join(dir, "protocol")
		if err := cmd.Start(); err != nil {
			glog.Errorf("err: %v", err)
		}
		if err := cmd.Wait(); err != nil {
			glog.Infof("Couldn't clone: %v", err)
			os.Exit(1)
		}

		fmt.Println("Running `truffle migrate --reset --network lpTestNet`")
		cmd = exec.Command("truffle", "migrate", "--reset", "--network", "lpTestNet")
		cmd.Dir = filepath.Join(dir, "protocol")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Start(); err != nil {
			glog.Errorf("err: %v", err)
		}
		if err := cmd.Wait(); err != nil {
			glog.Infof("Couldn't clone: %v", err)
			os.Exit(1)
		}
	}

	//TODO: Run truffle migrate --network lpTestNet
}

func (w *wizard) setupAndStartBroadcaster() {
	isBuild := false
	GetLivePeer(isBuild)

	if _, err := os.Stat(filepath.Join(dir, "lpdata1/keys.json")); os.IsNotExist(err) {
		os.Mkdir("lpdata1", 0777)
		Copy(filepath.Join(dir, "lpkeys1.json"), filepath.Join(dir, "lpdata1", "keys.json"))
	}

	for i := 0; ; i++ {
		if _, err := http.Get(fmt.Sprintf("http://localhost:%v", broadcasterPort)); err != nil {
			if i == 0 {
				fmt.Println("Start broadcaster before we can set it up")
				w.broadcasterCmd(isBuild)
			}
			time.Sleep(time.Millisecond * 500)
			continue
		} else {
			break
		}
	}

	if w.getTokenBalance(broadcasterPort) == 0 {
		glog.Infof("Requesting for test tokens")
		httpPost(fmt.Sprintf("http://localhost:%v/requestTokens", broadcasterPort))
	}

	if w.getDeposit(broadcasterPort) == 0 {
		glog.Infof("Depositing 500 tokens")
		val := url.Values{
			"amount": {"500"},
		}
		httpPostWithParams(fmt.Sprintf("http://localhost:%v/deposit", broadcasterPort), val)
	}

}

func (w *wizard) setupAndStartTranscoder() {
	isBuild := true
	GetLivePeer(isBuild)
	if _, err := os.Stat(filepath.Join(dir, "lpdata2/keys.json")); os.IsNotExist(err) {
		os.Mkdir("lpdata2", 0777)
		Copy(filepath.Join(dir, "lpkeys2.json"), filepath.Join(dir, "lpdata2", "keys.json"))
	}

	for i := 0; ; i++ {
		if _, err := http.Get(fmt.Sprintf("http://localhost:%v", transcoderPort)); err != nil {
			if i == 0 {
				fmt.Println("Start transcoder before we can set it up")
				w.transcoderCmd(isBuild)
			}
			time.Sleep(time.Millisecond * 500)
			continue
		} else {
			break
		}
	}

	if w.getTokenBalance(transcoderPort) == 0 {
		glog.Infof("Requesting for test tokens")
		httpPost(fmt.Sprintf("http://localhost:%v/requestTokens", transcoderPort))
	}

	if w.getTranscoderStatus(transcoderPort) != "Active" {
		glog.Infof("Activating transcoder")

		val := url.Values{
			"blockRewardCut":  {fmt.Sprintf("%v", 10)},
			"feeShare":        {fmt.Sprintf("%v", 5)},
			"pricePerSegment": {fmt.Sprintf("%v", 1)},
			"amount":          {fmt.Sprintf("%v", 500)},
		}

		httpPostWithParams(fmt.Sprintf("http://localhost:%v/activateTranscoder", transcoderPort), val)
	}
}

func (w *wizard) broadcasterCmd(isBuild bool) {
	if isBuild {
		cmd := fmt.Sprintf("./livepeer -bootnode -controllerAddr %v -datadir %v -ethDatadir %v -ethAccountAddr 0x94107cb2261e722f9f4908115546eeee17decada -monitor=false -rtmp %v -http %v &> lpBroadcaster.log",
			w.ControllerAddr, filepath.Join(dir, "lpdata1"), filepath.Join(dir, "lpGeth"), broadcasterPort-7000, broadcasterPort)
		fmt.Printf("\n\nCommand: %v\n\n", cmd)
	}else{
		cmd:= fmt.Sprintf("cd go-livepeer ; go run cmd/livepeer/livepeer.go -bootnode -controllerAddr %v -datadir %v -ethDatadir %v -ethAccountAddr 0x94107cb2261e722f9f4908115546eeee17decada -monitor=false -rtmp %v -http %v &> lpBroadcaster.log",
			w.ControllerAddr, filepath.Join(dir, "lpdata1"), filepath.Join(dir, "lpGeth"), broadcasterPort-7000, broadcasterPort)
			fmt.Printf("\n\nCommand: %v\n\n",cmd)
	}
}

func (w *wizard) transcoderCmd(isBuild bool) {
	if isBuild {
		cmd := fmt.Sprintf("./livepeer -controllerAddr %v -datadir %v -ethDatadir %v -ethAccountAddr 0x0ddb225031ccb58ff42866f82d907f7766899014 -monitor=false -rtmp %v -http %v -bootID 1220fd39d26e8a0ddf25693e574b821df32c45cd18fee1ee8bf329da96eb67bd2b5f -bootAddr /ip4/127.0.0.1/tcp/15000 -p 15001 -transcoder &> lpBroadcaster.log",
			w.ControllerAddr, filepath.Join(dir, "lpdata2"), filepath.Join(dir, "lpGeth"), transcoderPort-7000, transcoderPort)
		fmt.Printf("\n\nCommand: %v\n\n", cmd)
	}else{
		cmd:= fmt.Sprintf("cd go-livepeer ; go run cmd/livepeer/livepeer.go -controllerAddr %v -datadir %v -ethDatadir %v -ethAccountAddr 0x0ddb225031ccb58ff42866f82d907f7766899014 -monitor=false -rtmp %v -http %v -bootID 1220fd39d26e8a0ddf25693e574b821df32c45cd18fee1ee8bf329da96eb67bd2b5f -bootAddr /ip4/127.0.0.1/tcp/15000 -p 15001 -transcoder &> lpBroadcaster.log",
			w.ControllerAddr, filepath.Join(dir, "lpdata2"), filepath.Join(dir, "lpGeth"), transcoderPort-7000, transcoderPort)
		fmt.Printf("\n\nCommand: %v\n\n",cmd)
	}
}

func download(rawURL, fileName string) {
	file, err := os.Create(fileName)
	if err != nil {
		fmt.Println(err)
		panic(err)
	}
	defer file.Close()

	check := http.Client{
		CheckRedirect: func(r *http.Request, via []*http.Request) error {
			r.URL.Opaque = r.URL.Path
			return nil
		},
	}

	resp, err := check.Get(rawURL) // add a filter to check redirect

	if err != nil {
		fmt.Println(err)
		panic(err)
	}
	defer resp.Body.Close()
	fmt.Println(resp.Status)

	size, err := io.Copy(file, resp.Body)

	if err != nil {
		panic(err)
	}

	fmt.Printf("%s with %v bytes downloaded", fileName, size)
}

func (w *wizard) getDeposit(port int) int {
	e := httpGet(fmt.Sprintf("http://localhost:%v/broadcasterDeposit", port))
	i, _ := strconv.Atoi(e)
	return i
}

func (w *wizard) getTokenBalance(port int) int {
	b := httpGet(fmt.Sprintf("http://localhost:%v/tokenBalance", port))
	i, _ := strconv.Atoi(b)
	return i
}

func (w *wizard) getTranscoderStatus(port int) string {
	return httpGet(fmt.Sprintf("http://localhost:%v/transcoderStatus", port))
}
