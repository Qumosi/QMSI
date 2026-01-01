// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./OpenZeppelin/ReentrancyGuardTransient.sol";
import "./OpenZeppelin/Strings.sol";
import "./qlibs/deadman.sol";
import "./qlibs/zkp.sol";
import {ERC20Spendable} from "./QMSIToken.sol";

/**
 * @notice A non-fungible certificate that anybody can create by spending tokens
 */

contract QMSI_721 is SecureZKP, DeadmanSwitch, ReentrancyGuardTransient
{
    using TransientSlot for bytes32;
    // @notice Error handlers
    // error InsufficientBalance(uint256 available, uint256 required);
    error TokenDoesNotExist(string tokenURI);
    error SpendFailed(bool result);
    error InvalidPrice(uint256 price);
    error InvalidOption(uint256 option);
    error NotRootToken(uint256 tokenId);
    error InvalidQuantity(int32 quantity);

    // @notice Event for when NFT is sold
    event SoldNFT(address indexed seller, uint256 indexed tokenId, address indexed buyer);

    // @notice Event for when NFT is minted
    event MintedNFT(address indexed minter, uint256 indexed tokenId);

    // @notice Event for when minting currency is set
    event SetMintCurrency(ERC20Spendable indexed qmsi);
    
    // @notice Event for when mint price changes
    event SetMintPrice(uint256 indexed price);

    // @notice Event for when base URI is set
    event SetBaseURI(string indexed baseURI);

    // @notice Event for when NFT price changes
    event SetNFTPrice(address indexed seller, uint256 indexed tokenId, uint256 indexed price);

    // @notice Event for when NFT token commission changes
    event SetTokenCommission(address indexed minter, uint256 indexed tokenId, uint256 indexed percentage);

    // @notice Event for when NFT URI location changes
    event SetTokenURI(address indexed minter, uint256 indexed tokenId, string indexed tokenURI);

    // @notice Event for when token type changes
    event TransformToken(uint256 indexed tokenType, uint256 indexed tokenId, int32 indexed tokenQuantity);

    /// @notice The price to create new certificates
    uint256 _mintingPrice;

    /// @notice The currency to create new certificates
    ERC20Spendable _mintingCurrency;

    /// @dev The serial number of the next certificate to create
    uint256 public nextCertificateId = 1;

    mapping(uint256 => bytes32) certificateDataHashes;

    // ERC721 tokenURI standard
    mapping (uint256 => string) private _tokenURIs;

    // Mappings for token costs
    mapping (uint256 => uint256) public tokenPrice;

    // Mappings for commission
    mapping (uint256 => uint256) public tokenCommission;

    // Mappings for original token minter
    mapping (uint256 => address) public tokenMinter;

    mapping (uint256 => uint256) public tokenType;
    mapping (uint256 => uint256) public rootTokenId;
    mapping (uint256 => int32) public tokenQuantity;

    string private _name;
    string private _symbol;

    constructor() {
        _name = "Qumosi Market";
        _symbol = "QMSI";
    }


    /**
     * @notice Query the certificate hash for a token
     * @param tokenId Which certificate to query
     * @return The hash for the certificate
     */
    function hashForToken(uint256 tokenId) external view returns (bytes32) {
        return certificateDataHashes[tokenId];
    }

    /**
     * @notice The price to create certificates influenced by token circulation and max supply
     * @return The price to create certificates
     */
    function mintingPrice() external view returns (uint256) {
        uint256 _burnRate = _mintingCurrency.burnRate();
        return (_mintingPrice*_burnRate)/100;
    }

    /**
     * @notice The price to create certificates
     * @return The price to create certificates
     */
    function trueMintingPrice() external view returns (uint256) {
        return _mintingPrice;
    }

    /**
     * @notice The currency (ERC20) to create certificates
     * @return The currency (ERC20) to create certificates
     */
    function mintingCurrency() external view returns (ERC20Spendable) {
        return _mintingCurrency;
    }

    /**
     * @notice Set new price to create certificates
     * @param newMintingPrice The new price
     */
    function setMintingPrice(uint256 newMintingPrice) onlyOwner external {
        _mintingPrice = newMintingPrice;
        emit SetMintPrice(newMintingPrice);
    }

    /**
     * @notice Set new ERC20 currency to create certificates
     * @param newMintingCurrency The new currency
     */
    function setMintingCurrency(ERC20Spendable newMintingCurrency) onlyOwner external {
        _mintingCurrency = newMintingCurrency;
        emit SetMintCurrency(newMintingCurrency);
    }

    /**
     * @notice QMSI_721 Timeline ranking system by burning QMSI_20
     * Designed to deter spam and keep what's relevant
     * All users can help rank better content 
     */
    struct RankInfo {
        uint256 tokenId;
        uint256 amountBurned; // Total ERC20 burned
        uint256 lastUpdateTime; // Timestamp of last ranking update
    }
    
    mapping(uint256 => RankInfo) public timeBasedRanks; // For time-based ranking
    mapping(uint256 => RankInfo) public amountBasedRanks; // For amount-based ranking
    mapping(uint256 => uint256) public timeBasedAmount; // Tracks amount burned in the time window
    mapping(uint256 => uint256) public overallAmountBurned; // Tracks total burned per token ID

    uint256 public constant RANK_SIZE = 100; // Maximum rank size
    uint256 public constant TIME_WINDOW = 1 days; // Time window for time-based ranking

    /**
     * @notice this only works if the contract owns the token
     * @dev Users spend their own ERC20 tokens to rank a token ID.
     * @param tokenId The ID of the token being ranked
     * @param amount The amount of ERC20 tokens to burn
     */
    function _spendAndRank(uint256 tokenId, uint256 amount) internal {
        // Need to send tokens to this contract first

        // Burn the caller's tokens that were sent over
        // require(_mintingCurrency.spend(amount), "QMSI-ERC721: Spend failed");
        if(!(_mintingCurrency.spend(amount))){
            revert SpendFailed(true);
        }

        // Update time-based and amount-based rankings
        _updateTimeBasedRanking(tokenId, amount);
        _updateAmountBasedRanking(tokenId, amount);
    }

    // Internal function to update the time-based ranking
    function _updateTimeBasedRanking(uint256 tokenId, uint256 amount) internal {
        uint256 currentTime = block.timestamp;

        // Add to the token's time-based total without resetting the timer
        timeBasedAmount[tokenId] += amount;

        // If token is already ranked, update its amount
        for (uint256 i = 0; i < RANK_SIZE; i++) {
            if (timeBasedRanks[i].tokenId == tokenId) {
                timeBasedRanks[i].amountBurned = timeBasedAmount[tokenId];

                // Update the timestamp if 24 hours have passed
                if (timeBasedRanks[i].lastUpdateTime + TIME_WINDOW < currentTime) {
                    timeBasedRanks[i].lastUpdateTime = currentTime;
                }
                return;
            }
        }

        // If not already ranked, try to insert it
        for (uint256 i = 0; i < RANK_SIZE; i++) {
            if (
                timeBasedRanks[i].lastUpdateTime + TIME_WINDOW < currentTime || 
                timeBasedAmount[tokenId] > timeBasedRanks[i].amountBurned
            ) {
                _shiftDown(timeBasedRanks, i);
                timeBasedRanks[i] = RankInfo(tokenId, timeBasedAmount[tokenId], currentTime);
                return;
            }
        }
    }

    // Internal function to update the amount-based ranking
    function _updateAmountBasedRanking(uint256 tokenId, uint256 amount) internal {
        overallAmountBurned[tokenId] += amount;

        for (uint256 i = 0; i < RANK_SIZE; i++) {
            if (amountBasedRanks[i].tokenId == tokenId) {
                // If token is already ranked, update its amount
                amountBasedRanks[i].amountBurned = overallAmountBurned[tokenId];
                return;
            }
        }

        // If not already ranked, try to insert it
        for (uint256 i = 0; i < RANK_SIZE; i++) {
            if (overallAmountBurned[tokenId] > amountBasedRanks[i].amountBurned) {
                _shiftDown(amountBasedRanks, i);
                amountBasedRanks[i] = RankInfo(tokenId, overallAmountBurned[tokenId], block.timestamp);
                return;
            }
        }
    }

    // Helper function to shift ranking entries down from a given index
    function _shiftDown(mapping(uint256 => RankInfo) storage ranks, uint256 index) internal {
        for (uint256 i = RANK_SIZE - 1; i > index; i--) {
            ranks[i] = ranks[i - 1];
        }
    }
    
    // Base URI
    string private _baseURIextended;

    /**
    * @dev Function to check if address is contract address
    * @param _addr The address to check
    * @return A boolean that indicates if the operation was successful
    */
    function _isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly{
        size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @notice used by the contract owner to set a prefix string at the beginning of all token resource locations.
     * @param baseURI_ the string that goes at the beginning of all token URI
     *
     */
    function setBaseURI(string calldata baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
        emit SetBaseURI(baseURI_);
    }


    /**
     * @notice used for setting the certificate artifact remote location. only be called by setTokenURI.
     * @param tokenId the id of the certificate that we want to set the remote location of
     * @param _tokenURI a string that contains the URL of the artifact's location.
     *
     */
    function _setTokenURI(uint256 tokenId, string calldata _tokenURI) internal virtual {
        // require(bytes(_tokenURI).length > 0, "QMSI-ERC721: token URI cannot be empty");
        if(!(bytes(_tokenURI).length > 0)){
            revert TokenDoesNotExist(_tokenURI);
        }
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @notice for setting the commission rate of a certificate, called by setTokenCommissionProperty only.
     * @param tokenId the id of the certificate that we want to set the commission rate
     * @param percentage the percent token commission rate that is taken by the original minter
     *
     */
    function _setTokenCommissionProperty(uint256 tokenId, uint256 percentage) internal virtual{
        // require(percentage >= 0 && percentage <= 100, "QMSI-ERC721: Commission property must be a percent integer");
        if(!(percentage >= 0 && percentage <= 100)){
            revert InvalidRange(percentage);
        }
        tokenCommission[tokenId] = percentage;
    }

    /**
     * @notice for setting the commission rate of a certificate, optional. only original minter can call this.
     * @param tokenId the id of the certificate that we want to set the commission rate
     * @param percentage_ the percent token commission rate that is taken by the original minter
     *
     */
    function setTokenCommissionProperty(uint256 tokenId, uint256 percentage_) external{
        // require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        // require(msg.sender == _tokenMinter[tokenId], "QMSI-ERC721: Must be the original minter to set commission rate");
        if(msg.sender != tokenMinter[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(percentage_ >= 0 && percentage_ <= 100, "QMSI-ERC721: Commission property must be a percent integer");
        if(!(percentage_ >= 0 && percentage_ <= 100)){
            revert InvalidRange(percentage_);
        }
        _setTokenCommissionProperty(tokenId, percentage_);
        emit SetTokenCommission(msg.sender, tokenId, percentage_);

    }

    /**
     * @notice used for setting the original artist/minter of the certificate. called once per tokenId.
     * @param tokenId the id of the certificate that is being minted
     *
     */
    function _setTokenMinter(uint256 tokenId, address minter) internal virtual {
        // require(minter != address(0), "QMSI-ERC721: Invalid address");
        if(minter == address(0)){
            revert Unauthorized(address(0));
        }
        tokenMinter[tokenId] = minter;
    }

    /**
     * @notice used for setting the price of the token. can only be called from sellToken()
     * @param tokenId the id of the certificate that we want sell
     * @param _tokenPrice the amount in token currency units that we want to sell the certificate for
     *
     */
    function _setTokenPrice(uint256 tokenId, uint256 _tokenPrice) internal virtual {
        if(_tokenPrice > 0){
            tokenPrice[tokenId] = _tokenPrice;
        }
    }

    /**
     * @notice used for creating a listing for the certificate to be bought
     * @param tokenId the id of the certificate that we want sell
     * @param _tokenPrice the amount in token currency units that we want to sell the certificate for
     *
     */
    function sellToken(uint256 tokenId, uint256 _tokenPrice) external {
        // require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        // require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to sell");
        if(msg.sender != idToOwner[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(_tokenPrice > 0, "QMSI-ERC721: Must set a price to sell token for");
        if(!(_tokenPrice > 0)){
            revert InvalidPrice(_tokenPrice);
        }
        _setTokenPrice(tokenId, _tokenPrice);
        emit SetNFTPrice(msg.sender, tokenId, _tokenPrice);
    }

    /**
     * @notice used for removing a listing, if the certificate is up for sale
     * @param tokenId the id of the certificate that we want to remove listing of
     *
     */
    function removeListing(uint256 tokenId) external {
        // require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        // require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to remove listing");
        if(msg.sender != idToOwner[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(_tokenPrices[tokenId] > 0, "QMSI-ERC721: Must be selling in order to remove listing");
        if(!(tokenPrice[tokenId] > 0)){
            revert InvalidPrice(tokenPrice[tokenId]);
        }
        tokenPrice[tokenId] = 0;
        emit SetNFTPrice(msg.sender, tokenId, 0);
    }

    /**
     * @notice used for setting the certificate artifact remote location
     * @param tokenId the id of the certificate that we want to set the remote location of
     * @param _tokenURI a string that contains the URL of the artifact's location.
     *
     */
    function setTokenURI(uint256 tokenId, string calldata _tokenURI) external {
        // require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        // require(msg.sender == _tokenMinter[tokenId], "QMSI-ERC721: Must be the original minter to set URI");
        if(msg.sender != tokenMinter[tokenId]){
            revert Unauthorized(msg.sender);
        }
        _setTokenURI(tokenId, _tokenURI);
        emit SetTokenURI(msg.sender, tokenId, _tokenURI);
    }

    /**
     * @notice used for transforming token from non-fungible to fungible
     * @param tokenId the id of the certificate that we want to set the type of
     * @param quantity the number of tokens available, 0 for infinite
     *
     */
    function transformToken(uint256 tokenId, int32 quantity, uint256 ttype) external {
        _transformToken(tokenId, quantity, ttype);
    }
    function _transformToken(uint256 tokenId, int32 quantity, uint256 ttype) internal {
        // require(_tokenType[tokenId] == 1, "QMSI-ERC721: Token already split");
        if(tokenType[tokenId] != 1){
            revert InvalidOption(tokenType[tokenId]);
        }
        // require(msg.sender == _tokenMinter[tokenId], "QMSI-ERC721: Must be the original minter to set tokenType");
        if(msg.sender != tokenMinter[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to set tokenType");
        if(msg.sender != idToOwner[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(tokenId == _rootTokenId[tokenId], "QMSI-ERC721: Can only change type on root token");
        if(tokenId != rootTokenId[tokenId]){
            revert NotRootToken(tokenId);
        }
        // quantity = -1 means unlimited
        // quantity = 1 only one, NFT
        // quantity = 1+, fungible
        // require((quantity > 0 && quantity < 1000000) || quantity == -1, "QMSI-ERC721: Quantity must be zero to million"); // think of real max for overflows
        if(ttype == 2){
            // We are splitting the token
            if(!((quantity > 0 && quantity < 1000000) || quantity == -1)){
                revert InvalidQuantity(quantity);
            }
            tokenType[tokenId] = 2; // the token has been split
            tokenQuantity[tokenId] = quantity;
            emit TransformToken(2, tokenId, quantity);
        }else if(ttype == 3){
            // We are boosting the token
            tokenType[tokenId] = 3; // the token has been boosted
            tokenQuantity[tokenId] = -1;
            _transfer(address(this), tokenId);
            emit TransformToken(3, tokenId, -1);
        }else{
            revert InvalidOption(ttype);
        }

    }
    // To allow for setting the price safely otherwise someone can snatch the NFT before you can split it
    function safeBoostToken(uint256 tokenId, uint256 _tokenPrice) external {
        // require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        // require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to sell");
        if(msg.sender != idToOwner[tokenId]){
            revert Unauthorized(msg.sender);
        }
        // require(_tokenPrice > 0, "QMSI-ERC721: Must set a price to sell token for");
        if(!(_tokenPrice > 0)){
            revert InvalidPrice(_tokenPrice);
        }
        _setTokenPrice(tokenId, _tokenPrice);
        _transformToken(tokenId, 1, 3);
    }

    /**
     * @notice to be called by the buy function inside the ERC20 contract
     * @param from the address we are transferring the NFT from
     * @param tokenId the id of the NFT we are moving
     *
     */
    function buyToken(address from, uint256 tokenId) external nonReentrant returns (bool) {
        return _buyToken(from, tokenId);
    }
    function _buyToken(address from, uint256 tokenId) internal returns (bool) {
        // require(_isContract(msg.sender) == true, "QMSI-ERC721: Only contract addresses can use this function");
        if(_isContract(msg.sender) == false){
            revert Unauthorized(msg.sender);
        }
        // require(msg.sender == address(_mintingCurrency), "QMSI-ERC721: Only the set currency can buy NFT on behalf of the user");
        if(msg.sender != address(_mintingCurrency)){
            revert Unauthorized(msg.sender);
        }
        // require(_quantity[tokenId] > 0 || _quantity[tokenId] == -1, "QMSI-ERC721: Not enough tokens left");
        if(!(tokenQuantity[tokenId] > 0 || tokenQuantity[tokenId] == -1)){
            revert InvalidQuantity(tokenQuantity[tokenId]);
        }
        // require that a public key is not set otherwise can redeem later
        if(tokenPublicKey[tokenId] != address(0)){
            revert Unauthorized(msg.sender);
        }
        if(tokenType[tokenId] == 1){
            _transfer(from, tokenId);
            tokenPrice[tokenId] = 0;
        }else if(tokenType[tokenId] == 3){
            if(idToOwner[tokenId] == address(this)) {
                // the idea is simple, send the multi token to this contract to own
                // once owned, you can "buy" as many, whomever and 
                // increment the rankings 

               // calculate the real price with comission applied and only burn the amount given to the owner, this contract
               uint256 tokenCommission_ = tokenCommission[tokenId];
               uint256 tokenPrice_ = tokenPrice[tokenId];

               uint256 amount = tokenPrice_;
               if(tokenCommission_ > 0){
                amount = (tokenPrice_ * (100 - tokenCommission_)) / 100;
               }

               _spendAndRank(tokenId, amount);
            }else{
                revert Unauthorized(idToOwner[tokenId]);
            }   
        }else if(tokenType[tokenId] == 2){
            if(tokenQuantity[tokenId] > 0){
                tokenQuantity[tokenId]--; // deduct from quantity
            }
            uint256 newToken = _create(certificateDataHashes[tokenId], _tokenURIs[tokenId], 0, tokenCommission[tokenId], tokenMinter[tokenId], rootTokenId[tokenId]);
            _transfer(from, newToken);
        }else{
            revert InvalidOption(tokenType[tokenId]);
        }
        // if token quantity is infinite lock the token to type 2, if it is limited prevent ability to upgrade
        // we need to store the original token id of the top most token
        emit SoldNFT(idToOwner[tokenId], tokenId, from);

        return true;
    }

    /**
     * @notice this string goes at the beginning of the tokenURI, if the contract owner chose to set a value for it.
     * @return a string of the base URI if there is one
     *
     */
    function baseURI() external view returns (string memory) {
        return _baseURIextended;
    }

    /**
     * @notice Purpose is to set the remote location of the JSON artifact
     * @param tokenId the id of the certificate
     * @return The remote location of the JSON artifact
     *
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        // require(bytes(_tokenURIs[tokenId]).length > 0, "ERC721Metadata: URI query for nonexistent token");
        if(!(bytes(_tokenURIs[tokenId]).length > 0)){
            revert TokenDoesNotExist(_tokenURIs[tokenId]);
        }
        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURIextended;

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, Strings.toString(tokenId)));
    }

    /**
     * @notice Allows anybody to create a certificate, takes payment from the
     *   msg.sender. Can only be called by the mintingCurrency contract
     * @param dataHash A representation of the certificate data using the Aria
     *   protocol (a 0xcert cenvention).
     * @param tokenURI_ The (optional) remote location of the certificate's JSON artifact, represented by the dataHash
     * @param tokenPrice_ The (optional) price of the certificate in token currency in order for someone to buy it and transfer ownership of it
     * @param commission_ The (optional) percentage that the original minter will take each time the certificate is bought
     * @return The new certificate ID
     *
     */
    function create(bytes32 dataHash, string calldata tokenURI_, uint256 tokenPrice_, uint256 commission_, address minter_) external returns (uint) {
        // require(_isContract(msg.sender) == true, "QMSI-ERC721: Only contract addresses can use this function");
        if(_isContract(msg.sender) == false){
            revert Unauthorized(msg.sender);
        }
        // require(msg.sender == address(_mintingCurrency), "QMSI-ERC721: Only the set currency can create NFT on behalf of the user");
        if(msg.sender != address(_mintingCurrency)){
            revert Unauthorized(msg.sender);
        }
        // All tokens start as NFTs and can be converted into FTs that can be minted over and over
        tokenType[nextCertificateId] = 1;
        tokenQuantity[nextCertificateId] = 1;

        // root most tokenid gets set here
        rootTokenId[nextCertificateId] = nextCertificateId;

        // Set URI of token
        _setTokenURI(nextCertificateId, tokenURI_);

        // Set price of token (optional)
        _setTokenPrice(nextCertificateId, tokenPrice_);

        // Set token minter (the original artist)
        _setTokenMinter(nextCertificateId, minter_);
        _setTokenCommissionProperty(nextCertificateId, commission_);

        // Create the certificate
        uint256 newCertificateId = nextCertificateId;
        _mint(minter_, newCertificateId);
        certificateDataHashes[newCertificateId] = dataHash;
        nextCertificateId = nextCertificateId + 1;
        // Emit that we minted an NFT
        emit MintedNFT(minter_, newCertificateId);

        return newCertificateId;
    }

    // Overloading for split tokens
    function _create(bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, address minter_, uint256 rootTokenId_) internal returns (uint) {
        // All tokens start as NFTs and can be converted into FTs that can be minted over and over
        tokenType[nextCertificateId] = 1;
        tokenQuantity[nextCertificateId] = 1;

        // Passed down from buyToken call
        rootTokenId[nextCertificateId] = rootTokenId_;

        // Set URI of token (here twice due to calldata vs memory
        if(!(bytes(tokenURI_).length > 0)){
            revert TokenDoesNotExist(tokenURI_);
        }
        _tokenURIs[nextCertificateId] = tokenURI_;

        // Set price of token (optional)
        _setTokenPrice(nextCertificateId, tokenPrice_);

        // Set token minter (the original artist)
        _setTokenMinter(nextCertificateId, minter_);
        _setTokenCommissionProperty(nextCertificateId, commission_);

        // Create the certificate
        uint256 newCertificateId = nextCertificateId;
        _mint(minter_, newCertificateId);
        certificateDataHashes[newCertificateId] = dataHash;
        nextCertificateId = nextCertificateId + 1;
        // Emit that we minted an NFT
        emit MintedNFT(minter_, newCertificateId);

        return newCertificateId;
    }
}
