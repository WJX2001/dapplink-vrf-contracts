// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/DappLinkVRF.sol";
import "../src/DappLinkVRFFactory.sol";


contract DappLinkVRFTest is Test {
    DappLinkVRF public dappLinkVRF;
    DappLinkVRFFactory public dappLinkVRFFactory;
    DappLinkVRF public proxyDappLinkVRF;

    function setUp() public {
        dappLinkVRF = new DappLinkVRF();
        dappLinkVRFFactory = new DappLinkVRFFactory();
        address proxyDappLink = dappLinkVRFFactory.createProxy(address(dappLinkVRF), address(this));
        proxyDappLinkVRF = DappLinkVRF(proxyDappLink);
    }

    function testSetValueThroughProxy() public {
        proxyDappLinkVRF.requestRandomWords(11111, 3);
        uint256[] memory randomWords = new uint256[](5);
        randomWords[0] = 1;
        randomWords[1] = 2;
        randomWords[2] = 3;
        randomWords[3] = 4;
        randomWords[4] = 5;
        proxyDappLinkVRF.fulfillRandomWords(11111, randomWords);
        (bool success, uint256[] memory randomList) = proxyDappLinkVRF.getRequestStatus(11111);
        console.log("================result==================");
        console.log(success);
        console.log(randomList[0]);
        console.log(randomList[4]);
        console.log("================result==================");
    }
}
