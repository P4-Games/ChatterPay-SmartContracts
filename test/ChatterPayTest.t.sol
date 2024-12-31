// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployAllContracts} from "script/DeployAllContracts.s.sol";
import {HelperConfig} from "script/utils/HelperConfig.s.sol";
import {ChatterPay} from "src/L2/ChatterPay.sol";
import {ChatterPayWalletFactory} from "src/L2/ChatterPayWalletFactory.sol";
import {ChatterPayNFT} from "src/L2/ChatterPayNFT.sol";
import {ChatterPayPaymaster} from "src/L2/ChatterPayPaymaster.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, UserOperation, IEntryPoint} from "script/utils/SendPackedUserOp.s.sol";

contract ChatterPayTest is Test {
    HelperConfig helperConfig;
    ChatterPay chatterPay;
    ChatterPayWalletFactory factory;
    ChatterPayNFT chatterPayNFT;
    ChatterPayPaymaster paymaster;
    IEntryPoint entryPoint;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;
    address deployer;
    address RANDOM_USER = makeAddr("randomUser");
    address RANDOM_APPROVER = makeAddr("RANDOM_APPROVER");
    address ANVIL_DEFAULT_USER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 ANVIL_DEFAULT_USER_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    function setUp() public {
        DeployAllContracts deployAllContracts = new DeployAllContracts();
        (
            helperConfig,
            chatterPay,
            factory,
            chatterPayNFT,
            paymaster
        ) = deployAllContracts.run();
        console.log("Contracts deployed");
        console.log("factory:", address(factory));
        usdc = ERC20Mock(helperConfig.getConfig().usdc);
        sendPackedUserOp = new SendPackedUserOp();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        deployer = config.account;
        console.log("Deployer:", deployer); // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        entryPoint = IEntryPoint(config.entryPoint);
    }

    function createProxyForUser(address user) public returns (address) {
        address proxy = factory.createProxy(user);
        assertEq(factory.getProxiesCount(), 1, "There should be 1 proxy");
        return proxy;
    }

    function getImplementationAddress(
        address proxy
    ) internal view returns (address impl) {
        bytes32 slot = 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC;
        bytes32 data = vm.load(proxy, slot);
        impl = address(uint160(uint256(data)));
    }

    function testFactoryOwner() public view {
        console.log("Factory Owner:", factory.owner());
        assertEq(
            factory.owner(),
            deployer,
            "Owner should be the burner wallet"
        );
    }

    function testProxyOwner() public {
        address proxy = createProxyForUser(RANDOM_USER);

        console.log("Proxy Address:", proxy);

        // Check if the proxy contract is deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(proxy)
        }
        require(codeSize > 0, "Proxy contract is not deployed");

        (, bytes memory owner) = proxy.call(abi.encodeWithSignature("owner()"));
        assertEq(
            abi.decode(owner, (address)),
            RANDOM_USER,
            "Proxy owner should be RANDOM_USER"
        );
    }

    function testDeployProxy() public {
        vm.startPrank(deployer);
        address proxy = factory.createProxy(RANDOM_USER);
        assertEq(
            factory.proxies(0),
            proxy,
            "Proxy should be stored in the factory"
        );
    }

    function testProxyImplementationShouldBeChatterPayImplementation() public {
        address proxy = createProxyForUser(RANDOM_USER);
        address implementation = getImplementationAddress(proxy);

        assertEq(
            implementation,
            address(chatterPay),
            "Proxy implementation should be ChatterPay"
        );
    }

    function skip_testComputeAddressMustBeEqualToCreateProxyAddress() public {
        address proxy = factory.createProxy(RANDOM_USER);
        address computedProxy = factory.computeProxyAddress(RANDOM_USER);
        assertEq(
            proxy,
            computedProxy,
            "Computed proxy address should be equal to created proxy address"
        );
    }

    function testApproveUsdcWithoutInitCode() public {
        vm.startPrank(deployer);

        address proxyAddress = createProxyForUser(ANVIL_DEFAULT_USER);

        vm.deal(deployer, 1 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));

        // Assign ETH to proxy for gas
        vm.deal(proxyAddress, 1 ether);

        // Set up destination, value and null initCode
        address dest = helperConfig.getConfig().usdc;
        uint256 value = 0;
        bytes memory initCode = hex"";

        // Encode approve function call
        bytes memory functionData = abi.encodeWithSelector(
            usdc.approve.selector,
            RANDOM_APPROVER,
            1e18
        );
        bytes memory executeCalldata = abi.encodeWithSelector(
            ChatterPay.execute.selector,
            dest,
            value,
            functionData
        );

        // Generate signed user operation
        UserOperation memory userOp = sendPackedUserOp
            .generateSignedUserOperation(
                initCode,
                executeCalldata,
                helperConfig.getConfig(),
                proxyAddress,
                ANVIL_DEFAULT_USER_KEY,
                address(paymaster)
            );
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        // Execute handleOps
        entryPoint.handleOps(ops, payable(proxyAddress));

        // Check allowance
        uint256 allowance = ERC20Mock(dest).allowance(
            proxyAddress,
            RANDOM_APPROVER
        );
        console.log("Allowance after operation:", allowance);

        // Assert expected allowance
        assertEq(
            allowance,
            1e18,
            "Proxy should have approved 1e18 USDC to RANDOM_APPROVER"
        );

        vm.stopPrank();
    }

    function testApproveUsdcWithInitCode() public {
        vm.startPrank(deployer);

        // Compute new address, send userOp with initCode to create account
        address proxyAddress = factory.computeProxyAddress(ANVIL_DEFAULT_USER);
        console.log("Computed Proxy Address:", proxyAddress);

        vm.deal(deployer, 1 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));

        // Generate initCode
        bytes memory encodedData = abi.encodeWithSelector(
            ChatterPayWalletFactory.createProxy.selector,
            ANVIL_DEFAULT_USER
        );
        bytes memory encodedFactory = abi.encodePacked(address(factory));
        bytes memory initCode = abi.encodePacked(encodedFactory, encodedData);

        // Assign ETH to proxy for gas
        vm.deal(proxyAddress, 1 ether);
        console.log("Assigned ETH to Proxy");

        // Set up destination and value
        address dest = helperConfig.getConfig().usdc;
        uint256 value = 0;

        // Encode approve function call
        bytes memory functionData = abi.encodeWithSelector(
            usdc.approve.selector,
            RANDOM_APPROVER,
            1e18
        );
        bytes memory executeCalldata = abi.encodeWithSelector(
            ChatterPay.execute.selector,
            dest,
            value,
            functionData
        );

        // Generate signed user operation
        UserOperation memory userOp = sendPackedUserOp
            .generateSignedUserOperation(
                initCode,
                executeCalldata,
                helperConfig.getConfig(),
                proxyAddress,
                ANVIL_DEFAULT_USER_KEY,
                address(paymaster)
            );
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        // Execute handleOps
        entryPoint.handleOps(ops, payable(proxyAddress));

        // Check allowance
        uint256 allowance = ERC20Mock(dest).allowance(
            proxyAddress,
            RANDOM_APPROVER
        );
        console.log("Allowance after operation:", allowance);

        // Assert expected allowance
        assertEq(
            allowance,
            1e18,
            "Proxy should have approved 1e18 USDC to RANDOM_APPROVER"
        );

        vm.stopPrank();
    }

    function testTransferUSDCWithFee() public {
        vm.startPrank(deployer);

        address proxyAddress = createProxyForUser(ANVIL_DEFAULT_USER);

        vm.deal(deployer, 1 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));

        // Assign ETH to proxy for gas
        vm.deal(proxyAddress, 1 ether);

        // Set up destination, value and null initCode
        address dest = helperConfig.getConfig().usdt;
        uint256 fee = 500000000000000000; // ERC20 contract with 18 decimals (50 cents)
        bytes memory initCode = hex"";

        // Mint USDC to Proxy
        ERC20Mock(dest).mint(proxyAddress, 1e18);

        // Encode transfer function call
        bytes memory functionData = abi.encodeWithSelector(
            usdc.transfer.selector,
            RANDOM_APPROVER,
            1e6
        );
        bytes memory executeCalldata = abi.encodeWithSelector(
            ChatterPay.executeTokenTransfer.selector,
            dest,
            fee,
            functionData
        );

        // Generate signed user operation
        UserOperation memory userOp = sendPackedUserOp
            .generateSignedUserOperation(
                initCode,
                executeCalldata,
                helperConfig.getConfig(),
                proxyAddress,
                ANVIL_DEFAULT_USER_KEY,
                address(paymaster)
            );
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        // Execute handleOps
        entryPoint.handleOps(ops, payable(proxyAddress));

        // Check balance
        uint256 balance = ERC20Mock(dest).balanceOf(RANDOM_APPROVER);
        console.log("Balance after operation:", balance);

        // Assert expected allowance
        assertEq(
            balance,
            1e6,
            " RANDOM_APPROVER should have a balance of 1e17"
        );

        vm.stopPrank();
    }
}
