// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ChatterPayNFT} from "../../src/ChatterPayNFT.sol";

error ChatterPayNFT__InvalidURICharacter();
error ChatterPayNFT__OriginalTokenNotMinted(uint256);
error ChatterPayNFT__LimitExceedsCopies();
error ChatterPayNFT__Unauthorized();

contract NFTMintingModule is Test {
    ChatterPayNFT nft;
    address minter = address(0x123);
    address recipient = address(0x456);

    function setUp() public {
        nft = new ChatterPayNFT();
        nft.initialize(minter, "");
    }

    function testMintOriginalValidURI() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://metadata/1");

        string memory uri = nft.tokenURI(1);
        assertEq(uri, "ipfs://metadata/1");
        assertEq(nft.ownerOf(1), recipient);
    }

    function testMintOriginalRejectsInvalidURI() public {
        vm.prank(minter);
        vm.expectRevert(ChatterPayNFT__InvalidURICharacter.selector);
        nft.mintOriginal(recipient, "ipfs://<bad>");
    }

    function testMintCopyValid() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://metadata/1");

        vm.prank(minter);
        nft.mintCopy(recipient, 1, "ipfs://metadata/1-copy");

        uint256 copyId = 1 * 10 ** 8 + 1;
        assertEq(nft.ownerOf(copyId), recipient);
        assertEq(nft.tokenURI(copyId), "ipfs://metadata/1-copy");
    }

    function testMintCopyFailsIfOriginalNotExists() public {
        vm.expectRevert(abi.encodeWithSelector(ChatterPayNFT__OriginalTokenNotMinted.selector, 42));
        nft.mintCopy(recipient, 42, "ipfs://metadata/42");
    }

    function testMintCopyFailsWhenLimitExceeded() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://original");

        vm.prank(minter);
        nft.setCopyLimit(1, 1);

        vm.prank(minter);
        nft.mintCopy(recipient, 1, "ipfs://copy1");

        vm.prank(minter);
        vm.expectRevert(ChatterPayNFT__LimitExceedsCopies.selector);
        nft.mintCopy(recipient, 1, "ipfs://copy2");
    }

    function testSetCopyLimitFailsIfNotMinter() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://original");

        vm.prank(address(0xBEEF));
        vm.expectRevert(ChatterPayNFT__Unauthorized.selector);
        nft.setCopyLimit(1, 9999);
    }

    function testSetCopyLimitFailsIfBelowCurrentCopies() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://original");

        vm.prank(minter);
        nft.mintCopy(recipient, 1, "ipfs://copy1");

        vm.prank(minter);
        vm.expectRevert(ChatterPayNFT__LimitExceedsCopies.selector);
        nft.setCopyLimit(1, 0);
    }
}
