// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/DappLinkVRF.sol";
import "../src/DappLinkVRFFactory.sol";

contract DappLinkVRFDepolyScript is Script {
    function run() external {
        vm.startBroadcast();
        DappLinkVRF dappLinkVRF = new DappLinkVRF();
        console.log(
            "dapplink base contract deployed at:",
            address(dappLinkVRF)
        );

        DappLinkVRFFactory dappLinkVRFFactory = new DappLinkVRFFactory();
        console.log(
            "DappLink Proxy Factory contract deployed at:",
            address(dappLinkVRFFactory)
        );

        address proxyDappLink = dappLinkVRFFactory.createProxy(address(dappLinkVRF), msg.sender);
         console.log("DappLink Proxy contract deployed at:", proxyDappLink);
        vm.stopBroadcast();
    }
}
