// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployChatterPay_EntryPoint} from "../script/DeployChatterPay_EntryPoint.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ChatterPay} from "../src/L2/AccountAbstraction_EntryPoint/ChatterPay.sol";
import {ChatterPayWalletFactory} from "../src/L2/AccountAbstraction_EntryPoint/ChatterPayWalletFactory.sol";
import {ChatterPayBeacon} from "../src/L2/AccountAbstraction_EntryPoint/ChatterPayBeacon.sol";


// Chequear Owners
// Chequear envio de transacciones
contract ChatterPay_EntryPoint_Test is Test {

  HelperConfig helperConfig;
  ChatterPay chatterPay;
  ChatterPayBeacon beacon;
  ChatterPayWalletFactory factory;
  
  function setUp() public {
    DeployChatterPay_EntryPoint deployChatterPay = new DeployChatterPay_EntryPoint();
    (helperConfig, chatterPay, beacon, factory) = deployChatterPay.deployChatterPay();
    chatterPay = chatterPay;
    beacon = beacon;
    factory = factory;
  }

  function testSetup() public view {
    console.log("ChatterPay: %s, Beacon: %s, Factory: %s", address(chatterPay), address(beacon), address(factory));
    assertEq(address(chatterPay), address(beacon.implementation()), "ChatterPay and Beacon should have the same implementation");
  }

  function testOwners() public {
    HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
    assertEq(factory.owner(), config.account, "Owner should be the test contract");
  }
}