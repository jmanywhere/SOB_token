// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SecuredOnBlockChainToken} from "../src/OnSecuredToken.sol";
import "forge-std/Script.sol";

contract DeployToken is Script {
    address dev = 0x2FB70Dd1b7677C29103BCD280cF061b81357b877;
    address mkt = 0x430732094A39c4BdA694121E4513041fAb878CaB;

    function run() public {
        vm.startBroadcast();
        SecuredOnBlockChainToken sob = new SecuredOnBlockChainToken(
            dev,
            mkt,
            dev
        );
        vm.stopBroadcast();

        console.log("SOB Token: ", address(sob));
    }
}
