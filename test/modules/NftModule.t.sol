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

    /**
     * @notice Sets up the ChatterPayNFT instance for testing
     * @dev Deploys the contract and initializes it with a minter
     */
    function setUp() public {
        nft = new ChatterPayNFT();
        nft.initialize(minter, "");
    }

    /**
     * @notice Tests successful minting of an original NFT with a valid URI
     * @dev Ensures tokenURI and ownerOf return expected values
     */
    function testMintOriginalValidURI() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://metadata/1");

        string memory uri = nft.tokenURI(1);
        assertEq(uri, "ipfs://metadata/1");
        assertEq(nft.ownerOf(1), recipient);
    }

    /**
     * @notice Tests minting an original NFT with an invalid URI
     * @dev Expects revert with ChatterPayNFT__InvalidURICharacter
     */
    function testMintOriginalRejectsInvalidURI() public {
        vm.prank(minter);
        vm.expectRevert(ChatterPayNFT__InvalidURICharacter.selector);
        nft.mintOriginal(recipient, "ipfs://<bad>");
    }

    /**
     * @notice Tests successful minting of a valid copy NFT
     * @dev Ensures the copy NFT is minted with correct URI and ownership
     */
    function testMintCopyValid() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://metadata/1");

        vm.prank(minter);
        nft.mintCopy(recipient, 1, "ipfs://metadata/1-copy");

        uint256 copyId = 1 * 10 ** 8 + 1;
        assertEq(nft.ownerOf(copyId), recipient);
        assertEq(nft.tokenURI(copyId), "ipfs://metadata/1-copy");
    }

    /**
     * @notice Tests minting a copy when the original does not exist
     * @dev Expects revert with ChatterPayNFT__OriginalTokenNotMinted
     */
    function testMintCopyFailsIfOriginalNotExists() public {
        vm.expectRevert(abi.encodeWithSelector(ChatterPayNFT__OriginalTokenNotMinted.selector, 42));
        nft.mintCopy(recipient, 42, "ipfs://metadata/42");
    }

    /**
     * @notice Tests that copy minting fails if copy limit is exceeded
     * @dev Expects revert with ChatterPayNFT__LimitExceedsCopies
     */
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

    /**
     * @notice Tests that only the minter can set the copy limit
     * @dev Expects revert with ChatterPayNFT__Unauthorized
     */
    function testSetCopyLimitFailsIfNotMinter() public {
        vm.prank(minter);
        nft.mintOriginal(recipient, "ipfs://original");

        vm.prank(address(0xBEEF));
        vm.expectRevert(ChatterPayNFT__Unauthorized.selector);
        nft.setCopyLimit(1, 9999);
    }

    /**
     * @notice Tests that setting the copy limit below current copies fails
     * @dev Expects revert with ChatterPayNFT__LimitExceedsCopies
     */
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
