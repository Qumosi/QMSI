// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Nibbstack/nf-token.sol";

/**
 * @title SecureZKP
 * @notice A library for secure Zero-Knowledge Proof based NFT protection using cryptographic commitments
 * @dev Extends NFToken to access idToOwner mapping and _transfer function directly
 */
abstract contract SecureZKP is NFToken {
    
    // Mapping to store the commitment (hash of secret) for each token
    mapping(uint256 => address) public tokenPublicKey;
    
    // Event for when the public key (commitment) is set
    event PublicKeySet(uint256 indexed tokenId, address publicKey);
    
    // Event for when the public key is cleared  
    event PublicKeyCleared(uint256 indexed tokenId);
    
    // Custom errors for gas efficiency
    error InvalidCommitment();
    error InvalidProof();
    error ZKPUnauthorized(address caller);

    /**
     * @notice Sets the public key (commitment) for a specific token. Only the token owner can set it.
     * @param tokenId The ID of the NFT
     * @param _publicKey The commitment to set (should be keccak256(secret + tokenId))
     * @dev The commitment should be computed off-chain for security
     */
    function setPublicKey(uint256 tokenId, address _publicKey) external {
        // Using idToOwner directly from NFToken
        if(msg.sender != idToOwner[tokenId]){
            revert ZKPUnauthorized(msg.sender);
        }
        
        tokenPublicKey[tokenId] = _publicKey;
        emit PublicKeySet(tokenId, _publicKey);
    }

    /**
     * @notice Clears the public key for a specific token
     * @param tokenId The ID of the NFT
     */
    function clearPublicKey(uint256 tokenId) external {
        // Using idToOwner directly from NFToken
        if(msg.sender != idToOwner[tokenId]){
            revert ZKPUnauthorized(msg.sender);
        }
        
        tokenPublicKey[tokenId] = address(0);
        emit PublicKeyCleared(tokenId);
    }

    function _toChecksumString(address addr) internal pure returns (string memory) {
        bytes20 addrBytes = bytes20(addr);
        bytes memory hexChars = new bytes(40);

        // Convert address bytes to lowercase hex first
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(addrBytes[i]);
            hexChars[i * 2] = _nibbleToHexCharLower(b >> 4);
            hexChars[i * 2 + 1] = _nibbleToHexCharLower(b & 0x0f);
        }

        // Compute keccak256 of lowercase hex string
        bytes32 hash = keccak256(hexChars);

        // Apply checksum
        for (uint256 i = 0; i < 40; i++) {
            // If the ith nibble of the hash >= 8, uppercase the hex character
            uint8 hashNibble;
            if (i % 2 == 0) {
                hashNibble = uint8(hash[i / 2] >> 4);
            } else {
                hashNibble = uint8(hash[i / 2] & 0x0f);
            }

            if (hashNibble >= 8 && hexChars[i] >= 0x61) { // 'a' = 0x61
                hexChars[i] = bytes1(uint8(hexChars[i]) - 32); // convert to uppercase
            }
        }

        // Prepend "0x"
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";
        for (uint256 i = 0; i < 40; i++) {
            result[i + 2] = hexChars[i];
        }

        return string(result);
    }

    function _nibbleToHexCharLower(uint8 nibble) internal pure returns (bytes1) {
        if (nibble < 10) return bytes1(nibble + 48); // '0'..'9'
        else return bytes1(nibble + 87);             // 'a'..'f'
    }

    function getEthSignedMessageHash() public view returns (bytes32) {
        // Use lowercase hex string with "0x" prefix
        string memory addrStr = string(abi.encodePacked(_toChecksumString(msg.sender)));
        bytes32 messageHash = keccak256(bytes(addrStr));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }
    
     /**
     * @notice NFT Redeeming via ZKP signatures of a known pub key, sandwich/front-running proof
     * @param tokenId The ID of the NFT
     * @param signature The signature to check
     */
    function redeemNFT(uint256 tokenId, bytes memory signature) external {
        if (tokenPublicKey[tokenId] == address(0)) {
            revert InvalidCommitment();
        }

        string memory addrStr = _toChecksumString(msg.sender);
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked(addrStr)) 
            )
        );
        
        if (!verifySignature(messageHash, signature, tokenPublicKey[tokenId])) {
            revert InvalidProof();
        }

        _transfer(msg.sender, tokenId);
    }

     /**
     * @notice ZKP Verification for string/phrase secrets
     * @param messageHash ethSignedMessageHash (Solidity)
     * @param signature The signature to check
     * @param publicKey The public key that is already set
     * @return bool True if verification passes
     */
    function verifySignature(bytes32 messageHash, bytes memory signature, address publicKey) public pure returns (bool) {
        address signer = recover(messageHash, signature);
        return signer == publicKey;
    }

    function recover(bytes32 ethSignedMessageHash, bytes memory signature) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}