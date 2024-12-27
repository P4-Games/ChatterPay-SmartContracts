// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

error ChatterPayNFT__Unauthorized();
error ChatterPayNFT__TokenAlreadyMinted(uint256);
error ChatterPayNFT__OriginalTokenNotMinted(uint256);
error ChatterPayNFT__LimitExceedsCopies();

/**
 * @title ChatterPayNFT
 * @notice This contract allows minting of original NFTs and their limited copies.
 * @dev Uses OpenZeppelin's UUPS upgradeable and ERC721 modules.
 */
contract ChatterPayNFT is
    UUPSUpgradeable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable
{
    uint256 private s_tokenId;
    mapping(uint256 tokenId => address minter) public s_originalMinter;
    mapping(uint256 tokenId => uint256 copies) public s_copyCount;
    mapping(uint256 tokenId => uint256 copyLimit) public s_copyLimit;
    string private s_baseURI;

    /**
     * @notice Initializes the contract with an initial owner and base URI.
     * @dev This function is called once during contract deployment.
     * @param initialOwner The address of the contract owner.
     * @param baseURI The base URI for the NFT metadata.
     */
    function initialize(
        address initialOwner,
        string memory baseURI
    ) public initializer {
        __ERC721_init("ChatterPayNFT", "CHTP");
        __Ownable_init(initialOwner);
        s_baseURI = baseURI;
    }

    /**
     * @notice Mints a new original NFT.
     * @dev The token ID is auto-incremented, and every 10th token ID is skipped.
     * @param to The address to receive the minted NFT.
     * @param uri The metadata URI for the NFT.
     * @custom:reverts ChatterPayNFT__TokenAlreadyMinted if the token ID is already minted.
     */
    function mintOriginal(address to, string memory uri) public {
        s_tokenId++;
        if (s_tokenId % 10 == 0) s_tokenId++;
        uint256 tokenId = s_tokenId;
        s_copyLimit[tokenId] = 1000; // default limit
        // The msg.sender (who pays for the gas) is the original minter
        s_originalMinter[tokenId] = msg.sender;
        // The NFT goes to the recipient
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    /**
     * @notice Mints a copy of an existing original NFT.
     * @dev Each copy has a unique token ID derived from the original token ID and copy count.
     * @param to The address to receive the copied NFT.
     * @param originalTokenId The token ID of the original NFT.
     * @param uri The metadata URI for the copied NFT.
     * @custom:reverts ChatterPayNFT__OriginalTokenNotMinted if the original token does not exist.
     * @custom:reverts ChatterPayNFT__LimitExceedsCopies if the copy limit for the original token is reached.
     */
    function mintCopy(
        address to,
        uint256 originalTokenId,
        string memory uri
    ) public {
        if (s_originalMinter[originalTokenId] == address(0))
            revert ChatterPayNFT__OriginalTokenNotMinted(originalTokenId);
        if (s_copyCount[originalTokenId] >= s_copyLimit[originalTokenId])
            revert ChatterPayNFT__LimitExceedsCopies();
        s_copyCount[originalTokenId]++;
        uint256 copyTokenId = originalTokenId *
            10 ** 8 +
            s_copyCount[originalTokenId];
        _mint(to, copyTokenId);
        _setTokenURI(copyTokenId, uri);
    }

    /**
     * @notice Updates the base URI for NFT metadata.
     * @dev Only callable by the contract owner.
     * @param _newBaseURI The new base URI.
     */
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        s_baseURI = _newBaseURI;
    }

    /**
     * @notice Updates the copy limit for an original NFT.
     * @dev Only the original minter of the NFT can update the copy limit.
     * @param tokenId The token ID of the original NFT.
     * @param newLimit The new copy limit.
     * @custom:reverts ChatterPayNFT__Unauthorized if the caller is not the original minter.
     * @custom:reverts ChatterPayNFT__LimitExceedsCopies if the new limit is less than the current copy count.
     */
    function setCopyLimit(uint256 tokenId, uint256 newLimit) public {
        if (msg.sender != s_originalMinter[tokenId])
            revert ChatterPayNFT__Unauthorized();
        if (newLimit < s_copyCount[tokenId])
            revert ChatterPayNFT__LimitExceedsCopies();
        s_copyLimit[tokenId] = newLimit;
    }

    /**
     * @notice Retrieves the base URI for NFT metadata.
     * @return The base URI as a string.
     */
    function _baseURI() internal view override returns (string memory) {
        return s_baseURI;
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @dev Only callable by the contract owner.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // The following functions are overrides required by Solidity.
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
